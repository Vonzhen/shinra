/**
 * Shinra | core/auto_apply_state.uc | v1.0
 */

'use strict';

import { PATH } from 'shinra.core.constants';
import { write_runtime_text_atomic, json_stringify } from 'shinra.core.utils';

function state_write(trace_id, phase, status, detail, data) {
	let state = {
		schema_version: 1,
		trace_id: "" + trace_id,
		controller: "ruleset_auto_apply",
		phase: phase || "unknown",
		status: status || "unknown",
		detail: detail || "",
		data: type(data) == "object" && data != null ? data : {}
	};

	write_runtime_text_atomic(PATH.AUTO_APPLY_STATE, json_stringify(state) + "\n");
	return state;
}

function state_decision(trace_id, detail, data) {
	return state_write(trace_id, "decision", "blocked", detail, data);
}

function state_freeze(trace_id, detail, data) {
	return state_write(trace_id, "freeze", "converging", detail, data);
}

function state_candidate(trace_id, detail, data) {
	return state_write(trace_id, "candidate", "converging", detail, data);
}

function state_applying(trace_id, detail, data) {
	return state_write(trace_id, "applying", "converging", detail, data);
}

function state_verifying(trace_id, detail, data) {
	return state_write(trace_id, "verifying", "verifying", detail, data);
}

function state_rollback(trace_id, detail, data) {
	return state_write(trace_id, "rollback", "rollback", detail, data);
}

function state_rolled_back(trace_id, detail, data) {
	return state_write(trace_id, "rollback", "rolled_back", detail, data);
}

function state_success(trace_id, detail, data) {
	return state_write(trace_id, "stable", "success", detail, data);
}

function state_failed(trace_id, phase, detail, data) {
	return state_write(trace_id, phase || "failed", "failed", detail, data);
}

function state_degraded(trace_id, detail, data) {
	return state_write(trace_id, "rollback", "degraded", detail, data);
}

export { state_write, state_decision, state_freeze, state_candidate, state_applying, state_verifying, state_rollback, state_rolled_back, state_success, state_failed, state_degraded };
