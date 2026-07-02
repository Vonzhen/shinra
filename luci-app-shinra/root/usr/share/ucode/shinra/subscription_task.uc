/**
 * Shinra | subscription_task.uc | v1.0
 */

'use strict';

import { mkdir, stat } from 'fs';
import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { validate_refresh_strategy } from 'shinra.subscription_policy';
import { task_path, read_task, patch_task, running_task } from 'shinra.core.task';

const SUBSCRIPTION_REFRESH_TASK = "subscription.refresh";
const SUBSCRIPTION_REFRESH_TRACE = "shinra-runner-subscription-refresh";

function subscription_refresh_task_enabled(trace_id) {
	return trace_id == SUBSCRIPTION_REFRESH_TRACE;
}

function progress_percent(done, total) {
	done = int(done || 0);
	total = int(total || 0);
	if (total <= 0)
		return 0;
	if (done >= total)
		return 100;
	return int((done * 100) / total);
}

function redacted_url(url) {
	if (type(url) != "string" || url == "")
		return "";

	let scheme = "";
	let rest = url;
	if (substr(url, 0, 8) == "https://") {
		scheme = "https://";
		rest = substr(url, 8);
	} else if (substr(url, 0, 7) == "http://") {
		scheme = "http://";
		rest = substr(url, 7);
	}

	let slash = index(rest, "/");
	let host = slash >= 0 ? substr(rest, 0, slash) : rest;
	if (host == "")
		return "";
	return scheme + host + "/...";
}

function write_subscription_refresh_task(trace_id, patch) {
	try {
		if (!subscription_refresh_task_enabled(trace_id))
			return;
		if (patch.status == "running")
			running_task(SUBSCRIPTION_REFRESH_TASK, trace_id, patch);
		else
			patch_task(SUBSCRIPTION_REFRESH_TASK, patch);
	} catch (e) {
		/* Progress must never fail the actual refresh. */
	}
}

function path_exists(path) {
	let info = stat(path);
	return type(info) == "object" && info != null;
}

function source_arg(req, key) {
	if (type(req) == "object" && req != null && type(req[key]) == "string")
		return req[key];
	return "";
}

function subscription_refresh_runner_strategy(req) {
	if (type(req) != "object" || req == null || type(req.strategy) != "string" || req.strategy == "")
		return "";
	if (req.strategy == "saved")
		return "";
	validate_refresh_strategy(req.strategy);
	return req.strategy;
}

function notify_intent_arg(req) {
	if (type(req) == "object" && req != null && req.notify_intent == true)
		return " notify";
	return "";
}

function shell_safe_token(value, label) {
	value = "" + value;
	if (value == "")
		die("Missing " + label);

	for (let i = 0; i < length(value); i++) {
		let ch = substr(value, i, 1);
		let ok = (ch >= "A" && ch <= "Z") ||
			(ch >= "a" && ch <= "z") ||
			(ch >= "0" && ch <= "9") ||
			ch == "." || ch == "_" || ch == "-";
		if (!ok)
			die("Invalid " + label + ": " + value);
	}

	return value;
}

function subscriptions_refresh_status(trace_id, req) {
	try {
		let path = task_path(SUBSCRIPTION_REFRESH_TASK);
		return Success({
			path: path,
			exists: path_exists(path),
			task: read_task(SUBSCRIPTION_REFRESH_TASK)
		}, 200, trace_id, "Subscription refresh task status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Failed to load Subscription refresh task status", trace_id, err);
	}
}

