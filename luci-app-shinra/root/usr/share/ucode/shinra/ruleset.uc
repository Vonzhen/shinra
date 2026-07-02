/**
 * Shinra | ruleset.uc | v1.0
 */

'use strict';

import { unlink } from 'fs';
import { PATH } from 'shinra.core.constants';
import { Success, Fail } from 'shinra.core.result';
import { ERR } from 'shinra.core.error';
import { lock_acquire, lock_release } from 'shinra.core.lock';
import { finish_task, fail_task } from 'shinra.core.task';
import { ruleset_transaction_prepare_change, ruleset_transaction_record_change, ruleset_artifact_state } from 'shinra.core.ruleset_artifact';
import { maybe_auto_apply_ruleset_update } from 'shinra.auto_apply';
import { normalized_subscriptions_config, ruleset_policy_get_impl, ruleset_policy_save_impl } from 'shinra.ruleset_policy';
import { RULESET_SYNC_TASK, RULESET_DOWNLOAD_ONE_TASK, ruleset_task_enabled, ruleset_download_one_task_enabled, progress_percent, write_ruleset_task_progress, write_ruleset_download_one_task_progress, ruleset_download_required_status_impl, request_tag, ruleset_download_one_status_impl, ruleset_download_one_start_impl, ruleset_download_required_start_impl } from 'shinra.ruleset_task';
import { redacted_url, file_metadata, required_entries_from_profile, ruleset_required_inventory_impl, ruleset_inventory_impl } from 'shinra.ruleset_inventory';
import { ensure_rule_dirs, ruleset_urls, direct_fetch_rule, same_file_content, atomic_swap_rule } from 'shinra.ruleset_download';

function download_required_entry(trace_id, entry, config, strategy, tmp_dir, on_progress) {
	let final_path = PATH.RULE_DIR + "/" + entry.tag + ".srs";
	let meta = file_metadata(final_path);
	let urls = ruleset_urls(entry, config.ruleset);
	let tmp_path = tmp_dir + "/" + entry.tag + ".srs.tmp";
	let attempts = [];
	let downloaded = false;
	let last_error = "";
	let used_url = "";
	let downloaded_size = 0;

	if (type(on_progress) == "function")
		on_progress({
			current_item: entry.tag,
			last_error: "",
			meta: {
				fetch_strategy: strategy,
				current_url_redacted: length(urls) ? redacted_url(urls[0]) : "",
				rule_dir: PATH.RULE_DIR,
				tag: entry.tag
			}
		});

	for (let url in urls) {
		if (type(on_progress) == "function")
			on_progress({
				current_item: entry.tag,
				meta: {
					current_url_redacted: redacted_url(url)
				}
			});

		let fetch = direct_fetch_rule(trace_id, url, tmp_path, strategy);
		push(attempts, {
			tag: entry.tag,
			url_redacted: redacted_url(url),
			fetch_strategy: strategy,
			method: "get",
			ok: fetch.ok == true,
			error: fetch.ok == true ? "" : fetch.error
		});
		if (fetch.ok == true) {
			downloaded = true;
			used_url = url;
			downloaded_size = fetch.size || 0;
			break;
		}
		last_error = fetch.error;
	}

	if (!downloaded) {
		return {
			status: "failed",
			tag: entry.tag,
			path: final_path,
			error: last_error || "No downloadable URL succeeded",
			attempts: attempts
		};
	}

	if (meta.exists && meta.size > 0 && same_file_content(tmp_path, final_path)) {
		unlink(tmp_path);
		return {
			status: "unchanged",
			tag: entry.tag,
			path: final_path,
			size: meta.size,
			url_redacted: redacted_url(used_url),
			checked_download: true,
			attempts: attempts
		};
	}

	let prepared = null;
	if (config.ruleset.mode == "local")
		prepared = ruleset_transaction_prepare_change(trace_id, entry.tag, final_path);

	let swap = atomic_swap_rule(tmp_path, final_path);
	let transaction = {};
	if (prepared != null)
		transaction = ruleset_transaction_record_change(trace_id, prepared);

	return {
		status: "updated",
		tag: entry.tag,
		path: final_path,
		size: downloaded_size,
		url_redacted: redacted_url(used_url),
		backup_created: swap.backup_created == true,
		pending_runtime_validation: prepared != null,
		transaction_changed_count: transaction.changed_count || 0,
		attempts: attempts
	};
}

