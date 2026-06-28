/**
 * Shinra | auto_task.uc | v1.0
 */

'use strict';

import { stat } from 'fs';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { PATH, AUTO_TASK } from 'shinra.core.constants';
import { read_optional_text, parse_json_object, ExecResult } from 'shinra.core.utils';

function empty_job(enabled) {
	return {
		enabled: enabled == true,
		scheduled_hour: "",
		due_now: false,
		decision: "",
		last_run_key: "",
		last_run_at: "",
		last_status: "",
		last_message: ""
	};
}

function string_field(obj, key) {
	if (type(obj) == "object" && obj != null && type(obj[key]) == "string")
		return obj[key];
	return "";
}

function bool_field(obj, key) {
	return type(obj) == "object" && obj != null && obj[key] == true;
}

function normalize_job(raw) {
	let job = empty_job(false);
	if (type(raw) != "object" || raw == null || type(raw) == "array")
		return job;

	job.enabled = bool_field(raw, "enabled");
	job.scheduled_hour = string_field(raw, "scheduled_hour");
	job.due_now = bool_field(raw, "due_now");
	job.decision = string_field(raw, "decision");
	job.last_run_key = string_field(raw, "last_run_key");
	job.last_run_at = string_field(raw, "last_run_at");
	job.last_status = string_field(raw, "last_status");
	job.last_message = string_field(raw, "last_message");
	return job;
}

function normalize_state(raw) {
	let jobs = type(raw.jobs) == "object" && raw.jobs != null && type(raw.jobs) != "array" ? raw.jobs : {};

	return {
		schema_version: 1,
		last_checked_at: string_field(raw, "last_checked_at"),
		current_hour: string_field(raw, "current_hour"),
		run_key: string_field(raw, "run_key"),
		jobs: {
			subscriptions_refresh_auto: normalize_job(jobs.subscriptions_refresh_auto),
			ruleset_download_required_auto: normalize_job(jobs.ruleset_download_required_auto)
		}
	};
}

function empty_state() {
	return normalize_state({
		last_checked_at: "",
		jobs: {
			subscriptions_refresh_auto: empty_job(false),
			ruleset_download_required_auto: empty_job(false)
		}
	});
}

function executable(info) {
	if (type(info) != "object" || info == null)
		return false;
	return (int(info.mode || 0) & 0111) != 0;
}

function cron_running(trace_id) {
	let result = ExecResult(trace_id + "-cron", [ "/etc/init.d/cron", "status" ]);
	return {
		running: result.code == 0,
		code: result.code,
		stdout: result.stdout || "",
		stderr: result.stderr || ""
	};
}

function scheduler_status(trace_id) {
	let script_info = stat(PATH.AUTO_TASK_SCRIPT);
	let cron_info = stat(PATH.CRON_ROOT);
	let cron_content = read_optional_text(PATH.CRON_ROOT);
	let cron = cron_running(trace_id);
	let script_exists = type(script_info) == "object" && script_info != null;
	let script_executable = executable(script_info);
	let cron_file_exists = type(cron_info) == "object" && cron_info != null;
	let cron_installed = index(cron_content, PATH.AUTO_TASK_SCRIPT) >= 0;

	return {
		script_path: PATH.AUTO_TASK_SCRIPT,
		script_exists: script_exists,
		script_executable: script_executable,
		cron_file: PATH.CRON_ROOT,
		cron_file_exists: cron_file_exists,
		cron_installed: cron_installed,
		cron_running: cron.running,
		cron_status_code: cron.code,
		cron_status_stdout: cron.stdout,
		cron_status_stderr: cron.stderr,
		cron_entry: AUTO_TASK.CRON_ENTRY,
		healthy: script_exists && script_executable && cron_installed && cron.running
	};
}

function auto_task_status_get(trace_id, req) {
	try {
		let content = read_optional_text(PATH.AUTO_TASK_STATE);
		let exists = length(content) > 0;
		let state = exists ? normalize_state(parse_json_object(content, "Auto Task State")) : empty_state();

		return Success({
			path: PATH.AUTO_TASK_STATE,
			exists: exists,
			state: state,
			scheduler: scheduler_status(trace_id)
		}, 200, trace_id, "Auto Task status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_INTERNAL, "Failed to load Auto Task status", trace_id, err);
	}
}

export { auto_task_status_get };
