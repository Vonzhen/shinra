/**
 * Shinra | core/utils.uc | v1.0
 */

'use strict';

import { readfile, writefile, rename, unlink, mkdir, stat } from 'fs';

function read_text(path) {
	let data = readfile(path);
	if (data == null)
		die("Failed to read " + path);
	return data;
}

function write_text_atomic(path, data) {
	let tmp = path + ".tmp";
	let ok = writefile(tmp, data);
	let failed = ok == null || ((type(ok) == "bool" || type(ok) == "boolean") && ok == false);
	if (failed)
		die("Failed to write " + tmp);
	if (!rename(tmp, path))
		die("Failed to rename " + tmp + " to " + path);
}

function parse_json_object(content, label) {
	let parsed = json(content);
	if (type(parsed) != "object" || parsed == null || type(parsed) == "array")
		die((label || "JSON") + " root must be a JSON object");
	return parsed;
}

function request_keys(req) {
	let keys = "";
	if (type(req) == "object" && req != null) {
		for (let key in req) {
			if (length(keys))
				keys = keys + ",";
			keys = keys + key;
		}
	}
	return keys;
}

function request_content(req) {
	if (type(req) == "string")
		return req;
	if (type(req) == "object" && req != null) {
		if (type(req.content) == "string")
			return req.content;
		if (type(req.params) == "object" && req.params != null && type(req.params.content) == "string")
			return req.params.content;
	}
	return "";
}

function shell_escape(arg) {
	let value = "" + arg;
	return "'" + replace(value, "'", "'\\''") + "'";
}

function json_escape(arg) {
	let value = "" + arg;
	value = replace(value, "\\", "\\\\");
	value = replace(value, "\"", "\\\"");
	value = replace(value, "\r", "\\r");
	value = replace(value, "\n", "\\n");
	value = replace(value, "\t", "\\t");
	return value;
}

function json_stringify(value) {
	return sprintf("%J", value);
}

function ensure_run_dir() {
	let info = stat("/var/run/shinra");
	if (type(info) == "object" && info != null)
		return;

	let ok = mkdir("/var/run/shinra", 0700);
	if (!ok)
		die("Failed to create /var/run/shinra");
}

function ExecResult(trace_id, argv) {
	if (type(argv) != "array" || length(argv) == 0)
		die("ExecResult requires argv array; trace_id=" + trace_id);

	ensure_run_dir();

	let safe_trace = replace("" + trace_id, "/", "_");
	let out = "/var/run/shinra/exec-" + safe_trace + ".out";
	let err = "/var/run/shinra/exec-" + safe_trace + ".err";
	let cmd = "";

	for (let arg in argv) {
		if (length(cmd))
			cmd = cmd + " ";
		cmd = cmd + shell_escape(arg);
	}

	cmd = cmd + " > " + shell_escape(out) + " 2> " + shell_escape(err);

	let code = system(cmd);
	let stdout = readfile(out) || "";
	let stderr = readfile(err) || "";
	unlink(out);
	unlink(err);

	return {
		code: code,
		stdout: stdout,
		stderr: stderr
	};
}

function ExecSafe(trace_id, argv) {
	let result = ExecResult(trace_id, argv);

	if (result.code != 0)
		die("Command failed(" + result.code + "): " + result.stderr);

	return result.stdout;
}

function file_exists(path) {
	let info = stat(path);
	return type(info) == "object" && info != null;
}

function ensure_runtime_dir() {
	ensure_run_dir();
}

function ensure_config_dir() {
	let info = stat("/etc/shinra/runtime");
	if (type(info) == "object" && info != null)
		return;

	let ok = mkdir("/etc/shinra/runtime", 0700);
	if (!ok)
		die("Failed to create /etc/shinra/runtime");
}

function write_runtime_text_atomic(path, data) {
	ensure_run_dir();
	write_text_atomic(path, data);
}

function read_optional_text(path) {
	let data = readfile(path);
	if (data == null)
		return "";
	return data;
}

export { read_text, read_optional_text, write_text_atomic, write_runtime_text_atomic, parse_json_object, request_keys, request_content, shell_escape, json_escape, json_stringify, file_exists, ensure_runtime_dir, ensure_config_dir, ExecResult, ExecSafe };
