/**
 * Shinra | core/artifact.uc | v1.0
 */

'use strict';

import { PATH, BIN } from 'shinra.core.constants';
import { read_text, write_text_atomic, write_runtime_text_atomic, parse_json_object, file_exists, ensure_config_dir, ExecResult } from 'shinra.core.utils';

function artifact_check_config(trace_id, path) {
	let result = ExecResult(trace_id, [ BIN.SING_BOX, "check", "-c", path ]);
	return {
		ok: result.code == 0,
		path: path,
		stdout: result.stdout,
		stderr: result.stderr,
		error: result.code == 0 ? "" : (result.stderr || result.stdout)
	};
}

function artifact_write_candidate(trace_id, content) {
	parse_json_object(content, "Candidate Config");
	write_runtime_text_atomic(PATH.CANDIDATE_CONFIG, content);
	return {
		path: PATH.CANDIDATE_CONFIG
	};
}

function artifact_commit_runtime(trace_id, candidate_path, runtime_path, backup_path) {
	if (!file_exists(candidate_path))
		die("Candidate config not found: " + candidate_path);

	let candidate = read_text(candidate_path);
	parse_json_object(candidate, "Candidate Config");
	ensure_config_dir();

	let backup_created = false;
	if (file_exists(runtime_path)) {
		let current = read_text(runtime_path);
		parse_json_object(current, "Runtime Config");
		write_text_atomic(backup_path, current);
		backup_created = true;
	}

	write_text_atomic(runtime_path, candidate);
	return {
		path: runtime_path,
		backup: backup_path,
		backup_created: backup_created
	};
}

function artifact_restore_runtime(trace_id, runtime_path, backup_path) {
	if (!file_exists(backup_path))
		return {
			restored: false,
			path: runtime_path,
			backup: backup_path
		};

	let backup = read_text(backup_path);
	parse_json_object(backup, "Runtime Config Backup");
	write_text_atomic(runtime_path, backup);
	return {
		restored: true,
		path: runtime_path,
		backup: backup_path
	};
}

function artifact_swap_runtime_backup(trace_id, runtime_path, backup_path) {
	if (!file_exists(backup_path))
		die("Runtime backup config not found: " + backup_path);

	let backup = read_text(backup_path);
	parse_json_object(backup, "Runtime Config Backup");
	let current = "";
	if (file_exists(runtime_path))
		current = read_text(runtime_path);

	write_text_atomic(runtime_path, backup);
	if (current != "")
		write_text_atomic(backup_path, current);

	return {
		path: runtime_path,
		backup: backup_path,
		backup_created: current != ""
	};
}

export { artifact_check_config, artifact_write_candidate, artifact_commit_runtime, artifact_restore_runtime, artifact_swap_runtime_backup };
