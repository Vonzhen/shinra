/**
 * Shinra | core/runtime_cleanup.uc | v1.0
 */

'use strict';

import { PATH } from 'shinra.core.constants';
import { read_optional_text, parse_json_object, file_exists, ExecResult } from 'shinra.core.utils';
import { runtime_ownership_observe } from 'shinra.core.runtime_ownership';

function trim_line(value) {
	value = replace("" + value, "\r", "");
	while (length(value) && substr(value, length(value) - 1, 1) == "\n")
		value = substr(value, 0, length(value) - 1);
	return value;
}

function contains(text, needle) {
	return index("" + text, "" + needle) >= 0;
}

function starts_with(text, prefix) {
	return substr("" + text, 0, length(prefix)) == prefix;
}

function tun_name_from_runtime_config() {
	if (!file_exists(PATH.RUNTIME_CONFIG))
		return "";

	let config = parse_json_object(read_optional_text(PATH.RUNTIME_CONFIG), "Runtime Config");
	if (type(config.inbounds) != "array")
		return "";

	for (let inbound in config.inbounds) {
		if (type(inbound) != "object" || inbound == null)
			continue;
		if (inbound.type != "tun")
			continue;
		if (type(inbound.interface_name) == "string" && inbound.interface_name != "")
			return inbound.interface_name;
		return "tun0";
	}

	return "";
}

function safe_tun_name(name) {
	name = "" + name;
	if (name == "" || name == "lo")
		return false;
	if (name == "br-lan" || name == "lan" || name == "wan")
		return false;
	if (name == "singtun0")
		return false;
	if (starts_with(name, "eth") || starts_with(name, "pppoe") || starts_with(name, "wlan"))
		return false;
	if (starts_with(name, "br-") || starts_with(name, "lan") || starts_with(name, "wan"))
		return false;
	return true;
}

function command_result(trace_id, argv) {
	let result = ExecResult(trace_id, argv);
	return {
		code: result.code,
		stdout: trim_line(result.stdout),
		stderr: trim_line(result.stderr),
		ok: result.code == 0
	};
}

function link_exists(trace_id, tun_name) {
	return command_result(trace_id, [ "ip", "link", "show", tun_name ]).ok;
}

function append_matching_lines(output, needle, lines) {
	let current = "";
	for (let i = 0; i < length(output); i++) {
		let ch = substr(output, i, 1);
		if (ch == "\r")
			continue;
		if (ch == "\n") {
			current = trim_line(current);
			if (current != "" && contains(current, needle))
				push(lines, current);
			current = "";
			continue;
		}
		current = current + ch;
	}

	current = trim_line(current);
	if (current != "" && contains(current, needle))
		push(lines, current);
}

function route_diagnostics(trace_id, tun_name) {
	let result = command_result(trace_id, [ "ip", "route", "show", "table", "all" ]);
	let lines = [];
	if (tun_name != "")
		append_matching_lines(result.stdout, "dev " + tun_name, lines);
	return {
		command: "ip route show table all",
		code: result.code,
		ok: result.ok,
		stale_shinra_routes: lines,
		stderr: result.stderr
	};
}

function rule_diagnostics(trace_id, tun_name) {
	let result = command_result(trace_id, [ "ip", "rule", "show" ]);
	let lines = [];
	if (tun_name != "")
		append_matching_lines(result.stdout, tun_name, lines);
	return {
		command: "ip rule show",
		code: result.code,
		ok: result.ok,
		stale_shinra_rules: lines,
		stderr: result.stderr
	};
}

function base_result(trace_id) {
	let tun_name = "";
	let config_error = "";

	try {
		tun_name = tun_name_from_runtime_config();
	} catch (e) {
		config_error = "" + e;
	}

	let routes = route_diagnostics(trace_id, tun_name);
	let rules = rule_diagnostics(trace_id, tun_name);

	return {
		supported: true,
		skipped: false,
		skip_reason: "",
		tun_name: tun_name,
		config_error: config_error,
		tun_safe: safe_tun_name(tun_name),
		tun_existed: tun_name != "" ? link_exists(trace_id, tun_name) : false,
		tun_delete_attempted: false,
		tun_deleted: false,
		tun_delete_code: 0,
		tun_delete_stdout: "",
		tun_delete_stderr: "",
		foreign_conflict: false,
		shinra_running: false,
		stale_shinra_routes: routes.stale_shinra_routes,
		stale_shinra_rules: rules.stale_shinra_rules,
		route_diagnostics: routes,
		rule_diagnostics: rules,
		actions: []
	};
}

function runtime_cleanup_observe(trace_id) {
	return base_result(trace_id);
}

function runtime_cleanup_shinra_owned(trace_id) {
	let result = base_result(trace_id);

	let ownership = null;
	try {
		ownership = runtime_ownership_observe(trace_id);
	} catch (e) {
		result.skipped = true;
		result.skip_reason = "ownership_check_failed: " + ("" + e);
		return result;
	}

	result.foreign_conflict = ownership.runtime_conflict == true;
	result.shinra_running = length(ownership.shinra_managed_processes) > 0;

	if (result.foreign_conflict) {
		result.skipped = true;
		result.skip_reason = "foreign_sing_box_running";
		return result;
	}

	if (result.shinra_running) {
		result.skipped = true;
		result.skip_reason = "shinra_sing_box_running";
		return result;
	}

	if (result.config_error != "") {
		result.skipped = true;
		result.skip_reason = "runtime_config_invalid";
		return result;
	}

	if (result.tun_name == "") {
		result.skipped = true;
		result.skip_reason = "tun_not_declared";
		return result;
	}

	if (!result.tun_safe) {
		result.skipped = true;
		result.skip_reason = "unsafe_tun_name";
		return result;
	}

	if (!result.tun_existed) {
		result.skipped = true;
		result.skip_reason = "tun_not_present";
		return result;
	}

	let deleted = command_result(trace_id, [ "ip", "link", "del", result.tun_name ]);
	result.tun_delete_attempted = true;
	result.tun_delete_code = deleted.code;
	result.tun_delete_stdout = deleted.stdout;
	result.tun_delete_stderr = deleted.stderr;
	push(result.actions, {
		action: "ip_link_del",
		target: result.tun_name,
		code: deleted.code,
		ok: deleted.ok
	});

	result.tun_deleted = deleted.ok && !link_exists(trace_id, result.tun_name);
	return result;
}

export { runtime_cleanup_observe, runtime_cleanup_shinra_owned };
