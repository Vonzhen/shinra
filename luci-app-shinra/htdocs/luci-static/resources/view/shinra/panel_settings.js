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

const DEFAULT_DOWNLOAD_URL = 'https://github.com/Zephyruso/zashboard/releases/latest/download/dist-sarasa-only.zip';

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
		},
		clash_api: {
			enabled: true,
			external_controller: '0.0.0.0:9090',
			secret: '',
			external_ui: '',
			default_mode: 'rule'
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

function clashApiOf() {
	const source = sourceOf();
	return source.clash_api || defaultSource().clash_api;
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

function parseOrigins(value) {
	const text = String(value || '');
	const items = text.split(/[\n,]+/).map(function(item) {
		return item.trim();
	}).filter(function(item) {
		return item;
	});

	return items.length ? items : [ '*' ];
}

function originText(source) {
	const origins = source.access_control_allow_origin;
	if (!Array.isArray(origins) || !origins.length)
		return '*';
	return origins.join('\n');
}

function splitController(controller) {
	const value = String(controller || '0.0.0.0:9090');
	const fallback = { host: '0.0.0.0', port: 9090 };
	const bracketEnd = value.indexOf(']');

	if (value.charAt(0) === '[' && bracketEnd > 0) {
		const port = Number(value.substr(bracketEnd + 2));
		return {
			host: value.substr(1, bracketEnd - 1),
			port: Number.isFinite(port) && port > 0 ? port : fallback.port
		};
	}

	const offset = value.lastIndexOf(':');
	if (offset <= 0)
		return fallback;

	const port = Number(value.substr(offset + 1));
	return {
		host: value.substr(0, offset) || fallback.host,
		port: Number.isFinite(port) && port > 0 ? port : fallback.port
	};
}

function joinController(host, port) {
	host = String(host || '0.0.0.0');
	port = Number(port || 9090);
	if (!Number.isFinite(port) || port <= 0)
		port = 9090;
	if (host.indexOf(':') >= 0 && host.charAt(0) !== '[')
		host = '[' + host + ']';
	return host + ':' + port;
}

function collectSource() {
	const source = sourceOf();
	const port = Number(inputValue('shinra-dashboard-listen-port', source.listen_port || 20123));
	const clashPort = Number(inputValue('shinra-clash-api-listen-port', splitController(clashApiOf().external_controller).port));

	return {
		enabled: inputChecked('shinra-dashboard-enabled', true),
		listen: inputValue('shinra-dashboard-listen', '0.0.0.0'),
		listen_port: Number.isFinite(port) ? port : 20123,
		secret: inputValue('shinra-dashboard-secret', ''),
		access_control_allow_origin: parseOrigins(inputValue('shinra-dashboard-origins', '*')),
		access_control_allow_private_network: inputChecked('shinra-dashboard-private-network', true),
		dashboard: {
			enabled: inputChecked('shinra-dashboard-ui-enabled', true),
			path: inputValue('shinra-dashboard-path', '/www/shinra/dashboard'),
			download_url: inputValue('shinra-dashboard-download-url', DEFAULT_DOWNLOAD_URL),
			update_interval: inputValue('shinra-dashboard-update-interval', '1d')
		},
		clash_api: {
			enabled: inputChecked('shinra-clash-api-enabled', true),
			external_controller: joinController(inputValue('shinra-clash-api-listen', '0.0.0.0'), clashPort),
			secret: inputValue('shinra-clash-api-secret', ''),
			external_ui: inputValue('shinra-clash-api-external-ui', ''),
			default_mode: inputValue('shinra-clash-api-default-mode', 'rule')
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
		shinraUi.sectionTitle(_('Official API')),
		shinraUi.sectionDescription(_('这些设置用于生成 sing-box services 里的 API 服务。Profile 已配置 Official API 且不冲突时优先保留 Profile；与 Clash API 端口冲突时使用这里的配置兜底。修改后需要重新生成并应用配置。')),
		E('label', { 'style': 'display: flex; align-items: center; gap: .5rem; margin-bottom: .6rem;' }, [
			shinraUi.checkboxInput({ 'id': 'shinra-dashboard-enabled', 'checked': source.enabled ? 'checked' : null }),
			E('span', {}, _('启用 Official API'))
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
			E('label', {}, [
				shinraUi.fieldLabel(_('访问密钥')),
				E('input', { 'id': 'shinra-dashboard-secret', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'placeholder': _('私有局域网可留空'), 'value': source.secret || '' })
			])
		]),
		E('label', { 'style': 'display: block; margin-top: .6rem;' }, [
			shinraUi.fieldLabel(_('允许的 CORS 来源')),
			E('textarea', { 'id': 'shinra-dashboard-origins', 'class': 'cbi-input-textarea', 'style': 'width: 100%; min-height: 64px; box-sizing: border-box;' }, originText(source))
		]),
		E('label', { 'style': 'display: flex; align-items: center; gap: .5rem; margin-top: .6rem;' }, [
			shinraUi.checkboxInput({ 'id': 'shinra-dashboard-private-network', 'checked': source.access_control_allow_private_network ? 'checked' : null }),
			E('span', {}, _('允许私有网络访问'))
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

function clashApiSettings() {
	const clash = clashApiOf();
	const controller = splitController(clash.external_controller);

	return E('div', { 'style': shinraUi.sectionStyle() }, [
		shinraUi.sectionTitle(_('Clash API')),
		shinraUi.sectionDescription(_('这些设置用于生成 sing-box experimental.clash_api。Profile 已配置且不与最终生效的 Official API 冲突时优先保留 Profile；端口冲突时使用这里的配置兜底。')),
		E('label', { 'style': 'display: flex; align-items: center; gap: .5rem; margin-bottom: .6rem;' }, [
			shinraUi.checkboxInput({ 'id': 'shinra-clash-api-enabled', 'checked': clash.enabled ? 'checked' : null }),
			E('span', {}, _('启用 Clash API'))
		]),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: .75rem;' }, [
			E('label', {}, [
				shinraUi.fieldLabel(_('监听地址')),
				E('input', { 'id': 'shinra-clash-api-listen', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'value': controller.host || '0.0.0.0' })
			]),
			E('label', {}, [
				shinraUi.fieldLabel(_('监听端口')),
				E('input', { 'id': 'shinra-clash-api-listen-port', 'type': 'number', 'min': '1', 'max': '65535', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'value': controller.port || 9090 })
			]),
			E('label', {}, [
				shinraUi.fieldLabel(_('访问密钥')),
				E('input', { 'id': 'shinra-clash-api-secret', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'placeholder': _('私有局域网可留空'), 'value': clash.secret || '' })
			]),
			E('label', {}, [
				shinraUi.fieldLabel(_('默认模式')),
				E('select', { 'id': 'shinra-clash-api-default-mode', 'class': 'cbi-input-select', 'style': 'width: 100%; box-sizing: border-box;' }, [
					E('option', { 'value': 'rule', 'selected': (clash.default_mode || 'rule') === 'rule' ? 'selected' : null }, _('rule')),
					E('option', { 'value': 'global', 'selected': clash.default_mode === 'global' ? 'selected' : null }, _('global')),
					E('option', { 'value': 'direct', 'selected': clash.default_mode === 'direct' ? 'selected' : null }, _('direct'))
				])
			])
		]),
		E('label', { 'style': 'display: block; margin-top: .6rem;' }, [
			shinraUi.fieldLabel(_('External UI')),
			E('input', { 'id': 'shinra-clash-api-external-ui', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'placeholder': _('通常留空'), 'value': clash.external_ui || '' })
		])
	]);
}

function renderContent() {
	shinraMotion.inject();

	return E('div', { 'id': 'shinra-panel-settings-root' }, [
		shinraUi.pageHeader(
			_('面板'),
			_('Official API 负责 Dashboard 托管；Clash API 用于兼容面板的模式和策略组控制。Profile 中已配置的 API 会优先保留，端口冲突时使用此页设置兜底。Shinra 只保存设置并在重新生成配置时写入 sing-box。')
		),
		apiSettings(),
		dashboardSettings(),
		clashApiSettings(),
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
