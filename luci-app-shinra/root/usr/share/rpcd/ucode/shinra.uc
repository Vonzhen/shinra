'use strict';

import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { init as gen_trace_id } from 'shinra.core.trace';
import { get_profile, profile_source_get, profile_source_save, profile_sync_remote, validate_profile, save_profile, restore_default_profile, rollback_profile } from 'shinra.profile';
import { subscriptions_get, subscriptions_save, subscriptions_refresh, subscription_refresh_source, subscriptions_refresh_start, subscription_refresh_source_start, subscriptions_refresh_status, node_snapshot_get, node_snapshot_summary, subscription_test_source, subscription_fetch_preflight } from 'shinra.subscription';
import { runtime_status, runtime_start, runtime_stop, runtime_restart } from 'shinra.runtime';
import { generate_candidate, check_candidate } from 'shinra.generator';
import { config_apply, config_rollback, runtime_healthcheck } from 'shinra.apply';
import { dashboard_source_get, dashboard_source_save, dashboard_status } from 'shinra.dashboard_config';
import { api_status } from 'shinra.api_status';
import { logs_get, last_error_get, task_locks_get, task_lock_recover, diagnostics_get } from 'shinra.diagnostics';
import { connectivity_probe } from 'shinra.connectivity';
import { ruleset_inventory, ruleset_required_inventory, ruleset_policy_get, ruleset_policy_save, ruleset_download_required, ruleset_download_required_start, ruleset_download_required_status, ruleset_artifact_status, ruleset_download_one_start, ruleset_download_one_status } from 'shinra.ruleset';
import { notify_settings_get, notify_settings_save, notify_test_telegram } from 'shinra.notify';
import { auto_task_status_get } from 'shinra.auto_task';
import { scheduler_status, scheduler_tick } from 'shinra.scheduler';
import { net_fetch_test } from 'shinra.resource_fetch';
import { overview_status } from 'shinra.overview_status';

function request_args(req) {
	try {
		if (req != null && type(req.args) == "object" && req.args != null)
			return req.args;
	} catch (e) {
		let err = "" + e;
	}

	return {};
}

function gateway(trace_id, logic, req) {
	try {
		return logic(trace_id, request_args(req));
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_INTERNAL, "Gateway Crash: " + err, trace_id);
	}
}

const methods = {
	status: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, function(trace_id, req) {
				return Success({
					stage: "skeleton",
					runtime_ready: false
				}, 200, trace_id, "Stage 1 skeleton status");
			}, req);
		}
	},

	overview_status: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, overview_status, req);
		}
	},

	profile_get: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, get_profile, req);
		}
	},

	profile_source_get: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, profile_source_get, req);
		}
	},

	profile_source_save: {
		args: {
			content: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, profile_source_save, req);
		}
	},

	profile_sync_remote: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, profile_sync_remote, req);
		}
	},

	profile_validate: {
		args: {
			content: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, validate_profile, req);
		}
	},

	profile_save: {
		args: {
			content: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, save_profile, req);
		}
	},

	profile_restore_default: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, restore_default_profile, req);
		}
	},

	profile_rollback: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, rollback_profile, req);
		}
	},

	subscriptions_get: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, subscriptions_get, req);
		}
	},

	subscriptions_save: {
		args: {
			content: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, subscriptions_save, req);
		}
	},

	subscriptions_refresh: {
		args: {
			strategy: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, subscriptions_refresh, req);
		}
	},

	subscription_refresh_source: {
		args: {
			source_id: "",
			id: "",
			strategy: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, subscription_refresh_source, req);
		}
	},

	subscriptions_refresh_start: {
		args: {
			strategy: "",
			notify_intent: false
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, subscriptions_refresh_start, req);
		}
	},

	subscription_refresh_source_start: {
		args: {
			source_id: "",
			id: "",
			strategy: "",
			notify_intent: false
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, subscription_refresh_source_start, req);
		}
	},

	subscriptions_refresh_status: {
		args: {
			run_id: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, subscriptions_refresh_status, req);
		}
	},

	node_snapshot_get: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, node_snapshot_get, req);
		}
	},

	node_snapshot_summary: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, node_snapshot_summary, req);
		}
	},

	subscription_test_source: {
		args: {
			name: "",
			url: "",
			strategy: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, subscription_test_source, req);
		}
	},

	subscription_fetch_preflight: {
		args: {
			url: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, subscription_fetch_preflight, req);
		}
	},

	runtime_status: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, runtime_status, req);
		}
	},

	runtime_start: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, runtime_start, req);
		}
	},

	runtime_stop: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, runtime_stop, req);
		}
	},

	runtime_restart: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, runtime_restart, req);
		}
	},

	config_check_candidate: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, check_candidate, req);
		}
	},

	config_generate: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, generate_candidate, req);
		}
	},

	candidate_generate: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, generate_candidate, req);
		}
	},

	config_apply: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, config_apply, req);
		}
	},

	config_rollback: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, config_rollback, req);
		}
	},

	runtime_healthcheck: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, runtime_healthcheck, req);
		}
	},

	dashboard_source_get: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, dashboard_source_get, req);
		}
	},

	dashboard_source_save: {
		args: {
			content: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, dashboard_source_save, req);
		}
	},

	dashboard_status: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, dashboard_status, req);
		}
	},

	api_status: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, api_status, req);
		}
	},

	connectivity_probe: {
		args: {
			target: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, connectivity_probe, req);
		}
	},

	ruleset_inventory: {
		args: {
			source: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, ruleset_inventory, req);
		}
	},

	ruleset_required_inventory: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, ruleset_required_inventory, req);
		}
	},

	ruleset_policy_get: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, ruleset_policy_get, req);
		}
	},

	ruleset_policy_save: {
		args: {
			content: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, ruleset_policy_save, req);
		}
	},

	ruleset_download_required: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, ruleset_download_required, req);
		}
	},

	ruleset_download_required_start: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, ruleset_download_required_start, req);
		}
	},

	ruleset_download_required_status: {
		args: {
			run_id: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, ruleset_download_required_status, req);
		}
	},

	ruleset_artifact_status: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, ruleset_artifact_status, req);
		}
	},

	ruleset_download_one_start: {
		args: {
			tag: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, ruleset_download_one_start, req);
		}
	},

	ruleset_download_one_status: {
		args: {
			run_id: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, ruleset_download_one_status, req);
		}
	},

	notify_settings_get: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, notify_settings_get, req);
		}
	},

	notify_settings_save: {
		args: {
			content: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, notify_settings_save, req);
		}
	},

	notify_test_telegram: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, notify_test_telegram, req);
		}
	},

	auto_task_status_get: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, auto_task_status_get, req);
		}
	},

	scheduler_status: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, scheduler_status, req);
		}
	},

	scheduler_tick: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, scheduler_tick, req);
		}
	},

	net_fetch_test: {
		args: {
			url: "",
			policy: "",
			min_bytes: 0
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, net_fetch_test, req);
		}
	},

	logs_get: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, logs_get, req);
		}
	},

	last_error_get: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, last_error_get, req);
		}
	},

	task_locks_get: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, task_locks_get, req);
		}
	},

	task_lock_recover: {
		args: {
			task_type: ""
		},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, task_lock_recover, req);
		}
	},

	diagnostics_get: {
		args: {},
		call: function(req) {
			let trace_id = gen_trace_id();
			return gateway(trace_id, diagnostics_get, req);
		}
	}
};

return { shinra: methods };
