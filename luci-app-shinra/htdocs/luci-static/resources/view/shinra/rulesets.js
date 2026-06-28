'use strict';
'require view';
'require rpc';

const callRulesetInventory = rpc.declare({
	object: 'shinra',
	method: 'ruleset_inventory',
	params: [ 'source' ],
	expect: { '': {} }
});

const callRulesetRequiredInventory = rpc.declare({
	object: 'shinra',
	method: 'ruleset_required_inventory',
	expect: { '': {} }
});

const callRulesetPolicyGet = rpc.declare({
	object: 'shinra',
	method: 'ruleset_policy_get',
	expect: { '': {} }
});

const callRulesetPolicySave = rpc.declare({
	object: 'shinra',
	method: 'ruleset_policy_save',
	params: [ 'content' ],
	expect: { '': {} }
});

const callRulesetDownloadRequiredStart = rpc.declare({
	object: 'shinra',
	method: 'ruleset_download_required_start',
	expect: { '': {} }
});

const callRulesetDownloadRequiredStatus = rpc.declare({
	object: 'shinra',
	method: 'ruleset_download_required_status',
	expect: { '': {} }
});

const DEFAULT_POLICY = {
	mode: 'remote',
	auto_update: false,
	update_hour: 4,
	fetch_strategy: 'direct',
	repositories: {
		private: '',
		public: 'https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing'
	}
};

let policy = null;
let inventories = {
	profile: null,
	candidate: null,
	required: null
};
let activeTab = 'required';
let actionStatus = '';
let actionStatusOk = true;
let actionToken = 0;

function dataOf(result) {
	if (result && result.ok && result.data)
		return result.data;
	return {};
}

function normalizePolicy(input) {
	input = input && typeof input === 'object' && !Array.isArray(input) ? input : {};
	const repositories = input.repositories && typeof input.repositories === 'object' && !Array.isArray(input.repositories) ? input.repositories : {};
	let hour = input.update_hour != null ? Number(input.update_hour) : DEFAULT_POLICY.update_hour;

	if (!Number.isFinite(hour) || hour < 0 || hour > 23)
		hour = DEFAULT_POLICY.update_hour;

	return {
		mode: input.mode === 'local' ? 'local' : 'remote',
		auto_update: input.auto_update === true,
		update_hour: hour,
		fetch_strategy: input.fetch_strategy === 'proxy' ? 'proxy' : 'direct',
		repositories: {
			private: typeof repositories.private === 'string' ? repositories.private : DEFAULT_POLICY.repositories.private,
			public: typeof repositories.public === 'string' && repositories.public !== '' ? repositories.public : DEFAULT_POLICY.repositories.public
		}
	};
}

function valueText(value) {
	if (value == null || value === '')
		return '-';
	return String(value);
}

function readFieldValue(id, fallback) {
	const node = document.getElementById(id);
	return node ? node.value : fallback;
}

function readFieldChecked(id, fallback) {
	const node = document.getElementById(id);
	return node ? !!node.checked : fallback;
}

function readFieldNumber(id, fallback) {
	const value = readFieldValue(id, null);
	if (value == null || value === '')
		return fallback;
	return Number(value);
}

function bytesText(value) {
	if (typeof value !== 'number' || !isFinite(value) || value <= 0)
		return '0 B';

	const units = [ 'B', 'KB', 'MB', 'GB' ];
	let size = value;
	let index = 0;

	while (size >= 1024 && index < units.length - 1) {
		size = size / 1024;
		index++;
	}

	return index === 0 ? '%d %s'.format(Math.round(size), units[index]) : '%.1f %s'.format(size, units[index]);
}

function sectionStyle() {
	return 'border: 1px solid #dfe3e8; border-radius: 8px; padding: 1rem; margin-bottom: 1rem; background: #fff;';
}

function statusPill(text, level) {
	let color = '#475569';
	let bg = '#f1f5f9';

	if (level === 'ok') {
		color = '#166534';
		bg = '#dcfce7';
	} else if (level === 'warning') {
		color = '#92400e';
		bg = '#fef3c7';
	} else if (level === 'error') {
		color = '#991b1b';
		bg = '#fee2e2';
	}

	return E('span', {
		'style': 'display: inline-flex; align-items: center; min-height: 22px; padding: 0 .55rem; border-radius: 999px; font-size: 12px; font-weight: 700; color: %s; background: %s; white-space: nowrap;'.format(color, bg)
	}, text);
}

