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
		public_access: {
			enabled: false,
			origin: '',
			dashboard_path: '/shinra/dashboard/',
			api_path: '/shinra/api/'
		},
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

function publicAccessOf() {
	const source = sourceOf();
	return source.public_access || defaultSource().public_access;
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
		public_access: {
			enabled: inputChecked('shinra-public-access-enabled', false),
			origin: inputValue('shinra-public-access-origin', ''),
			dashboard_path: inputValue('shinra-public-dashboard-path', '/shinra/dashboard/'),
			api_path: inputValue('shinra-public-api-path', '/shinra/api/')
		},
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

function publicAccessSettings() {
	const source = sourceOf();
	const publicAccess = publicAccessOf();
	const port = source.listen_port || 20123;
	const dashboardPath = publicAccess.dashboard_path || '/shinra/dashboard/';
	const apiPath = publicAccess.api_path || '/shinra/api/';
	const routerIp = _('OpenWrt 管理 IP');
	const target = routerIp + ':' + port;
	const routeStyle = 'padding: .45rem .6rem; border: 1px solid #dfe3e8; border-radius: 6px; background: #f8fafc; overflow-wrap: anywhere;';

	return E('div', { 'style': shinraUi.sectionStyle() }, [
		shinraUi.sectionTitle(_('公网反向代理访问（可选）')),
		shinraUi.sectionDescription(_('这是可选增强功能。Shinra 不创建或管理 NPS 规则，只根据当前访问 Origin 选择公网路径；未启用或 Origin 不匹配时，Dashboard 始终使用内网直连。')),
		E('label', { 'style': 'display: flex; align-items: center; gap: .5rem; margin-bottom: .6rem;' }, [
			shinraUi.checkboxInput({ 'id': 'shinra-public-access-enabled', 'checked': publicAccess.enabled ? 'checked' : null }),
			E('span', {}, _('启用公网反向代理入口'))
		]),
		E('label', { 'style': 'display: block; margin-top: .6rem;' }, [
			shinraUi.fieldLabel(_('公网 Origin')),
			E('input', { 'id': 'shinra-public-access-origin', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'placeholder': 'https://mop.miozen.uk', 'value': publicAccess.origin || '' }),
			E('div', { 'style': shinraUi.mutedStyle('font-size: 12px; margin-top: .25rem;') }, _('只填写协议、域名和可选端口，不填写路径。例如：https://mop.miozen.uk'))
		]),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: .75rem; margin-top: .6rem;' }, [
			E('label', {}, [
				shinraUi.fieldLabel(_('Dashboard 公网路径')),
				E('input', { 'id': 'shinra-public-dashboard-path', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'value': dashboardPath })
			]),
			E('label', {}, [
				shinraUi.fieldLabel(_('API 公网路径')),
				E('input', { 'id': 'shinra-public-api-path', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'value': apiPath })
			])
		]),
		E('div', { 'style': 'margin-top: .85rem;' }, [
			E('div', { 'style': 'font-weight: 700; margin-bottom: .4rem;' }, _('NPS 服务器配置方法')),
			E('div', { 'style': shinraUi.mutedStyle('margin-bottom: .5rem;') }, _('在 NPS 的 HTTP 代理中配置以下三条路径规则。目标地址必须填写 OpenWrt 的明确内网管理 IP，不能填写 0.0.0.0 或 127.0.0.1；例如本机管理地址为 10.10.11.1 时，目标分别是 10.10.11.1:80 和 10.10.11.1:20123。')),
			E('div', { 'style': 'display: grid; gap: .45rem;' }, [
				E('div', { 'style': routeStyle }, [
					E('strong', {}, _('LuCI：')),
					'/ → %s:80，保持原路径'.format(routerIp)
				]),
				E('div', { 'style': routeStyle }, [
					E('strong', {}, _('Dashboard：')),
					'%s → %s，重写为 /dashboard/'.format(dashboardPath, target)
				]),
				E('div', { 'style': routeStyle }, [
					E('strong', {}, _('API：')),
					'%s → %s，重写为 /'.format(apiPath, target)
				])
			]),
			E('div', { 'style': shinraUi.mutedStyle('font-size: 12px; margin-top: .5rem;') }, _('Dashboard 与 API 两条规则使用同一个 sing-box API 监听端口，并启用 WebSocket 转发、保留查询参数。路径匹配应优先于根路径规则，避免 / 被提前接管。公网 HTTPS 入口应由 NPS 或其上游负责证书与访问控制。'))
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
		publicAccessSettings(),
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
