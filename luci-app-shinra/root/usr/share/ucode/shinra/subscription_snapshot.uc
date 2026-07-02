/**
 * Shinra | subscription_snapshot.uc | v1.0
 */

'use strict';

import { PATH } from 'shinra.core.constants';
import { read_optional_text, parse_json_object } from 'shinra.core.utils';
import { validate_refresh_strategy } from 'shinra.subscription_policy';

function validate_outbounds(outbounds) {
	if (type(outbounds) != "array")
		die("Sub-Store output must be a sing-box outbounds JSON array");

	for (let outbound in outbounds) {
		if (type(outbound) != "object" || outbound == null || type(outbound) == "array")
			die("Sub-Store outbound must be an object");
		if (type(outbound.type) != "string" || outbound.type == "")
			die("Sub-Store outbound type must be a non-empty string");
		if (type(outbound.tag) != "string" || outbound.tag == "")
			die("Sub-Store outbound tag must be a non-empty string");
	}
}

function preserve_source_attribution(outbounds, source_id, source_name) {
	for (let outbound in outbounds) {
		outbound.x_shinra_source_id = source_id;
		outbound.x_shinra_source_name = source_name;
		outbound.x_shinra_source = source_name;
	}
	return outbounds;
}

function validate_snapshot_sources(sources) {
	let source_map = {};
	let source_names = {};

	for (let source in sources) {
		if (type(source) != "object" || source == null || type(source) == "array")
			die("Node Snapshot source item must be an object");
		if (type(source.id) != "string" || source.id == "")
			die("Node Snapshot source id must be a non-empty string");
		if (type(source.name) != "string" || source.name == "")
			die("Node Snapshot source name must be a non-empty string");
		if (type(source.status) != "string" || source.status == "")
			die("Node Snapshot source status must be a non-empty string");
		if (source_map[source.id])
			die("Duplicated Node Snapshot source id: " + source.id);
		if (source_names[source.name])
			die("Duplicated Node Snapshot source name: " + source.name);

		source_map[source.id] = source;
		source_names[source.name] = true;
	}

	return source_map;
}

function validate_snapshot_outbound_attribution(outbounds, source_map) {
	let outbound_tags = {};

	for (let outbound in outbounds) {
		if (type(outbound.x_shinra_source_id) != "string" || outbound.x_shinra_source_id == "")
			die("Node Snapshot outbound source id must be a non-empty string");
		if (type(outbound.x_shinra_source_name) != "string" || outbound.x_shinra_source_name == "")
			die("Node Snapshot outbound source name must be a non-empty string");
		if (outbound_tags[outbound.tag])
			die("Duplicated Node Snapshot outbound tag: " + outbound.tag);
		if (!source_map[outbound.x_shinra_source_id])
			die("Node Snapshot outbound source id does not exist: " + outbound.x_shinra_source_id);
		if (outbound.x_shinra_source_name != source_map[outbound.x_shinra_source_id].name)
			die("Node Snapshot outbound source name does not match source id: " + outbound.x_shinra_source_id);

		outbound_tags[outbound.tag] = true;
	}
}

function validate_node_snapshot_object(snapshot) {
	if (snapshot.schema_version != 1)
		die("Node Snapshot schema_version must be 1");
	if (snapshot.source != "sub-store")
		die("Node Snapshot source must be sub-store");
	if (type(snapshot.refresh_strategy) == "string")
		validate_refresh_strategy(snapshot.refresh_strategy);
	if (type(snapshot.sources) != "array")
		die("Node Snapshot sources must be an array");
	let source_map = validate_snapshot_sources(snapshot.sources);
	validate_outbounds(snapshot.outbounds);
	validate_snapshot_outbound_attribution(snapshot.outbounds, source_map);
}

function validate_node_snapshot_content(content) {
	let snapshot = parse_json_object(content, "Node Snapshot");
	validate_node_snapshot_object(snapshot);
	return snapshot;
}

function empty_old_snapshot() {
	return {
		available: false,
		sources: [],
		outbounds: []
	};
}

function read_old_snapshot() {
	try {
		let raw = read_optional_text(PATH.NODE_SNAPSHOT);
		if (raw == "")
			return empty_old_snapshot();
		let snapshot = validate_node_snapshot_content(raw);
		return {
			available: true,
			sources: type(snapshot.sources) == "array" ? snapshot.sources : [],
			outbounds: type(snapshot.outbounds) == "array" ? snapshot.outbounds : []
		};
	} catch (e) {
		return empty_old_snapshot();
	}
}

function old_outbounds_for_source(old_snapshot, source_id) {
	let outbounds = [];
	if (type(old_snapshot) != "object" || old_snapshot == null || type(old_snapshot.outbounds) != "array")
		return outbounds;

	for (let outbound in old_snapshot.outbounds) {
		if (type(outbound) == "object" && outbound != null && outbound.x_shinra_source_id == source_id)
			push(outbounds, outbound);
	}

	return outbounds;
}

function old_source_for_id(old_snapshot, source_id) {
	if (type(old_snapshot) != "object" || old_snapshot == null || type(old_snapshot.sources) != "array")
		return null;

	for (let source in old_snapshot.sources) {
		if (type(source) == "object" && source != null && source.id == source_id)
			return source;
	}

	return null;
}

export {
	validate_outbounds,
	preserve_source_attribution,
	validate_snapshot_sources,
	validate_snapshot_outbound_attribution,
	validate_node_snapshot_object,
	validate_node_snapshot_content,
	empty_old_snapshot,
	read_old_snapshot,
	old_outbounds_for_source,
	old_source_for_id
};
