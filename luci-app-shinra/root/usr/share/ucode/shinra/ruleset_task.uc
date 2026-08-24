/**
 * Shinra | ruleset_task.uc | v1.0
 */

'use strict';

import { mkdir, unlink, rmdir, writefile } from 'fs';
import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { file_exists } from 'shinra.core.utils';
import { task_path, read_task, patch_task, running_task, start_task, fail_task } from 'shinra.core.task';

const RULESET_SYNC_TASK = "ruleset.sync";
const RULESET_SYNC_TRACE = "shinra-runner-ruleset-sync";
const RULESET_DOWNLOAD_ONE_TASK = "ruleset.download_one";
const RULESET_DOWNLOAD_ONE_TRACE = "shinra-runner-ruleset-download-one";
let ruleset_run_sequence = 0;

function ruleset_sync_task_meta() {
	return {
		task_type: RULESET_SYNC_TASK,
		display_name: "规则集同步任务",
		category: "background_task",
		status_path: task_path(RULESET_SYNC_TASK)
	};
}

function ruleset_download_one_task_meta() {
	return {
		task_type: RULESET_DOWNLOAD_ONE_TASK,
		display_name: "单个规则集下载任务",
		category: "background_task",
		status_path: task_path(RULESET_DOWNLOAD_ONE_TASK)
	};
}

function ruleset_task_enabled(trace_id) {
	return trace_id == RULESET_SYNC_TRACE;
}

