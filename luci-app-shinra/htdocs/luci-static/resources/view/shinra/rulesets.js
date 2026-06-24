'use strict';
'require view';
'require rpc';

const callRulesetInventory = rpc.declare({
	object: 'shinra',
	method: 'ruleset_inventory',
	params: [ 'source' ],
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

const callRulesetDownloadRequired = rpc.declare({
	object: 'shinra',
	method: 'ruleset_download_required',
	expect: { '': {} }
});

const DEFAULT_POLICY = {
	mode: 'remote',
	auto_update: false,
	update_hour: 4,
	repositories: {
		private: '',
		public: 'https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing'
	}
};

let policy = null;
let inventories = {
	profile: null,
	candidate: null,
	runtime: null
};
let activeTab = 'remote';
let actionStatus = '';
let actionStatusOk = true;

function dataOf(result) {
	if (result && result.ok && result.data)
		return result.data;
	return {};
}

function notifyFailure(result) {
	if (!result || result.ok)
		return;

	const message = '%s: %s'.format(result.message || result.code || _('未知错误'), result.detail || result.code || _('无详细信息'));
	setStatus(message, false);
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
		repositories: {
			private: typeof repositories.private === 'string' ? repositories.private : DEFAULT_POLICY.repositories.private,
			public: typeof repositories.public === 'string' && repositories.public !== '' ? repositories.public : DEFAULT_POLICY.repositories.public
		}
	};
}

function readFieldValue(id, fallback) {
	const node = document.getElementById(id);
	if (!node)
		return fallback;

	return node.value;
}

function readFieldChecked(id, fallback) {
	const node = document.getElementById(id);
	if (!node)
		return fallback;

	return !!node.checked;
}

function readFieldNumber(id, fallback) {
	const value = readFieldValue(id, null);
	if (value == null || value === '')
		return fallback;

	return Number(value);
}

function valueText(value) {
	if (value == null || value === '')
		return '-';
	return String(value);
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

	if (index === 0)
		return '%d %s'.format(Math.round(size), units[index]);

	return '%.1f %s'.format(size, units[index]);
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

function remoteEntries() {
	const entries = inventories.profile && Array.isArray(inventories.profile.entries) ? inventories.profile.entries : [];
	return entries;
}

function localSource() {
	const candidate = inventories.candidate && Array.isArray(inventories.candidate.entries) ? inventories.candidate.entries : [];
	const runtime = inventories.runtime && Array.isArray(inventories.runtime.entries) ? inventories.runtime.entries : [];
	let candidateLocal = candidate.filter(function(entry) { return entry && entry.path; });
	let runtimeLocal = runtime.filter(function(entry) { return entry && entry.path; });

	if (candidateLocal.length)
		return {
			name: 'Candidate',
			path: inventories.candidate.path || '',
			entries: candidateLocal
		};

	if (runtimeLocal.length)
		return {
			name: 'Runtime',
			path: inventories.runtime.path || '',
			entries: runtimeLocal
		};

	return {
		name: 'Local',
		path: '/etc/shinra/rules',
		entries: []
	};
}

function modeButton(mode, label) {
	const active = policy.mode === mode;
	return E('button', {
		'class': active ? 'btn cbi-button cbi-button-positive' : 'btn cbi-button',
		'style': 'min-width: 120px;',
		'click': function(ev) {
			ev.preventDefault();
			updatePolicyFromFields();
			policy.mode = mode;
			redraw();
		}
	}, label);
}

function modeSettings() {
	return E('div', { 'style': sectionStyle() }, [
		E('h3', { 'style': 'margin-top: 0;' }, _('模式')),
		E('div', { 'style': 'display: flex; gap: .5rem; flex-wrap: wrap; margin-bottom: .65rem;' }, [
			modeButton('remote', _('远程模式')),
			modeButton('local', _('本地模式'))
		]),
		E('div', { 'style': 'color: #667; overflow-wrap: anywhere;' }, policy.mode === 'local' ?
			_('本地模式要求规则集位于 /etc/shinra/rules。缺少必要本地文件时，候选配置生成会失败。') :
			_('远程模式保留 main-profile.json 中的 rule_set 声明，不要求本地文件。'))
	]);
}

function localSyncSettings() {
	if (policy.mode !== 'local')
		return E('div', { 'style': 'display: none;' }, '');

	return E('div', { 'style': sectionStyle() }, [
		E('h3', { 'style': 'margin-top: 0;' }, _('本地同步设置')),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: .75rem; margin-bottom: .75rem;' }, [
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('本地目录')),
				E('input', { 'class': 'cbi-input-text', 'readonly': 'readonly', 'value': '/etc/shinra/rules' })
			]),
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('每日同步小时')),
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
				E('span', {}, _('每日自动同步'))
			])
		]),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: .75rem; margin-bottom: .75rem;' }, [
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('私有仓库')),
				E('input', {
					'id': 'shinra-ruleset-private-repo',
					'class': 'cbi-input-text',
					'placeholder': _('可选私有仓库地址'),
					'value': policy.repositories.private
				})
			]),
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('公共仓库')),
				E('input', {
					'id': 'shinra-ruleset-public-repo',
					'class': 'cbi-input-text',
					'value': policy.repositories.public
				})
			])
		]),
		E('div', { 'style': 'color: #667; margin-bottom: .85rem;' }, _('下载策略：私有仓库优先，公共仓库兜底，最后使用模板 URL。下载直连，不依赖代理。')),
		E('div', { 'style': 'display: flex; gap: .5rem; align-items: center; flex-wrap: wrap;' }, [
			E('button', { 'class': 'btn cbi-button cbi-button-save', 'click': function(ev) { ev.preventDefault(); return savePolicy(); } }, _('保存设置')),
			E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': function(ev) { ev.preventDefault(); return syncRulesets(); } }, _('同步所需规则集'))
		]),
		inlineActionStatus()
	]);
}

