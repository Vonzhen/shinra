'use strict';
'require view';
'require rpc';
'require shinra.time as shinraTime';
'require shinra.ui as shinraUi';
'require shinra.motion as shinraMotion';

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
	params: [ 'run_id' ],
	expect: { '': {} }
});

const callRulesetDownloadOneStart = rpc.declare({
	object: 'shinra',
	method: 'ruleset_download_one_start',
	params: [ 'tag' ],
	expect: { '': {} }
});

const callRulesetDownloadOneStatus = rpc.declare({
	object: 'shinra',
	method: 'ruleset_download_one_status',
	params: [ 'run_id' ],
	expect: { '': {} }
});

const callRulesetArtifactStatus = rpc.declare({
	object: 'shinra',
	method: 'ruleset_artifact_status',
	expect: { '': {} }
});

const DEFAULT_POLICY = {
	mode: 'remote',
	auto_update: false,
	auto_apply_after_update: false,
	update_hour: 4,
	fetch_strategy: 'direct',
	repositories: {
		private: 'https://testingcf.jsdelivr.net/gh/miozen/sing-box-rulesets@master/rules',
		public: 'https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing'
	}
};

let policy = null;
let inventories = {
	profile: null,
	candidate: null,
	required: null
};
let artifactStatus = {};
let actionStatus = '';
let actionStatusOk = true;
let actionToken = 0;
let downloadingTag = '';
let rulesetListOpen = false;
let syncingRunId = '';
let downloadingRunId = '';

function dataOf(result) {
	if (result && result.ok && result.data)
		return result.data;
	return {};
}

function taskMetaOf(result) {
	const data = dataOf(result);
	return data.task_meta && typeof data.task_meta === 'object' ? data.task_meta : {};
}

function taskDisplayName(result, fallback) {
	const meta = taskMetaOf(result);
	return meta.display_name || fallback || _('后台任务');
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
		auto_apply_after_update: input.auto_apply_after_update === true,
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
	return 'border: 1px solid #dfe3e8; border-radius: 8px; padding: .75rem 1rem; margin: 0 0 .75rem; background: #fff;';
}

function mutedStyle() {
	return 'color: #667; line-height: 1.35; overflow-wrap: anywhere;';
}

function pageHeader(title, description) {
	return E('div', { 'style': sectionStyle() }, [
		E('h2', { 'style': 'margin: 0 0 .35rem; line-height: 1.25;' }, title),
		E('p', { 'style': mutedStyle() + ' margin: 0;' }, description)
	]);
}

function sectionTitle(title) {
	return E('h3', { 'style': 'margin: 0 0 .45rem; line-height: 1.25;' }, title);
}

function sectionDescription(text) {
	return E('div', { 'style': mutedStyle() + ' margin: 0 0 .6rem;' }, text);
}

function fieldLabel(text) {
	return E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin: 0 0 .25rem; line-height: 1.25;' }, text);
}

function setStatus(text, ok) {
	actionStatus = text || '';
	actionStatusOk = ok !== false;
	shinraUi.paintStatus('shinra-ruleset-action-status', actionStatus, actionStatusOk ? 'ok' : 'error');
}

function inlineActionStatus() {
	return shinraUi.statusBox('shinra-ruleset-action-status', actionStatus, actionStatusOk ? 'ok' : 'error', {
		margin: '.75rem 0 0'
	});
}

function notifyFailure(result) {
	if (!result || result.ok)
		return;
	setStatus('%s: %s'.format(result.message || result.code || _('未知错误'), result.detail || result.code || _('无详细信息')), false);
}

function delay(ms) {
	return new Promise(function(resolve) {
		window.setTimeout(resolve, ms);
	});
}

function rulesetTaskFrom(result) {
	const data = dataOf(result);
	return data.task && typeof data.task === 'object' ? data.task : {};
}

function rulesetTaskCounts(task) {
	const completed = Number(task.completed_count || 0);
	const meta = task.meta && typeof task.meta === 'object' ? task.meta : {};
	let text = _('进度 %d / %d，已更新 %d，未变化 %d，失败 %d').format(
		completed,
		Number(task.total_count || 0),
		Number(task.updated_count || 0),
		Number(task.unchanged_count || 0),
		Number(task.failed_count || 0)
	);
	const checked = Number(task.checked_count || 0);
	if (checked)
		text += _('；完整比对 %d').format(checked);
	if (task.current_item)
		text += _('；当前 %s').format(task.current_item);
	if (meta.current_url_redacted)
		text += _('；来源 %s').format(meta.current_url_redacted);
	if (task.last_error)
		text += _('；最近错误 %s').format(task.last_error);
	return text;
}

