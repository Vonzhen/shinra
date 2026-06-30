/**
 * Shinra | core/scheduler.uc | v1.0
 */

'use strict';

import { mkdir, rmdir, stat } from 'fs';
import { PATH, AUTO_TASK } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { read_text, read_optional_text, write_text_atomic, parse_json_object, json_stringify, ExecResult } from 'shinra.core.utils';
import { normalize_subscriptions_policy } from 'shinra.subscription_policy';
import { subscriptions_refresh_start } from 'shinra.subscription';
import { ruleset_download_required_start } from 'shinra.ruleset';

const SCHEDULER_TYPE = "auto-resource";
const SUB_TASK = "subscription.refresh";
const RULE_TASK = "ruleset.sync";

function path_exists(path) {
	let info = stat(path);
	return type(info) == "object" && info != null;
}

function ensure_dir(path) {
	if (path_exists(path))
		return;
	if (!mkdir(path, 0700))
		die("Failed to create directory: " + path);
}

function ensure_scheduler_dir() {
	ensure_dir(PATH.RUN_DIR);
	ensure_dir(PATH.SCHEDULER_DIR);
}

function trim_line(value) {
	value = "" + value;
	value = replace(value, "\r", "");
	value = replace(value, "\n", "");
	return value;
}

function now_utc(trace_id) {
	let result = ExecResult(trace_id || "shinra-scheduler", [ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" ]);
	if (result.code != 0)
		return "";
	return trim_line(result.stdout);
}

function current_hour(trace_id) {
	let result = ExecResult(trace_id || "shinra-scheduler", [ "date", "+%H" ]);
	if (result.code != 0)
		return -1;
	return int(trim_line(result.stdout));
}

function current_run_key(trace_id) {
	let result = ExecResult(trace_id || "shinra-scheduler", [ "date", "+%Y-%m-%dT%H" ]);
	if (result.code != 0)
		return "";
	return trim_line(result.stdout);
}

function current_year(trace_id) {
	let result = ExecResult(trace_id || "shinra-scheduler", [ "date", "+%Y" ]);
	if (result.code != 0)
		return 0;
	return int(trim_line(result.stdout));
}

function boot_id() {
	return trim_line(read_optional_text("/proc/sys/kernel/random/boot_id"));
}

function bool_field(obj, key) {
	return type(obj) == "object" && obj != null && obj[key] == true;
}

function string_field(obj, key) {
	if (type(obj) == "object" && obj != null && type(obj[key]) == "string")
		return obj[key];
	return "";
}

function int_field(obj, key) {
	if (type(obj) == "object" && obj != null && obj[key] != null)
		return int(obj[key]);
	return 0;
}

function task_state(task_type, defaults) {
	defaults = defaults || {};
	return {
		enabled: bool_field(defaults, "enabled"),
		scheduled_hour: int_field(defaults, "scheduled_hour"),
		due_now: bool_field(defaults, "due_now"),
		decision: string_field(defaults, "decision"),
		last_run_key: string_field(defaults, "last_run_key"),
		last_run_at: string_field(defaults, "last_run_at"),
		last_trigger_result: string_field(defaults, "last_trigger_result"),
		last_error: string_field(defaults, "last_error"),
		strategy: string_field(defaults, "strategy"),
		notify_intent: bool_field(defaults, "notify_intent")
	};
}

function empty_state() {
	return {
		schema_version: 1,
		scheduler_type: SCHEDULER_TYPE,
		last_checked_at: "",
		current_hour: 0,
		run_key: "",
		boot_id: "",
		boot_checked: false,
		trace_id: "",
		triggered_tasks: [],
		skipped_tasks: [],
		tasks: {
			"subscription.refresh": task_state(SUB_TASK, { strategy: "saved" }),
			"ruleset.sync": task_state(RULE_TASK, {})
		}
	};
}

function normalize_state(raw) {
	let state = empty_state();
	if (type(raw) != "object" || raw == null || type(raw) == "array")
		return state;

	state.last_checked_at = string_field(raw, "last_checked_at");
	state.current_hour = int_field(raw, "current_hour");
	state.run_key = string_field(raw, "run_key");
	state.boot_id = string_field(raw, "boot_id");
	state.boot_checked = bool_field(raw, "boot_checked");
	state.trace_id = string_field(raw, "trace_id");
	state.triggered_tasks = type(raw.triggered_tasks) == "array" ? raw.triggered_tasks : [];
	state.skipped_tasks = type(raw.skipped_tasks) == "array" ? raw.skipped_tasks : [];

	let tasks = type(raw.tasks) == "object" && raw.tasks != null && type(raw.tasks) != "array" ? raw.tasks : {};
	state.tasks[SUB_TASK] = task_state(SUB_TASK, tasks[SUB_TASK]);
	state.tasks[RULE_TASK] = task_state(RULE_TASK, tasks[RULE_TASK]);
	return state;
}

function read_scheduler_state() {
	if (!path_exists(PATH.SCHEDULER_STATE))
		return empty_state();
	return normalize_state(parse_json_object(read_optional_text(PATH.SCHEDULER_STATE), "Scheduler State"));
}

function write_scheduler_state(state) {
	ensure_scheduler_dir();
	write_text_atomic(PATH.SCHEDULER_STATE, json_stringify(normalize_state(state)) + "\n");
	return normalize_state(state);
}

function load_policy() {
	return normalize_subscriptions_policy(parse_json_object(read_text(PATH.SUBSCRIPTIONS), "Subscriptions"));
}

function push_task(list, task_type, decision) {
	push(list, {
		task_type: task_type,
		decision: decision || ""
	});
}

function mark_skip(state, task_type, task, decision, error) {
	task.decision = decision || "skipped";
	task.due_now = false;
	task.last_trigger_result = decision || "skipped";
	task.last_error = error || "";
	push_task(state.skipped_tasks, task_type, task.decision);
}

function mark_trigger(state, task_type, task, now, run_key, result) {
	task.due_now = true;
	task.decision = result && result.data && result.data.started == false ? "already_running" : "triggered";
	task.last_run_key = run_key;
	task.last_run_at = now;
	task.last_trigger_result = task.decision;
	task.last_error = "";
	if (task.decision == "already_running")
		push_task(state.skipped_tasks, task_type, task.decision);
	else
		push_task(state.triggered_tasks, task_type, task.decision);
}

function trigger_subscription(trace_id, strategy) {
	if (strategy == "direct" || strategy == "proxy")
		return subscriptions_refresh_start(trace_id, { strategy: strategy, notify_intent: true });
	return subscriptions_refresh_start(trace_id, { notify_intent: true });
}

function trigger_ruleset(trace_id) {
	return ruleset_download_required_start(trace_id, { notify_intent: true });
}

function evaluate_hourly(state, task_type, task, enabled, scheduled_hour, now, run_key, time_ok, trigger_fn) {
	task.enabled = enabled == true;
	task.scheduled_hour = scheduled_hour;
	task.due_now = false;
	task.last_error = "";

	if (task.last_run_key == run_key && (task.last_trigger_result == "boot_triggered" || task.last_trigger_result == "boot_already_running"))
		return;

	if (!task.enabled) {
		mark_skip(state, task_type, task, "disabled", "");
		return;
	}

	if (!time_ok) {
		mark_skip(state, task_type, task, "time_unreliable", "");
		return;
	}

	if (scheduled_hour != state.current_hour) {
		task.decision = "waiting";
		task.last_trigger_result = "waiting";
		push_task(state.skipped_tasks, task_type, "waiting");
		return;
	}

	if (task.last_run_key == run_key) {
		mark_skip(state, task_type, task, "already_ran", "");
		return;
	}

	let result = trigger_fn();
	if (!result || result.ok != true) {
		mark_skip(state, task_type, task, "failed_to_start", result ? (result.detail || result.message || result.code || "") : "failed_to_start");
		return;
	}

	mark_trigger(state, task_type, task, now, run_key, result);
}

function evaluate_boot(state, task, policy, now, run_key, boot, trace_id) {
	if (policy.run_on_boot != true)
		return;
	if (boot == "") {
		task.decision = "boot_id_unavailable";
		task.last_trigger_result = "boot_id_unavailable";
		task.last_error = "boot_id_unavailable";
		push_task(state.skipped_tasks, SUB_TASK, "boot_id_unavailable");
		return;
	}
	if (state.boot_checked == true && state.boot_id == boot)
		return;

	let result = trigger_subscription(trace_id, policy.strategy);
	if (!result || result.ok != true) {
		task.decision = "boot_failed_to_start";
		task.last_trigger_result = "boot_failed_to_start";
		task.last_error = result ? (result.detail || result.message || result.code || "") : "failed_to_start";
		push_task(state.skipped_tasks, SUB_TASK, "boot_failed_to_start");
		return;
	}

	task.decision = result && result.data && result.data.started == false ? "boot_already_running" : "boot_triggered";
	task.last_run_key = run_key;
	task.last_run_at = now;
	task.last_trigger_result = task.decision;
	task.last_error = "";
	if (task.decision == "boot_already_running")
		push_task(state.skipped_tasks, SUB_TASK, task.decision);
	else
		push_task(state.triggered_tasks, SUB_TASK, task.decision);
	state.boot_checked = true;
	state.boot_id = boot;
}

function scheduler_health(trace_id) {
	let script_info = stat(PATH.AUTO_TASK_SCRIPT);
	let cron_info = stat(PATH.CRON_ROOT);
	let cron_content = read_optional_text(PATH.CRON_ROOT);
	let cron = ExecResult(trace_id + "-cron", [ "/etc/init.d/cron", "status" ]);
	let script_exists = type(script_info) == "object" && script_info != null;
	let script_executable = script_exists && (int(script_info.mode || 0) & 0111) != 0;
	let cron_file_exists = type(cron_info) == "object" && cron_info != null;
	let cron_installed = index(cron_content, PATH.AUTO_TASK_SCRIPT) >= 0;

	return {
		script_path: PATH.AUTO_TASK_SCRIPT,
		script_exists: script_exists,
		script_executable: script_executable,
		cron_file: PATH.CRON_ROOT,
		cron_file_exists: cron_file_exists,
		cron_installed: cron_installed,
		cron_running: cron.code == 0,
		cron_status_code: cron.code,
		cron_status_stdout: cron.stdout || "",
		cron_status_stderr: cron.stderr || "",
		cron_entry: AUTO_TASK.CRON_ENTRY,
		healthy: script_exists && script_executable && cron_installed && cron.code == 0
	};
}

function with_scheduler_lock(fn) {
	ensure_scheduler_dir();
	let lock = PATH.SCHEDULER_DIR + "/tick.lock";
	if (!mkdir(lock, 0700))
		return null;
	try {
		let result = fn();
		rmdir(lock);
		return result;
	} catch (e) {
		rmdir(lock);
		die("" + e);
	}
}

function scheduler_tick(trace_id, req) {
	try {
		let locked = with_scheduler_lock(function() {
			let policy = load_policy();
			let now = now_utc(trace_id);
			let run_key = current_run_key(trace_id);
			let year = current_year(trace_id);
			let time_ok = year >= 2024;
			let boot = boot_id();
			let state = read_scheduler_state();
			let previous_boot_id = state.boot_id;
			let previous_boot_checked = state.boot_checked;

			state.schema_version = 1;
			state.scheduler_type = SCHEDULER_TYPE;
			state.last_checked_at = now;
			state.current_hour = current_hour(trace_id);
			state.run_key = run_key;
			state.trace_id = trace_id;
			state.triggered_tasks = [];
			state.skipped_tasks = [];
			state.boot_id = boot;
			state.boot_checked = previous_boot_id == boot ? previous_boot_checked : false;

			let sub = state.tasks[SUB_TASK];
			let rules = state.tasks[RULE_TASK];
			sub.strategy = policy.subscription_update.strategy || "saved";
			sub.notify_intent = true;
			rules.notify_intent = true;

			time_ok = time_ok && state.current_hour >= 0 && state.current_hour <= 23 && run_key != "";

			evaluate_boot(state, sub, policy.subscription_update, now, run_key, boot, trace_id);
			evaluate_hourly(state, SUB_TASK, sub, policy.subscription_update.auto_update, policy.subscription_update.update_hour, now, run_key, time_ok, function() {
				return trigger_subscription(trace_id, policy.subscription_update.strategy);
			});
			evaluate_hourly(state, RULE_TASK, rules, policy.ruleset.auto_update, policy.ruleset.update_hour, now, run_key, time_ok, function() {
				return trigger_ruleset(trace_id);
			});

			return write_scheduler_state(state);
		});

		if (locked == null) {
			let state = read_scheduler_state();
			push_task(state.skipped_tasks, "scheduler", "already_running");
			state.trace_id = trace_id;
			state.last_checked_at = now_utc(trace_id);
			write_scheduler_state(state);
			return Success({ path: PATH.SCHEDULER_STATE, state: state }, 200, trace_id, "Scheduler already running");
		}

		return Success({ path: PATH.SCHEDULER_STATE, state: locked }, 200, trace_id, "Scheduler tick completed");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_INTERNAL, "Scheduler tick failed", trace_id, err);
	}
}

function scheduler_status(trace_id, req) {
	try {
		let state = read_scheduler_state();
		return Success({
			path: PATH.SCHEDULER_STATE,
			exists: path_exists(PATH.SCHEDULER_STATE),
			state: state,
			scheduler: scheduler_health(trace_id)
		}, 200, trace_id, "Scheduler status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_INTERNAL, "Failed to load Scheduler status", trace_id, err);
	}
}

export { scheduler_tick, scheduler_status };
