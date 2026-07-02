/**
 * Shinra | generator.uc | v1.0
 */

'use strict';

import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { file_exists, json_stringify_pretty } from 'shinra.core.utils';
import { artifact_check_config, artifact_write_candidate } from 'shinra.core.artifact';
import { parse_profile, parse_node_snapshot, parse_subscriptions_policy } from 'shinra.generator_input';
import { validate_tun_contract, validate_extensions, strip_extensions, validate_references } from 'shinra.generator_validate';
import { collect_profile_tags, normalized_nodes, collect_node_tags } from 'shinra.generator_nodes';
import { generate_region_groups, grouped_node_tags, unmatched_node_tag_list, matched_node_count } from 'shinra.generator_groups';
import { inject_selectors, main_selector_option_count, merge_outbounds } from 'shinra.generator_selectors';
import { localize_rulesets } from 'shinra.generator_rulesets';
import { apply_panel_api_policy, ensure_control_plane_proxy_inbound } from 'shinra.generator_control_plane';

function generate_candidate(trace_id, req) {
	try {
		let profile = parse_profile();
		let snapshot = parse_node_snapshot();
		let subscriptions = parse_subscriptions_policy();
		validate_extensions(profile);

		let profile_tags = collect_profile_tags(profile);
		let normalized = normalized_nodes(snapshot, profile_tags, subscriptions);
		let nodes = normalized.nodes;
		let node_tags = collect_node_tags(nodes);
		let groups = generate_region_groups(subscriptions, nodes, profile_tags, node_tags);
		let matched_nodes = grouped_node_tags(groups);
		let unmatched_nodes = unmatched_node_tag_list(nodes, matched_nodes);
		let matched_count = matched_node_count(nodes, matched_nodes);
		let unmatched_count = length(unmatched_nodes);
		let injected = inject_selectors(profile, nodes, groups);
		let main_options = main_selector_option_count(profile);
		merge_outbounds(profile, groups, nodes);
		let ruleset = localize_rulesets(profile, subscriptions);
		let panel_api = apply_panel_api_policy(profile);
		let control_proxy = ensure_control_plane_proxy_inbound(profile);
		validate_tun_contract(profile);
		let stripped = strip_extensions(profile);
		validate_references(profile);

		let content = json_stringify_pretty(profile);
		artifact_write_candidate(trace_id, content + "\n");

		return Success({
			path: PATH.CANDIDATE_CONFIG,
			node_count: length(nodes),
			skipped_banned: normalized.skipped_banned,
			skipped_high_rate: normalized.skipped_high_rate,
			generated_groups: length(groups),
			matched_node_count: matched_count,
			unmatched_node_count: unmatched_count,
			main_selector_options: main_options,
			injected_selectors: injected,
			ruleset_mode: ruleset.mode,
			ruleset_total: ruleset.total,
			ruleset_localized: ruleset.localized,
			ruleset_preserved_remote: ruleset.preserved_remote,
			ruleset_missing: ruleset.missing,
			panel_api_enabled: panel_api.enabled,
			panel_api_external_controller: panel_api.external_controller,
			panel_api_secret_configured: panel_api.secret_configured,
			panel_api_source: panel_api.source,
			control_proxy_inserted: control_proxy.inserted,
			control_proxy_existing: control_proxy.existing,
			control_proxy_tag: control_proxy.tag,
			control_proxy_listen: control_proxy.listen,
			control_proxy_port: control_proxy.port,
			stripped_extensions: stripped,
			outbounds: length(profile.outbounds)
		}, 200, trace_id, "Candidate generated");
	} catch (e) {
		let err = "" + e;
		if (substr(err, 0, 13) == "TUN_CONTRACT:")
			return Fail(ERR.E_TUN_CONTRACT_FAILED, "Profile TUN contract failed", trace_id, substr(err, 13));
		return Fail(ERR.E_GENERATE_FAILED, "Failed to generate Candidate", trace_id, err);
	}
}

function check_candidate(trace_id, req) {
	try {
		if (!file_exists(PATH.CANDIDATE_CONFIG))
			return Fail(ERR.E_CANDIDATE_NOT_FOUND, "Candidate config not found", trace_id, PATH.CANDIDATE_CONFIG);

		let result = artifact_check_config(trace_id, PATH.CANDIDATE_CONFIG);
		if (!result.ok)
			return Fail(ERR.E_CANDIDATE_CHECK_FAILED, "Candidate check failed", trace_id, result.error);

		return Success({
			path: PATH.CANDIDATE_CONFIG,
			stdout: result.stdout,
			stderr: result.stderr
		}, 200, trace_id, "Candidate check passed");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_CANDIDATE_CHECK_FAILED, "Candidate check crashed", trace_id, err);
	}
}

export { generate_candidate, check_candidate };