function rulesetTaskStatusText(task, taskName) {
	const status = task.status || '-';
	const counts = rulesetTaskCounts(task);
	const message = task.message || '';
	taskName = taskName || _('规则集同步任务');

	if (status === 'starting')
		return _('%s已排队。').format(taskName);
	if (status === 'running')
		return _('%s正在运行：%s').format(taskName, counts);
	if (status === 'success')
		return _('%s完成：%s%s').format(taskName, counts, message ? ' - ' + message : '');
	if (status === 'partial')
		return _('%s部分完成：%s%s').format(taskName, counts, message ? ' - ' + message : '');
	if (status === 'failed')
		return _('%s失败：%s').format(taskName, message || counts);

	return message || _('未观测到%s状态。').format(taskName);
}

function rulesetDownloadOneStatusText(task, taskName) {
	const meta = task.meta && typeof task.meta === 'object' ? task.meta : {};
	const tag = task.current_item || meta.tag || downloadingTag || '-';
	const status = task.status || '-';
	taskName = taskName || _('单个规则集下载任务');

	if (status === 'starting')
		return _('%s已排队：%s。').format(taskName, tag);
	if (status === 'running')
		return _('%s正在运行：%s。').format(taskName, tag);
	if (status === 'success')
		return _('%s完成：%s。').format(taskName, tag);
	if (status === 'failed')
		return _('%s失败：%s，%s').format(taskName, tag, task.last_error || task.message || '-');

	return task.message || _('未观测到%s状态。').format(taskName);
}

function updatePolicyFromFields() {
	policy = normalizePolicy({
		mode: readFieldValue('shinra-ruleset-mode', policy.mode),
		auto_update: readFieldChecked('shinra-ruleset-auto-update', policy.auto_update),
		auto_apply_after_update: readFieldChecked('shinra-ruleset-auto-apply-after-update', policy.auto_apply_after_update),
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
		_('本地模式会在生成候选配置时把规则集改写到 /etc/shinra/rules。缺失本地文件会阻止候选配置生成。') :
		_('远程模式保留 main-profile.json 中的 rule_set 声明，不要求本地规则集文件。');
}

function modeSettings() {
	return E('div', { 'style': sectionStyle() }, [
		sectionTitle(_('模式设置')),
		E('div', { 'style': 'display: flex; gap: .65rem; align-items: flex-end; flex-wrap: wrap; margin-bottom: .65rem;' }, [
			E('label', { 'style': 'min-width: 220px;' }, [
				fieldLabel(_('规则集模式')),
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
					E('option', { 'value': 'remote', 'selected': policy.mode === 'remote' ? 'selected' : null }, _('远程模式')),
					E('option', { 'value': 'local', 'selected': policy.mode === 'local' ? 'selected' : null }, _('本地模式'))
				])
			]),
			E('button', { 'type': 'button', 'class': shinraMotion.buttonClass('btn cbi-button cbi-button-save'), 'click': function(ev) { ev.preventDefault(); return savePolicy(); } }, _('保存设置')),
			policy.mode === 'local' ? E('button', { 'type': 'button', 'class': shinraMotion.buttonClass('btn cbi-button cbi-button-apply'), 'click': function(ev) { ev.preventDefault(); return syncRulesets(); } }, _('同步所需规则集')) : ''
		]),
		E('div', { 'style': mutedStyle() }, modeHelpText()),
		inlineActionStatus()
	]);
}

