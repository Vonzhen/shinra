/**
 * Shinra | subscription_policy.uc | v1.0
 */

'use strict';

import { ExecResult } from 'shinra.core.utils';

function append_unique(list, value) {
	if (type(value) != "string" || value == "")
		return;

	for (let item in list) {
		if (item == value)
			return;
	}

	push(list, value);
}

function default_region_keywords() {
	return {
		HK: [ "HK", "Hong Kong", "HongKong", "香港" ],
		TW: [ "TW", "Taiwan", "台湾", "台灣" ],
		SG: [ "SG", "Singapore", "新加坡", "狮城", "獅城" ],
		JP: [ "JP", "Japan", "日本" ],
		US: [ "US", "USA", "United States", "美国", "美國" ]
	};
}

function default_banned_keywords() {
	return "expire|expired|traffic|invalid|remaining|过期|到期|失效|无效|剩余|流量|重置|订阅|套餐|官网|用量";
}
function default_urltest_params() {
	return {
		url: "https://www.gstatic.com/generate_204",
		interval: "3m",
		tolerance: 150
	};
}

function default_ruleset_policy() {
	return {
		mode: "auto",
		fetch_strategy: "direct",
		auto_update: false,
		auto_apply_after_update: false,
		update_hour: 4,
		repositories: {
			"private": "",
			"public": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing"
		}
	};
}

function default_subscription_update_policy() {
	return {
		auto_update: false,
		update_hour: 3,
		strategy: "saved",
		run_on_boot: false
	};
}

function validate_refresh_strategy(strategy) {
	if (strategy != "direct" && strategy != "proxy")
		die("refresh_strategy must be direct or proxy");
}

function validate_fetch_strategy(strategy, label) {
	if (strategy != "direct" && strategy != "proxy")
		die(label + " must be direct or proxy");
}

function validate_subscription_update_strategy(strategy) {
	if (strategy != "saved" && strategy != "direct" && strategy != "proxy")
		die("subscription_update.strategy must be saved, direct, or proxy");
}

function validate_ruleset_mode(mode) {
	if (mode != "remote" && mode != "auto" && mode != "local")
		die("ruleset.mode must be remote, auto, or local");
}

function digit_value(ch) {
	if (ch == "0") return 0;
	if (ch == "1") return 1;
	if (ch == "2") return 2;
	if (ch == "3") return 3;
	if (ch == "4") return 4;
	if (ch == "5") return 5;
	if (ch == "6") return 6;
	if (ch == "7") return 7;
	if (ch == "8") return 8;
	if (ch == "9") return 9;
	return -1;
}

function is_digit_text(value) {
	value = "" + value;
	if (value == "")
		return false;

	for (let i = 0; i < length(value); i++) {
		let ch = substr(value, i, 1);
		if (ch < "0" || ch > "9")
			return false;
	}

	return true;
}

function parse_small_int(value) {
	value = "" + value;
	let number = 0;

	if (!is_digit_text(value))
		return -1;

	for (let i = 0; i < length(value); i++)
		number = number * 10 + digit_value(substr(value, i, 1));

	return number;
}

function ipv4_octets(host) {
	host = "" + host;
	let parts = [];
	let current = "";

	for (let i = 0; i < length(host); i++) {
		let ch = substr(host, i, 1);
		if (ch == ".") {
			push(parts, current);
			current = "";
			continue;
		}
		current = current + ch;
	}

	push(parts, current);

	if (length(parts) != 4)
		return null;

	for (let part in parts) {
		if (!is_digit_text(part))
			return null;
		let value = parse_small_int(part);
		if (value < 0 || value > 255)
			return null;
	}

	return parts;
}

function is_lan_ipv4(host) {
	let parts = ipv4_octets(host);
	if (parts == null)
		return false;

	let a = parse_small_int(parts[0]);
	let b = parse_small_int(parts[1]);

	if (a == 10)
		return true;
	if (a == 192 && b == 168)
		return true;
	if (a == 172 && b >= 16 && b <= 31)
		return true;
	return false;
}

