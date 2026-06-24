'use strict';
'require view';
'require rpc';

const callRuntimeStatus = rpc.declare({
	object: 'shinra',
	method: 'runtime_status',
	expect: { '': {} }
});

const callProfileGet = rpc.declare({
	object: 'shinra',
	method: 'profile_get',
	expect: { '': {} }
});

const callProfileSourceGet = rpc.declare({
	object: 'shinra',
	method: 'profile_source_get',
	expect: { '': {} }
});

const callSubscriptionsGet = rpc.declare({
	object: 'shinra',
	method: 'subscriptions_get',
	expect: { '': {} }
});

const callNodeSnapshotSummary = rpc.declare({
	object: 'shinra',
	method: 'node_snapshot_summary',
	expect: { '': {} }
});

const callRulesetInventory = rpc.declare({
	object: 'shinra',
	method: 'ruleset_inventory',
	expect: { '': {} }
});

const callRulesetPolicyGet = rpc.declare({
	object: 'shinra',
	method: 'ruleset_policy_get',
	expect: { '': {} }
});

const callZashboardStatus = rpc.declare({
	object: 'shinra',
	method: 'zashboard_status',
	expect: { '': {} }
});

const callNotifySettingsGet = rpc.declare({
	object: 'shinra',
	method: 'notify_settings_get',
	expect: { '': {} }
});

const callAutoTaskStatusGet = rpc.declare({
	object: 'shinra',
	method: 'auto_task_status_get',
	expect: { '': {} }
});

const callGenerate = rpc.declare({
	object: 'shinra',
	method: 'config_generate',
	expect: { '': {} }
});

const callCheck = rpc.declare({
	object: 'shinra',
	method: 'config_check_candidate',
	expect: { '': {} }
});

const callApply = rpc.declare({
	object: 'shinra',
	method: 'config_apply',
	expect: { '': {} }
});

const callStop = rpc.declare({
	object: 'shinra',
	method: 'runtime_stop',
	expect: { '': {} }
});

const callRollback = rpc.declare({
	object: 'shinra',
	method: 'config_rollback',
	expect: { '': {} }
});

let pageResults = {};
let actionStatus = '';
let actionStatusOk = true;

function dataOf(result) {
	if (result && result.ok && result.data)
		return result.data;
	return {};
}

function stateOf() {
	const data = dataOf(pageResults.runtime);
	return data.state || {};
}

function safeJson(text) {
	try {
		return JSON.parse(text || '{}');
	} catch (e) {
		return {};
	}
}

function valueText(value) {
	if (value == null || value === '')
		return '-';
	return String(value);
}

function sectionStyle() {
	return 'border: 1px solid #dfe3e8; border-radius: 8px; padding: 1rem; margin-bottom: 1rem; background: #fff;';
}

function cardStyle(accent) {
	return 'border: 1px solid #dfe3e8; border-left: 4px solid %s; border-radius: 8px; padding: .9rem; background: #fff; box-sizing: border-box; min-height: 92px;'.format(accent || '#64748b');
}

function card(title, value, detail, accent) {
	return E('div', { 'style': cardStyle(accent) }, [
		E('div', { 'style': 'font-size: 12px; color: #667; text-transform: uppercase; letter-spacing: .04em;' }, title),
		E('div', { 'style': 'font-size: 22px; font-weight: 700; margin-top: .25rem; line-height: 1.2; overflow-wrap: anywhere;' }, valueText(value)),
		E('div', { 'style': 'margin-top: .45rem; color: #667; font-size: 12px; overflow-wrap: anywhere;' }, valueText(detail))
	]);
}

function statusTone(ok, warning) {
	if (ok)
		return '#16a34a';
	if (warning)
		return '#ea580c';
	return '#dc2626';
}

function statusWord(status) {
	if (status === 'success')
		return _('\u6210\u529f');
	if (status === 'partial')
		return _('\u90e8\u5206\u6210\u529f');
	if (status === 'fail')
		return _('\u5931\u8d25');
	if (status)
		return status;
	return '-';
}

function compactMessage(text) {
	text = valueText(text);
	text = text.replace(/\n/g, ' · ');
	return text;
}

function autoJobText(job, disabledText, waitingText) {
	job = job || {};
	if (job.last_status)
		return _('%s \u4e8e %s').format(statusWord(job.last_status), job.last_run_at || '-');
	if (job.enabled)
		return waitingText || _('\u81ea\u52a8\u4efb\u52a1\u7b49\u5f85\u4e2d');
	return disabledText || _('\u81ea\u52a8\u4efb\u52a1\u5df2\u505c\u7528');
}

