/**
 * Shinra | core/trace.uc | v1.0
 */

'use strict';

let seq = 0;

function init() {
	seq = seq + 1;
	return sprintf("shinra-%d-%d", time(), seq);
}

export { init };