function localSyncSettings() {
	if (policy.mode !== 'local')
		return E('div', { 'style': 'display: none;' }, '');

	return E('div', { 'style': sectionStyle() }, [
		sectionTitle(_('本地同步设置')),
		E('h4', { 'style': 'margin: .25rem 0 .65rem;' }, _('规则集来源')),
		E('div', { 'style': 'display: grid; grid-template-columns: minmax(0, 1fr); gap: .6rem; margin-bottom: .75rem;' }, [
			E('label', {}, [
				fieldLabel(_('私有仓库')),
				E('input', {
					'id': 'shinra-ruleset-private-repo',
					'class': 'cbi-input-text',
					'style': 'width: 100%; box-sizing: border-box;',
					'placeholder': _('可选的私有仓库地址'),
					'value': policy.repositories.private
				})
			]),
			E('label', {}, [
				fieldLabel(_('公共仓库')),
				E('input', {
					'id': 'shinra-ruleset-public-repo',
					'class': 'cbi-input-text',
					'style': 'width: 100%; box-sizing: border-box;',
					'value': policy.repositories.public
				})
			])
		]),
		E('h4', { 'style': 'margin: .25rem 0 .65rem;' }, _('同步方式')),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: .6rem; margin-bottom: .65rem; align-items: start;' }, [
			E('label', {}, [
				fieldLabel(_('下载策略')),
				E('select', { 'id': 'shinra-ruleset-fetch-strategy', 'class': 'cbi-input-select', 'style': 'width: 100%;' }, [
					E('option', { 'value': 'direct', 'selected': policy.fetch_strategy === 'direct' ? 'selected' : null }, _('直连')),
					E('option', { 'value': 'proxy', 'selected': policy.fetch_strategy === 'proxy' ? 'selected' : null }, _('代理'))
				])
			]),
			E('div', { 'style': 'display: flex; gap: .65rem; align-items: flex-end; flex-wrap: wrap;' }, [
				E('label', { 'style': 'display: flex; gap: .5rem; align-items: center; min-height: 32px; margin-bottom: .15rem;' }, [
					shinraUi.checkboxInput({
						'id': 'shinra-ruleset-auto-update',
						'checked': policy.auto_update ? 'checked' : null,
						'change': function(ev) {
							const checked = !!ev.target.checked;
							updatePolicyFromFields();
							policy.auto_update = checked;
							shinraUi.defer(redraw);
						}
					}),
					E('span', {}, _('每日自动同步'))
				]),
				policy.auto_update ? E('label', { 'style': 'min-width: 130px; max-width: 160px;' }, [
					fieldLabel(_('每日同步时间')),
					E('input', {
						'id': 'shinra-ruleset-update-hour',
						'class': 'cbi-input-text',
						'type': 'number',
						'min': '0',
						'max': '23',
						'value': String(policy.update_hour),
						'style': 'width: 100%; box-sizing: border-box;'
					})
				]) : '',
				policy.auto_update ? E('label', { 'style': 'display: flex; gap: .5rem; align-items: center; min-height: 32px; margin-bottom: .15rem;' }, [
					shinraUi.checkboxInput({
						'id': 'shinra-ruleset-auto-apply-after-update',
						'checked': policy.auto_apply_after_update ? 'checked' : null,
						'change': function(ev) {
							const checked = !!ev.target.checked;
							updatePolicyFromFields();
							policy.auto_apply_after_update = checked;
							shinraUi.defer(redraw);
						}
					}),
					E('span', {}, _('更新后自动应用（实验）'))
				]) : ''
			])
		]),
		E('div', { 'style': mutedStyle() }, _('下载顺序：私有仓库优先，公共仓库兜底，最后使用模板中的原始地址。'))
	]);
}

function artifactStatusData() {
	return artifactStatus && typeof artifactStatus === 'object' && !Array.isArray(artifactStatus) ? artifactStatus : {};
}

function artifactNotice(state) {
	if (state.pending)
		return E('div', {
			'style': 'border: 1px solid #f59e0b; border-radius: 8px; padding: .75rem; background: #fffbeb; color: #92400e; margin-top: .75rem;'
		}, _('规则集已更新，等待下一次配置应用成功后确认为可运行版本。如果应用失败，Shinra 会自动恢复上一组已确认规则集。'));

	if (!state.last_good_exists || Number(state.last_good_count || 0) <= 0)
		return E('div', {
			'style': 'border: 1px solid #bfdbfe; border-radius: 8px; padding: .75rem; background: #eff6ff; color: #1e40af; margin-top: .75rem;'
		}, _('尚未建立已确认规则集基线。首次成功应用本地规则集后会建立。'));

	return E('div', {
		'style': 'border: 1px solid #bbf7d0; border-radius: 8px; padding: .75rem; background: #f0fdf4; color: #166534; margin-top: .75rem;'
	}, _('本地规则集已有已确认可运行版本。'));
}

