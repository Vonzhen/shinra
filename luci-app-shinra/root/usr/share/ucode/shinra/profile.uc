/**
 * Shinra | profile.uc | v1.0
 */

'use strict';

import { PATH, BIN } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { acquire, release } from 'shinra.core.lock';
import { read_text, read_optional_text, write_text_atomic, parse_json_object, request_content, request_keys, json_stringify, ExecResult, ExecSafe } from 'shinra.core.utils';

function validate_profile_object(profile) {
	if (type(profile.inbounds) != "array")
		die("Profile must contain inbounds array");
	if (type(profile.outbounds) != "array")
		die("Profile must contain outbounds array");
	if (type(profile.route) != "object" || profile.route == null || type(profile.route) == "array")
		die("Profile must contain route object");

	let has_tun = false;
	for (let inbound in profile.inbounds) {
		if (type(inbound) == "object" && inbound.type == "tun")
			has_tun = true;
	}
	if (!has_tun)
		die("Profile must contain a tun inbound");

	let main_selector_count = 0;
	let has_direct = false;
	for (let outbound in profile.outbounds) {
		if (type(outbound) != "object")
			continue;
		if (outbound.type == "selector" && outbound.x_rule == "main")
			main_selector_count = main_selector_count + 1;
		if (outbound.type == "direct")
			has_direct = true;
	}
	if (main_selector_count != 1)
		die("Profile must contain exactly one selector outbound with x_rule main");
	if (!has_direct)
		die("Profile must contain a direct outbound");
}

function validate_profile_content(content) {
	let profile = parse_json_object(content, "Profile");
	validate_profile_object(profile);
	return profile;
}

function default_profile_source() {
	return {
		schema_version: 1,
		url: "https://testingcf.jsdelivr.net/gh/Vonzhen/singbox-profiles@master/profiles/main-profile.json",
		updated_at: ""
	};
}