function setStatus(text, ok) {
	actionStatus = text || '';
	actionStatusOk = ok !== false;
	const node = document.getElementById('shinra-ruleset-action-status');
	if (!node)
		return;

	node.textContent = actionStatus;
	node.style.display = actionStatus ? 'block' : 'none';
	node.style.borderColor = actionStatusOk ? '#bbf7d0' : '#fecaca';
	node.style.background = actionStatusOk ? '#f0fdf4' : '#fef2f2';
	node.style.color = actionStatusOk ? '#166534' : '#991b1b';
}

function inlineActionStatus() {
	return E('div', {
		'id': 'shinra-ruleset-action-status',
		'style': 'display: %s; border: 1px solid %s; border-radius: 8px; padding: .65rem; margin-top: .75rem; background: %s; color: %s; overflow-wrap: anywhere;'.format(
			actionStatus ? 'block' : 'none',
			actionStatusOk ? '#bbf7d0' : '#fecaca',
			actionStatusOk ? '#f0fdf4' : '#fef2f2',
			actionStatusOk ? '#166534' : '#991b1b'
		)
	}, actionStatus);
}

function notifyFailure(result) {
	if (!result || result.ok)
		return;
	setStatus('%s: %s'.format(result.message || result.code || _('\u672a\u77e5\u9519\u8bef'), result.detail || result.code || _('\u65e0\u8be6\u7ec6\u4fe1\u606f')), false);
}

function delay(ms) {
	return new Promise(function(resolve) {
		window.setTimeout(resolve, ms);
	});
}

function rulesetJobFrom(result) {
	const data = dataOf(result);
	const state = data.state && typeof data.state === 'object' ? data.state : {};
	const jobs = state.jobs && typeof state.jobs === 'object' ? state.jobs : {};
	return jobs.ruleset_download_required && typeof jobs.ruleset_download_required === 'object' ? jobs.ruleset_download_required : {};
}

function rulesetJobCounts(job) {
	const completed = Number(job.completed_count || 0);
	let text = _('\u8fdb\u5ea6 %d / %d\uff0c\u5df2\u66f4\u65b0 %d\uff0c\u672a\u53d8\u5316 %d\uff0c\u5931\u8d25 %d').format(
		completed,
		Number(job.required_count || 0),
		Number(job.updated_count || 0),
		Number(job.unchanged_count || 0),
		Number(job.failed_count || 0)
	);
	const checked = Number(job.checked_count || 0);
	if (checked)
		text += _('\uff1b\u5b8c\u6574\u6bd4\u5bf9 %d').format(checked);
	if (job.current_tag)
		text += _('\uff1b\u5f53\u524d %s').format(job.current_tag);
	if (job.current_url_redacted)
		text += _('\uff1b\u6765\u6e90 %s').format(job.current_url_redacted);
	if (job.last_error)
		text += _('\uff1b\u6700\u8fd1\u9519\u8bef %s').format(job.last_error);
	return text;
}

function rulesetJobStatusText(job) {
	const status = job.status || '-';
	const counts = rulesetJobCounts(job);
	const message = job.message || '';

	if (status === 'starting')
		return _('\u89c4\u5219\u96c6\u540c\u6b65\u5df2\u6392\u961f\u3002');
	if (status === 'running')
		return _('\u89c4\u5219\u96c6\u6b63\u5728\u540c\u6b65\uff1a%s').format(counts);
	if (status === 'success')
		return _('\u89c4\u5219\u96c6\u540c\u6b65\u5b8c\u6210\uff1a%s%s').format(counts, message ? ' - ' + message : '');
	if (status === 'partial')
		return _('\u89c4\u5219\u96c6\u90e8\u5206\u540c\u6b65\u5b8c\u6210\uff1a%s%s').format(counts, message ? ' - ' + message : '');
	if (status === 'failed')
		return _('\u89c4\u5219\u96c6\u540c\u6b65\u5931\u8d25\uff1a%s').format(message || counts);

	return message || _('\u672a\u89c2\u6d4b\u5230\u89c4\u5219\u96c6\u540c\u6b65\u72b6\u6001\u3002');
}