function find_required_entry(required, tag) {
	for (let entry in required) {
		if (entry.tag == tag)
			return entry;
	}
	return null;
}

function ruleset_inventory(trace_id, req) {
	return ruleset_inventory_impl(trace_id, req);
}

function ruleset_required_inventory(trace_id, req) {
	return ruleset_required_inventory_impl(trace_id, req);
}

function ruleset_policy_get(trace_id, req) {
	return ruleset_policy_get_impl(trace_id, req);
}

function ruleset_policy_save(trace_id, req) {
	return ruleset_policy_save_impl(trace_id, req);
}

function ruleset_download_required_start(trace_id, req) {
	return ruleset_download_required_start_impl(trace_id, req);
}

function ruleset_download_required_status(trace_id, req) {
	return ruleset_download_required_status_impl(trace_id, req);
}

function ruleset_download_required(trace_id, req) {
	let lock = null;
	try {
		ensure_rule_dirs();
		let config = normalized_subscriptions_config();
		let strategy = config.ruleset.fetch_strategy == "proxy" ? "proxy" : "direct";
		let required = required_entries_from_profile().entries;
		let updated = [];
		let unchanged = [];
		let failed = [];
		let attempts = [];
		let checked = [];
		let tmp_dir = PATH.RULE_DIR + "/.tmp";

		lock = lock_acquire("ruleset", trace_id);
		write_ruleset_task_progress(trace_id, {
			status: "running",
			message: "Rule Set sync running",
			total_count: length(required),
			completed_count: 0,
			updated_count: 0,
			unchanged_count: 0,
			failed_count: 0,
			checked_count: 0,
			progress: 0,
			current_item: "",
			last_error: "",
			meta: {
				fetch_strategy: strategy,
				current_url_redacted: "",
				rule_dir: PATH.RULE_DIR
			},
			trace_id: trace_id
		});

		for (let entry in required) {
			write_ruleset_task_progress(trace_id, {
				status: "running",
				message: "Rule Set sync running",
				total_count: length(required),
				completed_count: length(updated) + length(unchanged) + length(failed),
				updated_count: length(updated),
				unchanged_count: length(unchanged),
				failed_count: length(failed),
				checked_count: length(checked),
				progress: progress_percent(length(updated) + length(unchanged) + length(failed), length(required)),
				current_item: entry.tag,
				last_error: "",
				meta: {
					fetch_strategy: strategy,
					current_url_redacted: "",
					rule_dir: PATH.RULE_DIR
				}
			});

			let result = download_required_entry(trace_id, entry, config, strategy, tmp_dir, function(patch) {
				write_ruleset_task_progress(trace_id, {
					current_item: patch.current_item,
					last_error: patch.last_error || "",
					meta: patch.meta || {}
				});
			});
			for (let attempt in result.attempts)
				push(attempts, attempt);

			if (result.status == "failed") {
				push(failed, {
					tag: result.tag,
					path: result.path,
					error: result.error
				});
				write_ruleset_task_progress(trace_id, {
					completed_count: length(updated) + length(unchanged) + length(failed),
					updated_count: length(updated),
					unchanged_count: length(unchanged),
					failed_count: length(failed),
					checked_count: length(checked),
					progress: progress_percent(length(updated) + length(unchanged) + length(failed), length(required)),
					current_item: entry.tag,
					last_error: result.error
				});
				continue;
			}

			if (result.status == "unchanged") {
				push(unchanged, {
					tag: result.tag,
					path: result.path,
					size: result.size,
					url_redacted: result.url_redacted,
					checked_download: true
				});
				push(checked, entry.tag);
				write_ruleset_task_progress(trace_id, {
					completed_count: length(updated) + length(unchanged) + length(failed),
					updated_count: length(updated),
					unchanged_count: length(unchanged),
					failed_count: length(failed),
					checked_count: length(checked),
					progress: progress_percent(length(updated) + length(unchanged) + length(failed), length(required)),
					current_item: entry.tag,
					last_error: "",
					meta: {
						current_url_redacted: result.url_redacted
					}
				});
				continue;
			}

			push(updated, {
				tag: result.tag,
				path: result.path,
				size: result.size,
				url_redacted: result.url_redacted,
				backup_created: result.backup_created == true,
				pending_runtime_validation: result.pending_runtime_validation == true,
				transaction_changed_count: result.transaction_changed_count || 0
			});
			write_ruleset_task_progress(trace_id, {
				completed_count: length(updated) + length(unchanged) + length(failed),
				updated_count: length(updated),
				unchanged_count: length(unchanged),
				failed_count: length(failed),
				checked_count: length(checked),
				progress: progress_percent(length(updated) + length(unchanged) + length(failed), length(required)),
				current_item: entry.tag,
				last_error: "",
				meta: {
					current_url_redacted: result.url_redacted
				}
			});
		}

		lock_release(lock);
		let auto_apply = maybe_auto_apply_ruleset_update(trace_id, {
			updated_count: length(updated),
			unchanged_count: length(unchanged),
			failed_count: length(failed),
			checked_count: length(checked),
			mode: config.ruleset.mode
		}, {
			auto_apply_intent: type(req) == "object" && req != null && req.auto_apply_intent == true,
			scheduler_intent: type(req) == "object" && req != null && req.scheduler_intent == true,
			ruleset_policy: config.ruleset
		});
		if (ruleset_task_enabled(trace_id)) {
			finish_task(RULESET_SYNC_TASK, length(failed) ? "partial" : "success", trace_id, {
				message: "Required Rule Sets downloaded",
				total_count: length(required),
				completed_count: length(required),
				updated_count: length(updated),
				unchanged_count: length(unchanged),
				failed_count: length(failed),
				checked_count: length(checked),
				progress: 100,
				current_item: "",
				last_error: length(failed) ? failed[length(failed) - 1].error : "",
				meta: {
					fetch_strategy: strategy,
					current_url_redacted: "",
					rule_dir: PATH.RULE_DIR,
					auto_apply: auto_apply
				}
			});
		}
		return Success({
			required_count: length(required),
			updated_count: length(updated),
			unchanged_count: length(unchanged),
			failed_count: length(failed),
			checked_count: length(checked),
			rule_dir: PATH.RULE_DIR,
			tmp_dir: tmp_dir,
			mode: config.ruleset.mode,
			fetch_strategy: strategy,
			updated: updated,
			unchanged: unchanged,
			checked: checked,
			failed: failed,
			attempts: attempts,
			auto_apply: auto_apply
		}, 200, trace_id, "Required Rule Sets downloaded");
	} catch (e) {
		if (lock != null)
			lock_release(lock);
		let err = "" + e;
		if (ruleset_task_enabled(trace_id)) {
			try {
				fail_task(RULESET_SYNC_TASK, trace_id, err, {
					message: "Failed to download required Rule Sets"
				});
			} catch (task_error) {
				let ignored = "" + task_error;
			}
		}
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to download required Rule Sets", trace_id, err);
	}
}
function ruleset_artifact_status(trace_id, req) {
	try {
		return Success(ruleset_artifact_state(trace_id), 200, trace_id, "Rule Set artifact status loaded");
	} catch (e) {
		let err = "" + e;
		return Fail(ERR.E_RULESET_INVENTORY_FAILED, "Failed to load Rule Set artifact status", trace_id, err);
	}
}

