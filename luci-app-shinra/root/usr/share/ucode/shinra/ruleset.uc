/**
 * Shinra | ruleset.uc | v1.0
 */

'use strict';

import { mkdir, opendir, readfile, stat, unlink } from 'fs';
import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { lock_acquire, lock_release } from 'shinra.core.lock';
import { normalize_subscriptions_policy } from 'shinra.subscription_policy';
import { read_text, write_text_atomic, parse_json_object, request_content, request_keys, json_stringify, file_exists } from 'shinra.core.utils';
import { fetch_file } from 'shinra.resource_fetch';
import { task_path, read_task, patch_task, running_task, finish_task, fail_task } from 'shinra.core.task';
import { resource_promote_file } from 'shinra.core.resource';
import { ruleset_transaction_prepare_change, ruleset_transaction_record_change, ruleset_artifact_state } from 'shinra.core.ruleset_artifact';

const RULESET_SYNC_TASK = "ruleset.sync";
const RULESET_SYNC_TRACE = "shinra-runner-ruleset-sync";
const RULESET_DOWNLOAD_ONE_TASK = "ruleset.download_one";
const RULESET_DOWNLOAD_ONE_TRACE = "shinra-runner-ruleset-download-one";

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

function ends_with(value, suffix) {
	value = "" + value;
	suffix = "" + suffix;
	if (length(suffix) > length(value))
		return false;
	return substr(value, length(value) - length(suffix)) == suffix;
}

