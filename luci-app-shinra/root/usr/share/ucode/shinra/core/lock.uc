/**
 * Shinra | core/lock.uc | v2.0
 */

'use strict';

import { mkdir, readfile, rmdir, stat, unlink, writefile } from 'fs';
import { PATH } from 'shinra.core.constants';
import { json_escape } from 'shinra.core.utils';

function ensure_dir(path) {
	let info = stat(path);
	if (type(info) == "object" && info != null)
		return;

	let ok = mkdir(path, 0700);
	if (!ok)
		die("Failed to create Shinra runtime directory: " + path);
}

function valid_resource(resource) {
	resource = "" + resource;
	if (resource == "")
		die("Lock resource must not be empty");

	for (let i = 0; i < length(resource); i = i + 1) {
		let ch = substr(resource, i, 1);
		let ok = (ch >= "a" && ch <= "z") ||
			(ch >= "0" && ch <= "9") ||
			ch == "." || ch == "_" || ch == "-";
		if (!ok)
			die("Invalid lock resource: " + resource);
	}

	return resource;
}

function lock_path(resource) {
	return PATH.LOCK_DIR + "/" + valid_resource(resource) + ".lock";
}

function lock_exists(resource) {
	let info = stat(lock_path(resource));
	return type(info) == "object" && info != null;
}

function owner_content(resource, trace_id) {
	return "{" +
		"\"schema_version\":1," +
		"\"resource\":\"" + json_escape(valid_resource(resource)) + "\"," +
		"\"trace_id\":\"" + json_escape(trace_id || "") + "\"" +
	"}\n";
}

function write_owner(path, resource, trace_id) {
	writefile(path + "/owner.json", owner_content(resource, trace_id));
}

function lock_try(resource, trace_id) {
	resource = valid_resource(resource);
	ensure_dir(PATH.RUN_DIR);
	ensure_dir(PATH.LOCK_DIR);

	let path = lock_path(resource);
	let ok = mkdir(path, 0700);
	if (!ok)
		return null;

	write_owner(path, resource, trace_id);
	return {
		resource: resource,
		path: path,
		trace_id: trace_id || ""
	};
}

function lock_acquire(resource, trace_id) {
	let lock = lock_try(resource, trace_id);
	if (lock == null)
		die("Failed to acquire Shinra resource lock: " + lock_path(resource) + " trace_id=" + trace_id);
	return lock;
}

function lock_release(handle) {
	if (type(handle) == "object" && handle != null && type(handle.path) == "string") {
		unlink(handle.path + "/owner.json");
		rmdir(handle.path);
	}
}

function lock_owner(resource) {
	let content = readfile(lock_path(resource) + "/owner.json");
	if (content == null)
		return "";
	return content;
}

export { lock_path, lock_acquire, lock_release, lock_try, lock_exists, lock_owner };
