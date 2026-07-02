/**
 * Shinra | generator_rulesets.uc | v1.0
 */

'use strict';

import { stat } from 'fs';
import { PATH } from 'shinra.core.constants';

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

export { local_ruleset_path, local_ruleset_exists, local_ruleset_entry, localize_rulesets };