function updatePolicyFromFields() {
	policy = normalizePolicy({
		mode: readFieldValue('shinra-ruleset-mode', policy.mode),
		auto_update: readFieldChecked('shinra-ruleset-auto-update', policy.auto_update),
		update_hour: readFieldNumber('shinra-ruleset-update-hour', policy.update_hour),
		fetch_strategy: readFieldValue('shinra-ruleset-fetch-strategy', policy.fetch_strategy),
		repositories: {
			private: readFieldValue('shinra-ruleset-private-repo', policy.repositories.private),
			public: readFieldValue('shinra-ruleset-public-repo', policy.repositories.public)
		}
	});
}

function modeHelpText() {
	return policy.mode === 'local' ?
		_('\u672c\u5730\u6a21\u5f0f\u4f1a\u5728\u751f\u6210\u5019\u9009\u914d\u7f6e\u65f6\u628a\u89c4\u5219\u96c6\u6539\u5199\u5230 /etc/shinra/rules\u3002\u7f3a\u5931\u672c\u5730\u6587\u4ef6\u4f1a\u963b\u6b62\u5019\u9009\u914d\u7f6e\u751f\u6210\u3002') :
		_('\u8fdc\u7a0b\u6a21\u5f0f\u4fdd\u7559 main-profile.json \u4e2d\u7684 rule_set \u58f0\u660e\uff0c\u4e0d\u8981\u6c42\u672c\u5730\u89c4\u5219\u96c6\u6587\u4ef6\u3002');
}

function modeSettings() {
	return E('div', { 'style': sectionStyle() }, [
		E('h3', { 'style': 'margin-top: 0;' }, _('\u6a21\u5f0f\u8bbe\u7f6e')),
		E('div', { 'style': 'display: flex; gap: .65rem; align-items: flex-end; flex-wrap: wrap; margin-bottom: .65rem;' }, [
			E('label', { 'style': 'min-width: 220px;' }, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('\u89c4\u5219\u96c6\u6a21\u5f0f')),
				E('select', {
					'id': 'shinra-ruleset-mode',
					'class': 'cbi-input-select',
					'style': 'width: 100%;',
					'change': function(ev) {
						actionToken++;
						updatePolicyFromFields();
						policy.mode = ev.target.value === 'local' ? 'local' : 'remote';
						actionStatus = '';
						redraw();
					}
				}, [
					E('option', { 'value': 'remote', 'selected': policy.mode === 'remote' ? 'selected' : null }, _('\u8fdc\u7a0b\u6a21\u5f0f')),
					E('option', { 'value': 'local', 'selected': policy.mode === 'local' ? 'selected' : null }, _('\u672c\u5730\u6a21\u5f0f'))
				])
			]),
			E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-save', 'click': function(ev) { ev.preventDefault(); return savePolicy(); } }, _('\u4fdd\u5b58\u8bbe\u7f6e')),
			policy.mode === 'local' ? E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-apply', 'click': function(ev) { ev.preventDefault(); return syncRulesets(); } }, _('\u540c\u6b65\u6240\u9700\u89c4\u5219\u96c6')) : ''
		]),
		E('div', { 'style': 'color: #667; overflow-wrap: anywhere;' }, modeHelpText()),
		inlineActionStatus()
	]);
}

function localSyncSettings() {
	if (policy.mode !== 'local')
		return E('div', { 'style': 'display: none;' }, '');

	return E('div', { 'style': sectionStyle() }, [
		E('h3', { 'style': 'margin-top: 0;' }, _('\u672c\u5730\u540c\u6b65\u8bbe\u7f6e')),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: .75rem; margin-bottom: .75rem;' }, [
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('\u672c\u5730\u76ee\u5f55')),
				E('input', { 'class': 'cbi-input-text', 'readonly': 'readonly', 'value': '/etc/shinra/rules' })
			]),
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('\u4e0b\u8f7d\u7b56\u7565')),
				E('select', { 'id': 'shinra-ruleset-fetch-strategy', 'class': 'cbi-input-select', 'style': 'width: 100%;' }, [
					E('option', { 'value': 'direct', 'selected': policy.fetch_strategy === 'direct' ? 'selected' : null }, _('\u76f4\u8fde')),
					E('option', { 'value': 'proxy', 'selected': policy.fetch_strategy === 'proxy' ? 'selected' : null }, _('\u4ee3\u7406'))
				])
			]),
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('\u6bcf\u65e5\u540c\u6b65\u65f6\u95f4')),
				E('input', {
					'id': 'shinra-ruleset-update-hour',
					'class': 'cbi-input-text',
					'type': 'number',
					'min': '0',
					'max': '23',
					'value': String(policy.update_hour)
				})
			]),
			E('label', { 'style': 'display: flex; gap: .5rem; align-items: center; margin-top: 1.45rem;' }, [
				E('input', { 'id': 'shinra-ruleset-auto-update', 'type': 'checkbox', 'checked': policy.auto_update ? 'checked' : null }),
				E('span', {}, _('\u6bcf\u65e5\u81ea\u52a8\u540c\u6b65'))
			])
		]),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: .75rem; margin-bottom: .75rem;' }, [
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('\u79c1\u6709\u4ed3\u5e93')),
				E('input', {
					'id': 'shinra-ruleset-private-repo',
					'class': 'cbi-input-text',
					'placeholder': _('\u53ef\u9009\u7684\u79c1\u6709\u4ed3\u5e93\u5730\u5740'),
					'value': policy.repositories.private
				})
			]),
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('\u516c\u5171\u4ed3\u5e93')),
				E('input', {
					'id': 'shinra-ruleset-public-repo',
					'class': 'cbi-input-text',
					'value': policy.repositories.public
				})
			])
		]),
		E('div', { 'style': 'color: #667;' }, _('\u4e0b\u8f7d\u987a\u5e8f\uff1a\u79c1\u6709\u4ed3\u5e93\u4f18\u5148\uff0c\u516c\u5171\u4ed3\u5e93\u515c\u5e95\uff0c\u6700\u540e\u4f7f\u7528\u6a21\u677f\u4e2d\u7684\u539f\u59cb\u5730\u5740\u3002'))
	]);
}

