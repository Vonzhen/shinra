'use strict';
'require view';
'require rpc';

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

const callProfileSourceSave = rpc.declare({
	object: 'shinra',
	method: 'profile_source_save',
	params: [ 'content' ],
	expect: { '': {} }
});

const callProfileSyncRemote = rpc.declare({
	object: 'shinra',
	method: 'profile_sync_remote',
	expect: { '': {} }
});

const callProfileRestoreDefault = rpc.declare({
	object: 'shinra',
	method: 'profile_restore_default',
	expect: { '': {} }
});

const callProfileRollback = rpc.declare({
	object: 'shinra',
	method: 'profile_rollback',
	expect: { '': {} }
});

const DEFAULT_TEMPLATE_URL = 'https://testingcf.jsdelivr.net/gh/Vonzhen/singbox-profiles@master/profiles/main-profile.json';

let profileResult = null;
let sourceResult = null;
let actionStatus = '';
let actionStatusOk = true;

function dataOf(result) {
	if (result && result.ok && result.data)
		return result.data;
	return {};
}

function profileContent(result) {
	return result && result.ok && result.data && typeof result.data.content === 'string' ? result.data.content : '';
}

function sourceData() {
	const data = dataOf(sourceResult);
	return data.source || {};
}

function sourceInputUrl() {
	return sourceData().url || DEFAULT_TEMPLATE_URL;
}

function sourceFetchStrategy() {
	return sourceData().fetch_strategy === 'proxy' ? 'proxy' : 'direct';
}

function sectionStyle() {
	return 'border: 1px solid #dfe3e8; border-radius: 8px; padding: 1rem; margin-bottom: 1rem; background: #fff;';
}

