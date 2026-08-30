'use strict';
'require view';
'require rpc';
'require shinra.time as shinraTime';
'require shinra.ui as shinraUi';
'require shinra.motion as shinraMotion';

const callOverviewStatus = rpc.declare({
	object: 'shinra',
	method: 'overview_status',
	expect: { '': {} }
});

const callGenerate = rpc.declare({
	object: 'shinra',
	method: 'config_generate',
	expect: { '': {} }
});

const callCheck = rpc.declare({
	object: 'shinra',
	method: 'config_check_candidate',
	expect: { '': {} }
});

const callApply = rpc.declare({
	object: 'shinra',
	method: 'config_apply',
	expect: { '': {} }
});

const callStop = rpc.declare({
	object: 'shinra',
	method: 'runtime_stop',
	expect: { '': {} }
});

const callRestart = rpc.declare({
	object: 'shinra',
	method: 'runtime_restart',
	expect: { '': {} }
});

const callRollback = rpc.declare({
	object: 'shinra',
	method: 'config_rollback',
	expect: { '': {} }
});

let pageResults = {};
let actionStatus = '';
let actionStatusOk = true;
let supplementalLoading = false;
let supplementalLoadSeq = 0;

function stateOf() {
	const data = shinraUi.dataOf(pageResults.runtime);
	return data.state || {};
}

function safeJson(text) {
	try {
		return JSON.parse(text || '{}');
	} catch (e) {
		return {};
	}
}

function routerHostUrl(url) {
	url = shinraUi.valueText(url);
	if (url === '-')
		return url;
	return url.replace('://<router-host>', '://%s'.format(window.location.hostname || 'router-host'));
}

function cardStyle(accent, clickable) {
	return 'border: 1px solid #dfe3e8; border-left: 4px solid %s; border-radius: 8px; padding: .65rem .75rem; background: #fff; box-sizing: border-box; min-height: 76px;%s'.format(
		accent || '#64748b',
		clickable ? ' display: block; color: inherit; text-decoration: none; cursor: pointer;' : ''
	);
}

function externalLinkIcon() {
	const icon = E('span', { 'style': 'display: flex; align-items: center; justify-content: center;' });
	icon.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="currentColor" viewBox="0 0 16 16"><path fill-rule="evenodd" d="M8.636 3.5a.5.5 0 0 0-.5-.5H1.5A1.5 1.5 0 0 0 0 4.5v10A1.5 1.5 0 0 0 1.5 16h10a1.5 1.5 0 0 0 1.5-1.5V7.864a.5.5 0 0 0-1 0V14.5a.5.5 0 0 1-.5.5h-10a.5.5 0 0 1-.5-.5v-10a.5.5 0 0 1 .5-.5h6.636a.5.5 0 0 0 .5-.5z"/><path fill-rule="evenodd" d="M16 .5a.5.5 0 0 0-.5-.5h-5a.5.5 0 0 0 0 1h3.793L6.146 9.146a.5.5 0 1 0 .708.708L15 1.707V5.5a.5.5 0 0 0 1 0v-5z"/></svg>';
	return icon;
}

function card(title, value, detail, accent, href, action) {
	const detailContent = typeof detail === 'string' || detail == null ? shinraUi.valueText(detail) : detail;
	const tag = href && !action ? 'a' : 'div';
	const attrs = {
		'class': shinraMotion.cardClass(null, !!href),
		'style': cardStyle(accent, !!href) + (action ? ' position: relative; padding-right: 2.6rem;' : '')
	};
	if (href)
		if (action) {
			attrs.role = 'link';
			attrs.tabindex = '0';
			attrs.click = function(ev) {
				window.location.href = href;
			};
			attrs.keydown = function(ev) {
				if (ev.key === 'Enter' || ev.key === ' ') {
					ev.preventDefault();
					window.location.href = href;
				}
			};
		} else {
			attrs.href = href;
		}

	const children = [
		E('div', { 'style': 'font-size: 11px; color: #667; text-transform: uppercase; letter-spacing: .04em;' }, title),
		E('div', { 'style': 'font-size: 19px; font-weight: 700; margin-top: .2rem; line-height: 1.15; overflow-wrap: anywhere;' }, shinraUi.valueText(value)),
		E('div', { 'style': 'margin-top: .35rem; color: #667; font-size: 12px; line-height: 1.3; overflow-wrap: anywhere;' }, detailContent)
	];

	if (action)
		children.push(action);

	return E(tag, attrs, children);
}

