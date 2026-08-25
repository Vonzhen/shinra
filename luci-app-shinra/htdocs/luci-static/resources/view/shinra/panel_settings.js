'use strict';
'require view';
'require rpc';
'require shinra.ui as shinraUi';
'require shinra.motion as shinraMotion';

const callDashboardSourceGet = rpc.declare({
	object: 'shinra',
	method: 'dashboard_source_get',
	expect: { '': {} }
});

const callDashboardSourceSave = rpc.declare({
	object: 'shinra',
	method: 'dashboard_source_save',
	params: [ 'content' ],
	expect: { '': {} }
});

const callDashboardStatus = rpc.declare({
	object: 'shinra',
	method: 'dashboard_status',
	expect: { '': {} }
});

const DEFAULT_DOWNLOAD_URL = 'https://github.com/miozen/shinra-dashboard/releases/latest/download/shinra-dashboard.zip';

let sourceResult = null;
let statusResult = null;
let actionStatus = '';
let actionStatusOk = true;

function dataOf(result) {
	if (result && result.ok && result.data)
		return result.data;
	return {};
}

function defaultSource() {
	return {
		enabled: true,
		listen: '0.0.0.0',
		listen_port: 20123,
		secret: '',
		access_control_allow_origin: [ '*' ],
		access_control_allow_private_network: true,
		dashboard: {
			enabled: true,
			path: '/www/shinra/dashboard',
			download_url: DEFAULT_DOWNLOAD_URL,
			update_interval: '1d'
		}
	};
}

function sourceOf() {
	const sourceData = dataOf(sourceResult);
	const statusData = dataOf(statusResult);
	return sourceData.source || statusData.source || defaultSource();
}

function dashboardOf() {
	const source = sourceOf();
	return source.dashboard || defaultSource().dashboard;
}

function resultMessage(result, fallback) {
	if (result && result.ok)
		return fallback || result.message || _('完成');
	if (result && (result.message || result.code))
		return '%s: %s'.format(result.message || result.code || _('未知错误'), result.detail || result.code || _('无详细信息'));
	return fallback || _('操作失败');
}

function loadErrorMessage() {
	const messages = [];

	[sourceResult, statusResult].forEach(function(result) {
		if (result && !result.ok)
			messages.push('%s: %s'.format(result.message || result.code || _('未知错误'), result.detail || result.code || _('无详细信息')));
	});

	return messages.join('\n');
}

function inlineResultNode() {
	const loadError = loadErrorMessage();
	const text = actionStatus || loadError;
	const ok = actionStatus ? actionStatusOk : !loadError;

	return shinraUi.statusBox('shinra-panel-settings-action-status', text, ok ? 'ok' : 'error', {
		padding: '.45rem .65rem',
		margin: '0',
		style: 'min-width: min(360px, 100%); flex: 1 1 320px;'
	});
}

function setStatus(text, ok) {
	actionStatus = text || '';
	actionStatusOk = ok !== false;
	shinraUi.paintStatus('shinra-panel-settings-action-status', actionStatus, actionStatusOk ? 'ok' : 'error');
}

function inputValue(id, fallback) {
	const node = document.getElementById(id);
	return node ? node.value : fallback || '';
}

function inputChecked(id, fallback) {
	const node = document.getElementById(id);
	return node ? !!node.checked : !!fallback;
}

function collectSource() {
	const source = sourceOf();
	const port = Number(inputValue('shinra-dashboard-listen-port', source.listen_port || 20123));

	return {
		enabled: inputChecked('shinra-dashboard-enabled', true),
		listen: inputValue('shinra-dashboard-listen', '0.0.0.0'),
		listen_port: Number.isFinite(port) ? port : 20123,
		secret: '',
		access_control_allow_origin: [ '*' ],
		access_control_allow_private_network: true,
		dashboard: {
			enabled: inputChecked('shinra-dashboard-ui-enabled', true),
			path: inputValue('shinra-dashboard-path', '/www/shinra/dashboard'),
			download_url: inputValue('shinra-dashboard-download-url', DEFAULT_DOWNLOAD_URL),
			update_interval: inputValue('shinra-dashboard-update-interval', '1d')
		}
	};
}

