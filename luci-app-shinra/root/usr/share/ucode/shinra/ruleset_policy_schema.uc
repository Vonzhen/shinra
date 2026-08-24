/**
 * Shinra | ruleset_policy_schema.uc | v1.0
 */

'use strict';

function default_ruleset_policy() {
	return {
		mode: "auto",
		fetch_strategy: "direct",
		auto_update: false,
		auto_apply_after_update: false,
		update_hour: 4,
		repositories: {
			"private": "https://testingcf.jsdelivr.net/gh/miozen/sing-box-rulesets@master/rules",
			"public": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing"
		}
	};
}

function validate_fetch_strategy(strategy, label) {
	if (strategy != "direct" && strategy != "proxy")
		die(label + " must be direct or proxy");
}

function validate_ruleset_mode(mode) {
	if (mode != "remote" && mode != "auto" && mode != "local")
		die("ruleset.mode must be remote, auto, or local");
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

export { default_ruleset_policy, validate_ruleset_mode, normalize_ruleset_policy };
