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

let sourceResult = null;
let statusResult = null;

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

	[sourceResult, statusResult].forEach(function(result) {
		if (result && !result.ok)
			messages.push('%s: %s'.format(result.message || result.code || _('加载失败'), result.detail || result.code || _('无详细信息')));
	});

	return messages.join('\n');
}

function renderPage() {
	const source = sourceOf();
	const dash = dashboardOf();
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
			callDashboardStatus()
		]);
	},

	render: function(results) {
		sourceResult = results && results[0] ? results[0] : {};
		statusResult = results && results[1] ? results[1] : {};
		return renderPage();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
