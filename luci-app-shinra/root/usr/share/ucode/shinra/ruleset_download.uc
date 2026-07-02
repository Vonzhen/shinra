/**
 * Shinra | ruleset_download.uc | v1.0
 */

'use strict';

import { mkdir, readfile, stat, unlink } from 'fs';
import { PATH } from 'shinra.core.constants';
import { file_exists } from 'shinra.core.utils';
import { fetch_file } from 'shinra.resource_fetch';
import { resource_promote_file } from 'shinra.core.resource';

function starts_with(value, prefix) {
	value = "" + value;
	prefix = "" + prefix;
	return substr(value, 0, length(prefix)) == prefix;
}

function trim_trailing_slash(value) {
	value = "" + value;
	while (length(value) > 0 && substr(value, length(value) - 1, 1) == "/")
		value = substr(value, 0, length(value) - 1);
	return value;
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

function ensure_rule_dirs() {
	if (!file_exists(PATH.RULE_DIR) && !mkdir(PATH.RULE_DIR, 0700))
		die("Failed to create " + PATH.RULE_DIR);
	let tmp_dir = PATH.RULE_DIR + "/.tmp";
	if (!file_exists(PATH.RUN_DIR) && !mkdir(PATH.RUN_DIR, 0700))
		die("Failed to create " + PATH.RUN_DIR);
	if (!file_exists(tmp_dir) && !mkdir(tmp_dir, 0700))
		die("Failed to create " + tmp_dir);
}

function rule_name_parts(tag) {
	if (starts_with(tag, "geosite-"))
		return {
			kind: "geosite",
			name: substr(tag, 8),
			standard: true
		};
	if (starts_with(tag, "geoip-"))
		return {
			kind: "geoip",
			name: substr(tag, 6),
			standard: true
		};
	return {
		kind: "",
		name: tag,
		standard: false
	};
}

function ruleset_urls(entry, policy) {
	let urls = [];
	let repos = policy.repositories || {};
	let private_repo = trim_trailing_slash(repos["private"] || "");
	let public_repo = trim_trailing_slash(repos["public"] || "");
	let parts = rule_name_parts(entry.tag);

	if (private_repo != "")
		append_unique(urls, private_repo + "/" + entry.tag + ".srs");

	if (public_repo != "") {
		if (parts.standard) {
			append_unique(urls, public_repo + "/geo/" + parts.kind + "/" + parts.name + ".srs");
			append_unique(urls, public_repo + "/geo-lite/" + parts.kind + "/" + parts.name + ".srs");
		} else {
			append_unique(urls, public_repo + "/rules/" + entry.tag + ".srs");
			append_unique(urls, public_repo + "/" + entry.tag + ".srs");
		}
	}

	append_unique(urls, entry.source_url);
	return urls;
}

function direct_fetch_rule(trace_id, url, tmp_path, strategy) {
	unlink(tmp_path);
	strategy = strategy == "proxy" ? "proxy" : "direct";
	let result = fetch_file(trace_id, url, tmp_path, strategy, { timeout_sec: 15, min_bytes: 20 });
	if (!result.ok) {
		unlink(tmp_path);
		return {
			ok: false,
			error: "fetch failed: strategy=" + strategy + " " + result.error + " exit=" + result.exit_code + " stderr=" + result.stderr
		};
	}

	let info = stat(tmp_path);
	if (type(info) != "object" || info == null || info.size <= 0) {
		unlink(tmp_path);
		return {
			ok: false,
			error: "Downloaded file is empty or too small"
		};
	}

	return {
		ok: true,
		size: info.size || 0
	};
}

function same_file_content(left_path, right_path) {
	let left = readfile(left_path);
	let right = readfile(right_path);
	return left != null && right != null && left == right;
}

function atomic_swap_rule(tmp_path, final_path) {
	return resource_promote_file(tmp_path, final_path, {
		stage_suffix: ".stage",
		backup_suffix: ".bak",
		stage_error: "Failed to stage rule file: ",
		backup_error: "Failed to backup rule file: ",
		promote_error: "Failed to deploy rule file: "
	});
}

export { ensure_rule_dirs, ruleset_urls, direct_fetch_rule, same_file_content, atomic_swap_rule };
