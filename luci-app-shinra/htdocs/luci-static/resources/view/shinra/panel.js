'use strict';
'require view';
'require rpc';

const callZashboardSourceGet = rpc.declare({
	object: 'shinra',
	method: 'zashboard_source_get',
	expect: { '': {} }
});

const callZashboardSourceSave = rpc.declare({
	object: 'shinra',
	method: 'zashboard_source_save',
	params: [ 'content' ],
	expect: { '': {} }
});

const callZashboardStatus = rpc.declare({
	object: 'shinra',
	method: 'zashboard_status',
	expect: { '': {} }
});

const callZashboardUpdateCheck = rpc.declare({
	object: 'shinra',
	method: 'zashboard_update_check',
	expect: { '': {} }
});

const callZashboardUpdateApply = rpc.declare({
	object: 'shinra',
	method: 'zashboard_update_apply',
	expect: { '': {} }
});

let sourceResult = null;
let statusResult = null;
let activeTab = 'zashboard';
let actionStatus = '';
let actionStatusOk = true;

function dataOf(result) {
	if (result && result.ok && result.data)
		return result.data;
	return {};
}

function defaultRepository() {
	return {
		type: 'github',
		owner: 'Zephyruso',
		repo: 'zashboard',
		asset_pattern: 'dist.zip',
		proxy_prefix: 'https://gh-proxy.com/'
	};
}

function sourceOf() {
	const data = dataOf(sourceResult);
	if (data.source)
		return data.source;
	const status = dataOf(statusResult);
	return status.source || {};
}

function repositoryOf() {
	const source = sourceOf();
	const defaults = defaultRepository();
	const repo = source.repository || {};
	return {
		type: repo.type || defaults.type,
		owner: repo.owner || defaults.owner,
		repo: repo.repo || defaults.repo,
		asset_pattern: repo.asset_pattern || defaults.asset_pattern,
		proxy_prefix: repo.proxy_prefix == null ? defaults.proxy_prefix : repo.proxy_prefix
	};
}

function installedOf() {
	const source = sourceOf();
	return source.installed || {
		version: source.version || '',
		updated_at: source.updated_at || ''
	};
}

function lastCheckOf() {
	const source = sourceOf();
	return source.last_check || {
		version: '',
		asset_name: '',
		asset_url: '',
		download_url: '',
		checked_at: '',
		result: '',
		update_available: false
	};
}

function panelApiOf() {
	const source = sourceOf();
	return source.panel_api || {
		enabled: true,
		external_controller: '0.0.0.0:20123',
		secret: '',
		allow_empty_secret: true
	};
}

function resultMessage(result, fallback) {
	if (result && result.ok)
		return fallback || result.message || _('完成');
	if (result && (result.message || result.code))
		return '%s: %s'.format(result.message || result.code || _('未知错误'), result.detail || result.code || _('无详细信息'));
	return fallback || _('\u64cd\u4f5c\u5931\u8d25');
}

function loadErrorMessage() {
	const messages = [];

	[sourceResult, statusResult].forEach(function(result) {
		if (result && !result.ok)
			messages.push('%s: %s'.format(result.message || result.code || _('未知错误'), result.detail || result.code || _('无详细信息')));
	});

	return messages.join('\n');
}

function sectionStyle() {
	return 'border: 1px solid #dfe3e8; border-radius: 8px; padding: 1rem; margin-bottom: 1rem; background: #fff;';
}

function valueText(value) {
	if (value == null || value === '')
		return '-';
	return String(value);
}

function inlineResultNode() {
	const loadError = loadErrorMessage();
	const text = actionStatus || loadError;
	const ok = actionStatus ? actionStatusOk : !loadError;

	return E('div', {
		'id': 'shinra-zashboard-action-status',
		'style': 'display: %s; border: 1px solid %s; border-radius: 8px; padding: .7rem; margin-top: .85rem; background: %s; color: %s; overflow-wrap: anywhere;'.format(
			text ? 'block' : 'none',
			ok ? '#bbf7d0' : '#fecaca',
			ok ? '#f0fdf4' : '#fef2f2',
			ok ? '#166534' : '#991b1b'
		)
	}, text);
}

