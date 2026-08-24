/**
 * Shinra | subscription_task.uc | v1.0
 */

'use strict';

import { mkdir, stat, unlink, rmdir, writefile } from 'fs';
import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { validate_refresh_strategy } from 'shinra.subscription_policy_schema';
import { task_path, read_task, patch_task, running_task, start_task, fail_task } from 'shinra.core.task';

const SUBSCRIPTION_REFRESH_TASK = "subscription.refresh";
const SUBSCRIPTION_REFRESH_TRACE = "shinra-runner-subscription-refresh";
const SUBSCRIPTION_REFRESH_LOCK = "subscription.refresh.lock";
let refresh_run_sequence = 0;

function subscription_refresh_task_meta() {
	return {
		task_type: SUBSCRIPTION_REFRESH_TASK,
		display_name: "订阅刷新任务",
		category: "background_task",
		status_path: task_path(SUBSCRIPTION_REFRESH_TASK)
	};
}

function subscription_refresh_task_enabled(trace_id) {
	return trace_id == SUBSCRIPTION_REFRESH_TRACE;
}

function progress_percent(done, total) {
	done = int(done || 0);
	total = int(total || 0);
	if (total <= 0)
		return 0;
	if (done >= total)
		return 100;
	return int((done * 100) / total);
}

function redacted_url(url) {
	if (type(url) != "string" || url == "")
		return "";

	let scheme = "";
	let rest = url;
	if (substr(url, 0, 8) == "https://") {
		scheme = "https://";
		rest = substr(url, 8);
	} else if (substr(url, 0, 7) == "http://") {
		scheme = "http://";
		rest = substr(url, 7);
	}

	let slash = index(rest, "/");
	let host = slash >= 0 ? substr(rest, 0, slash) : rest;
	if (host == "")
		return "";
	return scheme + host + "/...";
}

function task_run_id(task) {
	if (type(task) != "object" || task == null || type(task.meta) != "object" || task.meta == null)
		return "";
	return type(task.meta.run_id) == "string" ? task.meta.run_id : "";
}

function write_subscription_refresh_task(trace_id, run_id, patch) {
	try {
		if (!subscription_refresh_task_enabled(trace_id))
			return;
		if (run_id == "" || task_run_id(read_task(SUBSCRIPTION_REFRESH_TASK)) != run_id)
			return;
		if (patch.status == "running")
			running_task(SUBSCRIPTION_REFRESH_TASK, trace_id, patch);
		else
			patch_task(SUBSCRIPTION_REFRESH_TASK, patch);
	} catch (e) {
		/* Progress must never fail the actual refresh. */
	}
}

function path_exists(path) {
	let info = stat(path);
	return type(info) == "object" && info != null;
}

function refresh_lock_path() {
	return PATH.RUNNER_DIR + "/" + SUBSCRIPTION_REFRESH_LOCK;
}

function release_refresh_lock(path) {
	if (type(path) != "string" || path == "")
		return;
	unlink(path + "/run_id");
	rmdir(path);
}

function next_refresh_run_id() {
	refresh_run_sequence = refresh_run_sequence + 1;
	return "subscription-refresh-" + time() + "-" + refresh_run_sequence;
}

function source_arg(req, key) {
	if (type(req) == "object" && req != null && type(req[key]) == "string")
		return req[key];
	return "";
}

function subscription_refresh_runner_strategy(req) {
	if (type(req) != "object" || req == null || type(req.strategy) != "string" || req.strategy == "")
		return "";
	if (req.strategy == "saved")
		return "";
	validate_refresh_strategy(req.strategy);
	return req.strategy;
}

function notify_intent_arg(req) {
	if (type(req) == "object" && req != null && req.notify_intent == true)
		return " notify";
	return "";
}

function shell_safe_token(value, label) {
	value = "" + value;
	if (value == "")
		die("Missing " + label);

	for (let i = 0; i < length(value); i++) {
		let ch = substr(value, i, 1);
		let ok = (ch >= "A" && ch <= "Z") ||
			(ch >= "a" && ch <= "z") ||
			(ch >= "0" && ch <= "9") ||
			ch == "." || ch == "_" || ch == "-";
		if (!ok)
			die("Invalid " + label + ": " + value);
	}

	return value;
}

