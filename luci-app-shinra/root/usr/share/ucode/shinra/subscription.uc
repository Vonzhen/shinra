/**
 * Shinra | subscription.uc | v1.0
 */

'use strict';

import { mkdir, stat } from 'fs';
import { PATH, BIN } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { lock_acquire, lock_release } from 'shinra.core.lock';
import { read_text, write_text_atomic, parse_json_object, request_content, request_keys, json_escape, json_stringify, ExecResult, ExecSafe } from 'shinra.core.utils';
import { validate_refresh_strategy, normalize_subscriptions_policy } from 'shinra.subscription_policy';
import { fetch_text } from 'shinra.resource_fetch';
import { task_path, read_task, patch_task, running_task, finish_task, fail_task } from 'shinra.core.task';

const SUBSCRIPTION_REFRESH_TASK = "subscription.refresh";
const SUBSCRIPTION_REFRESH_TRACE = "shinra-runner-subscription-refresh";

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

function subscription_refresh_task_enabled(trace_id) {
	return trace_id == SUBSCRIPTION_REFRESH_TRACE;
}

function progress_percent(done, total) {
	done = int(done || 0);
	total = int(total || 0);
	if (total <= 0)
		return 0;
	if (done >= total)
		return 100;
	return int((done * 100) / total);
}

function redacted_url(url) {
	if (type(url) != "string" || url == "")
		return "";

	let scheme = "";
	let rest = url;
	if (substr(url, 0, 8) == "https://") {
		scheme = "https://";
		rest = substr(url, 8);
	} else if (substr(url, 0, 7) == "http://") {
		scheme = "http://";
		rest = substr(url, 7);
	}

	let slash = index(rest, "/");
	let host = slash >= 0 ? substr(rest, 0, slash) : rest;
	if (host == "")
		return "";
	return scheme + host + "/...";
}

function write_subscription_refresh_task(trace_id, patch) {
	try {
		if (!subscription_refresh_task_enabled(trace_id))
			return;
		if (patch.status == "running")
			running_task(SUBSCRIPTION_REFRESH_TASK, trace_id, patch);
		else
			patch_task(SUBSCRIPTION_REFRESH_TASK, patch);
	} catch (e) {
		/* Progress must never fail the actual refresh. */
	}
}

