/**
 * Shinra | dashboard_config.uc | v1.0
 */

'use strict';

import { stat } from 'fs';
import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { read_optional_text, write_text_atomic, parse_json_object, request_content, request_keys, json_stringify_pretty } from 'shinra.core.utils';

const DEFAULT_DASHBOARD_DOWNLOAD_URL = "https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip";

function default_dashboard_source() {
	return {
		enabled: true,
		listen: "0.0.0.0",
		listen_port: 20123,
		secret: "",
		access_control_allow_origin: [ "*" ],
		access_control_allow_private_network: true,
		dashboard: {
			enabled: true,
			path: PATH.DASHBOARD_DIR,
			download_url: DEFAULT_DASHBOARD_DOWNLOAD_URL,
			update_interval: "1d"
		},
		clash_api: {
			enabled: true,
			external_controller: "0.0.0.0:9090",
			secret: "",
			external_ui: "",
			default_mode: "rule",
			access_control_allow_origin: [ "*" ],
			access_control_allow_private_network: true
		}
	};
}

function valid_url(url) {
	return index(url, "http://") == 0 || index(url, "https://") == 0;
}

function normalize_origin_list(raw) {
	if (type(raw) != "array")
		return [ "*" ];

	let result = [];
	for (let item in raw) {
		if (type(item) == "string" && item != "")
			push(result, item);
	}

	if (!length(result))
		return [ "*" ];
	return result;
}

function normalize_dashboard(raw) {
	let defaults = default_dashboard_source().dashboard;
	let result = {
		enabled: true,
		path: defaults.path,
		download_url: defaults.download_url,
		update_interval: defaults.update_interval
	};

	if (type(raw) == "object" && raw != null && type(raw) != "array") {
		result.enabled = raw.enabled == false ? false : true;
		if (type(raw.path) == "string" && raw.path != "")
			result.path = raw.path;
		if (type(raw.download_url) == "string")
			result.download_url = raw.download_url;
		if (type(raw.update_interval) == "string")
			result.update_interval = raw.update_interval;
	}

	if (result.path == "")
		die("dashboard.path is required");
	if (result.download_url != "" && !valid_url(result.download_url))
		die("dashboard.download_url must start with http:// or https://");

	return result;
}

function normalize_clash_api(raw) {
	let defaults = default_dashboard_source().clash_api;
	let result = {
		enabled: true,
		external_controller: defaults.external_controller,
		secret: "",
		external_ui: "",
		default_mode: defaults.default_mode,
		access_control_allow_origin: [ "*" ],
		access_control_allow_private_network: true
	};

	if (type(raw) == "object" && raw != null && type(raw) != "array") {
		result.enabled = raw.enabled == false ? false : true;
		if (type(raw.external_controller) == "string" && raw.external_controller != "")
			result.external_controller = raw.external_controller;
		if (type(raw.secret) == "string")
			result.secret = raw.secret;
		if (type(raw.external_ui) == "string")
			result.external_ui = raw.external_ui;
		if (type(raw.default_mode) == "string" && raw.default_mode != "")
			result.default_mode = raw.default_mode;
	}

	let parts = split(result.external_controller, ":");
	if (length(parts) < 2)
		die("clash_api.external_controller must be host:port");

	let port = int(parts[length(parts) - 1] || 0);
	if (port <= 0 || port > 65535)
		die("clash_api.external_controller port must be between 1 and 65535");

	return result;
}

