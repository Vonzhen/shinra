/**
 * Shinra | core/task_lock.uc | v1.0
 *
 * Read and recover runner locks only after the recorded runner has gone away.
 */

'use strict';

import { readfile, rmdir, stat, unlink } from 'fs';
import { PATH } from 'shinra.core.constants';
import { ExecResult } from 'shinra.core.utils';
import { read_task, fail_task } from 'shinra.core.task';

const STALE_AFTER_SEC = 600;
const TASK_TYPES = {
	"subscription.refresh": true,
	"ruleset.sync": true,
	"ruleset.download_one": true
};

function valid_task_type(task_type) {
	task_type = "" + task_type;
	if (TASK_TYPES[task_type] != true)
		die("Unsupported background task: " + task_type);
	return task_type;
}

function task_lock_path(task_type) {
	return PATH.RUNNER_DIR + "/" + valid_task_type(task_type) + ".lock";
}

function task_done(status) {
	return status == "success" || status == "partial" || status == "failed" ||
		status == "failed_preserved" || status == "failed_no_snapshot";
}

function numeric_pid(value) {
	value = "" + value;
	if (value == "")
		return "";
	for (let i = 0; i < length(value); i++) {
		let ch = substr(value, i, 1);
		if (ch < "0" || ch > "9")
			return "";
	}
	return value;
}

function runner_pid(path) {
	let value = readfile(path + "/pid");
	if (value == null)
		return "";
	value = replace(value, "\r", "");
	value = replace(value, "\n", "");
	return numeric_pid(value);
}

function pid_alive(trace_id, pid) {
	if (pid == "")
		return false;
	return ExecResult(trace_id || "shinra-task-lock", [ "kill", "-0", pid ]).code == 0;
}

function task_run_id(task) {
	if (type(task) != "object" || task == null || type(task.meta) != "object" || task.meta == null)
		return "";
	return type(task.meta.run_id) == "string" ? task.meta.run_id : "";
}

function task_lock_status(trace_id, task_type) {
	task_type = valid_task_type(task_type);
	let path = task_lock_path(task_type);
	let info = stat(path);
	let exists = type(info) == "object" && info != null;
	let task = read_task(task_type);
	let pid = exists ? runner_pid(path) : "";
	let alive = exists && pid_alive(trace_id, pid);
	let active = !task_done(task.status);
	let updated_epoch = int(task.updated_at_epoch || 0);
	let age_sec = updated_epoch > 0 ? time() - updated_epoch : -1;
	let stale = exists && !alive && (task_done(task.status) || (active && age_sec >= STALE_AFTER_SEC));

	return {
		task_type: task_type,
		path: path,
		exists: exists,
		pid: pid,
		pid_alive: alive,
		task: task,
		run_id: task_run_id(task),
		age_sec: age_sec,
		stale_after_sec: STALE_AFTER_SEC,
		stale: stale,
		recoverable: stale,
		reason: !exists ? "not_locked" : (alive ? "runner_alive" : (task_done(task.status) ? "terminal_task_lock" : (age_sec >= STALE_AFTER_SEC ? "heartbeat_expired" : "heartbeat_recent")))
	};
}

function release_task_lock(path) {
	unlink(path + "/pid");
	unlink(path + "/run_id");
	unlink(path + "/owner.json");
	if (!rmdir(path))
		die("Failed to remove stale task lock: " + path);
}

function recover_task_lock(trace_id, task_type) {
	let status = task_lock_status(trace_id, task_type);
	if (!status.recoverable)
		die("Task lock is not recoverable: " + status.reason);

	release_task_lock(status.path);
	if (!task_done(status.task.status)) {
		fail_task(status.task_type, trace_id, "Recovered stale runner lock", {
			message: "Recovered stale background task lock",
			meta: { recovered_lock: true }
		});
	}
	return task_lock_status(trace_id, task_type);
}

function all_task_lock_status(trace_id) {
	let results = [];
	for (let task_type in TASK_TYPES)
		push(results, task_lock_status(trace_id, task_type));
	return results;
}

export { task_lock_status, all_task_lock_status, recover_task_lock };
