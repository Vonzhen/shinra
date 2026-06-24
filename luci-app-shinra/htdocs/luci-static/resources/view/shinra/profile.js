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

function sourceUrl(result) {
	const data = dataOf(result);
	return data.source && typeof data.source.url === 'string' ? data.source.url : '';
}

function sourceInputUrl(result) {
	return sourceUrl(result) || DEFAULT_TEMPLATE_URL;
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

function sourceSettings() {
	return E('div', { 'style': sectionStyle() }, [
		E('h3', { 'style': 'margin-top: 0;' }, _('模板同步')),
		E('div', { 'style': 'color: #667; margin-bottom: .75rem; overflow-wrap: anywhere;' }, _('设置远程 JSON 模板地址，然后同步到 /etc/shinra/main-profile.json。同步前会校验模板，并在替换当前模板前创建备份。')),
		E('label', {}, [
			E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('模板地址')),
			E('input', {
				'id': 'shinra-profile-source-url',
				'class': 'cbi-input-text',
				'style': 'width: 100%; max-width: 100%; box-sizing: border-box;',
				'placeholder': DEFAULT_TEMPLATE_URL,
				'value': sourceInputUrl(sourceResult)
			})
		]),
		E('div', { 'style': 'display: flex; gap: .5rem; align-items: center; flex-wrap: wrap; margin-top: .85rem;' }, [
			E('button', { 'class': 'btn cbi-button cbi-button-save', 'click': function(ev) { ev.preventDefault(); return saveSource(); } }, _('保存模板地址')),
			E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': function(ev) { ev.preventDefault(); return syncRemote(); } }, _('同步模板')),
			E('span', {
				'id': 'shinra-profile-action-status',
				'style': 'color: %s;'.format(actionStatusOk ? '#166534' : '#991b1b')
			}, actionStatus)
		])
	]);
}

function profilePreview() {
	const content = profileContent(profileResult);

	return E('div', { 'style': sectionStyle() }, [
		E('div', { 'style': 'display: flex; justify-content: space-between; gap: .75rem; align-items: center; flex-wrap: wrap; margin-bottom: .75rem;' }, [
			E('h3', { 'style': 'margin: 0;' }, _('只读预览')),
			profileResult && profileResult.ok && dataOf(profileResult).valid !== false ? statusPill(_('有效'), 'ok') : statusPill(_('无效'), 'error')
		]),
		E('pre', {
			'style': 'max-height: 36rem; overflow: auto; padding: .85rem; border-radius: 8px; background: #0f172a; color: #e5e7eb; font-family: monospace; white-space: pre;'
		}, content || _('没有模板内容。'))
	]);
}

function localActions() {
	return E('div', { 'style': sectionStyle() }, [
		E('h3', { 'style': 'margin-top: 0;' }, _('本地恢复')),
		E('div', { 'style': 'color: #667; margin-bottom: .75rem;' }, _('这些操作只影响 main-profile.json 及其备份，不会生成候选配置、应用运行配置或重启 sing-box。')),
		E('div', { 'style': 'display: flex; gap: .5rem; flex-wrap: wrap;' }, [
			E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function(ev) { ev.preventDefault(); return rollbackProfile(); } }, _('回滚')),
			E('button', { 'class': 'btn cbi-button cbi-button-remove', 'click': function(ev) { ev.preventDefault(); return restoreDefault(); } }, _('恢复内置模板'))
		])
	]);
}

function setStatus(text) {
	actionStatus = text || '';
	actionStatusOk = true;
	const node = document.getElementById('shinra-profile-action-status');
	if (node) {
		node.textContent = actionStatus;
		node.style.color = '#166534';
	}
}

function setError(text) {
	actionStatus = text || '';
	actionStatusOk = false;
	const node = document.getElementById('shinra-profile-action-status');
	if (node) {
		node.textContent = actionStatus;
		node.style.color = '#991b1b';
	}
}

function resultError(result, fallback) {
	if (result && (result.message || result.code))
		return '%s: %s'.format(result.message || result.code || fallback || _('操作失败'), result.detail || result.code || _('无详细信息'));
	return fallback || _('操作失败');
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
		setError(error.message || String(error));
	});
}

function saveSource() {
	const input = document.getElementById('shinra-profile-source-url');
	const source = {
		schema_version: 1,
		url: input ? input.value : ''
	};
	setStatus(_('正在保存...'));

	return callProfileSourceSave(JSON.stringify(source)).then(function(result) {
		if (result && result.ok) {
			sourceResult = {
				ok: true,
				data: dataOf(result)
			};
			setStatus(_('模板地址已保存。准备替换 main-profile.json 时，请执行同步模板。'));
			redraw();
		} else {
			setError(resultError(result, _('保存失败')));
		}
		return result;
	}).catch(function(error) {
		setError(error.message || String(error));
	});
}

function syncRemote() {
	setStatus(_('正在同步...'));
	return callProfileSyncRemote().then(function(result) {
		if (result && result.ok) {
			setStatus(_('模板已同步。准备使用更新后的模板时，请生成候选配置。'));
			return refreshPage();
		}

		setError(resultError(result, _('同步失败')));
		return result;
	}).catch(function(error) {
		setError(error.message || String(error));
	});
}

function rollbackProfile() {
	if (!window.confirm(_('回滚到上一个模板备份吗？运行配置不会改变。')))
		return Promise.resolve();

	setStatus(_('正在回滚...'));
	return callProfileRollback().then(function(result) {
		if (result && result.ok) {
			setStatus(_('模板已回滚。准备使用时，请生成候选配置。'));
			return refreshPage();
		}
		setError(resultError(result, _('回滚失败')));
		return result;
	}).catch(function(error) {
		setError(error.message || String(error));
	});
}

function restoreDefault() {
	if (!window.confirm(_('恢复内置模板吗？当前模板会被备份。')))
		return Promise.resolve();

	setStatus(_('正在恢复内置模板...'));
	return callProfileRestoreDefault().then(function(result) {
		if (result && result.ok) {
			setStatus(_('内置模板已恢复。准备使用时，请生成候选配置。'));
			return refreshPage();
		}
		setError(resultError(result, _('恢复失败')));
		return result;
	}).catch(function(error) {
		setError(error.message || String(error));
	});
}

function redraw() {
	const root = document.getElementById('shinra-profile-root');
	if (root)
		root.parentNode.replaceChild(renderPage(), root);
}

function renderPage() {
	return E('div', { 'id': 'shinra-profile-root', 'class': 'cbi-map' }, [
		E('h2', {}, _('模板')),
		E('p', {}, _('只读预览 main-profile.json，并支持远程模板同步。')),
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
	}
});
