/**
 * Shinra | generator_validate.uc | v1.0
 */

'use strict';

function valid_region_code(code) {
	return code == "HK" || code == "TW" || code == "SG" || code == "JP" || code == "US";
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

export { validate_x_rule, validate_tun_contract, validated_main_selector_tag, validate_extension_on_object, validate_extensions, strip_extensions, validate_references };
