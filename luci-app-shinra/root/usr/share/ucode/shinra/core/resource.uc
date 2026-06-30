/**
 * Shinra | core/resource.uc | v1.0
 */

'use strict';

import { rename, stat, unlink } from 'fs';
import { fetch_file } from 'shinra.resource_fetch';
import { ExecResult, ExecSafe, file_exists } from 'shinra.core.utils';

function safe_name(value, label) {
	value = "" + value;
	if (value == "")
		die(label + " must not be empty");

	for (let i = 0; i < length(value); i = i + 1) {
		let ch = substr(value, i, 1);
		let ok = (ch >= "a" && ch <= "z") ||
			(ch >= "0" && ch <= "9") ||
			ch == "." || ch == "_" || ch == "-";
		if (!ok)
			die("Invalid " + label + ": " + value);
	}

	return value;
}

function safe_trace(trace_id) {
	let value = "" + (trace_id || "resource");
	let out = "";
	for (let i = 0; i < length(value); i = i + 1) {
		let ch = substr(value, i, 1);
		let ok = (ch >= "A" && ch <= "Z") ||
			(ch >= "a" && ch <= "z") ||
			(ch >= "0" && ch <= "9") ||
			ch == "." || ch == "_" || ch == "-";
		out = out + (ok ? ch : "_");
	}
	return out == "" ? "resource" : out;
}

function dir_exists(path) {
	let info = stat(path);
	return type(info) == "object" && info != null;
}

function run_best_effort(trace_id, argv) {
	let result = ExecResult(trace_id || "resource", argv);
	return result.code == 0;
}

function cleanup_allowed(path) {
	path = "" + path;
	return index(path, "/tmp/shinra-") == 0 || index(path, "/var/run/shinra/") == 0;
}

function resource_cleanup(paths) {
	if (type(paths) != "array")
		return;

	for (let path in paths) {
		if (path == null || path == "")
			continue;
		if (!cleanup_allowed(path))
			die("Refusing to cleanup unsafe resource path: " + path);
		run_best_effort("resource-cleanup", [ "rm", "-rf", path ]);
	}
}

function resource_stage_dir(resource_type, trace_id) {
	resource_type = safe_name(resource_type, "resource_type");
	let work_dir = "/tmp/shinra-" + resource_type + "-" + safe_trace(trace_id);
	let stage_dir = work_dir + "/stage";

	resource_cleanup([ work_dir ]);
	ExecSafe(trace_id, [ "mkdir", "-p", stage_dir ]);
	return {
		work_dir: work_dir,
		stage_dir: stage_dir
	};
}

function resource_fetch_file(trace_id, url, dest, strategy, opts) {
	return fetch_file(trace_id, url, dest, strategy, opts);
}

function resource_promote_file(stage_path, final_path, opts) {
	opts = type(opts) == "object" && opts != null ? opts : {};
	let stage_suffix = opts.stage_suffix || ".stage";
	let backup_suffix = opts.backup_suffix || ".bak";
	let stage_error = opts.stage_error || "Failed to stage resource file: ";
	let backup_error = opts.backup_error || "Failed to backup resource file: ";
	let promote_error = opts.promote_error || "Failed to promote resource file: ";
	let promote_stage = final_path + stage_suffix;
	let backup_path = final_path + backup_suffix;
	let had_live = file_exists(final_path);

	unlink(promote_stage);
	if (!rename(stage_path, promote_stage)) {
		unlink(stage_path);
		die(stage_error + final_path);
	}

	if (had_live) {
		unlink(backup_path);
		if (!rename(final_path, backup_path)) {
			unlink(promote_stage);
			die(backup_error + final_path);
		}
	}

	if (rename(promote_stage, final_path)) {
		return {
			final_path: final_path,
			backup_path: backup_path,
			backup_created: had_live,
			restored: false
		};
	}

	let restored = false;
	if (had_live && file_exists(backup_path))
		restored = rename(backup_path, final_path) ? true : false;
	unlink(promote_stage);
	die(promote_error + final_path + "; restored=" + (restored ? "true" : "false"));
}

function resource_promote_dir(stage_dir, live_dir, opts) {
	opts = type(opts) == "object" && opts != null ? opts : {};
	let trace_id = opts.trace_id || "resource";
	let last_good_dir = opts.last_good_dir || (live_dir + ".last-good");
	let stale_dir = last_good_dir + ".stale";
	let had_live = dir_exists(live_dir);
	let had_last_good = dir_exists(last_good_dir);

	if (!dir_exists(stage_dir))
		die("Resource stage directory missing: " + stage_dir);

	run_best_effort(trace_id, [ "rm", "-rf", stale_dir ]);
	if (had_live && had_last_good && !run_best_effort(trace_id, [ "mv", last_good_dir, stale_dir ]))
		die("Failed to rotate last-good resource directory: " + last_good_dir);

	if (had_live && !run_best_effort(trace_id, [ "mv", live_dir, last_good_dir ])) {
		if (dir_exists(stale_dir))
			run_best_effort(trace_id, [ "mv", stale_dir, last_good_dir ]);
		die("Failed to backup live resource directory: " + live_dir);
	}

	if (run_best_effort(trace_id, [ "mv", stage_dir, live_dir ])) {
		run_best_effort(trace_id, [ "rm", "-rf", stale_dir ]);
		return {
			live_dir: live_dir,
			stage_dir: stage_dir,
			last_good_dir: last_good_dir,
			backup_created: had_live,
			restored: false
		};
	}

	let restored = false;
	if (had_live && dir_exists(last_good_dir))
		restored = run_best_effort(trace_id, [ "mv", last_good_dir, live_dir ]);
	if (dir_exists(stale_dir) && !dir_exists(last_good_dir))
		run_best_effort(trace_id, [ "mv", stale_dir, last_good_dir ]);
	die("Failed to promote resource directory: " + live_dir + "; restored=" + (restored ? "true" : "false"));
}

export { resource_stage_dir, resource_fetch_file, resource_promote_file, resource_promote_dir, resource_cleanup };
