/**
 * Shinra | dashboard.uc | v1.0
 */

'use strict';

import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { observe_runtime } from 'shinra.runtime';
import { http_get_json, clash_api_url } from 'shinra.clash';

function empty_clash_api(reason) {
	return {
		available: false,
		reason: reason,
		traffic: {
			up: 0,
			down: 0
		},
		connections: {
			count: 0
		},
		proxies: {
			selectors: []
		}
	};
}

function number_or_zero(value) {
	if (type(value) == "int" || type(value) == "double")
		return value;
	return 0;
}

function observe_traffic(trace_id) {
	let data = http_get_json(trace_id, clash_api_url("/traffic"));
	return {
		up: number_or_zero(data.up),
		down: number_or_zero(data.down)
	};
}

function observe_connections(trace_id) {
	let data = http_get_json(trace_id, clash_api_url("/connections"));
	let count = 0;

	if (type(data.connections) == "array")
		count = length(data.connections);

	return {
		count: count
	};
}

function is_selector(proxy) {
	if (type(proxy) != "object" || proxy == null)
		return false;
	if (proxy.type == "Selector" || proxy.type == "selector")
		return true;
	return type(proxy.all) == "array" && type(proxy.now) == "string";
}

function observe_proxies(trace_id) {
	let data = http_get_json(trace_id, clash_api_url("/proxies"));
	let selectors = [];

	if (type(data.proxies) == "object" && data.proxies != null) {
		for (let name in data.proxies) {
			let proxy = data.proxies[name];
			if (!is_selector(proxy))
				continue;

			push(selectors, {
				name: name,
				now: type(proxy.now) == "string" ? proxy.now : "",
				all_count: type(proxy.all) == "array" ? length(proxy.all) : 0
			});
		}
	}

	return {
		selectors: selectors
	};
}

function observe_clash_api(trace_id, runtime_state) {
	if (!runtime_state.sing_box_running)
		return empty_clash_api("runtime_not_running");

	let proxies = null;
	try {
		proxies = observe_proxies(trace_id);
	} catch (e) {
		let err = "" + e;
		return empty_clash_api("api_unreachable");
	}

	let traffic = {
		up: 0,
		down: 0
	};
	let connections = {
		count: 0
	};

	try {
		traffic = observe_traffic(trace_id);
	} catch (e) {
		let err = "" + e;
	}

	try {
		connections = observe_connections(trace_id);
	} catch (e) {
		let err = "" + e;
	}

	return {
		available: true,
		reason: "ok",
		traffic: traffic,
		connections: connections,
		proxies: proxies
	};
}

function dashboard_overview(trace_id, req) {
	try {
		let observed = observe_runtime(trace_id);
		let state = json(observed.state);

		return Success({
			runtime: state,
			cards: {
				running: state.sing_box_running,
				tun: state.tun_exists,
				clash_api: state.clash_api_available,
				runtime_config: state.runtime_config_exists,
				last_apply_result: state.last_apply_result,
				recent_error: state.recent_error,
				checked_at: state.checked_at
			}
		}, 200, trace_id, "Dashboard overview observed");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_DASHBOARD_OBSERVE_FAILED, "Failed to observe Dashboard overview", trace_id, err);
	}
}

function dashboard_metrics(trace_id, req) {
	try {
		let observed = observe_runtime(trace_id);
		let state = json(observed.state);
		let clash_api = observe_clash_api(trace_id, state);

		return Success({
			runtime: state,
			clash_api: clash_api
		}, 200, trace_id, "Dashboard metrics observed");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_DASHBOARD_OBSERVE_FAILED, "Failed to observe Dashboard metrics", trace_id, err);
	}
}

export { dashboard_overview, dashboard_metrics };
