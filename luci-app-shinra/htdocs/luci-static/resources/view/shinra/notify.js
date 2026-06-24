'use strict';
'require view';
'require rpc';

const callNotifySettingsGet = rpc.declare({
	object: 'shinra',
	method: 'notify_settings_get',
	expect: { '': {} }
});

const callNotifySettingsSave = rpc.declare({
	object: 'shinra',
	method: 'notify_settings_save',
	params: [ 'content' ],
	expect: { '': {} }
});

const callNotifyTestTelegram = rpc.declare({
	object: 'shinra',
	method: 'notify_test_telegram',
	expect: { '': {} }
});

let settingsResult = null;
let actionStatus = '';
let actionStatusOk = true;

function setStatus(message, ok) {
	actionStatus = message || '';
	actionStatusOk = ok !== false;
	const node = document.getElementById('shinra-notify-status');
	if (!node)
		return;

	node.textContent = actionStatus;
	node.style.display = actionStatus ? 'block' : 'none';
	node.style.borderColor = actionStatusOk ? '#bbf7d0' : '#fecaca';
	node.style.background = actionStatusOk ? '#f0fdf4' : '#fef2f2';
	node.style.color = actionStatusOk ? '#166534' : '#991b1b';
}

function dataOf(result) {
	if (result && result.ok && result.data)
		return result.data;
	return {};
}

function notifySettings() {
	const data = dataOf(settingsResult);
	const settings = data.settings || {};
	const telegram = settings.telegram || {};

	return {
		schema_version: 1,
		telegram: {
			enabled: telegram.enabled === true,
			mode: telegram.mode === 'all' ? 'all' : 'fail_only',
			bot_token: typeof telegram.bot_token === 'string' ? telegram.bot_token : '',
			chat_id: typeof telegram.chat_id === 'string' ? telegram.chat_id : '',
			location_name: typeof telegram.location_name === 'string' && telegram.location_name !== '' ? telegram.location_name : 'Shinra',
			timeout_sec: Number(telegram.timeout_sec || 15)
		}
	};
}

function sectionStyle() {
	return 'border: 1px solid #dfe3e8; border-radius: 8px; padding: 1rem; margin-bottom: 1rem; background: #fff;';
}

function field(label, input, help) {
	return E('label', { 'style': 'display: block; margin-bottom: .75rem;' }, [
		E('div', { 'style': 'font-size: 12px; color: #667; font-weight: 700; margin-bottom: .25rem;' }, label),
		input,
		help ? E('div', { 'style': 'font-size: 12px; color: #667; margin-top: .25rem;' }, help) : ''
	]);
}

function settingsFromInputs() {
	return {
		schema_version: 1,
		telegram: {
			enabled: document.getElementById('shinra-notify-enabled') ? document.getElementById('shinra-notify-enabled').checked : false,
			mode: document.getElementById('shinra-notify-mode') ? document.getElementById('shinra-notify-mode').value : 'fail_only',
			bot_token: document.getElementById('shinra-notify-token') ? document.getElementById('shinra-notify-token').value : '',
			chat_id: document.getElementById('shinra-notify-chat') ? document.getElementById('shinra-notify-chat').value : '',
			location_name: document.getElementById('shinra-notify-location') ? document.getElementById('shinra-notify-location').value : 'Shinra',
			timeout_sec: document.getElementById('shinra-notify-timeout') ? Number(document.getElementById('shinra-notify-timeout').value || 15) : 15
		}
	};
}

function refreshPage() {
	return callNotifySettingsGet().then(function(result) {
		settingsResult = result;
		redraw();
		return result;
	});
}