function refreshPage() {
	return load().then(function(results) {
		sourceResult = results && results[0] ? results[0] : {};
		statusResult = results && results[1] ? results[1] : {};
		redraw();
		return results;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function saveSource() {
	setStatus(_('正在保存设置...'), true);
	return callDashboardSourceSave(JSON.stringify(collectSource())).then(function(result) {
		if (result && result.ok) {
			sourceResult = {
				ok: true,
				data: dataOf(result)
			};
			setStatus(_('设置已保存。重新生成并应用配置后生效。'), true);
			return refreshPage();
		}

		setStatus(resultMessage(result, _('保存失败')), false);
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function apiSettings() {
	const source = sourceOf();

	return E('div', { 'style': shinraUi.sectionStyle() }, [
		shinraUi.sectionTitle(_('sing-box API')),
		shinraUi.sectionDescription(_('这些设置用于生成由 Shinra 管理的 sing-box API 服务。Dashboard 通过同源地址连接该服务，访问密钥固定留空。修改后需要重新生成并应用配置。')),
		E('label', { 'style': 'display: flex; align-items: center; gap: .5rem; margin-bottom: .6rem;' }, [
			shinraUi.checkboxInput({ 'id': 'shinra-dashboard-enabled', 'checked': source.enabled ? 'checked' : null }),
			E('span', {}, _('启用 sing-box API'))
		]),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: .75rem;' }, [
			E('label', {}, [
				shinraUi.fieldLabel(_('监听地址')),
				E('input', { 'id': 'shinra-dashboard-listen', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'value': source.listen || '0.0.0.0' })
			]),
			E('label', {}, [
				shinraUi.fieldLabel(_('监听端口')),
				E('input', { 'id': 'shinra-dashboard-listen-port', 'type': 'number', 'min': '1', 'max': '65535', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'value': source.listen_port || 20123 })
			]),
		])
	]);
}

function dashboardSettings() {
	const dash = dashboardOf();

	return E('div', { 'style': shinraUi.sectionStyle() }, [
		shinraUi.sectionTitle(_('Dashboard')),
		shinraUi.sectionDescription(_('面板文件由 sing-box 根据下载地址自动下载、更新并托管。Shinra 只保存配置。')),
		E('label', { 'style': 'display: flex; align-items: center; gap: .5rem; margin-bottom: .6rem;' }, [
			shinraUi.checkboxInput({ 'id': 'shinra-dashboard-ui-enabled', 'checked': dash.enabled ? 'checked' : null }),
			E('span', {}, _('启用 Dashboard'))
		]),
		E('label', { 'style': 'display: block; margin-top: .6rem;' }, [
			shinraUi.fieldLabel(_('面板目录')),
			E('input', { 'id': 'shinra-dashboard-path', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'value': dash.path || '/www/shinra/dashboard' })
		]),
		E('label', { 'style': 'display: block; margin-top: .6rem;' }, [
			shinraUi.fieldLabel(_('下载地址')),
			E('input', { 'id': 'shinra-dashboard-download-url', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'value': dash.download_url || DEFAULT_DOWNLOAD_URL })
		]),
		E('label', { 'style': 'display: block; margin-top: .6rem;' }, [
			shinraUi.fieldLabel(_('更新间隔')),
			E('input', { 'id': 'shinra-dashboard-update-interval', 'class': 'cbi-input-text', 'style': 'width: 220px; max-width: 100%; box-sizing: border-box;', 'value': dash.update_interval || '1d' })
		])
	]);
}

function renderContent() {
	shinraMotion.inject();

	return E('div', { 'id': 'shinra-panel-settings-root' }, [
		shinraUi.pageHeader(
			_('面板'),
			_('sing-box API 负责托管并同源提供 Shinra Dashboard；Shinra 在重新生成配置时写入固定的无密钥 API 服务。')
		),
		apiSettings(),
		dashboardSettings(),
		E('div', { 'style': 'display: flex; gap: .5rem; align-items: center; flex-wrap: wrap; margin-top: .7rem;' }, [
			E('button', { 'class': shinraMotion.buttonClass('btn cbi-button cbi-button-save'), 'click': function(ev) { ev.preventDefault(); return saveSource(); } }, _('保存设置')),
			inlineResultNode()
		])
	]);
}

function redraw() {
	const root = document.getElementById('shinra-panel-settings-root');
	if (root)
		root.parentNode.replaceChild(renderContent(), root);
}

function load() {
	return Promise.all([
		callDashboardSourceGet(),
		callDashboardStatus()
	]);
}

return view.extend({
	load: load,
	render: function(results) {
		sourceResult = results && results[0] ? results[0] : {};
		statusResult = results && results[1] ? results[1] : {};
		return renderContent();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