function repositorySettings() {
	const repo = repositoryOf();
	const lastCheck = lastCheckOf();

	return E('div', { 'style': sectionStyle() }, [
		E('h3', { 'style': 'margin-top: 0;' }, _('\u4fdd\u5b58\u8bbe\u7f6e')),
		E('div', { 'style': 'color: #667; margin-bottom: .75rem; overflow-wrap: anywhere;' }, _('设置 Zashboard GitHub 仓库，检查最新稳定版本，然后下载并安装到 /www/shinra/zashboard。默认仓库为 Zashboard 官方发布源。')),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: .75rem;' }, [
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('所有者')),
				E('input', {
					'id': 'shinra-zashboard-repo-owner',
					'class': 'cbi-input-text',
					'style': 'width: 100%; box-sizing: border-box;',
					'value': repo.owner
				})
			]),
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('完成')),
				E('input', {
					'id': 'shinra-zashboard-repo-name',
					'class': 'cbi-input-text',
					'style': 'width: 100%; box-sizing: border-box;',
					'value': repo.repo
				})
			]),
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('\u4fdd\u5b58\u8bbe\u7f6e')),
				E('input', {
					'id': 'shinra-zashboard-asset-pattern',
					'class': 'cbi-input-text',
					'style': 'width: 100%; box-sizing: border-box;',
					'value': repo.asset_pattern
				})
			])
		]),
		E('label', { 'style': 'display: block; margin-top: .75rem;' }, [
			E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('GitHub 代理前缀')),
			E('input', {
				'id': 'shinra-zashboard-proxy-prefix',
				'class': 'cbi-input-text',
				'style': 'width: 100%; max-width: 100%; box-sizing: border-box;',
				'placeholder': _('https://gh-proxy.com/'),
				'value': repo.proxy_prefix
			})
		]),
		E('div', { 'style': 'display: flex; gap: .5rem; align-items: center; flex-wrap: wrap; margin-top: .85rem;' }, [
			E('button', { 'class': 'btn cbi-button cbi-button-save', 'click': function(ev) { ev.preventDefault(); return saveSource(); } }, _('\u4fdd\u5b58\u8bbe\u7f6e')),
			E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function(ev) { ev.preventDefault(); return checkUpdate(); } }, _('检查最新版本')),
			E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': function(ev) { ev.preventDefault(); return applyUpdate(); } }, _('下载 / 更新'))
		]),
		E('div', { 'style': 'margin-top: .75rem; color: #667; overflow-wrap: anywhere;' }, [
			E('div', {}, _('无详细信息') + valueText(lastCheck.result)),
			E('div', {}, _('无详细信息') + valueText(lastCheck.asset_name)),
			E('div', {}, _('无详细信息') + valueText(lastCheck.download_url))
		])
	]);
}

function apiSettings() {
	const api = panelApiOf();

	return E('div', { 'style': sectionStyle() }, [
		E('h3', { 'style': 'margin-top: 0;' }, _('Clash API 访问')),
		E('div', { 'style': 'color: #667; margin-bottom: .75rem; overflow-wrap: anywhere;' }, _('Zashboard 是默认策略组和运行时面板，因此默认启用局域网 Clash API。修改会影响下一次生成的候选配置，并在应用后生效。')),
		E('label', { 'style': 'display: flex; align-items: center; gap: .5rem; margin-bottom: .75rem;' }, [
			E('input', {
				'id': 'shinra-zashboard-api-enabled',
				'type': 'checkbox',
				'checked': api.enabled ? 'checked' : null
			}),
			E('span', {}, _('为 Zashboard 启用局域网 Clash API'))
		]),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: .75rem;' }, [
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('检查最新版本')),
				E('input', {
					'id': 'shinra-zashboard-api-controller',
					'class': 'cbi-input-text',
					'style': 'width: 100%; box-sizing: border-box;',
					'value': api.external_controller || '0.0.0.0:20123'
				})
			]),
			E('label', {}, [
				E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, _('完成')),
				E('input', {
					'id': 'shinra-zashboard-api-secret',
					'class': 'cbi-input-text',
					'style': 'width: 100%; box-sizing: border-box;',
					'value': api.secret || '',
					'placeholder': _('私有局域网可留空')
				})
			])
		]),
		E('label', { 'style': 'display: flex; align-items: center; gap: .5rem; margin-top: .75rem;' }, [
			E('input', {
				'id': 'shinra-zashboard-api-empty-secret',
				'type': 'checkbox',
				'checked': api.allow_empty_secret !== false ? 'checked' : null
			}),
			E('span', {}, _('允许私有局域网空密钥'))
		]),
		E('div', { 'style': 'color: #92400e; background: #fef3c7; border-radius: 8px; padding: .65rem; margin-top: .75rem;' }, _('在 Zashboard 中使用这个 API 地址：http://<router-lan-ip>:20123。私有局域网可留空密钥。修改后需要生成并应用配置。'))
	]);
}