function tabButton(tab, label) {
	return E('button', {
		'type': 'button',
		'class': activeTab === tab ? 'btn cbi-button cbi-button-positive' : 'btn cbi-button',
		'click': function(ev) {
			ev.preventDefault();
			actionToken++;
			activeTab = tab;
			actionStatus = '';
			redraw();
		}
	}, label);
}

function timeText(value) {
	if (!value)
		return '-';
	return valueText(value);
}

function statBox(label, value) {
	return E('div', { 'style': 'border: 1px solid #e5e7eb; border-radius: 8px; padding: .65rem; background: #f8fafc;' }, [
		E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700;' }, label),
		E('div', { 'style': 'font-size: 22px; font-weight: 800; margin-top: .25rem;' }, valueText(value))
	]);
}

function requiredInventory() {
	return inventories.required && typeof inventories.required === 'object' ? inventories.required : {};
}

function rulesetStatus(entry) {
	if (!entry || entry.status === 'missing')
		return statusPill(_('\u7f3a\u5931'), 'error');
	if (entry.status === 'extra')
		return statusPill(_('\u672c\u5730\u591a\u4f59'), 'warning');
	return statusPill(_('\u5df2\u5c31\u7eea'), 'ok');
}

function sourceText(entry) {
	const urls = entry && Array.isArray(entry.candidate_url_redacted) ? entry.candidate_url_redacted : [];
	if (urls.length)
		return urls.join('\n');
	return valueText(entry && (entry.source_url_redacted || entry.source_url));
}

function readinessSummary(inv) {
	const summary = inv.summary || {};
	return E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: .65rem; margin: .75rem 0;' }, [
		statBox(_('\u6a21\u677f\u9700\u8981'), summary.required_count || 0),
		statBox(_('\u5df2\u5c31\u7eea'), summary.ready_count || 0),
		statBox(_('\u7f3a\u5931'), summary.missing_count || 0),
		statBox(_('\u672c\u5730\u603b\u6570'), summary.local_count || 0),
		statBox(_('\u672c\u5730\u591a\u4f59'), summary.local_extra_count || 0)
	]);
}

function requiredRows(entries) {
	if (!entries.length)
		return [ E('tr', {}, [ E('td', { 'colspan': '7', 'style': 'padding: .8rem; color: #667; text-align: center;' }, _('\u6a21\u677f\u6ca1\u6709\u5f15\u7528\u89c4\u5219\u96c6\u3002')) ]) ];

	return entries.map(function(entry) {
		return E('tr', {}, [
			E('td', { 'style': 'overflow-wrap: anywhere; font-weight: 600;' }, valueText(entry.tag)),
			E('td', {}, rulesetStatus(entry)),
			E('td', { 'style': 'overflow-wrap: anywhere;' }, valueText(entry.local_path)),
			E('td', { 'style': 'text-align: right;' }, bytesText(Number(entry.local_size || 0))),
			E('td', { 'style': 'text-align: right;' }, timeText(entry.local_mtime)),
			E('td', { 'style': 'overflow-wrap: anywhere; white-space: pre-line;' }, sourceText(entry)),
			E('td', {}, entry.status === 'missing' ? _('\u6a21\u677f\u9700\u8981\uff0c\u672c\u5730\u7f3a\u5931') : '-')
		]);
	});
}

