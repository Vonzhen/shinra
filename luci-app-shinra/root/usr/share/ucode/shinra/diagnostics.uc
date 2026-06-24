/**
 * Shinra | diagnostics.uc | v1.0
 */

'use strict';

import { PATH, BIN } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { read_optional_text, file_exists, ExecResult } from 'shinra.core.utils';
import { observe_runtime } from 'shinra.runtime';

function redact_line(line) {
	let value = "" + line;
	let lower = lc(value);

	if (index(lower, "password") >= 0 || index(lower, "private_key") >= 0 || index(lower, "token") >= 0 || index(lower, "uuid") >= 0)
		return "[redacted sensitive line]";

	return value;
}

function strip_ansi(text) {
	text = "" + text;
	let esc = sprintf("%c", 27);
	let output = "";

	for (let i = 0; i < length(text); i++) {
		let ch = substr(text, i, 1);
		if (ch != esc) {
			output = output + ch;
			continue;
		}

		i = i + 1;
		if (i >= length(text))
			break;

		if (substr(text, i, 1) != "[") {
			i = i - 1;
			continue;
		}

		for (; i < length(text); i++) {
			let code = substr(text, i, 1);
			if ((code >= "A" && code <= "Z") || (code >= "a" && code <= "z"))
				break;
		}
	}

	return output;
}

function push_log_lines(lines, text) {
	let current = "";

	for (let i = 0; i < length(text); i++) {
		let ch = substr(text, i, 1);
		if (ch == "\r")
			continue;
		if (ch == "\n") {
			if (current != "")
				push(lines, strip_ansi(redact_line(current)));
			current = "";
			continue;
		}
		current = current + ch;
	}

	if (current != "")
		push(lines, strip_ansi(redact_line(current)));
}

function recent_logs(trace_id) {
	let result = ExecResult(trace_id, [ "logread" ]);
	let lines = [];
	let all = [];

	push_log_lines(all, result.stdout);

	for (let line in all) {
		let lower = lc(line);
		if (index(lower, "shinra") < 0 && index(lower, "sing-box") < 0 && index(lower, "tun") < 0)
			continue;
		push(lines, line);
	}

	let start = length(lines) - 120;
	if (start < 0)
		start = 0;

	let sliced = [];
	for (let i = start; i < length(lines); i++)
		push(sliced, lines[i]);

	return sliced;
}

function file_status(path) {
	return {
		path: path,
		exists: file_exists(path)
	};
}

function service_status(trace_id) {
	let result = ExecResult(trace_id, [ BIN.INIT, "status" ]);
	return {
		code: result.code,
		stdout: result.stdout,
		stderr: result.stderr
	};
}

function logs_get(trace_id, req) {
	try {
		return Success({
			lines: recent_logs(trace_id)
		}, 200, trace_id, "Logs loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_LOG_READ_FAILED, "Failed to read logs", trace_id, err);
	}
}

function last_error_get(trace_id, req) {
	try {
		return Success({
			path: PATH.LAST_ERROR,
			content: read_optional_text(PATH.LAST_ERROR)
		}, 200, trace_id, "Last error loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_LOG_READ_FAILED, "Failed to read last error", trace_id, err);
	}
}

function diagnostics_get(trace_id, req) {
	try {
		let observed = observe_runtime(trace_id);

		return Success({
			service: service_status(trace_id),
			runtime: json(observed.state),
			files: {
				profile: file_status(PATH.PROFILE),
				subscriptions: file_status(PATH.SUBSCRIPTIONS),
				node_snapshot: file_status(PATH.NODE_SNAPSHOT),
				candidate: file_status(PATH.CANDIDATE_CONFIG),
				runtime_config: file_status(PATH.RUNTIME_CONFIG),
				runtime_backup: file_status(PATH.RUNTIME_CONFIG_BAK),
				runtime_state: file_status(PATH.RUNTIME_STATE),
				last_error: file_status(PATH.LAST_ERROR)
			}
		}, 200, trace_id, "Diagnostics loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_DIAGNOSTICS_FAILED, "Failed to load diagnostics", trace_id, err);
	}
}

export { logs_get, last_error_get, diagnostics_get };
