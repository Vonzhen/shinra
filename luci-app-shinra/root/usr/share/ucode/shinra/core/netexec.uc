/**
 * Shinra | core/netexec.uc | v1.0
 * Unified network fetch layer. This deliberately relies on wget -T instead of
 * coreutils timeout so resource fetches do not fail when timeout is missing.
 */

'use strict';

import { readfile, stat, unlink } from 'fs';
import { BIN, PATH, CONTROL_PLANE_PROXY } from 'shinra.core.constants';
import { ExecResult, ensure_runtime_dir } from 'shinra.core.utils';

const DEFAULT_TIMEOUT_SEC = 20;
const DEFAULT_MIN_BYTES = 1;

function now_ms() {
	return time() * 1000;
}

function trim_text(value) {
	value = "" + value;
	value = replace(value, "\r", "");
	while (length(value) && substr(value, length(value) - 1, 1) == "\n")
		value = substr(value, 0, length(value) - 1);
	return value;
}

function file_size(path) {
	let info = stat(path);
	if (type(info) != "object" || info == null)
		return 0;
	return info.size || 0;
}

function classify_exit(code, stderr) {
	code = int(code);
	let text = lc(stderr || "");
	let dns_ok = true;
	let tls_ok = true;
	let connect_ok = true;

	if (code == 0)
		return { dns_ok: true, tls_ok: true, connect_ok: true };

	if (index(text, "bad address") >= 0 || index(text, "name resolution") >= 0 || index(text, "resolve") >= 0)
		dns_ok = false;
	if (index(text, "ssl") >= 0 || index(text, "tls") >= 0 || index(text, "certificate") >= 0)
		tls_ok = false;
	if (index(text, "connection refused") >= 0 || index(text, "timed out") >= 0 || index(text, "network") >= 0)
		connect_ok = false;

	return {
		dns_ok: dns_ok,
		tls_ok: tls_ok,
		connect_ok: connect_ok
	};
}

function redacted_url(url) {
	url = "" + url;
	let scheme = index(url, "://");
	let start = scheme >= 0 ? scheme + 3 : 0;
	let rest = substr(url, start);
	let slash = index(rest, "/");
	let host = slash >= 0 ? substr(rest, 0, slash) : rest;
	if (host == "")
		return "";
	return (scheme >= 0 ? substr(url, 0, scheme + 3) : "https://") + host + "/...";
}

function normalize_mode(mode) {
	if (mode == "proxy")
		return "proxy";
	return "direct";
}

function wget_argv(opts, output_path) {
	let timeout_sec = int(opts.timeout_sec || DEFAULT_TIMEOUT_SEC);
	if (timeout_sec <= 0)
		timeout_sec = DEFAULT_TIMEOUT_SEC;
	let mode = normalize_mode(opts.effective_mode);

	let argv = [];
	if (mode == "proxy") {
		push(argv, "env");
		push(argv, "http_proxy=" + CONTROL_PLANE_PROXY.URL);
		push(argv, "https_proxy=" + CONTROL_PLANE_PROXY.URL);
		push(argv, "HTTP_PROXY=" + CONTROL_PLANE_PROXY.URL);
		push(argv, "HTTPS_PROXY=" + CONTROL_PLANE_PROXY.URL);
		push(argv, "no_proxy=");
		push(argv, "NO_PROXY=");
	}

	push(argv, BIN.WGET);
	push(argv, "-T");
	push(argv, "" + timeout_sec);
	push(argv, "-Y");
	push(argv, mode == "proxy" ? "on" : "off");

	if (opts.user_agent && opts.user_agent != "") {
		push(argv, "-U");
		push(argv, "" + opts.user_agent);
	}

	if (type(opts.headers) == "array") {
		for (let header in opts.headers) {
			if (type(header) == "string" && header != "") {
				push(argv, "--header");
				push(argv, header);
			}
		}
	}

	if (opts.method == "POST") {
		push(argv, "--post-data");
		push(argv, "" + (opts.post_data || ""));
	}

	push(argv, "-O");
	push(argv, output_path);
	push(argv, "" + opts.url);
	return argv;
}

function fetch(opts) {
	opts = type(opts) == "object" && opts != null ? opts : {};
	let trace_id = opts.trace_id || "shinra-netexec";
	let url = opts.url || "";
	let mode = normalize_mode(opts.effective_mode);
	let start = now_ms();

	ensure_runtime_dir();

	if (url == "") {
		return {
			ok: false,
			error: "invalid_url",
			exit_code: 126,
			stderr: "missing url",
			stdout: "",
			effective_mode: mode,
			file_size: 0,
			duration_ms: 0,
			dns_ok: false,
			tls_ok: false,
			connect_ok: false
		};
	}

	let dest_file = opts.dest_file || "";
	let body_path = dest_file != "" ? dest_file : PATH.RUN_DIR + "/netfetch-" + replace("" + trace_id, "/", "_") + "-" + time() + ".body";
	let temp_body = dest_file == "";
	let min_bytes = int(opts.min_bytes || DEFAULT_MIN_BYTES);
	if (min_bytes < 0)
		min_bytes = DEFAULT_MIN_BYTES;

	unlink(body_path);
	let result = ExecResult(trace_id, wget_argv(opts, body_path));
	let size = file_size(body_path);
	let body = temp_body ? (readfile(body_path) || "") : "";
	let duration = now_ms() - start;
	let cls = classify_exit(result.code, result.stderr);
	let ok = result.code == 0 && size >= min_bytes;
	let error = "";

	if (result.code != 0)
		error = "wget_failed";
	else if (size < min_bytes)
		error = "payload_too_small";

	if (!ok && dest_file != "")
		unlink(body_path);
	if (temp_body)
		unlink(body_path);

	return {
		ok: ok,
		error: error,
		exit_code: result.code,
		stderr: trim_text(result.stderr),
		stdout: trim_text(result.stdout),
		body: body,
		url_redacted: redacted_url(url),
		effective_mode: mode,
		proxy_endpoint: mode == "proxy" ? CONTROL_PLANE_PROXY.URL : "",
		file_size: size,
		min_bytes: min_bytes,
		duration_ms: duration,
		dns_ok: cls.dns_ok,
		tls_ok: cls.tls_ok,
		connect_ok: cls.connect_ok
	};
}

const NetExec = {
	fetch: fetch
};

export { NetExec, fetch };