function normalize_dashboard_source(source) {
	if (type(source) != "object" || source == null || type(source) == "array")
		die("Dashboard source root must be a JSON object");

	let defaults = default_dashboard_source();
	let listen_port = int(source.listen_port || defaults.listen_port);
	if (listen_port <= 0 || listen_port > 65535)
		die("listen_port must be between 1 and 65535");

	let listen = type(source.listen) == "string" && source.listen != "" ? source.listen : defaults.listen;
	let secret = type(source.secret) == "string" ? source.secret : "";
	let has_clash_api = type(source.clash_api) == "object" && source.clash_api != null && type(source.clash_api) != "array";
	let dashboard = normalize_dashboard(source.dashboard);

	/* Sources written by the retired Shinra Dashboard integration have no
	 * clash_api section and point at shinra-dashboard.zip. Restore the
	 * Zashboard default during downgrade without changing existing Clash API
	 * users' settings. */
	if (!has_clash_api && dashboard.download_url == "https://github.com/miozen/shinra-dashboard/releases/latest/download/shinra-dashboard.zip")
		dashboard.download_url = defaults.dashboard.download_url;

	return {
		enabled: source.enabled == false ? false : true,
		listen: listen,
		listen_port: listen_port,
		secret: secret,
		access_control_allow_origin: normalize_origin_list(source.access_control_allow_origin),
		access_control_allow_private_network: source.access_control_allow_private_network == true ? true : false,
		dashboard: dashboard,
		clash_api: normalize_clash_api(source.clash_api)
	};
}

function read_dashboard_source() {
	let content = read_optional_text(PATH.DASHBOARD_SOURCE);
	if (!length(content))
		return default_dashboard_source();
	return normalize_dashboard_source(parse_json_object(content, "Dashboard Source"));
}

function dashboard_source_content(source) {
	return json_stringify_pretty(normalize_dashboard_source(source)) + "\n";
}

function dashboard_url(source) {
	let listen = source.listen;
	if (listen == "0.0.0.0" || listen == "::")
		listen = "<router-host>";
	return "http://" + listen + ":" + source.listen_port + "/dashboard/";
}

function dashboard_status_data(source) {
	let info = stat(source.dashboard.path);
	let path_exists = type(info) == "object" && info != null;

	return {
		source_path: PATH.DASHBOARD_SOURCE,
		enabled: source.enabled,
		listen: source.listen,
		listen_port: source.listen_port,
		secret_configured: source.secret != "",
		access_control_allow_origin: source.access_control_allow_origin,
		access_control_allow_private_network: source.access_control_allow_private_network,
		api_url: "http://" + (source.listen == "0.0.0.0" || source.listen == "::" ? "<router-host>" : source.listen) + ":" + source.listen_port + "/",
		dashboard_url: dashboard_url(source),
		dashboard: source.dashboard,
		clash_api: source.clash_api,
		clash_api_secret_configured: source.clash_api.secret != "",
		dashboard_path_exists: path_exists,
		dashboard_path_size: path_exists && type(info.size) == "int" ? info.size : 0,
		source: source
	};
}

function dashboard_policy() {
	return read_dashboard_source();
}

function dashboard_source_get(trace_id, req) {
	try {
		let source = read_dashboard_source();
		return Success({
			path: PATH.DASHBOARD_SOURCE,
			source: source,
			content: dashboard_source_content(source)
		}, 200, trace_id, "Dashboard source loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_DASHBOARD_SOURCE_FAILED, "Failed to load Dashboard source", trace_id, err);
	}
}

function dashboard_source_save(trace_id, req) {
	try {
		let content = request_content(req);
		if (!length(content))
			die("Missing Dashboard source content; request keys: " + request_keys(req));

		let source = normalize_dashboard_source(parse_json_object(content, "Dashboard Source"));
		write_text_atomic(PATH.DASHBOARD_SOURCE, dashboard_source_content(source));
		return Success({
			path: PATH.DASHBOARD_SOURCE,
			source: source
		}, 200, trace_id, "Dashboard source saved");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_DASHBOARD_SOURCE_FAILED, "Failed to save Dashboard source", trace_id, err);
	}
}

function dashboard_status(trace_id, req) {
	try {
		let source = read_dashboard_source();
		return Success(dashboard_status_data(source), 200, trace_id, "Dashboard status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_DASHBOARD_SOURCE_FAILED, "Failed to load Dashboard status", trace_id, err);
	}
}

export { default_dashboard_source, normalize_dashboard_source, read_dashboard_source, dashboard_source_content, dashboard_policy, dashboard_source_get, dashboard_source_save, dashboard_status };
