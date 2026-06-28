/**
 * Shinra | clash.uc | v1.0
 */

'use strict';

import { PATH, BIN, CLASH_API } from 'shinra.core.constants';
import { read_optional_text, parse_json_object, ExecResult } from 'shinra.core.utils';

function first_json_line(text) {
	text = "" + text;
	let line = "";

	for (let i = 0; i < length(text); i++) {
		let ch = substr(text, i, 1);
		if (ch == "\r")
			continue;
		if (ch == "\n")
			break;
		line = line + ch;
	}

	return line;
}

function clash_api_secret() {
	let content = read_optional_text(PATH.RUNTIME_CONFIG);
	if (content == "")
		return "";

	try {
		let config = parse_json_object(content, "Runtime Config");
		if (type(config.experimental) != "object" || config.experimental == null)
			return "";
		if (type(config.experimental.clash_api) != "object" || config.experimental.clash_api == null)
			return "";
		if (type(config.experimental.clash_api.secret) != "string")
			return "";
		return config.experimental.clash_api.secret;
	} catch (e) {
		let err = "" + e;
		return "";
	}
}

function clash_api_external_controller() {
	let content = read_optional_text(PATH.RUNTIME_CONFIG);
	if (content == "")
		return CLASH_API.DEFAULT_EXTERNAL_CONTROLLER;

	try {
		let config = parse_json_object(content, "Runtime Config");
		if (type(config.experimental) != "object" || config.experimental == null)
			return CLASH_API.DEFAULT_EXTERNAL_CONTROLLER;
		if (type(config.experimental.clash_api) != "object" || config.experimental.clash_api == null)
			return CLASH_API.DEFAULT_EXTERNAL_CONTROLLER;
		if (type(config.experimental.clash_api.external_controller) != "string" || config.experimental.clash_api.external_controller == "")
			return CLASH_API.DEFAULT_EXTERNAL_CONTROLLER;
		return config.experimental.clash_api.external_controller;
	} catch (e) {
		let err = "" + e;
		return CLASH_API.DEFAULT_EXTERNAL_CONTROLLER;
	}
}

function strip_trailing_slash(value) {
	value = "" + value;
	while (length(value) > 0 && substr(value, length(value) - 1, 1) == "/")
		value = substr(value, 0, length(value) - 1);
	return value;
}

function clash_api_base_url() {
	let controller = strip_trailing_slash(clash_api_external_controller());
	if (index(controller, "http://") == 0 || index(controller, "https://") == 0)
		return controller;
	return "http://" + controller;
}

function clash_api_url(path) {
	path = "" + path;
	if (path == "")
		return clash_api_base_url();
	if (substr(path, 0, 1) != "/")
		path = "/" + path;
	return clash_api_base_url() + path;
}

function wget_args(method, url, body) {
	let args = [ BIN.TIMEOUT, "3", "wget", "-q", "-T", "2" ];
	let secret = clash_api_secret();

	if (secret != "")
		push(args, "--header=Authorization: Bearer " + secret);

	if (method == "PUT") {
		push(args, "--method=PUT");
		push(args, "--body-data=" + body);
	}

	push(args, "-O");
	push(args, "-");
	push(args, url);
	return args;
}

function http_get_json(trace_id, url) {
	let result = ExecResult(trace_id, wget_args("GET", url, ""));
	let body = first_json_line(result.stdout);

	if (result.code != 0)
		die(result.stderr || result.stdout || "HTTP GET failed");
	if (body == "")
		die(result.stderr || "empty response from " + url);

	return json(body);
}

function http_put_json(trace_id, url, body) {
	let result = ExecResult(trace_id, wget_args("PUT", url, body));

	if (result.code != 0)
		die(result.stderr || result.stdout || "HTTP PUT failed");

	return result.stdout || "";
}

function api_available(trace_id, url) {
	try {
		http_get_json(trace_id, url);
		return true;
	} catch (e) {
		let err = "" + e;
		return false;
	}
}

export { clash_api_external_controller, clash_api_base_url, clash_api_url, http_get_json, http_put_json, api_available };
