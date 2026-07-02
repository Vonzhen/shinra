/**
 * Shinra | subscription_fetch.uc | v1.0
 */

'use strict';

import { json_escape } from 'shinra.core.utils';
import { fetch_text } from 'shinra.resource_fetch';
import { preflight_for_url, preflight_detail } from 'shinra.subscription_preflight';

function substore_outbounds(content) {
	let parsed = json(content);

	if (type(parsed) == "array")
		return parsed;

	if (type(parsed) == "object" && parsed != null && type(parsed.outbounds) == "array")
		return parsed.outbounds;

	die("Sub-Store output must be an outbounds array or an object with outbounds array");
}

function source_result_json(id, name, url, strategy, status, ok, node_count, error) {
	return "{" +
		"\"id\":\"" + json_escape(id) + "\"," +
		"\"name\":\"" + json_escape(name) + "\"," +
		"\"url\":\"" + json_escape(url) + "\"," +
		"\"refresh_strategy\":\"" + json_escape(strategy) + "\"," +
		"\"status\":\"" + json_escape(status) + "\"," +
		"\"ok\":" + (ok ? "true" : "false") + "," +
		"\"node_count\":" + node_count + "," +
		"\"error\":\"" + json_escape(error || "") + "\"" +
	"}";
}

function source_result_object(source, strategy, status, ok, node_count, error) {
	return {
		id: source.id || "",
		name: source.name || "",
		url: source.url || "",
		refresh_strategy: strategy,
		status: status || "unknown",
		ok: ok == true,
		node_count: node_count || 0,
		error: error || ""
	};
}

function fetch_substore_output(trace_id, url, strategy) {
	let fetched = fetch_text(trace_id, url, strategy, { timeout_sec: 10, min_bytes: 16 });
	if (!fetched.ok)
		die("fetch failed: " + fetched.error + " exit=" + fetched.exit_code + " stderr=" + fetched.stderr);
	return fetched.body;
}

function fetch_substore_output_checked(trace_id, url, strategy) {
	let preflight = preflight_for_url(trace_id, url);
	let fetched = fetch_text(trace_id, url, strategy, { timeout_sec: 10, min_bytes: 16 });
	if (!fetched.ok)
		die("fetch failed: " + fetched.error + " exit=" + fetched.exit_code + " stderr=" + fetched.stderr + "; " + preflight_detail(preflight));
	return fetched.body;
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

export {
	substore_outbounds,
	source_result_json,
	source_result_object,
	fetch_substore_output,
	fetch_substore_output_checked,
	node_preview
};
