/**
 * Shinra | dashboard_config.uc | v1.0
 */

'use strict';

import { stat } from 'fs';
import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { read_optional_text, write_text_atomic, parse_json_object, request_content, request_keys, json_stringify_pretty } from 'shinra.core.utils';

const DEFAULT_DASHBOARD_DOWNLOAD_URL = "https://github.com/miozen/shinra-dashboard/releases/latest/download/shinra-dashboard.zip";

function default_dashboard_source() {
	return {
		enabled: true,
		listen: "0.0.0.0",
		listen_port: 20123,
		secret: "",
		access_control_allow_origin: [ "*" ],
		access_control_allow_private_network: true,
		public_access: {
			enabled: false,
			origin: "",
			dashboard_path: "/shinra/dashboard/",
			api_path: "/shinra/api/"
		},
		dashboard: {
			enabled: true,
			path: PATH.DASHBOARD_DIR,
			download_url: DEFAULT_DASHBOARD_DOWNLOAD_URL,
			update_interval: "1d"
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

function normalize_public_origin(value) {
	if (type(value) != "string")
		return "";

	let origin = value;
	while (length(origin) && substr(origin, length(origin) - 1, 1) == "/")
		origin = substr(origin, 0, length(origin) - 1);

	if (origin == "")
		return "";
	if (!valid_url(origin))
		die("public_access.origin must start with http:// or https://");

	let authority = index(origin, "https://") == 0 ? substr(origin, 8) : substr(origin, 7);
	if (authority == "" || index(authority, "/") >= 0 || index(authority, "?") >= 0 || index(authority, "#") >= 0 || index(authority, "@") >= 0)
		die("public_access.origin must contain only scheme, host and optional port");

	return origin;
}

function normalize_public_path(value, fallback, field) {
	let path = type(value) == "string" && value != "" ? value : fallback;
	if (substr(path, 0, 1) != "/")
		die(field + " must start with /");
	if (index(path, "?") >= 0 || index(path, "#") >= 0)
		die(field + " must not contain query or fragment");
	if (substr(path, length(path) - 1, 1) != "/")
		path += "/";
	return path;
}

function normalize_public_access(raw) {
	let defaults = default_dashboard_source().public_access;
	let result = {
		enabled: false,
		origin: "",
		dashboard_path: defaults.dashboard_path,
		api_path: defaults.api_path
	};

	if (type(raw) == "object" && raw != null && type(raw) != "array") {
		result.enabled = raw.enabled == true;
		result.origin = normalize_public_origin(raw.origin);
		result.dashboard_path = normalize_public_path(raw.dashboard_path, defaults.dashboard_path, "public_access.dashboard_path");
		result.api_path = normalize_public_path(raw.api_path, defaults.api_path, "public_access.api_path");
	}

	if (result.enabled && result.origin == "")
		die("public_access.origin is required when public access is enabled");

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

function normalize_dashboard_source(source) {
	if (type(source) != "object" || source == null || type(source) == "array")
		die("Dashboard source root must be a JSON object");

	let defaults = default_dashboard_source();
	let listen_port = int(source.listen_port || defaults.listen_port);
	if (listen_port <= 0 || listen_port > 65535)
		die("listen_port must be between 1 and 65535");

	let listen = type(source.listen) == "string" && source.listen != "" ? source.listen : defaults.listen;
	return {
		enabled: source.enabled == false ? false : true,
		listen: listen,
		listen_port: listen_port,
		secret: "",
		access_control_allow_origin: normalize_origin_list(source.access_control_allow_origin),
		access_control_allow_private_network: source.access_control_allow_private_network == true ? true : false,
		public_access: normalize_public_access(source.public_access),
		dashboard: normalize_dashboard(source.dashboard)
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
	let index_info = stat(source.dashboard.path + "/index.html");
	let dashboard_ready = type(index_info) == "object" && index_info != null;

	return {
		source_path: PATH.DASHBOARD_SOURCE,
		enabled: source.enabled,
		listen: source.listen,
		listen_port: source.listen_port,
		secret_configured: source.secret != "",
		access_control_allow_origin: source.access_control_allow_origin,
		access_control_allow_private_network: source.access_control_allow_private_network,
		public_access: source.public_access,
		api_url: "http://" + (source.listen == "0.0.0.0" || source.listen == "::" ? "<router-host>" : source.listen) + ":" + source.listen_port + "/",
		dashboard_url: dashboard_url(source),
		dashboard: source.dashboard,
		dashboard_path_exists: path_exists,
		dashboard_path_size: path_exists && type(info.size) == "int" ? info.size : 0,
		dashboard_ready: dashboard_ready,
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
