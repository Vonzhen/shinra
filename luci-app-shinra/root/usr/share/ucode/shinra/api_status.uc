/**
 * Shinra | api_status.uc | v1.1
 */

'use strict';

import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { read_optional_text, parse_json_object, file_exists } from 'shinra.core.utils';
import { observe_runtime } from 'shinra.runtime';
import { read_dashboard_source } from 'shinra.dashboard_config';

function runtime_config() {
	if (!file_exists(PATH.RUNTIME_CONFIG))
		return {};

	let content = read_optional_text(PATH.RUNTIME_CONFIG);
	return content == "" ? {} : parse_json_object(content, "Runtime Config");
}

function endpoint_host(listen) {
	return listen == "0.0.0.0" || listen == "::" ? "<router-host>" : listen;
}

function empty_singbox_api() {
	return {
		configured: false,
		tag: "shinra-api",
		listen: "",
		listen_port: 0,
		secret_configured: false,
		dashboard_enabled: false
	};
}

function runtime_singbox_api(config) {
	let fallback = empty_singbox_api();
	if (type(config.services) != "array")
		return fallback;

	for (let service in config.services) {
		if (type(service) != "object" || service == null || service.type != "api" || service.tag != "shinra-api")
			continue;

		return {
			configured: true,
			tag: "shinra-api",
			listen: type(service.listen) == "string" && service.listen != "" ? service.listen : "0.0.0.0",
			listen_port: int(service.listen_port || 0),
			secret_configured: type(service.secret) == "string" && service.secret != "",
			dashboard_enabled: type(service.dashboard) == "object" && service.dashboard != null && service.dashboard.enabled == true
		};
	}

	return fallback;
}

function singbox_status(source, config, running) {
	let runtime_api = runtime_singbox_api(config);
	let runtime_configured = runtime_api.configured == true;
	let configured = source.enabled == true || runtime_configured;
	let listen = runtime_configured ? runtime_api.listen : source.listen;
	let listen_port = runtime_configured ? runtime_api.listen_port : source.listen_port;
	let reason = "ok";

	if (!configured)
		reason = "disabled";
	else if (!running)
		reason = "runtime_not_running";
	else if (!runtime_configured)
		reason = "runtime_service_missing";

	return {
		configured: configured,
		runtime_configured: runtime_configured,
		source_enabled: source.enabled == true,
		tag: "shinra-api",
		running: running,
		available: configured && runtime_configured && running,
		listen: listen,
		listen_port: listen_port,
		api_url: "http://" + endpoint_host(listen) + ":" + listen_port + "/",
		dashboard_url: "http://" + endpoint_host(listen) + ":" + listen_port + "/dashboard/",
		dashboard_enabled: runtime_configured ? runtime_api.dashboard_enabled : (type(source.dashboard) == "object" && source.dashboard != null && source.dashboard.enabled == true),
		secret_configured: runtime_configured ? runtime_api.secret_configured : false,
		reason: reason
	};
}

function api_status(trace_id, req) {
	try {
		let source = read_dashboard_source();
		let config = runtime_config();
		let observed = observe_runtime(trace_id);
		return Success({ singbox_api: singbox_status(source, config, observed.running == true) }, 200, trace_id, "sing-box API status observed");
	} catch (e) {
		return Fail(ERR.E_API_STATUS_FAILED, "Failed to observe sing-box API status", trace_id, "" + e);
	}
}

export { api_status };
