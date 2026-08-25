'use strict';
'require view';
'require rpc';

const callDashboardSourceGet = rpc.declare({
	object: 'shinra',
	method: 'dashboard_source_get',
	expect: { '': {} }
});

const callDashboardStatus = rpc.declare({
	object: 'shinra',
	method: 'dashboard_status',
	expect: { '': {} }
});

const callApiStatus = rpc.declare({
	object: 'shinra',
	method: 'api_status',
	expect: { '': {} }
});

let sourceResult = null;
let statusResult = null;
let apiStatusResult = null;

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
		dashboard: {
			enabled: true,
			path: '/www/shinra/dashboard'
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

function dashboardHost(source) {
	if (source.listen && source.listen !== '0.0.0.0' && source.listen !== '::')
		return source.listen;
	return window.location.hostname || location.hostname || '192.168.1.1';
}

function dashboardUrl() {
	const source = sourceOf();
	const status = dataOf(statusResult);
	if (status.dashboard_url && status.dashboard_url.indexOf('<router-host>') < 0)
		return status.dashboard_url;
	return '%s//%s:%s/dashboard/'.format(window.location.protocol || 'http:', dashboardHost(source), source.listen_port || 20123);
}

function sectionStyle() {
	return 'border: 1px solid #dfe3e8; border-radius: 8px; padding: .75rem 1rem; margin: 0 0 .75rem; background: #fff;';
}

function mutedStyle() {
	return 'color: #667; line-height: 1.35; overflow-wrap: anywhere;';
}

function errorMessage() {
	const messages = [];

	[sourceResult, statusResult, apiStatusResult].forEach(function(result) {
		if (result && !result.ok)
			messages.push('%s: %s'.format(result.message || result.code || _('加载失败'), result.detail || result.code || _('无详细信息')));
	});

	return messages.join('\n');
}

function renderPage() {
	const source = sourceOf();
	const dash = dashboardOf();
	const status = dataOf(statusResult);
	const singboxApi = dataOf(apiStatusResult).singbox_api || {};
	const error = errorMessage();

	if (error) {
		return E('div', { 'id': 'shinra-panel-root', 'class': 'cbi-map' }, [
			E('div', { 'style': sectionStyle() + ' color: #991b1b; background: #fef2f2; border-color: #fecaca;' }, error)
		]);
	}

	if (!source.enabled || !dash.enabled) {
		return E('div', { 'id': 'shinra-panel-root', 'class': 'cbi-map' }, [
			E('div', { 'style': sectionStyle() }, [
				E('h3', { 'style': 'margin: 0 0 .35rem; line-height: 1.25;' }, _('面板未启用')),
				E('div', { 'style': mutedStyle() }, _('请在资源管理的面板页启用并应用配置。'))
			])
		]);
	}

	if (!singboxApi.available) {
		return E('div', { 'id': 'shinra-panel-root', 'class': 'cbi-map' }, [
			E('div', { 'style': sectionStyle() }, [
				E('h3', { 'style': 'margin: 0 0 .35rem; line-height: 1.25;' }, _('sing-box API 未就绪')),
				E('div', { 'style': mutedStyle() }, _('请先在概览页生成并应用配置。sing-box 启动后会自动下载并托管 Dashboard。'))
			])
		]);
	}

	if (!status.dashboard_ready) {
		return E('div', { 'id': 'shinra-panel-root', 'class': 'cbi-map' }, [
			E('div', { 'style': sectionStyle() }, [
				E('h3', { 'style': 'margin: 0 0 .35rem; line-height: 1.25;' }, _('Dashboard 正在初始化')),
				E('div', { 'style': mutedStyle() }, _('首次启动时 sing-box 会自动下载 Dashboard。下载完成后刷新此页即可打开。'))
			])
		]);
	}

	return E('div', { 'id': 'shinra-panel-root', 'class': 'cbi-map' }, [
		E('iframe', {
			'src': dashboardUrl(),
			'style': 'width: 100%; height: min(84vh, 820px); border: 1px solid #dfe3e8; border-radius: 8px; background: #fff;',
			'loading': 'lazy'
		})
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			callDashboardSourceGet(),
			callDashboardStatus(),
			callApiStatus()
		]);
	},

	render: function(results) {
		sourceResult = results && results[0] ? results[0] : {};
		statusResult = results && results[1] ? results[1] : {};
		apiStatusResult = results && results[2] ? results[2] : {};
		return renderPage();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
