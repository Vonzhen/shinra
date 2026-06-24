/**
 * Shinra | subscription.uc | v1.0
 */

'use strict';

import { PATH, BIN } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { acquire, release } from 'shinra.core.lock';
import { read_text, write_text_atomic, parse_json_object, request_content, request_keys, json_escape, json_stringify, ExecResult, ExecSafe } from 'shinra.core.utils';
import { validate_refresh_strategy, normalize_subscriptions_policy } from 'shinra.subscription_policy';
import { send_telegram_best_effort } from 'shinra.notify';

function validate_url(url) {
	if (type(url) != "string" || url == "")
		die("Subscription URL must be a non-empty string");

	if (substr(url, 0, 7) != "http://" && substr(url, 0, 8) != "https://")
		die("Subscription URL must start with http:// or https://");
}

function validate_subscriptions_object(config) {
	normalize_subscriptions_policy(config);
}

function validate_subscriptions_content(content) {
	let config = parse_json_object(content, "Subscriptions");
	validate_subscriptions_object(config);
	return normalize_subscriptions_policy(config);
}

function refresh_strategy(config, req) {
	if (type(req) == "object" && req != null && type(req.strategy) == "string" && req.strategy != "") {
		validate_refresh_strategy(req.strategy);
		return req.strategy;
	}

	if (type(config.refresh_strategy) == "string" && config.refresh_strategy != "") {
		validate_refresh_strategy(config.refresh_strategy);
		return config.refresh_strategy;
	}

	return "direct";
}

function validate_outbounds(outbounds) {
	if (type(outbounds) != "array")
		die("Sub-Store output must be a sing-box outbounds JSON array");

	for (let outbound in outbounds) {
		if (type(outbound) != "object" || outbound == null || type(outbound) == "array")
			die("Sub-Store outbound must be an object");
		if (type(outbound.type) != "string" || outbound.type == "")
			die("Sub-Store outbound type must be a non-empty string");
		if (type(outbound.tag) != "string" || outbound.tag == "")
			die("Sub-Store outbound tag must be a non-empty string");
	}
}

function preserve_source_attribution(outbounds, source_name) {
	for (let outbound in outbounds)
		outbound.x_shinra_source = source_name;
	return outbounds;
}

function validate_node_snapshot_object(snapshot) {
	if (snapshot.schema_version != 1)
		die("Node Snapshot schema_version must be 1");
	if (snapshot.source != "sub-store")
		die("Node Snapshot source must be sub-store");
	if (type(snapshot.refresh_strategy) == "string")
		validate_refresh_strategy(snapshot.refresh_strategy);
	if (type(snapshot.sources) != "array")
		die("Node Snapshot sources must be an array");
	validate_outbounds(snapshot.outbounds);
}

function validate_node_snapshot_content(content) {
	let snapshot = parse_json_object(content, "Node Snapshot");
	validate_node_snapshot_object(snapshot);
	return snapshot;
}

function substore_outbounds(content) {
	let parsed = json(content);

	if (type(parsed) == "array")
		return parsed;

	if (type(parsed) == "object" && parsed != null && type(parsed.outbounds) == "array")
		return parsed.outbounds;

	die("Sub-Store output must be an outbounds array or an object with outbounds array");
}

function source_result_json(name, url, strategy, ok, node_count, error) {
	return "{" +
		"\"name\":\"" + json_escape(name) + "\"," +
		"\"url\":\"" + json_escape(url) + "\"," +
		"\"refresh_strategy\":\"" + json_escape(strategy) + "\"," +
		"\"ok\":" + (ok ? "true" : "false") + "," +
		"\"node_count\":" + node_count + "," +
		"\"error\":\"" + json_escape(error || "") + "\"" +
	"}";
}

function fetch_substore_output(trace_id, url, strategy) {
	if (strategy == "direct")
		return ExecSafe(trace_id, [ BIN.TIMEOUT, "15", "wget", "-q", "-T", "10", "-Y", "off", "-O", "-", url ]);

	return ExecSafe(trace_id, [ BIN.TIMEOUT, "15", "wget", "-q", "-T", "10", "-Y", "on", "-O", "-", url ]);
}

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
		recommendation = "Stop Runtime before direct refresh, use proxy refresh, or configure LAN bypass.";
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