function statusTone(ok, warning) {
	if (ok)
		return '#16a34a';
	if (warning)
		return '#ea580c';
	return '#dc2626';
}

function statusWord(status) {
	if (status === 'success')
		return _('成功');
	if (status === 'partial')
		return _('部分成功');
	if (status === 'fail')
		return _('失败');
	if (status === 'failed')
		return _('失败');
	if (status === 'running')
		return _('运行中');
	if (status === 'starting')
		return _('启动中');
	if (status === 'idle')
		return _('空闲');
	if (status)
		return status;
	return '-';
}

function taskMetaOf(result) {
	const data = shinraUi.dataOf(result);
	return data.task_meta && typeof data.task_meta === 'object' ? data.task_meta : {};
}

function taskDisplayName(result, fallback) {
	const meta = taskMetaOf(result);
	return meta.display_name || fallback || _('后台任务');
}

function compactMessage(text) {
	text = shinraUi.valueText(text);
	text = text.replace(/Required Rule Sets downloaded/g, '所需规则集已同步');
	text = text.replace(/Rule Set sync running/g, '规则集正在同步');
	text = text.replace(/Rule Set sync queued/g, '规则集同步已排队');
	text = text.replace(/Rule Set sync job started/g, '规则集同步任务已启动');
	text = text.replace(/Rule Set sync job is already running/g, '规则集同步任务正在运行');
	text = text.replace(/Rule Set sync success/g, '规则集同步成功');
	text = text.replace(/Rule Set sync partial/g, '规则集部分同步成功');
	text = text.replace(/Rule Set sync fail/g, '规则集同步失败');
	text = text.replace(/Required:/g, '需要:');
	text = text.replace(/Updated:/g, '已更新:');
	text = text.replace(/Unchanged:/g, '未变化:');
	text = text.replace(/Failed:/g, '失败:');
	text = text.replace(/Detail:/g, '详情:');
	text = text.replace(/\n/g, ' | ');
	return text;
}

function schedulerTaskText(schedulerTask, task, disabledText, waitingText) {
	schedulerTask = schedulerTask || {};
	task = task || {};
	if (task.status && task.status !== 'idle')
		return _('%s 于 %s').format(statusWord(task.status), shinraTime.formatMaybeTime(task.finished_at || task.started_at));
	if (schedulerTask.last_trigger_result && schedulerTask.last_trigger_result !== 'waiting')
		return _('%s 于 %s').format(schedulerTask.last_trigger_result, shinraTime.formatMaybeTime(schedulerTask.last_run_at));
	if (schedulerTask.enabled)
		return waitingText || _('等待调度');
	return disabledText || _('自动调度已停用');
}

function backgroundTaskText(taskName, schedulerTask, task, disabledText, waitingText) {
	const text = schedulerTaskText(schedulerTask, task, disabledText, waitingText);
	return taskName ? _('%s：%s').format(taskName, text) : text;
}

function autoApplySummary(task) {
	const meta = task && task.meta || {};
	const autoApply = meta.auto_apply || {};
	if (autoApply.attempted !== true)
		return '';
	if (autoApply.ok === true && autoApply.stage === 'stable_success')
		return _('自动应用：sing-box 运行正常');
	if (autoApply.stage === 'rollback_success')
		return _('自动应用：已回滚，sing-box 运行正常');
	if (autoApply.stage === 'rollback_degraded')
		return _('自动应用：异常，请检查');
	if (autoApply.ok === false)
		return _('自动应用：失败，请检查');
	return '';
}

function schedulerWarning(scheduler, enabled) {
	scheduler = scheduler || {};
	if (!enabled)
		return '';
	if (scheduler.healthy)
		return '';
	if (!scheduler.script_exists)
		return _('自动调度器脚本缺失');
	if (!scheduler.script_executable)
		return _('自动调度器脚本不可执行');
	if (!scheduler.cron_installed)
		return _('系统计划任务未安装');
	if (!scheduler.cron_running)
		return _('cron 未运行');
	return _('自动调度器异常');
}

