/**
 * Shinra | generator.uc | v1.0
 */

'use strict';

import { stat } from 'fs';
import { PATH, BIN, CONTROL_PLANE_PROXY } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { read_text, write_runtime_text_atomic, parse_json_object, ensure_runtime_dir, file_exists, json_stringify, ExecResult } from 'shinra.core.utils';
import { normalize_subscriptions_policy } from 'shinra.subscription_policy';
import { zashboard_panel_policy } from 'shinra.zashboard';

function parse_profile() {
	let profile = parse_json_object(read_text(PATH.PROFILE), "Profile");
	if (type(profile.outbounds) != "array")
		die("Profile must contain outbounds array");
	return profile;
}

function parse_node_snapshot() {
	let snapshot = parse_json_object(read_text(PATH.NODE_SNAPSHOT), "Node Snapshot");
	if (snapshot.schema_version != 1)
		die("Node Snapshot schema_version must be 1");
	if (snapshot.source != "sub-store")
		die("Node Snapshot source must be sub-store");
	if (type(snapshot.outbounds) != "array")
		die("Node Snapshot outbounds must be an array");
	return snapshot;
}

function parse_subscriptions_policy() {
	let config = parse_json_object(read_text(PATH.SUBSCRIPTIONS), "Subscriptions");
	return normalize_subscriptions_policy(config);
}

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

function upper_text(value) {
	let text = "" + value;
	text = replace(text, "a", "A");
	text = replace(text, "b", "B");
	text = replace(text, "c", "C");
	text = replace(text, "d", "D");
	text = replace(text, "e", "E");
	text = replace(text, "f", "F");
	text = replace(text, "g", "G");
	text = replace(text, "h", "H");
	text = replace(text, "i", "I");
	text = replace(text, "j", "J");
	text = replace(text, "k", "K");
	text = replace(text, "l", "L");
	text = replace(text, "m", "M");
	text = replace(text, "n", "N");
	text = replace(text, "o", "O");
	text = replace(text, "p", "P");
	text = replace(text, "q", "Q");
	text = replace(text, "r", "R");
	text = replace(text, "s", "S");
	text = replace(text, "t", "T");
	text = replace(text, "u", "U");
	text = replace(text, "v", "V");
	text = replace(text, "w", "W");
	text = replace(text, "x", "X");
	text = replace(text, "y", "Y");
	text = replace(text, "z", "Z");
	return text;
}

function tag_contains_keyword(tag_upper, keyword) {
	if (type(keyword) != "string" || keyword == "")
		return false;
	return index(tag_upper, upper_text(keyword)) >= 0;
}

function tag_matches_banned_keywords(tag, banned_keywords) {
	let tag_upper = upper_text(tag);
	for (let keyword in split(banned_keywords || "", "|")) {
		if (tag_contains_keyword(tag_upper, keyword))
			return true;
	}
	return false;
}