function actionLink(label, path, primary) {
	return E('a', {
		'class': 'btn cbi-button %s'.format(primary ? 'cbi-button-apply' : 'cbi-button-neutral'),
		'href': L.url(path),
		'style': 'margin-right: .5rem; margin-bottom: .5rem;'
	}, label);
}

function setActionStatus(text, ok) {
	actionStatus = text || '';
	actionStatusOk = ok !== false;
	const node = document.getElementById('shinra-overview-action-status');
	if (!node)
		return;

	node.textContent = actionStatus;
	node.style.display = actionStatus ? 'block' : 'none';
	node.style.borderColor = actionStatusOk ? '#bbf7d0' : '#fecaca';
	node.style.background = actionStatusOk ? '#f0fdf4' : '#fef2f2';
	node.style.color = actionStatusOk ? '#166534' : '#991b1b';
}

function resultError(result, fallback) {
	if (result && (result.message || result.code))
		return '%s: %s'.format(result.message || result.code || fallback || _('\u64cd\u4f5c\u5931\u8d25'), result.detail || result.code || _('\u65e0\u8be6\u7ec6\u4fe1\u606f'));
	return fallback || _('\u64cd\u4f5c\u5931\u8d25');
}

function pageLoadError() {
	const failures = [
		pageResults.runtime,
		pageResults.profile,
		pageResults.subscriptions,
		pageResults.snapshot,
		pageResults.rules,
		pageResults.panel,
		pageResults.profileSource,
		pageResults.rulesPolicy,
		pageResults.notify,
		pageResults.autoTask
	].filter(function(result) {
		return result && !result.ok;
	});

	if (!failures.length)
		return '';

	return failures.map(function(result) {
		return resultError(result, _('\u52a0\u8f7d\u5931\u8d25'));
	}).join(' | ');
}

function runAction(label, rpcCall, confirmText) {
	if (confirmText && !window.confirm(confirmText))
		return Promise.resolve();

	setActionStatus(_('%s \u6b63\u5728\u6267\u884c...').format(label), true);

	return rpcCall().then(function(result) {
		if (result && result.ok) {
			setActionStatus(_('%s \u5df2\u5b8c\u6210\u3002').format(label), true);
			return refreshPage();
		}
		setActionStatus(resultError(result, _('%s \u5931\u8d25').format(label)), false);
		return result;
	}).catch(function(error) {
		setActionStatus(error.message || String(error), false);
	});
}

function refreshPage() {
	return loadAll().then(function(results) {
		pageResults = results;
		redraw();
		return results;
	});
}

function loadAll() {
	return Promise.all([
		callRuntimeStatus().catch(function(e) { return { ok: false, message: _('Runtime \u72b6\u6001\u52a0\u8f7d\u5931\u8d25'), detail: e.message || String(e) }; }),
		callProfileGet().catch(function(e) { return { ok: false, message: _('\u6a21\u677f\u52a0\u8f7d\u5931\u8d25'), detail: e.message || String(e) }; }),
		callSubscriptionsGet().catch(function(e) { return { ok: false, message: _('\u8ba2\u9605\u52a0\u8f7d\u5931\u8d25'), detail: e.message || String(e) }; }),
		callNodeSnapshotSummary().catch(function(e) { return { ok: false, message: _('\u8282\u70b9\u5feb\u7167\u6458\u8981\u52a0\u8f7d\u5931\u8d25'), detail: e.message || String(e) }; }),
		callRulesetInventory().catch(function(e) { return { ok: false, message: _('\u89c4\u5219\u96c6\u6e05\u5355\u52a0\u8f7d\u5931\u8d25'), detail: e.message || String(e) }; }),
		callZashboardStatus().catch(function(e) { return { ok: false, message: _('\u9762\u677f\u72b6\u6001\u52a0\u8f7d\u5931\u8d25'), detail: e.message || String(e) }; }),
		callProfileSourceGet().catch(function(e) { return { ok: false, message: _('\u6a21\u677f\u6e90\u52a0\u8f7d\u5931\u8d25'), detail: e.message || String(e) }; }),
		callRulesetPolicyGet().catch(function(e) { return { ok: false, message: _('\u89c4\u5219\u96c6\u7b56\u7565\u52a0\u8f7d\u5931\u8d25'), detail: e.message || String(e) }; }),
		callNotifySettingsGet().catch(function(e) { return { ok: false, message: _('\u901a\u77e5\u8bbe\u7f6e\u52a0\u8f7d\u5931\u8d25'), detail: e.message || String(e) }; }),
		callAutoTaskStatusGet().catch(function(e) { return { ok: false, message: _('\u81ea\u52a8\u4efb\u52a1\u72b6\u6001\u52a0\u8f7d\u5931\u8d25'), detail: e.message || String(e) }; })
	]).then(function(results) {
		return {
			runtime: results[0],
			profile: results[1],
			subscriptions: results[2],
			snapshot: results[3],
			rules: results[4],
			panel: results[5],
			profileSource: results[6],
			rulesPolicy: results[7],
			notify: results[8],
			autoTask: results[9]
		};
	});
}