function schedulerPlanText(enabled, hour) {
	if (!enabled)
		return _('自动调度已停用');
	if (hour == null || hour === '')
		return _('已启用，等待调度');
	hour = Number(hour);
	if (!Number.isFinite(hour))
		return _('已启用，等待调度');
	return _('每日 %s:05 检查执行').format(hour < 10 ? '0' + hour : String(hour));
}

function operationButton(label, actionLabel, rpcCall, buttonClass, confirmText) {
	return E('button', {
		'class': shinraMotion.buttonClass('btn cbi-button %s'.format(buttonClass || 'cbi-button-neutral')),
		'style': 'min-width: 5.5rem; padding-left: 1rem; padding-right: 1rem;',
		'click': function(ev) {
			ev.preventDefault();
			return runAction(actionLabel, rpcCall, confirmText);
		}
	}, label);
}

function resourceHref(tab) {
	return L.url('admin/services/shinra/resources') + '?tab=' + encodeURIComponent(tab);
}

function setActionStatus(text, ok) {
	actionStatus = text || '';
	actionStatusOk = ok !== false;
	shinraUi.paintStatus('shinra-overview-action-status', actionStatus, actionStatusOk ? 'ok' : 'error');
}

function resultError(result, fallback) {
	if (result && (result.message || result.code))
		return '%s: %s'.format(result.message || result.code || fallback || _('操作失败'), result.detail || result.code || _('无详细信息'));
	return fallback || _('操作失败');
}

function pageLoadError() {
	const failures = [
		pageResults.runtime,
		pageResults.profile,
		pageResults.subscriptions,
		pageResults.snapshot,
		pageResults.rules,
		pageResults.panel,
		pageResults.apiStatus,
		pageResults.profileSource,
		pageResults.rulesPolicy,
		pageResults.notify,
		pageResults.autoTask,
		pageResults.subscriptionTask,
		pageResults.rulesetTask
	].filter(function(result) {
		return result && !result.ok;
	});

	if (!failures.length)
		return '';

	return failures.map(function(result) {
		return resultError(result, _('加载失败'));
	}).join(' | ');
}

function runAction(label, rpcCall, confirmText) {
	if (confirmText && !window.confirm(confirmText))
		return Promise.resolve();

	setActionStatus(_('%s 正在执行...').format(label), true);

	return rpcCall().then(function(result) {
		if (result && result.ok) {
			setActionStatus(_('%s 已完成。').format(label), true);
			return refreshPage();
		}
		setActionStatus(resultError(result, _('%s 失败').format(label)), false);
		return result;
	}).catch(function(error) {
		setActionStatus(error.message || String(error), false);
	});
}

function refreshPage() {
	return loadAll().then(function(results) {
		supplementalLoadSeq++;
		supplementalLoading = false;
		pageResults = results;
		redraw();
		return results;
	});
}

function overviewItem(items, key, fallback) {
	return items && items[key] ? items[key] : {
		ok: false,
		message: fallback || _('加载失败'),
		detail: key
	};
}

function loadAll() {
	return callOverviewStatus().then(function(result) {
		const items = shinraUi.dataOf(result).items || {};
		return {
			runtime: overviewItem(items, 'runtime', _('Runtime 状态加载失败')),
			profile: overviewItem(items, 'profile', _('模板加载失败')),
			subscriptions: overviewItem(items, 'subscriptions', _('订阅加载失败')),
			snapshot: overviewItem(items, 'snapshot', _('节点快照摘要加载失败')),
			rules: overviewItem(items, 'rules', _('规则集清单加载失败')),
			panel: overviewItem(items, 'dashboard', _('面板状态加载失败')),
			apiStatus: overviewItem(items, 'api', _('API 状态加载失败')),
			profileSource: overviewItem(items, 'profile_source', _('模板源加载失败')),
			rulesPolicy: overviewItem(items, 'rules_policy', _('规则集策略加载失败')),
			notify: overviewItem(items, 'notify', _('通知设置加载失败')),
			autoTask: overviewItem(items, 'scheduler', _('自动调度器状态加载失败')),
			subscriptionTask: overviewItem(items, 'subscription_task', _('订阅刷新后台任务状态加载失败')),
			rulesetTask: overviewItem(items, 'ruleset_task', _('规则集同步后台任务状态加载失败'))
		};
	}).catch(function(e) {
		const failed = { ok: false, message: _('Overview 状态加载失败'), detail: e.message || String(e) };
		return {
			runtime: failed,
			profile: failed,
			subscriptions: failed,
			snapshot: failed,
			rules: failed,
			panel: failed,
			apiStatus: failed,
			profileSource: failed,
			rulesPolicy: failed,
			notify: failed,
			autoTask: failed,
			subscriptionTask: failed,
			rulesetTask: failed
		};
	});
}