function remoteModeActions() {
	if (policy.mode === 'local')
		return E('div', { 'style': 'display: none;' }, '');

	return E('div', { 'style': sectionStyle() }, [
		E('div', { 'style': 'display: flex; justify-content: space-between; align-items: center; gap: .75rem; flex-wrap: wrap;' }, [
			E('div', {}, [
				E('div', { 'style': 'font-weight: 700;' }, _('远程规则集')),
				E('div', { 'style': 'color: #667; margin-top: .25rem;' }, _('远程模式只保存模式设置，本地同步控制项会隐藏。'))
			]),
			E('button', { 'class': 'btn cbi-button cbi-button-save', 'click': function(ev) { ev.preventDefault(); return savePolicy(); } }, _('保存设置'))
		]),
		inlineActionStatus()
	]);
}

function tabButton(tab, label) {
	return E('button', {
		'class': activeTab === tab ? 'btn cbi-button cbi-button-positive' : 'btn cbi-button',
		'click': function(ev) {
			ev.preventDefault();
			activeTab = tab;
			redraw();
		}
	}, label);
}

function remoteRows(entries) {
	if (!entries.length)
		return [ E('tr', {}, [ E('td', { 'colspan': '4', 'style': 'padding: .8rem; color: #667; text-align: center;' }, _('未声明远程规则集。')) ]) ];

	return entries.map(function(entry) {
		return E('tr', {}, [
			E('td', { 'style': 'overflow-wrap: anywhere; font-weight: 600;' }, valueText(entry.tag)),
			E('td', {}, '%s / %s'.format(valueText(entry.type), valueText(entry.format))),
			E('td', { 'style': 'overflow-wrap: anywhere;' }, valueText(entry.url_redacted || entry.source_url)),
			E('td', {}, statusPill(_('远程'), ''))
		]);
	});
}

function localRows(entries) {
	if (!entries.length)
		return [ E('tr', {}, [ E('td', { 'colspan': '5', 'style': 'padding: .8rem; color: #667; text-align: center;' }, _('未观测到本地规则集。请在本地模式下生成候选配置或同步规则集。')) ]) ];

	return entries.map(function(entry) {
		return E('tr', {}, [
			E('td', { 'style': 'overflow-wrap: anywhere; font-weight: 600;' }, valueText(entry.tag)),
			E('td', { 'style': 'overflow-wrap: anywhere;' }, valueText(entry.path)),
			E('td', { 'style': 'text-align: right;' }, bytesText(entry.size)),
			E('td', { 'style': 'text-align: right;' }, entry.mtime ? valueText(entry.mtime) : '-'),
			E('td', {}, entry.exists === false ? statusPill(_('缺失'), 'error') : statusPill(_('就绪'), 'ok'))
		]);
	});
}