function runtimeCards() {
	const state = stateOf();
	const running = !!state.sing_box_running;
	const tun = !!state.tun_exists;
	const clash = !!state.clash_api_available;
	const config = !!state.runtime_config_exists;

	return E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: .75rem; margin-bottom: 1rem;' }, [
		card(_('\u8fd0\u884c\u65f6'), running ? _('\u8fd0\u884c\u4e2d') : _('\u5df2\u505c\u6b62'), running ? _('sing-box \u670d\u52a1\u8fd0\u884c\u4e2d') : _('\u670d\u52a1\u5df2\u505c\u6b62'), statusTone(running)),
		card(_('TUN'), tun ? _('\u5b58\u5728') : _('\u7f3a\u5931'), state.tun_name || '-', statusTone(tun, running)),
		card(_('Clash API'), clash ? _('\u53ef\u7528') : _('\u4e0d\u53ef\u7528'), clash ? _('\u9762\u677f\u53ef\u8fde\u63a5') : _('\u9762\u677f\u4e0d\u53ef\u7528'), statusTone(clash, running)),
		card(_('\u914d\u7f6e'), config ? _('\u5c31\u7eea') : _('\u7f3a\u5931'), state.runtime_config_hash ? _('\u5df2\u89c2\u6d4b\u5230\u8fd0\u884c\u914d\u7f6e\u54c8\u5e0c') : _('\u8fd0\u884c\u914d\u7f6e\u7f3a\u5931'), statusTone(config))
	]);
}

