/**
 * Shinra | apply.uc | v1.0
 */

'use strict';

import { PATH, BIN } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { lock_acquire, lock_release } from 'shinra.core.lock';
import { write_runtime_text_atomic, file_exists, ExecResult, json_stringify } from 'shinra.core.utils';
import { artifact_check_config, artifact_commit_runtime, artifact_restore_runtime, artifact_swap_runtime_backup } from 'shinra.core.artifact';
import { observe_runtime, runtime_restart_owned } from 'shinra.runtime';
import { runtime_ownership_guard } from 'shinra.core.runtime_ownership';
import { ruleset_transaction_confirm, ruleset_transaction_restore } from 'shinra.core.ruleset_artifact';

function write_last_error(detail) {
	write_runtime_text_atomic(PATH.LAST_ERROR, "" + detail);
}

function write_last_apply_result(detail) {
	write_runtime_text_atomic(PATH.LAST_APPLY_RESULT, "" + detail);
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
	return runtime_restart_owned(trace_id);
}

function restore_backup(trace_id) {
	let restored = artifact_restore_runtime(trace_id, PATH.RUNTIME_CONFIG, PATH.RUNTIME_CONFIG_BAK).restored == true;
	if (!restored)
		return false;
	restart_runtime(trace_id);
	return true;
}

function restore_pending_rulesets(trace_id) {
	try {
		return ruleset_transaction_restore(trace_id);
	} catch (e) {
		return {
			pending: true,
			failed_count: 1,
			error: "" + e
		};
	}
}

function confirm_pending_rulesets(trace_id) {
	try {
		return ruleset_transaction_confirm(trace_id);
	} catch (e) {
		return {
			pending: true,
			failed_count: 1,
			error: "" + e
		};
	}
}

function config_apply(trace_id, req) {
	let lock = null;
	let backup_created = false;
	try {
		if (!file_exists(PATH.CANDIDATE_CONFIG))
			return Fail(ERR.E_CANDIDATE_NOT_FOUND, "Candidate config not found", trace_id, PATH.CANDIDATE_CONFIG);

		let check = artifact_check_config(trace_id, PATH.CANDIDATE_CONFIG);
		if (!check.ok)
			die(check.error);

		let guard = null;
		try {
			guard = runtime_ownership_guard(trace_id);
		} catch (ownership_error) {
			let err = "" + ownership_error;
			write_last_error(err);
			write_last_apply_result("apply_failed");
			return Fail(ERR.E_RUNTIME_OWNERSHIP_CHECK_FAILED, "Failed to check Runtime ownership", trace_id, err);
		}
		if (!guard.ok) {
			write_last_error(guard.detail);
			write_last_apply_result("apply_failed");
			return Fail(ERR.E_RUNTIME_FOREIGN_PROCESS, "Foreign sing-box runtime detected", trace_id, guard.detail);
		}

		lock = lock_acquire("runtime", trace_id);
		let committed = artifact_commit_runtime(trace_id, PATH.CANDIDATE_CONFIG, PATH.RUNTIME_CONFIG, PATH.RUNTIME_CONFIG_BAK);
		backup_created = committed.backup_created == true;

		write_last_error("");
		write_last_apply_result("apply_ok");
		let observed = restart_runtime(trace_id);
		let ruleset_transaction = confirm_pending_rulesets(trace_id);
		lock_release(lock);

		return Success({
			path: PATH.RUNTIME_CONFIG,
			backup: PATH.RUNTIME_CONFIG_BAK,
			backup_created: backup_created,
			health_ready: observed.health_ready,
			health_wait_attempts: observed.health_wait_attempts,
			stop_wait: observed.stop_wait || {},
			cleanup: observed.cleanup || {},
			ruleset_transaction: ruleset_transaction,
			state: json(observed.state)
		}, 200, trace_id, "Runtime config applied");
	} catch (e) {
		if (lock != null) {
			let err = "" + e;
			let rolled_back = false;
			let ruleset_rollback = restore_pending_rulesets(trace_id);
			try {
				if (backup_created)
					rolled_back = restore_backup(trace_id);
			} catch (rollback_error) {
				err = err + "; rollback failed: " + ("" + rollback_error);
			}
			if (ruleset_rollback.failed_count > 0)
				err = err + "; ruleset rollback failed: " + (ruleset_rollback.error || json_stringify(ruleset_rollback));
			write_last_error(err);
			write_last_apply_result("apply_failed");
			lock_release(lock);
			return Fail(ERR.E_RUNTIME_APPLY_FAILED, "Failed to apply Runtime config", trace_id, err + "; rolled_back=" + rolled_back + "; ruleset_rollback=" + json_stringify(ruleset_rollback));
		}

		let err = "" + e;
		let ruleset_rollback = restore_pending_rulesets(trace_id);
		if (ruleset_rollback.failed_count > 0)
			err = err + "; ruleset rollback failed: " + (ruleset_rollback.error || json_stringify(ruleset_rollback));
		write_last_error(err);
		write_last_apply_result("apply_failed");
		return Fail(ERR.E_RUNTIME_APPLY_FAILED, "Failed to apply Runtime config", trace_id, err + "; ruleset_rollback=" + json_stringify(ruleset_rollback));
	}
}

function config_rollback(trace_id, req) {
	let lock = null;
	try {
		if (!file_exists(PATH.RUNTIME_CONFIG_BAK))
			return Fail(ERR.E_RUNTIME_CONFIG_NOT_FOUND, "Runtime backup config not found", trace_id, PATH.RUNTIME_CONFIG_BAK);

		let check = artifact_check_config(trace_id, PATH.RUNTIME_CONFIG_BAK);
		if (!check.ok)
			return Fail(ERR.E_RUNTIME_ROLLBACK_FAILED, "Failed to roll back Runtime config", trace_id, check.error);

		lock = lock_acquire("runtime", trace_id);
		artifact_swap_runtime_backup(trace_id, PATH.RUNTIME_CONFIG, PATH.RUNTIME_CONFIG_BAK);

		write_last_error("");
		write_last_apply_result("rollback_ok");
		let observed = restart_runtime(trace_id);
		lock_release(lock);

		return Success({
			path: PATH.RUNTIME_CONFIG,
			backup: PATH.RUNTIME_CONFIG_BAK,
			health_ready: observed.health_ready,
			health_wait_attempts: observed.health_wait_attempts,
			stop_wait: observed.stop_wait || {},
			cleanup: observed.cleanup || {},
			state: json(observed.state)
		}, 200, trace_id, "Runtime config rolled back");
	} catch (e) {
		if (lock != null)
			lock_release(lock);
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
