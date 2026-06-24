/**
 * Shinra | zashboard.uc | v1.1
 */

'use strict';

import { stat } from 'fs';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { PATH, BIN } from 'shinra.core.constants';
import { read_optional_text, write_text_atomic, parse_json_object, request_content, request_keys, json_stringify, file_exists, ExecSafe } from 'shinra.core.utils';

function default_zashboard_source() {
	return {
		schema_version: 1,
		url: "",
		repository: {
			type: "github",
			owner: "Zephyruso",
			repo: "zashboard",
			asset_pattern: "dist.zip",
			proxy_prefix: "https://gh-proxy.com/"
		},
		installed: {
			version: "",
			updated_at: ""
		},
		last_check: {
			version: "",
			asset_name: "",
			asset_url: "",
			download_url: "",
			checked_at: "",
			result: "",
			update_available: false
		},
		panel_api: {
			enabled: true,
			external_controller: "0.0.0.0:20123",
			secret: "",
			allow_empty_secret: true
		}
	};
}

function valid_url(url) {
	return index(url, "http://") == 0 || index(url, "https://") == 0;
}

function trim_text(value) {
	let text = "" + value;
	text = replace(text, "\r", "");
	text = replace(text, "\n", "");
	return text;
}

function now_utc(trace_id) {
	return trim_text(ExecSafe(trace_id, [ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" ]));
}

function normalize_panel_api(raw) {
	let result = {
		enabled: true,
		external_controller: "0.0.0.0:20123",
		secret: "",
		allow_empty_secret: true
	};

	if (type(raw) == "object" && raw != null && type(raw) != "array") {
		result.enabled = raw.enabled == false ? false : true;
		if (type(raw.external_controller) == "string" && raw.external_controller != "")
			result.external_controller = raw.external_controller;
		if (type(raw.secret) == "string")
			result.secret = raw.secret;
		result.allow_empty_secret = raw.allow_empty_secret == false ? false : true;
	}

	if (index(result.external_controller, ":") < 0)
		die("panel_api.external_controller must be host:port");
	if (result.enabled && !result.allow_empty_secret && result.secret == "")
		die("panel_api.secret must not be empty when allow_empty_secret is false");

	return result;
}

function normalize_repository(raw) {
	let defaults = default_zashboard_source();
	let result = defaults.repository;

	if (type(raw) == "object" && raw != null && type(raw) != "array") {
		if (type(raw.type) == "string" && raw.type != "")
			result.type = raw.type;
		if (type(raw.owner) == "string" && raw.owner != "")
			result.owner = raw.owner;
		if (type(raw.repo) == "string" && raw.repo != "")
			result.repo = raw.repo;
		if (type(raw.asset_pattern) == "string" && raw.asset_pattern != "")
			result.asset_pattern = raw.asset_pattern;
		if (type(raw.proxy_prefix) == "string")
			result.proxy_prefix = raw.proxy_prefix;
	}

	if (result.type != "github")
		die("repository.type must be github");
	if (!length(result.owner))
		die("repository.owner is required");
	if (!length(result.repo))
		die("repository.repo is required");
	if (!length(result.asset_pattern))
		die("repository.asset_pattern is required");
	if (length(result.proxy_prefix) && !valid_url(result.proxy_prefix))
		die("repository.proxy_prefix must start with http:// or https://");

	return result;
}

function normalize_installed(raw, legacy) {
	let result = {
		version: "",
		updated_at: ""
	};

	if (type(raw) == "object" && raw != null && type(raw) != "array") {
		if (type(raw.version) == "string")
			result.version = raw.version;
		if (type(raw.updated_at) == "string")
			result.updated_at = raw.updated_at;
	}

	if (type(legacy) == "object" && legacy != null && type(legacy) != "array") {
		if (!length(result.version) && type(legacy.version) == "string")
			result.version = legacy.version;
		if (!length(result.updated_at) && type(legacy.updated_at) == "string")
			result.updated_at = legacy.updated_at;
	}

	return result;
}

function normalize_last_check(raw) {
	let defaults = default_zashboard_source();
	let result = defaults.last_check;

	if (type(raw) == "object" && raw != null && type(raw) != "array") {
		if (type(raw.version) == "string")
			result.version = raw.version;
		if (type(raw.asset_name) == "string")
			result.asset_name = raw.asset_name;
		if (type(raw.asset_url) == "string")
			result.asset_url = raw.asset_url;
		if (type(raw.download_url) == "string")
			result.download_url = raw.download_url;
		if (type(raw.checked_at) == "string")
			result.checked_at = raw.checked_at;
		if (type(raw.result) == "string")
			result.result = raw.result;
		result.update_available = raw.update_available == true ? true : false;
	}

	return result;
}

function normalize_zashboard_source(source) {
	if (type(source) != "object" || source == null || type(source) == "array")
		die("Zashboard source root must be a JSON object");

	let url = type(source.url) == "string" ? source.url : "";
	if (length(url) && !valid_url(url))
		die("Zashboard URL must start with http:// or https://");

	return {
		schema_version: 1,
		url: url,
		repository: normalize_repository(source.repository),
		installed: normalize_installed(source.installed, source),
		last_check: normalize_last_check(source.last_check),
		panel_api: normalize_panel_api(source.panel_api)
	};
}

function read_zashboard_source() {
	let content = read_optional_text(PATH.ZASHBOARD_SOURCE);
	if (!length(content))
		return default_zashboard_source();
	return normalize_zashboard_source(parse_json_object(content, "Zashboard Source"));
}

function zashboard_source_content(source) {
	return json_stringify(normalize_zashboard_source(source)) + "\n";
}

function panel_status(source) {
	let index_path = PATH.ZASHBOARD_DIR + "/index.html";
	let info = stat(index_path);
	let installed = type(info) == "object" && info != null;

	return {
		source_path: PATH.ZASHBOARD_SOURCE,
		panel_dir: PATH.ZASHBOARD_DIR,
		index_path: index_path,
		installed: installed,
		index_size: installed && type(info.size) == "int" ? info.size : 0,
		index_mtime: installed && type(info.mtime) == "int" ? info.mtime : 0,
		source: source
	};
}

function zashboard_panel_policy() {
	let source = read_zashboard_source();
	return source.panel_api;
}

function proxied_url(url, repository) {
	if (length(repository.proxy_prefix))
		return repository.proxy_prefix + url;
	return url;
}

function github_latest_api_url(repository) {
	return "https://api.github.com/repos/" + repository.owner + "/" + repository.repo + "/releases/latest";
}

function pattern_match(name, pattern) {
	if (name == pattern)
		return true;

	let star = index(pattern, "*");
	if (star < 0)
		return false;

	let prefix = substr(pattern, 0, star);
	let suffix = substr(pattern, star + 1);
	if (length(prefix) && index(name, prefix) != 0)
		return false;
	if (length(name) < length(prefix) + length(suffix))
		return false;
	if (length(suffix) && substr(name, length(name) - length(suffix)) != suffix)
		return false;
	return true;
}

function release_asset(release, pattern) {
	if (type(release.assets) != "array")
		die("GitHub release has no assets array");

	for (let asset in release.assets) {
		if (type(asset) != "object" || asset == null || type(asset) == "array")
			continue;
		let name = type(asset.name) == "string" ? asset.name : "";
		let url = type(asset.browser_download_url) == "string" ? asset.browser_download_url : "";
		if (length(name) && length(url) && pattern_match(name, pattern))
			return {
				name: name,
				url: url
			};
	}

	die("No Zashboard release asset matched " + pattern);
}

function check_latest_release(trace_id, source) {
	let repository = normalize_repository(source.repository);
	let api_url = github_latest_api_url(repository);
	let content = ExecSafe(trace_id, [ BIN.TIMEOUT, "60", "wget", "-q", "-T", "30", "-Y", "off", "--header", "Accept: application/vnd.github+json", "-O", "-", proxied_url(api_url, repository) ]);
	let release = parse_json_object(content, "Zashboard GitHub release");
	let version = type(release.tag_name) == "string" && length(release.tag_name) ? release.tag_name : "";
	if (!length(version))
		die("GitHub release tag_name is empty");

	let asset = release_asset(release, repository.asset_pattern);
	return {
		version: version,
		asset_name: asset.name,
		asset_url: asset.url,
		download_url: proxied_url(asset.url, repository),
		checked_at: now_utc(trace_id),
		result: "ok",
		update_available: source.installed.version != version
	};
}

function install_archive_url(trace_id, url) {
	let safe_trace = replace("" + trace_id, "/", "_");
	let work_dir = "/tmp/shinra-zashboard-" + safe_trace;
	let archive = work_dir + "/zashboard.zip";
	let unpack_dir = work_dir + "/unpack";
	let stage_dir = work_dir + "/stage";
	let old_dir = PATH.ZASHBOARD_DIR + ".old";

	ExecSafe(trace_id, [ "rm", "-rf", work_dir ]);
	ExecSafe(trace_id, [ "mkdir", "-p", unpack_dir ]);
	ExecSafe(trace_id, [ BIN.TIMEOUT, "60", "wget", "-q", "-T", "30", "-Y", "off", "-O", archive, url ]);
	ExecSafe(trace_id, [ "unzip", "-q", archive, "-d", unpack_dir ]);

	let candidates = [
		unpack_dir,
		unpack_dir + "/dist",
		unpack_dir + "/zashboard",
		unpack_dir + "/public"
	];

	let selected = "";
	for (let candidate in candidates) {
		if (file_exists(candidate + "/index.html")) {
			selected = candidate;
			break;
		}
	}

	if (!length(selected))
		die("Downloaded Zashboard archive does not contain index.html");

	ExecSafe(trace_id, [ "mkdir", "-p", "/www/shinra" ]);
	ExecSafe(trace_id, [ "rm", "-rf", stage_dir ]);
	ExecSafe(trace_id, [ "cp", "-R", selected, stage_dir ]);
	if (!file_exists(stage_dir + "/index.html"))
		die("Staged Zashboard index.html missing");

	ExecSafe(trace_id, [ "rm", "-rf", old_dir ]);
	if (file_exists(PATH.ZASHBOARD_DIR))
		ExecSafe(trace_id, [ "mv", PATH.ZASHBOARD_DIR, old_dir ]);
	ExecSafe(trace_id, [ "mv", stage_dir, PATH.ZASHBOARD_DIR ]);
	ExecSafe(trace_id, [ "rm", "-rf", old_dir ]);
	ExecSafe(trace_id, [ "rm", "-rf", work_dir ]);
}

function zashboard_source_get(trace_id, req) {
	try {
		let source = read_zashboard_source();
		return Success({
			path: PATH.ZASHBOARD_SOURCE,
			source: source,
			content: zashboard_source_content(source)
		}, 200, trace_id, "Zashboard source loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_ZASHBOARD_SOURCE_FAILED, "Failed to load Zashboard source", trace_id, err);
	}
}

function zashboard_source_save(trace_id, req) {
	try {
		let content = request_content(req);
		if (!length(content))
			die("Missing Zashboard source content; request keys: " + request_keys(req));

		let source = normalize_zashboard_source(parse_json_object(content, "Zashboard Source"));
		write_text_atomic(PATH.ZASHBOARD_SOURCE, zashboard_source_content(source));
		return Success({
			path: PATH.ZASHBOARD_SOURCE,
			source: source
		}, 200, trace_id, "Zashboard source saved");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_ZASHBOARD_SOURCE_FAILED, "Failed to save Zashboard source", trace_id, err);
	}
}

function zashboard_status(trace_id, req) {
	try {
		let source = read_zashboard_source();
		return Success(panel_status(source), 200, trace_id, "Zashboard status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_ZASHBOARD_SOURCE_FAILED, "Failed to load Zashboard status", trace_id, err);
	}
}

function zashboard_update_check(trace_id, req) {
	try {
		let source = read_zashboard_source();
		source.last_check = check_latest_release(trace_id, source);
		write_text_atomic(PATH.ZASHBOARD_SOURCE, zashboard_source_content(source));

		return Success({
			path: PATH.ZASHBOARD_SOURCE,
			repository: source.repository,
			installed: source.installed,
			last_check: source.last_check
		}, 200, trace_id, "Zashboard update checked");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_ZASHBOARD_SYNC_FAILED, "Failed to check Zashboard update", trace_id, err);
	}
}

function zashboard_update_apply(trace_id, req) {
	try {
		let source = read_zashboard_source();
		source.last_check = check_latest_release(trace_id, source);
		install_archive_url(trace_id, source.last_check.download_url);
		source.installed.version = source.last_check.version;
		source.installed.updated_at = now_utc(trace_id);
		source.last_check.result = "updated";
		source.last_check.update_available = false;
		write_text_atomic(PATH.ZASHBOARD_SOURCE, zashboard_source_content(source));

		return Success(panel_status(source), 200, trace_id, "Zashboard updated");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_ZASHBOARD_SYNC_FAILED, "Failed to update Zashboard", trace_id, err);
	}
}

function zashboard_sync_remote(trace_id, req) {
	try {
		let source = read_zashboard_source();
		if (!length(source.url))
			die("Zashboard URL is empty");
		if (!valid_url(source.url))
			die("Zashboard URL must start with http:// or https://");

		install_archive_url(trace_id, source.url);
		source.installed.updated_at = now_utc(trace_id);
		write_text_atomic(PATH.ZASHBOARD_SOURCE, zashboard_source_content(source));

		return Success(panel_status(source), 200, trace_id, "Zashboard synced");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_ZASHBOARD_SYNC_FAILED, "Failed to sync Zashboard", trace_id, err);
	}
}

export { zashboard_source_get, zashboard_source_save, zashboard_status, zashboard_sync_remote, zashboard_update_check, zashboard_update_apply, zashboard_panel_policy };