function subscriptions_refresh_status(trace_id, req) {
	try {
		let path = task_path(SUBSCRIPTION_REFRESH_TASK);
		let task = read_task(SUBSCRIPTION_REFRESH_TASK);
		let requested_run_id = source_arg(req, "run_id");
		return Success({
			path: path,
			exists: path_exists(path),
			task: task,
			requested_run_id: requested_run_id,
			matches_run: requested_run_id == "" || requested_run_id == task_run_id(task),
			task_meta: subscription_refresh_task_meta()
		}, 200, trace_id, "Subscription refresh task status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Failed to load Subscription refresh task status", trace_id, err);
	}
}

function start_refresh_task(trace_id, req, source_id) {
	let lock_path = "";
	try {
		if (!path_exists(PATH.RUN_DIR) && !mkdir(PATH.RUN_DIR, 0700))
			die("Failed to create Run directory: " + PATH.RUN_DIR);
		if (!path_exists(PATH.RUNNER_DIR) && !mkdir(PATH.RUNNER_DIR, 0700))
			die("Failed to create Runner directory: " + PATH.RUNNER_DIR);

		let strategy = subscription_refresh_runner_strategy(req);
		let path = task_path(SUBSCRIPTION_REFRESH_TASK);
		let task = read_task(SUBSCRIPTION_REFRESH_TASK);
		lock_path = refresh_lock_path();
		if (!mkdir(lock_path, 0700)) {
			return Success({
				path: path,
				task: task,
				task_meta: subscription_refresh_task_meta(),
				started: false,
				reason: "lock_present"
			}, 200, trace_id, "Subscription refresh task is already running");
		}

		let run_id = next_refresh_run_id();
		let scope = source_id == "" ? "all" : "source";
		let runner_target = scope == "all" ? "subscriptions_refresh" : "subscription_refresh_source";
		let strategy_arg = strategy != "" ? strategy : "-";
		let notify_arg = notify_intent_arg(req) != "" ? "notify" : "-";
		if (!writefile(lock_path + "/run_id", run_id + "\n")) {
			release_refresh_lock(lock_path);
			die("Failed to record Subscription refresh run id");
		}
		task = start_task(SUBSCRIPTION_REFRESH_TASK, SUBSCRIPTION_REFRESH_TRACE, "Subscription refresh queued", {
			meta: {
				run_id: run_id,
				scope: scope,
				target_source_id: source_id,
				refresh_strategy: strategy != "" ? strategy : "saved",
				source_results: []
			}
		});

		let command = "/usr/libexec/shinra-runner subscription.refresh " + runner_target + " " + SUBSCRIPTION_REFRESH_TRACE;
		if (scope == "source")
			command = command + " " + source_id;
		command = command + " " + run_id + " " + strategy_arg + " " + notify_arg;
		let code = system(command + " >/dev/null 2>&1 &");
		if (code != 0) {
			release_refresh_lock(lock_path);
			fail_task(SUBSCRIPTION_REFRESH_TASK, SUBSCRIPTION_REFRESH_TRACE, "Failed to start /usr/libexec/shinra-runner: " + code, {
				meta: { run_id: run_id }
			});
			die("Failed to start /usr/libexec/shinra-runner: " + code);
		}
		return Success({
			path: path,
			task: task,
			task_meta: subscription_refresh_task_meta(),
			started: true,
			run_id: run_id,
			scope: scope,
			source_id: source_id
		}, 202, trace_id, "Subscription refresh task started");
	} catch (e) {
		if (lock_path != "")
			release_refresh_lock(lock_path);
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Failed to start Subscription refresh task", trace_id, err);
	}
}

function subscriptions_refresh_start(trace_id, req) {
	return start_refresh_task(trace_id, req, "");
}

function subscription_refresh_source_start(trace_id, req) {
	try {
		let source_id = source_arg(req, "source_id");
		if (source_id == "")
			source_id = source_arg(req, "id");
		return start_refresh_task(trace_id, req, shell_safe_token(source_id, "source_id"));
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Failed to start Subscription source refresh task", trace_id, err);
	}
}

export {
	SUBSCRIPTION_REFRESH_TASK,
	SUBSCRIPTION_REFRESH_TRACE,
	subscription_refresh_task_enabled,
	progress_percent,
	redacted_url,
	write_subscription_refresh_task,
	path_exists,
	source_arg,
	subscription_refresh_runner_strategy,
	notify_intent_arg,
	shell_safe_token,
	subscriptions_refresh_status,
	subscriptions_refresh_start,
	subscription_refresh_source_start
};
