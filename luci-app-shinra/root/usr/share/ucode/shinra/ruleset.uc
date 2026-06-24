/**
 * Shinra | ruleset.uc | v1.0
 */

'use strict';

import { mkdir, rename, stat, unlink } from 'fs';
import { PATH, BIN } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { acquire, release } from 'shinra.core.lock';
import { normalize_subscriptions_policy } from 'shinra.subscription_policy';
import { read_text, write_text_atomic, parse_json_object, request_content, request_keys, json_stringify, file_exists, ExecResult } from 'shinra.core.utils';
import { send_telegram_best_effort } from 'shinra.notify';

function starts_with(value, prefix) {
	value = "" + value;
	prefix = "" + prefix;
	return substr(value, 0, length(prefix)) == prefix;
}

function subscriptions_config() {
	return parse_json_object(read_text(PATH.SUBSCRIPTIONS), "Subscriptions");
}

function normalized_subscriptions_config() {
	return normalize_subscriptions_policy(subscriptions_config());
}

function normalize_ruleset_policy_content(content) {
	if (content == "")
		die("Missing Rule Set policy content");

	let wrapper = {
		schema_version: 1,
		sources: [],
		ruleset: parse_json_object(content, "Rule Set policy")
	};
	let normalized = normalize_subscriptions_policy(wrapper);
	return normalized.ruleset;
}

function apply_ruleset_policy(config, policy) {
	let normalized = normalize_subscriptions_policy({
		schema_version: 1,
		sources: [],
		ruleset: policy
	});
	config.ruleset = normalized.ruleset;
	return normalize_subscriptions_policy(config);
}

function source_path(source) {
	if (source == "profile")
		return PATH.PROFILE;
	if (source == "candidate")
		return PATH.CANDIDATE_CONFIG;
	if (source == "runtime")
		return PATH.RUNTIME_CONFIG;
	die("Unsupported ruleset inventory source: " + source);
}

function select_source(req) {
	let source = "auto";
	if (type(req) == "object" && req != null && type(req.source) == "string" && req.source != "")
		source = req.source;

	if (source == "auto") {
		if (file_exists(PATH.RUNTIME_CONFIG))
			return {
				requested: source,
				source: "runtime",
				path: PATH.RUNTIME_CONFIG,
				exists: true
			};
		if (file_exists(PATH.CANDIDATE_CONFIG))
			return {
				requested: source,
				source: "candidate",
				path: PATH.CANDIDATE_CONFIG,
				exists: true
			};
		return {
			requested: source,
			source: "profile",
			path: PATH.PROFILE,
			exists: file_exists(PATH.PROFILE)
		};
	}

	if (source != "profile" && source != "candidate" && source != "runtime")
		die("ruleset_inventory source must be auto, profile, candidate, or runtime");

	return {
		requested: source,
		source: source,
		path: source_path(source),
		exists: file_exists(source_path(source))
	};
}

function url_host(url) {
	if (type(url) != "string" || url == "")
		return "";

	let value = url;
	let start = 0;
	let scheme = index(value, "://");
	if (scheme >= 0)
		start = scheme + 3;

	let rest = substr(value, start);
	let slash = index(rest, "/");
	if (slash >= 0)
		return substr(rest, 0, slash);

	return rest;
}

function strip_query(value) {
	if (type(value) != "string")
		return "";
	let q = index(value, "?");
	if (q >= 0)
		return substr(value, 0, q);
	return value;
}

