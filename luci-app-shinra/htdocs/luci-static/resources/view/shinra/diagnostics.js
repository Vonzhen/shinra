'use strict';
'require view';
'require rpc';
'require shinra.time as shinraTime';

const callLogsGet = rpc.declare({
	object: 'shinra',
	method: 'logs_get',
	expect: { '': {} }
});

const callLastErrorGet = rpc.declare({
	object: 'shinra',
	method: 'last_error_get',
	expect: { '': {} }
});

const callDiagnosticsGet = rpc.declare({
	object: 'shinra',
	method: 'diagnostics_get',
	expect: { '': {} }
});

const callConnectivityProbe = rpc.declare({
	object: 'shinra',
	method: 'connectivity_probe',
	expect: { '': {} }
});

let activeTab = 'dataplane';
let pageResults = {};

function dataOf(result) {
	if (result && result.ok && result.data)
		return result.data;
	return {};
}

function mutedStyle() {
	return 'color: #667; line-height: 1.35; overflow-wrap: anywhere;';
}

function sectionStyle() {
	return 'border: 1px solid #dfe3e8; border-radius: 8px; padding: .75rem 1rem; margin: 0 0 .75rem; background: #fff;';
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

function valueText(value) {
	if (value == null || value === '')
		return '-';
	return String(value);
}

function yesNo(value) {
	return value ? _('是') : _('否');
}

function pill(text, ok, warn) {
	let color = '#374151';
	let bg = '#f3f4f6';

	if (ok) {
		color = '#166534';
		bg = '#dcfce7';
	} else if (warn) {
		color = '#9a3412';
		bg = '#ffedd5';
	} else {
		color = '#991b1b';
		bg = '#fee2e2';
	}

	return E('span', {
		'style': 'display: inline-flex; align-items: center; min-height: 22px; padding: 0 .55rem; border-radius: 999px; font-size: 12px; font-weight: 700; color: %s; background: %s;'.format(color, bg)
	}, text);
}

function checkRow(label, ok, detail, warn) {
	return E('div', { 'style': 'display: grid; grid-template-columns: minmax(180px, 1fr) 90px minmax(0, 2fr); gap: .75rem; align-items: center; padding: .55rem 0; border-bottom: 1px solid #eef0f3;' }, [
		E('div', { 'style': 'font-weight: 600;' }, label),
		E('div', {}, pill(yesNo(ok), ok, warn)),
		E('div', { 'style': mutedStyle() }, valueText(detail))
	]);
}

function field(label, value) {
	return E('div', { 'style': 'display: grid; grid-template-columns: minmax(160px, 1fr) minmax(0, 2fr); gap: .75rem; padding: .45rem 0; border-bottom: 1px solid #eef0f3;' }, [
		E('div', { 'style': 'color: #667;' }, label),
		E('div', { 'style': 'overflow-wrap: anywhere;' }, valueText(value))
	]);
}

function commandBlock(label, result) {
	result = result || {};

	const text = [
		'$ ' + label,
		result.stdout || '',
		result.stderr ? 'stderr: ' + result.stderr : ''
	].filter(function(line) {
		return line !== '';
	}).join('\n');

	return E('div', { 'style': 'margin-bottom: .75rem;' }, [
		E('div', { 'style': 'font-weight: 600; margin-bottom: .25rem;' }, label),
		E('pre', { 'style': 'white-space: pre-wrap; overflow-wrap: anywhere; max-height: 180px; overflow-y: auto; background: #f8fafc; border: 1px solid #eef0f3; border-radius: 6px; padding: .65rem;' }, text)
	]);
}

function loadErrorPanel() {
	const errors = [];

	[
		pageResults.diagnostics,
		pageResults.connectivity,
		pageResults.lastError,
		pageResults.logs
	].forEach(function(result) {
		if (result && !result.ok)
			errors.push('%s: %s'.format(result.message || result.code || _('加载失败'), result.detail || result.code || _('无详细信息')));
	});

	if (!errors.length)
		return null;

	return E('div', {
		'style': 'border: 1px solid #fecaca; border-left: 4px solid #dc2626; border-radius: 8px; padding: .85rem; margin-bottom: 1rem; background: #fef2f2; color: #7f1d1d;'
	}, [
		E('div', { 'style': 'font-weight: 700; margin-bottom: .35rem;' }, _('诊断加载异常')),
		E('pre', { 'style': 'white-space: pre-wrap; overflow-wrap: anywhere; margin: 0;' }, errors.join('\n'))
	]);
}

function tabButton(id, label) {
	const active = activeTab === id;
	return E('button', {
		'type': 'button',
		'class': 'btn cbi-button %s'.format(active ? 'cbi-button-apply' : 'cbi-button-neutral'),
		'style': 'margin-right: .5rem; margin-bottom: .75rem;',
		'click': function(ev) {
			ev.preventDefault();
			activeTab = id;
			redraw();
		}
	}, label);
}

function logsText(lines, filter) {
	if (!Array.isArray(lines) || !lines.length)
		return _('未观测到日志。');

	const selected = lines.filter(function(line) {
		if (!filter)
			return true;
		return filter(line);
	});

	if (!selected.length)
		return _('未观测到匹配日志。');

	return selected.join('\n');
}

function dataplaneLogs(line) {
	line = String(line || '').toLowerCase();
	return line.indexOf('sing-box') >= 0 || line.indexOf('tun') >= 0 || line.indexOf('clash') >= 0;
}

function controlplaneLogs(line) {
	line = String(line || '').toLowerCase();
	return line.indexOf('shinra') >= 0 || line.indexOf('rpcd') >= 0 || line.indexOf('uhttpd') >= 0;
}

function dataplanePanel() {
	const probe = dataOf(pageResults.connectivity);
	const checks = probe.checks || {};
	const readiness = probe.readiness || {};
	const commands = probe.commands || {};
	const selectors = probe.selectors || {};
	const runtime = probe.runtime || {};
	const logs = dataOf(pageResults.logs);

	const ready = readiness.ready === true;
	const routeDiagnostic = checks.route_default_uses_tun || checks.route_target_uses_tun;

	return E('div', {}, [
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('数据面观测')),
			sectionDescription(_('用于排查 TUN、auto_redirect、策略表、Clash API 和策略组可观测性。')),
			checkRow(_('数据面就绪'), ready, ready ? _('ready') : (readiness.failed_check || '-')),
			checkRow(_('Runtime 运行中'), !!checks.runtime_running, runtime.service_status || '-'),
			checkRow(_('TUN 存在'), !!checks.tun_present, runtime.tun_name || readiness.tun_name || 'tun0'),
			checkRow(_('TUN 已 UP'), !!checks.tun_up, '-'),
			checkRow(_('表 2022 指向 TUN'), !!checks.table_2022_has_tun, '-'),
			checkRow(_('ip rule 包含表 2022'), !!checks.ip_rule_has_table_2022, '-'),
			checkRow(_('auto_redirect 规则可观测'), !!checks.ip_rule_has_fwmark_redirect, checks.auto_redirect_mode ? _('auto_redirect mode') : '-'),
			checkRow(_('Clash API 可访问'), !!checks.clash_api_available, checks.clash_api_available ? _('ok') : _('api_unreachable')),
			checkRow(_('策略组可观测'), !!checks.selector_available, selectors.first_now || selectors.error || '-'),
			checkRow(_('本机 route get 经 TUN'), !!routeDiagnostic, _('auto_redirect 模式下仅作诊断，不参与就绪判断'), true)
		]),
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('数据面命令输出')),
			commandBlock('ip link show ' + (runtime.tun_name || readiness.tun_name || 'tun0'), commands.tun_link),
			commandBlock('ip rule', commands.ip_rule),
			commandBlock('ip route show table 2022', commands.table_2022),
			commandBlock('ip route get 1.1.1.1', commands.route_1_1_1_1),
			commandBlock('ip route get ' + (probe.probe_target || '1.1.1.1'), commands.route_target)
		]),
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('数据面日志')),
			E('pre', { 'style': 'white-space: pre-wrap; overflow-wrap: anywhere; max-height: 420px; overflow-y: auto;' }, logsText(logs.lines, dataplaneLogs))
		])
	]);
}

