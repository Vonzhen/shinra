/**
 * Shinra | overview_status.uc | v1.0
 */

'use strict';

import { Success } from 'shinra.core.result';
import { runtime_status } from 'shinra.runtime';
import { get_profile, profile_source_get } from 'shinra.profile';
import { subscriptions_get, node_snapshot_summary, subscriptions_refresh_status } from 'shinra.subscription';
import { ruleset_required_inventory, ruleset_policy_get, ruleset_download_required_status } from 'shinra.ruleset';
import { dashboard_status } from 'shinra.dashboard_config';
import { api_status } from 'shinra.api_status';
import { notify_settings_get } from 'shinra.notify';
import { auto_task_status_get } from 'shinra.auto_task';

const SOURCES = [
	{ key: "runtime", fn: runtime_status },
	{ key: "profile", fn: get_profile },
	{ key: "profile_source", fn: profile_source_get },
	{ key: "subscriptions", fn: subscriptions_get },
	{ key: "snapshot", fn: node_snapshot_summary },
	{ key: "rules", fn: ruleset_required_inventory },
	{ key: "rules_policy", fn: ruleset_policy_get },
	{ key: "dashboard", fn: dashboard_status },
	{ key: "api", fn: api_status },
	{ key: "notify", fn: notify_settings_get },
	{ key: "scheduler", fn: auto_task_status_get },
	{ key: "subscription_task", fn: subscriptions_refresh_status },
	{ key: "ruleset_task", fn: ruleset_download_required_status }
];

function source_status(trace_id, source) {
	try {
		let result = source.fn(trace_id, {});
		if (type(result) == "object" && result != null)
			return result;
		return {
			ok: false,
			code: "E_INTERNAL",
			message: "Overview source returned invalid result",
			detail: source.key,
			trace_id: trace_id
		};
	} catch (e) {
		return {
			ok: false,
			code: "E_INTERNAL",
			message: "Overview source failed",
			detail: "" + e,
			trace_id: trace_id
		};
	}
}

function result_data(result) {
	if (type(result) == "object" && result != null && type(result.data) == "object" && result.data != null)
		return result.data;
	return {};
}

function compact_result(result, data) {
	result = type(result) == "object" && result != null ? result : {};
	return {
		ok: result.ok == true,
		code: result.code || (result.ok == true ? "OK" : "E_INTERNAL"),
		message: result.message || "",
		detail: result.detail || "",
		data: data || {},
		trace_id: result.trace_id || ""
	};
}

function compact_profile(result) {
	let data = result_data(result);
	return compact_result(result, {
		valid: data.valid != false
	});
}

function compact_profile_source(result) {
	let data = result_data(result);
	let source = type(data.source) == "object" && data.source != null ? data.source : {};
	return compact_result(result, {
		source: {
			url: source.url ? "configured" : "",
			updated_at: source.updated_at || ""
		}
	});
}

function compact_subscriptions(result) {
	let data = result_data(result);
	let content = "{}";
	try {
		let cfg = json(data.content || "{}");
		let sources = [];
		if (type(cfg.sources) == "array")
			for (let source in cfg.sources)
				push(sources, {});
		content = sprintf("{\"sources\":%J,\"subscription_update\":%J}",
			sources,
			type(cfg.subscription_update) == "object" && cfg.subscription_update != null ? cfg.subscription_update : {});
	} catch (e) {
		content = "{}";
	}
	return compact_result(result, {
		content: content
	});
}

function compact_snapshot(result) {
	let data = result_data(result);
	return compact_result(result, {
		node_count: data.node_count || 0,
		updated_at: data.updated_at || ""
	});
}

function compact_rules(result) {
	let data = result_data(result);
	let summary = type(data.summary) == "object" && data.summary != null ? data.summary : {};
	return compact_result(result, {
		summary: {
			required_count: summary.required_count || 0,
			ready_count: summary.ready_count || 0,
			missing_count: summary.missing_count || 0,
			local_extra_count: summary.local_extra_count || 0
		}
	});
}

function compact_rules_policy(result) {
	let data = result_data(result);
	let policy = type(data.policy) == "object" && data.policy != null ? data.policy : {};
	return compact_result(result, {
		policy: {
			mode: policy.mode || "",
			auto_update: policy.auto_update == true,
			update_hour: policy.update_hour || 0
		}
	});
}

function compact_notify(result) {
	let data = result_data(result);
	let settings = type(data.settings) == "object" && data.settings != null ? data.settings : {};
	let telegram = type(settings.telegram) == "object" && settings.telegram != null ? settings.telegram : {};
	let state = type(data.state) == "object" && data.state != null ? data.state : {};
	return compact_result(result, {
		settings: {
			telegram: {
				enabled: telegram.enabled == true
			}
		},
		state: {
			last_status: state.last_status || "",
			last_attempt_at: state.last_attempt_at || "",
			last_sent: state.last_sent == true
		}
	});
}

function compact_dashboard(result) {
	let data = result_data(result);
	let source = type(data.source) == "object" && data.source != null ? data.source : {};
	let dashboard = type(data.dashboard) == "object" && data.dashboard != null ? data.dashboard : {};
	if (type(source.dashboard) == "object" && source.dashboard != null && type(data.dashboard) != "object")
		dashboard = source.dashboard;
	return compact_result(result, {
		source: {
			enabled: source.enabled == true
		},
		dashboard: {
			enabled: dashboard.enabled == true,
			path: dashboard.path || ""
		},
		dashboard_url: data.dashboard_url || ""
	});
}

function compact_scheduler(result) {
	let data = result_data(result);
	let state = type(data.state) == "object" && data.state != null ? data.state : {};
	return compact_result(result, {
		state: {
			enabled: state.enabled == true,
			tasks: type(state.tasks) == "object" && state.tasks != null ? state.tasks : {}
		},
		scheduler: type(data.scheduler) == "object" && data.scheduler != null ? data.scheduler : {}
	});
}

function compact_task(result) {
	let data = result_data(result);
	return compact_result(result, {
		task: type(data.task) == "object" && data.task != null ? data.task : {},
		task_meta: type(data.task_meta) == "object" && data.task_meta != null ? data.task_meta : {}
	});
}

function compact_source(key, result) {
	if (key == "profile")
		return compact_profile(result);
	if (key == "profile_source")
		return compact_profile_source(result);
	if (key == "subscriptions")
		return compact_subscriptions(result);
	if (key == "snapshot")
		return compact_snapshot(result);
	if (key == "rules")
		return compact_rules(result);
	if (key == "rules_policy")
		return compact_rules_policy(result);
	if (key == "dashboard")
		return compact_dashboard(result);
	if (key == "notify")
		return compact_notify(result);
	if (key == "scheduler")
		return compact_scheduler(result);
	if (key == "subscription_task" || key == "ruleset_task")
		return compact_task(result);
	return result;
}

function overview_status(trace_id, req) {
	let items = {};
	let errors = {};
	let partial = false;

	for (let source in SOURCES) {
		let result = source_status(trace_id, source);
		items[source.key] = compact_source(source.key, result);
		if (!result || result.ok != true) {
			partial = true;
			errors[source.key] = {
				code: result ? (result.code || "E_INTERNAL") : "E_INTERNAL",
				message: result ? (result.message || "failed") : "failed",
				detail: result ? (result.detail || "") : ""
			};
		}
	}

	return Success({
		partial: partial,
		items: items,
		errors: errors
	}, 200, trace_id, partial ? "Overview status loaded with partial failures" : "Overview status loaded");
}

export { overview_status };
