/**
 * Shinra | ruleset_task.uc | v1.0
 */

'use strict';

import { mkdir, stat } from 'fs';
import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { file_exists } from 'shinra.core.utils';
import { task_path, read_task, patch_task, running_task } from 'shinra.core.task';

const RULESET_SYNC_TASK = "ruleset.sync";
const RULESET_SYNC_TRACE = "shinra-runner-ruleset-sync";
const RULESET_DOWNLOAD_ONE_TASK = "ruleset.download_one";
const RULESET_DOWNLOAD_ONE_TRACE = "shinra-runner-ruleset-download-one";

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

function write_ruleset_task_progress(trace_id, patch) {
	try {
		if (!ruleset_task_enabled(trace_id))
			return;
		if (patch.status == "running")
			running_task(RULESET_SYNC_TASK, trace_id, patch);
		else
			patch_task(RULESET_SYNC_TASK, patch);
	} catch (e) {
		/* Progress must never fail the actual sync. */
	}
}

function write_ruleset_download_one_task_progress(trace_id, patch) {
	try {
		if (!ruleset_download_one_task_enabled(trace_id))
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
		return Success({
			path: path,
			exists: file_exists(path),
			task: read_task(RULESET_SYNC_TASK)
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
		return Success({
			path: path,
			exists: file_exists(path),
			task: read_task(RULESET_DOWNLOAD_ONE_TASK)
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

function ruleset_download_one_start(trace_id, req) {
	try {
		let tag = safe_shell_arg(request_tag(req), "Rule Set tag");
		if (!file_exists(PATH.RUN_DIR) && !mkdir(PATH.RUN_DIR, 0700))
			die("Failed to create Run directory: " + PATH.RUN_DIR);
		if (!file_exists(PATH.RUNNER_DIR) && !mkdir(PATH.RUNNER_DIR, 0700))
			die("Failed to create Runner directory: " + PATH.RUNNER_DIR);

		let lock_info = stat(PATH.RUNNER_DIR + "/ruleset.download_one.lock");
		let path = task_path(RULESET_DOWNLOAD_ONE_TASK);
		let task = read_task(RULESET_DOWNLOAD_ONE_TASK);
		if (type(lock_info) == "object" && lock_info != null && (task.status == "running" || task.status == "starting")) {
			return Success({
				path: path,
				task: task,
				started: false,
				reason: "already_running"
			}, 200, trace_id, "Rule Set download task is already running");
		}

		let code = system("/usr/libexec/shinra-runner ruleset.download_one ruleset_download_one " + RULESET_DOWNLOAD_ONE_TRACE + " " + tag + " >/dev/null 2>&1 &");
		if (code != 0)
			die("Failed to start /usr/libexec/shinra-runner: " + code);

		task = read_task(RULESET_DOWNLOAD_ONE_TASK);
		task.status = "starting";
		task.message = "Rule Set download queued";
		task.trace_id = trace_id;
		task.current_item = tag;
		task.total_count = 1;
		task.meta.tag = tag;
		return Success({
			path: path,
			task: task,
			started: true
		}, 202, trace_id, "Rule Set download task started");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to start Rule Set download task", trace_id, err);
	}
}

function ruleset_download_required_start(trace_id, req) {
	try {
		if (!file_exists(PATH.RUN_DIR) && !mkdir(PATH.RUN_DIR, 0700))
			die("Failed to create Run directory: " + PATH.RUN_DIR);
		if (!file_exists(PATH.RUNNER_DIR) && !mkdir(PATH.RUNNER_DIR, 0700))
			die("Failed to create Runner directory: " + PATH.RUNNER_DIR);
		let lock_info = stat(PATH.RUNNER_DIR + "/ruleset.sync.lock");
		let path = task_path(RULESET_SYNC_TASK);
		let task = read_task(RULESET_SYNC_TASK);
		if (type(lock_info) == "object" && lock_info != null && (task.status == "running" || task.status == "starting")) {
			return Success({
				path: path,
				task: task,
				started: false,
				reason: "already_running"
			}, 200, trace_id, "Rule Set sync task is already running");
		}

		let notify = type(req) == "object" && req != null && req.notify_intent == true;
		let auto_apply = type(req) == "object" && req != null && req.auto_apply_intent == true;
		let runner_args = "";
		if (notify || auto_apply)
			runner_args = " - " + (notify ? "notify" : "-");
		if (auto_apply)
			runner_args = runner_args + " autoapply";
		let code = system("/usr/libexec/shinra-runner ruleset.sync ruleset_download_required " + RULESET_SYNC_TRACE + runner_args + " >/dev/null 2>&1 &");
		if (code != 0)
			die("Failed to start /usr/libexec/shinra-runner: " + code);

		task = read_task(RULESET_SYNC_TASK);
		task.status = "starting";
		task.message = "Rule Set sync queued";
		task.trace_id = trace_id;
		return Success({
			path: path,
			task: task,
			started: true
		}, 202, trace_id, "Rule Set sync task started");
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
