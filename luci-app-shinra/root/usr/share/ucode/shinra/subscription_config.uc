/**
 * Shinra | subscription_config.uc | v1.0
 */

'use strict';

import { parse_json_object } from 'shinra.core.utils';
import { validate_refresh_strategy, normalize_subscriptions_policy } from 'shinra.subscription_policy';

function validate_url(url) {
	if (type(url) != "string" || url == "")
		die("Subscription URL must be a non-empty string");

	if (substr(url, 0, 7) != "http://" && substr(url, 0, 8) != "https://")
		die("Subscription URL must start with http:// or https://");
}

function validate_subscriptions_object(config) {
	normalize_subscriptions_policy(config);
}

function validate_subscriptions_content(content) {
	let config = parse_json_object(content, "Subscriptions");
	validate_subscriptions_object(config);
	return normalize_subscriptions_policy(config);
}

function refresh_strategy(config, req) {
	if (type(req) == "object" && req != null && type(req.strategy) == "string" && req.strategy != "") {
		validate_refresh_strategy(req.strategy);
		return req.strategy;
	}

	if (type(config.refresh_strategy) == "string" && config.refresh_strategy != "") {
		validate_refresh_strategy(config.refresh_strategy);
		return config.refresh_strategy;
	}

	return "direct";
}

export { validate_url, validate_subscriptions_object, validate_subscriptions_content, refresh_strategy };
