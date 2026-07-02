/**
 * Shinra | generator_input.uc | v1.0
 */

'use strict';

import { PATH } from 'shinra.core.constants';
import { read_text, parse_json_object } from 'shinra.core.utils';
import { normalize_subscriptions_policy } from 'shinra.subscription_policy';

function parse_profile() {
	let profile = parse_json_object(read_text(PATH.PROFILE), "Profile");
	if (type(profile.outbounds) != "array")
		die("Profile must contain outbounds array");
	return profile;
}

function parse_node_snapshot() {
	let snapshot = parse_json_object(read_text(PATH.NODE_SNAPSHOT), "Node Snapshot");
	if (snapshot.schema_version != 1)
		die("Node Snapshot schema_version must be 1");
	if (snapshot.source != "sub-store")
		die("Node Snapshot source must be sub-store");
	if (type(snapshot.outbounds) != "array")
		die("Node Snapshot outbounds must be an array");
	return snapshot;
}

function parse_subscriptions_policy() {
	let config = parse_json_object(read_text(PATH.SUBSCRIPTIONS), "Subscriptions");
	return normalize_subscriptions_policy(config);
}

export { parse_profile, parse_node_snapshot, parse_subscriptions_policy };