function resourceCards() {
	const profile = dataOf(pageResults.profile);
	const subscriptions = safeJson(dataOf(pageResults.subscriptions).content || '{}');
	const snapshot = dataOf(pageResults.snapshot);
	const rules = dataOf(pageResults.rules).summary || {};
	const panel = dataOf(pageResults.panel);
	const panelSource = panel.source || {};
	const panelInstalled = panelSource.installed || {};
	const panelLastCheck = panelSource.last_check || {};
	const profileSource = dataOf(pageResults.profileSource).source || {};
	const rulesPolicy = dataOf(pageResults.rulesPolicy).policy || {};
	const notifyData = dataOf(pageResults.notify);
	const notifySettings = notifyData.settings || {};
	const notifyTelegram = notifySettings.telegram || {};
	const notifyState = notifyData.state || {};
	const autoTask = dataOf(pageResults.autoTask).state || {};
	const jobs = autoTask.jobs || {};
	const subJob = jobs.subscriptions_refresh_auto || {};
	const rulesJob = jobs.ruleset_download_required_auto || {};
	const sourceCount = Array.isArray(subscriptions.sources) ? subscriptions.sources.length : 0;
	const nodeCount = Number(snapshot.node_count || 0);
	const missingRules = Number(rules.missing_count || 0) + Number(rules.missing_reference_count || 0) + Number(rules.invalid_count || 0);
	const requiredRules = Number(rules.declared_count || 0);
	const profileOk = pageResults.profile && pageResults.profile.ok && profile.valid !== false;
	const profileSyncTime = profileSource.updated_at || _('\u672a\u8bb0\u5f55');
	const profileSourceText = profileSource.url ? _('\u5df2\u914d\u7f6e\u8fdc\u7a0b\u6e90') : _('\u672a\u914d\u7f6e\u8fdc\u7a0b\u6e90');
	const snapshotTime = snapshot.updated_at || _('\u672a\u5237\u65b0');
	const subAutoText = autoJobText(subJob, _('\u81ea\u52a8\u5237\u65b0\u5df2\u505c\u7528'), _('\u7b49\u5f85\u81ea\u52a8\u5237\u65b0'));
	const rulesTime = rulesJob.last_run_at || _('\u672a\u540c\u6b65');
	const rulesResultText = rulesJob.last_message ? compactMessage(rulesJob.last_message) : autoJobText(rulesJob, _('\u81ea\u52a8\u540c\u6b65\u5df2\u505c\u7528'), _('\u7b49\u5f85\u81ea\u52a8\u540c\u6b65'));
	const rulesMode = rulesPolicy.mode || '-';
	const panelUpdated = panelInstalled.updated_at || (panel.index_mtime ? _('mtime %s').format(panel.index_mtime) : _('\u672a\u66f4\u65b0'));
	const panelVersion = panelInstalled.version || panelLastCheck.version || (panel.installed ? _('\u672a\u8bb0\u5f55\u7248\u672c') : _('\u8bf7\u5b89\u88c5\u9762\u677f\u8d44\u6e90'));
	const notifyEnabled = notifyTelegram.enabled == true;
	const notifyStatus = notifyState.last_status || (notifyEnabled ? _('\u7b49\u5f85\u4e2d') : _('\u5df2\u505c\u7528'));
	const notifyResult = notifyState.last_attempt_at ? _('%s \u4e8e %s').format(notifyState.last_sent ? _('\u5df2\u53d1\u9001') : _('\u672a\u53d1\u9001'), notifyState.last_attempt_at) : (notifyEnabled ? _('\u672a\u8bb0\u5f55\u53d1\u9001\u5c1d\u8bd5') : _('Telegram \u5df2\u505c\u7528'));
	let notifyAccent = '#64748b';
	if (notifyEnabled)
		notifyAccent = statusTone(notifyState.last_sent == true, !notifyState.last_attempt_at);

	return E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: .75rem; margin-bottom: 1rem;' }, [
		card(_('\u6a21\u677f'), profileOk ? _('\u5c31\u7eea') : _('\u9519\u8bef'), _('\u4e0a\u6b21\u540c\u6b65\uff1a%s | %s').format(profileSyncTime, profileSourceText), statusTone(profileOk)),
		card(_('\u8ba2\u9605'), nodeCount ? _('%d \u4e2a\u8282\u70b9').format(nodeCount) : _('\u65e0\u8282\u70b9'), _('\u4e0a\u6b21\u5237\u65b0\uff1a%s | %s').format(snapshotTime, subAutoText), statusTone(sourceCount > 0 && nodeCount > 0, sourceCount > 0)),
		card(_('\u89c4\u5219\u96c6'), missingRules === 0 ? _('\u5c31\u7eea') : _('\u9700\u8981\u5904\u7406'), _('\u4e0a\u6b21\u540c\u6b65\uff1a%s | \u9700\u8981 %d / \u7f3a\u5931 %d | %s | %s').format(rulesTime, requiredRules, missingRules, rulesMode, rulesResultText), statusTone(missingRules === 0, requiredRules > 0)),
		card(_('\u9762\u677f'), panel.installed ? _('\u5df2\u5b89\u88c5') : _('\u7f3a\u5931'), _('\u4e0a\u6b21\u66f4\u65b0\uff1a%s | %s').format(panelUpdated, panelVersion), statusTone(panel.installed)),
		card(_('Telegram'), notifyEnabled ? _('\u5df2\u542f\u7528') : _('\u5df2\u505c\u7528'), _('\u6700\u8fd1\u7ed3\u679c\uff1a%s | %s').format(notifyStatus, notifyResult), notifyAccent)
	]);
}

