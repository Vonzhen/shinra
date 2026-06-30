/**
 * Shinra | core/task.uc | v1.0
 */

'use strict';

import { mkdir, stat } from 'fs';
import { PATH } from 'shinra.core.constants';
import { read_optional_text, write_text_atomic, parse_json_object, json_stringify, file_exists, ExecResult } from 'shinra.core.utils';

function ensure_dir(path) {
	let info = stat(path);
	if (type(info) == "object" && info != null)
		return;

	if (!mkdir(path, 0700))
		die("Failed to create task directory: " + path);
}

function ensure_task_dir() {
	ensure_dir(PATH.RUN_DIR);
	ensure_dir(PATH.TASK_DIR);
}

function valid_task_type(task_type) {
	task_type = "" + task_type;
	if (task_type == "" || index(task_type, "/") >= 0 || index(task_type, "\\") >= 0)
		die("Invalid task type: " + task_type);
	return task_type;
}

function task_path(task_type) {
	task_type = valid_task_type(task_type);
	return PATH.TASK_DIR + "/" + task_type + ".json";
}

function trim_line(value) {
	value = "" + value;
	value = replace(value, "\r", "");
	value = replace(value, "\n", "");
	return value;
}

function now_utc(trace_id) {
	let result = ExecResult(trace_id || "shinra-task", [ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" ]);
	if (result.code != 0)
		return "";
	return trim_line(result.stdout);
}

function default_task(task_type) {
	task_type = valid_task_type(task_type);
	return {
		schema_version: 1,
		task_type: task_type,
		status: "idle",
		started_at: "",
		finished_at: "",
		progress: 0,
		current_item: "",
		total_count: 0,
		completed_count: 0,
		updated_count: 0,
		unchanged_count: 0,
		failed_count: 0,
		checked_count: 0,
		last_error: "",
		trace_id: "",
		message: "",
		meta: {}
	};
}

function int_field(obj, key) {
	if (type(obj) == "object" && obj != null && obj[key] != null)
		return int(obj[key]);
	return 0;
}

function string_field(obj, key) {
	if (type(obj) == "object" && obj != null && type(obj[key]) == "string")
		return obj[key];
	return "";
}

function normalize_task(task_type, raw) {
	let task = default_task(task_type);
	if (type(raw) != "object" || raw == null || type(raw) == "array")
		return task;

	task.schema_version = 1;
	task.task_type = task_type;
	task.status = string_field(raw, "status") || "idle";
	task.started_at = string_field(raw, "started_at");
	task.finished_at = string_field(raw, "finished_at");
	task.progress = int_field(raw, "progress");
	task.current_item = string_field(raw, "current_item");
	task.total_count = int_field(raw, "total_count");
	task.completed_count = int_field(raw, "completed_count");
	task.updated_count = int_field(raw, "updated_count");
	task.unchanged_count = int_field(raw, "unchanged_count");
	task.failed_count = int_field(raw, "failed_count");
	task.checked_count = int_field(raw, "checked_count");
	task.last_error = string_field(raw, "last_error");
	task.trace_id = string_field(raw, "trace_id");
	task.message = string_field(raw, "message");
	task.meta = type(raw.meta) == "object" && raw.meta != null && type(raw.meta) != "array" ? raw.meta : {};
	return task;
}

function read_task(task_type) {
	let path = task_path(task_type);
	if (!file_exists(path))
		return default_task(task_type);

	return normalize_task(task_type, parse_json_object(read_optional_text(path), "Task State"));
}

function write_task(task) {
	let task_type = valid_task_type(task.task_type);
	ensure_task_dir();
	write_text_atomic(task_path(task_type), json_stringify(normalize_task(task_type, task)) + "\n");
	return normalize_task(task_type, task);
}

function merge_patch(task, patch) {
	if (type(patch) != "object" || patch == null || type(patch) == "array")
		return task;

	for (let key in patch) {
		if (key == "meta" && type(patch.meta) == "object" && patch.meta != null && type(patch.meta) != "array") {
			if (type(task.meta) != "object" || task.meta == null || type(task.meta) == "array")
				task.meta = {};
			for (let meta_key in patch.meta)
				task.meta[meta_key] = patch.meta[meta_key];
			continue;
		}

		task[key] = patch[key];
	}

	return task;
}

function patch_task(task_type, patch) {
	let task = read_task(task_type);
	merge_patch(task, patch);
	return write_task(task);
}

function start_task(task_type, trace_id, message, patch) {
	let task = default_task(task_type);
	task.status = "starting";
	task.started_at = now_utc(trace_id);
	task.finished_at = "";
	task.progress = 0;
	task.trace_id = trace_id || "";
	task.message = message || "";
	merge_patch(task, patch);
	return write_task(task);
}

function running_task(task_type, trace_id, patch) {
	let task = read_task(task_type);
	task.status = "running";
	if (task.started_at == "")
		task.started_at = now_utc(trace_id);
	task.trace_id = trace_id || task.trace_id;
	merge_patch(task, patch);
	return write_task(task);
}

function finish_task(task_type, status, trace_id, patch) {
	let task = read_task(task_type);
	task.status = status || "success";
	task.finished_at = now_utc(trace_id);
	task.trace_id = trace_id || task.trace_id;
	merge_patch(task, patch);
	return write_task(task);
}

function fail_task(task_type, trace_id, error, patch) {
	let task = read_task(task_type);
	task.status = "failed";
	task.finished_at = now_utc(trace_id);
	task.trace_id = trace_id || task.trace_id;
	task.last_error = "" + (error || "");
	task.message = task.message || "Task failed";
	merge_patch(task, patch);
	return write_task(task);
}

export { task_path, default_task, read_task, write_task, patch_task, start_task, running_task, finish_task, fail_task };