function subscriptions_refresh_start(trace_id, req) {
	try {
		if (!path_exists(PATH.RUN_DIR) && !mkdir(PATH.RUN_DIR, 0700))
			die("Failed to create Run directory: " + PATH.RUN_DIR);
		if (!path_exists(PATH.RUNNER_DIR) && !mkdir(PATH.RUNNER_DIR, 0700))
			die("Failed to create Runner directory: " + PATH.RUNNER_DIR);

		let strategy = subscription_refresh_runner_strategy(req);
		let lock_info = stat(PATH.RUNNER_DIR + "/subscription.refresh.lock");
		let path = task_path(SUBSCRIPTION_REFRESH_TASK);
		let task = read_task(SUBSCRIPTION_REFRESH_TASK);
		if (type(lock_info) == "object" && lock_info != null) {
			return Success({
				path: path,
				task: task,
				started: false,
				reason: "lock_present"
			}, 200, trace_id, "Subscription refresh task is already running");
		}

		let command = "/usr/libexec/shinra-runner subscription.refresh subscriptions_refresh " + SUBSCRIPTION_REFRESH_TRACE;
		if (strategy != "")
			command = command + " " + strategy;
		else if (notify_intent_arg(req) != "")
			command = command + " -";
		command = command + notify_intent_arg(req);
		let code = system(command + " >/dev/null 2>&1 &");
		if (code != 0)
			die("Failed to start /usr/libexec/shinra-runner: " + code);

		task = read_task(SUBSCRIPTION_REFRESH_TASK);
		task.status = "starting";
		task.message = "Subscription refresh queued";
		task.trace_id = trace_id;
		return Success({
			path: path,
			task: task,
			started: true
		}, 202, trace_id, "Subscription refresh task started");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Failed to start Subscription refresh task", trace_id, err);
	}
}

function subscription_refresh_source_start(trace_id, req) {
	try {
		if (!path_exists(PATH.RUN_DIR) && !mkdir(PATH.RUN_DIR, 0700))
			die("Failed to create Run directory: " + PATH.RUN_DIR);
		if (!path_exists(PATH.RUNNER_DIR) && !mkdir(PATH.RUNNER_DIR, 0700))
			die("Failed to create Runner directory: " + PATH.RUNNER_DIR);

		let source_id = source_arg(req, "source_id");
		if (source_id == "")
			source_id = source_arg(req, "id");
		source_id = shell_safe_token(source_id, "source_id");
		let strategy = subscription_refresh_runner_strategy(req);
		let lock_info = stat(PATH.RUNNER_DIR + "/subscription.refresh.lock");
		let path = task_path(SUBSCRIPTION_REFRESH_TASK);
		let task = read_task(SUBSCRIPTION_REFRESH_TASK);
		if (type(lock_info) == "object" && lock_info != null) {
			return Success({
				path: path,
				task: task,
				started: false,
				reason: "lock_present"
			}, 200, trace_id, "Subscription refresh task is already running");
		}

		let command = "/usr/libexec/shinra-runner subscription.refresh subscription_refresh_source " + SUBSCRIPTION_REFRESH_TRACE + " " + source_id;
		if (strategy != "")
			command = command + " " + strategy;
		else if (notify_intent_arg(req) != "")
			command = command + " -";
		command = command + notify_intent_arg(req);
		let code = system(command + " >/dev/null 2>&1 &");
		if (code != 0)
			die("Failed to start /usr/libexec/shinra-runner: " + code);

		task = read_task(SUBSCRIPTION_REFRESH_TASK);
		task.status = "starting";
		task.message = "Subscription source refresh queued";
		task.trace_id = trace_id;
		if (type(task.meta) != "object" || task.meta == null || type(task.meta) == "array")
			task.meta = {};
		task.meta.source_id = source_id;
		return Success({
			path: path,
			task: task,
			started: true,
			source_id: source_id
		}, 202, trace_id, "Subscription source refresh task started");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_SUBSCRIPTION_FETCH_FAILED, "Failed to start Subscription source refresh task", trace_id, err);
	}
}

export {
	SUBSCRIPTION_REFRESH_TASK,
	SUBSCRIPTION_REFRESH_TRACE,
	subscription_refresh_task_enabled,
	progress_percent,
	redacted_url,
	write_subscription_refresh_task,
	path_exists,
	source_arg,
	subscription_refresh_runner_strategy,
	notify_intent_arg,
	shell_safe_token,
	subscriptions_refresh_status,
	subscriptions_refresh_start,
	subscription_refresh_source_start
};
