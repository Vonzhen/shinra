'use strict';
'require view';
'require rpc';

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

function dataOf(result) {
	if (result && result.ok && result.data)
		return result.data;
	return {};
}

function sectionStyle() {
	return 'border: 1px solid #dfe3e8; border-radius: 8px; padding: 1rem; margin-bottom: 1rem; background: #fff;';
}

function mutedText() {
	return 'color: #667; overflow-wrap: anywhere;';
}

function field(label, value) {
	return E('div', { 'style': 'display: grid; grid-template-columns: minmax(150px, 1fr) minmax(0, 2fr); gap: .75rem; padding: .45rem 0; border-bottom: 1px solid #eef0f3;' }, [
		E('div', { 'style': 'color: #667;' }, label),
		E('div', { 'style': 'overflow-wrap: anywhere;' }, value == null || value === '' ? '-' : String(value))
	]);
}

function boolText(value) {
	return value ? _('\u65e0') : _('\u65e0');
}

function statusText(value) {
	return value ? _('\u662f') : _('\u5426');
}

function pill(text, ok) {
	return E('span', {
		'style': 'display: inline-flex; align-items: center; min-height: 22px; padding: 0 .55rem; border-radius: 999px; font-size: 12px; font-weight: 700; color: %s; background: %s;'.format(ok ? '#166534' : '#991b1b', ok ? '#dcfce7' : '#fee2e2')
	}, text);
}

