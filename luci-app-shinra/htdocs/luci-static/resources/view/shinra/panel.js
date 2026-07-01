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
		release_api_url: 'https://api.github.com/repos/Zephyruso/zashboard/releases/latest',
		asset_download_base: 'https://github.com/Zephyruso/zashboard/releases/download'
	};
}

function sourceOf() {
	const data = dataOf(sourceResult);
	if (data.source)
		return data.source;
	return dataOf(statusResult).source || {};
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
		release_api_url: repo.release_api_url || defaults.release_api_url,
		asset_download_base: repo.asset_download_base || defaults.asset_download_base
	};
}

function sourceFetchStrategy() {
	return sourceOf().fetch_strategy === 'proxy' ? 'proxy' : 'direct';
}

function lastCheckOf() {
	return sourceOf().last_check || {
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
	return sourceOf().panel_api || {
		enabled: true,
		external_controller: '0.0.0.0:20123',
		secret: '',
		allow_empty_secret: true
	};
}

function sectionStyle() {
	return 'border: 1px solid #dfe3e8; border-radius: 8px; padding: .75rem 1rem; margin: 0 0 .75rem; background: #fff;';
}

function mutedStyle() {
	return 'color: #667; line-height: 1.35; overflow-wrap: anywhere;';
}

function pageHeader(title, description) {
	return E('div', { 'style': sectionStyle() }, [
		E('h2', { 'style': 'margin: 0 0 .35rem; line-height: 1.25;' }, title),
		description ? E('p', { 'style': mutedStyle() + ' margin: 0;' }, description) : ''
	]);
}

function sectionTitle(title) {
	return E('h3', { 'style': 'margin: 0 0 .45rem; line-height: 1.25;' }, title);
}

function sectionDescription(text) {
	return E('div', { 'style': mutedStyle() + ' margin: 0 0 .6rem;' }, text);
}

function fieldLabel(text) {
	return E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin: 0 0 .25rem; line-height: 1.25;' }, text);
}

function panelResponsibilityText() {
	return _('Zashboard 负责策略组切换、URLTest 延迟和实时运行时交互。Shinra 负责面板资源和生成 Clash API 端点。');
}

function valueText(value) {
	if (value == null || value === '')
		return '-';
	return String(value);
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

	return E('div', {
		'id': 'shinra-zashboard-action-status',
		'style': 'display: %s; border: 1px solid %s; border-radius: 8px; padding: .45rem .65rem; background: %s; color: %s; overflow-wrap: anywhere; min-width: min(360px, 100%); flex: 1 1 320px;'.format(
			text ? 'block' : 'none',
			ok ? '#bbf7d0' : '#fecaca',
			ok ? '#f0fdf4' : '#fef2f2',
			ok ? '#166534' : '#991b1b'
		)
	}, text);
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

function inputValue(id, fallback) {
	const node = document.getElementById(id);
	return node ? node.value : fallback || '';
}

function inputChecked(id, fallback) {
	const node = document.getElementById(id);
	return node ? !!node.checked : !!fallback;
}

function collectSource() {
	return {
		schema_version: 1,
		fetch_strategy: inputValue('shinra-zashboard-fetch-strategy', sourceFetchStrategy()) === 'proxy' ? 'proxy' : 'direct',
		repository: {
			type: 'github',
			owner: inputValue('shinra-zashboard-repo-owner', 'Zephyruso'),
			repo: inputValue('shinra-zashboard-repo-name', 'zashboard'),
			asset_pattern: inputValue('shinra-zashboard-asset-pattern', 'dist.zip'),
			release_api_url: inputValue('shinra-zashboard-release-api-url', defaultRepository().release_api_url),
			asset_download_base: inputValue('shinra-zashboard-asset-download-base', defaultRepository().asset_download_base)
		},
		panel_api: {
			enabled: inputChecked('shinra-zashboard-api-enabled', true),
			external_controller: inputValue('shinra-zashboard-api-controller', '0.0.0.0:20123'),
			secret: inputValue('shinra-zashboard-api-secret', ''),
			allow_empty_secret: inputChecked('shinra-zashboard-api-empty-secret', true)
		}
	};
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

function saveSourceContent() {
	return callZashboardSourceSave(JSON.stringify(collectSource())).then(function(result) {
		if (result && result.ok) {
			sourceResult = {
				ok: true,
				data: dataOf(result)
			};
		}
		return result;
	});
}

function saveSource() {
	setStatus(_('正在保存设置...'), true);
	return saveSourceContent().then(function(result) {
		if (result && result.ok) {
			setStatus(_('设置已保存。'), true);
			return refreshPage();
		}

		setStatus(resultMessage(result, _('保存失败')), false);
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function checkUpdate() {
	setStatus(_('正在保存设置并检查最新版本...'), true);
	return saveSourceContent().then(function(saved) {
		if (!saved || !saved.ok)
			return saved;
		return callZashboardUpdateCheck();
	}).then(function(result) {
		if (result && result.ok) {
			const lastCheck = dataOf(result).last_check || {};
			const message = lastCheck.version ? _('已检查最新版本：%s').format(lastCheck.version) : _('已完成最新版本检查。');
			setStatus(message, true);
			return refreshPage();
		}

		setStatus(resultMessage(result, _('操作失败')), false);
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function applyUpdate() {
	setStatus(_('正在保存设置并下载 / 更新面板...'), true);
	return saveSourceContent().then(function(saved) {
		if (!saved || !saved.ok)
			return saved;
		return callZashboardUpdateApply();
	}).then(function(result) {
		if (result && result.ok) {
			setStatus(_('面板已更新。'), true);
			return refreshPage();
		}

		setStatus(resultMessage(result, _('操作失败')), false);
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function tabButton(tab, label) {
	const active = activeTab === tab;

	return E('button', {
		'type': 'button',
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
	return E('div', { 'style': 'display: flex; gap: .5rem; align-items: center; flex-wrap: wrap; margin: 0 0 .75rem;' }, [
		tabButton('zashboard', _('Zashboard')),
		tabButton('manage', _('管理'))
	]);
}

function repositorySettings() {
	const repo = repositoryOf();
	const lastCheck = lastCheckOf();

	return E('div', { 'style': sectionStyle() }, [
		sectionTitle(_('Zashboard 更新源')),
		sectionDescription(_('设置 Zashboard 的发布源。检测更新时读取 Release API，安装时下载匹配的资源文件并部署到 /www/shinra/zashboard。')),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: .75rem;' }, [
			E('label', {}, [
				fieldLabel(_('仓库所有者')),
				E('input', { 'id': 'shinra-zashboard-repo-owner', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'value': repo.owner })
			]),
			E('label', {}, [
				fieldLabel(_('仓库名称')),
				E('input', { 'id': 'shinra-zashboard-repo-name', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'value': repo.repo })
			]),
			E('label', {}, [
				fieldLabel(_('资源文件名')),
				E('input', { 'id': 'shinra-zashboard-asset-pattern', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'value': repo.asset_pattern })
			])
		]),
		E('label', { 'style': 'display: block; margin-top: .6rem;' }, [
			fieldLabel(_('Release API 地址')),
			E('input', { 'id': 'shinra-zashboard-release-api-url', 'class': 'cbi-input-text', 'style': 'width: 100%; max-width: 100%; box-sizing: border-box;', 'placeholder': defaultRepository().release_api_url, 'value': repo.release_api_url })
		]),
		E('label', { 'style': 'display: block; margin-top: .6rem;' }, [
			fieldLabel(_('Release 下载基址')),
			E('input', { 'id': 'shinra-zashboard-asset-download-base', 'class': 'cbi-input-text', 'style': 'width: 100%; max-width: 100%; box-sizing: border-box;', 'placeholder': defaultRepository().asset_download_base, 'value': repo.asset_download_base })
		]),
		E('label', { 'style': 'display: block; margin-top: .6rem;' }, [
			fieldLabel(_('下载策略')),
			E('select', { 'id': 'shinra-zashboard-fetch-strategy', 'class': 'cbi-input-select', 'style': 'min-width: 220px;' }, [
				E('option', { 'value': 'direct', 'selected': sourceFetchStrategy() === 'direct' ? 'selected' : null }, _('直连')),
				E('option', { 'value': 'proxy', 'selected': sourceFetchStrategy() === 'proxy' ? 'selected' : null }, _('代理'))
			])
		]),
		E('div', { 'style': 'display: flex; gap: .5rem; align-items: center; flex-wrap: wrap; margin-top: .7rem;' }, [
			E('button', { 'class': 'btn cbi-button cbi-button-save', 'click': function(ev) { ev.preventDefault(); return saveSource(); } }, _('保存设置')),
			E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function(ev) { ev.preventDefault(); return checkUpdate(); } }, _('检查最新版本')),
			E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': function(ev) { ev.preventDefault(); return applyUpdate(); } }, _('下载 / 更新')),
			inlineResultNode()
		]),
		E('div', { 'style': mutedStyle() + ' margin-top: .6rem;' }, [
			E('div', {}, _('检测结果：') + valueText(lastCheck.result)),
			E('div', {}, _('资源文件：') + valueText(lastCheck.asset_name)),
			E('div', {}, _('下载地址：') + valueText(lastCheck.download_url))
		])
	]);
}

function apiSettings() {
	const api = panelApiOf();

	return E('div', { 'style': sectionStyle() }, [
		sectionTitle(_('Clash API 访问')),
		sectionDescription(_('优先使用模板中的 experimental.clash_api 配置。仅当模板未配置 Clash API 时，才使用这里的设置作为生成兜底。修改后需要重新生成并应用配置。')),
		E('label', { 'style': 'display: flex; align-items: center; gap: .5rem; margin-bottom: .6rem;' }, [
			E('input', { 'id': 'shinra-zashboard-api-enabled', 'type': 'checkbox', 'checked': api.enabled ? 'checked' : null }),
			E('span', {}, _('为 Zashboard 启用局域网 Clash API'))
		]),
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: .75rem;' }, [
			E('label', {}, [
				fieldLabel(_('Clash API 地址')),
				E('input', { 'id': 'shinra-zashboard-api-controller', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'value': api.external_controller || '0.0.0.0:20123' })
			]),
			E('label', {}, [
				fieldLabel(_('访问密钥')),
				E('input', { 'id': 'shinra-zashboard-api-secret', 'class': 'cbi-input-text', 'style': 'width: 100%; box-sizing: border-box;', 'placeholder': _('私有局域网可留空'), 'value': api.secret || '' })
			])
		]),
		E('label', { 'style': 'display: flex; align-items: center; gap: .5rem; margin-top: .6rem;' }, [
			E('input', { 'id': 'shinra-zashboard-api-empty-secret', 'type': 'checkbox', 'checked': api.allow_empty_secret ? 'checked' : null }),
			E('span', {}, _('允许私有局域网使用空密钥'))
		]),
		E('div', { 'style': 'color: #92400e; background: #fef3c7; border-radius: 8px; padding: .65rem; margin-top: .6rem;' },
			_('Zashboard 将使用上方 Clash API 地址：%s。修改后需要重新生成并应用配置。').format(api.external_controller || '0.0.0.0:20123'))
	]);
}

function zashboardPanelFrame() {
	const status = dataOf(statusResult);
	const header = E('div', { 'style': 'display: flex; align-items: center; justify-content: space-between; gap: .5rem; flex-wrap: nowrap; margin-bottom: .5rem;' }, [
		E('h3', { 'style': 'margin: 0; font-size: 16px;' }, _('Zashboard')),
		status.installed ? E('a', {
			'href': '/shinra/zashboard/',
			'target': '_blank',
			'rel': 'noopener noreferrer',
			'title': _('在新标签页打开'),
			'aria-label': _('在新标签页打开'),
			'style': 'display: inline-flex; align-items: center; justify-content: center; width: 32px; height: 32px; border-radius: 999px; border: 1px solid #dfe3e8; background: #f8fafc; color: #334155; text-decoration: none; font-size: 16px; font-weight: 700; line-height: 1;'
		}, '↗') : ''
	]);

	if (!status.installed) {
		return E('div', { 'style': sectionStyle() }, [
			header,
			sectionDescription(panelResponsibilityText()),
			sectionDescription(_('尚未安装 Zashboard 面板。请进入管理页检查最新版本并安装面板资源。')),
			E('button', {
				'class': 'btn cbi-button cbi-button-apply',
				'click': function(ev) {
					ev.preventDefault();
					activeTab = 'manage';
					redraw();
				}
			}, _('前往管理'))
		]);
	}

	return E('div', { 'style': sectionStyle() + ' padding-top: .75rem;' }, [
		header,
		sectionDescription(panelResponsibilityText()),
		E('iframe', {
			'src': '/shinra/zashboard/',
			'style': 'width: 100%; height: min(78vh, 760px); border: 1px solid #dfe3e8; border-radius: 8px; background: #fff;',
			'loading': 'lazy'
		})
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
	return zashboardPanelFrame();
}

function renderPage() {
	return E('div', { 'id': 'shinra-panel-root', 'class': 'cbi-map' }, [
		pageHeader(_('\u9762\u677f'), panelResponsibilityText()),
		tabBar(),
		activeContent()
	]);
}

function redraw() {
	const root = document.getElementById('shinra-panel-root');
	if (root)
		root.parentNode.replaceChild(renderPage(), root);
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
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
