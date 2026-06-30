/**
 * Shinra | runtime.uc | v1.0
 */

'use strict';

import { PATH, BIN } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { read_optional_text, write_runtime_text_atomic, parse_json_object, json_escape, file_exists, ExecResult } from 'shinra.core.utils';
import { api_available, clash_api_url } from 'shinra.clash';
import { runtime_ownership_observe, runtime_ownership_guard } from 'shinra.core.runtime_ownership';
import { runtime_cleanup_observe, runtime_cleanup_shinra_owned } from 'shinra.core.runtime_cleanup';

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

function cleanup_observe_safe(trace_id) {
	try {
		return runtime_cleanup_observe(trace_id);
	} catch (e) {
		return {
			supported: true,
			error: "" + e,
			stale_shinra_routes: [],
			stale_shinra_rules: []
		};
	}
}

function runtime_state_json(trace_id, service_result, ownership) {
	let config_exists = file_exists(PATH.RUNTIME_CONFIG);
	let running = is_service_running(service_result);
	let last_apply_result = read_optional_text(PATH.LAST_APPLY_RESULT);
	let last_error = read_optional_text(PATH.LAST_ERROR);
	let tun_name = tun_name_from_config();
	let cleanup = cleanup_observe_safe(trace_id);
	let stale_routes = running ? [] : (cleanup.stale_shinra_routes || []);
	let stale_rules = running ? [] : (cleanup.stale_shinra_rules || []);

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
		"\"shinra_managed_processes\":" + sprintf("%J", ownership.shinra_managed_processes) + "," +
		"\"foreign_processes\":" + sprintf("%J", ownership.foreign_processes) + "," +
		"\"runtime_conflict\":" + (ownership.runtime_conflict ? "true" : "false") + "," +
		"\"recommendation\":\"" + json_escape(ownership.recommendation) + "\"," +
		"\"shinra_cleanup_supported\":true," +
		"\"stale_shinra_tun\":" + (cleanup.tun_existed == true && !running ? "true" : "false") + "," +
		"\"stale_shinra_routes\":" + sprintf("%J", stale_routes) + "," +
		"\"stale_shinra_rules\":" + sprintf("%J", stale_rules) + "," +
		"\"checked_at\":\"" + json_escape(now_utc(trace_id)) + "\"" +
	"}";
}

