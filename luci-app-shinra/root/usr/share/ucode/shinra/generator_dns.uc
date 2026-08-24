/**
 * Shinra | generator_dns.uc | v1.0
 */

'use strict';

import { append_unique, tag_contains_keyword, upper_text } from 'shinra.generator_util';
import { rate_filter_excludes_from_urltest } from 'shinra.generator_nodes';

const DNS_OUTBOUND_TAG = "📡 dns-out";

function node_matches_keywords(node, keywords) {
	if (type(node.tag) != "string")
		return false;

	let tag_upper = upper_text(node.tag);
	for (let keyword in keywords) {
		if (tag_contains_keyword(tag_upper, keyword))
			return true;
	}

	return false;
}

function generate_dns_urltest(config, nodes, profile_tags, node_tags) {
	let policy = config.dns_urltest;
	if (type(policy) != "object" || policy == null || policy.enabled != true)
		return null;

	let outbounds = [];
	for (let node in nodes) {
		if (rate_filter_excludes_from_urltest(node.tag, config))
			continue;
		if (node_matches_keywords(node, policy.keywords))
			append_unique(outbounds, node.tag);
	}

	if (length(outbounds) == 0)
		return null;
	if (profile_tags[DNS_OUTBOUND_TAG])
		die("Generated DNS outbound tag conflicts with Profile outbound tag: " + DNS_OUTBOUND_TAG);
	if (node_tags[DNS_OUTBOUND_TAG])
		die("Generated DNS outbound tag conflicts with Node outbound tag: " + DNS_OUTBOUND_TAG);

	return {
		type: "urltest",
		tag: DNS_OUTBOUND_TAG,
		outbounds: outbounds,
		url: policy.url,
		interval: policy.interval,
		tolerance: policy.tolerance,
		interrupt_exist_connections: true
	};
}

function route_dns_detours(profile, dns_group, fallback_tag) {
	let adjusted = 0;
	if (type(profile.dns) != "object" || profile.dns == null || type(profile.dns.servers) != "array")
		return adjusted;

	let target = dns_group != null ? DNS_OUTBOUND_TAG : fallback_tag;
	for (let server in profile.dns.servers) {
		if (type(server) != "object" || server == null || type(server.detour) != "string" || server.detour == "")
			continue;
		server.detour = target;
		adjusted = adjusted + 1;
	}

	return adjusted;
}

export { DNS_OUTBOUND_TAG, generate_dns_urltest, route_dns_detours };