function clone_string_array(values, label) {
	if (type(values) != "array")
		die(label + " must be an array");

	let result = [];
	for (let value in values) {
		if (type(value) != "string" || value == "")
			die(label + " must contain non-empty strings");
		append_unique(result, value);
	}
	return result;
}

function merge_string_array(base, values, label) {
	let result = clone_string_array(base, label);
	if (type(values) != "array")
		die(label + " must be an array");

	for (let value in values) {
		if (type(value) != "string" || value == "")
			die(label + " must contain non-empty strings");
		append_unique(result, value);
	}
	return result;
}

function merge_pipe_text(defaults, value) {
	let result = "" + defaults;
	if (type(value) != "string" || value == "")
		return result;

	let current = "";
	for (let i = 0; i <= length(value); i++) {
		let ch = i < length(value) ? substr(value, i, 1) : "|";
		if (ch == "|") {
			if (current != "" && index("|" + result + "|", "|" + current + "|") < 0)
				result = result + "|" + current;
			current = "";
			continue;
		}
		current = current + ch;
	}

	return result;
}

function normalize_region_keywords(raw) {
	let defaults = default_region_keywords();
	let result = {};
	let count = 0;

	for (let region in defaults) {
		result[region] = clone_string_array(defaults[region], "region_keywords." + region);
		count = count + 1;
	}

	if (type(raw) != "object" || raw == null || type(raw) == "array")
		return result;

	for (let region in raw) {
		if (type(region) != "string" || region == "")
			die("region keyword key must be a non-empty string");
		if (defaults[region])
			result[region] = merge_string_array(defaults[region], raw[region], "region_keywords." + region);
		else
			result[region] = clone_string_array(raw[region], "region_keywords." + region);
		if (!defaults[region])
			count = count + 1;
	}

	if (count == 0)
		die("region_keywords must not be empty");

	return result;
}

function region_keys(region_keywords) {
	let regions = [];
	for (let region in region_keywords)
		append_unique(regions, region);
	return regions;
}

function has_region(regions, region) {
	for (let item in regions) {
		if (item == region)
			return true;
	}
	return false;
}

function normalize_allowed_regions(source, regions) {
	let allowed = [];

	if (type(source.allowed_regions) == "array") {
		for (let region in source.allowed_regions) {
			if (!has_region(regions, region))
				die("Unsupported subscription source region: " + region);
			append_unique(allowed, region);
		}
		return allowed;
	}

	for (let region in regions)
		append_unique(allowed, region);
	return allowed;
}

function normalize_urltest_params(raw) {
	let defaults = default_urltest_params();
	let result = {
		url: defaults.url,
		interval: defaults.interval,
		tolerance: defaults.tolerance
	};

	if (type(raw) == "object" && raw != null && type(raw) != "array") {
		if (type(raw.url) == "string" && raw.url != "")
			result.url = raw.url;
		if (type(raw.interval) == "string" && raw.interval != "")
			result.interval = raw.interval;
		if (type(raw.tolerance) == "int" || type(raw.tolerance) == "double")
			result.tolerance = raw.tolerance;
	}

	if (substr(result.url, 0, 7) != "http://" && substr(result.url, 0, 8) != "https://")
		die("urltest_params.url must start with http:// or https://");
	if (index(result.url, "://x.test/") >= 0 || result.url == "http://x.test" || result.url == "https://x.test")
		result.url = defaults.url;
	if (type(result.interval) != "string" || result.interval == "")
		die("urltest_params.interval must be a non-empty string");
	if (result.tolerance < 0)
		die("urltest_params.tolerance must not be negative");

	return result;
}

function normalize_repository_url(url, label, allow_empty) {
	if (type(url) != "string" || url == "") {
		if (allow_empty)
			return "";
		die(label + " must be a non-empty URL");
	}

	if (substr(url, 0, 7) != "http://" && substr(url, 0, 8) != "https://")
		die(label + " must start with http:// or https://");

	return url;
}