function extraRows(entries) {
	if (!entries.length)
		return [ E('tr', {}, [ E('td', { 'colspan': '5', 'style': 'padding: .8rem; color: #667; text-align: center;' }, _('\u6ca1\u6709\u672c\u5730\u591a\u4f59\u89c4\u5219\u96c6\u3002')) ]) ];

	return entries.map(function(entry) {
		return E('tr', {}, [
			E('td', { 'style': 'overflow-wrap: anywhere; font-weight: 600;' }, valueText(entry.tag)),
			E('td', {}, rulesetStatus(entry)),
			E('td', { 'style': 'overflow-wrap: anywhere;' }, valueText(entry.local_path)),
			E('td', { 'style': 'text-align: right;' }, bytesText(Number(entry.local_size || 0))),
			E('td', { 'style': 'text-align: right;' }, timeText(entry.local_mtime))
		]);
	});
}

function rulesetList() {
	const inv = requiredInventory();
	const entries = Array.isArray(inv.entries) ? inv.entries : [];
	const extras = Array.isArray(inv.extras) ? inv.extras : [];
	const showingExtras = activeTab === 'extra';

	return E('div', { 'style': sectionStyle() }, [
		E('div', { 'style': 'display: flex; justify-content: space-between; align-items: center; gap: .75rem; flex-wrap: wrap; margin-bottom: .75rem;' }, [
			E('h3', { 'style': 'margin: 0;' }, _('\u89c4\u5219\u96c6\u5bf9\u6bd4')),
			E('div', { 'style': 'display: flex; gap: .5rem; flex-wrap: wrap;' }, [
				tabButton('required', _('\u6a21\u677f\u6240\u9700')),
				tabButton('extra', _('\u672c\u5730\u591a\u4f59'))
			])
		]),
		E('div', { 'style': 'color: #667; margin-bottom: .75rem; overflow-wrap: anywhere;' },
			_('\u5bf9\u6bd4 main-profile.json \u5f15\u7528\u7684\u89c4\u5219\u96c6\u4e0e /etc/shinra/rules \u672c\u5730\u6587\u4ef6\u3002')),
		readinessSummary(inv),
		E('div', { 'style': 'overflow-x: auto;' }, [
			showingExtras ?
				E('table', { 'class': 'table', 'style': 'min-width: 760px;' }, [
					E('thead', {}, [ E('tr', {}, [
						E('th', {}, _('\u6807\u7b7e')),
						E('th', {}, _('\u72b6\u6001')),
						E('th', {}, _('\u672c\u5730\u6587\u4ef6')),
						E('th', { 'style': 'text-align: right;' }, _('\u5927\u5c0f')),
						E('th', { 'style': 'text-align: right;' }, _('\u4fee\u6539\u65f6\u95f4'))
					]) ]),
					E('tbody', {}, extraRows(extras))
				]) :
				E('table', { 'class': 'table', 'style': 'min-width: 980px;' }, [
					E('thead', {}, [ E('tr', {}, [
						E('th', {}, _('\u6807\u7b7e')),
						E('th', {}, _('\u72b6\u6001')),
						E('th', {}, _('\u672c\u5730\u6587\u4ef6')),
						E('th', { 'style': 'text-align: right;' }, _('\u5927\u5c0f')),
						E('th', { 'style': 'text-align: right;' }, _('\u4fee\u6539\u65f6\u95f4')),
						E('th', {}, _('\u4e0b\u8f7d\u6765\u6e90')),
						E('th', {}, _('\u8bca\u65ad'))
					]) ]),
					E('tbody', {}, requiredRows(entries))
				])
		])
	]);
}

function savePolicy() {
	const token = ++actionToken;
	updatePolicyFromFields();
	setStatus(_('\u6b63\u5728\u4fdd\u5b58\u8bbe\u7f6e...'), true);

	return callRulesetPolicySave(JSON.stringify(policy)).then(function(result) {
		if (token !== actionToken)
			return result;
		notifyFailure(result);
		if (result && result.ok) {
			policy = normalizePolicy(dataOf(result).policy);
			setStatus(_('\u89c4\u5219\u96c6\u8bbe\u7f6e\u5df2\u4fdd\u5b58\u3002'), true);
			redraw();
		} else {
			setStatus(_('\u4fdd\u5b58\u5931\u8d25\u3002'), false);
		}
		return result;
	}).catch(function(error) {
		if (token !== actionToken)
			return;
		setStatus(error.message || String(error), false);
	});
}