function hasSupplementalData() {
	return true;
}

function loadSupplemental() {
}

function ensureSupplementalLoad() {
}

function runtimeCards() {
	const state = stateOf();
	const status = shinraUi.dataOf(pageResults.apiStatus);
	const official = status.official_api || {};
	const clash = status.clash_api || {};
	const running = !!state.sing_box_running;
	const tun = !!state.tun_exists;
	const config = !!state.runtime_config_exists;
	const officialObserved = official.available != null || official.configured != null;
	const clashObserved = clash.available != null || clash.configured != null;
	const apiObserved = officialObserved || clashObserved;
	const officialOk = official.available === true;
	const clashOk = clash.available === true;
	let apiValue = _('未观测');
	let apiAccent = '#64748b';

	if (apiObserved) {
		if (officialOk && clashOk) {
			apiValue = _('全部可用');
			apiAccent = '#16a34a';
		} else if (officialOk || clashOk) {
			apiValue = _('部分可用');
			apiAccent = '#ea580c';
		} else {
			apiValue = _('不可用');
			apiAccent = '#dc2626';
		}
	}

	return E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: .65rem;' }, [
		card(_('运行时'), running ? _('运行中') : _('已停止'), running ? _('sing-box 服务运行中') : _('服务已停止'), statusTone(running)),
		card(_('TUN'), tun ? _('存在') : _('缺失'), state.tun_name || '-', statusTone(tun, running)),
		card(_('配置'), config ? _('就绪') : _('缺失'), state.runtime_config_hash ? _('已观测到运行配置哈希') : _('运行配置缺失'), statusTone(config)),
		card(_('API'), apiValue, _('Official API: %s | Clash API: %s').format(officialObserved ? (officialOk ? _('可用') : _('不可用')) : '-', clashObserved ? (clashOk ? _('可用') : _('不可用')) : '-'), apiAccent)
	]);
}