function normalize_ruleset_policy(raw) {
	let defaults = default_ruleset_policy();
	let result = {
		mode: defaults.mode,
		fetch_strategy: defaults.fetch_strategy,
		auto_update: defaults.auto_update,
		auto_apply_after_update: defaults.auto_apply_after_update,
		update_hour: defaults.update_hour,
		repositories: {
			"private": defaults.repositories["private"],
			"public": defaults.repositories["public"]
		}
	};

	if (type(raw) == "object" && raw != null && type(raw) != "array") {
		if (type(raw.mode) == "string" && raw.mode != "")
			result.mode = raw.mode;
		if (type(raw.fetch_strategy) == "string" && raw.fetch_strategy != "")
			result.fetch_strategy = raw.fetch_strategy;
		result.auto_update = raw.auto_update == true ? true : false;
		result.auto_apply_after_update = raw.auto_apply_after_update == true ? true : false;
		if (type(raw.update_hour) == "int")
			result.update_hour = raw.update_hour;
		if (type(raw.repositories) == "object" && raw.repositories != null && type(raw.repositories) != "array") {
			if (type(raw.repositories["private"]) == "string")
				result.repositories["private"] = raw.repositories["private"];
			if (type(raw.repositories["public"]) == "string" && raw.repositories["public"] != "")
				result.repositories["public"] = raw.repositories["public"];
		}
	}

	validate_ruleset_mode(result.mode);
	validate_fetch_strategy(result.fetch_strategy, "ruleset.fetch_strategy");
	if (result.update_hour < 0 || result.update_hour > 23)
		die("ruleset.update_hour must be between 0 and 23");

	result.repositories["private"] = normalize_repository_url(result.repositories["private"], "ruleset.repositories.private", true);
	result.repositories["public"] = normalize_repository_url(result.repositories["public"], "ruleset.repositories.public", false);

	return result;
}

function normalize_subscription_update_policy(raw) {
	let defaults = default_subscription_update_policy();
	let result = {
		auto_update: defaults.auto_update,
		update_hour: defaults.update_hour,
		strategy: defaults.strategy,
		run_on_boot: defaults.run_on_boot
	};

	if (type(raw) == "object" && raw != null && type(raw) != "array") {
		result.auto_update = raw.auto_update == true ? true : false;
		result.run_on_boot = raw.run_on_boot == true ? true : false;
		if (type(raw.update_hour) == "int")
			result.update_hour = raw.update_hour;
		if (type(raw.strategy) == "string" && raw.strategy != "")
			result.strategy = raw.strategy;
	}

	validate_subscription_update_strategy(result.strategy);
	if (result.update_hour < 0 || result.update_hour > 23)
		die("subscription_update.update_hour must be between 0 and 23");

	return result;
}

function validate_source_url(url) {
	if (type(url) != "string" || url == "")
		die("Subscription URL must be a non-empty string");

	if (substr(url, 0, 7) != "http://" && substr(url, 0, 8) != "https://")
		die("Subscription URL must start with http:// or https://");
}

function validate_source_id(id) {
	if (type(id) != "string" || id == "")
		die("subscription source id must be a non-empty string");

	for (let i = 0; i < length(id); i++) {
		let ch = substr(id, i, 1);
		let ok = (ch >= "a" && ch <= "z") ||
			(ch >= "A" && ch <= "Z") ||
			(ch >= "0" && ch <= "9") ||
			ch == "." || ch == "_" || ch == "-";
		if (!ok)
			die("Invalid subscription source id: " + id);
	}
}

function source_has_id(source) {
	return type(source) == "object" && source != null && type(source) != "array" &&
		type(source.id) == "string" && source.id != "";
}