function fileRows(files) {
	const order = [
		'profile',
		'subscriptions',
		'node_snapshot',
		'candidate',
		'runtime_config',
		'runtime_backup',
		'runtime_state',
		'auto_apply_state',
		'last_error'
	];
	const rows = [];

	order.forEach(function(key) {
		const item = files && files[key];
		if (!item)
			return;

		rows.push(E('div', { 'style': 'display: grid; grid-template-columns: minmax(130px, .8fr) minmax(0, 2fr) 90px; gap: .75rem; padding: .5rem 0; border-bottom: 1px solid #eef0f3; align-items: center;' }, [
			E('div', { 'style': 'font-weight: 600;' }, key),
			E('div', { 'style': 'overflow-wrap: anywhere;' }, item.path || '-'),
			E('div', { 'style': 'text-align: right;' }, pill(item.exists ? _('存在') : _('缺失'), !!item.exists))
		]));
	});

	if (!rows.length)
		rows.push(E('div', { 'style': mutedStyle() }, _('未观测到文件状态。')));

	return rows;
}

function commandText() {
	return [
		'/etc/init.d/rpcd restart',
		'sleep 2',
		'rm -rf /tmp/luci-*',
		'/etc/init.d/uhttpd restart',
		'ubus call shinra runtime_healthcheck',
		'ubus call shinra diagnostics_get',
		'ubus call shinra connectivity_probe',
		'ubus call shinra logs_get',
		'ubus call shinra last_error_get',
		'ubus call shinra selector_list | head -c 3000'
	].join('\n');
}

