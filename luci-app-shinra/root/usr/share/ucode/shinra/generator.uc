/**
 * Shinra | generator.uc | v1.0
 */

'use strict';

import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { file_exists, json_stringify_pretty } from 'shinra.core.utils';
import { artifact_check_config, artifact_write_candidate } from 'shinra.core.artifact';
import { parse_profile, parse_node_snapshot, parse_subscriptions_policy, parse_ruleset_policy } from 'shinra.generator_input';
import { validate_tun_contract, validate_extensions, strip_extensions, validate_references, validated_main_selector_tag } from 'shinra.generator_validate';
import { collect_profile_tags, normalized_nodes, collect_node_tags } from 'shinra.generator_nodes';
import { generate_region_groups, grouped_node_tags, unmatched_node_tag_list, matched_node_count } from 'shinra.generator_groups';
import { direct_outbound_tag, inject_selectors, main_selector_option_count, merge_outbounds } from 'shinra.generator_selectors';
import { collect_manual_selector_consumers, restore_manual_selector_references, generate_manual_selector } from 'shinra.generator_manual_selector';
import { generate_dns_urltest, route_dns_detours } from 'shinra.generator_dns';
import { localize_rulesets } from 'shinra.generator_rulesets';
import { apply_dashboard_api_service, ensure_control_plane_proxy_inbound } from 'shinra.generator_control_plane';

function generate_candidate(trace_id, req) {
	try {
		let profile = parse_profile();
		let snapshot = parse_node_snapshot();
		let subscriptions = parse_subscriptions_policy();
		let ruleset_policy = parse_ruleset_policy();
		validate_extensions(profile);

		let profile_tags = collect_profile_tags(profile);
		let normalized = normalized_nodes(snapshot, profile_tags, subscriptions);
		let nodes = normalized.nodes;
		let node_tags = collect_node_tags(nodes);
		let manual_consumers = collect_manual_selector_consumers(profile);
		let groups = generate_region_groups(subscriptions, nodes, profile_tags, node_tags);
		let dns_group = generate_dns_urltest(subscriptions, nodes, profile_tags, node_tags);
		let matched_nodes = grouped_node_tags(groups);
		let unmatched_nodes = unmatched_node_tag_list(nodes, matched_nodes);
		let matched_count = matched_node_count(nodes, matched_nodes);
		let unmatched_count = length(unmatched_nodes);
		let injected = inject_selectors(profile, nodes, groups);
		restore_manual_selector_references(profile, manual_consumers);
		let manual_selector = generate_manual_selector(subscriptions, nodes, direct_outbound_tag(profile), profile_tags, node_tags);
		let main_options = main_selector_option_count(profile);
		merge_outbounds(profile, groups, manual_selector, dns_group, nodes);
		let dns_detours_adjusted = route_dns_detours(profile, dns_group, validated_main_selector_tag(profile));
		let ruleset = localize_rulesets(profile, ruleset_policy);
		let api_service = apply_dashboard_api_service(profile);
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
			skipped_inactive_source: normalized.skipped_inactive_source,
			generated_groups: length(groups),
			dns_urltest_enabled: subscriptions.dns_urltest.enabled,
			dns_group_nodes: dns_group != null ? length(dns_group.outbounds) : 0,
			dns_detours_adjusted: dns_detours_adjusted,
			dns_detours_fallback: dns_group == null,
			matched_node_count: matched_count,
			unmatched_node_count: unmatched_count,
			main_selector_options: main_options,
			injected_selectors: injected,
			ruleset_mode: ruleset.mode,
			ruleset_total: ruleset.total,
			ruleset_localized: ruleset.localized,
			ruleset_preserved_remote: ruleset.preserved_remote,
			ruleset_missing: ruleset.missing,
			api_service_enabled: api_service.enabled,
			api_service_inserted: api_service.inserted,
			api_service_existing: api_service.existing,
			api_service_source: api_service.source,
			api_service_tag: api_service.tag,
			api_service_listen: api_service.listen,
			api_service_port: api_service.listen_port,
			api_service_endpoint_valid: api_service.endpoint_valid,
			api_service_secret_configured: api_service.secret_configured,
			dashboard_enabled: api_service.dashboard_enabled,
			dashboard_path: api_service.dashboard_path,
			dashboard_download_url: api_service.dashboard_download_url,
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