function artifactStatusPanel() {
	if (policy.mode !== 'local')
		return E('div', { 'style': 'display: none;' }, '');

	const state = artifactStatusData();
	const changed = Number(state.changed_count || 0);
	const lastGoodCount = Number(state.last_good_count || 0);

	return E('div', { 'style': sectionStyle() }, [
		sectionTitle(_('本地规则集保护')),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: .65rem;' }, [
			shinraUi.statCard(_('等待运行验证'), state.pending ? _('是') : _('否'), { 'class': shinraMotion.cardClass(), valueStyle: 'font-size: 22px;' }),
			shinraUi.statCard(_('待验证文件'), changed, { 'class': shinraMotion.cardClass(), valueStyle: 'font-size: 22px;' }),
			shinraUi.statCard(_('已确认文件'), lastGoodCount, { 'class': shinraMotion.cardClass(), valueStyle: 'font-size: 22px;' }),
			shinraUi.statCard(_('事务状态'), state.pending_status || '-', { 'class': shinraMotion.cardClass(), valueStyle: 'font-size: 22px;' })
		]),
		artifactNotice(state),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: .65rem; margin-top: .75rem; color: #667; overflow-wrap: anywhere;' }, [
			E('div', {}, [
				E('strong', {}, _('Last-good 目录')),
				E('div', {}, valueText(state.last_good_dir))
			]),
			E('div', {}, [
				E('strong', {}, _('Pending 文件')),
				E('div', {}, valueText(state.pending_path))
			]),
			E('div', {}, [
				E('strong', {}, _('更新时间')),
				E('div', {}, shinraTime.formatMaybeTime(state.pending_updated_at || state.last_good_mtime))
			])
		])
	]);
}

function timeText(value) {
	if (!value)
		return '-';
	return valueText(value);
}

function requiredInventory() {
	return inventories.required && typeof inventories.required === 'object' ? inventories.required : {};
}

function rulesetStatus(entry) {
	if (!entry || entry.status === 'missing')
		return shinraUi.pill(_('缺失'), 'error');
	if (entry.status === 'extra')
		return shinraUi.pill(_('未使用'), 'warning');
	return shinraUi.pill(_('已就绪'), 'ok');
}

function sourceText(entry) {
	const urls = entry && Array.isArray(entry.candidate_url_redacted) ? entry.candidate_url_redacted : [];
	if (urls.length)
		return urls.join('\n');
	return valueText(entry && (entry.source_url_redacted || entry.source_url));
}

function templateRequiredText(entry) {
	return entry && entry.required === false ? _('否') : _('是');
}

function pendingRulesetTags() {
	const state = artifactStatusData();
	const files = Array.isArray(state.changed_files) ? state.changed_files : [];
	let tags = {};

	for (let item of files) {
		if (item && item.tag)
			tags[item.tag] = true;
	}

	return tags;
}

function isPendingRuleset(tag) {
	const state = artifactStatusData();
	if (!state.pending)
		return false;
	return pendingRulesetTags()[tag] == true;
}

function rowStatus(entry) {
	if (entry && isPendingRuleset(entry.tag))
		return shinraUi.pill(_('待验证'), 'warning');
	return rulesetStatus(entry);
}

function rulesetItems(inv) {
	const entries = Array.isArray(inv.entries) ? inv.entries : [];
	const extras = Array.isArray(inv.extras) ? inv.extras : [];
	let items = [];

	for (let entry of entries)
		items.push(entry);
	for (let entry of extras)
		items.push(entry);

	return items;
}

