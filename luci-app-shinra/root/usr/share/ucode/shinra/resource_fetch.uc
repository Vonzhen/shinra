/**
 * Shinra | resource_fetch.uc | v1.0
 * Thin policy wrapper around core.netexec.
 */

'use strict';

import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { fetch as net_fetch } from 'shinra.core.netexec';

function normalize_fetch_strategy(strategy, fallback) {
	if (fallback != "proxy")
		fallback = "direct";

	if (strategy == null || strategy == "")
		return fallback;
	if (strategy == "proxy")
		return "proxy";
	return "direct";
}

function apply_strategy(opts, strategy) {
	opts.fetch_strategy = strategy;
	opts.effective_mode = strategy;
	return opts;
}

function fetch_text(trace_id, url, strategy, opts) {
	opts = type(opts) == "object" && opts != null ? opts : {};
	strategy = normalize_fetch_strategy(strategy, "direct");
	opts.url = url;
	opts.trace_id = trace_id;
	opts.dest_file = "";
	let result = net_fetch(apply_strategy(opts, strategy));
	result.fetch_strategy = strategy;
	return result;
}

function fetch_file(trace_id, url, dest_file, strategy, opts) {
	opts = type(opts) == "object" && opts != null ? opts : {};
	strategy = normalize_fetch_strategy(strategy, "direct");
	opts.url = url;
	opts.trace_id = trace_id;
	opts.dest_file = dest_file;
	let result = net_fetch(apply_strategy(opts, strategy));
	result.fetch_strategy = strategy;
	return result;
}

function net_fetch_test(trace_id, req) {
	try {
		let url = "";
		let policy = "direct";
		let min_bytes = 1;

		if (type(req) == "object" && req != null) {
			if (type(req.url) == "string")
				url = req.url;
			if (type(req.policy) == "string")
				policy = req.policy;
			if (req.min_bytes != null)
				min_bytes = int(req.min_bytes);
		}

		let res = fetch_text(trace_id, url, policy, {
			timeout_sec: 15,
			min_bytes: min_bytes
		});

		let data = {
			ok: res.ok,
			error: res.error,
			exit_code: res.exit_code,
			fetch_strategy: res.fetch_strategy,
			effective_mode: res.effective_mode,
			proxy_endpoint: res.proxy_endpoint,
			url_redacted: res.url_redacted,
			file_size: res.file_size,
			min_bytes: res.min_bytes,
			duration_ms: res.duration_ms,
			dns_ok: res.dns_ok,
			tls_ok: res.tls_ok,
			connect_ok: res.connect_ok,
			stderr: res.stderr
		};

		if (!res.ok)
			return Fail(ERR.E_INTERNAL, "Network fetch test failed", trace_id, res.error + ": " + res.stderr);

		return Success(data, 200, trace_id, "Network fetch test passed");
	} catch (e) {
		return Fail(ERR.E_INTERNAL, "Network fetch test crashed", trace_id, "" + e);
	}
}

export { normalize_fetch_strategy, fetch_text, fetch_file, net_fetch_test };
