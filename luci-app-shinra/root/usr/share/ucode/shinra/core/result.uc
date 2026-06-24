/**
 * Shinra | core/result.uc | v1.0
 */

'use strict';

import { ERR } from 'shinra.core.error';

function Success(data, status, trace_id, message) {
	return {
		ok: true,
		code: ERR.OK,
		message: message || "success",
		data: data || {},
		trace_id: trace_id || ""
	};
}

function Fail(code, message, trace_id, detail) {
	return {
		ok: false,
		code: code || ERR.E_INTERNAL,
		message: message || "failed",
		detail: detail || "",
		trace_id: trace_id || ""
	};
}

export { Success, Fail };