function rulesetRows(items) {
	if (!items.length)
		return [ E('div', { 'style': 'padding: .8rem; color: #667; text-align: center;' }, _('没有观测到规则集。')) ];

	return items.map(function(entry) {
		const required = !(entry && entry.required === false);
		const busy = downloadingTag && entry && entry.tag === downloadingTag;
		return E('div', { 'class': shinraMotion.softRowClass(), 'style': 'display: grid; grid-template-columns: minmax(150px, 1.1fr) 92px 84px minmax(220px, 1.7fr) 86px 120px minmax(220px, 1.8fr) 98px; gap: .75rem; padding: .5rem 0; border-bottom: 1px solid #eee; align-items: center;' }, [
			E('div', { 'style': 'overflow-wrap: anywhere; font-weight: 600;' }, valueText(entry && entry.tag)),
			E('div', {}, rowStatus(entry)),
			E('div', { 'style': 'color: #667;' }, templateRequiredText(entry)),
			E('div', { 'style': 'overflow-wrap: anywhere; color: #667;' }, valueText(entry && entry.local_path)),
			E('div', { 'style': 'color: #667; text-align: right;' }, bytesText(Number(entry && entry.local_size || 0))),
			E('div', { 'style': 'color: #667; text-align: right;' }, timeText(entry && entry.local_mtime)),
			E('div', { 'style': 'overflow-wrap: anywhere; white-space: pre-line; color: #667;' }, sourceText(entry)),
			E('div', {}, required ? E('button', {
				'type': 'button',
				'class': shinraMotion.buttonClass('btn cbi-button'),
				'disabled': busy ? 'disabled' : null,
				'click': function(ev) {
					ev.preventDefault();
					return downloadOneRuleset(entry.tag);
				}
			}, busy ? _('下载中') : entry.status === 'missing' ? _('下载') : _('重新下载')) : '-')
		]);
	});
}

function rulesetListContent(items) {
	return E('div', { 'style': 'overflow-x: auto; margin-top: .75rem;' }, [
		E('div', { 'style': 'min-width: 1260px;' }, [
			E('div', { 'style': 'display: grid; grid-template-columns: minmax(150px, 1.1fr) 92px 84px minmax(220px, 1.7fr) 86px 120px minmax(220px, 1.8fr) 98px; gap: .75rem; color: #667; font-size: 12px; padding-bottom: .4rem; border-bottom: 1px solid #ddd;' }, [
				E('div', {}, _('标签')),
				E('div', {}, _('状态')),
				E('div', {}, _('模板需要')),
				E('div', {}, _('本地文件')),
				E('div', { 'style': 'text-align: right;' }, _('大小')),
				E('div', { 'style': 'text-align: right;' }, _('修改时间')),
				E('div', {}, _('下载来源')),
				E('div', {}, _('操作'))
			]),
			E('div', {}, rulesetRows(items))
		])
	]);
}

function rulesetList() {
	const inv = requiredInventory();
	const items = rulesetItems(inv);
	const summary = inv.summary || {};
	const artifact = artifactStatusData();
	let suffix = '';
	if (artifact.pending)
		suffix = _('，待运行验证 %d').format(Number(artifact.changed_count || 0));
	else if (Number(artifact.last_good_count || 0) > 0)
		suffix = _('，已确认基线 %d').format(Number(artifact.last_good_count || 0));
	const subtitle = _('需要 %d，已就绪 %d，缺失 %d，未使用 %d%s').format(
		summary.required_count || 0,
		summary.ready_count || 0,
		summary.missing_count || 0,
		summary.local_extra_count || 0,
		suffix
	);

	return E('details', {
		'open': rulesetListOpen ? 'open' : null,
		'toggle': function(ev) {
			rulesetListOpen = !!ev.target.open;
		},
		'style': sectionStyle()
	}, [
		E('summary', { 'style': 'cursor: pointer; list-style-position: inside;' }, [
			E('span', { 'style': 'font-weight: 700;' }, _('规则集列表')),
			E('span', { 'style': 'display: block; color: #667; font-size: 12px; margin-top: .25rem;' }, subtitle)
		]),
		E('div', { 'style': 'color: #667; margin-top: .75rem; overflow-wrap: anywhere;' },
			_('以列表形式展示 main-profile.json 引用的规则集和 /etc/shinra/rules 本地文件状态。')),
		rulesetListContent(items)
	]);
}

function savePolicy() {
	const token = ++actionToken;
	updatePolicyFromFields();
	setStatus(_('正在保存设置...'), true);

	return callRulesetPolicySave(JSON.stringify(policy)).then(function(result) {
		if (token !== actionToken)
			return result;
		notifyFailure(result);
		if (result && result.ok) {
			policy = normalizePolicy(dataOf(result).policy);
			setStatus(_('规则集设置已保存。'), true);
			redraw();
		} else {
			setStatus(_('保存失败。'), false);
		}
		return result;
	}).catch(function(error) {
		if (token !== actionToken)
			return;
		setStatus(error.message || String(error), false);
	});
}