function list_has(list, value) {
	for (let item in list) {
		if (item == value)
			return true;
	}
	return false;
}

function bypass_plan(fetch_bypass, preflight) {
	let reason = "allowed";
	let allowed = true;
	let would_add_rule = false;

	if (fetch_bypass.enabled != true) {
		allowed = false;
		reason = "disabled";
	} else if (fetch_bypass.mode != "temporary_rule") {
		allowed = false;
		reason = "unsupported_mode";
	} else if (preflight.target_kind != "lan_ipv4") {
		allowed = false;
		reason = "not_lan_ipv4";
	} else if (fetch_bypass.allow_lan != true) {
		allowed = false;
		reason = "allow_lan_false";
	} else if (!list_has(fetch_bypass.hosts, preflight.target_host)) {
		allowed = false;
		reason = "host_not_allowed";
	} else if (!preflight.route_uses_tun && !preflight.route_uses_table_2022) {
		allowed = false;
		reason = "route_not_captured";
	}

	if (allowed)
		would_add_rule = true;

	return {
		enabled: fetch_bypass.enabled == true,
		allowed: allowed,
		would_add_rule: would_add_rule,
		reason: reason,
		mode: fetch_bypass.mode,
		host: preflight.target_host,
		target_kind: preflight.target_kind,
		priority: fetch_bypass.priority,
		rule_argv: would_add_rule ? [ "ip", "rule", "add", "to", preflight.target_host, "lookup", "main", "priority", "" + fetch_bypass.priority ] : [],
		cleanup_argv: would_add_rule ? [ "ip", "rule", "del", "to", preflight.target_host, "lookup", "main", "priority", "" + fetch_bypass.priority ] : []
	};
}

function bypass_rule_command(action, plan) {
	if (action == "add")
		return [ "ip", "rule", "add", "to", plan.host, "lookup", "main", "priority", "" + plan.priority ];
	return [ "ip", "rule", "del", "to", plan.host, "lookup", "main", "priority", "" + plan.priority ];
}

function bypass_rule_result(trace_id, argv) {
	let result = ExecResult(trace_id, argv);
	return {
		code: result.code,
		stdout: trim_line(result.stdout),
		stderr: trim_line(result.stderr),
		ok: result.code == 0
	};
}

function bypass_cleanup(trace_id, plan) {
	let result = bypass_rule_result(trace_id, bypass_rule_command("del", plan));
	result.ok = result.ok || result.code == 2;
	return result;
}

function bypass_add(trace_id, plan) {
	return bypass_rule_result(trace_id, bypass_rule_command("add", plan));
}

function bypass_verify(trace_id, plan) {
	let route = command_result(trace_id, [ "ip", "route", "get", plan.host ]);
	route.route_uses_tun = route.ok && contains(route.stdout, " dev tun");
	route.route_uses_table_2022 = route.ok && contains(route.stdout, "table 2022");
	route.route_uses_main = route.ok && !route.route_uses_tun && !route.route_uses_table_2022;
	route.ok = route.ok && route.route_uses_main;
	return route;
}

function bypass_transaction_prepare(trace_id, plan) {
	let report = {
		enabled: plan.enabled,
		attempted: false,
		allowed: plan.allowed,
		host: plan.host,
		priority: plan.priority,
		stage: "not_started",
		cleanup_before: null,
		add: null,
		verify: null,
		cleanup_after: null
	};

	if (!plan.allowed) {
		report.stage = "denied";
		return report;
	}

	report.attempted = true;
	report.stage = "cleanup_before";
	report.cleanup_before = bypass_cleanup(trace_id, plan);
	if (!report.cleanup_before.ok)
		return report;

	report.stage = "add";
	report.add = bypass_add(trace_id, plan);
	if (!report.add.ok) {
		report.cleanup_after = bypass_cleanup(trace_id, plan);
		return report;
	}

	report.stage = "verify";
	report.verify = bypass_verify(trace_id, plan);
	if (!report.verify.ok) {
		report.cleanup_after = bypass_cleanup(trace_id, plan);
		return report;
	}

	report.stage = "ready";
	return report;
}

