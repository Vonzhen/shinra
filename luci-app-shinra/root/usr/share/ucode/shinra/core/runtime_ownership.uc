/**
 * Shinra | core/runtime_ownership.uc | v1.0
 */

'use strict';

import { PATH } from 'shinra.core.constants';
import { ExecResult, json_stringify } from 'shinra.core.utils';

function trim_line(value) {
	value = replace("" + value, "\r", "");
	while (length(value) && substr(value, length(value) - 1, 1) == "\n")
		value = substr(value, 0, length(value) - 1);
	return value;
}

function first_token(value) {
	value = "" + value;
	let token = "";

	for (let i = 0; i < length(value); i++) {
		let ch = substr(value, i, 1);
		if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n")
			break;
		token = token + ch;
	}

	return token;
}

function next_token_after(value, marker) {
	let pos = index(value, marker);
	if (pos < 0)
		return "";

	let start = pos + length(marker);
	while (start < length(value)) {
		let ch = substr(value, start, 1);
		if (ch != " " && ch != "\t")
			break;
		start = start + 1;
	}

	let token = "";
	for (let i = start; i < length(value); i++) {
		let ch = substr(value, i, 1);
		if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n")
			break;
		token = token + ch;
	}

	if (length(token) >= 2 && substr(token, 0, 1) == "\"" && substr(token, length(token) - 1, 1) == "\"")
		token = substr(token, 1, length(token) - 2);
	if (length(token) >= 2 && substr(token, 0, 1) == "'" && substr(token, length(token) - 1, 1) == "'")
		token = substr(token, 1, length(token) - 2);

	return token;
}

function config_path_from_cmdline(cmdline) {
	let path = next_token_after(cmdline, " -c ");
	if (path != "")
		return path;

	path = next_token_after(cmdline, " --config ");
	if (path != "")
		return path;

	let marker = "--config=";
	let pos = index(cmdline, marker);
	if (pos >= 0)
		return next_token_after(cmdline, marker);

	return "";
}

function suspected_owner(cmdline, config_path) {
	let lower = lc(cmdline + " " + config_path);

	if (index(config_path, PATH.RUNTIME_CONFIG) >= 0)
		return "shinra";
	if (index(lower, "/var/run/flowproxy/") >= 0 || index(lower, "flowproxy") >= 0)
		return "flowproxy";
	if (index(lower, "homeproxy") >= 0)
		return "homeproxy";
	if (index(lower, "openclash") >= 0)
		return "openclash";

	return "unknown/manual";
}

function process_recommendation(owner) {
	if (owner == "flowproxy")
		return "Stop FlowProxy before starting Shinra.";
	if (owner == "homeproxy")
		return "Stop HomeProxy before starting Shinra.";
	if (owner == "openclash")
		return "Stop OpenClash before starting Shinra.";
	if (owner == "unknown/manual")
		return "Stop the foreign sing-box process before starting Shinra.";
	return "";
}

function process_record(line) {
	let cmdline = trim_line(line);
	let config_path = config_path_from_cmdline(cmdline);
	let owner = suspected_owner(cmdline, config_path);

	return {
		pid: first_token(cmdline),
		cmdline: cmdline,
		config_path: config_path,
		suspected_owner: owner,
		recommendation: process_recommendation(owner)
	};
}

function is_sing_box_runtime_line(line) {
	let lower = lc(line);
	return index(lower, "sing-box") >= 0 && index(lower, " run") >= 0;
}

function append_processes_from_ps(output, shinra, foreign) {
	let current = "";

	for (let i = 0; i < length(output); i++) {
		let ch = substr(output, i, 1);
		if (ch == "\r")
			continue;
		if (ch == "\n") {
			current = trim_line(current);
			if (current != "" && is_sing_box_runtime_line(current)) {
				let record = process_record(current);
				if (record.suspected_owner == "shinra")
					push(shinra, record);
				else
					push(foreign, record);
			}
			current = "";
			continue;
		}
		current = current + ch;
	}

	current = trim_line(current);
	if (current != "" && is_sing_box_runtime_line(current)) {
		let record = process_record(current);
		if (record.suspected_owner == "shinra")
			push(shinra, record);
		else
			push(foreign, record);
	}
}

function recommendation_for_foreign(foreign) {
	if (length(foreign) == 0)
		return "";

	let owners = "";
	for (let item in foreign) {
		if (length(owners))
			owners = owners + ", ";
		owners = owners + item.suspected_owner;
	}

	return "Foreign sing-box runtime detected (" + owners + "). Stop it before applying or starting Shinra.";
}

function runtime_ownership_observe(trace_id) {
	let result = ExecResult(trace_id, [ "ps", "w" ]);
	if (result.code != 0)
		die(result.stderr || result.stdout || "Failed to list processes");

	let shinra = [];
	let foreign = [];
	append_processes_from_ps(result.stdout, shinra, foreign);

	return {
		shinra_managed_processes: shinra,
		foreign_processes: foreign,
		runtime_conflict: length(foreign) > 0,
		recommendation: recommendation_for_foreign(foreign)
	};
}

function runtime_ownership_guard(trace_id) {
	let ownership = runtime_ownership_observe(trace_id);
	if (!ownership.runtime_conflict)
		return {
			ok: true,
			ownership: ownership,
			detail: ""
		};

	return {
		ok: false,
		ownership: ownership,
		detail: json_stringify({
			foreign_processes: ownership.foreign_processes,
			recommendation: ownership.recommendation
		})
	};
}

export { runtime_ownership_observe, runtime_ownership_guard };