function source_id_material(index, attempt) {
	let result = ExecResult("subscription-source-id", [ "sh", "-c", "cat /proc/sys/kernel/random/uuid 2>/dev/null || printf '%s-%s' \"$(date +%s%N 2>/dev/null || date +%s)\" \"$$\"" ]);
	let material = result.code == 0 && type(result.stdout) == "string" && result.stdout != "" ? result.stdout : "";
	return material + "-" + index + "-" + attempt;
}

function generated_source_id(index, attempt) {
	let material = source_id_material(index, attempt);
	let body = "";

	for (let i = 0; i < length(material); i++) {
		let ch = substr(material, i, 1);
		if ((ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9"))
			body = body + ch;
		if (length(body) >= 12)
			break;
	}

	if (body == "")
		body = "" + index + attempt;

	return "src-" + body;
}

function reserve_source_ids(config) {
	let reserved = {};

	for (let source in config.sources) {
		if (!source_has_id(source))
			continue;
		validate_source_id(source.id);
		if (reserved[source.id])
			die("Duplicated subscription source id: " + source.id);
		reserved[source.id] = true;
	}

	return reserved;
}

function unique_generated_source_id(index, seen_ids, reserved_ids) {
	let id = "";
	let attempt = 1;

	while (attempt <= 16) {
		id = generated_source_id(index, attempt);
		if (!seen_ids[id] && !reserved_ids[id])
			return id;
		attempt = attempt + 1;
	}

	die("Failed to generate unique subscription source id");
}

function normalize_source(source, regions, index, seen_ids, reserved_ids) {
	if (type(source) != "object" || source == null || type(source) == "array")
		die("subscription source must be an object");
	if (type(source.name) != "string" || source.name == "")
		die("subscription source name must be a non-empty string");

	validate_source_url(source.url);

	let id = source_has_id(source) ? source.id : unique_generated_source_id(index, seen_ids, reserved_ids);
	validate_source_id(id);

	return {
		id: id,
		name: source.name,
		url: source.url,
		enabled: source.enabled == false ? false : true,
		allowed_regions: normalize_allowed_regions(source, regions)
	};
}

function normalize_subscriptions_policy(config) {
	if (type(config) != "object" || config == null || type(config) == "array")
		die("subscriptions root must be an object");
	if (config.schema_version != 1)
		die("subscriptions schema_version must be 1");
	if (type(config.sources) != "array")
		die("subscriptions sources must be an array");

	let strategy = type(config.refresh_strategy) == "string" && config.refresh_strategy != "" ? config.refresh_strategy : "direct";
	validate_refresh_strategy(strategy);

	let keywords = normalize_region_keywords(config.region_keywords);
	let regions = region_keys(keywords);
	let reserved_ids = reserve_source_ids(config);
	let seen_ids = {};
	let seen_names = {};
	let sources = [];
	let source_index = 0;

	for (let source in config.sources) {
		let normalized = normalize_source(source, regions, source_index, seen_ids, reserved_ids);
		if (seen_ids[normalized.id])
			die("Duplicated subscription source id: " + normalized.id);
		if (seen_names[normalized.name])
			die("Duplicated subscription source name: " + normalized.name);
		seen_ids[normalized.id] = true;
		seen_names[normalized.name] = true;
		push(sources, normalized);
		source_index = source_index + 1;
	}

	return {
		schema_version: 1,
		refresh_strategy: strategy,
		region_keywords: keywords,
		region_keys: regions,
		banned_keywords: merge_pipe_text(default_banned_keywords(), config.banned_keywords),
		urltest_params: normalize_urltest_params(config.urltest_params),
		subscription_update: normalize_subscription_update_policy(config.subscription_update),
		ruleset: normalize_ruleset_policy(config.ruleset),
		sources: sources
	};
}

export { default_region_keywords, default_banned_keywords, default_urltest_params, default_ruleset_policy, default_subscription_update_policy, validate_refresh_strategy, validate_fetch_strategy, normalize_subscriptions_policy };

