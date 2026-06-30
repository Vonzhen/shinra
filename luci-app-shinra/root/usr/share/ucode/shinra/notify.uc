/**
 * Shinra | notify.uc | v1.0
 */

'use strict';

import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { PATH } from 'shinra.core.constants';
import { read_optional_text, write_text_atomic, write_runtime_text_atomic, parse_json_object, request_content, request_keys, json_escape, json_stringify, ExecResult } from 'shinra.core.utils';
import { fetch_text } from 'shinra.resource_fetch';
import { validate_fetch_strategy } from 'shinra.subscription_policy';

const TELEGRAM_MAX_TEXT = 3900;

function default_notify_settings() {
	return {
		schema_version: 1,
		telegram: {
			enabled: false,
			mode: "fail_only",
			bot_token: "",
			chat_id: "",
			location_name: "Shinra",
			fetch_strategy: "proxy",
			timeout_sec: 15
		}
	};
}

function trim_text(value) {
	let text = "" + value;
	text = replace(text, "\r", "");
	text = replace(text, "\n", "");
	return text;
}

function normalize_mode(value) {
	if (value == "all")
		return "all";
	return "fail_only";
}

function normalize_timeout(value) {
	let n = int(value || 15);
	if (n < 5)
		return 5;
	if (n > 60)
		return 60;
	return n;
}

function normalize_notify_settings(raw) {
	if (type(raw) != "object" || raw == null || type(raw) == "array")
		die("Notify settings root must be a JSON object");

	let defaults = default_notify_settings();
	let source = type(raw.telegram) == "object" && raw.telegram != null && type(raw.telegram) != "array" ? raw.telegram : {};

	let result = {
		schema_version: 1,
		telegram: {
			enabled: source.enabled == true,
			mode: normalize_mode(source.mode),
			bot_token: type(source.bot_token) == "string" ? trim_text(source.bot_token) : defaults.telegram.bot_token,
			chat_id: type(source.chat_id) == "string" ? trim_text(source.chat_id) : defaults.telegram.chat_id,
			location_name: type(source.location_name) == "string" && source.location_name != "" ? source.location_name : defaults.telegram.location_name,
			fetch_strategy: type(source.fetch_strategy) == "string" && source.fetch_strategy != "" ? source.fetch_strategy : defaults.telegram.fetch_strategy,
			timeout_sec: normalize_timeout(source.timeout_sec)
		}
	};
	validate_fetch_strategy(result.telegram.fetch_strategy, "telegram.fetch_strategy");
	return result;
}

function read_notify_settings() {
	let content = read_optional_text(PATH.NOTIFY);
	if (!length(content))
		return default_notify_settings();
	return normalize_notify_settings(parse_json_object(content, "Notify Settings"));
}

function notify_settings_content(settings) {
	return json_stringify(normalize_notify_settings(settings)) + "\n";
}

function default_notify_state() {
	return {
		schema_version: 1,
		last_attempt_at: "",
		last_task_type: "",
		last_status: "",
		last_message: "",
		last_sent: false,
		last_reason: ""
	};
}

