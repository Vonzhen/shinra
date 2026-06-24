/**
 * Shinra | connections.uc | v1.0
 */

'use strict';

import { CLASH_API } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { observe_runtime } from 'shinra.runtime';
import { http_get_json } from 'shinra.clash';

function number_or_zero(value) {
	if (type(value) == "int" || type(value) == "double")
		return value;
	return 0;
}

function string_or_empty(value) {
	if (type(value) == "string")
		return value;
	return "";
}

function array_or_empty(value) {
	if (type(value) == "array")
		return value;
	return [];
}

function unavailable(reason) {
	return {
		available: false,
		reason: reason,
		summary: {
			count: 0,
			upload_total: 0,
			download_total: 0,
			memory: 0
		},
		connections: []
	};
}

function endpoint(address, port) {
	let host = string_or_empty(address);
	if (host == "")
		return "";
	if (type(port) == "int" || type(port) == "double")
		return host + ":" + port;
	if (type(port) == "string" && port != "")
		return host + ":" + port;
	return host;
}

function connection_host(metadata) {
	if (type(metadata) != "object" || metadata == null)
		return "";
	if (type(metadata.host) == "string" && metadata.host != "")
		return metadata.host;
	if (type(metadata.domain) == "string" && metadata.domain != "")
		return metadata.domain;
	if (type(metadata.destinationIP) == "string" && metadata.destinationIP != "")
		return metadata.destinationIP;
	if (type(metadata.destination_ip) == "string" && metadata.destination_ip != "")
		return metadata.destination_ip;
	return "";
}

function destination(metadata) {
	if (type(metadata) != "object" || metadata == null)
		return "";
	if (type(metadata.destinationIP) == "string" && metadata.destinationIP != "")
		return endpoint(metadata.destinationIP, metadata.destinationPort);
	if (type(metadata.destination_ip) == "string" && metadata.destination_ip != "")
		return endpoint(metadata.destination_ip, metadata.destination_port);
	if (type(metadata.host) == "string" && metadata.host != "")
		return endpoint(metadata.host, metadata.destinationPort);
	return "";
}

function source(metadata) {
	if (type(metadata) != "object" || metadata == null)
		return "";
	if (type(metadata.sourceIP) == "string" && metadata.sourceIP != "")
		return endpoint(metadata.sourceIP, metadata.sourcePort);
	if (type(metadata.source_ip) == "string" && metadata.source_ip != "")
		return endpoint(metadata.source_ip, metadata.source_port);
	return "";
}

function normalize_connection(item) {
	let metadata = type(item.metadata) == "object" && item.metadata != null ? item.metadata : {};

	return {
		id: string_or_empty(item.id),
		network: string_or_empty(metadata.network),
		type: string_or_empty(metadata.type),
		host: connection_host(metadata),
		destination: destination(metadata),
		source: source(metadata),
		rule: string_or_empty(item.rule),
		rule_payload: string_or_empty(item.rulePayload),
		chains: array_or_empty(item.chains),
		upload: number_or_zero(item.upload),
		download: number_or_zero(item.download),
		start: string_or_empty(item.start)
	};
}

function normalize_connections(data) {
	let raw = array_or_empty(data.connections);
	let rows = [];

	for (let item in raw) {
		if (type(item) != "object" || item == null)
			continue;
		push(rows, normalize_connection(item));
	}

	return rows;
}

function connections_list(trace_id, req) {
	try {
		let observed = observe_runtime(trace_id);
		let state = json(observed.state);

		if (!state.sing_box_running)
			return Success(unavailable("runtime_not_running"), 200, trace_id, "Connections unavailable");

		let data = null;
		try {
			data = http_get_json(trace_id, CLASH_API.CONNECTIONS);
		} catch (e) {
			let err = "" + e;
			return Success(unavailable("api_unreachable"), 200, trace_id, "Connections unavailable");
		}

		let connections = normalize_connections(data);
		return Success({
			available: true,
			reason: "ok",
			summary: {
				count: length(connections),
				upload_total: number_or_zero(data.uploadTotal),
				download_total: number_or_zero(data.downloadTotal),
				memory: number_or_zero(data.memory)
			},
			connections: connections
		}, 200, trace_id, "Connections loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_DIAGNOSTICS_FAILED, "Failed to load connections", trace_id, err);
	}
}

export { connections_list };
