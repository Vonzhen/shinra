/**
 * Shinra | ruleset_policy.uc | v1.0
 */

'use strict';

import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { lock_acquire, lock_release } from 'shinra.core.lock';
import { normalize_subscriptions_policy } from 'shinra.subscription_policy';
import { read_text, write_text_atomic, parse_json_object, request_content, request_keys, json_stringify } from 'shinra.core.utils';

function subscriptions_config() {
	return parse_json_object(read_text(PATH.SUBSCRIPTIONS), "Subscriptions");
}

function normalized_subscriptions_config() {
	return normalize_subscriptions_policy(subscriptions_config());
}

function normalize_ruleset_policy_content(content) {
	if (content == "")
		die("Missing Rule Set policy content");

	let wrapper = {
		schema_version: 1,
		sources: [],
		ruleset: parse_json_object(content, "Rule Set policy")
	};
	let normalized = normalize_subscriptions_policy(wrapper);
	return normalized.ruleset;
}

function apply_ruleset_policy(config, policy) {
	let normalized = normalize_subscriptions_policy({
		schema_version: 1,
		sources: [],
		ruleset: policy
	});
	config.ruleset = normalized.ruleset;
	return normalize_subscriptions_policy(config);
}

function ruleset_policy_get(trace_id, req) {
	try {
		let config = normalized_subscriptions_config();
		return Success({
			path: PATH.SUBSCRIPTIONS,
			policy: config.ruleset,
			content: json_stringify(config.ruleset)
		}, 200, trace_id, "Rule Set policy loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_POLICY_FAILED, "Failed to load Rule Set policy", trace_id, err);
	}
}

function ruleset_policy_save(trace_id, req) {
	let lock = null;
	try {
		let content = request_content(req);
		if (content == "")
			die("Missing Rule Set policy content; request keys: " + request_keys(req));

		let policy = normalize_ruleset_policy_content(content);
		lock = lock_acquire("subscription", trace_id);
		let config = apply_ruleset_policy(subscriptions_config(), policy);
		write_text_atomic(PATH.SUBSCRIPTIONS, json_stringify(config));
		lock_release(lock);
		return Success({
			path: PATH.SUBSCRIPTIONS,
			policy: config.ruleset
		}, 200, trace_id, "Rule Set policy saved");
	} catch (e) {
		if (lock != null)
			lock_release(lock);
		let err = "" + e;
		return Fail(ERR.E_RULESET_POLICY_FAILED, "Failed to save Rule Set policy", trace_id, err);
	}
}

function ruleset_policy_get_impl(trace_id, req) {
	return ruleset_policy_get(trace_id, req);
}

function ruleset_policy_save_impl(trace_id, req) {
	return ruleset_policy_save(trace_id, req);
}

export { subscriptions_config, normalized_subscriptions_config, normalize_ruleset_policy_content, apply_ruleset_policy, ruleset_policy_get, ruleset_policy_save, ruleset_policy_get_impl, ruleset_policy_save_impl };