function resourceCards() {
	const profile = shinraUi.dataOf(pageResults.profile);
	const subscriptions = safeJson(shinraUi.dataOf(pageResults.subscriptions).content || '{}');
	const snapshot = shinraUi.dataOf(pageResults.snapshot);
	const rules = shinraUi.dataOf(pageResults.rules).summary || {};
	const panel = shinraUi.dataOf(pageResults.panel);
	const panelSource = panel.source || {};
	const panelDashboard = panel.dashboard || panelSource.dashboard || {};
	const profileSource = shinraUi.dataOf(pageResults.profileSource).source || {};
	const rulesPolicy = shinraUi.dataOf(pageResults.rulesPolicy).policy || {};
	const notifyData = shinraUi.dataOf(pageResults.notify);
	const notifySettings = notifyData.settings || {};
	const notifyTelegram = notifySettings.telegram || {};
	const notifyState = notifyData.state || {};
	const autoTaskData = shinraUi.dataOf(pageResults.autoTask);
	const autoTask = autoTaskData.state || {};
	const scheduler = autoTaskData.scheduler || {};
	const schedulerTasks = autoTask.tasks || {};
	const subSchedulerTask = schedulerTasks['subscription.refresh'] || {};
	const rulesSchedulerTask = schedulerTasks['ruleset.sync'] || {};
	const subTask = shinraUi.dataOf(pageResults.subscriptionTask).task || {};
	const rulesTask = shinraUi.dataOf(pageResults.rulesetTask).task || {};
	const subTaskName = taskDisplayName(pageResults.subscriptionTask, _('订阅刷新任务'));
	const rulesTaskName = taskDisplayName(pageResults.rulesetTask, _('规则集同步任务'));
	const sourceCount = Array.isArray(subscriptions.sources) ? subscriptions.sources.length : 0;
	const nodeCount = Number(snapshot.node_count || 0);
	const missingRules = Number(rules.missing_count || 0);
	const requiredRules = Number(rules.required_count || 0);
	const readyRules = Number(rules.ready_count || 0);
	const extraRules = Number(rules.local_extra_count || 0);
	const profileOk = pageResults.profile && pageResults.profile.ok && profile.valid !== false;
	const profileSyncTime = profileSource.updated_at ? shinraTime.formatMaybeTime(profileSource.updated_at) : _('未记录');
	const profileSourceText = profileSource.url ? _('已配置远程源') : _('未配置远程源');
	const snapshotTime = snapshot.updated_at ? shinraTime.formatMaybeTime(snapshot.updated_at) : _('未刷新');
	const subUpdate = subscriptions.subscription_update || {};
	const subScheduleWarning = schedulerWarning(scheduler, subUpdate.auto_update === true);
	const subAutoText = subScheduleWarning || backgroundTaskText(subTaskName, subSchedulerTask, subTask, _('自动刷新已停用'), schedulerPlanText(true, subUpdate.update_hour));
	const rulesTimeRaw = rulesTask.finished_at || rulesTask.started_at || rulesSchedulerTask.last_run_at || '';
	const rulesTime = rulesTimeRaw ? shinraTime.formatMaybeTime(rulesTimeRaw) : _('未同步');
	const rulesScheduleWarning = schedulerWarning(scheduler, rulesPolicy.auto_update === true);
	const rulesResultText = rulesScheduleWarning || compactMessage(backgroundTaskText(rulesTaskName, rulesSchedulerTask, rulesTask, _('自动同步已停用'), schedulerPlanText(true, rulesPolicy.update_hour)));
	const rulesMode = rulesPolicy.mode || '-';
	const rulesAutoApplyText = autoApplySummary(rulesTask);
	const rulesDetailText = _('上次同步：%s | 需要 %d / 已就绪 %d / 缺失 %d / 本地多余 %d | %s | %s%s').format(
		rulesTime,
		requiredRules,
		readyRules,
		missingRules,
		extraRules,
		rulesMode,
		rulesResultText,
		rulesAutoApplyText ? ' | ' + rulesAutoApplyText : ''
	);
	const panelReady = panelSource.enabled == true && panelDashboard.enabled == true;
	const panelUrl = routerHostUrl(panel.dashboard_url);
	const panelDetail = _('%s | %s').format(panelUrl !== '-' ? _('Dashboard 已托管') : _('Dashboard 地址未知'), panelDashboard.path || '-');
	const panelAction = panelUrl !== '-' ? E('a', {
			'class': shinraMotion.iconButtonClass(),
			'href': panelUrl,
			'target': '_blank',
			'rel': 'noopener noreferrer',
			'title': _('打开 Dashboard'),
			'aria-label': _('打开 Dashboard'),
			'style': 'position: absolute; top: .55rem; right: .6rem; display: inline-flex; align-items: center; justify-content: center; width: 28px; height: 28px; border-radius: 999px; border: 1px solid #dfe3e8; background: #f8fafc; color: #334155; text-decoration: none;',
			'click': function(ev) {
				ev.preventDefault();
				ev.stopPropagation();
				window.open(panelUrl, '_blank', 'noopener');
			}
		}, externalLinkIcon()) : null;
	const notifyEnabled = notifyTelegram.enabled == true;
	const notifyStatus = notifyState.last_status || (notifyEnabled ? _('等待中') : _('已停用'));
	const notifyResult = notifyState.last_attempt_at ? _('%s 于 %s').format(notifyState.last_sent ? _('已发送') : _('未发送'), shinraTime.formatMaybeTime(notifyState.last_attempt_at)) : (notifyEnabled ? _('未记录发送尝试') : _('Telegram 已停用'));
	let notifyAccent = '#64748b';
	if (notifyEnabled)
		notifyAccent = statusTone(notifyState.last_sent == true, !notifyState.last_attempt_at);

	return E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: .65rem;' }, [
		card(_('模板'), profileOk ? _('就绪') : _('错误'), _('上次同步：%s | %s').format(profileSyncTime, profileSourceText), statusTone(profileOk), resourceHref('profile')),
		card(_('订阅'), nodeCount ? _('%d 个节点').format(nodeCount) : _('无节点'), _('上次刷新：%s | %s').format(snapshotTime, subAutoText), subScheduleWarning ? '#ea580c' : statusTone(sourceCount > 0 && nodeCount > 0, sourceCount > 0), resourceHref('subscriptions')),
		card(_('规则集'), missingRules === 0 ? _('就绪') : _('需要处理'), rulesDetailText, rulesScheduleWarning ? '#ea580c' : statusTone(missingRules === 0 && requiredRules > 0, requiredRules > 0), resourceHref('rules')),
		card(_('面板'), panelReady ? _('已启用') : _('未启用'), panelDetail, statusTone(panelReady), resourceHref('panel'), panelAction),
		card(_('Telegram'), notifyEnabled ? _('已启用') : _('已停用'), _('最近结果：%s | %s').format(notifyStatus, notifyResult), notifyAccent, resourceHref('notify'))
	]);
}

