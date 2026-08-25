/**
 * Shinra | generator_control_plane.uc | v1.1
 */

'use strict';

import { CONTROL_PLANE_PROXY } from 'shinra.core.constants';
import { dashboard_policy } from 'shinra.dashboard_config';

function ensure_object_field(parent, key) {
	if (type(parent[key]) != "object" || parent[key] == null || type(parent[key]) == "array")
		parent[key] = {};
	return parent[key];
}

function strip_clash_api(profile) {
	if (type(profile.experimental) != "object" || profile.experimental == null || type(profile.experimental) == "array")
		return false;

	if (profile.experimental.clash_api == null)
		return false;

	delete profile.experimental.clash_api;
	return true;
}

function dashboard_api_service(policy) {
	let service = {
		type: "api",
		tag: "shinra-api",
		listen: policy.listen,
		listen_port: policy.listen_port,
		secret: "",
		access_control_allow_origin: policy.access_control_allow_origin,
		access_control_allow_private_network: policy.access_control_allow_private_network
	};

	if (type(policy.dashboard) == "object" && policy.dashboard != null && type(policy.dashboard) != "array")
		service.dashboard = policy.dashboard;

	return service;
}

function find_shinra_api_service(profile) {
	if (type(profile.services) != "array")
		return -1;

	for (let i = 0; i < length(profile.services); i++) {
		let service = profile.services[i];
		if (type(service) == "object" && service != null && service.tag == "shinra-api")
			return i;
	}

	return -1;
}

function apply_dashboard_api_service(profile) {
	let policy = dashboard_policy();
	strip_clash_api(profile);
	let result = {
		enabled: policy.enabled == true,
		inserted: false,
		existing: false,
		source: policy.enabled == true ? "shinra" : "none",
		tag: "shinra-api",
		listen: policy.listen,
		listen_port: policy.listen_port,
		endpoint_valid: true,
		secret_configured: false,
		dashboard_enabled: type(policy.dashboard) == "object" && policy.dashboard != null && policy.dashboard.enabled == true,
		dashboard_path: type(policy.dashboard) == "object" && policy.dashboard != null ? policy.dashboard.path : "",
		dashboard_download_url: type(policy.dashboard) == "object" && policy.dashboard != null ? policy.dashboard.download_url : ""
	};

	if (policy.enabled != true)
		return result;

	if (type(profile.services) != "array")
		profile.services = [];

	let index = find_shinra_api_service(profile);
	let service = dashboard_api_service(policy);
	if (index >= 0) {
		profile.services[index] = service;
		result.existing = true;
	} else {
		push(profile.services, service);
		result.inserted = true;
	}

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

export { ensure_object_field, apply_dashboard_api_service, ensure_control_plane_proxy_inbound };