function now_utc(trace_id) {
	let result = ExecResult(trace_id, [ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" ]);
	if (result.code == 0)
		return replace(replace(result.stdout || "", "\n", ""), "\r", "");
	return "";
}

function valid_template_url(url) {
	return substr(url, 0, 7) == "http://" || substr(url, 0, 8) == "https://";
}

function normalize_profile_source(source) {
	source = type(source) == "object" && source != null && type(source) != "array" ? source : {};
	let url = type(source.url) == "string" ? source.url : "";
	let updated_at = type(source.updated_at) == "string" ? source.updated_at : "";

	return {
		schema_version: 1,
		url: url,
		updated_at: updated_at
	};
}

function read_profile_source() {
	let content = read_optional_text(PATH.PROFILE_SOURCE);
	if (content == "")
		return default_profile_source();
	return normalize_profile_source(parse_json_object(content, "Profile Source"));
}

function profile_source_content(source) {
	return json_stringify(normalize_profile_source(source)) + "\n";
}

function get_profile(trace_id, req) {
	try {
		let content = read_text(PATH.PROFILE);
		let valid = true;
		let validation_error = "";

		try {
			validate_profile_content(content);
		} catch (e) {
			valid = false;
			validation_error = "" + e;
		}

		return Success({
			path: PATH.PROFILE,
			content: content,
			valid: valid,
			validation_error: validation_error
		}, 200, trace_id, "Profile loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_PROFILE_NOT_FOUND, "Failed to load Profile", trace_id, err);
	}
}

function profile_source_get(trace_id, req) {
	try {
		let source = read_profile_source();
		return Success({
			path: PATH.PROFILE_SOURCE,
			source: source,
			content: json_stringify(source)
		}, 200, trace_id, "Profile source loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_PROFILE_SOURCE_FAILED, "Failed to load Profile source", trace_id, err);
	}
}

function profile_source_save(trace_id, req) {
	let lock = null;
	try {
		let content = request_content(req);
		if (content == "")
			die("Missing Profile source content; request keys: " + request_keys(req));

		let source = normalize_profile_source(parse_json_object(content, "Profile Source"));
		if (source.url != "" && !valid_template_url(source.url))
			die("Profile template URL must start with http:// or https://");

		lock = acquire(trace_id);
		write_text_atomic(PATH.PROFILE_SOURCE, profile_source_content(source));
		release(lock);

		return Success({
			path: PATH.PROFILE_SOURCE,
			source: source
		}, 200, trace_id, "Profile source saved");
	} catch (e) {
		if (lock != null)
			release(lock);
		let err = "" + e;
		return Fail(ERR.E_PROFILE_SOURCE_FAILED, "Failed to save Profile source", trace_id, err);
	}
}

function profile_sync_remote(trace_id, req) {
	let lock = null;
	try {
		let source = read_profile_source();
		if (source.url == "")
			die("Profile template URL is empty");
		if (!valid_template_url(source.url))
			die("Profile template URL must start with http:// or https://");

		let content = ExecSafe(trace_id, [ BIN.TIMEOUT, "30", "wget", "-q", "-T", "20", "-Y", "off", "-O", "-", source.url ]);
		validate_profile_content(content);

		lock = acquire(trace_id);
		let current = read_text(PATH.PROFILE);
		write_text_atomic(PATH.PROFILE_BAK, current);
		write_text_atomic(PATH.PROFILE, content);
		source.updated_at = now_utc(trace_id);
		write_text_atomic(PATH.PROFILE_SOURCE, profile_source_content(source));
		release(lock);

		return Success({
			path: PATH.PROFILE,
			backup: PATH.PROFILE_BAK,
			source: source.url
		}, 200, trace_id, "Profile template synced");
	} catch (e) {
		if (lock != null)
			release(lock);
		let err = "" + e;
		return Fail(ERR.E_PROFILE_SYNC_FAILED, "Failed to sync Profile template", trace_id, err);
	}
}

function validate_profile(trace_id, req) {
	try {
		let content = request_content(req);
		if (content == "")
			die("Missing Profile content; request keys: " + request_keys(req));
		validate_profile_content(content);
		return Success({ valid: true }, 200, trace_id, "Profile is valid");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_PROFILE_INVALID_STRUCTURE, "Profile validation failed", trace_id, err);
	}
}

function save_profile(trace_id, req) {
	let lock = null;
	try {
		let content = request_content(req);
		if (content == "")
			die("Missing Profile content; request keys: " + request_keys(req));
		validate_profile_content(content);
		lock = acquire(trace_id);
		let current = read_text(PATH.PROFILE);
		write_text_atomic(PATH.PROFILE_BAK, current);
		write_text_atomic(PATH.PROFILE, content);
		release(lock);
		return Success({ path: PATH.PROFILE, backup: PATH.PROFILE_BAK }, 200, trace_id, "Profile saved");
	} catch (e) {
		if (lock != null)
			release(lock);
		let err = "" + e;
		return Fail(ERR.E_PROFILE_SAVE_FAILED, "Failed to save Profile", trace_id, err);
	}
}

function restore_default_profile(trace_id, req) {
	let lock = null;
	try {
		lock = acquire(trace_id);
		let current = read_text(PATH.PROFILE);
		let defaults = read_text(PATH.PROFILE_DEFAULT);
		validate_profile_content(defaults);
		write_text_atomic(PATH.PROFILE_BAK, current);
		write_text_atomic(PATH.PROFILE, defaults);
		release(lock);
		return Success({ path: PATH.PROFILE, backup: PATH.PROFILE_BAK }, 200, trace_id, "Default Profile restored");
	} catch (e) {
		if (lock != null)
			release(lock);
		let err = "" + e;
		return Fail(ERR.E_PROFILE_RESTORE_FAILED, "Failed to restore default Profile", trace_id, err);
	}
}

function rollback_profile(trace_id, req) {
	let lock = null;
	try {
		lock = acquire(trace_id);
		let backup = read_text(PATH.PROFILE_BAK);
		validate_profile_content(backup);
		let current = read_text(PATH.PROFILE);
		write_text_atomic(PATH.PROFILE_BAK, current);
		write_text_atomic(PATH.PROFILE, backup);
		release(lock);
		return Success({ path: PATH.PROFILE, backup: PATH.PROFILE_BAK }, 200, trace_id, "Profile rolled back");
	} catch (e) {
		if (lock != null)
			release(lock);
		let err = "" + e;
		return Fail(ERR.E_PROFILE_ROLLBACK_FAILED, "Failed to roll back Profile", trace_id, err);
	}
}

export { get_profile, profile_source_get, profile_source_save, profile_sync_remote, validate_profile, save_profile, restore_default_profile, rollback_profile };
