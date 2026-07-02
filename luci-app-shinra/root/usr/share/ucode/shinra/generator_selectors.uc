/**
 * Shinra | generator_selectors.uc | v1.0
 */

'use strict';

import { append_unique } from 'shinra.generator_util';
import { validated_main_selector_tag } from 'shinra.generator_validate';
import { group_tag_list, group_tags_for_regions, grouped_node_tags, unmatched_node_tag_list, regions_from_x_rule } from 'shinra.generator_groups';

function direct_outbound_tag(profile) {
	for (let outbound in profile.outbounds) {
		if (type(outbound) == "object" && outbound != null && outbound.type == "direct" && type(outbound.tag) == "string" && outbound.tag != "")
			return outbound.tag;
	}
	return "";
}

function main_selector_option_count(profile) {
	for (let outbound in profile.outbounds) {
		if (type(outbound) != "object" || outbound == null || outbound.type != "selector" || outbound.x_rule != "main")
			continue;
		if (type(outbound.outbounds) != "array")
			return 0;
		return length(outbound.outbounds);
	}
	return 0;
}

function append_existing_outbounds(next, outbound) {
	if (type(outbound.outbounds) != "array")
		return;

	for (let existing in outbound.outbounds)
		append_unique(next, existing);
}

function set_selector_outbounds(outbound, next) {
	if (length(next) == 0)
		return false;
	outbound.outbounds = next;
	return true;
}

function inject_selectors(profile, nodes, groups) {
	let all_groups = group_tag_list(groups);
	let matched_nodes = grouped_node_tags(groups);
	let unmatched_nodes = unmatched_node_tag_list(nodes, matched_nodes);
	let direct_tag = direct_outbound_tag(profile);
	let main_tag = validated_main_selector_tag(profile);
	let injected = 0;

	for (let outbound in profile.outbounds) {
		if (type(outbound) != "object" || outbound == null || outbound.type != "selector")
			continue;

		if (outbound.x_rule == "keep" || type(outbound.x_rule) != "string")
			continue;

		if (outbound.x_rule == "main") {
			let next = [];
			for (let tag in all_groups)
				append_unique(next, tag);
			for (let tag in unmatched_nodes)
				append_unique(next, tag);

			if (set_selector_outbounds(outbound, next))
				injected = injected + 1;
			continue;
		}

		if (outbound.x_rule == "all_regions") {
			let next = [];
			append_unique(next, main_tag);
			for (let tag in all_groups)
				append_unique(next, tag);

			if (set_selector_outbounds(outbound, next))
				injected = injected + 1;
			continue;
		}

		if (outbound.x_rule == "direct_only") {
			if (direct_tag == "")
				die("Profile must contain direct outbound for x_rule direct_only");

			if (set_selector_outbounds(outbound, [ direct_tag ]))
				injected = injected + 1;
			continue;
		}

		if (substr(outbound.x_rule, 0, 7) == "region:") {
			let next = [];
			append_unique(next, main_tag);
			for (let tag in group_tags_for_regions(groups, regions_from_x_rule(outbound.x_rule, 7)))
				append_unique(next, tag);
			if (set_selector_outbounds(outbound, next))
				injected = injected + 1;
			continue;
		}

		if (substr(outbound.x_rule, 0, 14) == "region+direct:") {
			if (direct_tag == "")
				die("Profile must contain direct outbound for x_rule region+direct");

			let next = [];
			append_unique(next, main_tag);
			append_unique(next, direct_tag);
			for (let tag in group_tags_for_regions(groups, regions_from_x_rule(outbound.x_rule, 14)))
				append_unique(next, tag);

			if (set_selector_outbounds(outbound, next))
				injected = injected + 1;
		}
	}

	return injected;
}

function merge_outbounds(profile, groups, nodes) {
	let merged = [];

	for (let outbound in profile.outbounds) {
		if (type(outbound) == "object" && outbound != null && type(outbound.type) == "string" && outbound.type != "")
			push(merged, outbound);
	}

	for (let group in groups)
		push(merged, group);

	for (let node in nodes)
		push(merged, node);

	profile.outbounds = merged;
}

export { direct_outbound_tag, main_selector_option_count, append_existing_outbounds, set_selector_outbounds, inject_selectors, merge_outbounds };