function basename(path) {
	let value = "" + path;
	let last = -1;

	for (let i = 0; i < length(value); i = i + 1) {
		if (substr(value, i, 1) == "/")
			last = i;
	}

	return substr(value, last + 1);
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

function redacted_url(url) {
	if (type(url) != "string" || url == "")
		return "";

	let host = url_host(url);
	let name = basename(strip_query(url));
	if (host == "")
		return "";
	if (name == "")
		return "https://" + host + "/...";
	return "https://" + host + "/.../" + name;
}

function file_metadata(path) {
	let info = stat(path);
	if (type(info) != "object" || info == null)
		return {
			exists: false,
			size: 0,
			mtime: 0
		};

	return {
		exists: true,
		size: info.size || 0,
		mtime: info.mtime || 0
	};
}

function is_managed_rule_path(path) {
	if (type(path) != "string" || path == "")
		return false;
	if (path == PATH.RULE_DIR)
		return true;
	return starts_with(path, PATH.RULE_DIR + "/");
}

function entry_errors(entry, duplicate) {
	let errors = [];

	if (duplicate)
		push(errors, "duplicate_tag");
	if (entry.type != "local" && entry.type != "remote" && entry.type != "")
		push(errors, "unsupported_type");
	if (entry.format != "binary" && entry.format != "")
		push(errors, "unsupported_format");
	if (entry.path != "" && !entry.managed_root)
		push(errors, "path_outside_managed_root");
	if (entry.path != "" && !entry.exists)
		push(errors, "missing_file");
	if (entry.referenced_count == 0)
		push(errors, "unreferenced_declaration");

	return errors;
}

function normalize_declaration(item) {
	if (type(item) != "object" || item == null || type(item) == "array")
		return null;
	if (type(item.tag) != "string" || item.tag == "")
		return null;

	let path = type(item.path) == "string" ? item.path : "";
	let url = type(item.url) == "string" ? item.url : "";
	let meta = path != "" ? file_metadata(path) : {
		exists: false,
		size: 0,
		mtime: 0
	};

	return {
		tag: item.tag,
		type: type(item.type) == "string" ? item.type : "",
		format: type(item.format) == "string" ? item.format : "",
		path: path,
		source_url: url,
		url_present: url != "",
		url_host: url_host(url),
		url_redacted: redacted_url(url),
		download_detour: type(item.download_detour) == "string" ? item.download_detour : "",
		exists: meta.exists,
		size: meta.size,
		mtime: meta.mtime,
		managed_root: path != "" && is_managed_rule_path(path),
		referenced_count: 0,
		reference_scopes: [],
		reference_indexes: [],
		referenced_by: [],
		errors: []
	};
}

function collect_declarations(config) {
	let declarations = [];
	if (type(config.route) != "object" || config.route == null)
		return declarations;
	if (type(config.route.rule_set) != "array")
		return declarations;

	for (let item in config.route.rule_set) {
		let entry = normalize_declaration(item);
		if (entry != null)
			push(declarations, entry);
	}

	return declarations;
}

function push_reference(references, tag, scope, index_value, declarations) {
	if (type(tag) != "string" || tag == "")
		return;

	let exists = declarations[tag] == true;
	let errors = [];
	if (!exists)
		push(errors, "reference_missing_declaration");

	push(references, {
		tag: tag,
		scope: scope,
		index: index_value,
		exists_in_declarations: exists,
		errors: errors
	});
}

function collect_rule_reference(references, value, scope, index_value, declarations) {
	if (type(value) == "string") {
		push_reference(references, value, scope, index_value, declarations);
		return;
	}

	if (type(value) != "array")
		return;

	for (let tag in value)
		push_reference(references, tag, scope, index_value, declarations);
}

function collect_references(config, declaration_map) {
	let references = [];

	if (type(config.route) == "object" && config.route != null && type(config.route.rules) == "array") {
		let idx = 0;
		for (let rule in config.route.rules) {
			if (type(rule) == "object" && rule != null)
				collect_rule_reference(references, rule.rule_set, "route", idx, declaration_map);
			idx = idx + 1;
		}
	}

	if (type(config.dns) == "object" && config.dns != null && type(config.dns.rules) == "array") {
		let idx = 0;
		for (let rule in config.dns.rules) {
			if (type(rule) == "object" && rule != null)
				collect_rule_reference(references, rule.rule_set, "dns", idx, declaration_map);
			idx = idx + 1;
		}
	}

	return references;
}

function count_references(entries, references) {
	for (let entry in entries) {
		let count = 0;
		let scopes = [];
		let indexes = [];
		let referenced_by = [];

		for (let reference in references) {
			if (reference.tag != entry.tag)
				continue;

			count = count + 1;
			append_unique(scopes, reference.scope);
			push(indexes, reference.scope + ":" + reference.index);
			push(referenced_by, {
				scope: reference.scope,
				index: reference.index
			});
		}

		entry.referenced_count = count;
		entry.reference_scopes = scopes;
		entry.reference_indexes = indexes;
		entry.referenced_by = referenced_by;
	}
}

function declaration_map(entries) {
	let result = {};
	for (let entry in entries)
		result[entry.tag] = true;
	return result;
}

function duplicate_map(entries) {
	let seen = {};
	let duplicated = {};

	for (let entry in entries) {
		if (seen[entry.tag])
			duplicated[entry.tag] = true;
		seen[entry.tag] = true;
	}

	return duplicated;
}

function finalize_entries(entries) {
	let duplicated = duplicate_map(entries);

	for (let entry in entries)
		entry.errors = entry_errors(entry, duplicated[entry.tag] == true);
}

function summary(entries, references) {
	let existing = 0;
	let missing = 0;
	let duplicate = 0;
	let invalid = 0;
	let outside = 0;
	let missing_references = 0;
	let duplicated = duplicate_map(entries);

	for (let entry in entries) {
		if (entry.exists)
			existing = existing + 1;
		if (entry.path != "" && !entry.exists)
			missing = missing + 1;
		if (duplicated[entry.tag])
			duplicate = duplicate + 1;
		if (length(entry.errors) > 0)
			invalid = invalid + 1;
		if (entry.path != "" && !entry.managed_root)
			outside = outside + 1;
	}

	for (let reference in references) {
		if (!reference.exists_in_declarations)
			missing_references = missing_references + 1;
	}

	return {
		declared_count: length(entries),
		referenced_count: length(references),
		existing_count: existing,
		missing_count: missing,
		duplicate_count: duplicate,
		invalid_count: invalid,
		outside_managed_root_count: outside,
		missing_reference_count: missing_references
	};
}

function push_diagnostic(diagnostics, level, code, message, data) {
	push(diagnostics, {
		level: level,
		code: code,
		message: message,
		data: data || {}
	});
}

function build_diagnostics(entries, references) {
	let diagnostics = [];

	for (let entry in entries) {
		for (let err in entry.errors) {
			if (err == "missing_file") {
				push_diagnostic(diagnostics, "error", err, "Rule Set local file is missing", {
					tag: entry.tag,
					path: entry.path
				});
			} else if (err == "duplicate_tag") {
				push_diagnostic(diagnostics, "error", err, "Rule Set tag is duplicated", {
					tag: entry.tag
				});
			} else if (err == "unsupported_type") {
				push_diagnostic(diagnostics, "warning", err, "Rule Set type is not recognized by Shinra inventory", {
					tag: entry.tag,
					type: entry.type
				});
			} else if (err == "unsupported_format") {
				push_diagnostic(diagnostics, "warning", err, "Rule Set format is not recognized by Shinra inventory", {
					tag: entry.tag,
					format: entry.format
				});
			} else if (err == "path_outside_managed_root") {
				push_diagnostic(diagnostics, "warning", err, "Rule Set path is outside Shinra managed root", {
					tag: entry.tag,
					path: entry.path
				});
			} else if (err == "unreferenced_declaration") {
				push_diagnostic(diagnostics, "info", err, "Rule Set declaration is not referenced", {
					tag: entry.tag
				});
			} else {
				push_diagnostic(diagnostics, "warning", err, "Rule Set diagnostic", {
					tag: entry.tag
				});
			}
		}
	}

	for (let reference in references) {
		for (let err in reference.errors) {
			if (err == "reference_missing_declaration") {
				push_diagnostic(diagnostics, "error", err, "Rule Set reference has no declaration", {
					tag: reference.tag,
					scope: reference.scope,
					index: reference.index
				});
			} else {
				push_diagnostic(diagnostics, "warning", err, "Rule Set reference diagnostic", {
					tag: reference.tag,
					scope: reference.scope,
					index: reference.index
				});
			}
		}
	}

	return diagnostics;
}

function ensure_rule_dirs() {
	if (!file_exists(PATH.RULE_DIR) && !mkdir(PATH.RULE_DIR, 0700))
		die("Failed to create " + PATH.RULE_DIR);

	let tmp_dir = PATH.RUN_DIR + "/rules-tmp";
	if (!file_exists(PATH.RUN_DIR) && !mkdir(PATH.RUN_DIR, 0700))
		die("Failed to create " + PATH.RUN_DIR);
	if (!file_exists(tmp_dir) && !mkdir(tmp_dir, 0700))
		die("Failed to create " + tmp_dir);

	return tmp_dir;
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

function direct_fetch_rule(trace_id, url, tmp_path) {
	unlink(tmp_path);
	let result = ExecResult(trace_id, [ BIN.TIMEOUT, "20", "wget", "-q", "-T", "15", "-Y", "off", "-O", tmp_path, url ]);
	if (result.code != 0) {
		unlink(tmp_path);
		return {
			ok: false,
			error: "Command failed(" + result.code + "): " + result.stderr
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

function atomic_swap_rule(tmp_path, final_path) {
	let stage_path = final_path + ".stage";
	let bak_path = final_path + ".bak";
	let had_live = file_exists(final_path);

	unlink(stage_path);
	if (!rename(tmp_path, stage_path)) {
		unlink(tmp_path);
		die("Failed to stage rule file: " + final_path);
	}

	if (had_live) {
		unlink(bak_path);
		if (!rename(final_path, bak_path)) {
			unlink(stage_path);
			die("Failed to backup rule file: " + final_path);
		}
	}

	if (rename(stage_path, final_path))
		return {
			final_path: final_path,
			backup_path: bak_path,
			backup_created: had_live
		};

	let restored = false;
	if (had_live && file_exists(bak_path))
		restored = rename(bak_path, final_path) ? true : false;
	unlink(stage_path);
	die("Failed to deploy rule file: " + final_path + "; restored=" + (restored ? "true" : "false"));
}

function required_entries_from_profile() {
	let config = parse_json_object(read_text(PATH.PROFILE), "Profile");
	let entries = collect_declarations(config);
	let refs = collect_references(config, declaration_map(entries));

	count_references(entries, refs);
	finalize_entries(entries);

	let required = [];
	for (let entry in entries) {
		if (entry.referenced_count > 0)
			push(required, entry);
	}

	return {
		entries: required,
		references: refs
	};
}

function ruleset_inventory(trace_id, req) {
	try {
		let selected = select_source(req);
		let config = parse_json_object(read_text(selected.path), "Rule Set inventory source");
		let entries = collect_declarations(config);
		let refs = collect_references(config, declaration_map(entries));

		count_references(entries, refs);
		finalize_entries(entries);

		return Success({
			source_requested: selected.requested,
			source_used: selected.source,
			path: selected.path,
			source_exists: selected.exists,
			summary: summary(entries, refs),
			entries: entries,
			references: refs,
			diagnostics: build_diagnostics(entries, refs)
		}, 200, trace_id, "Rule Set inventory loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_INVENTORY_FAILED, "Failed to load Rule Set inventory", trace_id, err);
	}
}

function ruleset_policy_get(trace_id, req) {
	try {
		let config = normalized_subscriptions_config();
		return Success({
			path: PATH.SUBSCRIPTIONS,
			policy: config.ruleset,
			content: json_stringify(config.ruleset)
		}, 200, trace_id, "Rule Set policy loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_POLICY_FAILED, "Failed to load Rule Set policy", trace_id, err);
	}
}

function ruleset_policy_save(trace_id, req) {
	let lock = null;
	try {
		let content = request_content(req);
		if (content == "")
			die("Missing Rule Set policy content; request keys: " + request_keys(req));

		let policy = normalize_ruleset_policy_content(content);
		lock = acquire(trace_id);
		let config = apply_ruleset_policy(subscriptions_config(), policy);
		write_text_atomic(PATH.SUBSCRIPTIONS, json_stringify(config));
		release(lock);
		return Success({
			path: PATH.SUBSCRIPTIONS,
			policy: config.ruleset
		}, 200, trace_id, "Rule Set policy saved");
	} catch (e) {
		if (lock != null)
			release(lock);
		let err = "" + e;
		return Fail(ERR.E_RULESET_POLICY_FAILED, "Failed to save Rule Set policy", trace_id, err);
	}
}

function ruleset_download_required(trace_id, req) {
	let lock = null;
	try {
		let tmp_dir = ensure_rule_dirs();
		let config = normalized_subscriptions_config();
		let required = required_entries_from_profile().entries;
		let updated = [];
		let unchanged = [];
		let failed = [];
		let attempts = [];

		lock = acquire(trace_id);

		for (let entry in required) {
			let final_path = PATH.RULE_DIR + "/" + entry.tag + ".srs";
			let meta = file_metadata(final_path);

			if (meta.exists && meta.size > 0) {
				push(unchanged, {
					tag: entry.tag,
					path: final_path,
					size: meta.size
				});
				continue;
			}

			let urls = ruleset_urls(entry, config.ruleset);
			let tmp_path = tmp_dir + "/" + entry.tag + ".srs.tmp";
			let downloaded = false;
			let last_error = "";
			let used_url = "";
			let downloaded_size = 0;

			for (let url in urls) {
				let fetch = direct_fetch_rule(trace_id, url, tmp_path);
				push(attempts, {
					tag: entry.tag,
					url_redacted: redacted_url(url),
					ok: fetch.ok == true,
					error: fetch.ok == true ? "" : fetch.error
				});
				if (fetch.ok == true) {
					downloaded = true;
					used_url = url;
					downloaded_size = fetch.size || 0;
					break;
				}
				last_error = fetch.error;
			}

			if (!downloaded) {
				push(failed, {
					tag: entry.tag,
					path: final_path,
					error: last_error || "No downloadable URL succeeded"
				});
				continue;
			}

			let swap = atomic_swap_rule(tmp_path, final_path);
			push(updated, {
				tag: entry.tag,
				path: final_path,
				size: downloaded_size,
				url_redacted: redacted_url(used_url),
				backup_created: swap.backup_created == true
			});
		}

		release(lock);
		return Success({
			required_count: length(required),
			updated_count: length(updated),
			unchanged_count: length(unchanged),
			failed_count: length(failed),
			rule_dir: PATH.RULE_DIR,
			mode: config.ruleset.mode,
			updated: updated,
			unchanged: unchanged,
			failed: failed,
			attempts: attempts
		}, 200, trace_id, "Required Rule Sets downloaded");
	} catch (e) {
		if (lock != null)
			release(lock);
		let err = "" + e;
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to download required Rule Sets", trace_id, err);
	}
}

function notification_meta(result) {
	if (result == null)
		return {
			attempted: true,
			ok: false,
			sent: false,
			reason: "notification crashed"
		};

	let reason = "";
	if (result.ok == true && type(result.data) == "object" && result.data != null && type(result.data.reason) == "string")
		reason = result.data.reason;
	else if (result.ok != true)
		reason = result.detail || result.message || result.code || "";

	return {
		attempted: true,
		ok: result.ok == true,
		sent: result.ok == true && type(result.data) == "object" && result.data != null && result.data.sent == true,
		reason: reason
	};
}

function append_notification(result, meta) {
	if (type(result.data) == "object" && result.data != null && type(result.data) != "array")
		result.data.notification = meta;
	else
		result.notification = meta;
	return result;
}

function failed_rule_tags(data) {
	let tags = [];
	let failed = type(data.failed) == "array" ? data.failed : [];

	for (let item in failed) {
		if (type(item) == "object" && item != null && type(item.tag) == "string")
			push(tags, item.tag);
	}

	return tags;
}

function join_tags(tags) {
	let text = "";
	for (let tag in tags) {
		if (length(text))
			text = text + ", ";
		text = text + tag;
	}
	return text;
}

function ruleset_auto_status(result) {
	if (!result || result.ok != true)
		return "fail";
	let data = type(result.data) == "object" && result.data != null ? result.data : {};
	return (data.failed_count || 0) > 0 ? "partial" : "success";
}

function ruleset_auto_message(result, status) {
	if (!result || result.ok != true) {
		let detail = "unknown error";
		if (result != null)
			detail = result.detail || result.message || result.code || detail;
		return "Rule Set sync " + status + "\nDetail: " + detail;
	}

	let data = type(result.data) == "object" && result.data != null ? result.data : {};
	let tags = failed_rule_tags(data);
	let message = "Rule Set sync " + status +
		"\nRequired: " + (data.required_count || 0) +
		"\nUpdated: " + (data.updated_count || 0) +
		"\nUnchanged: " + (data.unchanged_count || 0) +
		"\nFailed: " + (data.failed_count || 0);
	if (length(tags))
		message = message + "\nFailed rules: " + join_tags(tags);
	return message;
}

function ruleset_download_required_auto(trace_id, req) {
	let result = ruleset_download_required(trace_id, req);
	let status = ruleset_auto_status(result);
	let message = ruleset_auto_message(result, status);
	let notify = send_telegram_best_effort(trace_id, "ruleset_download_required_auto", status, message);
	return append_notification(result, notification_meta(notify));
}

export { ruleset_inventory, ruleset_policy_get, ruleset_policy_save, ruleset_download_required, ruleset_download_required_auto };