function path_exists(path) {
	let info = stat(path);
	return type(info) == "object" && info != null;
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
	let fetched = fetch_text(trace_id, url, strategy, { timeout_sec: 10, min_bytes: 16 });
	if (!fetched.ok)
		die("fetch failed: " + fetched.error + " exit=" + fetched.exit_code + " stderr=" + fetched.stderr);
	return fetched.body;
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

function fetch_substore_output_checked(trace_id, url, strategy) {
	let preflight = preflight_for_url(trace_id, url);
	let fetched = fetch_text(trace_id, url, strategy, { timeout_sec: 10, min_bytes: 16 });
	if (!fetched.ok)
		die("fetch failed: " + fetched.error + " exit=" + fetched.exit_code + " stderr=" + fetched.stderr + "; " + preflight_detail(preflight));
	return fetched.body;
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
		lock = lock_acquire("subscription", trace_id);
		write_text_atomic(PATH.SUBSCRIPTIONS, json_stringify(config));
		lock_release(lock);
		return Success({ path: PATH.SUBSCRIPTIONS }, 200, trace_id, "Subscriptions saved");
	} catch (e) {
		if (lock != null)
			lock_release(lock);
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

		validate_url(url);
		if (strategy == "")
			strategy = "direct";
		validate_refresh_strategy(strategy);

		let content = fetch_substore_output_checked(trace_id, url, strategy);
		let outbounds = substore_outbounds(content);
		validate_outbounds(outbounds);

		return Success({
			name: name,
			url: url,
			refresh_strategy: strategy,
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
		let preflight = preflight_for_url(trace_id, url);
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
		lock = lock_acquire("subscription", trace_id);

		let timestamp = ExecSafe(trace_id, [ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" ]);
		timestamp = replace(timestamp, "\n", "");
		timestamp = replace(timestamp, "\r", "");

		let sources_json = "";
		let outbounds_json = "";
		let total = 0;
		let completed = 0;

		write_subscription_refresh_task(trace_id, {
			status: "running",
			message: "Subscription refresh running",
			total_count: length(config.sources),
			completed_count: 0,
			updated_count: 0,
			unchanged_count: 0,
			failed_count: 0,
			checked_count: 0,
			progress: 0,
			current_item: "",
			last_error: "",
			meta: {
				refresh_strategy: strategy,
				source_name: "",
				current_url_redacted: "",
				node_count: 0
			},
			trace_id: trace_id
		});

		for (let source in config.sources) {
			write_subscription_refresh_task(trace_id, {
				status: "running",
				message: "Subscription refresh running",
				total_count: length(config.sources),
				completed_count: completed,
				updated_count: total,
				checked_count: completed,
				progress: progress_percent(completed, length(config.sources)),
				current_item: source.name || "",
				last_error: "",
				meta: {
					refresh_strategy: strategy,
					source_name: source.name || "",
					current_url_redacted: redacted_url(source.url),
					node_count: total
				}
			});

			if (source.enabled == false) {
				if (length(sources_json))
					sources_json = sources_json + ",";
				sources_json = sources_json + source_result_json(source.name, source.url, strategy, true, 0, "disabled");
				completed = completed + 1;
				write_subscription_refresh_task(trace_id, {
					completed_count: completed,
					checked_count: completed,
					progress: progress_percent(completed, length(config.sources)),
					current_item: source.name || "",
					meta: {
						refresh_strategy: strategy,
						source_name: source.name || "",
						current_url_redacted: redacted_url(source.url),
						node_count: total
					}
				});
				continue;
			}

			let content = fetch_substore_output_checked(trace_id, source.url, strategy);
			let outbounds = substore_outbounds(content);
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
			completed = completed + 1;
			write_subscription_refresh_task(trace_id, {
				completed_count: completed,
				updated_count: total,
				checked_count: completed,
				progress: progress_percent(completed, length(config.sources)),
				current_item: source.name || "",
				last_error: "",
				meta: {
					refresh_strategy: strategy,
					source_name: source.name || "",
					current_url_redacted: redacted_url(source.url),
					node_count: total
				}
			});
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
		lock_release(lock);
		if (subscription_refresh_task_enabled(trace_id)) {
			finish_task(SUBSCRIPTION_REFRESH_TASK, total > 0 ? "success" : "partial", trace_id, {
				message: "Node Snapshot refreshed",
				total_count: length(config.sources),
				completed_count: length(config.sources),
				updated_count: total,
				unchanged_count: 0,
				failed_count: 0,
				checked_count: length(config.sources),
				progress: 100,
				current_item: "",
				last_error: "",
				meta: {
					refresh_strategy: strategy,
					source_name: "",
					current_url_redacted: "",
					node_count: total
				}
			});
		}
		return Success({ path: PATH.NODE_SNAPSHOT, node_count: total, refresh_strategy: strategy }, 200, trace_id, "Node Snapshot refreshed");
	} catch (e) {
		if (lock != null)
			lock_release(lock);
		let err = "" + e;
		if (subscription_refresh_task_enabled(trace_id)) {
			try {
				fail_task(SUBSCRIPTION_REFRESH_TASK, trace_id, err, {
					message: "Failed to refresh Subscriptions"
				});
			} catch (task_error) {
				let ignored = "" + task_error;
			}
		}
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Failed to refresh Subscriptions", trace_id, err);
	}
}

function subscription_refresh_runner_strategy(req) {
	if (type(req) != "object" || req == null || type(req.strategy) != "string" || req.strategy == "")
		return "";
	if (req.strategy == "saved")
		return "";
	validate_refresh_strategy(req.strategy);
	return req.strategy;
}

function notify_intent_arg(req) {
	if (type(req) == "object" && req != null && req.notify_intent == true)
		return " notify";
	return "";
}

function subscriptions_refresh_status(trace_id, req) {
	try {
		let path = task_path(SUBSCRIPTION_REFRESH_TASK);
		return Success({
			path: path,
			exists: path_exists(path),
			task: read_task(SUBSCRIPTION_REFRESH_TASK)
		}, 200, trace_id, "Subscription refresh task status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Failed to load Subscription refresh task status", trace_id, err);
	}
}

function subscriptions_refresh_start(trace_id, req) {
	try {
		if (!path_exists(PATH.RUN_DIR) && !mkdir(PATH.RUN_DIR, 0700))
			die("Failed to create Run directory: " + PATH.RUN_DIR);
		if (!path_exists(PATH.RUNNER_DIR) && !mkdir(PATH.RUNNER_DIR, 0700))
			die("Failed to create Runner directory: " + PATH.RUNNER_DIR);

		let strategy = subscription_refresh_runner_strategy(req);
		let lock_info = stat(PATH.RUNNER_DIR + "/subscription.refresh.lock");
		let path = task_path(SUBSCRIPTION_REFRESH_TASK);
		let task = read_task(SUBSCRIPTION_REFRESH_TASK);
		if (type(lock_info) == "object" && lock_info != null && (task.status == "running" || task.status == "starting")) {
			return Success({
				path: path,
				task: task,
				started: false,
				reason: "already_running"
			}, 200, trace_id, "Subscription refresh task is already running");
		}

		let command = "/usr/libexec/shinra-runner subscription.refresh subscriptions_refresh " + SUBSCRIPTION_REFRESH_TRACE;
		if (strategy != "")
			command = command + " " + strategy;
		else if (notify_intent_arg(req) != "")
			command = command + " -";
		command = command + notify_intent_arg(req);
		let code = system(command + " >/dev/null 2>&1 &");
		if (code != 0)
			die("Failed to start /usr/libexec/shinra-runner: " + code);

		task = read_task(SUBSCRIPTION_REFRESH_TASK);
		task.status = "starting";
		task.message = "Subscription refresh queued";
		task.trace_id = trace_id;
		return Success({
			path: path,
			task: task,
			started: true
		}, 202, trace_id, "Subscription refresh task started");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Failed to start Subscription refresh task", trace_id, err);
	}
}

export { subscriptions_get, subscriptions_save, subscriptions_refresh, subscriptions_refresh_start, subscriptions_refresh_status, node_snapshot_get, node_snapshot_summary, subscription_test_source, subscription_fetch_preflight };