function taskStale(task) {
	const updatedAt = task && task.updated_at ? Date.parse(task.updated_at) : NaN;
	return Number.isFinite(updatedAt) && Date.now() - updatedAt > 120000;
}

function pollRulesetSync(token, runId, attempt) {
	return callRulesetDownloadRequiredStatus(runId).then(function(statusResult) {
		if (token !== actionToken)
			return statusResult;
		notifyFailure(statusResult);
		if (!statusResult || !statusResult.ok) {
			setStatus(_('读取规则集同步任务状态失败。'), false);
			return refreshAll();
		}

		const task = rulesetTaskFrom(statusResult);
		const taskName = taskDisplayName(statusResult, _('规则集同步任务'));
		const status = task.status || '';
		if (!(dataOf(statusResult).matches_run)) {
			syncingRunId = '';
			setStatus(_('规则集同步任务已被其他操作替换。'), false);
			return refreshAll();
		}

		if (status === 'starting' || status === 'running') {
			setStatus(taskStale(task) ? _('规则集同步超过两分钟没有更新，仍在等待后台恢复。') : rulesetTaskStatusText(task, taskName), !taskStale(task));
			return delay(taskStale(task) ? 5000 : 2000).then(function() {
				return pollRulesetSync(token, runId, attempt + 1);
			});
		}

		const ok = status === 'success' || status === 'partial';
		syncingRunId = '';
		setStatus(rulesetTaskStatusText(task, taskName), ok && Number(task.failed_count || 0) === 0);
		return refreshAll();
	}).catch(function(error) {
		if (token !== actionToken)
			return;
		setStatus(error.message || String(error), false);
		return refreshAll();
	});
}

function pollRulesetDownloadOne(token, runId, attempt) {
	return callRulesetDownloadOneStatus(runId).then(function(statusResult) {
		if (token !== actionToken)
			return statusResult;
		notifyFailure(statusResult);
		if (!statusResult || !statusResult.ok) {
			setStatus(_('读取单个规则集下载任务状态失败。'), false);
			downloadingTag = '';
			return refreshAll();
		}

		const task = rulesetTaskFrom(statusResult);
		const taskName = taskDisplayName(statusResult, _('单个规则集下载任务'));
		const status = task.status || '';
		if (!(dataOf(statusResult).matches_run)) {
			downloadingRunId = '';
			downloadingTag = '';
			setStatus(_('单个规则集下载任务已被其他操作替换。'), false);
			return refreshAll();
		}

		if (status === 'starting' || status === 'running') {
			setStatus(taskStale(task) ? _('单个规则集下载超过两分钟没有更新，仍在等待后台恢复。') : rulesetDownloadOneStatusText(task, taskName), !taskStale(task));
			return delay(taskStale(task) ? 5000 : 1500).then(function() {
				return pollRulesetDownloadOne(token, runId, attempt + 1);
			});
		}

		downloadingTag = '';
		downloadingRunId = '';
		setStatus(rulesetDownloadOneStatusText(task, taskName), status === 'success');
		return refreshAll();
	}).catch(function(error) {
		if (token !== actionToken)
			return;
		downloadingTag = '';
		setStatus(error.message || String(error), false);
		return refreshAll();
	});
}

function downloadOneRuleset(tag) {
	const token = ++actionToken;
	downloadingTag = tag || '';
	rulesetListOpen = true;
	setStatus(_('正在启动单个规则集下载任务：%s...').format(downloadingTag || '-'), true);
	redraw();

	return callRulesetDownloadOneStart(tag).then(function(startResult) {
		if (token !== actionToken)
			return startResult;
		notifyFailure(startResult);
		if (!startResult || !startResult.ok) {
			downloadingTag = '';
			setStatus(_('启动单个规则集下载任务失败。'), false);
			return refreshAll();
		}

		const task = rulesetTaskFrom(startResult);
		downloadingRunId = dataOf(startResult).run_id || (task.meta && task.meta.run_id) || '';
		if (!downloadingRunId) {
			setStatus(_('单个规则集下载任务未返回运行标识。'), false);
			return refreshAll();
		}
		setStatus(rulesetDownloadOneStatusText(task, taskDisplayName(startResult, _('单个规则集下载任务'))), true);
		return pollRulesetDownloadOne(token, downloadingRunId, 0);
	}).catch(function(error) {
		if (token !== actionToken)
			return;
		downloadingTag = '';
		setStatus(error.message || String(error), false);
		return refreshAll();
	});
}

