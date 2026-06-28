/**
 * Shinra | connectivity.uc | v1.0
 */

'use strict';

import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { ExecResult } from 'shinra.core.utils';
import { observe_runtime } from 'shinra.runtime';
import { api_available, clash_api_url } from 'shinra.clash';
import { selector_list } from 'shinra.control';

function trim(value) {
	value = replace("" + value, "\r", "");
	while (length(value) && substr(value, length(value) - 1, 1) == "\n")
		value = substr(value, 0, length(value) - 1);
	return value;
}

function command_result(trace_id, argv) {
	let result = ExecResult(trace_id, argv);
	return {
		code: result.code,
		stdout: trim(result.stdout),
		stderr: trim(result.stderr),
		ok: result.code == 0
	};
}

function contains(text, needle) {
	return index("" + text, "" + needle) >= 0;
}

function route_uses_tun(route, tun_name) {
	return route.ok && contains(route.stdout, "dev " + tun_name);
}

function route_uses_table(route, table_name) {
	return route.ok && contains(route.stdout, "table " + table_name);
}

function table_has_tun(route, tun_name) {
	return route.ok && contains(route.stdout, "dev " + tun_name);
}

function tun_link_is_up(link) {
	return link.ok && contains(link.stdout, "<") && contains(link.stdout, "UP");
}

function ip_rule_has_fwmark_redirect(rule) {
	return rule.ok && contains(rule.stdout, "fwmark") && contains(rule.stdout, "lookup 2022");
}

function ip_rule_has_table_2022(rule) {
	return rule.ok && contains(rule.stdout, "lookup 2022");
}

function first_selector_with_now(result) {
	if (!result.ok || type(result.data) != "object" || result.data == null)
		return "";
	if (type(result.data.selectors) != "array")
		return "";

	for (let selector in result.data.selectors) {
		if (type(selector) != "object" || selector == null)
			continue;
		if (type(selector.now) == "string" && selector.now != "")
			return selector.name + " -> " + selector.now;
	}

	return "";
}

function selector_summary(trace_id) {
	let result = selector_list(trace_id, {});
	if (!result.ok)
		return {
			available: false,
			count: 0,
			first_now: "",
			error: result.detail || result.message || result.code || ""
		};

	let selectors = [];
	if (type(result.data) == "object" && result.data != null && type(result.data.selectors) == "array")
		selectors = result.data.selectors;

	return {
		available: true,
		count: length(selectors),
		first_now: first_selector_with_now(result),
		error: ""
	};
}

function runtime_state(trace_id) {
	let observed = observe_runtime(trace_id);
	return json(observed.state);
}

function route_probe(trace_id, target) {
	return command_result(trace_id, [ "ip", "route", "get", target ]);
}

function first_failed_readiness(checks) {
	let order = [
		"runtime_running",
		"tun_present",
		"tun_up",
		"table_2022_has_tun",
		"ip_rule_has_table_2022",
		"ip_rule_has_fwmark_redirect",
		"clash_api_available",
		"selector_available",
		"selector_has_now"
	];

	for (let key in order) {
		if (!checks[key])
			return key;
	}

	return "";
}

function connectivity_probe(trace_id, req) {
	try {
		let state = runtime_state(trace_id);
		let tun_name = state.tun_name || "tun0";
		let probe_target = "1.1.1.1";

		if (type(req) == "object" && req != null && type(req.target) == "string" && req.target != "")
			probe_target = req.target;

		let ip_rule = command_result(trace_id, [ "ip", "rule" ]);
		let table_2022 = command_result(trace_id, [ "ip", "route", "show", "table", "2022" ]);
		let route_default_probe = route_probe(trace_id, "1.1.1.1");
		let route_target_probe = route_probe(trace_id, probe_target);
		let tun_link = command_result(trace_id, [ "ip", "link", "show", tun_name ]);
		let clash_ok = state.sing_box_running ? api_available(trace_id, clash_api_url("/proxies")) : false;
		let selectors = state.sing_box_running && clash_ok ? selector_summary(trace_id) : {
			available: false,
			count: 0,
			first_now: "",
			error: state.sing_box_running ? "api_unreachable" : "runtime_not_running"
		};
		let checks = {
			runtime_running: !!state.sing_box_running,
			tun_present: tun_link.ok,
			tun_up: tun_link_is_up(tun_link),
			table_2022_has_tun: table_has_tun(table_2022, tun_name),
			ip_rule_has_table_2022: ip_rule_has_table_2022(ip_rule),
			ip_rule_has_fwmark_redirect: ip_rule_has_fwmark_redirect(ip_rule),
			auto_redirect_mode: ip_rule_has_fwmark_redirect(ip_rule),
			route_default_uses_tun: route_uses_tun(route_default_probe, tun_name),
			route_default_uses_table_2022: route_uses_table(route_default_probe, "2022"),
			route_target_uses_tun: route_uses_tun(route_target_probe, tun_name),
			route_target_uses_table_2022: route_uses_table(route_target_probe, "2022"),
			clash_api_available: clash_ok,
			selector_available: selectors.available,
			selector_has_now: selectors.first_now != ""
		};
		let failed = first_failed_readiness(checks);

		return Success({
			runtime: state,
			probe_target: probe_target,
			readiness: {
				ready: failed == "",
				failed_check: failed,
				tun_name: tun_name
			},
			checks: checks,
			commands: {
				tun_link: tun_link,
				ip_rule: ip_rule,
				table_2022: table_2022,
				route_1_1_1_1: route_default_probe,
				route_target: route_target_probe
			},
			selectors: selectors
		}, 200, trace_id, "Connectivity probe observed");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_DIAGNOSTICS_FAILED, "Failed to run connectivity probe", trace_id, err);
	}
}

export { connectivity_probe };
