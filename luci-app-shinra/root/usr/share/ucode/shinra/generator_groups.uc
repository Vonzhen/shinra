/**
 * Shinra | generator_groups.uc | v1.0
 */

'use strict';

import { append_unique, upper_text, tag_contains_keyword } from 'shinra.generator_util';

function default_region_order() {
	return [ "HK", "TW", "SG", "JP", "US" ];
}

function region_order(config) {
	if (type(config) == "object" && config != null && type(config.region_keys) == "array")
		return config.region_keys;
	return default_region_order();
}

function source_policy_map(config) {
	let sources = {};
	for (let source in config.sources) {
		if (type(source) != "object" || source == null || type(source) == "array")
			die("Subscription source must be an object");
		if (type(source.name) != "string" || source.name == "")
			die("Subscription source name must be a non-empty string");
		if (sources[source.name])
			die("Duplicated subscription source name: " + source.name);

		sources[source.name] = source;
	}
	return sources;
}

function allowed_regions(source, config) {
	let regions = [];

	if (type(source.allowed_regions) == "array") {
		for (let region in source.allowed_regions) {
			append_unique(regions, region);
		}
		return regions;
	}

	for (let region in region_order(config))
		push(regions, region);
	return regions;
}

function has_region(regions, region) {
	for (let item in regions) {
		if (item == region)
			return true;
	}
	return false;
}

function node_matches_region(node, keywords) {
	if (type(node.tag) != "string")
		return false;

	let tag_upper = upper_text(node.tag);
	for (let keyword in keywords) {
		if (tag_contains_keyword(tag_upper, keyword))
			return true;
	}
	return false;
}

function region_flag(region) {
	if (region == "HK")
		return "🇭🇰";
	if (region == "TW")
		return "🇹🇼";
	if (region == "SG")
		return "🇸🇬";
	if (region == "JP")
		return "🇯🇵";
	if (region == "US")
		return "🇺🇸";
	return "";
}

function make_region_group_tag(region, source_name) {
	let flag = region_flag(region);
	let tag = region + "-" + source_name;
	return flag != "" ? flag + " " + tag : tag;
}

function generate_region_groups(config, nodes, profile_tags, node_tags) {
	let groups = [];
	let group_tags = {};
	let sources = source_policy_map(config);
	let keywords = config.region_keywords;
	let urltest = config.urltest_params;

	for (let source_name in sources) {
		let source = sources[source_name];
		if (source.enabled == false)
			continue;

		let source_regions = allowed_regions(source, config);
		for (let region in region_order(config)) {
			if (!has_region(source_regions, region))
				continue;

			let outbounds = [];
			for (let node in nodes) {
				if (node.x_shinra_source != source_name)
					continue;
				if (!node_matches_region(node, keywords[region]))
					continue;
				append_unique(outbounds, node.tag);
			}

			if (length(outbounds) == 0)
				continue;

			let tag = make_region_group_tag(region, source_name);
			if (profile_tags[tag])
				die("Generated region group tag conflicts with Profile outbound tag: " + tag);
			if (node_tags[tag])
				die("Generated region group tag conflicts with Node outbound tag: " + tag);
			if (group_tags[tag])
				die("Duplicated generated region group tag: " + tag);

			group_tags[tag] = true;
			push(groups, {
				type: "urltest",
				tag: tag,
				x_shinra_region: region,
				outbounds: outbounds,
				url: urltest.url,
				interval: urltest.interval,
				tolerance: urltest.tolerance
			});
		}
	}

	return groups;
}

function group_tag_list(groups) {
	let tags = [];
	for (let group in groups)
		append_unique(tags, group.tag);
	return tags;
}

function group_tags_for_regions(groups, regions) {
	let tags = [];
	for (let group in groups) {
		for (let region in regions) {
			if (group.x_shinra_region == region)
				append_unique(tags, group.tag);
		}
	}
	return tags;
}

function grouped_node_tags(groups) {
	let tags = {};
	for (let group in groups) {
		if (type(group.outbounds) != "array")
			continue;
		for (let tag in group.outbounds)
			tags[tag] = true;
	}
	return tags;
}

function unmatched_node_tag_list(nodes, matched) {
	let tags = [];
	for (let node in nodes) {
		if (!matched[node.tag])
			append_unique(tags, node.tag);
	}
	return tags;
}

function matched_node_count(nodes, matched) {
	let count = 0;
	for (let node in nodes) {
		if (matched[node.tag])
			count = count + 1;
	}
	return count;
}

function regions_from_x_rule(rule, offset) {
	let regions = [];
	for (let region in split(substr(rule, offset), ","))
		append_unique(regions, region);
	return regions;
}

export { default_region_order, region_order, source_policy_map, allowed_regions, has_region, node_matches_region, make_region_group_tag, generate_region_groups, group_tag_list, group_tags_for_regions, grouped_node_tags, unmatched_node_tag_list, matched_node_count, regions_from_x_rule };
