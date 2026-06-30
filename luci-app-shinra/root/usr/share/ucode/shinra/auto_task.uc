/**
 * Shinra | auto_task.uc | v1.1
 */

'use strict';

import { scheduler_status } from 'shinra.core.scheduler';

function auto_task_status_get(trace_id, req) {
	return scheduler_status(trace_id, req);
}

export { auto_task_status_get };
