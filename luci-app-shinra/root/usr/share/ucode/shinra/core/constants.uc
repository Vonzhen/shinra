/**
 * Shinra | core/constants.uc | v1.0
 */

'use strict';

const PATH = {
	PROFILE: "/etc/shinra/main-profile.json",
	PROFILE_BAK: "/etc/shinra/main-profile.json.bak",
	PROFILE_DEFAULT: "/usr/share/shinra/profiles/main-profile.json",
	PROFILE_SOURCE: "/etc/shinra/profile-source.json",
	NOTIFY: "/etc/shinra/notify.json",
	NOTIFY_STATE: "/var/run/shinra/notify.state.json",
	ZASHBOARD_SOURCE: "/etc/shinra/zashboard-source.json",
	ZASHBOARD_DIR: "/www/shinra/zashboard",
	SUBSCRIPTIONS: "/etc/shinra/subscriptions.json",
	NODE_SNAPSHOT: "/etc/shinra/node-snapshot.json",
	RUNTIME_CONFIG: "/etc/shinra/runtime/config.json",
	RUNTIME_CONFIG_BAK: "/etc/shinra/runtime/config.json.bak",
	CANDIDATE_CONFIG: "/var/run/shinra/config.candidate.json",
	RUNTIME_STATE: "/var/run/shinra/runtime.state.json",
	AUTO_TASK_STATE: "/var/run/shinra/auto-task.state.json",
	JOB_STATE: "/var/run/shinra/job-state.json",
	LAST_APPLY_RESULT: "/var/run/shinra/last-apply-result",
	LAST_ERROR: "/var/run/shinra/last-error.log",
	RULE_DIR: "/etc/shinra/rules",
	RULE_DEFAULT_DIR: "/usr/share/shinra/rules",
	RUN_DIR: "/var/run/shinra",
	LOCK_DIR: "/var/run/shinra/lock"
};

const BIN = {
	SING_BOX: "sing-box",
	INIT: "/etc/init.d/shinra",
	TIMEOUT: "timeout"
};

const CLASH_API = {
	TRAFFIC: "http://127.0.0.1:20123/traffic",
	CONNECTIONS: "http://127.0.0.1:20123/connections",
	PROXIES: "http://127.0.0.1:20123/proxies"
};

export { PATH, BIN, CLASH_API };
