/**
 * Shinra | subscription.uc | v1.0
 */

'use strict';

import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { lock_acquire, lock_release } from 'shinra.core.lock';
import { read_text, write_text_atomic, request_content, request_keys, json_stringify, json_stringify_pretty, ExecSafe } from 'shinra.core.utils';
import { validate_refresh_strategy } from 'shinra.subscription_policy';
import { finish_task, fail_task } from 'shinra.core.task';
import { validate_url, validate_subscriptions_content, refresh_strategy } from 'shinra.subscription_config';
import { preflight_for_url } from 'shinra.subscription_preflight';
import { validate_outbounds, preserve_source_attribution, validate_node_snapshot_content, read_old_snapshot, old_outbounds_for_source, old_source_for_id } from 'shinra.subscription_snapshot';
import { SUBSCRIPTION_REFRESH_TASK, subscription_refresh_task_enabled, progress_percent, redacted_url, write_subscription_refresh_task, subscriptions_refresh_status as task_subscriptions_refresh_status, subscriptions_refresh_start as task_subscriptions_refresh_start, subscription_refresh_source_start as task_subscription_refresh_source_start } from 'shinra.subscription_task';
import { substore_outbounds, source_result_object, fetch_substore_output_checked, node_preview } from 'shinra.subscription_fetch';

function append_outbounds(target, outbounds) {
	for (let outbound in outbounds)
		push(target, outbound);
}

function refresh_source_safely(trace_id, source, strategy, old_snapshot) {
	let old_outbounds = old_outbounds_for_source(old_snapshot, source.id);
	let old_count = length(old_outbounds);
	let stage = "fetch";

	if (source.enabled == false)
		return {
			source: source_result_object(source, strategy, "disabled_removed", true, 0, "disabled"),
			outbounds: [],
			updated: false,
			preserved: false,
			failed: false
		};

	try {
		let content = fetch_substore_output_checked(trace_id, source.url, strategy);
		stage = "parse";
		let outbounds = substore_outbounds(content);
		stage = "validate";
		validate_outbounds(outbounds);
		if (length(outbounds) == 0) {
			if (old_count > 0) {
				preserve_source_attribution(old_outbounds, source.id, source.name);
				return {
					source: source_result_object(source, strategy, "preserved_empty_rejected", false, old_count, "empty result rejected"),
					outbounds: old_outbounds,
					updated: false,
					preserved: true,
					failed: true
				};
			}
			return {
				source: source_result_object(source, strategy, "failed_no_previous", false, 0, "empty result rejected; no previous nodes"),
				outbounds: [],
				updated: false,
				preserved: false,
				failed: true
			};
		}
		preserve_source_attribution(outbounds, source.id, source.name);
		return {
			source: source_result_object(source, strategy, "updated", true, length(outbounds), ""),
			outbounds: outbounds,
			updated: true,
			preserved: false,
			failed: false
		};
	} catch (e) {
		let err = "" + e;
		let status = stage == "parse" ? "preserved_parse_failed" : (stage == "validate" ? "preserved_validate_failed" : "preserved_fetch_failed");
		if (old_count > 0) {
			preserve_source_attribution(old_outbounds, source.id, source.name);
			return {
				source: source_result_object(source, strategy, status, false, old_count, err),
				outbounds: old_outbounds,
				updated: false,
				preserved: true,
				failed: true
			};
		}
		return {
			source: source_result_object(source, strategy, "failed_no_previous", false, 0, err),
			outbounds: [],
			updated: false,
			preserved: false,
			failed: true
		};
	}
}

function source_arg(req, key) {
	if (type(req) == "object" && req != null && type(req[key]) == "string")
		return req[key];
	return "";
}

function preserve_unselected_source(source, strategy, old_snapshot, require_existing) {
	if (source.enabled == false) {
		return {
			source: source_result_object(source, strategy, "disabled_removed", true, 0, ""),
			outbounds: []
		};
	}

	let old_outbounds = old_outbounds_for_source(old_snapshot, source.id);
	if (require_existing == true && length(old_outbounds) == 0)
		die("Single-source refresh requires existing snapshot for unselected source: " + source.name);

	preserve_source_attribution(old_outbounds, source.id, source.name);
	let old_source = old_source_for_id(old_snapshot, source.id);
	let status = type(old_source) == "object" && old_source != null && type(old_source.status) == "string" && old_source.status != "" ?
		old_source.status :
		"unchanged";

	return {
		source: source_result_object(source, strategy, status, true, length(old_outbounds), ""),
		outbounds: old_outbounds
	};
}