function panelFrame() {
	const status = dataOf(statusResult);
	if (!status.installed) {
		return E('div', { 'style': sectionStyle() }, [
			E('h3', { 'style': 'margin-top: 0;' }, _('Zashboard')),
			E('div', { 'style': 'color: #667; margin-bottom: .85rem;' }, _('尚未安装 Zashboard 面板。请进入管理页检查最新版本并安装面板资源。')),
			E('button', {
				'class': 'btn cbi-button cbi-button-apply',
				'click': function(ev) {
					ev.preventDefault();
					activeTab = 'manage';
					redraw();
				}
			}, _('\u4fdd\u5b58\u8bbe\u7f6e'))
		]);
	}

	return E('div', { 'style': sectionStyle() + ' padding-top: .75rem;' }, [
		E('div', { 'style': 'display: flex; align-items: center; justify-content: space-between; gap: .5rem; flex-wrap: nowrap; margin-bottom: .5rem;' }, [
			E('h3', { 'style': 'margin: 0; font-size: 16px;' }, _('Zashboard')),
			E('a', {
				'href': '/shinra/zashboard/',
				'target': '_blank',
				'rel': 'noopener noreferrer',
				'title': _('在新标签页打开'),
				'aria-label': _('在新标签页打开'),
				'style': 'display: inline-flex; align-items: center; justify-content: center; width: 32px; height: 32px; border-radius: 999px; border: 1px solid #dfe3e8; background: #f8fafc; color: #334155; text-decoration: none; font-size: 16px; font-weight: 700; line-height: 1;'
			}, '↗')
		]),
		E('iframe', {
			'src': '/shinra/zashboard/',
			'style': 'width: 100%; height: min(78vh, 760px); border: 1px solid #dfe3e8; border-radius: 8px; background: #fff;',
			'loading': 'lazy'
		})
	]);
}

function setStatus(text, ok) {
	actionStatus = text || '';
	actionStatusOk = ok !== false;
	const node = document.getElementById('shinra-zashboard-action-status');
	if (!node)
		return;

	node.textContent = actionStatus;
	node.style.display = actionStatus ? 'block' : 'none';
	node.style.borderColor = actionStatusOk ? '#bbf7d0' : '#fecaca';
	node.style.background = actionStatusOk ? '#f0fdf4' : '#fef2f2';
	node.style.color = actionStatusOk ? '#166534' : '#991b1b';
}

