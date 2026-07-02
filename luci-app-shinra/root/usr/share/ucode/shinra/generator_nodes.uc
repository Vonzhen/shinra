/**
 * Shinra | generator_nodes.uc | v1.0
 */

'use strict';

import { append_unique, upper_text, tag_contains_keyword, is_digit } from 'shinra.generator_util';

function is_reserved_node_type(node_type) {
	return node_type == "selector" || node_type == "urltest" || node_type == "direct" || node_type == "block" || node_type == "dns";
}

function is_real_node(outbound) {
	if (type(outbound) != "object" || outbound == null || type(outbound) == "array")
		return false;
	if (type(outbound.type) != "string" || outbound.type == "")
		return false;
	if (type(outbound.tag) != "string" || outbound.tag == "")
		return false;
	return !is_reserved_node_type(outbound.type);
}

function tag_matches_banned_keywords(tag, banned_keywords) {
	let tag_upper = upper_text(tag);
	for (let keyword in split(banned_keywords || "", "|")) {
		if (tag_contains_keyword(tag_upper, keyword))
			return true;
	}
	return false;
}

function has_high_rate_marker(tag) {
	let value = upper_text(tag);
	let size = length(value);

	for (let i = 0; i < size; i = i + 1) {
		let first = substr(value, i, 1);
		if (!is_digit(first) || first == "0")
			continue;

		let j = i + 1;
		if (j < size && substr(value, j, 1) == ".") {
			j = j + 1;
			if (j >= size || !is_digit(substr(value, j, 1)))
				continue;
			while (j < size && is_digit(substr(value, j, 1)))
				j = j + 1;
		} else {
			while (j < size && is_digit(substr(value, j, 1)))
				j = j + 1;
		}

		if (j < size && substr(value, j, 1) == "X")
			return true;
	}

	return false;
}

function collect_profile_tags(profile) {
	let tags = {};
	for (let outbound in profile.outbounds) {
		if (type(outbound) == "object" && outbound != null && type(outbound.tag) == "string" && outbound.tag != "")
			tags[outbound.tag] = true;
	}
	return tags;
}

function normalized_nodes(snapshot, profile_tags, policy) {
	let nodes = [];
	let node_tags = {};
	let skipped_banned = 0;
	let skipped_high_rate = 0;

	for (let outbound in snapshot.outbounds) {
		if (!is_real_node(outbound))
			continue;

		if (has_high_rate_marker(outbound.tag)) {
			skipped_high_rate = skipped_high_rate + 1;
			continue;
		}

		if (tag_matches_banned_keywords(outbound.tag, policy.banned_keywords)) {
			skipped_banned = skipped_banned + 1;
			continue;
		}

		if (profile_tags[outbound.tag])
			die("Node tag conflicts with Profile outbound tag: " + outbound.tag);
		if (node_tags[outbound.tag])
			die("Duplicated Node Snapshot outbound tag: " + outbound.tag);

		node_tags[outbound.tag] = true;
		push(nodes, outbound);
	}

	return {
		nodes: nodes,
		skipped_banned: skipped_banned,
		skipped_high_rate: skipped_high_rate
	};
}

function collect_node_tags(nodes) {
	let tags = {};
	for (let node in nodes)
		tags[node.tag] = true;
	return tags;
}

function node_tag_list(nodes) {
	let tags = [];
	for (let node in nodes)
		append_unique(tags, node.tag);
	return tags;
}

export { is_reserved_node_type, is_real_node, tag_matches_banned_keywords, has_high_rate_marker, collect_profile_tags, normalized_nodes, collect_node_tags, node_tag_list };