function target_source_count(config, target_source_id) {
	if (target_source_id == "")
		return length(config.sources);

	for (let source in config.sources)
		if (source.id == target_source_id)
			return 1;

	die("Subscription source id not found: " + target_source_id);
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
				id: type(source.id) == "string" ? source.id : "",
				name: type(source.name) == "string" ? source.name : "",
				status: type(source.status) == "string" ? source.status : "",
				ok: source.ok == true,
				node_count: type(source.node_count) == "int" ? source.node_count : 0,
				error: type(source.error) == "string" ? source.error : ""
			});
		}

		for (let outbound in snapshot.outbounds) {
			let source_name = type(outbound.x_shinra_source_name) == "string" ? outbound.x_shinra_source_name : "";
			push(nodes, {
				tag: outbound.tag,
				type: outbound.type,
				source_id: type(outbound.x_shinra_source_id) == "string" ? outbound.x_shinra_source_id : "",
				source_name: source_name,
				source: source_name != "" ? source_name : (type(outbound.x_shinra_source) == "string" ? outbound.x_shinra_source : "")
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

function subscriptions_refresh_selected(trace_id, req, target_source_id) {
	let lock = null;
	try {
		let config = validate_subscriptions_content(read_text(PATH.SUBSCRIPTIONS));
		let strategy = refresh_strategy(config, req);
		let target_count = target_source_count(config, target_source_id);
		lock = lock_acquire("subscription", trace_id);

		let timestamp = ExecSafe(trace_id, [ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" ]);
		timestamp = replace(timestamp, "\n", "");
		timestamp = replace(timestamp, "\r", "");

		let old_snapshot = read_old_snapshot();
		let sources = [];
		let outbounds = [];
		let total = 0;
		let completed = 0;
		let updated_sources = 0;
		let preserved_sources = 0;
		let failed_sources = 0;
		let last_error = "";

		write_subscription_refresh_task(trace_id, {
			status: "running",
			message: "Subscription refresh running",
			total_count: target_count,
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
			let selected = target_source_id == "" || source.id == target_source_id;
			if (!selected) {
				let preserved = preserve_unselected_source(source, strategy, old_snapshot, target_source_id != "");
				push(sources, preserved.source);
				append_outbounds(outbounds, preserved.outbounds);
				total = total + length(preserved.outbounds);
				continue;
			}

			write_subscription_refresh_task(trace_id, {
				status: "running",
				message: "Subscription refresh running",
				total_count: target_count,
				completed_count: completed,
				updated_count: total,
				checked_count: completed,
				progress: progress_percent(completed, target_count),
				current_item: source.name || "",
				last_error: "",
				meta: {
					refresh_strategy: strategy,
					source_id: source.id || "",
					source_name: source.name || "",
					current_url_redacted: redacted_url(source.url),
					node_count: total
				}
			});

			let result = refresh_source_safely(trace_id, source, strategy, old_snapshot);
			push(sources, result.source);
			append_outbounds(outbounds, result.outbounds);
			total = total + length(result.outbounds);
			if (result.updated)
				updated_sources = updated_sources + 1;
			if (result.preserved)
				preserved_sources = preserved_sources + 1;
			if (result.failed) {
				failed_sources = failed_sources + 1;
				last_error = result.source.error || last_error;
			}
			completed = completed + 1;
			write_subscription_refresh_task(trace_id, {
				completed_count: completed,
				updated_count: total,
				unchanged_count: preserved_sources,
				failed_count: failed_sources,
				checked_count: completed,
				progress: progress_percent(completed, target_count),
				current_item: source.name || "",
				last_error: last_error,
				meta: {
					refresh_strategy: strategy,
					source_id: source.id || "",
					source_name: source.name || "",
					current_url_redacted: redacted_url(source.url),
					node_count: total,
					source_status: result.source.status || ""
				}
			});
		}

		let task_status = failed_sources > 0 ?
			(updated_sources > 0 ? "partial" : (preserved_sources > 0 ? "failed_preserved" : "failed_no_snapshot")) :
			"success";
		if (task_status == "failed_no_snapshot")
			die(last_error != "" ? last_error : "Subscription refresh failed and no previous snapshot is available");

		let snapshot_obj = {
			schema_version: 1,
			updated_at: timestamp,
			source: "sub-store",
			refresh_strategy: strategy,
			sources: sources,
			outbounds: outbounds
		};
		let snapshot = json_stringify_pretty(snapshot_obj) + "\n";

		validate_node_snapshot_content(snapshot);
		write_text_atomic(PATH.NODE_SNAPSHOT, snapshot);
		lock_release(lock);
		if (subscription_refresh_task_enabled(trace_id)) {
			finish_task(SUBSCRIPTION_REFRESH_TASK, task_status, trace_id, {
				message: "Node Snapshot refreshed",
				total_count: target_count,
				completed_count: target_count,
				updated_count: total,
				unchanged_count: preserved_sources,
				failed_count: failed_sources,
				checked_count: target_count,
				progress: 100,
				current_item: "",
				last_error: last_error,
				meta: {
					refresh_strategy: strategy,
					source_id: target_source_id,
					source_name: "",
					current_url_redacted: "",
					node_count: total,
					updated_sources: updated_sources,
					preserved_sources: preserved_sources,
					failed_sources: failed_sources,
					target_source_id: target_source_id
				}
			});
		}
		return Success({
			path: PATH.NODE_SNAPSHOT,
			status: task_status,
			node_count: total,
			refresh_strategy: strategy,
			updated_sources: updated_sources,
			preserved_sources: preserved_sources,
			failed_sources: failed_sources,
			target_source_id: target_source_id,
			sources: sources
		}, 200, trace_id, "Node Snapshot refreshed");
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

function subscriptions_refresh(trace_id, req) {
	return subscriptions_refresh_selected(trace_id, req, "");
}

function subscription_refresh_source(trace_id, req) {
	let source_id = source_arg(req, "source_id");
	if (source_id == "")
		source_id = source_arg(req, "id");
	if (source_id == "")
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Failed to refresh Subscription source", trace_id, "Missing source_id");

	return subscriptions_refresh_selected(trace_id, req, source_id);
}

function subscriptions_refresh_status(trace_id, req) {
	return task_subscriptions_refresh_status(trace_id, req);
}

function subscriptions_refresh_start(trace_id, req) {
	return task_subscriptions_refresh_start(trace_id, req);
}

function subscription_refresh_source_start(trace_id, req) {
	return task_subscription_refresh_source_start(trace_id, req);
}

export { subscriptions_get, subscriptions_save, subscriptions_refresh, subscription_refresh_source, subscriptions_refresh_start, subscription_refresh_source_start, subscriptions_refresh_status, node_snapshot_get, node_snapshot_summary, subscription_test_source, subscription_fetch_preflight };