function is_digit(ch) {
	return ch == "0" || ch == "1" || ch == "2" || ch == "3" || ch == "4" || ch == "5" || ch == "6" || ch == "7" || ch == "8" || ch == "9";
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

function append_unique(list, value) {
	if (type(value) != "string" || value == "")
		return;

	for (let item in list) {
		if (item == value)
			return;
	}

	push(list, value);
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

function valid_region_code(code) {
	return code == "HK" || code == "TW" || code == "SG" || code == "JP" || code == "US";
}

function default_region_order() {
	return [ "HK", "TW", "SG", "JP", "US" ];
}

function region_order(config) {
	if (type(config) == "object" && config != null && type(config.region_keys) == "array")
		return config.region_keys;
	return default_region_order();
}

function validate_region_list(text, rule) {
	if (type(text) != "string" || text == "")
		die("x_rule region list is empty: " + rule);

	let regions = split(text, ",");
	for (let region in regions) {
		if (!valid_region_code(region))
			die("Unsupported x_rule region: " + region);
	}
}

function validate_x_rule(rule) {
	if (type(rule) != "string" || rule == "")
		die("x_rule must be a non-empty string");

	if (rule == "main" || rule == "keep" || rule == "all_regions" || rule == "direct_only")
		return;

	if (substr(rule, 0, 7) == "region:") {
		validate_region_list(substr(rule, 7), rule);
		return;
	}

	if (substr(rule, 0, 14) == "region+direct:") {
		validate_region_list(substr(rule, 14), rule);
		return;
	}

	die("Unsupported x_rule: " + rule);
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

function make_region_group_tag(region, source_name) {
	return region + "-" + source_name;
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
			if (substr(group.tag, 0, length(region) + 1) == region + "-")
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

function direct_outbound_tag(profile) {
	for (let outbound in profile.outbounds) {
		if (type(outbound) == "object" && outbound != null && outbound.type == "direct" && type(outbound.tag) == "string" && outbound.tag != "")
			return outbound.tag;
	}
	return "";
}

function tun_contract_fail(message) {
	die("TUN_CONTRACT: " + message);
}

function validate_tun_contract(profile) {
	if (type(profile.inbounds) != "array")
		tun_contract_fail("Profile must contain inbounds array");

	let tun_count = 0;
	let tun = null;

	for (let inbound in profile.inbounds) {
		if (type(inbound) != "object" || inbound == null)
			continue;

		if (inbound.type == "redirect" || inbound.type == "tproxy")
			tun_contract_fail("redirect/tproxy inbounds are not supported");

		if (inbound.type != "tun")
			continue;

		tun_count = tun_count + 1;
		tun = inbound;
	}

	if (tun_count == 0)
		tun_contract_fail("Profile must contain tun-in inbound");
	if (tun_count > 1)
		tun_contract_fail("Profile must contain exactly one tun inbound");

	if (tun.tag != "tun-in")
		tun_contract_fail("tun inbound tag must be tun-in");
	if (type(tun.interface_name) != "string" || tun.interface_name == "")
		tun_contract_fail("tun-in interface_name must be set");
	if (tun.auto_route != true)
		tun_contract_fail("tun-in auto_route must be true");
	if (tun.strict_route != true)
		tun_contract_fail("tun-in strict_route must be true");
	if (tun.auto_redirect != true)
		tun_contract_fail("tun-in auto_redirect must be true");
	if (tun.dns_mode != "hijack")
		tun_contract_fail("tun-in dns_mode must be hijack");
	if (tun.stack != "system" && tun.stack != "mixed")
        tun_contract_fail("tun-in stack must be system or mixed");

	if (type(profile.route) != "object" || profile.route == null || profile.route.auto_detect_interface != true)
		tun_contract_fail("route.auto_detect_interface must be true");
}

function validated_main_selector_tag(profile) {
	let count = 0;
	let tag = "";

	for (let outbound in profile.outbounds) {
		if (type(outbound) != "object" || outbound == null || outbound.type != "selector" || outbound.x_rule != "main")
			continue;

		count = count + 1;
		if (type(outbound.tag) != "string" || outbound.tag == "")
			die("Profile main selector must have a non-empty tag");
		tag = outbound.tag;
	}

	if (count != 1)
		die("Profile must contain exactly one selector outbound with x_rule main");

	return tag;
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

function validate_extension_on_object(obj) {
	for (let key in obj) {
		if (substr(key, 0, 2) != "x_")
			continue;

		if (key != "x_rule")
			die("Unknown Profile extension field: " + key);

		if (obj.type != "selector")
			die("x_rule is only allowed on selector outbounds");

		validate_x_rule(obj.x_rule);
	}
}

function validate_extensions(value) {
	if (type(value) == "array") {
		for (let item in value)
			validate_extensions(item);
		return;
	}

	if (type(value) != "object" || value == null)
		return;

	validate_extension_on_object(value);
	for (let key in value)
		validate_extensions(value[key]);
}

function strip_extensions(value) {
	let stripped = 0;

	if (type(value) == "array") {
		for (let item in value)
			stripped = stripped + strip_extensions(item);
		return stripped;
	}

	if (type(value) != "object" || value == null)
		return stripped;

	let remove = [];
	for (let key in value) {
		if (substr(key, 0, 2) == "x_")
			push(remove, key);
		else
			stripped = stripped + strip_extensions(value[key]);
	}

	for (let key in remove) {
		delete value[key];
		stripped = stripped + 1;
	}

	return stripped;
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

function validate_references(profile) {
	let tags = {};
	for (let outbound in profile.outbounds) {
		if (type(outbound) == "object" && outbound != null && type(outbound.tag) == "string" && outbound.tag != "")
			tags[outbound.tag] = true;
	}

	for (let outbound in profile.outbounds) {
		if (type(outbound) != "object" || outbound == null || type(outbound.outbounds) != "array")
			continue;

		for (let tag in outbound.outbounds) {
			if (!tags[tag])
				die("Invalid outbound reference: " + outbound.tag + " -> " + tag);
		}
	}

	if (type(profile.dns) == "object" && profile.dns != null && type(profile.dns.servers) == "array") {
		for (let server in profile.dns.servers) {
			if (type(server) == "object" && server != null && type(server.detour) == "string" && server.detour != "" && !tags[server.detour])
				die("Invalid DNS detour reference: " + server.tag + " -> " + server.detour);
		}
	}
}

function local_ruleset_path(tag) {
	return PATH.RULE_DIR + "/" + tag + ".srs";
}

function local_ruleset_exists(tag) {
	let info = stat(local_ruleset_path(tag));
	return type(info) == "object" && info != null && info.size > 0;
}

function local_ruleset_entry(tag, original) {
	let format = "binary";
	if (type(original.format) == "string" && original.format != "")
		format = original.format;

	return {
		type: "local",
		tag: tag,
		format: format,
		path: local_ruleset_path(tag)
	};
}

function localize_rulesets(profile, policy) {
	let mode = "auto";
	if (type(policy) == "object" && policy != null && type(policy.ruleset) == "object" && policy.ruleset != null && type(policy.ruleset.mode) == "string" && policy.ruleset.mode != "")
		mode = policy.ruleset.mode;

	let result = {
		mode: mode,
		total: 0,
		localized: 0,
		preserved_remote: 0,
		missing: 0
	};

	if (mode != "remote" && mode != "auto" && mode != "local")
		die("Unsupported Rule Set mode: " + mode);

	if (type(profile.route) != "object" || profile.route == null || type(profile.route.rule_set) != "array")
		return result;

	let next = [];
	for (let entry in profile.route.rule_set) {
		if (type(entry) != "object" || entry == null || type(entry) == "array" || type(entry.tag) != "string" || entry.tag == "") {
			push(next, entry);
			continue;
		}

		result.total = result.total + 1;
		if (mode == "remote") {
			push(next, entry);
			if (entry.type == "remote")
				result.preserved_remote = result.preserved_remote + 1;
			continue;
		}

		if (local_ruleset_exists(entry.tag)) {
			push(next, local_ruleset_entry(entry.tag, entry));
			result.localized = result.localized + 1;
			continue;
		}

		result.missing = result.missing + 1;
		if (mode == "local")
			die("Required local Rule Set missing: " + entry.tag + " -> " + local_ruleset_path(entry.tag));

		push(next, entry);
		if (entry.type == "remote")
			result.preserved_remote = result.preserved_remote + 1;
	}

	profile.route.rule_set = next;
	return result;
}

function ensure_object_field(parent, key) {
	if (type(parent[key]) != "object" || parent[key] == null || type(parent[key]) == "array")
		parent[key] = {};
	return parent[key];
}

function existing_clash_api(profile) {
	if (type(profile.experimental) != "object" || profile.experimental == null || type(profile.experimental) == "array")
		return null;
	if (type(profile.experimental.clash_api) != "object" || profile.experimental.clash_api == null || type(profile.experimental.clash_api) == "array")
		return null;
	if (type(profile.experimental.clash_api.external_controller) != "string" || profile.experimental.clash_api.external_controller == "")
		return null;
	return profile.experimental.clash_api;
}

function apply_panel_api_policy(profile) {
	let policy = zashboard_panel_policy();
	let existing = existing_clash_api(profile);
	let result = {
		enabled: policy.enabled == true || existing != null ? true : false,
		external_controller: "",
		secret_configured: false,
		source: ""
	};

	if (existing != null) {
		result.external_controller = existing.external_controller;
		result.secret_configured = type(existing.secret) == "string" && existing.secret != "";
		result.source = "profile";
		return result;
	}

	if (!result.enabled)
		return result;

	let experimental = ensure_object_field(profile, "experimental");
	let clash_api = ensure_object_field(experimental, "clash_api");
	clash_api.external_controller = policy.external_controller;
	clash_api.secret = policy.secret;

	result.external_controller = policy.external_controller;
	result.secret_configured = policy.secret != "";
	result.source = "panel";
	return result;
}

function ensure_control_plane_proxy_inbound(profile) {
	let result = {
		inserted: false,
		existing: false,
		tag: CONTROL_PLANE_PROXY.TAG,
		listen: CONTROL_PLANE_PROXY.LISTEN,
		port: CONTROL_PLANE_PROXY.PORT
	};

	if (type(profile.inbounds) != "array")
		profile.inbounds = [];

	for (let inbound in profile.inbounds) {
		if (type(inbound) != "object" || inbound == null)
			continue;

		if (inbound.tag == CONTROL_PLANE_PROXY.TAG) {
			inbound.type = "mixed";
			inbound.listen = CONTROL_PLANE_PROXY.LISTEN;
			inbound.listen_port = CONTROL_PLANE_PROXY.PORT;
			result.existing = true;
			return result;
		}

		if (inbound.listen == CONTROL_PLANE_PROXY.LISTEN && int(inbound.listen_port || 0) == CONTROL_PLANE_PROXY.PORT)
			die("Control-plane proxy endpoint is already used by inbound: " + (inbound.tag || ""));
	}

	push(profile.inbounds, {
		type: "mixed",
		tag: CONTROL_PLANE_PROXY.TAG,
		listen: CONTROL_PLANE_PROXY.LISTEN,
		listen_port: CONTROL_PLANE_PROXY.PORT
	});
	result.inserted = true;
	return result;
}

function generate_candidate(trace_id, req) {
	try {
		let profile = parse_profile();
		let snapshot = parse_node_snapshot();
		let subscriptions = parse_subscriptions_policy();
		validate_extensions(profile);

		let profile_tags = collect_profile_tags(profile);
		let normalized = normalized_nodes(snapshot, profile_tags, subscriptions);
		let nodes = normalized.nodes;
		let node_tags = collect_node_tags(nodes);
		let groups = generate_region_groups(subscriptions, nodes, profile_tags, node_tags);
		let matched_nodes = grouped_node_tags(groups);
		let unmatched_nodes = unmatched_node_tag_list(nodes, matched_nodes);
		let matched_count = matched_node_count(nodes, matched_nodes);
		let unmatched_count = length(unmatched_nodes);
		let injected = inject_selectors(profile, nodes, groups);
		let main_options = main_selector_option_count(profile);
		merge_outbounds(profile, groups, nodes);
		let ruleset = localize_rulesets(profile, subscriptions);
		let panel_api = apply_panel_api_policy(profile);
		let control_proxy = ensure_control_plane_proxy_inbound(profile);
		validate_tun_contract(profile);
		let stripped = strip_extensions(profile);
		validate_references(profile);

		ensure_runtime_dir();
		let content = json_stringify(profile);
		write_runtime_text_atomic(PATH.CANDIDATE_CONFIG, content + "\n");

		return Success({
			path: PATH.CANDIDATE_CONFIG,
			node_count: length(nodes),
			skipped_banned: normalized.skipped_banned,
			skipped_high_rate: normalized.skipped_high_rate,
			generated_groups: length(groups),
			matched_node_count: matched_count,
			unmatched_node_count: unmatched_count,
			main_selector_options: main_options,
			injected_selectors: injected,
			ruleset_mode: ruleset.mode,
			ruleset_total: ruleset.total,
			ruleset_localized: ruleset.localized,
			ruleset_preserved_remote: ruleset.preserved_remote,
			ruleset_missing: ruleset.missing,
			panel_api_enabled: panel_api.enabled,
			panel_api_external_controller: panel_api.external_controller,
			panel_api_secret_configured: panel_api.secret_configured,
			panel_api_source: panel_api.source,
			control_proxy_inserted: control_proxy.inserted,
			control_proxy_existing: control_proxy.existing,
			control_proxy_tag: control_proxy.tag,
			control_proxy_listen: control_proxy.listen,
			control_proxy_port: control_proxy.port,
			stripped_extensions: stripped,
			outbounds: length(profile.outbounds)
		}, 200, trace_id, "Candidate generated");
	} catch (e) {
		let err = "" + e;
		if (substr(err, 0, 13) == "TUN_CONTRACT:")
			return Fail(ERR.E_TUN_CONTRACT_FAILED, "Profile TUN contract failed", trace_id, substr(err, 13));
		return Fail(ERR.E_GENERATE_FAILED, "Failed to generate Candidate", trace_id, err);
	}
}

function check_candidate(trace_id, req) {
	try {
		if (!file_exists(PATH.CANDIDATE_CONFIG))
			return Fail(ERR.E_CANDIDATE_NOT_FOUND, "Candidate config not found", trace_id, PATH.CANDIDATE_CONFIG);

		let result = ExecResult(trace_id, [ BIN.SING_BOX, "check", "-c", PATH.CANDIDATE_CONFIG ]);
		if (result.code != 0)
			return Fail(ERR.E_CANDIDATE_CHECK_FAILED, "Candidate check failed", trace_id, result.stderr || result.stdout);

		return Success({
			path: PATH.CANDIDATE_CONFIG,
			stdout: result.stdout,
			stderr: result.stderr
		}, 200, trace_id, "Candidate check passed");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_CANDIDATE_CHECK_FAILED, "Candidate check crashed", trace_id, err);
	}
}

export { generate_candidate, check_candidate };
