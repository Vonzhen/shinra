/**
 * Shinra | core/runner.uc | v1.0
 */

'use strict';

import { mkdir, stat } from 'fs';
import { PATH } from 'shinra.core.constants';
import { json_escape, json_stringify, read_optional_text, write_text_atomic, ExecResult } from 'shinra.core.utils';
import { start_task, running_task, fail_task } from 'shinra.core.task';
import { ruleset_download_required, ruleset_download_one } from 'shinra.ruleset';
import { subscriptions_refresh, subscription_refresh_source } from 'shinra.subscription';
import { notify_result_best_effort } from 'shinra.notify';

function ensure_dir(path) {
	let info = stat(path);
	if (type(info) == "object" && info != null)
		return;

	if (!mkdir(path, 0700))
		die("Failed to create runner directory: " + path);
}

function ensure_runner_dir() {
	ensure_dir(PATH.RUN_DIR);
	ensure_dir(PATH.RUNNER_DIR);
}

function trim_line(value) {
	value = "" + value;
	value = replace(value, "\r", "");
	value = replace(value, "\n", "");
	return value;
}

function now_utc(trace_id) {
	let result = ExecResult(trace_id || "shinra-runner", [ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" ]);
	if (result.code != 0)
		return "";
	return trim_line(result.stdout);
}

function runner_log_path(task_type) {
	return PATH.RUNNER_DIR + "/" + task_type + ".log";
}

function runner_log(task_type, trace_id, level, message) {
	ensure_runner_dir();
	let line = "{" +
		"\"ts\":\"" + json_escape(now_utc(trace_id)) + "\"," +
		"\"task_type\":\"" + json_escape(task_type) + "\"," +
		"\"trace_id\":\"" + json_escape(trace_id || "") + "\"," +
		"\"level\":\"" + json_escape(level || "info") + "\"," +
		"\"message\":\"" + json_escape(message || "") + "\"" +
	"}\n";
	let path = runner_log_path(task_type);
	write_text_atomic(path, read_optional_text(path) + line);
}

function allowed_target(task_type, target) {
	return (task_type == "ruleset.sync" && target == "ruleset_download_required") ||
		(task_type == "ruleset.download_one" && target == "ruleset_download_one") ||
		(task_type == "subscription.refresh" && target == "subscriptions_refresh") ||
		(task_type == "subscription.refresh" && target == "subscription_refresh_source");
}

function execute_target(task_type, target, trace_id, req) {
	if (!allowed_target(task_type, target))
		die("Runner target is not allowed: " + task_type + " " + target);

	if (task_type == "ruleset.sync" && target == "ruleset_download_required")
		return ruleset_download_required(trace_id, req || {});
	if (task_type == "ruleset.download_one" && target == "ruleset_download_one")
		return ruleset_download_one(trace_id, req || {});
	if (task_type == "subscription.refresh" && target == "subscriptions_refresh")
		return subscriptions_refresh(trace_id, req || {});
	if (task_type == "subscription.refresh" && target == "subscription_refresh_source")
		return subscription_refresh_source(trace_id, req || {});

	die("Runner target is not implemented: " + task_type + " " + target);
}

function notify_enabled(req) {
	return type(req) == "object" && req != null && req.notify_intent == true;
}

function notify_result(task_type, trace_id, result, req) {
	if (!notify_enabled(req))
		return;
	try {
		let notify = notify_result_best_effort(trace_id, task_type, result);
		runner_log(task_type, trace_id, "info", "notify_result=" + json_stringify(notify));
	} catch (e) {
		try {
			runner_log(task_type, trace_id, "error", "notify crashed: " + e);
		} catch (ignored) {
			let ignored_error = "" + ignored;
		}
	}
}

function runner_execute(task_type, target, trace_id, req) {
	trace_id = trace_id || "shinra-runner";
	try {
		if (!allowed_target(task_type, target))
			die("Runner target is not allowed: " + task_type + " " + target);

		ensure_runner_dir();
		start_task(task_type, trace_id, "Task starting", {
			meta: {
				runner_target: target
			}
		});
		runner_log(task_type, trace_id, "info", "runner starting");
		running_task(task_type, trace_id, {
			status: "running",
			message: "Task running",
			meta: {
				runner_target: target
			}
		});

		let result = execute_target(task_type, target, trace_id, req);
		runner_log(task_type, trace_id, result && result.ok == true ? "info" : "error", json_stringify(result));
		notify_result(task_type, trace_id, result, req);
		if (!result || result.ok != true) {
			let err = result ? (result.detail || result.message || result.code || "Task failed") : "Task failed";
			fail_task(task_type, trace_id, err, {
				message: result ? (result.message || "Task failed") : "Task failed"
			});
			return 1;
		}
		return 0;
	} catch (e) {
		let err = "" + e;
		try {
			runner_log(task_type, trace_id, "error", err);
			notify_result(task_type, trace_id, {
				ok: false,
				code: "E_INTERNAL",
				message: "Task crashed",
				detail: err,
				trace_id: trace_id
			}, req);
			fail_task(task_type, trace_id, err, {
				message: "Task crashed"
			});
		} catch (ignored) {
			let ignored_error = "" + ignored;
		}
		return 1;
	}
}

export { runner_execute, runner_log_path, runner_log };
