/**
 * Shinra | apply.uc | v1.0
 */

'use strict';

import { PATH, BIN } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { acquire, release } from 'shinra.core.lock';
import { read_text, write_text_atomic, write_runtime_text_atomic, parse_json_object, file_exists, ensure_config_dir, ExecResult } from 'shinra.core.utils';
import { observe_runtime } from 'shinra.runtime';

function write_last_error(detail) {
	write_runtime_text_atomic(PATH.LAST_ERROR, "" + detail);
}

function write_last_apply_result(detail) {
	write_runtime_text_atomic(PATH.LAST_APPLY_RESULT, "" + detail);
}

function check_config_file(trace_id, path) {
	let result = ExecResult(trace_id, [ BIN.SING_BOX, "check", "-c", path ]);
	if (result.code != 0)
		die(result.stderr || result.stdout);
}

function runtime_observation_ready(observed) {
	let state = json(observed.state);
	return observed.running && state.tun_exists == true && state.clash_api_available == true;
}

function wait_runtime_ready(trace_id) {
	let observed = null;
	let ready = false;
	let attempts = 0;

	for (let i = 0; i < 8; i++) {
		observed = observe_runtime(trace_id);
		attempts = i + 1;
		ready = runtime_observation_ready(observed);
		if (ready)
			break;
		if (i < 7)
			ExecResult(trace_id, [ "sleep", "1" ]);
	}

	observed.health_ready = ready;
	observed.health_wait_attempts = attempts;
	return observed;
}

function restart_runtime(trace_id) {
	let result = ExecResult(trace_id, [ BIN.INIT, "restart" ]);
	if (result.code != 0)
		die(result.stderr || result.stdout);

	let observed = wait_runtime_ready(trace_id);
	if (!observed.running)
		die("Runtime restart did not create a running instance: " + observed.state);

	return observed;
}

function restore_backup(trace_id) {
	if (!file_exists(PATH.RUNTIME_CONFIG_BAK))
		return false;

	let backup = read_text(PATH.RUNTIME_CONFIG_BAK);
	parse_json_object(backup, "Runtime Config Backup");
	write_text_atomic(PATH.RUNTIME_CONFIG, backup);
	restart_runtime(trace_id);
	return true;
}

function config_apply(trace_id, req) {
	let lock = null;
	let backup_created = false;
	try {
		if (!file_exists(PATH.CANDIDATE_CONFIG))
			return Fail(ERR.E_CANDIDATE_NOT_FOUND, "Candidate config not found", trace_id, PATH.CANDIDATE_CONFIG);

		let candidate = read_text(PATH.CANDIDATE_CONFIG);
		parse_json_object(candidate, "Candidate Config");
		check_config_file(trace_id, PATH.CANDIDATE_CONFIG);

		lock = acquire(trace_id);
		ensure_config_dir();

		if (file_exists(PATH.RUNTIME_CONFIG)) {
			let current = read_text(PATH.RUNTIME_CONFIG);
			parse_json_object(current, "Runtime Config");
			write_text_atomic(PATH.RUNTIME_CONFIG_BAK, current);
			backup_created = true;
		}

		write_text_atomic(PATH.RUNTIME_CONFIG, candidate);
		write_last_error("");
		write_last_apply_result("apply_ok");
		let observed = restart_runtime(trace_id);
		release(lock);

		return Success({
			path: PATH.RUNTIME_CONFIG,
			backup: PATH.RUNTIME_CONFIG_BAK,
			backup_created: backup_created,
			health_ready: observed.health_ready,
			health_wait_attempts: observed.health_wait_attempts,
			state: json(observed.state)
		}, 200, trace_id, "Runtime config applied");
	} catch (e) {
		if (lock != null) {
			let err = "" + e;
			let rolled_back = false;
			try {
				if (backup_created)
					rolled_back = restore_backup(trace_id);
			} catch (rollback_error) {
				err = err + "; rollback failed: " + ("" + rollback_error);
			}
			write_last_error(err);
			write_last_apply_result("apply_failed");
			release(lock);
			return Fail(ERR.E_RUNTIME_APPLY_FAILED, "Failed to apply Runtime config", trace_id, err + "; rolled_back=" + rolled_back);
		}

		let err = "" + e;
		write_last_error(err);
		write_last_apply_result("apply_failed");
		return Fail(ERR.E_RUNTIME_APPLY_FAILED, "Failed to apply Runtime config", trace_id, err);
	}
}

function config_rollback(trace_id, req) {
	let lock = null;
	try {
		if (!file_exists(PATH.RUNTIME_CONFIG_BAK))
			return Fail(ERR.E_RUNTIME_CONFIG_NOT_FOUND, "Runtime backup config not found", trace_id, PATH.RUNTIME_CONFIG_BAK);

		let backup = read_text(PATH.RUNTIME_CONFIG_BAK);
		parse_json_object(backup, "Runtime Config Backup");
		check_config_file(trace_id, PATH.RUNTIME_CONFIG_BAK);

		lock = acquire(trace_id);
		let current = "";
		if (file_exists(PATH.RUNTIME_CONFIG))
			current = read_text(PATH.RUNTIME_CONFIG);

		write_text_atomic(PATH.RUNTIME_CONFIG, backup);
		if (current != "")
			write_text_atomic(PATH.RUNTIME_CONFIG_BAK, current);

		write_last_error("");
		write_last_apply_result("rollback_ok");
		let observed = restart_runtime(trace_id);
		release(lock);

		return Success({
			path: PATH.RUNTIME_CONFIG,
			backup: PATH.RUNTIME_CONFIG_BAK,
			health_ready: observed.health_ready,
			health_wait_attempts: observed.health_wait_attempts,
			state: json(observed.state)
		}, 200, trace_id, "Runtime config rolled back");
	} catch (e) {
		if (lock != null)
			release(lock);
		let err = "" + e;
		write_last_error(err);
		write_last_apply_result("rollback_failed");
		return Fail(ERR.E_RUNTIME_ROLLBACK_FAILED, "Failed to roll back Runtime config", trace_id, err);
	}
}

function runtime_healthcheck(trace_id, req) {
	try {
		let observed = observe_runtime(trace_id);
		if (!observed.running)
			return Fail(ERR.E_RUNTIME_HEALTHCHECK_FAILED, "Runtime healthcheck failed", trace_id, observed.state);

		return Success({
			path: PATH.RUNTIME_STATE,
			state: json(observed.state)
		}, 200, trace_id, "Runtime healthcheck passed");
	} catch (e) {
		let err = "" + e;
		write_last_error(err);
		return Fail(ERR.E_RUNTIME_HEALTHCHECK_FAILED, "Runtime healthcheck crashed", trace_id, err);
	}
}

export { config_apply, config_rollback, runtime_healthcheck };
