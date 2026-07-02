/**
 * Shinra | auto_apply.uc | v1.0
 */

'use strict';

import { lock_try, lock_release } from 'shinra.core.lock';
import { PATH } from 'shinra.core.constants';
import { generate_candidate, check_candidate } from 'shinra.generator';
import { config_apply } from 'shinra.apply';
import { observe_runtime } from 'shinra.runtime';
import { runtime_restart_owned } from 'shinra.runtime';
import { artifact_restore_runtime } from 'shinra.core.artifact';
import { ruleset_transaction_confirm, ruleset_transaction_restore } from 'shinra.core.ruleset_artifact';
import { state_decision, state_freeze, state_candidate, state_applying, state_verifying, state_rollback, state_rolled_back, state_success, state_failed, state_degraded } from 'shinra.core.auto_apply_state';
import { ExecResult } from 'shinra.core.utils';

const FREEZE_RESOURCES = [ "auto_apply", "ruleset" ];
const STABLE_REQUIRED_CHECKS = 3;
const STABLE_MAX_ATTEMPTS = 6;
const STABLE_INTERVAL_SEC = 2;

function bool_field(obj, key) {
	return type(obj) == "object" && obj != null && obj[key] == true;
}

function int_field(obj, key) {
	if (type(obj) == "object" && obj != null && obj[key] != null)
		return int(obj[key]);
	return 0;
}

function string_field(obj, key) {
	if (type(obj) == "object" && obj != null && type(obj[key]) == "string")
		return obj[key];
	return "";
}

function object_field(obj, key) {
	if (type(obj) == "object" && obj != null && type(obj[key]) == "object" && obj[key] != null && type(obj[key]) != "array")
		return obj[key];
	return {};
}

function deny(reason, detail) {
	return {
		attempted: false,
		eligible: false,
		dry_run: true,
		stage: "decision",
		blocked_reason: reason,
		detail: detail || "",
		freeze: {
			checked: false,
			acquired: false,
			blocked_resource: ""
		}
	};
}

function deny_with_state(trace_id, reason, detail) {
	let result = deny(reason, detail);
	state_decision(trace_id, detail || reason || "", {
		blocked_reason: reason || "",
		result: result
	});
	return result;
}

function allow(detail, freeze) {
	return {
		attempted: false,
		eligible: true,
		dry_run: true,
		stage: "dry_run_ready",
		blocked_reason: "",
		detail: detail || "Auto-apply would start in a later phase.",
		freeze: freeze || {
			checked: false,
			acquired: false,
			blocked_resource: ""
		}
	};
}

function auto_apply_requested(req) {
	return bool_field(req, "auto_apply_intent") || bool_field(req, "scheduler_intent") || string_field(req, "source") == "scheduler";
}

function release_all(locks) {
	for (let i = length(locks) - 1; i >= 0; i = i - 1)
		lock_release(locks[i]);
}

function acquire_freeze_window(trace_id) {
	let locks = [];

	for (let resource in FREEZE_RESOURCES) {
		let lock = lock_try(resource, trace_id);
		if (lock == null) {
			release_all(locks);
			return {
				ok: false,
				checked: true,
				acquired: false,
				blocked_resource: resource,
				locks: []
			};
		}
		push(locks, lock);
	}

	return {
		ok: true,
		checked: true,
		acquired: true,
		blocked_resource: "",
		locks: locks
	};
}

function public_freeze(freeze) {
	return {
		ok: freeze.ok == true,
		checked: freeze.checked == true,
		acquired: freeze.acquired == true,
		blocked_resource: freeze.blocked_resource || ""
	};
}

