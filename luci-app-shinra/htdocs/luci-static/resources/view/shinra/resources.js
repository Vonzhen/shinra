'use strict';
'require view';

let activeTab = 'profile';
let modules = {};
let loaded = {};

const tabs = [
	{ id: 'profile', label: _('模板'), module: 'view.shinra.profile' },
	{ id: 'subscriptions', label: _('\u8ba2\u9605'), module: 'view.shinra.subscriptions' },
	{ id: 'rules', label: _('规则集'), module: 'view.shinra.rulesets' },
	{ id: 'notify', label: _('\u901a\u77e5'), module: 'view.shinra.notify' }
];

function tabById(id) {
	for (let i = 0; i < tabs.length; i++) {
		if (tabs[i].id === id)
			return tabs[i];
	}

	return tabs[0];
}

function loadTab(tab) {
	return L.require(tab.module).then(function(mod) {
		modules[tab.id] = mod;
		if (mod && typeof mod.load === 'function')
			return mod.load().then(function(data) {
				loaded[tab.id] = data;
				return data;
			});

		loaded[tab.id] = null;
		return null;
	}).catch(function(error) {
		modules[tab.id] = null;
		loaded[tab.id] = {
			error: error.message || String(error)
		};
		return loaded[tab.id];
	});
}

function loadAllTabs() {
	return Promise.all(tabs.map(loadTab));
}

function redraw() {
	const root = document.getElementById('shinra-resources-root');
	if (root)
		root.parentNode.replaceChild(renderPage(), root);
}

function tabButton(tab) {
	const active = activeTab === tab.id;

	return E('button', {
		'class': 'btn cbi-button %s'.format(active ? 'cbi-button-apply' : 'cbi-button-neutral'),
		'style': 'min-width: 120px;',
		'click': function(ev) {
			ev.preventDefault();
			activeTab = tab.id;
			redraw();
		}
	}, tab.label);
}

function tabBar() {
	return E('div', { 'style': 'display: flex; gap: .5rem; align-items: center; flex-wrap: wrap; margin: 1rem 0;' }, tabs.map(tabButton));
}

function renderActiveTab() {
	const tab = tabById(activeTab);
	const mod = modules[tab.id];
	const data = loaded[tab.id];

	if (data && data.error) {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, tab.label),
			E('p', { 'style': 'color: #b91c1c;' }, data.error)
		]);
	}

	if (!mod || typeof mod.render !== 'function') {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, tab.label),
			E('p', {}, _('资源标签页不可用。'))
		]);
	}

	return E('div', { 'class': 'shinra-resource-tab' }, [
		mod.render(data)
	]);
}

function renderPage() {
	return E('div', { 'id': 'shinra-resources-root', 'class': 'cbi-map' }, [
		E('h2', {}, _('资源管理')),
		E('p', {}, _('管理模板、订阅源、规则集资源和通知。资源摘要集中显示在概览页。')),
		tabBar(),
		renderActiveTab()
	]);
}

return view.extend({
	load: function() {
		return loadAllTabs();
	},

	render: function() {
		return renderPage();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
