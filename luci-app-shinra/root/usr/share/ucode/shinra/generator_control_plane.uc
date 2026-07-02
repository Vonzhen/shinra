/**
 * Shinra | generator_control_plane.uc | v1.0
 */

'use strict';

import { CONTROL_PLANE_PROXY } from 'shinra.core.constants';
import { zashboard_panel_policy } from 'shinra.zashboard';

function ensure_object_field(parent, key) {
	if (type(parent[key]) != "object" || parent[key] == null || type(parent[key]) == "array")
		parent[key] = {};
	return parent[key];
}

function existing_clash_api(profile) {
	if (type(profile.experimental) != "object" || profile.experimental == null || type(profile.experimental) == "array")
		return null;
	if (type(profile.experimental.clash_api) != "object" || profile.experimental.clash_api == null || type(profile.experimental.clash_api) == "array")
		return null;
	if (type(profile.experimental.clash_api.external_controller) != "string" || profile.experimental.clash_api.external_controller == "")
		return null;
	return profile.experimental.clash_api;
}

function apply_panel_api_policy(profile) {
	let policy = zashboard_panel_policy();
	let existing = existing_clash_api(profile);
	let result = {
		enabled: policy.enabled == true || existing != null ? true : false,
		external_controller: "",
		secret_configured: false,
		source: ""
	};

	if (existing != null) {
		result.external_controller = existing.external_controller;
		result.secret_configured = type(existing.secret) == "string" && existing.secret != "";
		result.source = "profile";
		return result;
	}

	if (!result.enabled)
		return result;

	let experimental = ensure_object_field(profile, "experimental");
	let clash_api = ensure_object_field(experimental, "clash_api");
	clash_api.external_controller = policy.external_controller;
	clash_api.secret = policy.secret;

	result.external_controller = policy.external_controller;
	result.secret_configured = policy.secret != "";
	result.source = "panel";
	return result;
}

function ensure_control_plane_proxy_inbound(profile) {
	let result = {
		inserted: false,
		existing: false,
		tag: CONTROL_PLANE_PROXY.TAG,
		listen: CONTROL_PLANE_PROXY.LISTEN,
		port: CONTROL_PLANE_PROXY.PORT
	};

	if (type(profile.inbounds) != "array")
		profile.inbounds = [];

	for (let inbound in profile.inbounds) {
		if (type(inbound) != "object" || inbound == null)
			continue;

		if (inbound.tag == CONTROL_PLANE_PROXY.TAG) {
			inbound.type = "mixed";
			inbound.listen = CONTROL_PLANE_PROXY.LISTEN;
			inbound.listen_port = CONTROL_PLANE_PROXY.PORT;
			result.existing = true;
			return result;
		}

		if (inbound.listen == CONTROL_PLANE_PROXY.LISTEN && int(inbound.listen_port || 0) == CONTROL_PLANE_PROXY.PORT)
			die("Control-plane proxy endpoint is already used by inbound: " + (inbound.tag || ""));
	}

	push(profile.inbounds, {
		type: "mixed",
		tag: CONTROL_PLANE_PROXY.TAG,
		listen: CONTROL_PLANE_PROXY.LISTEN,
		listen_port: CONTROL_PLANE_PROXY.PORT
	});
	result.inserted = true;
	return result;
}

export { ensure_object_field, existing_clash_api, apply_panel_api_policy, ensure_control_plane_proxy_inbound };