function bypass_transaction_cleanup(trace_id, plan, report) {
	if (report == null)
		report = {};
	report.cleanup_after = bypass_cleanup(trace_id, plan);
	if (report.cleanup_after.ok)
		report.stage = "cleaned";
	else
		report.stage = "cleanup_failed";
	return report;
}

function bypass_report_detail(report) {
	if (report == null)
		return "bypass_report=none";
	return "bypass_stage=" + (type(report.stage) == "string" ? report.stage : "") +
		" cleanup_before=" + (report.cleanup_before != null && report.cleanup_before.ok ? "ok" : "not_ok") +
		" add=" + (report.add != null && report.add.ok ? "ok" : "not_ok") +
		" verify=" + (report.verify != null && report.verify.ok ? "ok" : "not_ok") +
		" cleanup_after=" + (report.cleanup_after != null && report.cleanup_after.ok ? "ok" : "not_ok");
}

function fetch_substore_output_checked(trace_id, url, strategy) {
	let preflight = preflight_for_url(trace_id, url);
	let result = null;

	if (strategy == "direct")
		result = ExecResult(trace_id, [ BIN.TIMEOUT, "15", "wget", "-q", "-T", "10", "-Y", "off", "-O", "-", url ]);
	else
		result = ExecResult(trace_id, [ BIN.TIMEOUT, "15", "wget", "-q", "-T", "10", "-Y", "on", "-O", "-", url ]);

	if (result.code != 0)
		die("Command failed(" + result.code + "): " + result.stderr + "; " + preflight_detail(preflight));

	return result.stdout;
}

function fetch_substore_output_bypass_aware(trace_id, url, strategy, fetch_bypass) {
	let preflight = preflight_for_url(trace_id, url);
	let plan = bypass_plan(fetch_bypass, preflight);
	let bypass = {
		plan: plan,
		report: null,
		used: false
	};
	let result = null;

	if (strategy != "direct" || !plan.allowed) {
		return {
			content: fetch_substore_output_checked(trace_id, url, strategy),
			bypass: bypass
		};
	}

	bypass.used = true;
	bypass.report = bypass_transaction_prepare(trace_id, plan);
	if (bypass.report.stage != "ready") {
		bypass_transaction_cleanup(trace_id, plan, bypass.report);
		die("Subscription bypass prepare failed; " + bypass_report_detail(bypass.report));
	}

	result = ExecResult(trace_id, [ BIN.TIMEOUT, "15", "wget", "-q", "-T", "10", "-Y", "off", "-O", "-", url ]);
	bypass_transaction_cleanup(trace_id, plan, bypass.report);

	if (!bypass.report.cleanup_after.ok)
		die("Subscription bypass cleanup failed; " + bypass_report_detail(bypass.report));
	if (result.code != 0)
		die("Command failed(" + result.code + "): " + result.stderr + "; " + preflight_detail(preflight) + "; " + bypass_report_detail(bypass.report));

	return {
		content: result.stdout,
		bypass: bypass
	};
}

function source_arg(req, key) {
	if (type(req) == "object" && req != null && type(req[key]) == "string")
		return req[key];
	return "";
}

function node_preview(outbounds) {
	let nodes = [];
	let count = 0;

	for (let outbound in outbounds) {
		if (count >= 20)
			break;
		push(nodes, {
			tag: type(outbound.tag) == "string" ? outbound.tag : "",
			type: type(outbound.type) == "string" ? outbound.type : ""
		});
		count = count + 1;
	}

	return nodes;
}

function subscriptions_get(trace_id, req) {
	try {
		let content = read_text(PATH.SUBSCRIPTIONS);
		let config = validate_subscriptions_content(content);
		return Success({ path: PATH.SUBSCRIPTIONS, content: json_stringify(config) }, 200, trace_id, "Subscriptions loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_OUTPUT_INVALID, "Failed to load Subscriptions", trace_id, err);
	}
}

function subscriptions_save(trace_id, req) {
	let lock = null;
	try {
		let content = request_content(req);
		if (content == "")
			die("Missing Subscriptions content; request keys: " + request_keys(req));

		let config = validate_subscriptions_content(content);
		lock = acquire(trace_id);
		write_text_atomic(PATH.SUBSCRIPTIONS, json_stringify(config));
		release(lock);
		return Success({ path: PATH.SUBSCRIPTIONS }, 200, trace_id, "Subscriptions saved");
	} catch (e) {
		if (lock != null)
			release(lock);
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_SAVE_FAILED, "Failed to save Subscriptions", trace_id, err);
	}
}