function mutedStyle() {
	return 'color: #667; overflow-wrap: anywhere;';
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

function actionStatusBox() {
	return E('div', {
		'id': 'shinra-profile-action-status',
		'style': 'display: %s; border: 1px solid %s; border-radius: 8px; padding: .75rem; margin-top: .85rem; background: %s; color: %s; overflow-wrap: anywhere;'.format(
			actionStatus ? 'block' : 'none',
			actionStatusOk ? '#bbf7d0' : '#fecaca',
			actionStatusOk ? '#f0fdf4' : '#fef2f2',
			actionStatusOk ? '#166534' : '#991b1b'
		)
	}, actionStatus);
}

function setStatus(text, ok) {
	actionStatus = text || '';
	actionStatusOk = ok !== false;

	const node = document.getElementById('shinra-profile-action-status');
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

function refreshPage() {
	return Promise.all([
		callProfileGet(),
		callProfileSourceGet()
	]).then(function(results) {
		profileResult = results && results[0] ? results[0] : {};
		sourceResult = results && results[1] ? results[1] : {};
		redraw();
		return results;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function saveSource() {
	const input = document.getElementById('shinra-profile-source-url');
	const strategy = document.getElementById('shinra-profile-fetch-strategy');
	const source = {
		schema_version: 1,
		url: input ? input.value : '',
		fetch_strategy: strategy && strategy.value === 'proxy' ? 'proxy' : 'direct'
	};

	setStatus(_('\u6b63\u5728\u4fdd\u5b58\u6a21\u677f\u6e90...'), true);

	return callProfileSourceSave(JSON.stringify(source)).then(function(result) {
		if (result && result.ok) {
			sourceResult = {
				ok: true,
				data: dataOf(result)
			};
			setStatus(_('\u6a21\u677f\u6e90\u5df2\u4fdd\u5b58\u3002\u9700\u8981\u66ff\u6362 main-profile.json \u65f6\uff0c\u8bf7\u6267\u884c\u540c\u6b65\u6a21\u677f\u3002'), true);
			redraw();
		} else {
			setStatus(resultError(result, _('\u4fdd\u5b58\u5931\u8d25')), false);
		}
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function syncRemote() {
	setStatus(_('\u6b63\u5728\u540c\u6b65\u6a21\u677f...'), true);

	return callProfileSyncRemote().then(function(result) {
		if (result && result.ok) {
			setStatus(_('\u6a21\u677f\u5df2\u540c\u6b65\u3002\u51c6\u5907\u4f7f\u7528\u65b0\u6a21\u677f\u65f6\uff0c\u8bf7\u751f\u6210\u5019\u9009\u914d\u7f6e\u3002'), true);
			return refreshPage();
		}

		setStatus(resultError(result, _('\u540c\u6b65\u5931\u8d25')), false);
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function rollbackProfile() {
	if (!window.confirm(_('\u56de\u6eda\u5230\u4e0a\u4e00\u4e2a\u6a21\u677f\u5907\u4efd\u5417\uff1f\u8fd0\u884c\u914d\u7f6e\u4e0d\u4f1a\u6539\u53d8\u3002')))
		return Promise.resolve();

	setStatus(_('\u6b63\u5728\u56de\u6eda\u6a21\u677f...'), true);

	return callProfileRollback().then(function(result) {
		if (result && result.ok) {
			setStatus(_('\u6a21\u677f\u5df2\u56de\u6eda\u3002\u51c6\u5907\u4f7f\u7528\u65f6\uff0c\u8bf7\u751f\u6210\u5019\u9009\u914d\u7f6e\u3002'), true);
			return refreshPage();
		}
		setStatus(resultError(result, _('\u56de\u6eda\u5931\u8d25')), false);
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function restoreDefault() {
	if (!window.confirm(_('\u6062\u590d\u5185\u7f6e\u6a21\u677f\u5417\uff1f\u5f53\u524d\u6a21\u677f\u4f1a\u88ab\u5907\u4efd\u3002')))
		return Promise.resolve();

	setStatus(_('\u6b63\u5728\u6062\u590d\u5185\u7f6e\u6a21\u677f...'), true);

	return callProfileRestoreDefault().then(function(result) {
		if (result && result.ok) {
			setStatus(_('\u5185\u7f6e\u6a21\u677f\u5df2\u6062\u590d\u3002\u51c6\u5907\u4f7f\u7528\u65f6\uff0c\u8bf7\u751f\u6210\u5019\u9009\u914d\u7f6e\u3002'), true);
			return refreshPage();
		}
		setStatus(resultError(result, _('\u6062\u590d\u5931\u8d25')), false);
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function sourceSettings() {
	return E('div', { 'style': sectionStyle() }, [
		E('h3', { 'style': 'margin-top: 0;' }, _('\u6a21\u677f\u540c\u6b65')),
		E('div', { 'style': mutedStyle() + ' margin-bottom: .75rem;' }, _('\u8bbe\u7f6e\u8fdc\u7a0b JSON \u6a21\u677f\u5730\u5740\uff0c\u5e76\u540c\u6b65\u5230 /etc/shinra/main-profile.json\u3002\u540c\u6b65\u4f1a\u6821\u9a8c\u6a21\u677f\uff0c\u5e76\u5728\u66ff\u6362\u524d\u521b\u5efa\u5907\u4efd\u3002')),
		E('label', {}, [
			E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('\u6a21\u677f\u5730\u5740')),
			E('input', {
				'id': 'shinra-profile-source-url',
				'class': 'cbi-input-text',
				'style': 'width: 100%; max-width: 100%; box-sizing: border-box;',
				'placeholder': DEFAULT_TEMPLATE_URL,
				'value': sourceInputUrl()
			})
		]),
		E('label', { 'style': 'display: block; margin-top: .75rem;' }, [
			E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('\u4e0b\u8f7d\u7b56\u7565')),
			E('select', { 'id': 'shinra-profile-fetch-strategy', 'class': 'cbi-input-select', 'style': 'min-width: 220px;' }, [
				E('option', { 'value': 'direct', 'selected': sourceFetchStrategy() === 'direct' ? 'selected' : null }, _('\u76f4\u8fde')),
				E('option', { 'value': 'proxy', 'selected': sourceFetchStrategy() === 'proxy' ? 'selected' : null }, _('\u4ee3\u7406'))
			])
		]),
		E('div', { 'style': 'display: flex; gap: .5rem; align-items: center; flex-wrap: wrap; margin-top: .85rem;' }, [
			E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-save', 'click': function(ev) { ev.preventDefault(); return saveSource(); } }, _('\u4fdd\u5b58\u6a21\u677f\u6e90')),
			E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-apply', 'click': function(ev) { ev.preventDefault(); return syncRemote(); } }, _('\u540c\u6b65\u6a21\u677f'))
		]),
		actionStatusBox()
	]);
}

function localActions() {
	return E('div', { 'style': sectionStyle() }, [
		E('h3', { 'style': 'margin-top: 0;' }, _('\u672c\u5730\u6062\u590d')),
		E('div', { 'style': mutedStyle() + ' margin-bottom: .75rem;' }, _('\u8fd9\u4e9b\u64cd\u4f5c\u53ea\u4fee\u6539 main-profile.json \u53ca\u5176\u5907\u4efd\uff0c\u4e0d\u4f1a\u751f\u6210\u5019\u9009\u914d\u7f6e\u3001\u5e94\u7528\u8fd0\u884c\u914d\u7f6e\u6216\u91cd\u542f sing-box\u3002')),
		E('div', { 'style': 'display: flex; gap: .5rem; flex-wrap: wrap;' }, [
			E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-neutral', 'click': function(ev) { ev.preventDefault(); return rollbackProfile(); } }, _('\u56de\u6eda')),
			E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-remove', 'click': function(ev) { ev.preventDefault(); return restoreDefault(); } }, _('\u6062\u590d\u5185\u7f6e\u6a21\u677f'))
		])
	]);
}

function profilePreview() {
	const content = profileContent(profileResult);
	const valid = profileResult && profileResult.ok && dataOf(profileResult).valid !== false;

	return E('div', { 'style': sectionStyle() }, [
		E('div', { 'style': 'display: flex; justify-content: space-between; gap: .75rem; align-items: center; flex-wrap: wrap; margin-bottom: .75rem;' }, [
			E('h3', { 'style': 'margin: 0;' }, _('\u53ea\u8bfb\u9884\u89c8')),
			valid ? statusPill(_('\u6709\u6548'), 'ok') : statusPill(_('\u65e0\u6548'), 'error')
		]),
		E('pre', {
			'style': 'max-height: 36rem; overflow: auto; padding: .85rem; border-radius: 8px; background: #0f172a; color: #e5e7eb; font-family: monospace; white-space: pre;'
		}, content || _('\u6ca1\u6709\u6a21\u677f\u5185\u5bb9\u3002'))
	]);
}

function redraw() {
	const root = document.getElementById('shinra-profile-root');
	if (root)
		root.parentNode.replaceChild(renderPage(), root);
}

function renderPage() {
	return E('div', { 'id': 'shinra-profile-root', 'class': 'cbi-map' }, [
		E('h2', {}, _('\u6a21\u677f')),
		E('p', {}, _('\u53ea\u8bfb\u9884\u89c8 main-profile.json\uff0c\u5e76\u652f\u6301\u8fdc\u7a0b\u6a21\u677f\u540c\u6b65\u3002')),
		sourceSettings(),
		localActions(),
		profilePreview()
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			callProfileGet(),
			callProfileSourceGet()
		]);
	},

	render: function(results) {
		profileResult = results && results[0] ? results[0] : {};
		sourceResult = results && results[1] ? results[1] : {};

		return renderPage();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
