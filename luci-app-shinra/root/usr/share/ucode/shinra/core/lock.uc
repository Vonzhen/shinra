/**
 * Shinra | core/lock.uc | v1.0
 */

'use strict';

import { mkdir, rmdir, stat } from 'fs';
import { PATH } from 'shinra.core.constants';

function ensure_dir(path) {
	let info = stat(path);
	if (type(info) == "object" && info != null)
		return;

	let ok = mkdir(path, 0700);
	if (!ok)
		die("Failed to create Shinra runtime directory: " + path);
}

function acquire(trace_id) {
	ensure_dir(PATH.RUN_DIR);

	let ok = mkdir(PATH.LOCK_DIR, 0700);
	if (!ok)
		die("Failed to acquire Shinra lock: " + PATH.LOCK_DIR + " trace_id=" + trace_id);

	return {
		path: PATH.LOCK_DIR,
		trace_id: trace_id
	};
}

function release(lock) {
	if (type(lock) == "object" && lock != null && type(lock.path) == "string")
		rmdir(lock.path);
}

export { acquire, release };