function node_snapshot_get(trace_id, req) {
	try {
		let content = read_text(PATH.NODE_SNAPSHOT);
		validate_node_snapshot_content(content);
		return Success({ path: PATH.NODE_SNAPSHOT, content: content }, 200, trace_id, "Node Snapshot loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_NODE_SNAPSHOT_NOT_FOUND, "Failed to load Node Snapshot", trace_id, err);
	}
}

function node_snapshot_summary(trace_id, req) {
	try {
		let snapshot = validate_node_snapshot_content(read_text(PATH.NODE_SNAPSHOT));
		let sources = [];
		let nodes = [];

		for (let source in snapshot.sources) {
			push(sources, {
				name: type(source.name) == "string" ? source.name : "",
				ok: source.ok == true,
				node_count: type(source.node_count) == "int" ? source.node_count : 0,
				error: type(source.error) == "string" ? source.error : ""
			});
		}

		for (let outbound in snapshot.outbounds) {
			push(nodes, {
				tag: outbound.tag,
				type: outbound.type,
				source: type(outbound.x_shinra_source) == "string" ? outbound.x_shinra_source : ""
			});
		}

		return Success({
			path: PATH.NODE_SNAPSHOT,
			updated_at: type(snapshot.updated_at) == "string" ? snapshot.updated_at : "",
			source: snapshot.source,
			refresh_strategy: type(snapshot.refresh_strategy) == "string" ? snapshot.refresh_strategy : "direct",
			source_count: length(sources),
			node_count: length(nodes),
			sources: sources,
			nodes: nodes
		}, 200, trace_id, "Node Snapshot summary loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_NODE_SNAPSHOT_NOT_FOUND, "Failed to load Node Snapshot summary", trace_id, err);
	}
}

function subscription_test_source(trace_id, req) {
	try {
		let name = source_arg(req, "name");
		let url = source_arg(req, "url");
		let strategy = source_arg(req, "strategy");
		let config = validate_subscriptions_content(read_text(PATH.SUBSCRIPTIONS));

		validate_url(url);
		if (strategy == "")
			strategy = "direct";
		validate_refresh_strategy(strategy);

		let fetched = fetch_substore_output_bypass_aware(trace_id, url, strategy, config.fetch_bypass);
		let outbounds = substore_outbounds(fetched.content);
		validate_outbounds(outbounds);

		return Success({
			name: name,
			url: url,
			refresh_strategy: strategy,
			bypass: fetched.bypass,
			node_count: length(outbounds),
			nodes: node_preview(outbounds)
		}, 200, trace_id, "Subscription source test passed");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Subscription source test failed", trace_id, err);
	}
}

function subscription_fetch_preflight(trace_id, req) {
	try {
		let url = source_arg(req, "url");
		let config = validate_subscriptions_content(read_text(PATH.SUBSCRIPTIONS));
		let preflight = preflight_for_url(trace_id, url);
		preflight.bypass_plan = bypass_plan(config.fetch_bypass, preflight);
		return Success(preflight, 200, trace_id, "Subscription fetch preflight observed");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Subscription fetch preflight failed", trace_id, err);
	}
}

function subscriptions_refresh(trace_id, req) {
	let lock = null;
	try {
		let config = validate_subscriptions_content(read_text(PATH.SUBSCRIPTIONS));
		let strategy = refresh_strategy(config, req);
		lock = acquire(trace_id);

		let timestamp = ExecSafe(trace_id, [ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" ]);
		timestamp = replace(timestamp, "\n", "");
		timestamp = replace(timestamp, "\r", "");

		let sources_json = "";
		let outbounds_json = "";
		let total = 0;
		let bypass_used = 0;

		for (let source in config.sources) {
			if (source.enabled == false) {
				if (length(sources_json))
					sources_json = sources_json + ",";
				sources_json = sources_json + source_result_json(source.name, source.url, strategy, true, 0, "disabled");
				continue;
			}

			let fetched = fetch_substore_output_bypass_aware(trace_id, source.url, strategy, config.fetch_bypass);
			if (fetched.bypass.used)
				bypass_used = bypass_used + 1;
			let outbounds = substore_outbounds(fetched.content);
			validate_outbounds(outbounds);
			preserve_source_attribution(outbounds, source.name);
			let fetched_outbounds = json_stringify(outbounds);

			if (length(sources_json))
				sources_json = sources_json + ",";
			sources_json = sources_json + source_result_json(source.name, source.url, strategy, true, length(outbounds), "");

			if (length(outbounds_json))
				outbounds_json = outbounds_json + ",";
			outbounds_json = outbounds_json + substr(fetched_outbounds, 1, length(fetched_outbounds) - 2);
			total = total + length(outbounds);
		}

		let snapshot = "{" +
			"\"schema_version\":1," +
			"\"updated_at\":\"" + json_escape(timestamp) + "\"," +
			"\"source\":\"sub-store\"," +
			"\"refresh_strategy\":\"" + json_escape(strategy) + "\"," +
			"\"sources\":[" + sources_json + "]," +
			"\"outbounds\":[" + outbounds_json + "]" +
		"}";

		validate_node_snapshot_content(snapshot);
		write_text_atomic(PATH.NODE_SNAPSHOT, snapshot);
		release(lock);
		return Success({ path: PATH.NODE_SNAPSHOT, node_count: total, refresh_strategy: strategy, bypass_used: bypass_used }, 200, trace_id, "Node Snapshot refreshed");
	} catch (e) {
		if (lock != null)
			release(lock);
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Failed to refresh Subscriptions", trace_id, err);
	}
}

function subscription_source_count() {
	try {
		let config = validate_subscriptions_content(read_text(PATH.SUBSCRIPTIONS));
		if (type(config.sources) == "array")
			return length(config.sources);
	} catch (e) {
		let err = "" + e;
	}

	return 0;
}

function notification_meta(result) {
	if (result == null)
		return {
			attempted: true,
			ok: false,
			sent: false,
			reason: "notification crashed"
		};

	let reason = "";
	if (result.ok == true && type(result.data) == "object" && result.data != null && type(result.data.reason) == "string")
		reason = result.data.reason;
	else if (result.ok != true)
		reason = result.detail || result.message || result.code || "";

	return {
		attempted: true,
		ok: result.ok == true,
		sent: result.ok == true && type(result.data) == "object" && result.data != null && result.data.sent == true,
		reason: reason
	};
}

function append_notification(result, meta) {
	if (type(result.data) == "object" && result.data != null && type(result.data) != "array")
		result.data.notification = meta;
	else
		result.notification = meta;
	return result;
}

function subscription_auto_status(result) {
	if (!result || result.ok != true)
		return "fail";
	let data = type(result.data) == "object" && result.data != null ? result.data : {};
	return (data.node_count || 0) > 0 ? "success" : "partial";
}

function subscription_auto_message(result, status) {
	let source_count = subscription_source_count();
	if (!result || result.ok != true) {
		let detail = "unknown error";
		if (result != null)
			detail = result.detail || result.message || result.code || detail;
		return "Subscription refresh " + status + "\nDetail: " + detail + "\nSources: " + source_count;
	}

	let data = type(result.data) == "object" && result.data != null ? result.data : {};
	return "Subscription refresh " + status +
		"\nNodes: " + (data.node_count || 0) +
		"\nSources: " + source_count +
		"\nStrategy: " + (data.refresh_strategy || "-") +
		"\nLAN bypass used: " + (data.bypass_used || 0);
}

function subscriptions_refresh_auto(trace_id, req) {
	let result = subscriptions_refresh(trace_id, req);
	let status = subscription_auto_status(result);
	let message = subscription_auto_message(result, status);
	let notify = send_telegram_best_effort(trace_id, "subscriptions_refresh_auto", status, message);
	return append_notification(result, notification_meta(notify));
}

export { subscriptions_get, subscriptions_save, subscriptions_refresh, subscriptions_refresh_auto, node_snapshot_get, node_snapshot_summary, subscription_test_source, subscription_fetch_preflight };
