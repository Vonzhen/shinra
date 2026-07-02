/**
 * Shinra | subscription_preflight.uc | v1.0
 */

'use strict';

import { BIN } from 'shinra.core.constants';
import { ExecResult } from 'shinra.core.utils';
import { validate_url } from 'shinra.subscription_config';

function trim_line(value) {
	value = replace("" + value, "\r", "");
	while (length(value) && substr(value, length(value) - 1, 1) == "\n")
		value = substr(value, 0, length(value) - 1);
	return value;
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

function contains(text, needle) {
	return index("" + text, "" + needle) >= 0;
}

function url_host(url) {
	let start = 0;
	let rest = "" + url;
	let slash = -1;
	let host = "";
	let colon = -1;

	if (substr(rest, 0, 7) == "http://")
		start = 7;
	else if (substr(rest, 0, 8) == "https://")
		start = 8;
	else
		return "";

	rest = substr(rest, start);
	slash = index(rest, "/");
	if (slash >= 0)
		host = substr(rest, 0, slash);
	else
		host = rest;

	colon = index(host, ":");
	if (colon >= 0)
		host = substr(host, 0, colon);

	return host;
}

function is_digit_text(value) {
	value = "" + value;
	if (value == "")
		return false;

	for (let i = 0; i < length(value); i++) {
		let ch = substr(value, i, 1);
		if (ch < "0" || ch > "9")
			return false;
	}

	return true;
}

function digit_value(ch) {
	if (ch == "0") return 0;
	if (ch == "1") return 1;
	if (ch == "2") return 2;
	if (ch == "3") return 3;
	if (ch == "4") return 4;
	if (ch == "5") return 5;
	if (ch == "6") return 6;
	if (ch == "7") return 7;
	if (ch == "8") return 8;
	if (ch == "9") return 9;
	return -1;
}

function parse_small_int(value) {
	value = "" + value;
	let number = 0;

	if (!is_digit_text(value))
		return -1;

	for (let i = 0; i < length(value); i++)
		number = number * 10 + digit_value(substr(value, i, 1));

	return number;
}

function ipv4_octets(host) {
	host = "" + host;
	let parts = [];
	let current = "";

	for (let i = 0; i < length(host); i++) {
		let ch = substr(host, i, 1);
		if (ch == ".") {
			push(parts, current);
			current = "";
			continue;
		}
		current = current + ch;
	}

	push(parts, current);

	for (let part in parts) {
		if (!is_digit_text(part))
			return null;
		let value = parse_small_int(part);
		if (value < 0 || value > 255)
			return null;
	}

	if (length(parts) != 4)
		return null;

	return parts;
}

function target_kind(host) {
	let parts = ipv4_octets(host);
	if (host == "localhost" || host == "127.0.0.1")
		return "localhost";
	if (parts == null)
		return "hostname";

	let a = parse_small_int(parts[0]);
	let b = parse_small_int(parts[1]);
	if (a == 10)
		return "lan_ipv4";
	if (a == 192 && b == 168)
		return "lan_ipv4";
	if (a == 172 && b >= 16 && b <= 31)
		return "lan_ipv4";
	if (a == 127)
		return "localhost";
	return "ipv4";
}

function service_running(trace_id) {
	let result = ExecResult(trace_id, [ BIN.INIT, "status" ]);
	let status = trim_line(result.stdout);
	return result.code == 0 && (status == "running" || status == "active");
}

function preflight_for_url(trace_id, url) {
	validate_url(url);
	let host = url_host(url);
	let kind = target_kind(host);
	let route = { code: -1, stdout: "", stderr: "", ok: false };
	let can_route = kind == "lan_ipv4" || kind == "ipv4" || kind == "localhost";
	let risk = "none";
	let recommendation = "";
	let running = service_running(trace_id);

	if (can_route && host != "")
		route = command_result(trace_id, [ "ip", "route", "get", host ]);

	let route_uses_tun = route.ok && contains(route.stdout, " dev tun");
	let route_uses_table_2022 = route.ok && contains(route.stdout, "table 2022");

	if (running && kind == "lan_ipv4" && (route_uses_tun || route_uses_table_2022)) {
		risk = "tun_captures_lan_substore";
		recommendation = "Generate and apply a Runtime config with TUN route_exclude_address for LAN/private ranges.";
	}

	return {
		url: url,
		target_host: host,
		target_kind: kind,
		runtime_running: running,
		route_stdout: route.stdout,
		route_stderr: route.stderr,
		route_ok: route.ok,
		route_uses_tun: route_uses_tun,
		route_uses_table_2022: route_uses_table_2022,
		risk: risk,
		recommendation: recommendation
	};
}

function preflight_detail(preflight) {
	return "preflight target_host=" + preflight.target_host +
		" target_kind=" + preflight.target_kind +
		" runtime_running=" + (preflight.runtime_running ? "true" : "false") +
		" route_uses_tun=" + (preflight.route_uses_tun ? "true" : "false") +
		" route_uses_table_2022=" + (preflight.route_uses_table_2022 ? "true" : "false") +
		" risk=" + preflight.risk +
		(preflight.recommendation != "" ? " recommendation=" + preflight.recommendation : "");
}

export { preflight_for_url, preflight_detail };
