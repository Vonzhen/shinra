/**
 * Shinra | core/ruleset_artifact.uc | v1.0
 */

'use strict';

import { mkdir, opendir, readfile, stat, unlink } from 'fs';
import { PATH } from 'shinra.core.constants';
import { parse_json_object, write_text_atomic, json_stringify, file_exists, ExecResult } from 'shinra.core.utils';

const LAST_GOOD_DIR = PATH.RULE_DIR + "/.last-good";
const PENDING_DIR = PATH.RULE_DIR + "/.pending";
const TRANSACTION_PATH = PENDING_DIR + "/transaction.json";

function now_utc(trace_id) {
	let result = ExecResult(trace_id, [ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" ]);
	return result.code == 0 ? replace(result.stdout, "\n", "") : "";
}

function safe_tag(tag) {
	tag = "" + tag;
	if (tag == "")
		die("Rule Set tag must not be empty");

	for (let i = 0; i < length(tag); i++) {
		let ch = substr(tag, i, 1);
		let ok = (ch >= "a" && ch <= "z") ||
			(ch >= "A" && ch <= "Z") ||
			(ch >= "0" && ch <= "9") ||
			ch == "." || ch == "_" || ch == "-" || ch == "!";
		if (!ok)
			die("Invalid Rule Set tag: " + tag);
	}

	return tag;
}

function dir_entry_name(entry) {
	if (entry == null)
		return "";
	if (type(entry) == "object" && entry.name != null)
		return "" + entry.name;
	return "" + entry;
}

function ensure_dirs() {
	if (!file_exists(PATH.RULE_DIR) && !mkdir(PATH.RULE_DIR, 0700))
		die("Failed to create " + PATH.RULE_DIR);
	if (!file_exists(LAST_GOOD_DIR) && !mkdir(LAST_GOOD_DIR, 0700))
		die("Failed to create " + LAST_GOOD_DIR);
	if (!file_exists(PENDING_DIR) && !mkdir(PENDING_DIR, 0700))
		die("Failed to create " + PENDING_DIR);
}

function dir_info(path) {
	let info = stat(path);
	return type(info) == "object" && info != null ? info : null;
}

function count_srs_files(path) {
	let dir = opendir(path);
	if (!dir)
		return 0;

	let count = 0;
	for (let item = dir.read(); item != null; item = dir.read()) {
		let name = dir_entry_name(item);
		if (length(name) > 4 && substr(name, length(name) - 4) == ".srs")
			count = count + 1;
	}

	dir.close();
	return count;
}

function managed_rule_path(path) {
	path = "" + path;
	return index(path, PATH.RULE_DIR + "/") == 0 && index(path, "/.tmp/") < 0 &&
		index(path, "/.pending/") < 0 && index(path, "/.last-good/") < 0;
}

function last_good_path(tag) {
	return LAST_GOOD_DIR + "/" + safe_tag(tag) + ".srs";
}

function copy_file(trace_id, src, dest) {
	let result = ExecResult(trace_id, [ "cp", "-f", src, dest ]);
	if (result.code != 0)
		die("Failed to copy " + src + " to " + dest + ": " + result.stderr);
}

function default_transaction(trace_id) {
	return {
		schema_version: 1,
		status: "pending_runtime_validation",
		started_at: now_utc(trace_id),
		updated_at: now_utc(trace_id),
		trace_id: trace_id,
		changed_files: []
	};
}

function read_transaction(trace_id) {
	if (!file_exists(TRANSACTION_PATH))
		return default_transaction(trace_id);

	let raw = readfile(TRANSACTION_PATH);
	let tx = parse_json_object(raw || "{}", "Ruleset transaction");
	if (type(tx.changed_files) != "array")
		tx.changed_files = [];
	if (type(tx.status) != "string" || tx.status == "")
		tx.status = "pending_runtime_validation";
	if (type(tx.trace_id) != "string" || tx.trace_id == "")
		tx.trace_id = trace_id;
	return tx;
}

function write_transaction(trace_id, tx) {
	ensure_dirs();
	tx.updated_at = now_utc(trace_id);
	write_text_atomic(TRANSACTION_PATH, json_stringify(tx));
}

function find_change(tx, path) {
	for (let i = 0; i < length(tx.changed_files); i++) {
		let item = tx.changed_files[i];
		if (type(item) == "object" && item != null && item.path == path)
			return i;
	}
	return -1;
}

function ruleset_transaction_prepare_change(trace_id, tag, live_path) {
	ensure_dirs();
	tag = safe_tag(tag);
	if (!managed_rule_path(live_path))
		die("Refusing to track unmanaged Rule Set path: " + live_path);

	let good_path = last_good_path(tag);
	let had_live = file_exists(live_path);
	let had_last_good = file_exists(good_path);

	if (had_live && !had_last_good) {
		copy_file(trace_id, live_path, good_path);
		had_last_good = true;
	}

	return {
		tag: tag,
		path: live_path,
		last_good_path: good_path,
		had_live: had_live,
		had_last_good: had_last_good
	};
}

function ruleset_transaction_record_change(trace_id, prepared) {
	if (type(prepared) != "object" || prepared == null)
		return {
			recorded: false
		};

	ensure_dirs();
	let tx = read_transaction(trace_id);
	let idx = find_change(tx, prepared.path);
	let item = {
		tag: prepared.tag,
		path: prepared.path,
		last_good_path: prepared.last_good_path,
		had_live: prepared.had_live == true,
		had_last_good: prepared.had_last_good == true
	};

	if (idx >= 0)
		tx.changed_files[idx] = item;
	else
		push(tx.changed_files, item);

	tx.status = "pending_runtime_validation";
	write_transaction(trace_id, tx);
	return {
		recorded: true,
		path: TRANSACTION_PATH,
		changed_count: length(tx.changed_files)
	};
}

function ruleset_transaction_pending() {
	if (!file_exists(TRANSACTION_PATH))
		return {
			pending: false,
			path: TRANSACTION_PATH,
			changed_count: 0
		};

	let tx = read_transaction("ruleset-pending");
	return {
		pending: length(tx.changed_files) > 0,
		path: TRANSACTION_PATH,
		changed_count: length(tx.changed_files),
		transaction: tx
	};
}

function ruleset_transaction_restore(trace_id) {
	if (!file_exists(TRANSACTION_PATH))
		return {
			pending: false,
			restored_count: 0,
			deleted_count: 0
		};

	let tx = read_transaction(trace_id);
	let restored = 0;
	let deleted = 0;
	let failed = [];

	for (let item in tx.changed_files) {
		if (type(item) != "object" || item == null || !managed_rule_path(item.path))
			continue;

		try {
			if (file_exists(item.last_good_path)) {
				copy_file(trace_id, item.last_good_path, item.path);
				restored = restored + 1;
			} else {
				unlink(item.path);
				deleted = deleted + 1;
			}
		} catch (e) {
			push(failed, {
				tag: item.tag || "",
				path: item.path || "",
				error: "" + e
			});
		}
	}

	if (length(failed) == 0)
		unlink(TRANSACTION_PATH);
	else {
		tx.status = "restore_failed";
		tx.failed = failed;
		write_transaction(trace_id, tx);
	}

	return {
		pending: true,
		restored_count: restored,
		deleted_count: deleted,
		failed_count: length(failed),
		failed: failed,
		path: TRANSACTION_PATH
	};
}

function ruleset_transaction_confirm(trace_id) {
	if (!file_exists(TRANSACTION_PATH))
		return {
			pending: false,
			confirmed_count: 0
		};

	ensure_dirs();
	let tx = read_transaction(trace_id);
	let confirmed = 0;
	let failed = [];

	for (let item in tx.changed_files) {
		if (type(item) != "object" || item == null || !managed_rule_path(item.path))
			continue;
		if (!file_exists(item.path))
			continue;

		try {
			copy_file(trace_id, item.path, item.last_good_path);
			confirmed = confirmed + 1;
		} catch (e) {
			push(failed, {
				tag: item.tag || "",
				path: item.path || "",
				error: "" + e
			});
		}
	}

	if (length(failed) == 0)
		unlink(TRANSACTION_PATH);
	else {
		tx.status = "confirm_failed";
		tx.failed = failed;
		write_transaction(trace_id, tx);
	}

	return {
		pending: true,
		confirmed_count: confirmed,
		failed_count: length(failed),
		failed: failed,
		path: TRANSACTION_PATH
	};
}

function ruleset_artifact_state(trace_id) {
	let pending = ruleset_transaction_pending();
	let good_info = dir_info(LAST_GOOD_DIR);
	let pending_tx = pending.transaction || {};

	return {
		rule_dir: PATH.RULE_DIR,
		last_good_dir: LAST_GOOD_DIR,
		pending_dir: PENDING_DIR,
		pending_path: TRANSACTION_PATH,
		pending: pending.pending == true,
		pending_status: pending_tx.status || "",
		pending_started_at: pending_tx.started_at || "",
		pending_updated_at: pending_tx.updated_at || "",
		pending_trace_id: pending_tx.trace_id || "",
		changed_count: pending.changed_count || 0,
		changed_files: pending_tx.changed_files || [],
		last_good_exists: good_info != null,
		last_good_count: good_info != null ? count_srs_files(LAST_GOOD_DIR) : 0,
		last_good_mtime: good_info != null ? (good_info.mtime || 0) : 0
	};
}

export { ruleset_transaction_prepare_change, ruleset_transaction_record_change, ruleset_transaction_pending, ruleset_transaction_restore, ruleset_transaction_confirm, ruleset_artifact_state };