function operationButtons() {
	return E('div', { 'style': sectionStyle() }, [
		E('h3', { 'style': 'margin-top: 0;' }, _('\u8fd0\u884c\u65f6\u64cd\u4f5c')),
		E('div', { 'style': 'color: #667; margin-bottom: .75rem;' }, _('\u8d44\u6e90\u51c6\u5907\u5b8c\u6210\u540e\uff0c\u5728\u8fd9\u91cc\u6267\u884c\u751f\u6210\u3001\u68c0\u67e5\u3001\u5e94\u7528\u548c\u56de\u6eda\u3002\u7b56\u7565\u7ec4\u5207\u6362\u548c\u5ef6\u8fdf\u6d4b\u901f\u4ea4\u7ed9 Zashboard\u3002')),
		E('div', {
			'id': 'shinra-overview-action-status',
			'style': 'display: %s; border: 1px solid %s; border-radius: 8px; padding: .75rem; margin-bottom: .75rem; background: %s; color: %s;'.format(
				actionStatus ? 'block' : 'none',
				actionStatusOk ? '#bbf7d0' : '#fecaca',
				actionStatusOk ? '#f0fdf4' : '#fef2f2',
				actionStatusOk ? '#166534' : '#991b1b'
			)
		}, actionStatus),
		E('div', { 'style': 'display: flex; flex-wrap: wrap; gap: .5rem;' }, [
			E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function(ev) { ev.preventDefault(); return runAction(_('\u751f\u6210\u5019\u9009\u914d\u7f6e'), callGenerate); } }, _('\u751f\u6210\u5019\u9009\u914d\u7f6e')),
			E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function(ev) { ev.preventDefault(); return runAction(_('\u68c0\u67e5\u5019\u9009\u914d\u7f6e'), callCheck); } }, _('\u68c0\u67e5\u5019\u9009\u914d\u7f6e')),
			E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': function(ev) { ev.preventDefault(); return runAction(_('\u5e94\u7528\u8fd0\u884c\u914d\u7f6e'), callApply, _('\u73b0\u5728\u5c06\u5019\u9009\u914d\u7f6e\u5e94\u7528\u5230\u8fd0\u884c\u65f6\u5417\uff1f')); } }, _('\u5e94\u7528\u8fd0\u884c\u914d\u7f6e')),
			E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': function(ev) { ev.preventDefault(); return runAction(_('\u505c\u6b62\u8fd0\u884c\u65f6'), callStop, _('\u73b0\u5728\u505c\u6b62 Shinra \u8fd0\u884c\u65f6\u5417\uff1f\u6d41\u91cf\u5c06\u4e0d\u518d\u7531 sing-box \u63a5\u7ba1\u3002')); } }, _('\u505c\u6b62\u8fd0\u884c\u65f6')),
			E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': function(ev) { ev.preventDefault(); return runAction(_('\u56de\u6eda\u8fd0\u884c\u914d\u7f6e'), callRollback, _('\u73b0\u5728\u56de\u6eda\u8fd0\u884c\u914d\u7f6e\u5417\uff1f')); } }, _('\u56de\u6eda\u8fd0\u884c\u914d\u7f6e'))
		])
	]);
}

function entryLinks() {
	return E('div', { 'style': sectionStyle() }, [
		E('h3', { 'style': 'margin-top: 0;' }, _('\u5feb\u6377\u5165\u53e3')),
		E('div', { 'style': 'display: flex; flex-wrap: wrap;' }, [
			actionLink(_('\u6253\u5f00 Zashboard'), 'admin/services/shinra/panel', true),
			actionLink(_('\u7ba1\u7406\u8d44\u6e90'), 'admin/services/shinra/resources'),
			actionLink(_('\u7f51\u7edc\u8bca\u65ad'), 'admin/services/shinra/logs')
		])
	]);
}

function renderPage() {
	const loadError = pageLoadError();

	return E('div', { 'id': 'shinra-overview-root', 'class': 'cbi-map' }, [
		E('h2', {}, _('Shinra')),
		E('p', {}, _('\u6982\u89c8\u662f\u63a7\u5236\u9762\u9996\u9875\u3002\u8fd0\u884c\u65f6\u7b56\u7565\u7ec4\u4ea4\u4e92\u7531 Zashboard \u5904\u7406\u3002')),
		loadError ? E('div', { 'style': 'border: 1px solid #fecaca; border-radius: 8px; padding: .75rem; margin-bottom: 1rem; background: #fef2f2; color: #991b1b;' }, loadError) : '',
		E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('\u8fd0\u884c\u65f6\u72b6\u6001')),
			runtimeCards(),
			E('h3', {}, _('\u8d44\u6e90\u5c31\u7eea\u72b6\u6001')),
			resourceCards(),
			operationButtons(),
			entryLinks()
		])
	]);
}

function redraw() {
	const root = document.getElementById('shinra-overview-root');
	if (root)
		root.parentNode.replaceChild(renderPage(), root);
}

return view.extend({
	load: function() {
		return loadAll();
	},

	render: function(results) {
		pageResults = results || {};
		return renderPage();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