function ruleset_download_one(trace_id, req) {
	let lock = null;
	try {
		ensure_rule_dirs();
		let tag = request_tag(req);
		let config = normalized_subscriptions_config();
		let strategy = config.ruleset.fetch_strategy == "proxy" ? "proxy" : "direct";
		let required = required_entries_from_profile().entries;
		let entry = find_required_entry(required, tag);
		let tmp_dir = PATH.RULE_DIR + "/.tmp";

		if (entry == null)
			die("Rule Set tag is not required by profile: " + tag);

		lock = lock_acquire("ruleset", trace_id);
		write_ruleset_download_one_task_progress(trace_id, {
			status: "running",
			message: "Rule Set download running",
			total_count: 1,
			completed_count: 0,
			updated_count: 0,
			unchanged_count: 0,
			failed_count: 0,
			checked_count: 0,
			progress: 0,
			current_item: tag,
			last_error: "",
			meta: {
				tag: tag,
				fetch_strategy: strategy,
				current_url_redacted: "",
				rule_dir: PATH.RULE_DIR
			},
			trace_id: trace_id
		});

		let result = download_required_entry(trace_id, entry, config, strategy, tmp_dir, function(patch) {
			write_ruleset_download_one_task_progress(trace_id, {
				current_item: patch.current_item,
				last_error: patch.last_error || "",
				meta: patch.meta || {}
			});
		});

		if (result.status == "failed") {
			if (ruleset_download_one_task_enabled(trace_id)) {
				finish_task(RULESET_DOWNLOAD_ONE_TASK, "failed", trace_id, {
					message: "Rule Set download failed",
					total_count: 1,
					completed_count: 1,
					updated_count: 0,
					unchanged_count: 0,
					failed_count: 1,
					checked_count: 0,
					progress: 100,
					current_item: "",
					last_error: result.error,
					meta: {
						tag: tag,
						fetch_strategy: strategy,
						current_url_redacted: "",
						rule_dir: PATH.RULE_DIR
					}
				});
			}
			die(result.error);
		}

		let updated_count = result.status == "updated" ? 1 : 0;
		let unchanged_count = result.status == "unchanged" ? 1 : 0;
		let checked_count = result.status == "unchanged" ? 1 : 0;

		lock_release(lock);
		lock = null;

		if (ruleset_download_one_task_enabled(trace_id)) {
			finish_task(RULESET_DOWNLOAD_ONE_TASK, "success", trace_id, {
				message: result.status == "updated" ? "Rule Set downloaded" : "Rule Set unchanged",
				total_count: 1,
				completed_count: 1,
				updated_count: updated_count,
				unchanged_count: unchanged_count,
				failed_count: 0,
				checked_count: checked_count,
				progress: 100,
				current_item: "",
				last_error: "",
				meta: {
					tag: tag,
					fetch_strategy: strategy,
					current_url_redacted: result.url_redacted || "",
					rule_dir: PATH.RULE_DIR,
					pending_runtime_validation: result.pending_runtime_validation == true
				}
			});
		}

		return Success({
			tag: tag,
			status: result.status,
			updated: result.status == "updated",
			unchanged: result.status == "unchanged",
			path: result.path,
			size: result.size || 0,
			url_redacted: result.url_redacted || "",
			mode: config.ruleset.mode,
			fetch_strategy: strategy,
			pending_runtime_validation: result.pending_runtime_validation == true,
			transaction_changed_count: result.transaction_changed_count || 0,
			attempts: result.attempts || []
		}, 200, trace_id, result.status == "updated" ? "Rule Set downloaded" : "Rule Set unchanged");
	} catch (e) {
		if (lock != null)
			lock_release(lock);
		let err = "" + e;
		if (ruleset_download_one_task_enabled(trace_id)) {
			try {
				fail_task(RULESET_DOWNLOAD_ONE_TASK, trace_id, err, {
					message: "Failed to download Rule Set"
				});
			} catch (task_error) {
				let ignored = "" + task_error;
			}
		}
		return Fail(ERR.E_RULESET_DOWNLOAD_FAILED, "Failed to download Rule Set", trace_id, err);
	}
}

function ruleset_download_one_start(trace_id, req) {
	return ruleset_download_one_start_impl(trace_id, req);
}

function ruleset_download_one_status(trace_id, req) {
	return ruleset_download_one_status_impl(trace_id, req);
}

export { ruleset_inventory, ruleset_required_inventory, ruleset_policy_get, ruleset_policy_save, ruleset_download_required, ruleset_download_required_start, ruleset_download_required_status, ruleset_artifact_status, ruleset_download_one, ruleset_download_one_start, ruleset_download_one_status };