function controlplanePanel() {
	const diagnostics = dataOf(pageResults.diagnostics);
	const runtime = diagnostics.runtime || {};
	const service = diagnostics.service || {};
	const files = diagnostics.files || {};
	const lastError = dataOf(pageResults.lastError);
	const logs = dataOf(pageResults.logs);

	return E('div', {}, [
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('控制面状态')),
			field(_('服务状态'), service.stdout || runtime.service_status || '-'),
			field(_('服务状态码'), service.code),
			field(_('Runtime 配置'), runtime.runtime_config_path || '-'),
			field(_('Runtime Hash'), runtime.runtime_config_hash || '-'),
			field(_('最近应用结果'), runtime.last_apply_result || '-'),
			field(_('检查时间'), shinraTime.formatMaybeTime(runtime.checked_at))
		]),
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('控制面文件')),
			E('div', { 'style': 'display: grid; grid-template-columns: minmax(130px, .8fr) minmax(0, 2fr) 90px; gap: .75rem; color: #667; font-size: 12px; padding-bottom: .4rem; border-bottom: 1px solid #dfe3e8;' }, [
				E('div', {}, _('名称')),
				E('div', {}, _('路径')),
				E('div', { 'style': 'text-align: right;' }, _('状态'))
			]),
			E('div', {}, fileRows(files))
		]),
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('最近错误')),
			E('pre', { 'style': 'white-space: pre-wrap; overflow-wrap: anywhere; min-height: 2.5rem;' }, lastError.content || runtime.recent_error || _('无'))
		]),
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('验收命令')),
			E('textarea', {
				'readonly': 'readonly',
				'style': 'width: 100%; min-height: 180px; box-sizing: border-box; font-family: monospace; white-space: pre;'
			}, commandText())
		]),
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('控制面日志')),
			E('pre', { 'style': 'white-space: pre-wrap; overflow-wrap: anywhere; max-height: 420px; overflow-y: auto;' }, logsText(logs.lines, controlplaneLogs))
		])
	]);
}

function renderPage() {
	const errorPanel = loadErrorPanel();
	const children = [
		pageHeader(_('网络诊断'), _('用于排查控制面任务和数据面接管。高层摘要集中在概览页。')),
		E('div', { 'style': 'display: flex; gap: .5rem; align-items: center; flex-wrap: wrap; margin: 0 0 .75rem;' }, [
			tabButton('dataplane', _('数据面')),
			tabButton('controlplane', _('控制面'))
		])
	];

	if (errorPanel)
		children.push(errorPanel);

	children.push(activeTab === 'dataplane' ? dataplanePanel() : controlplanePanel());

	return E('div', { 'id': 'shinra-diagnostics-root', 'class': 'cbi-map' }, [
		E('div', {}, children)
	]);
}

function redraw() {
	const root = document.getElementById('shinra-diagnostics-root');
	if (root)
		root.parentNode.replaceChild(renderPage(), root);
}

return view.extend({
	load: function() {
		return Promise.all([
			callDiagnosticsGet().catch(function(e) { return { ok: false, message: _('控制面诊断加载失败'), detail: e.message || String(e) }; }),
			callConnectivityProbe().catch(function(e) { return { ok: false, message: _('数据面诊断加载失败'), detail: e.message || String(e) }; }),
			callLastErrorGet().catch(function(e) { return { ok: false, message: _('最近错误加载失败'), detail: e.message || String(e) }; }),
			callLogsGet().catch(function(e) { return { ok: false, message: _('日志加载失败'), detail: e.message || String(e) }; })
		]).then(function(results) {
			return {
				diagnostics: results[0],
				connectivity: results[1],
				lastError: results[2],
				logs: results[3]
			};
		});
	},

	render: function(results) {
		pageResults = results || {};
		return renderPage();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});