function ruleset_download_one_task_enabled(trace_id) {
	return trace_id == RULESET_DOWNLOAD_ONE_TRACE;
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

function task_run_id(task) {
	if (type(task) != "object" || task == null || type(task.meta) != "object" || task.meta == null)
		return "";
	return type(task.meta.run_id) == "string" ? task.meta.run_id : "";
}

function task_run_writable(task_type, run_id) {
	let current_run_id = task_run_id(read_task(task_type));
	return run_id == "" ? current_run_id == "" : current_run_id == run_id;
}

function write_ruleset_task_progress(trace_id, run_id, patch) {
	try {
		if (!ruleset_task_enabled(trace_id))
			return;
		if (!task_run_writable(RULESET_SYNC_TASK, run_id))
			return;
		if (patch.status == "running")
			running_task(RULESET_SYNC_TASK, trace_id, patch);
		else
			patch_task(RULESET_SYNC_TASK, patch);
	} catch (e) {
		/* Progress must never fail the actual sync. */
	}
}

function write_ruleset_download_one_task_progress(trace_id, run_id, patch) {
	try {
		if (!ruleset_download_one_task_enabled(trace_id))
			return;
		if (!task_run_writable(RULESET_DOWNLOAD_ONE_TASK, run_id))
			return;
		if (patch.status == "running")
			running_task(RULESET_DOWNLOAD_ONE_TASK, trace_id, patch);
		else
			patch_task(RULESET_DOWNLOAD_ONE_TASK, patch);
	} catch (e) {
		/* Progress must never fail the actual download. */
	}
}

function ruleset_download_required_status(trace_id, req) {
	try {
		let path = task_path(RULESET_SYNC_TASK);
		let task = read_task(RULESET_SYNC_TASK);
		let run_id = type(req) == "object" && req != null && type(req.run_id) == "string" ? req.run_id : "";
		return Success({
			path: path,
			exists: file_exists(path),
			task: task,
			requested_run_id: run_id,
			matches_run: run_id == "" || run_id == task_run_id(task),
			task_meta: ruleset_sync_task_meta()
		}, 200, trace_id, "Rule Set sync task status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to load Rule Set sync task status", trace_id, err);
	}
}

function request_tag(req) {
	if (type(req) == "object" && req != null && type(req.tag) == "string" && req.tag != "")
		return req.tag;
	die("Missing Rule Set tag");
}

function ruleset_download_one_status(trace_id, req) {
	try {
		let path = task_path(RULESET_DOWNLOAD_ONE_TASK);
		let task = read_task(RULESET_DOWNLOAD_ONE_TASK);
		let run_id = type(req) == "object" && req != null && type(req.run_id) == "string" ? req.run_id : "";
		return Success({
			path: path,
			exists: file_exists(path),
			task: task,
			requested_run_id: run_id,
			matches_run: run_id == "" || run_id == task_run_id(task),
			task_meta: ruleset_download_one_task_meta()
		}, 200, trace_id, "Rule Set download task status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to load Rule Set download task status", trace_id, err);
	}
}

function safe_shell_arg(value, label) {
	value = "" + value;
	if (value == "")
		die(label + " must not be empty");
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

function release_runner_lock(path) {
	unlink(path + "/run_id");
	rmdir(path);
}

function next_run_id(task_type) {
	ruleset_run_sequence = ruleset_run_sequence + 1;
	return task_type + "-" + time() + "-" + ruleset_run_sequence;
}

function start_ruleset_task(trace_id, req, task_type, target, task_meta, runner_args) {
	let lock_path = "";
	try {
		if (!file_exists(PATH.RUN_DIR) && !mkdir(PATH.RUN_DIR, 0700))
			die("Failed to create Run directory: " + PATH.RUN_DIR);
		if (!file_exists(PATH.RUNNER_DIR) && !mkdir(PATH.RUNNER_DIR, 0700))
			die("Failed to create Runner directory: " + PATH.RUNNER_DIR);

		let path = task_path(task_type);
		let task = read_task(task_type);
		lock_path = PATH.RUNNER_DIR + "/" + task_type + ".lock";
		if (!mkdir(lock_path, 0700))
			return Success({ path: path, task: task, started: false, reason: "lock_present" }, 200, trace_id, "Rule Set task is already running");

		let run_id = next_run_id(task_type);
		if (!writefile(lock_path + "/run_id", run_id + "\n")) {
			release_runner_lock(lock_path);
			die("Failed to record Rule Set task run id");
		}
		task_meta.run_id = run_id;
		task = start_task(task_type, task_type == RULESET_SYNC_TASK ? RULESET_SYNC_TRACE : RULESET_DOWNLOAD_ONE_TRACE, "Rule Set task queued", { meta: task_meta });
		let command = "/usr/libexec/shinra-runner " + task_type + " " + target + " " + task.trace_id + " " + runner_args + " " + run_id;
		let code = system(command + " >/dev/null 2>&1 &");
		if (code != 0) {
			release_runner_lock(lock_path);
			fail_task(task_type, task.trace_id, "Failed to start /usr/libexec/shinra-runner: " + code, { meta: { run_id: run_id } });
			die("Failed to start /usr/libexec/shinra-runner: " + code);
		}
		return Success({ path: path, task: task, started: true, run_id: run_id }, 202, trace_id, "Rule Set task started");
	} catch (e) {
		if (lock_path != "")
			release_runner_lock(lock_path);
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to start Rule Set task", trace_id, "" + e);
	}
}

function ruleset_download_one_start(trace_id, req) {
	try {
		let tag = safe_shell_arg(request_tag(req), "Rule Set tag");
		let result = start_ruleset_task(trace_id, req, RULESET_DOWNLOAD_ONE_TASK, "ruleset_download_one", { tag: tag, scope: "one" }, tag + " - -");
		if (result.ok && result.data)
			result.data.task_meta = ruleset_download_one_task_meta();
		return result;
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to start Rule Set download task", trace_id, err);
	}
}

function ruleset_download_required_start(trace_id, req) {
	try {
		let notify = type(req) == "object" && req != null && req.notify_intent == true;
		let auto_apply = type(req) == "object" && req != null && req.auto_apply_intent == true;
		let result = start_ruleset_task(trace_id, req, RULESET_SYNC_TASK, "ruleset_download_required", { scope: "all" }, "- " + (notify ? "notify" : "-") + " " + (auto_apply ? "autoapply" : "-"));
		if (result.ok && result.data)
			result.data.task_meta = ruleset_sync_task_meta();
		return result;
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to start Rule Set sync task", trace_id, err);
	}
}

function ruleset_download_required_start_impl(trace_id, req) {
	return ruleset_download_required_start(trace_id, req);
}

function ruleset_download_required_status_impl(trace_id, req) {
	return ruleset_download_required_status(trace_id, req);
}

function ruleset_download_one_start_impl(trace_id, req) {
	return ruleset_download_one_start(trace_id, req);
}

function ruleset_download_one_status_impl(trace_id, req) {
	return ruleset_download_one_status(trace_id, req);
}

export {
	RULESET_SYNC_TASK,
	RULESET_SYNC_TRACE,
	RULESET_DOWNLOAD_ONE_TASK,
	RULESET_DOWNLOAD_ONE_TRACE,
	ruleset_task_enabled,
	ruleset_download_one_task_enabled,
	progress_percent,
	task_run_writable,
	write_ruleset_task_progress,
	write_ruleset_download_one_task_progress,
	ruleset_download_required_status,
	request_tag,
	ruleset_download_one_status,
	safe_shell_arg,
	ruleset_download_one_start,
	ruleset_download_required_start,
	ruleset_download_required_start_impl,
	ruleset_download_required_status_impl,
	ruleset_download_one_start_impl,
	ruleset_download_one_status_impl
};