function observe_runtime(trace_id) {
	let status = service_status(trace_id);
	let ownership = runtime_ownership_observe(trace_id);
	let state = runtime_state_json(trace_id, status, ownership);
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

function wait_shinra_process_exit(trace_id) {
	let attempts = 0;
	let exited = false;
	let remaining = [];
	let error = "";

	for (let i = 0; i < 5; i++) {
		attempts = i + 1;
		try {
			let ownership = runtime_ownership_observe(trace_id);
			remaining = ownership.shinra_managed_processes;
			exited = length(remaining) == 0;
			if (exited)
				break;
		} catch (e) {
			error = "" + e;
			break;
		}
		if (i < 4)
			ExecResult(trace_id, [ "sleep", "1" ]);
	}

	return {
		exited: exited,
		attempts: attempts,
		remaining_processes: remaining,
		error: error
	};
}

function ownership_guard_or_fail(trace_id) {
	try {
		return runtime_ownership_guard(trace_id);
	} catch (ownership_error) {
		die("ownership_check_failed: " + ("" + ownership_error));
	}
}

function runtime_stop_sequence(trace_id) {
	let stop_result = ExecResult(trace_id, [ BIN.INIT, "stop" ]);
	let wait = wait_shinra_process_exit(trace_id);
	let cleanup = runtime_cleanup_shinra_owned(trace_id);
	let observed = observe_runtime(trace_id);

	return {
		stop_result: stop_result,
		wait: wait,
		cleanup: cleanup,
		observed: observed
	};
}

function runtime_start_sequence(trace_id) {
	let guard = ownership_guard_or_fail(trace_id);
	if (!guard.ok)
		return {
			foreign_conflict: true,
			guard: guard,
			start_result: null,
			observed: observe_runtime(trace_id)
		};

	let start_result = ExecResult(trace_id, [ BIN.INIT, "start" ]);
	let observed = observe_runtime(trace_id);
	return {
		foreign_conflict: false,
		guard: guard,
		start_result: start_result,
		observed: observed
	};
}

function runtime_observation_ready(observed) {
	let state = json(observed.state);
	return observed.running && state.tun_exists == true && state.clash_api_available == true;
}

function wait_runtime_ready(trace_id) {
	let observed = null;
	let ready = false;
	let attempts = 0;

	for (let i = 0; i < 8; i++) {
		observed = observe_runtime(trace_id);
		attempts = i + 1;
		ready = runtime_observation_ready(observed);
		if (ready)
			break;
		if (i < 7)
			ExecResult(trace_id, [ "sleep", "1" ]);
	}

	observed.health_ready = ready;
	observed.health_wait_attempts = attempts;
	return observed;
}

function runtime_restart_sequence(trace_id) {
	let stopped = runtime_stop_sequence(trace_id);
	let started = runtime_start_sequence(trace_id);

	return {
		stop_result: stopped.stop_result,
		wait: stopped.wait,
		cleanup: stopped.cleanup,
		foreign_conflict: started.foreign_conflict,
		guard: started.guard,
		start_result: started.start_result,
		observed: started.observed
	};
}

function runtime_restart_owned(trace_id) {
	let result = runtime_restart_sequence(trace_id);
	if (result.stop_result.code != 0)
		die(result.stop_result.stderr || result.stop_result.stdout);
	if (result.foreign_conflict)
		die("Foreign sing-box runtime detected: " + result.guard.detail);
	if (result.start_result == null || result.start_result.code != 0)
		die(result.start_result != null ? (result.start_result.stderr || result.start_result.stdout) : "Runtime start was not attempted");

	let observed = wait_runtime_ready(trace_id);
	if (!observed.running)
		die("Runtime restart did not create a running instance: " + observed.state);

	observed.cleanup = result.cleanup;
	observed.stop_wait = result.wait;
	return observed;
}

function runtime_action(trace_id, action, success_message, error_code) {
	try {
		if ((action == "start" || action == "restart") && !file_exists(PATH.RUNTIME_CONFIG)) {
			observe_runtime(trace_id);
			return Fail(error_code, "Runtime config not found", trace_id, PATH.RUNTIME_CONFIG);
		}

		if (action == "stop") {
			let stopped = runtime_stop_sequence(trace_id);
			if (stopped.stop_result.code != 0)
				return Fail(error_code, "Runtime stop failed", trace_id, stopped.stop_result.stderr || stopped.stop_result.stdout);

			return Success({
				action: action,
				state: json(stopped.observed.state),
				stop_wait: stopped.wait,
				cleanup: stopped.cleanup
			}, 200, trace_id, success_message);
		}

		if (action == "start") {
			let started = runtime_start_sequence(trace_id);
			if (started.foreign_conflict)
				return Fail(ERR.E_RUNTIME_FOREIGN_PROCESS, "Foreign sing-box runtime detected", trace_id, started.guard.detail);
			if (started.start_result.code != 0)
				return Fail(error_code, "Runtime start failed", trace_id, started.start_result.stderr || started.start_result.stdout);
			if (!started.observed.running)
				return Fail(error_code, "Runtime start did not create a running instance", trace_id, json(started.observed.state));

			return Success({
				action: action,
				state: json(started.observed.state)
			}, 200, trace_id, success_message);
		}

		if (action == "restart") {
			let restarted = runtime_restart_sequence(trace_id);
			if (restarted.stop_result.code != 0)
				return Fail(error_code, "Runtime stop failed before restart", trace_id, restarted.stop_result.stderr || restarted.stop_result.stdout);
			if (restarted.foreign_conflict)
				return Fail(ERR.E_RUNTIME_FOREIGN_PROCESS, "Foreign sing-box runtime detected", trace_id, restarted.guard.detail);
			if (restarted.start_result.code != 0)
				return Fail(error_code, "Runtime start failed during restart", trace_id, restarted.start_result.stderr || restarted.start_result.stdout);
			let observed = wait_runtime_ready(trace_id);
			if (!observed.running)
				return Fail(error_code, "Runtime restart did not create a running instance", trace_id, json(observed.state));

			return Success({
				action: action,
				state: json(observed.state),
				stop_wait: restarted.wait,
				cleanup: restarted.cleanup
			}, 200, trace_id, success_message);
		}

		return Fail(ERR.E_UNSUPPORTED, "Unsupported Runtime action", trace_id, action);
	} catch (e) {
		let err = "" + e;
		if (index(err, "ownership_check_failed: ") == 0)
			return Fail(ERR.E_RUNTIME_OWNERSHIP_CHECK_FAILED, "Failed to check Runtime ownership", trace_id, substr(err, length("ownership_check_failed: ")));
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

export { observe_runtime, runtime_status, runtime_start, runtime_stop, runtime_restart, runtime_restart_owned };