function checkRow(label, ok, detail) {
	return E('div', { 'style': 'display: grid; grid-template-columns: minmax(170px, 1fr) 90px minmax(0, 2fr); gap: .75rem; align-items: center; padding: .55rem 0; border-bottom: 1px solid #eef0f3;' }, [
		E('div', { 'style': 'font-weight: 600;' }, label),
		E('div', {}, pill(statusText(ok), ok)),
		E('div', { 'style': mutedText() }, detail || '-')
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

function loadErrorPanel(results) {
	const errors = [];

	(results || []).forEach(function(result) {
		if (result && !result.ok)
			errors.push('%s: %s'.format(result.message || result.code || _('\u672a\u77e5\u9519\u8bef'), result.detail || result.code || _('\u65e0\u8be6\u7ec6\u4fe1\u606f')));
	});

	if (!errors.length)
		return null;

	return E('div', {
		'style': 'border: 1px solid #fecaca; border-left: 4px solid #dc2626; border-radius: 8px; padding: .85rem; margin-bottom: 1rem; background: #fef2f2; color: #7f1d1d;'
	}, [
		E('div', { 'style': 'font-weight: 700; margin-bottom: .35rem;' }, _('\u8bca\u65ad\u52a0\u8f7d\u5f02\u5e38')),
		E('pre', { 'style': 'white-space: pre-wrap; overflow-wrap: anywhere; margin: 0;' }, errors.join('\n'))
	]);
}

function connectivityPanel(probe) {
	probe = probe || {};
	const checks = probe.checks || {};
	const commands = probe.commands || {};
	const selectors = probe.selectors || {};
	const routingOk = !!checks.route_default_uses_tun && !!checks.route_target_uses_tun;

	return E('div', { 'style': sectionStyle() }, [
		E('h3', {}, _('\u672a\u77e5\u9519\u8bef')),
		E('div', { 'style': mutedText() + ' margin-bottom: .85rem;' }, _('\u7528\u4e8e\u6392\u67e5 TUN\u3001\u7b56\u7565\u8868\u3001Clash API \u548c\u7b56\u7565\u7ec4\u53ef\u89c2\u6d4b\u6027\u7684\u6df1\u5ea6\u8def\u7531\u8bc1\u636e\u3002')),
		E('div', { 'style': 'margin-bottom: 1rem;' }, [
			checkRow(_('\u8bca\u65ad\u52a0\u8f7d\u5f02\u5e38'), !!checks.runtime_running, '-'),
			checkRow(_('TUN \u5b58\u5728'), !!checks.tun_present, (probe.runtime && probe.runtime.tun_name) || '-'),
			checkRow(_('\u8868 2022 \u5305\u542b TUN'), !!checks.table_2022_has_tun, '-'),
			checkRow(_('1.1.1.1 \u7ecf TUN \u8def\u7531'), !!checks.route_default_uses_tun, '-'),
			checkRow(_('1.1.1.1 \u4f7f\u7528\u8868 2022'), !!checks.route_default_uses_table_2022, '-'),
			checkRow(_('\u63a2\u6d4b\u76ee\u6807\u7ecf TUN \u8def\u7531'), !!checks.route_target_uses_tun, probe.probe_target || '-'),
			checkRow(_('\u63a2\u6d4b\u76ee\u6807\u4f7f\u7528\u8868 2022'), !!checks.route_target_uses_table_2022, probe.probe_target || '-'),
			checkRow(_('Clash API \u53ef\u8bbf\u95ee'), !!checks.clash_api_available, checks.clash_api_available ? _('ok') : _('api_unreachable')),
			checkRow(_('\u65e0\u8be6\u7ec6\u4fe1\u606f'), !!checks.selector_available, selectors.first_now || selectors.error || '-')
		]),
		E('div', { 'style': 'border: 1px solid #e5e7eb; border-radius: 8px; padding: .85rem; background: #f8fafc; margin-bottom: 1rem;' }, [
			E('div', { 'style': 'font-weight: 700; margin-bottom: .35rem;' }, _('\u89e3\u8bfb')),
			E('div', { 'style': mutedText() }, routingOk && checks.clash_api_available && checks.selector_has_now ?
				_('\u672c\u5730 TUN \u8def\u7531\u3001Clash API \u548c\u7b56\u7565\u7ec4\u72b6\u6001\u5747\u53ef\u89c2\u6d4b\u3002\u5982\u679c\u865a\u62df\u673a\u5916\u90e8\u8fde\u901a\u6027\u4ecd\u5931\u8d25\uff0c\u8bf7\u68c0\u67e5\u4e0a\u6e38\u8def\u7531\u3001\u5d4c\u5957\u4ee3\u7406\u6216\u8f6f\u8def\u7531\u7b56\u7565\u3002') :
				_('\u4e00\u4e2a\u6216\u591a\u4e2a\u672c\u5730\u68c0\u67e5\u5931\u8d25\u3002\u6d4b\u8bd5\u5916\u90e8\u8fde\u901a\u6027\u524d\uff0c\u8bf7\u5148\u67e5\u770b\u4e0b\u9762\u7684\u547d\u4ee4\u8f93\u51fa\u3002'))
		]),
		E('details', { 'open': 'open' }, [
			E('summary', { 'style': 'cursor: pointer; font-weight: 700; margin-bottom: .75rem;' }, _('\u672a\u77e5\u9519\u8bef')),
			commandBlock('ip link show ' + ((probe.runtime && probe.runtime.tun_name) || 'tun0'), commands.tun_link),
			commandBlock('ip rule', commands.ip_rule),
			commandBlock('ip route show table 2022', commands.table_2022),
			commandBlock('ip route get 1.1.1.1', commands.route_1_1_1_1),
			commandBlock('ip route get ' + (probe.probe_target || '1.1.1.1'), commands.route_target)
		])
	]);
}

function runtimeStatePanel(diagnostics) {
	const runtime = (diagnostics && diagnostics.runtime) || {};
	const service = (diagnostics && diagnostics.service) || {};

	return E('details', { 'style': sectionStyle() }, [
		E('summary', { 'style': 'cursor: pointer; font-weight: 700;' }, _('\u539f\u59cb\u8fd0\u884c\u65f6\u72b6\u6001')),
		E('div', { 'style': 'margin-top: .75rem;' }, [
			field(_('\u672a\u77e5\u9519\u8bef'), service.stdout || runtime.service_status || '-'),
			field(_('\u72b6\u6001\u7801'), service.code),
			field(_('\u72b6\u6001\u7801'), boolText(!!runtime.sing_box_running)),
			field(_('TUN'), '%s / %s'.format(runtime.tun_name || '-', boolText(!!runtime.tun_exists))),
			field(_('Clash API'), boolText(!!runtime.clash_api_available)),
			field(_('\u672a\u77e5\u9519\u8bef'), runtime.runtime_config_path || '-'),
			field(_('\u8bca\u65ad\u52a0\u8f7d\u5f02\u5e38'), boolText(!!runtime.runtime_config_exists)),
			field(_('\u8bca\u65ad\u52a0\u8f7d\u5f02\u5e38'), runtime.runtime_config_hash || '-'),
			field(_('\u672a\u77e5\u9519\u8bef'), runtime.last_apply_result || '-'),
			field(_('\u672a\u77e5\u9519\u8bef'), runtime.recent_error || _('\u65e0')),
			field(_('\u672a\u77e5\u9519\u8bef'), runtime.checked_at || '-')
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
		'last_error'
	];
	const seen = {};
	const keys = [];

	order.forEach(function(key) {
		if (files && files[key]) {
			keys.push(key);
			seen[key] = true;
		}
	});

	Object.keys(files || {}).sort().forEach(function(key) {
		if (!seen[key])
			keys.push(key);
	});

	if (!keys.length)
		return [E('div', { 'style': 'color: #667; padding: .35rem 0;' }, _('\u539f\u59cb\u8fd0\u884c\u65f6\u72b6\u6001'))];

	return keys.map(function(key) {
		const item = files[key] || {};
		return E('div', { 'style': 'display: grid; grid-template-columns: minmax(130px, .8fr) minmax(0, 2fr) 90px; gap: .75rem; padding: .5rem 0; border-bottom: 1px solid #eef0f3; align-items: center;' }, [
			E('div', { 'style': 'font-weight: 600;' }, key),
			E('div', { 'style': 'overflow-wrap: anywhere;' }, item.path || '-'),
			E('div', { 'style': 'text-align: right;' }, pill(boolText(item.exists), !!item.exists))
		]);
	});
}

function filesPanel(files) {
	return E('div', { 'style': sectionStyle() }, [
		E('h3', {}, _('\u89e3\u8bfb')),
		E('div', { 'style': mutedText() + ' margin-bottom: .75rem;' }, _('用于排查生成、应用和运行状态的文件路径与存在性检查。')),
		E('div', { 'style': 'display: grid; grid-template-columns: minmax(130px, .8fr) minmax(0, 2fr) 90px; gap: .75rem; color: #667; font-size: 12px; padding-bottom: .4rem; border-bottom: 1px solid #dfe3e8;' }, [
			E('div', {}, _('\u89e3\u8bfb')),
			E('div', {}, _('\u89e3\u8bfb')),
			E('div', { 'style': 'text-align: right;' }, _('\u89e3\u8bfb'))
		]),
		E('div', {}, fileRows(files))
	]);
}

function logText(lines) {
	if (!Array.isArray(lines) || !lines.length)
		return _('\u672a\u89c2\u6d4b\u5230 Shinra \u65e5\u5fd7\u3002');
	return lines.join('\n');
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
		'ubus call shinra selector_list | head -c 3000',
		'grep -o \'\"x_[^\"]*\":\' /etc/shinra/runtime/config.json | head'
	].join('\n');
}

return view.extend({
	load: function() {
		return Promise.all([
			callDiagnosticsGet(),
			callConnectivityProbe(),
			callLastErrorGet(),
			callLogsGet()
		]);
	},

	render: function(results) {
		const diagnosticsResult = results && results[0];
		const connectivityResult = results && results[1];
		const lastErrorResult = results && results[2];
		const logsResult = results && results[3];
		const diagnostics = dataOf(diagnosticsResult);
		const connectivity = dataOf(connectivityResult);
		const lastError = dataOf(lastErrorResult);
		const logs = dataOf(logsResult);
		const files = diagnostics.files || {};
		const lastErrorText = lastError.content || (diagnostics.runtime && diagnostics.runtime.recent_error) || '';
		const loadErrors = loadErrorPanel(results);
		const children = [
			E('h2', {}, _('\u672a\u77e5\u9519\u8bef')),
			E('div', { 'style': mutedText() + ' margin-bottom: 1rem;' }, _('\u7528\u4e8e\u6392\u67e5\u8def\u7531\u3001\u672c\u5730\u8d44\u6e90\u3001\u547d\u4ee4\u8f93\u51fa\u548c\u65e5\u5fd7\u7684\u8fd0\u884c\u65f6\u8bc1\u636e\u3002\u9ad8\u5c42\u72b6\u6001\u6458\u8981\u96c6\u4e2d\u5728\u6982\u89c8\u9875\u3002'))
		];

		if (loadErrors)
			children.push(loadErrors);

		children.push(
			connectivityPanel(connectivity),
			runtimeStatePanel(diagnostics),
			filesPanel(files),
			E('div', { 'style': sectionStyle() }, [
				E('h3', {}, _('\u89e3\u8bfb')),
				E('textarea', {
					'readonly': 'readonly',
					'style': 'width: 100%; min-height: 210px; box-sizing: border-box; font-family: monospace; white-space: pre;'
				}, commandText())
			]),
			E('div', { 'style': sectionStyle() }, [
				E('h3', {}, _('\u672a\u77e5\u9519\u8bef')),
				E('pre', { 'style': 'white-space: pre-wrap; overflow-wrap: anywhere; min-height: 2.5rem;' }, lastErrorText || _('\u65e0'))
			]),
			E('div', { 'style': sectionStyle() }, [
				E('h3', {}, _('\u89e3\u8bfb')),
				E('pre', { 'style': 'white-space: pre-wrap; overflow-wrap: anywhere; max-height: 420px; overflow-y: auto;' }, logText(logs.lines))
			])
		);

		return E('div', { 'class': 'cbi-map' }, [
			E('div', { 'class': 'cbi-section' }, children)
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