function pollRulesetSync(token, attempt) {
	return callRulesetDownloadRequiredStatus().then(function(statusResult) {
		if (token !== actionToken)
			return statusResult;
		notifyFailure(statusResult);
		if (!statusResult || !statusResult.ok) {
			setStatus(_('\u8bfb\u53d6\u89c4\u5219\u96c6\u540c\u6b65\u72b6\u6001\u5931\u8d25\u3002'), false);
			return refreshAll();
		}

		const job = rulesetJobFrom(statusResult);
		const status = job.status || '';

		if (status === 'starting' || status === 'running') {
			setStatus(rulesetJobStatusText(job), true);
			if (attempt >= 180) {
				setStatus(_('\u89c4\u5219\u96c6\u540c\u6b65\u4ecd\u5728\u540e\u53f0\u8fd0\u884c\u3002\u7a0d\u540e\u8fd4\u56de\u53ef\u67e5\u770b\u7ed3\u679c\u3002'), true);
				return refreshAll();
			}

			return delay(2000).then(function() {
				return pollRulesetSync(token, attempt + 1);
			});
		}

		const ok = status === 'success' || status === 'partial';
		setStatus(rulesetJobStatusText(job), ok && Number(job.failed_count || 0) === 0);
		return refreshAll();
	}).catch(function(error) {
		if (token !== actionToken)
			return;
		setStatus(error.message || String(error), false);
		return refreshAll();
	});
}

function syncRulesets() {
	const token = ++actionToken;
	updatePolicyFromFields();
	setStatus(_('\u6b63\u5728\u4fdd\u5b58\u8bbe\u7f6e\u5e76\u542f\u52a8\u89c4\u5219\u96c6\u540c\u6b65...'), true);

	return callRulesetPolicySave(JSON.stringify(policy)).then(function(saveResult) {
		if (token !== actionToken)
			return saveResult;
		notifyFailure(saveResult);
		if (!saveResult || !saveResult.ok) {
			setStatus(_('\u4fdd\u5b58\u5931\u8d25\u3002'), false);
			return saveResult;
		}

		policy = normalizePolicy(dataOf(saveResult).policy);
		return callRulesetDownloadRequiredStart();
	}).then(function(startResult) {
		if (token !== actionToken)
			return startResult;
		notifyFailure(startResult);
		if (!startResult || !startResult.ok) {
			setStatus(_('\u542f\u52a8\u89c4\u5219\u96c6\u540c\u6b65\u5931\u8d25\u3002'), false);
			return refreshAll();
		}

		const job = rulesetJobFrom(startResult);
		setStatus(rulesetJobStatusText(job), true);
		return pollRulesetSync(token, 0);
	}).catch(function(error) {
		if (token !== actionToken)
			return;
		setStatus(error.message || String(error), false);
	});
}

function refreshAll() {
	return Promise.all([
		callRulesetPolicyGet(),
		callRulesetRequiredInventory()
	]).then(function(results) {
		for (let i = 0; i < results.length; i++)
			notifyFailure(results[i]);

		policy = normalizePolicy(dataOf(results[0]).policy);
		inventories.required = dataOf(results[1]);
		redraw();
		return results;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function redraw() {
	const root = document.getElementById('shinra-rulesets-root');
	if (root)
		root.parentNode.replaceChild(renderPage(), root);
}

function renderPage() {
	return E('div', { 'id': 'shinra-rulesets-root' }, [
		E('h2', {}, '规则集'),
		E('p', {}, '管理 main-profile.json 所需的规则集模式和本地资源。'),
		modeSettings(),
		localSyncSettings(),
		rulesetList()
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			callRulesetPolicyGet(),
			callRulesetRequiredInventory()
		]);
	},

	render: function(results) {
		const policyResult = results && results[0] ? results[0] : {};
		const requiredResult = results && results[1] ? results[1] : {};

		notifyFailure(policyResult);
		notifyFailure(requiredResult);

		policy = normalizePolicy(dataOf(policyResult).policy);
		inventories.required = dataOf(requiredResult);

		return renderPage();
	}
});