function runtimeStatusSection() {
	return E('div', { 'style': shinraUi.sectionStyle() }, [
		shinraUi.sectionTitle(_('运行时状态')),
		runtimeCards()
	]);
}

function resourceStatusSection() {
	return E('div', { 'style': shinraUi.sectionStyle() }, [
		shinraUi.sectionTitle(_('资源就绪状态')),
		resourceCards()
	]);
}

function operationButtons() {
	return E('div', { 'style': shinraUi.sectionStyle() }, [
		shinraUi.sectionTitle(_('运行时操作')),
		shinraUi.sectionDescription(_('资源准备完成后，在这里执行生成、检查、应用和回滚。策略组切换和延迟测速交给 Dashboard。')),
		shinraUi.statusBox('shinra-overview-action-status', actionStatus, actionStatusOk ? 'ok' : 'error', {
			padding: '.75rem',
			margin: '0 0 .75rem'
		}),
		E('div', { 'style': 'display: flex; flex-wrap: wrap; gap: .5rem;' }, [
			operationButton(_('生成'), _('生成候选配置'), callGenerate),
			operationButton(_('检查'), _('检查候选配置'), callCheck),
			operationButton(_('应用'), _('应用运行配置'), callApply, 'cbi-button-apply', _('现在将候选配置应用到运行时吗？')),
			operationButton(_('重启'), _('重启运行时'), callRestart, 'cbi-button-neutral', _('现在重启 Shinra 运行时吗？短时间内流量可能会中断。')),
			operationButton(_('停止'), _('停止运行时'), callStop, 'cbi-button-reset', _('现在停止 Shinra 运行时吗？流量将不再由 sing-box 接管。')),
			operationButton(_('回滚'), _('回滚运行配置'), callRollback, 'cbi-button-reset', _('现在回滚运行配置吗？'))
		])
	]);
}

function renderPage() {
	const loadError = pageLoadError();
	shinraMotion.inject();
	ensureSupplementalLoad();

	return E('div', { 'id': 'shinra-overview-root', 'class': 'cbi-map' }, [
		shinraUi.pageHeader(_('Shinra'), _('概览是控制面首页。运行时策略组交互由 Dashboard 处理。')),
		loadError ? E('div', { 'style': 'border: 1px solid #fecaca; border-radius: 8px; padding: .65rem; margin: 0 0 .75rem; background: #fef2f2; color: #991b1b;' }, loadError) : '',
		runtimeStatusSection(),
		resourceStatusSection(),
		operationButtons()
	]);
}

function redraw() {
	const root = document.getElementById('shinra-overview-root');
	if (root)
		root.parentNode.replaceChild(renderPage(), root);
}

return view.extend({
	load: function() {
		return loadAll();
	},

	render: function(results) {
		supplementalLoadSeq++;
		supplementalLoading = false;
		pageResults = results || {};
		return renderPage();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