function now_utc(trace_id) {
	let result = ExecResult(trace_id, [ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" ]);
	if (result.code == 0)
		return trim_text(result.stdout || "");
	return "";
}

function normalize_notify_state(raw) {
	raw = type(raw) == "object" && raw != null && type(raw) != "array" ? raw : {};

	return {
		schema_version: 1,
		last_attempt_at: type(raw.last_attempt_at) == "string" ? raw.last_attempt_at : "",
		last_task_type: type(raw.last_task_type) == "string" ? raw.last_task_type : "",
		last_status: type(raw.last_status) == "string" ? raw.last_status : "",
		last_message: type(raw.last_message) == "string" ? raw.last_message : "",
		last_sent: raw.last_sent == true,
		last_reason: type(raw.last_reason) == "string" ? raw.last_reason : ""
	};
}

function read_notify_state() {
	try {
		let content = read_optional_text(PATH.NOTIFY_STATE);
		if (!length(content))
			return default_notify_state();
		return normalize_notify_state(parse_json_object(content, "Notify State"));
	} catch (e) {
		return default_notify_state();
	}
}

function write_notify_state(trace_id, task_type, status, message, sent, reason) {
	let state = {
		schema_version: 1,
		last_attempt_at: now_utc(trace_id),
		last_task_type: task_type || "",
		last_status: status || "",
		last_message: message || "",
		last_sent: sent == true,
		last_reason: reason || ""
	};
	write_runtime_text_atomic(PATH.NOTIFY_STATE, json_stringify(normalize_notify_state(state)) + "\n");
}

function plain_text(value) {
	let text = "" + value;
	text = replace(text, "<br>", "\n");
	text = replace(text, "<br/>", "\n");
	text = replace(text, "<br />", "\n");
	text = replace(text, "%0A", "\n");
	return text;
}

function truncate_text(value) {
	let text = plain_text(value);
	if (length(text) <= TELEGRAM_MAX_TEXT)
		return text;
	return substr(text, 0, TELEGRAM_MAX_TEXT - 80) + "\n...[message truncated]";
}

function redact_token(text, token) {
	let safe = "" + text;
	if (length(token))
		safe = replace(safe, token, "<redacted>");
	return safe;
}

function token_without_bot_prefix(token) {
	if (index(token, "bot") == 0)
		return substr(token, 3);
	return token;
}

function should_send(settings, status, force) {
	if (force)
		return true;
	if (!settings.telegram.enabled)
		return false;
	if (status == "success" && settings.telegram.mode == "fail_only")
		return false;
	return true;
}

function task_title(settings, task_type, status) {
	let name = settings.telegram.location_name || "Shinra";
	let task = "Task notification";
	if (task_type == "subscriptions_refresh" || task_type == "subscription.refresh")
		task = "Subscription refresh";
	else if (task_type == "ruleset_download_required" || task_type == "ruleset.sync")
		task = "Rule Set sync";
	else if (task_type == "telegram_test")
		task = "Telegram test";

	return "[" + name + "] " + task + " " + status;
}

function send_telegram_with_settings(trace_id, settings, task_type, status, message, force) {
	let token = token_without_bot_prefix(settings.telegram.bot_token || "");
	let chat_id = settings.telegram.chat_id || "";
	let strategy = settings.telegram.fetch_strategy == "direct" ? "direct" : "proxy";

	if (!should_send(settings, status, force)) {
		write_notify_state(trace_id, task_type, status, message, false, "disabled or fail_only mode active");
		return Success({ sent: false, reason: "disabled or fail_only mode active", fetch_strategy: strategy }, 200, trace_id, "Telegram notification skipped");
	}
	if (!length(token) || !length(chat_id)) {
		write_notify_state(trace_id, task_type, status, message, false, "missing credentials");
		return Success({ sent: false, reason: "missing credentials", fetch_strategy: strategy }, 200, trace_id, "Telegram notification skipped");
	}

	let text = truncate_text(task_title(settings, task_type, status) + "\n" + message);
	let url = "https://api.telegram.org/bot" + token + "/sendMessage";
	let payload = "{" +
		"\"chat_id\":\"" + json_escape(chat_id) + "\"," +
		"\"text\":\"" + json_escape(text) + "\"," +
		"\"disable_web_page_preview\":true" +
	"}";

	let result = fetch_text(trace_id, url, strategy, {
		timeout_sec: settings.telegram.timeout_sec,
		min_bytes: 1,
		method: "POST",
		post_data: payload,
		headers: [ "Content-Type: application/json" ]
	});

	if (!result.ok) {
		let detail = redact_token(result.stderr || result.body || "Telegram request failed", token);
		write_notify_state(trace_id, task_type, status, message, false, detail);
		return Fail(ERR.E_NOTIFY_SEND_FAILED, "Telegram API request failed", trace_id, detail);
	}

	let body = parse_json_object(result.body || "{}", "Telegram API response");
	if (body.ok == true) {
		write_notify_state(trace_id, task_type, status, message, true, "");
		return Success({ sent: true, fetch_strategy: strategy }, 200, trace_id, "Telegram notification sent");
	}

	write_notify_state(trace_id, task_type, status, message, false, redact_token(result.body || "", token));
	return Fail(ERR.E_NOTIFY_SEND_FAILED, "Telegram API response rejected", trace_id, redact_token(result.body || "", token));
}

function send_telegram(trace_id, task_type, status, message) {
	try {
		let settings = read_notify_settings();
		return send_telegram_with_settings(trace_id, settings, task_type, status, message, false);
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_NOTIFY_SEND_FAILED, "Telegram notification crashed", trace_id, err);
	}
}

function result_data(result) {
	if (result && type(result.data) == "object" && result.data != null && type(result.data) != "array")
		return result.data;
	return {};
}

function failed_rule_tags(data) {
	let tags = [];
	let failed = type(data.failed) == "array" ? data.failed : [];

	for (let item in failed) {
		if (type(item) == "object" && item != null && type(item.tag) == "string")
			push(tags, item.tag);
	}

	return tags;
}

function join_tags(tags) {
	let text = "";
	for (let tag in tags) {
		if (length(text))
			text = text + ", ";
		text = text + tag;
	}
	return text;
}

function result_status(task_type, result) {
	if (!result || result.ok != true)
		return "fail";

	let data = result_data(result);
	if (task_type == "subscription.refresh")
		return (data.node_count || 0) > 0 ? "success" : "partial";
	if (task_type == "ruleset.sync")
		return (data.failed_count || 0) > 0 ? "partial" : "success";
	return "success";
}

function result_message(task_type, result, status) {
	if (!result || result.ok != true) {
		let detail = "unknown error";
		if (result != null)
			detail = result.detail || result.message || result.code || detail;
		return task_type + " " + status + "\nDetail: " + detail;
	}

	let data = result_data(result);
	if (task_type == "subscription.refresh") {
		return "Subscription refresh " + status +
			"\nNodes: " + (data.node_count || 0) +
			"\nStrategy: " + (data.refresh_strategy || "-") +
			"\nLAN/private routing: TUN route_exclude_address";
	}

	if (task_type == "ruleset.sync") {
		let tags = failed_rule_tags(data);
		let message = "Rule Set sync " + status +
			"\nRequired: " + (data.required_count || 0) +
			"\nUpdated: " + (data.updated_count || 0) +
			"\nUnchanged: " + (data.unchanged_count || 0) +
			"\nFailed: " + (data.failed_count || 0);
		if (length(tags))
			message = message + "\nFailed Rule Sets: " + join_tags(tags);
		return message;
	}

	return (result.message || task_type + " " + status);
}

function notify_result_best_effort(trace_id, task_type, result) {
	try {
		let status = result_status(task_type, result);
		let message = result_message(task_type, result, status);
		return send_telegram(trace_id, task_type, status, message);
	} catch (e) {
		return null;
	}
}

function notify_settings_get(trace_id, req) {
	try {
		let settings = read_notify_settings();
		return Success({
			path: PATH.NOTIFY,
			settings: settings,
			state: read_notify_state(),
			content: notify_settings_content(settings)
		}, 200, trace_id, "Notify settings loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_NOTIFY_SETTINGS_FAILED, "Failed to load Notify settings", trace_id, err);
	}
}

function notify_settings_save(trace_id, req) {
	try {
		let content = request_content(req);
		if (!length(content))
			die("Missing Notify settings content; request keys: " + request_keys(req));

		let settings = normalize_notify_settings(parse_json_object(content, "Notify Settings"));
		write_text_atomic(PATH.NOTIFY, notify_settings_content(settings));
		return Success({
			path: PATH.NOTIFY,
			settings: settings
		}, 200, trace_id, "Notify settings saved");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_NOTIFY_SETTINGS_FAILED, "Failed to save Notify settings", trace_id, err);
	}
}

function notify_test_telegram(trace_id, req) {
	try {
		let settings = read_notify_settings();
		return send_telegram_with_settings(trace_id, settings, "telegram_test", "success", "Telegram notification channel is ready.", true);
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_NOTIFY_SEND_FAILED, "Failed to test Telegram notification", trace_id, err);
	}
}

export { notify_settings_get, notify_settings_save, notify_test_telegram, send_telegram, notify_result_best_effort };