function syncRulesets() {
	const token = ++actionToken;
	updatePolicyFromFields();
	setStatus(_('正在保存设置并启动规则集同步任务...'), true);

	return callRulesetPolicySave(JSON.stringify(policy)).then(function(saveResult) {
		if (token !== actionToken)
			return saveResult;
		notifyFailure(saveResult);
		if (!saveResult || !saveResult.ok) {
			setStatus(_('保存失败。'), false);
			return saveResult;
		}

		policy = normalizePolicy(dataOf(saveResult).policy);
		return callRulesetDownloadRequiredStart();
	}).then(function(startResult) {
		if (token !== actionToken)
			return startResult;
		notifyFailure(startResult);
		if (!startResult || !startResult.ok) {
			setStatus(_('启动规则集同步任务失败。'), false);
			return refreshAll();
		}

		const task = rulesetTaskFrom(startResult);
		syncingRunId = dataOf(startResult).run_id || (task.meta && task.meta.run_id) || '';
		if (!syncingRunId) {
			setStatus(_('规则集同步任务未返回运行标识。'), false);
			return refreshAll();
		}
		setStatus(rulesetTaskStatusText(task, taskDisplayName(startResult, _('规则集同步任务'))), true);
		return pollRulesetSync(token, syncingRunId, 0);
	}).catch(function(error) {
		if (token !== actionToken)
			return;
		setStatus(error.message || String(error), false);
	});
}

function refreshAll() {
	return Promise.all([
		callRulesetPolicyGet(),
		callRulesetRequiredInventory(),
		callRulesetArtifactStatus()
	]).then(function(results) {
		for (let i = 0; i < results.length; i++)
			notifyFailure(results[i]);

		policy = normalizePolicy(dataOf(results[0]).policy);
		inventories.required = dataOf(results[1]);
		artifactStatus = dataOf(results[2]);
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
	shinraMotion.inject();

	return E('div', { 'id': 'shinra-rulesets-root' }, [
		pageHeader('规则集', '管理 main-profile.json 所需的规则集模式和本地资源。'),
		modeSettings(),
		localSyncSettings(),
		rulesetList()
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			callRulesetPolicyGet(),
			callRulesetRequiredInventory(),
			callRulesetArtifactStatus(),
			callRulesetDownloadRequiredStatus(),
			callRulesetDownloadOneStatus()
		]);
	},

	render: function(results) {
		const policyResult = results && results[0] ? results[0] : {};
		const requiredResult = results && results[1] ? results[1] : {};
		const artifactResult = results && results[2] ? results[2] : {};
		const syncTaskResult = results && results[3] ? results[3] : {};
		const downloadTaskResult = results && results[4] ? results[4] : {};

		notifyFailure(policyResult);
		notifyFailure(requiredResult);
		notifyFailure(artifactResult);

		policy = normalizePolicy(dataOf(policyResult).policy);
		inventories.required = dataOf(requiredResult);
		artifactStatus = dataOf(artifactResult);

		const syncTask = rulesetTaskFrom(syncTaskResult);
		const downloadTask = rulesetTaskFrom(downloadTaskResult);
		const syncRunId = syncTask.meta && syncTask.meta.run_id || '';
		const downloadRunId = downloadTask.meta && downloadTask.meta.run_id || '';
		const page = renderPage();
		if ((syncTask.status === 'starting' || syncTask.status === 'running') && syncRunId) {
			syncingRunId = syncRunId;
			window.setTimeout(function() { pollRulesetSync(actionToken, syncRunId, 0); }, 0);
		}
		if ((downloadTask.status === 'starting' || downloadTask.status === 'running') && downloadRunId) {
			downloadingRunId = downloadRunId;
			downloadingTag = downloadTask.meta && downloadTask.meta.tag || '';
			window.setTimeout(function() { pollRulesetDownloadOne(actionToken, downloadRunId, 0); }, 0);
		}

		return page;
	}
});
