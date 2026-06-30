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
	AUTO_TASK_SCRIPT: "/usr/libexec/shinra-auto-task",
	CRON_ROOT: "/etc/crontabs/root",
	TASK_DIR: "/var/run/shinra/tasks",
	RUNNER_DIR: "/var/run/shinra/runner",
	SCHEDULER_DIR: "/var/run/shinra/scheduler",
	SCHEDULER_STATE: "/var/run/shinra/scheduler/state.json",
	LAST_APPLY_RESULT: "/var/run/shinra/last-apply-result",
	LAST_ERROR: "/var/run/shinra/last-error.log",
	RULE_DIR: "/etc/shinra/rules",
	RULE_DEFAULT_DIR: "/usr/share/shinra/rules",
	RUN_DIR: "/var/run/shinra",
	LOCK_DIR: "/var/run/shinra/locks"
};

const BIN = {
	SING_BOX: "sing-box",
	INIT: "/etc/init.d/shinra",
	TIMEOUT: "timeout",
	WGET: "wget"
};

const CLASH_API = {
	DEFAULT_EXTERNAL_CONTROLLER: "0.0.0.0:20123"
};

const CONTROL_PLANE_PROXY = {
	TAG: "shinra-control-proxy",
	LISTEN: "127.0.0.1",
	PORT: 20124,
	URL: "http://127.0.0.1:20124"
};

const AUTO_TASK = {
	CRON_ENTRY: "5 * * * * /usr/libexec/shinra-auto-task >/dev/null 2>&1"
};

export { PATH, BIN, CLASH_API, CONTROL_PLANE_PROXY, AUTO_TASK };