function saveSettings() {
	setStatus(_('\u6b63\u5728\u4fdd\u5b58\u901a\u77e5\u8bbe\u7f6e...'), true);
	return callNotifySettingsSave(JSON.stringify(settingsFromInputs())).then(function(result) {
		if (result && result.ok) {
			settingsResult = {
				ok: true,
				data: result.data || {}
			};
			setStatus(_('\u901a\u77e5\u8bbe\u7f6e\u5df2\u4fdd\u5b58\u3002\u81ea\u52a8\u4efb\u52a1\u4f1a\u4f7f\u7528\u8fd9\u4e9b\u8bbe\u7f6e\u3002'), true);
			return result;
		}
		setStatus('%s: %s'.format(result && (result.message || result.code) || _('保存失败'), result && (result.detail || result.code) || _('\u65e0\u8be6\u7ec6\u4fe1\u606f')), false);
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function testTelegram() {
	setStatus(_('\u6d4b\u8bd5\u524d\u6b63\u5728\u4fdd\u5b58\u8bbe\u7f6e...'), true);
	return saveSettings().then(function(saveResult) {
		if (!(saveResult && saveResult.ok))
			return saveResult;
		setStatus(_('\u6b63\u5728\u53d1\u9001 Telegram \u6d4b\u8bd5...'), true);
		return callNotifyTestTelegram();
	}).then(function(result) {
		if (!(result && result.ok !== undefined))
			return result;
		if (result && result.ok)
			setStatus(_('Telegram \u6d4b\u8bd5\u5df2\u53d1\u9001\u3002'), true);
		else {
			setStatus('%s: %s'.format(result && (result.message || result.code) || _('Telegram \u6d4b\u8bd5\u5931\u8d25'), result && (result.detail || result.code) || _('\u65e0\u8be6\u7ec6\u4fe1\u606f')), false);
		}
		return result;
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function renderPage() {
	const settings = notifySettings();
	const tg = settings.telegram;

	return E('div', { 'id': 'shinra-notify-root', 'class': 'cbi-map' }, [
		E('h2', {}, _('\u901a\u77e5')),
		E('p', {}, _('Telegram \u901a\u77e5\u4ec5\u7528\u4e8e\u65e0\u4eba\u503c\u5b88\u7684\u81ea\u52a8\u8d44\u6e90\u66f4\u65b0\uff0c\u4f8b\u5982\u8ba2\u9605\u5237\u65b0\u548c\u89c4\u5219\u96c6\u540c\u6b65\u5931\u8d25\u3002\u624b\u5de5\u64cd\u4f5c\u4e0d\u4f1a\u53d1\u9001\u901a\u77e5\u3002')),
		E('div', { 'style': sectionStyle() }, [
			E('h3', { 'style': 'margin-top: 0;' }, _('Telegram')),
			E('div', {
				'id': 'shinra-notify-status',
				'style': 'display: %s; border: 1px solid %s; border-radius: 8px; padding: .75rem; margin-bottom: 1rem; background: %s; color: %s;'.format(
					actionStatus ? 'block' : 'none',
					actionStatusOk ? '#bbf7d0' : '#fecaca',
					actionStatusOk ? '#f0fdf4' : '#fef2f2',
					actionStatusOk ? '#166534' : '#991b1b'
				)
			}, actionStatus),
			E('label', { 'style': 'display: flex; align-items: center; gap: .5rem; margin-bottom: .75rem;' }, [
				E('input', {
					'id': 'shinra-notify-enabled',
					'type': 'checkbox',
					'checked': tg.enabled ? 'checked' : null
				}),
				E('span', {}, _('\u4e3a\u81ea\u52a8\u8d44\u6e90\u4efb\u52a1\u542f\u7528 Telegram \u901a\u77e5'))
			]),
			field(_('\u901a\u77e5'), E('select', { 'id': 'shinra-notify-mode', 'class': 'cbi-input-select', 'style': 'min-width: 220px;' }, [
				E('option', { 'value': 'fail_only', 'selected': tg.mode === 'fail_only' ? 'selected' : null }, _('\u4ec5\u5931\u8d25')),
				E('option', { 'value': 'all', 'selected': tg.mode === 'all' ? 'selected' : null }, _('\u65e0\u8be6\u7ec6\u4fe1\u606f'))
			]), _('\u65e0\u4eba\u503c\u5b88\u66f4\u65b0\u5efa\u8bae\u53ea\u901a\u77e5\u5931\u8d25\u3002')),
			E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: .75rem;' }, [
				field(_('Bot Token'), E('input', {
					'id': 'shinra-notify-token',
					'class': 'cbi-input-password',
					'type': 'password',
					'style': 'width: 100%; box-sizing: border-box;',
					'value': tg.bot_token || '',
					'placeholder': _('123456:ABC...')
				}), _('\u53ef\u5e26 bot \u524d\u7f00\u3002')),
				field(_('Chat ID'), E('input', {
					'id': 'shinra-notify-chat',
					'class': 'cbi-input-text',
					'style': 'width: 100%; box-sizing: border-box;',
					'value': tg.chat_id || ''
				}), _('\u7528\u6237\u3001\u7fa4\u7ec4\u6216\u9891\u9053 Chat ID\u3002')),
				field(_('\u4f4d\u7f6e\u540d\u79f0'), E('input', {
					'id': 'shinra-notify-location',
					'class': 'cbi-input-text',
					'style': 'width: 100%; box-sizing: border-box;',
					'value': tg.location_name || 'Shinra'
				}), _('\u663e\u793a\u5728\u6d88\u606f\u6807\u9898\u4e2d\u3002')),
				field(_('\u901a\u77e5'), E('input', {
					'id': 'shinra-notify-timeout',
					'class': 'cbi-input-text',
					'type': 'number',
					'min': '5',
					'max': '60',
					'style': 'width: 100%; box-sizing: border-box;',
					'value': tg.timeout_sec || 15
				}), _('\u901a\u77e5'))
			]),
			E('div', { 'style': 'display: flex; gap: .5rem; flex-wrap: wrap; margin-top: .85rem;' }, [
				E('button', { 'class': 'btn cbi-button cbi-button-save', 'click': function(ev) { ev.preventDefault(); return saveSettings(); } }, _('\u4fdd\u5b58\u901a\u77e5\u8bbe\u7f6e')),
				E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': function(ev) { ev.preventDefault(); return testTelegram(); } }, _('\u4fdd\u5b58\u5e76\u53d1\u9001\u6d4b\u8bd5'))
			])
		])
	]);
}

function redraw() {
	const root = document.getElementById('shinra-notify-root');
	if (root)
		root.parentNode.replaceChild(renderPage(), root);
}

return view.extend({
	load: function() {
		return callNotifySettingsGet();
	},

	render: function(result) {
		settingsResult = result;
		return renderPage();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
