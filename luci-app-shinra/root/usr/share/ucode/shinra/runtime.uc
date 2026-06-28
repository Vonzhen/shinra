/**
 * Shinra | runtime.uc | v1.0
 */

'use strict';

import { PATH, BIN } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { read_optional_text, write_runtime_text_atomic, parse_json_object, json_escape, file_exists, ExecResult } from 'shinra.core.utils';
import { api_available, clash_api_url } from 'shinra.clash';

function trim_line(value) {
	value = replace("" + value, "\r", "");
	value = replace(value, "\n", "");
	return value;
}

function first_token(value) {
	value = "" + value;
	let token = "";

	for (let i = 0; i < length(value); i++) {
		let ch = substr(value, i, 1);
		if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n")
			break;
		token = token + ch;
	}

	return token;
}

function is_service_running(service_result) {
	if (service_result.code != 0)
		return false;

	let status = trim_line(service_result.stdout);
	return status == "running" || status == "active";
}

function now_utc(trace_id) {
	let result = ExecResult(trace_id, [ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" ]);
	if (result.code != 0)
		return "";
	return trim_line(result.stdout);
}

function runtime_hash(trace_id) {
	if (!file_exists(PATH.RUNTIME_CONFIG))
		return "";

	let result = ExecResult(trace_id, [ "sha256sum", PATH.RUNTIME_CONFIG ]);
	if (result.code != 0)
		return "";

	return first_token(result.stdout);
}

function service_status(trace_id) {
	return ExecResult(trace_id, [ BIN.INIT, "status" ]);
}

function tun_name_from_config() {
	if (!file_exists(PATH.RUNTIME_CONFIG))
		return "tun0";

	let config = parse_json_object(read_optional_text(PATH.RUNTIME_CONFIG), "Runtime Config");
	if (type(config.inbounds) != "array")
		return "tun0";

	for (let inbound in config.inbounds) {
		if (type(inbound) != "object" || inbound == null)
			continue;
		if (inbound.type != "tun")
			continue;
		if (type(inbound.interface_name) == "string" && inbound.interface_name != "")
			return inbound.interface_name;
		return "tun0";
	}

	return "tun0";
}

function tun_exists(trace_id, tun_name) {
	let result = ExecResult(trace_id, [ "ip", "link", "show", tun_name ]);
	return result.code == 0;
}

function clash_api_available(trace_id, running) {
	if (!running)
		return false;

	return api_available(trace_id, clash_api_url("/proxies"));
}

function runtime_state_json(trace_id, service_result) {
	let config_exists = file_exists(PATH.RUNTIME_CONFIG);
	let running = is_service_running(service_result);
	let last_apply_result = read_optional_text(PATH.LAST_APPLY_RESULT);
	let last_error = read_optional_text(PATH.LAST_ERROR);
	let tun_name = tun_name_from_config();

	if (!running && service_result.stderr != "")
		last_error = service_result.stderr;

	return "{" +
		"\"schema_version\":1," +
		"\"sing_box_running\":" + (running ? "true" : "false") + "," +
		"\"service_status_code\":" + service_result.code + "," +
		"\"service_status\":\"" + json_escape(service_result.stdout) + "\"," +
		"\"runtime_config_exists\":" + (config_exists ? "true" : "false") + "," +
		"\"runtime_config_path\":\"" + json_escape(PATH.RUNTIME_CONFIG) + "\"," +
		"\"runtime_config_hash\":\"" + json_escape(runtime_hash(trace_id)) + "\"," +
		"\"tun_exists\":" + (tun_exists(trace_id, tun_name) ? "true" : "false") + "," +
		"\"tun_name\":\"" + json_escape(tun_name) + "\"," +
		"\"clash_api_available\":" + (clash_api_available(trace_id, running) ? "true" : "false") + "," +
		"\"last_apply_result\":\"" + json_escape(last_apply_result) + "\"," +
		"\"recent_error\":\"" + json_escape(last_error) + "\"," +
		"\"checked_at\":\"" + json_escape(now_utc(trace_id)) + "\"" +
	"}";
}

function observe_runtime(trace_id) {
	let status = service_status(trace_id);
	let state = runtime_state_json(trace_id, status);
	write_runtime_text_atomic(PATH.RUNTIME_STATE, state);
	return {
		state: state,
		running: is_service_running(status),
		status_code: status.code
	};
}

function runtime_status(trace_id, req) {
	try {
		let observed = observe_runtime(trace_id);
		return Success({
			path: PATH.RUNTIME_STATE,
			state: json(observed.state)
		}, 200, trace_id, "Runtime status observed");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RUNTIME_STATUS_FAILED, "Failed to observe Runtime status", trace_id, err);
	}
}

function runtime_action(trace_id, action, success_message, error_code) {
	try {
		if ((action == "start" || action == "restart") && !file_exists(PATH.RUNTIME_CONFIG)) {
			observe_runtime(trace_id);
			return Fail(error_code, "Runtime config not found", trace_id, PATH.RUNTIME_CONFIG);
		}

		let result = ExecResult(trace_id, [ BIN.INIT, action ]);
		let observed = observe_runtime(trace_id);

		if (result.code != 0)
			return Fail(error_code, "Runtime " + action + " failed", trace_id, result.stderr || result.stdout);

		if ((action == "start" || action == "restart") && !observed.running)
			return Fail(error_code, "Runtime " + action + " did not create a running instance", trace_id, json(observed.state));

		return Success({
			action: action,
			state: json(observed.state)
		}, 200, trace_id, success_message);
	} catch (e) {
		let err = "" + e;
		return Fail(error_code, "Runtime " + action + " crashed", trace_id, err);
	}
}

function runtime_start(trace_id, req) {
	return runtime_action(trace_id, "start", "Runtime start requested", ERR.E_RUNTIME_START_FAILED);
}

function runtime_stop(trace_id, req) {
	return runtime_action(trace_id, "stop", "Runtime stop requested", ERR.E_RUNTIME_STOP_FAILED);
}

function runtime_restart(trace_id, req) {
	return runtime_action(trace_id, "restart", "Runtime restart requested", ERR.E_RUNTIME_RESTART_FAILED);
}

export { observe_runtime, runtime_status, runtime_start, runtime_stop, runtime_restart };
