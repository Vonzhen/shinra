'use strict';
'require view';

let activeTab = 'profile';
let modules = {};
let loaded = {};

const tabs = [
	{ id: 'profile', label: _('\u6a21\u677f'), module: 'view.shinra.profile' },
	{ id: 'subscriptions', label: _('\u8ba2\u9605'), module: 'view.shinra.subscriptions' },
	{ id: 'rules', label: _('\u89c4\u5219\u96c6'), module: 'view.shinra.rulesets' },
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
		if (mod && typeof mod.load === 'function') {
			return mod.load().then(function(data) {
				loaded[tab.id] = data;
				return data;
			});
		}

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
		'type': 'button',
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
	return E('div', {
		'style': 'display: flex; gap: .5rem; align-items: center; flex-wrap: wrap; margin: 1rem 0;'
	}, tabs.map(tabButton));
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
			E('p', {}, _('\u8be5\u8d44\u6e90\u9875\u6682\u4e0d\u53ef\u7528\u3002'))
		]);
	}

	return E('div', { 'class': 'shinra-resource-tab' }, [
		mod.render(data)
	]);
}

function renderPage() {
	return E('div', { 'id': 'shinra-resources-root', 'class': 'cbi-map' }, [
		E('h2', {}, _('\u8d44\u6e90\u7ba1\u7406')),
		E('p', {}, _('\u7ba1\u7406\u6a21\u677f\u3001\u8ba2\u9605\u6e90\u3001\u89c4\u5219\u96c6\u548c\u81ea\u52a8\u4efb\u52a1\u901a\u77e5\u3002\u4fdd\u5b58\u53ea\u5199\u5165\u8bbe\u7f6e\uff1b\u5237\u65b0\u3001\u540c\u6b65\u548c\u66f4\u65b0\u53ef\u80fd\u4f5c\u4e3a\u540e\u53f0\u4efb\u52a1\u8fd0\u884c\u3002')),
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