function dir_entry_name(entry) {
	if (entry == null)
		return "";
	if (type(entry) == "object" && entry.name != null)
		return "" + entry.name;
	return "" + entry;
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

function local_rule_files() {
	let files = {};
	if (!file_exists(PATH.RULE_DIR))
		return files;

	let dir = opendir(PATH.RULE_DIR);
	if (!dir)
		return files;

	for (let item = dir.read(); item != null; item = dir.read()) {
		let name = dir_entry_name(item);
		if (!ends_with(name, ".srs"))
			continue;

		let path = PATH.RULE_DIR + "/" + name;
		let info = stat(path);
		if (type(info) != "object" || info == null)
			continue;
		if (type(info.type) == "string" && info.type != "file")
			continue;

		let tag = substr(name, 0, length(name) - 4);
		files[tag] = {
			tag: tag,
			path: path,
			exists: true,
			size: info.size || 0,
			mtime: info.mtime || 0
		};
	}

	dir.close();
	return files;
}

function redacted_urls(urls) {
	let result = [];
	for (let url in urls)
		push(result, redacted_url(url));
	return result;
}

function ruleset_required_inventory(trace_id, req) {
	try {
		let required_info = required_entries_from_profile();
		let required = required_info.entries;
		let config = normalized_subscriptions_config();
		let locals = local_rule_files();
		let required_map = {};
		let entries = [];
		let diagnostics = [];
		let ready = 0;
		let missing = 0;

		for (let entry in required) {
			let tag = entry.tag;
			let local_path = PATH.RULE_DIR + "/" + tag + ".srs";
			let meta = file_metadata(local_path);
			let status = meta.exists && meta.size > 0 ? "ready" : "missing";
			let urls = ruleset_urls(entry, config.ruleset);
			required_map[tag] = true;

			if (status == "ready")
				ready = ready + 1;
			else {
				missing = missing + 1;
				push(diagnostics, {
					level: "error",
					code: "required_local_missing",
					message: "Required local Rule Set is missing",
					data: {
						tag: tag,
						path: local_path
					}
				});
			}

			push(entries, {
				tag: tag,
				required: true,
				status: status,
				local_path: local_path,
				local_exists: meta.exists,
				local_size: meta.size,
				local_mtime: meta.mtime,
				source_url: entry.source_url,
				source_url_redacted: redacted_url(entry.source_url),
				candidate_urls: urls,
				candidate_url_redacted: redacted_urls(urls),
				referenced_count: entry.referenced_count,
				reference_scopes: entry.reference_scopes,
				reference_indexes: entry.reference_indexes,
				referenced_by: entry.referenced_by
			});
		}

		let extras = [];
		let local_count = 0;
		for (let tag in locals) {
			local_count = local_count + 1;
			if (required_map[tag])
				continue;
			let item = locals[tag];
			push(extras, {
				tag: tag,
				required: false,
				status: "extra",
				local_path: item.path,
				local_exists: true,
				local_size: item.size,
				local_mtime: item.mtime
			});
		}

		return Success({
			source: "profile",
			profile_path: PATH.PROFILE,
			rule_dir: PATH.RULE_DIR,
			mode: config.ruleset.mode,
			fetch_strategy: config.ruleset.fetch_strategy,
			summary: {
				required_count: length(required),
				ready_count: ready,
				missing_count: missing,
				local_count: local_count,
				local_extra_count: length(extras)
			},
			entries: entries,
			extras: extras,
			references: required_info.references,
			diagnostics: diagnostics
		}, 200, trace_id, "Required Rule Set inventory loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_INVENTORY_FAILED, "Failed to load Required Rule Set inventory", trace_id, err);
	}
}

function ruleset_inventory(trace_id, req) {
	try {
		let selected = select_source(req);
		if (!selected.exists) {
			return Success({
				source_requested: selected.requested,
				source_used: selected.source,
				path: selected.path,
				source_exists: false,
				summary: summary([], []),
				entries: [],
				references: [],
				diagnostics: [
					{
						level: "info",
						code: "source_missing",
						message: "Rule Set inventory source does not exist yet",
						data: {
							source: selected.source,
							path: selected.path
						}
					}
				]
			}, 200, trace_id, "Rule Set inventory source missing");
		}

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
		lock = lock_acquire("subscription", trace_id);
		let config = apply_ruleset_policy(subscriptions_config(), policy);
		write_text_atomic(PATH.SUBSCRIPTIONS, json_stringify(config));
		lock_release(lock);
		return Success({
			path: PATH.SUBSCRIPTIONS,
			policy: config.ruleset
		}, 200, trace_id, "Rule Set policy saved");
	} catch (e) {
		if (lock != null)
			lock_release(lock);
		let err = "" + e;
		return Fail(ERR.E_RULESET_POLICY_FAILED, "Failed to save Rule Set policy", trace_id, err);
	}
}

function ruleset_task_enabled(trace_id) {
	return trace_id == RULESET_SYNC_TRACE;
}

function ruleset_download_one_task_enabled(trace_id) {
	return trace_id == RULESET_DOWNLOAD_ONE_TRACE;
}

function progress_percent(done, total) {
	done = int(done || 0);
	total = int(total || 0);
	if (total <= 0)
		return 0;
	if (done >= total)
		return 100;
	return int((done * 100) / total);
}

function write_ruleset_task_progress(trace_id, patch) {
	try {
		if (!ruleset_task_enabled(trace_id))
			return;
		if (patch.status == "running")
			running_task(RULESET_SYNC_TASK, trace_id, patch);
		else
			patch_task(RULESET_SYNC_TASK, patch);
	} catch (e) {
		/* Progress must never fail the actual sync. */
	}
}

function write_ruleset_download_one_task_progress(trace_id, patch) {
	try {
		if (!ruleset_download_one_task_enabled(trace_id))
			return;
		if (patch.status == "running")
			running_task(RULESET_DOWNLOAD_ONE_TASK, trace_id, patch);
		else
			patch_task(RULESET_DOWNLOAD_ONE_TASK, patch);
	} catch (e) {
		/* Progress must never fail the actual download. */
	}
}

function download_required_entry(trace_id, entry, config, strategy, tmp_dir, on_progress) {
	let final_path = PATH.RULE_DIR + "/" + entry.tag + ".srs";
	let meta = file_metadata(final_path);
	let urls = ruleset_urls(entry, config.ruleset);
	let tmp_path = tmp_dir + "/" + entry.tag + ".srs.tmp";
	let attempts = [];
	let downloaded = false;
	let last_error = "";
	let used_url = "";
	let downloaded_size = 0;

	if (type(on_progress) == "function")
		on_progress({
			current_item: entry.tag,
			last_error: "",
			meta: {
				fetch_strategy: strategy,
				current_url_redacted: length(urls) ? redacted_url(urls[0]) : "",
				rule_dir: PATH.RULE_DIR,
				tag: entry.tag
			}
		});

	for (let url in urls) {
		if (type(on_progress) == "function")
			on_progress({
				current_item: entry.tag,
				meta: {
					current_url_redacted: redacted_url(url)
				}
			});

		let fetch = direct_fetch_rule(trace_id, url, tmp_path, strategy);
		push(attempts, {
			tag: entry.tag,
			url_redacted: redacted_url(url),
			fetch_strategy: strategy,
			method: "get",
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
		return {
			status: "failed",
			tag: entry.tag,
			path: final_path,
			error: last_error || "No downloadable URL succeeded",
			attempts: attempts
		};
	}

	if (meta.exists && meta.size > 0 && same_file_content(tmp_path, final_path)) {
		unlink(tmp_path);
		return {
			status: "unchanged",
			tag: entry.tag,
			path: final_path,
			size: meta.size,
			url_redacted: redacted_url(used_url),
			checked_download: true,
			attempts: attempts
		};
	}

	let prepared = null;
	if (config.ruleset.mode == "local")
		prepared = ruleset_transaction_prepare_change(trace_id, entry.tag, final_path);

	let swap = atomic_swap_rule(tmp_path, final_path);
	let transaction = {};
	if (prepared != null)
		transaction = ruleset_transaction_record_change(trace_id, prepared);

	return {
		status: "updated",
		tag: entry.tag,
		path: final_path,
		size: downloaded_size,
		url_redacted: redacted_url(used_url),
		backup_created: swap.backup_created == true,
		pending_runtime_validation: prepared != null,
		transaction_changed_count: transaction.changed_count || 0,
		attempts: attempts
	};
}

function find_required_entry(required, tag) {
	for (let entry in required) {
		if (entry.tag == tag)
			return entry;
	}
	return null;
}

function ruleset_download_required(trace_id, req) {
	let lock = null;
	try {
		ensure_rule_dirs();
		let config = normalized_subscriptions_config();
		let strategy = config.ruleset.fetch_strategy == "proxy" ? "proxy" : "direct";
		let required = required_entries_from_profile().entries;
		let updated = [];
		let unchanged = [];
		let failed = [];
		let attempts = [];
		let checked = [];
		let tmp_dir = PATH.RULE_DIR + "/.tmp";

		lock = lock_acquire("ruleset", trace_id);
		write_ruleset_task_progress(trace_id, {
			status: "running",
			message: "Rule Set sync running",
			total_count: length(required),
			completed_count: 0,
			updated_count: 0,
			unchanged_count: 0,
			failed_count: 0,
			checked_count: 0,
			progress: 0,
			current_item: "",
			last_error: "",
			meta: {
				fetch_strategy: strategy,
				current_url_redacted: "",
				rule_dir: PATH.RULE_DIR
			},
			trace_id: trace_id
		});

		for (let entry in required) {
			write_ruleset_task_progress(trace_id, {
				status: "running",
				message: "Rule Set sync running",
				total_count: length(required),
				completed_count: length(updated) + length(unchanged) + length(failed),
				updated_count: length(updated),
				unchanged_count: length(unchanged),
				failed_count: length(failed),
				checked_count: length(checked),
				progress: progress_percent(length(updated) + length(unchanged) + length(failed), length(required)),
				current_item: entry.tag,
				last_error: "",
				meta: {
					fetch_strategy: strategy,
					current_url_redacted: "",
					rule_dir: PATH.RULE_DIR
				}
			});

			let result = download_required_entry(trace_id, entry, config, strategy, tmp_dir, function(patch) {
				write_ruleset_task_progress(trace_id, {
					current_item: patch.current_item,
					last_error: patch.last_error || "",
					meta: patch.meta || {}
				});
			});
			for (let attempt in result.attempts)
				push(attempts, attempt);

			if (result.status == "failed") {
				push(failed, {
					tag: result.tag,
					path: result.path,
					error: result.error
				});
				write_ruleset_task_progress(trace_id, {
					completed_count: length(updated) + length(unchanged) + length(failed),
					updated_count: length(updated),
					unchanged_count: length(unchanged),
					failed_count: length(failed),
					checked_count: length(checked),
					progress: progress_percent(length(updated) + length(unchanged) + length(failed), length(required)),
					current_item: entry.tag,
					last_error: result.error
				});
				continue;
			}

			if (result.status == "unchanged") {
				push(unchanged, {
					tag: result.tag,
					path: result.path,
					size: result.size,
					url_redacted: result.url_redacted,
					checked_download: true
				});
				push(checked, entry.tag);
				write_ruleset_task_progress(trace_id, {
					completed_count: length(updated) + length(unchanged) + length(failed),
					updated_count: length(updated),
					unchanged_count: length(unchanged),
					failed_count: length(failed),
					checked_count: length(checked),
					progress: progress_percent(length(updated) + length(unchanged) + length(failed), length(required)),
					current_item: entry.tag,
					last_error: "",
					meta: {
						current_url_redacted: result.url_redacted
					}
				});
				continue;
			}

			push(updated, {
				tag: result.tag,
				path: result.path,
				size: result.size,
				url_redacted: result.url_redacted,
				backup_created: result.backup_created == true,
				pending_runtime_validation: result.pending_runtime_validation == true,
				transaction_changed_count: result.transaction_changed_count || 0
			});
			write_ruleset_task_progress(trace_id, {
				completed_count: length(updated) + length(unchanged) + length(failed),
				updated_count: length(updated),
				unchanged_count: length(unchanged),
				failed_count: length(failed),
				checked_count: length(checked),
				progress: progress_percent(length(updated) + length(unchanged) + length(failed), length(required)),
				current_item: entry.tag,
				last_error: "",
				meta: {
					current_url_redacted: result.url_redacted
				}
			});
		}

		lock_release(lock);
		if (ruleset_task_enabled(trace_id)) {
			finish_task(RULESET_SYNC_TASK, length(failed) ? "partial" : "success", trace_id, {
				message: "Required Rule Sets downloaded",
				total_count: length(required),
				completed_count: length(required),
				updated_count: length(updated),
				unchanged_count: length(unchanged),
				failed_count: length(failed),
				checked_count: length(checked),
				progress: 100,
				current_item: "",
				last_error: length(failed) ? failed[length(failed) - 1].error : "",
				meta: {
					fetch_strategy: strategy,
					current_url_redacted: "",
					rule_dir: PATH.RULE_DIR
				}
			});
		}
		return Success({
			required_count: length(required),
			updated_count: length(updated),
			unchanged_count: length(unchanged),
			failed_count: length(failed),
			checked_count: length(checked),
			rule_dir: PATH.RULE_DIR,
			tmp_dir: tmp_dir,
			mode: config.ruleset.mode,
			fetch_strategy: strategy,
			updated: updated,
			unchanged: unchanged,
			checked: checked,
			failed: failed,
			attempts: attempts
		}, 200, trace_id, "Required Rule Sets downloaded");
	} catch (e) {
		if (lock != null)
			lock_release(lock);
		let err = "" + e;
		if (ruleset_task_enabled(trace_id)) {
			try {
				fail_task(RULESET_SYNC_TASK, trace_id, err, {
					message: "Failed to download required Rule Sets"
				});
			} catch (task_error) {
				let ignored = "" + task_error;
			}
		}
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to download required Rule Sets", trace_id, err);
	}
}
function ruleset_download_required_status(trace_id, req) {
	try {
		let path = task_path(RULESET_SYNC_TASK);
		return Success({
			path: path,
			exists: file_exists(path),
			task: read_task(RULESET_SYNC_TASK)
		}, 200, trace_id, "Rule Set sync task status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to load Rule Set sync task status", trace_id, err);
	}
}

function ruleset_artifact_status(trace_id, req) {
	try {
		return Success(ruleset_artifact_state(trace_id), 200, trace_id, "Rule Set artifact status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_INVENTORY_FAILED, "Failed to load Rule Set artifact status", trace_id, err);
	}
}

function request_tag(req) {
	if (type(req) == "object" && req != null && type(req.tag) == "string" && req.tag != "")
		return req.tag;
	die("Missing Rule Set tag");
}

function ruleset_download_one(trace_id, req) {
	let lock = null;
	try {
		ensure_rule_dirs();
		let tag = request_tag(req);
		let config = normalized_subscriptions_config();
		let strategy = config.ruleset.fetch_strategy == "proxy" ? "proxy" : "direct";
		let required = required_entries_from_profile().entries;
		let entry = find_required_entry(required, tag);
		let tmp_dir = PATH.RULE_DIR + "/.tmp";

		if (entry == null)
			die("Rule Set tag is not required by profile: " + tag);

		lock = lock_acquire("ruleset", trace_id);
		write_ruleset_download_one_task_progress(trace_id, {
			status: "running",
			message: "Rule Set download running",
			total_count: 1,
			completed_count: 0,
			updated_count: 0,
			unchanged_count: 0,
			failed_count: 0,
			checked_count: 0,
			progress: 0,
			current_item: tag,
			last_error: "",
			meta: {
				tag: tag,
				fetch_strategy: strategy,
				current_url_redacted: "",
				rule_dir: PATH.RULE_DIR
			},
			trace_id: trace_id
		});

		let result = download_required_entry(trace_id, entry, config, strategy, tmp_dir, function(patch) {
			write_ruleset_download_one_task_progress(trace_id, {
				current_item: patch.current_item,
				last_error: patch.last_error || "",
				meta: patch.meta || {}
			});
		});

		if (result.status == "failed") {
			if (ruleset_download_one_task_enabled(trace_id)) {
				finish_task(RULESET_DOWNLOAD_ONE_TASK, "failed", trace_id, {
					message: "Rule Set download failed",
					total_count: 1,
					completed_count: 1,
					updated_count: 0,
					unchanged_count: 0,
					failed_count: 1,
					checked_count: 0,
					progress: 100,
					current_item: "",
					last_error: result.error,
					meta: {
						tag: tag,
						fetch_strategy: strategy,
						current_url_redacted: "",
						rule_dir: PATH.RULE_DIR
					}
				});
			}
			die(result.error);
		}

		let updated_count = result.status == "updated" ? 1 : 0;
		let unchanged_count = result.status == "unchanged" ? 1 : 0;
		let checked_count = result.status == "unchanged" ? 1 : 0;

		lock_release(lock);
		lock = null;

		if (ruleset_download_one_task_enabled(trace_id)) {
			finish_task(RULESET_DOWNLOAD_ONE_TASK, "success", trace_id, {
				message: result.status == "updated" ? "Rule Set downloaded" : "Rule Set unchanged",
				total_count: 1,
				completed_count: 1,
				updated_count: updated_count,
				unchanged_count: unchanged_count,
				failed_count: 0,
				checked_count: checked_count,
				progress: 100,
				current_item: "",
				last_error: "",
				meta: {
					tag: tag,
					fetch_strategy: strategy,
					current_url_redacted: result.url_redacted || "",
					rule_dir: PATH.RULE_DIR,
					pending_runtime_validation: result.pending_runtime_validation == true
				}
			});
		}

		return Success({
			tag: tag,
			status: result.status,
			updated: result.status == "updated",
			unchanged: result.status == "unchanged",
			path: result.path,
			size: result.size || 0,
			url_redacted: result.url_redacted || "",
			mode: config.ruleset.mode,
			fetch_strategy: strategy,
			pending_runtime_validation: result.pending_runtime_validation == true,
			transaction_changed_count: result.transaction_changed_count || 0,
			attempts: result.attempts || []
		}, 200, trace_id, result.status == "updated" ? "Rule Set downloaded" : "Rule Set unchanged");
	} catch (e) {
		if (lock != null)
			lock_release(lock);
		let err = "" + e;
		if (ruleset_download_one_task_enabled(trace_id)) {
			try {
				fail_task(RULESET_DOWNLOAD_ONE_TASK, trace_id, err, {
					message: "Failed to download Rule Set"
				});
			} catch (task_error) {
				let ignored = "" + task_error;
			}
		}
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to download Rule Set", trace_id, err);
	}
}

function ruleset_download_one_status(trace_id, req) {
	try {
		let path = task_path(RULESET_DOWNLOAD_ONE_TASK);
		return Success({
			path: path,
			exists: file_exists(path),
			task: read_task(RULESET_DOWNLOAD_ONE_TASK)
		}, 200, trace_id, "Rule Set download task status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to load Rule Set download task status", trace_id, err);
	}
}

function safe_shell_arg(value, label) {
	value = "" + value;
	if (value == "")
		die(label + " must not be empty");
	for (let i = 0; i < length(value); i++) {
		let ch = substr(value, i, 1);
		let ok = (ch >= "A" && ch <= "Z") ||
			(ch >= "a" && ch <= "z") ||
			(ch >= "0" && ch <= "9") ||
			ch == "." || ch == "_" || ch == "-";
		if (!ok)
			die("Invalid " + label + ": " + value);
	}
	return value;
}

function ruleset_download_one_start(trace_id, req) {
	try {
		let tag = safe_shell_arg(request_tag(req), "Rule Set tag");
		if (!file_exists(PATH.RUN_DIR) && !mkdir(PATH.RUN_DIR, 0700))
			die("Failed to create Run directory: " + PATH.RUN_DIR);
		if (!file_exists(PATH.RUNNER_DIR) && !mkdir(PATH.RUNNER_DIR, 0700))
			die("Failed to create Runner directory: " + PATH.RUNNER_DIR);

		let lock_info = stat(PATH.RUNNER_DIR + "/ruleset.download_one.lock");
		let path = task_path(RULESET_DOWNLOAD_ONE_TASK);
		let task = read_task(RULESET_DOWNLOAD_ONE_TASK);
		if (type(lock_info) == "object" && lock_info != null && (task.status == "running" || task.status == "starting")) {
			return Success({
				path: path,
				task: task,
				started: false,
				reason: "already_running"
			}, 200, trace_id, "Rule Set download task is already running");
		}

		let code = system("/usr/libexec/shinra-runner ruleset.download_one ruleset_download_one " + RULESET_DOWNLOAD_ONE_TRACE + " " + tag + " >/dev/null 2>&1 &");
		if (code != 0)
			die("Failed to start /usr/libexec/shinra-runner: " + code);

		task = read_task(RULESET_DOWNLOAD_ONE_TASK);
		task.status = "starting";
		task.message = "Rule Set download queued";
		task.trace_id = trace_id;
		task.current_item = tag;
		task.total_count = 1;
		task.meta.tag = tag;
		return Success({
			path: path,
			task: task,
			started: true
		}, 202, trace_id, "Rule Set download task started");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to start Rule Set download task", trace_id, err);
	}
}

function ruleset_download_required_start(trace_id, req) {
	try {
		if (!file_exists(PATH.RUN_DIR) && !mkdir(PATH.RUN_DIR, 0700))
			die("Failed to create Run directory: " + PATH.RUN_DIR);
		if (!file_exists(PATH.RUNNER_DIR) && !mkdir(PATH.RUNNER_DIR, 0700))
			die("Failed to create Runner directory: " + PATH.RUNNER_DIR);
		let lock_info = stat(PATH.RUNNER_DIR + "/ruleset.sync.lock");
		let path = task_path(RULESET_SYNC_TASK);
		let task = read_task(RULESET_SYNC_TASK);
		if (type(lock_info) == "object" && lock_info != null && (task.status == "running" || task.status == "starting")) {
			return Success({
				path: path,
				task: task,
				started: false,
				reason: "already_running"
			}, 200, trace_id, "Rule Set sync task is already running");
		}

		let notify_arg = type(req) == "object" && req != null && req.notify_intent == true ? " - notify" : "";
		let code = system("/usr/libexec/shinra-runner ruleset.sync ruleset_download_required " + RULESET_SYNC_TRACE + notify_arg + " >/dev/null 2>&1 &");
		if (code != 0)
			die("Failed to start /usr/libexec/shinra-runner: " + code);

		task = read_task(RULESET_SYNC_TASK);
		task.status = "starting";
		task.message = "Rule Set sync queued";
		task.trace_id = trace_id;
		return Success({
			path: path,
			task: task,
			started: true
		}, 202, trace_id, "Rule Set sync task started");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to start Rule Set sync task", trace_id, err);
	}
}

export { ruleset_inventory, ruleset_required_inventory, ruleset_policy_get, ruleset_policy_save, ruleset_download_required, ruleset_download_required_start, ruleset_download_required_status, ruleset_artifact_status, ruleset_download_one, ruleset_download_one_start, ruleset_download_one_status };