function rulesetList() {
	const local = localSource();
	const entries = activeTab === 'local' ? local.entries : remoteEntries();

	return E('div', { 'style': sectionStyle() }, [
		E('div', { 'style': 'display: flex; justify-content: space-between; align-items: center; gap: .75rem; flex-wrap: wrap; margin-bottom: .75rem;' }, [
			E('h3', { 'style': 'margin: 0;' }, _('规则集列表')),
			E('div', { 'style': 'display: flex; gap: .5rem; flex-wrap: wrap;' }, [
				tabButton('remote', _('远程规则集')),
				tabButton('local', _('本地规则集'))
			])
		]),
		E('div', { 'style': 'color: #667; margin-bottom: .75rem; overflow-wrap: anywhere;' }, activeTab === 'local' ?
			'%s: %s'.format(_('本地来源'), '%s (%s)'.format(local.name, valueText(local.path))) :
			_('远程列表读取自原始模板声明。')),
		E('div', { 'style': 'overflow-x: auto;' }, [
			activeTab === 'local' ?
				E('table', { 'class': 'table', 'style': 'min-width: 820px;' }, [
					E('thead', {}, [ E('tr', {}, [
						E('th', {}, _('标签')),
						E('th', {}, _('路径')),
						E('th', { 'style': 'text-align: right;' }, _('大小')),
						E('th', { 'style': 'text-align: right;' }, _('修改时间')),
						E('th', {}, _('状态'))
					]) ]),
					E('tbody', {}, localRows(entries))
				]) :
				E('table', { 'class': 'table', 'style': 'min-width: 820px;' }, [
					E('thead', {}, [ E('tr', {}, [
						E('th', {}, _('标签')),
						E('th', {}, _('类型')),
						E('th', {}, _('来源')),
						E('th', {}, _('状态'))
					]) ]),
					E('tbody', {}, remoteRows(entries))
				])
		])
	]);
}

function updatePolicyFromFields() {
	policy = normalizePolicy({
		mode: policy.mode,
		auto_update: readFieldChecked('shinra-ruleset-auto-update', policy.auto_update),
		update_hour: readFieldNumber('shinra-ruleset-update-hour', policy.update_hour),
		repositories: {
			private: readFieldValue('shinra-ruleset-private-repo', policy.repositories.private),
			public: readFieldValue('shinra-ruleset-public-repo', policy.repositories.public)
		}
	});
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

function savePolicy() {
	updatePolicyFromFields();
	setStatus(_('正在保存...'), true);

	return callRulesetPolicySave(JSON.stringify(policy)).then(function(result) {
		notifyFailure(result);
		if (result && result.ok) {
			policy = normalizePolicy(dataOf(result).policy);
			setStatus(_('设置已保存。'), true);
			redraw();
		} else {
			setStatus(_('保存失败。'), false);
		}
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function syncRulesets() {
	updatePolicyFromFields();
	setStatus(_('正在保存设置并同步所需规则集...'), true);

	return callRulesetPolicySave(JSON.stringify(policy)).then(function(saveResult) {
		notifyFailure(saveResult);
		if (!saveResult || !saveResult.ok) {
			setStatus(_('保存失败。'), false);
			return saveResult;
		}

		policy = normalizePolicy(dataOf(saveResult).policy);
		return callRulesetDownloadRequired();
	}).then(function(syncResult) {
		if (!syncResult || !syncResult.ok) {
			notifyFailure(syncResult);
			setStatus(_('同步失败。'), false);
			return refreshAll();
		}

		let summary = syncResult.data && syncResult.data.summary ? syncResult.data.summary : {};
		setStatus(_('规则集同步完成：需要 %d，已更新 %d，未变化 %d，失败 %d。准备使用本地规则集时，请生成候选配置。').format(
			summary.required_count || 0,
			summary.updated_count || 0,
			summary.unchanged_count || 0,
			summary.failed_count || 0
		), summary.failed_count ? false : true);
		return refreshAll();
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function refreshAll() {
	return Promise.all([
		callRulesetPolicyGet(),
		callRulesetInventory('profile'),
		callRulesetInventory('candidate'),
		callRulesetInventory('runtime')
	]).then(function(results) {
		for (let i = 0; i < results.length; i++)
			notifyFailure(results[i]);

		policy = normalizePolicy(dataOf(results[0]).policy);
		inventories.profile = dataOf(results[1]);
		inventories.candidate = dataOf(results[2]);
		inventories.runtime = dataOf(results[3]);
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
		E('h2', {}, _('规则集')),
		E('p', {}, _('管理 main-profile.json 所需的规则集模式和本地资源。')),
		modeSettings(),
		remoteModeActions(),
		localSyncSettings(),
		rulesetList()
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			callRulesetPolicyGet(),
			callRulesetInventory('profile'),
			callRulesetInventory('candidate'),
			callRulesetInventory('runtime')
		]);
	},

	render: function(results) {
		const policyResult = results && results[0] ? results[0] : {};
		const profileResult = results && results[1] ? results[1] : {};
		const candidateResult = results && results[2] ? results[2] : {};
		const runtimeResult = results && results[3] ? results[3] : {};

		notifyFailure(policyResult);
		notifyFailure(profileResult);
		notifyFailure(candidateResult);
		notifyFailure(runtimeResult);

		policy = normalizePolicy(dataOf(policyResult).policy);
		inventories.profile = dataOf(profileResult);
		inventories.candidate = dataOf(candidateResult);
		inventories.runtime = dataOf(runtimeResult);

		return renderPage();
	}
});