function refreshPage() {
	return Promise.all([
		callZashboardSourceGet(),
		callZashboardStatus()
	]).then(function(results) {
		sourceResult = results && results[0] ? results[0] : {};
		statusResult = results && results[1] ? results[1] : {};
		redraw();
		return results;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function sourceFromInputs() {
	const current = sourceOf();
	const installed = installedOf();
	const lastCheck = lastCheckOf();
	return {
		schema_version: 1,
		url: current.url || '',
		repository: {
			type: 'github',
			owner: document.getElementById('shinra-zashboard-repo-owner') ? document.getElementById('shinra-zashboard-repo-owner').value : 'Zephyruso',
			repo: document.getElementById('shinra-zashboard-repo-name') ? document.getElementById('shinra-zashboard-repo-name').value : 'zashboard',
			asset_pattern: document.getElementById('shinra-zashboard-asset-pattern') ? document.getElementById('shinra-zashboard-asset-pattern').value : 'dist.zip',
			proxy_prefix: document.getElementById('shinra-zashboard-proxy-prefix') ? document.getElementById('shinra-zashboard-proxy-prefix').value : 'https://gh-proxy.com/'
		},
		installed: installed,
		last_check: lastCheck,
		panel_api: {
			enabled: document.getElementById('shinra-zashboard-api-enabled') ? document.getElementById('shinra-zashboard-api-enabled').checked : true,
			external_controller: document.getElementById('shinra-zashboard-api-controller') ? document.getElementById('shinra-zashboard-api-controller').value : '0.0.0.0:20123',
			secret: document.getElementById('shinra-zashboard-api-secret') ? document.getElementById('shinra-zashboard-api-secret').value : '',
			allow_empty_secret: document.getElementById('shinra-zashboard-api-empty-secret') ? document.getElementById('shinra-zashboard-api-empty-secret').checked : true
		}
	};
}

function saveSource() {
	setStatus(_('正在处理...'), true);
	return callZashboardSourceSave(JSON.stringify(sourceFromInputs())).then(function(result) {
		if (result && result.ok) {
			setStatus('\u9762\u677f\u8bbe\u7f6e\u5df2\u4fdd\u5b58\u3002', true);
			return refreshPage().then(function() {
				return result;
			});
		}

		setStatus(resultMessage(result, _('\u64cd\u4f5c\u5931\u8d25')), false);
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function checkUpdate() {
	setStatus(_('正在处理...'), true);
	return saveSource().then(function(saved) {
		if (!saved || !saved.ok)
			return saved;
		return callZashboardUpdateCheck();
	}).then(function(result) {
		if (result && result.ok) {
			let data = dataOf(result);
			let lastCheck = data.last_check || {};
			let message = lastCheck.version ? _('已检查最新版本：%s').format(lastCheck.version) : _('私有局域网可留空');
			setStatus(message, true);
			return refreshPage();
		}

		setStatus(resultMessage(result, _('\u64cd\u4f5c\u5931\u8d25')), false);
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function applyUpdate() {
	setStatus(_('正在处理...'), true);
	return saveSource().then(function(saved) {
		if (!saved || !saved.ok)
			return saved;
		return callZashboardUpdateApply();
	}).then(function(result) {
		if (result && result.ok) {
			setStatus('\u9762\u677f\u5df2\u66f4\u65b0\u3002', true);
			return refreshPage();
		}

		setStatus(resultMessage(result, _('\u64cd\u4f5c\u5931\u8d25')), false);
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function redraw() {
	const root = document.getElementById('shinra-panel-root');
	if (root)
		root.parentNode.replaceChild(renderPage(), root);
}

function tabButton(tab, label) {
	const active = activeTab === tab;
	return E('button', {
		'class': 'btn cbi-button %s'.format(active ? 'cbi-button-apply' : 'cbi-button-neutral'),
		'style': 'min-width: 120px;',
		'click': function(ev) {
			ev.preventDefault();
			activeTab = tab;
			redraw();
		}
	}, label);
}

function tabBar() {
	return E('div', { 'style': 'display: flex; gap: .5rem; align-items: center; flex-wrap: wrap; margin: 1rem 0;' }, [
		tabButton('zashboard', _('Zashboard')),
		tabButton('manage', _('\u7ba1\u7406'))
	]);
}

function zashboardTab() {
	return E('div', {}, [
		panelFrame()
	]);
}

function manageTab() {
	return E('div', {}, [
		repositorySettings(),
		apiSettings()
	]);
}

function activeContent() {
	if (activeTab === 'manage')
		return manageTab();
	return zashboardTab();
}

function renderPage() {
	return E('div', { 'id': 'shinra-panel-root', 'class': 'cbi-map' }, [
		E('h2', {}, _('\u9762\u677f')),
		E('p', {}, _('Zashboard 负责策略组切换、URLTest 延迟和实时运行时交互。Shinra 负责面板资源和生成 Clash API 端点。')),
		tabBar(),
		inlineResultNode(),
		activeContent()
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			callZashboardSourceGet(),
			callZashboardStatus()
		]);
	},

	render: function(results) {
		sourceResult = results && results[0] ? results[0] : {};
		statusResult = results && results[1] ? results[1] : {};

		return renderPage();
	}
});