function restore_rulesets_safe(trace_id) {
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

function confirm_rulesets_safe(trace_id) {
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

function failed_after_attempt(stage, detail, freeze, candidate, ruleset_restore) {
	let result = {
		attempted: true,
		eligible: true,
		ok: false,
		dry_run: false,
		stage: stage,
		blocked_reason: "",
		detail: detail || "",
		freeze: public_freeze(freeze),
		candidate: candidate || {},
		ruleset_restore: ruleset_restore || {}
	};
	return result;
}

function success_after_apply(freeze, candidate, runtime_apply, runtime_verify, ruleset_confirm) {
	let result = {
		attempted: true,
		eligible: true,
		ok: true,
		dry_run: false,
		stage: "stable_success",
		blocked_reason: "",
		detail: "Candidate generated, checked, applied, and Runtime stability verification passed.",
		freeze: public_freeze(freeze),
		candidate: candidate,
		runtime_apply: runtime_apply,
		runtime_verify: runtime_verify || {},
		ruleset_confirm: ruleset_confirm || {}
	};
	return result;
}

function runtime_ready_state(observed) {
	if (type(observed) != "object" || observed == null)
		return false;
	let state = json(observed.state);
	return observed.running == true && state.tun_exists == true && state.clash_api_available == true;
}

function verify_runtime_stable(trace_id) {
	let consecutive = 0;
	let attempts = 0;
	let checks = [];
	let last_state = {};

	for (let i = 0; i < STABLE_MAX_ATTEMPTS; i++) {
		let observed = observe_runtime(trace_id);
		let state = json(observed.state);
		let ready = runtime_ready_state(observed);
		attempts = i + 1;
		last_state = state;

		if (ready)
			consecutive = consecutive + 1;
		else
			consecutive = 0;

		push(checks, {
			attempt: attempts,
			ready: ready,
			consecutive_ready: consecutive,
			sing_box_running: state.sing_box_running == true,
			tun_exists: state.tun_exists == true,
			clash_api_available: state.clash_api_available == true,
			checked_at: state.checked_at || ""
		});

		if (consecutive >= STABLE_REQUIRED_CHECKS)
			return {
				ok: true,
				stage: "stable_success",
				attempts: attempts,
				required_checks: STABLE_REQUIRED_CHECKS,
				consecutive_ready: consecutive,
				interval_sec: STABLE_INTERVAL_SEC,
				checks: checks,
				state: state
			};

		if (i < STABLE_MAX_ATTEMPTS - 1)
			ExecResult(trace_id, [ "sleep", "" + STABLE_INTERVAL_SEC ]);
	}

	return {
		ok: false,
		stage: "runtime_verify_timeout",
		attempts: attempts,
		required_checks: STABLE_REQUIRED_CHECKS,
		consecutive_ready: consecutive,
		interval_sec: STABLE_INTERVAL_SEC,
		checks: checks,
		state: last_state
	};
}

function failed_after_verify(detail, freeze, candidate, runtime_apply, runtime_verify) {
	return {
		attempted: true,
		eligible: true,
		ok: false,
		dry_run: false,
		stage: "runtime_verify_timeout",
		blocked_reason: "",
		detail: detail || "Runtime did not stay healthy for the required stability window.",
		freeze: public_freeze(freeze),
		candidate: candidate || {},
		runtime_apply: runtime_apply || {},
		runtime_verify: runtime_verify || {}
	};
}

function rollback_runtime_and_rulesets(trace_id) {
	state_rollback(trace_id, "Runtime verification failed; rollback started.", {});

	let runtime_lock = lock_try("runtime", trace_id);
	if (runtime_lock == null)
		return {
			ok: false,
			stage: "rollback_degraded",
			error: "runtime_lock_busy",
			runtime_restore: {},
			ruleset_restore: {},
			runtime_restart: {},
			runtime_verify: {}
		};

	let runtime_restore = {};
	let ruleset_restore = {};
	let runtime_restart = {};
	let runtime_verify = {};

	try {
		runtime_restore = artifact_restore_runtime(trace_id, PATH.RUNTIME_CONFIG, PATH.RUNTIME_CONFIG_BAK);
		ruleset_restore = restore_rulesets_safe(trace_id);
		if (runtime_restore.restored != true) {
			lock_release(runtime_lock);
			return {
				ok: false,
				stage: "rollback_degraded",
				error: "runtime_backup_not_restored",
				runtime_restore: runtime_restore,
				ruleset_restore: ruleset_restore,
				runtime_restart: runtime_restart,
				runtime_verify: runtime_verify
			};
		}

		runtime_restart = runtime_restart_owned(trace_id);
		runtime_verify = verify_runtime_stable(trace_id);
		lock_release(runtime_lock);

		let ruleset_failed = int_field(ruleset_restore, "failed_count") > 0;
		return {
			ok: runtime_verify.ok == true && !ruleset_failed,
			stage: runtime_verify.ok == true && !ruleset_failed ? "rollback_success" : "rollback_degraded",
			error: "",
			runtime_restore: runtime_restore,
			ruleset_restore: ruleset_restore,
			runtime_restart: runtime_restart,
			runtime_verify: runtime_verify
		};
	} catch (e) {
		lock_release(runtime_lock);
		return {
			ok: false,
			stage: "rollback_degraded",
			error: "" + e,
			runtime_restore: runtime_restore,
			ruleset_restore: ruleset_restore,
			runtime_restart: runtime_restart,
			runtime_verify: runtime_verify
		};
	}
}

function failed_after_verify_rollback(detail, freeze, candidate, runtime_apply, runtime_verify, rollback) {
	return {
		attempted: true,
		eligible: true,
		ok: false,
		dry_run: false,
		stage: rollback && rollback.ok == true ? "rollback_success" : "rollback_degraded",
		blocked_reason: "",
		detail: detail || "Runtime stability verification failed; rollback was attempted.",
		freeze: public_freeze(freeze),
		candidate: candidate || {},
		runtime_apply: runtime_apply || {},
		runtime_verify: runtime_verify || {},
		rollback: rollback || {}
	};
}

function maybe_auto_apply_ruleset_update(trace_id, ruleset_result, req) {
	ruleset_result = type(ruleset_result) == "object" && ruleset_result != null ? ruleset_result : {};
	req = type(req) == "object" && req != null ? req : {};

	let policy = object_field(req, "ruleset_policy");
	let updated_count = int_field(ruleset_result, "updated_count");
	let failed_count = int_field(ruleset_result, "failed_count");
	let mode = string_field(ruleset_result, "mode");

	if (!auto_apply_requested(req))
		return deny_with_state(trace_id, "not_auto_task", "Auto-apply is limited to scheduled Rule Set updates.");
	if (!bool_field(policy, "auto_apply_after_update"))
		return deny_with_state(trace_id, "disabled", "ruleset.auto_apply_after_update is false.");
	if (failed_count > 0)
		return deny_with_state(trace_id, "ruleset_partial", "Rule Set update has failed items.");
	if (updated_count <= 0)
		return deny_with_state(trace_id, "no_updates", "Rule Set update did not change any files.");
	if (mode != "local")
		return deny_with_state(trace_id, "not_local_mode", "Auto-apply only applies local Rule Set updates.");

	let freeze = acquire_freeze_window(trace_id);
	if (!freeze.ok) {
		let result = {
			attempted: false,
			eligible: false,
			ok: false,
			dry_run: false,
			stage: "decision",
			blocked_reason: "freeze_busy",
			detail: "Auto-apply freeze window is busy: " + freeze.blocked_resource,
			freeze: public_freeze(freeze)
		};
		state_decision(trace_id, result.detail, {
			blocked_reason: result.blocked_reason,
			freeze: result.freeze
		});
		return result;
	}

	try {
		state_freeze(trace_id, "Auto-apply freeze window acquired.", {
			freeze: public_freeze(freeze)
		});

		state_candidate(trace_id, "Generating candidate config.", {
			ruleset_result: ruleset_result
		});
		let generated = generate_candidate(trace_id, {});
		if (!generated || generated.ok != true) {
			let restored = restore_rulesets_safe(trace_id);
			release_all(freeze.locks);
			let result = failed_after_attempt("candidate_generate_failed", generated ? (generated.detail || generated.message || generated.code || "") : "generate_candidate failed", freeze, {
				generated: generated || null,
				checked: null
			}, restored);
			state_failed(trace_id, result.stage, result.detail, result);
			return result;
		}

		state_candidate(trace_id, "Checking candidate config.", {
			generated: generated
		});
		let checked = check_candidate(trace_id, {});
		if (!checked || checked.ok != true) {
			let restored = restore_rulesets_safe(trace_id);
			release_all(freeze.locks);
			let result = failed_after_attempt("candidate_check_failed", checked ? (checked.detail || checked.message || checked.code || "") : "check_candidate failed", freeze, {
				generated: generated,
				checked: checked || null
			}, restored);
			state_failed(trace_id, result.stage, result.detail, result);
			return result;
		}

		state_applying(trace_id, "Applying checked candidate to Runtime.", {
			generated: generated,
			checked: checked
		});
		let applied = config_apply(trace_id, { defer_ruleset_confirm: true });
		if (!applied || applied.ok != true) {
			let restored = restore_rulesets_safe(trace_id);
			release_all(freeze.locks);
			let result = failed_after_attempt("runtime_apply_failed", applied ? (applied.detail || applied.message || applied.code || "") : "config_apply failed", freeze, {
				generated: generated,
				checked: checked
			}, restored);
			state_failed(trace_id, result.stage, result.detail, result);
			return result;
		}

		state_verifying(trace_id, "Runtime apply completed; stability window verification started.", {
			runtime_apply: applied
		});
		let verified = verify_runtime_stable(trace_id);
		if (!verified.ok) {
			let rollback = rollback_runtime_and_rulesets(trace_id);
			release_all(freeze.locks);
			let result = failed_after_verify_rollback("Runtime did not pass the stability window; rollback was attempted.", freeze, {
				generated: generated,
				checked: checked
			}, applied, verified, rollback);
			if (rollback && rollback.ok == true)
				state_rolled_back(trace_id, result.detail, result);
			else
				state_degraded(trace_id, result.detail, result);
			return result;
		}

		let confirmed = confirm_rulesets_safe(trace_id);
		if (int_field(confirmed, "failed_count") > 0) {
			release_all(freeze.locks);
			let result = failed_after_attempt("ruleset_confirm_failed", confirmed.error || "Rule Set transaction confirm failed", freeze, {
				generated: generated,
				checked: checked
			}, confirmed);
			state_degraded(trace_id, result.detail, result);
			return result;
		}

		release_all(freeze.locks);
		let result = success_after_apply(freeze, {
			generated: generated,
			checked: checked
		}, applied, verified, confirmed);
		state_success(trace_id, result.detail, result);
		return result;
	} catch (e) {
		let restored = restore_rulesets_safe(trace_id);
		release_all(freeze.locks);
		let result = failed_after_attempt("candidate_crashed", "" + e, freeze, {}, restored);
		state_failed(trace_id, result.stage, result.detail, result);
		return result;
	}
}

export { maybe_auto_apply_ruleset_update };
