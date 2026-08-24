'use strict';
'require view';
'require rpc';
'require shinra.time as shinraTime';
'require shinra.ui as shinraUi';
'require shinra.motion as shinraMotion';

const callSubscriptionsGet = rpc.declare({
	object: 'shinra',
	method: 'subscriptions_get',
	expect: { '': {} }
});

const callSubscriptionsSave = rpc.declare({
	object: 'shinra',
	method: 'subscriptions_save',
	params: [ 'content' ],
	expect: { '': {} }
});

const callSubscriptionRefreshSourceStart = rpc.declare({
	object: 'shinra',
	method: 'subscription_refresh_source_start',
	params: [ 'source_id', 'strategy' ],
	expect: { '': {} }
});

const callSubscriptionsRefreshStatus = rpc.declare({
	object: 'shinra',
	method: 'subscriptions_refresh_status',
	params: [ 'run_id' ],
	expect: { '': {} }
});

const callSubscriptionsRefreshStart = rpc.declare({
	object: 'shinra',
	method: 'subscriptions_refresh_start',
	params: [ 'strategy' ],
	expect: { '': {} }
});

const callNodeSnapshotSummary = rpc.declare({
	object: 'shinra',
	method: 'node_snapshot_summary',
	expect: { '': {} }
});

const callSubscriptionTestSource = rpc.declare({
	object: 'shinra',
	method: 'subscription_test_source',
	params: [ 'name', 'url', 'strategy' ],
	expect: { '': {} }
});

const DEFAULT_REGION_KEYWORDS = {
	HK: [ 'HK', 'Hong Kong', 'HongKong', '香港' ],
	TW: [ 'TW', 'Taiwan', '台湾', '台灣' ],
	SG: [ 'SG', 'Singapore', '新加坡', '狮城', '獅城' ],
	JP: [ 'JP', 'Japan', '日本' ],
	US: [ 'US', 'USA', 'United States', '美国', '美國' ]
};
const DEFAULT_REGION_KEYS = [ 'HK', 'TW', 'SG', 'JP', 'US' ];

const DEFAULT_BANNED_KEYWORDS = 'expire|expired|traffic|invalid|remaining|过期|到期|失效|无效|剩余|流量|重置|订阅|套餐|官网|用量';
const DEFAULT_URLTEST_PARAMS = {
	url: 'https://www.gstatic.com/generate_204',
	interval: '3m',
	tolerance: 150
};
const DEFAULT_DNS_URLTEST = {
	enabled: false,
	keywords: [ 'HK', 'Hong Kong', 'HongKong', '香港' ],
	url: 'https://www.gstatic.com/generate_204',
	interval: '3m',
	tolerance: 150
};
const DEFAULT_RATE_FILTER = {
	enabled: true,
	threshold: 1.5,
	operator: '>=',
	scope: 'matched_regions',
	matched_regions: [ 'HK', 'TW', 'SG', 'JP', 'US' ],
	unmatched_action: 'keep',
	matched_high_rate_action: 'drop',
	patterns: [ 'number_x' ],
	include_integer_one: false
};

const DEFAULT_SUBSCRIPTION_UPDATE = {
	auto_update: false,
	update_hour: 3,
	strategy: 'saved',
	run_on_boot: false
};

function cloneArray(values) {
	return Array.isArray(values) ? values.slice() : [];
}

function appendUnique(values, value) {
	if (typeof value !== 'string' || value === '')
		return;
	if (values.indexOf(value) < 0)
		values.push(value);
}

function mergeKeywordList(defaults, values) {
	let merged = cloneArray(defaults);
	(Array.isArray(values) ? values : []).forEach(function(value) {
		appendUnique(merged, value);
	});
	return merged;
}

function mergePipeText(defaults, value) {
	let merged = [];
	(defaults || '').split('|').forEach(function(item) {
		appendUnique(merged, item);
	});
	(value || '').split('|').forEach(function(item) {
		appendUnique(merged, item);
	});
	return merged.join('|');
}

function normalizeUrltestUrl(value) {
	let url = typeof value === 'string' && value !== '' ? value : DEFAULT_URLTEST_PARAMS.url;
	if (url.indexOf('://x.test/') >= 0 || url === 'http://x.test' || url === 'https://x.test')
		return DEFAULT_URLTEST_PARAMS.url;
	return url;
}

function regionKeys(policy) {
	return DEFAULT_REGION_KEYS.slice();
}

function normalizeStringChoice(value, choices, fallback) {
	return choices.indexOf(value) >= 0 ? value : fallback;
}

function normalizeRateFilter(raw, keys) {
	raw = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
	keys = Array.isArray(keys) ? keys : DEFAULT_REGION_KEYS;

	let threshold = raw.threshold != null ? Number(raw.threshold) : DEFAULT_RATE_FILTER.threshold;
	if (!Number.isFinite(threshold) || threshold < 0)
		threshold = DEFAULT_RATE_FILTER.threshold;

	let matchedRegions = Array.isArray(raw.matched_regions) ? raw.matched_regions.filter(function(region) {
		return keys.indexOf(region) >= 0;
	}) : DEFAULT_RATE_FILTER.matched_regions.slice();

	let patterns = Array.isArray(raw.patterns) ? raw.patterns.filter(function(pattern) {
		return [ 'number_x', 'number_times_cn' ].indexOf(pattern) >= 0;
	}) : DEFAULT_RATE_FILTER.patterns.slice();

	return {
		enabled: raw.enabled === false ? false : true,
		threshold: threshold,
		operator: normalizeStringChoice(raw.operator, [ '>=', '>' ], DEFAULT_RATE_FILTER.operator),
		scope: normalizeStringChoice(raw.scope, [ 'matched_regions', 'all', 'none' ], DEFAULT_RATE_FILTER.scope),
		matched_regions: matchedRegions,
		unmatched_action: normalizeStringChoice(raw.unmatched_action, [ 'keep', 'drop' ], DEFAULT_RATE_FILTER.unmatched_action),
		matched_high_rate_action: normalizeStringChoice(raw.matched_high_rate_action, [ 'drop', 'raw' ], DEFAULT_RATE_FILTER.matched_high_rate_action),
		patterns: patterns,
		include_integer_one: raw.include_integer_one === true
	};
}

function normalizePolicy(raw) {
	let policy = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
	let regionKeywords = {};
	let inputKeywords = policy.region_keywords && typeof policy.region_keywords === 'object' && !Array.isArray(policy.region_keywords) ? policy.region_keywords : DEFAULT_REGION_KEYWORDS;

	DEFAULT_REGION_KEYS.forEach(function(region) {
		let values = Array.isArray(inputKeywords[region]) ? inputKeywords[region] : [];
		values = values.filter(function(value) {
			return typeof value === 'string' && value !== '';
		});
		regionKeywords[region] = mergeKeywordList(DEFAULT_REGION_KEYWORDS[region], values);
	});

	let keys = Object.keys(regionKeywords);
	let sources = Array.isArray(policy.sources) ? policy.sources.map(function(source) {
		source = source || {};
		let allowed = Array.isArray(source.allowed_regions) ? cloneArray(source.allowed_regions).filter(function(region) {
			return keys.indexOf(region) >= 0;
		}) : keys.slice();
		return {
			id: source.id || '',
			name: source.name || '',
			url: source.url || '',
			enabled: source.enabled === false ? false : true,
			allowed_regions: allowed
		};
	}) : [];

	return {
		schema_version: 1,
		refresh_strategy: policy.refresh_strategy === 'proxy' ? 'proxy' : 'direct',
		region_keywords: regionKeywords,
		manual_selector: {
			keywords: policy.manual_selector && Array.isArray(policy.manual_selector.keywords) ? policy.manual_selector.keywords.filter(function(value) {
				return typeof value === 'string' && value !== '';
			}) : []
		},
		banned_keywords: mergePipeText(DEFAULT_BANNED_KEYWORDS, policy.banned_keywords),
		urltest_params: {
			url: normalizeUrltestUrl(policy.urltest_params && policy.urltest_params.url),
			interval: policy.urltest_params && policy.urltest_params.interval || DEFAULT_URLTEST_PARAMS.interval,
			tolerance: policy.urltest_params && policy.urltest_params.tolerance != null ? Number(policy.urltest_params.tolerance) : DEFAULT_URLTEST_PARAMS.tolerance
		},
		dns_urltest: {
			enabled: policy.dns_urltest && policy.dns_urltest.enabled === true,
			keywords: policy.dns_urltest && Array.isArray(policy.dns_urltest.keywords) ? policy.dns_urltest.keywords.filter(function(value) {
				return typeof value === 'string' && value !== '';
			}) : DEFAULT_DNS_URLTEST.keywords.slice(),
			url: normalizeUrltestUrl(policy.dns_urltest && policy.dns_urltest.url),
			interval: policy.dns_urltest && policy.dns_urltest.interval || DEFAULT_DNS_URLTEST.interval,
			tolerance: policy.dns_urltest && policy.dns_urltest.tolerance != null ? Number(policy.dns_urltest.tolerance) : DEFAULT_DNS_URLTEST.tolerance
		},
		rate_filter: normalizeRateFilter(policy.rate_filter, keys),
		subscription_update: normalizeSubscriptionUpdate(policy.subscription_update),
		sources: sources
	};
}

function normalizeSubscriptionUpdate(raw) {
	raw = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
	let strategy = [ 'saved', 'direct', 'proxy' ].indexOf(raw.strategy) >= 0 ? raw.strategy : DEFAULT_SUBSCRIPTION_UPDATE.strategy;
	let updateHour = raw.update_hour != null ? Number(raw.update_hour) : DEFAULT_SUBSCRIPTION_UPDATE.update_hour;

	if (!Number.isFinite(updateHour) || updateHour < 0 || updateHour > 23)
		updateHour = DEFAULT_SUBSCRIPTION_UPDATE.update_hour;

	return {
		auto_update: raw.auto_update === true,
		update_hour: updateHour,
		strategy: strategy,
		run_on_boot: raw.run_on_boot === true
	};
}

function parseSubscriptions(content) {
	try {
		return normalizePolicy(JSON.parse(content || '{}'));
	} catch (e) {
		return normalizePolicy({});
	}
}

function getValue(id) {
	let el = document.getElementById(id);
	return el ? el.value : '';
}

function setValue(id, value) {
	let el = document.getElementById(id);
	if (el)
		el.value = value || '';
}

function checked(id) {
	let el = document.getElementById(id);
	return el ? !!el.checked : false;
}

function activeRefresh() {
	return window.shinraSubscriptionRefresh && typeof window.shinraSubscriptionRefresh === 'object' ? window.shinraSubscriptionRefresh : null;
}

function refreshStatusDone(status) {
	return [ 'success', 'partial', 'failed_preserved', 'failed_no_snapshot', 'failed' ].indexOf(status || '') >= 0;
}

function refreshInProgress() {
	let refresh = activeRefresh();
	return !!(refresh && refresh.run_id && !refreshStatusDone(refresh.task && refresh.task.status));
}

function updateRefreshControls() {
	let disabled = refreshInProgress();
	let button = document.getElementById('shinra-refresh-all');
	if (button)
		button.disabled = disabled;
}

function setActiveRefresh(refresh) {
	window.shinraSubscriptionRefresh = refresh || null;
	updateRefreshControls();
}

function setStatus(message, ok, refreshRunId) {
	let refresh = activeRefresh();
	if (refreshInProgress() && refreshRunId !== refresh.run_id)
		return;
	shinraUi.paintStatus('shinra-subscriptions-status', message || '', ok ? 'ok' : 'error');
}

function setRefreshStatus(message, ok) {
	let refresh = activeRefresh();
	setStatus(message, ok, refresh && refresh.run_id || '');
}

function taskMetaOf(result) {
	const data = result && result.ok && result.data ? result.data : {};
	return data.task_meta && typeof data.task_meta === 'object' ? data.task_meta : {};
}

function taskDisplayName(result, fallback) {
	const meta = taskMetaOf(result);
	return meta.display_name || fallback || _('后台任务');
}

function setTestReport(target, result) {
	let node = document.getElementById(target);
	if (!node)
		return;

	let ok = result && result.ok;
	let pending = result && result.pending;
	let data = result && result.data ? result.data : {};
	let detail = result && (result.detail || result.message || result.code) || '';
	let nodes = data.nodes && Array.isArray(data.nodes) ? data.nodes : [];
	let bypassText = '';

	node.style.display = 'block';
	node.style.borderColor = pending ? '#bfdbfe' : ok ? '#bbf7d0' : '#fecaca';
	node.style.background = pending ? '#eff6ff' : ok ? '#f0fdf4' : '#fef2f2';
	node.style.color = pending ? '#1d4ed8' : ok ? '#166534' : '#991b1b';
	node.textContent = pending
		? _('正在测试订阅源...')
		: ok
		? _('测试通过：%d 个节点。').format(data.node_count || 0) + bypassText + (nodes.length ? ' ' + nodes.slice(0, 3).map(function(item) { return item.tag || '-'; }).join(' / ') : '')
		: _('测试失败：') + subscriptionFailureHint(detail);
}

function subscriptionFailureHint(detail) {
	detail = detail || '';
	if (detail.indexOf('tun_captures_lan_substore') >= 0)
		return _('Runtime TUN 可能接管了这次局域网 Sub-Store 请求。请先停止运行时、使用代理刷新，或配置局域网绕行。') + ' ' + detail;
	return detail || _('无详细信息');
}

function testSource(name, url, strategy, target) {
	setTestReport(target, { pending: true });
	return callSubscriptionTestSource(name || '', url || '', strategy || 'direct').then(function(result) {
		setTestReport(target, result);
		return result;
	}).catch(function(error) {
		setTestReport(target, { ok: false, detail: error.message || String(error) });
	});
}

function setDraft(policy) {
	policy = normalizePolicy(policy);
	window.shinraSubscriptionsDraft = policy;
}

function draftPolicy() {
	return normalizePolicy(window.shinraSubscriptionsDraft || {});
}

function shortUrl(url) {
	url = url || '';
	try {
		let parsed = new URL(url);
		return parsed.host + parsed.pathname;
	} catch (e) {
		return url || '-';
	}
}

function sourceStatusMap(summary) {
	let map = {};
	let sources = summary && Array.isArray(summary.sources) ? summary.sources : [];
	sources.forEach(function(source) {
		map[source.name || ''] = source;
	});
	return map;
}

function refreshResultForSource(source) {
	let refresh = activeRefresh();
	if (!refresh || !refresh.task)
		return null;

	let task = refresh.task;
	let meta = task.meta && typeof task.meta === 'object' ? task.meta : {};
	let results = Array.isArray(meta.source_results) ? meta.source_results : [];
	for (let i = 0; i < results.length; i++) {
		if (results[i] && results[i].id === source.id)
			return results[i];
	}

	if (!refreshStatusDone(task.status) && ((meta.source_id && meta.source_id === source.id) || task.current_item === source.name))
		return { status: 'running', node_count: 0, error: '' };
	return null;
}

function refreshResultText(result) {
	if (!result)
		return '';
	if (result.status === 'running')
		return _('正在刷新...');
	if (result.ok)
		return _('刷新完成：%d 个节点。').format(result.node_count || 0);
	return _('刷新失败，已保留 %d 个节点。').format(result.node_count || 0);
}

function matrixId(index, field, region) {
	return 'shinra-matrix-' + index + '-' + field + (region ? '-' + region : '');
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
		E('p', { 'style': mutedStyle() + ' margin: 0;' }, description)
	]);
}

function sectionTitle(title, marginTop) {
	return E('h3', { 'style': 'margin: %s 0 .45rem; line-height: 1.25;'.format(marginTop || '0') }, title);
}

function sectionDescription(text) {
	return E('div', { 'style': mutedStyle() + ' margin: 0 0 .6rem;' }, text);
}

function field(label, value) {
	return E('div', { 'style': 'display: grid; grid-template-columns: minmax(130px, .8fr) minmax(0, 2fr); gap: .75rem; padding: .45rem 0; border-bottom: 1px solid #eef0f3;' }, [
		E('div', { 'style': 'color: #667;' }, label),
		E('div', { 'style': 'overflow-wrap: anywhere;' }, value == null || value === '' ? '-' : value)
	]);
}

function sourceMatrix(policy, summary) {
	let keys = regionKeys(policy);
	let status = sourceStatusMap(summary);
	let sources = policy.sources || [];

	return E('div', { 'style': sectionStyle() }, [
		E('div', { 'style': 'display: flex; justify-content: space-between; align-items: center; gap: .75rem; margin-bottom: .6rem;' }, [
			E('h3', { 'style': 'margin: 0; line-height: 1.25;' }, _('订阅源区域矩阵')),
			E('button', {
				'class': shinraMotion.buttonClass('btn cbi-button'),
				'click': function(ev) {
					ev.preventDefault();
					addSource();
				}
			}, _('添加订阅源'))
		]),
		sources.length ? E('div', { 'style': 'overflow-x: auto;' }, [
			E('table', { 'class': 'table', 'style': 'min-width: 760px;' }, [
				E('thead', {}, [
					E('tr', {}, [
						E('th', {}, _('名称')),
						E('th', { 'style': 'text-align: center;' }, _('启用'))
					].concat(keys.map(function(region) {
						return E('th', { 'style': 'text-align: center;' }, region);
					})).concat([
						E('th', { 'style': 'text-align: right;' }, _('节点')),
						E('th', { 'style': 'text-align: right;' }, _('操作'))
					]))
				]),
				E('tbody', {}, sources.map(function(source, index) {
					let item = status[source.name || ''] || {};
					let refresh = refreshResultForSource(source);
					return E('tr', {}, [
						E('td', {}, [
							E('div', { 'style': 'font-weight: 700; overflow-wrap: anywhere;' }, source.name || _('未命名订阅源')),
							E('div', { 'style': 'font-size: 12px; color: #667; overflow-wrap: anywhere;' }, shortUrl(source.url)),
							refresh ? E('div', { 'style': 'font-size: 12px; color: %s; overflow-wrap: anywhere; margin-top: .25rem;'.format(refresh.ok || refresh.status === 'running' ? '#2563eb' : '#991b1b') }, refreshResultText(refresh)) : item.error ? E('div', { 'style': 'font-size: 12px; color: #991b1b; overflow-wrap: anywhere; margin-top: .25rem;' }, item.error) : E('div')
						]),
						E('td', { 'style': 'text-align: center;' }, shinraUi.checkboxInput({
							'id': matrixId(index, 'enabled'),
							'checked': source.enabled !== false ? 'checked' : null,
							'change': function() {
								syncDraftFromMatrix();
							}
						}))
					].concat(keys.map(function(region) {
						return E('td', { 'style': 'text-align: center;' }, shinraUi.checkboxInput({
							'id': matrixId(index, 'region', region),
							'checked': source.allowed_regions.indexOf(region) >= 0 ? 'checked' : null,
							'change': function() {
								syncDraftFromMatrix();
							}
						}));
					})).concat([
						E('td', { 'style': 'text-align: right;' }, '%d'.format(item.node_count || 0)),
						E('td', { 'style': 'text-align: right; white-space: nowrap;' }, [
							E('button', {
								'class': shinraMotion.buttonClass('btn cbi-button'),
								'click': function(ev) {
									ev.preventDefault();
									openSourceEditor(index);
								}
							}, _('编辑')),
							' ',
							E('button', {
								'class': shinraMotion.buttonClass('btn cbi-button'),
								'click': function(ev) {
									ev.preventDefault();
									let policy = collectPolicyFromPage();
									let item = policy.sources[index] || {};
									testSource(item.name, item.url, policy.refresh_strategy, 'shinra-test-report');
								}
							}, _('测试')),
							' ',
							E('button', {
								'class': shinraMotion.buttonClass('btn cbi-button cbi-button-apply'),
								'disabled': refreshInProgress() ? 'disabled' : null,
								'click': function(ev) {
									ev.preventDefault();
									refreshOneSource(index);
								}
							}, _('刷新')),
							' ',
							E('button', {
								'class': shinraMotion.buttonClass('btn cbi-button cbi-button-remove'),
								'click': function(ev) {
									ev.preventDefault();
									removeSource(index);
								}
							}, _('删除'))
						])
					]));
				}))
			])
		]) : E('div', { 'style': 'color: #667; padding: .75rem 0;' }, _('没有订阅源。'))
	]);
}

function policySettings(policy) {
	let keys = regionKeys(policy);

	return E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; margin-top: .75rem;' }, [
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('区域关键字')),
			E('div', {}, keys.map(function(region) {
				return field(region, E('input', {
					'id': 'shinra-region-keywords-' + region,
					'class': 'cbi-input-text',
					'style': 'width: 100%;',
					'value': (policy.region_keywords[region] || []).join(', ')
				}));
			})),
			sectionTitle(_('DNS 专用出站组'), '1rem'),
			field(_('启用'), shinraUi.checkboxInput({
				'id': 'shinra-dns-urltest-enabled',
				'checked': policy.dns_urltest.enabled ? 'checked' : null
			})),
			field(_('节点筛选关键词'), E('textarea', {
				'id': 'shinra-dns-urltest-keywords',
				'class': 'cbi-input-textarea',
				'style': 'width: 100%; height: 2.4rem; min-height: 2.4rem; resize: none; font: inherit;',
				'spellcheck': 'false'
			}, [ (policy.dns_urltest.keywords || []).join(', ') ])),
			field(_('测速地址'), E('input', {
				'id': 'shinra-dns-urltest-url',
				'class': 'cbi-input-text',
				'style': 'width: 100%;',
				'value': policy.dns_urltest.url || DEFAULT_DNS_URLTEST.url
			})),
			field(_('间隔'), E('input', {
				'id': 'shinra-dns-urltest-interval',
				'class': 'cbi-input-text',
				'style': 'width: 100%;',
				'value': policy.dns_urltest.interval || DEFAULT_DNS_URLTEST.interval
			})),
			field(_('容差'), E('input', {
				'id': 'shinra-dns-urltest-tolerance',
				'class': 'cbi-input-text',
				'type': 'number',
				'min': '0',
				'style': 'width: 100%;',
				'value': policy.dns_urltest.tolerance
			})),
			E('div', { 'style': 'color: #667; font-size: .9em; margin-top: -.35rem;' }, _('生成固定 tag “📡 dns-out”，并接管已有 detour 的 DNS server；关闭或无匹配节点时回退至主选择器。')),
			sectionTitle(_('手动选择组'), '1rem'),
			field(_('手动选择关键词'), E('textarea', {
				'id': 'shinra-manual-selector-keywords',
				'class': 'cbi-input-textarea',
				'style': 'width: 100%; height: 2.4rem; min-height: 2.4rem; resize: none; font: inherit;',
				'spellcheck': 'false',
				'placeholder': _('例如：Brazil, 巴西, 🇧🇷, Turkey, 土耳其, 🇹🇷')
			}, [ (policy.manual_selector.keywords || []).join(', ') ])),
			E('div', { 'style': 'color: #667; font-size: .9em; margin-top: -.35rem;' }, _('用于生成“🍭 手动选择”组，多个关键词可使用逗号或换行分隔。'))
		]),
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('清洗与 URLTest')),
			field(_('过滤关键字'), E('textarea', {
				'id': 'shinra-banned-keywords',
				'class': 'cbi-input-textarea',
				'style': 'width: 100%; min-height: 4rem; font: inherit;',
				'spellcheck': 'false'
			}, [ policy.banned_keywords || '' ])),
			field(_('测速地址'), E('input', {
				'id': 'shinra-urltest-url',
				'class': 'cbi-input-text',
				'style': 'width: 100%;',
				'value': policy.urltest_params.url || DEFAULT_URLTEST_PARAMS.url
			})),
			field(_('间隔'), E('input', {
				'id': 'shinra-urltest-interval',
				'class': 'cbi-input-text',
				'style': 'width: 100%;',
				'value': policy.urltest_params.interval || DEFAULT_URLTEST_PARAMS.interval
			})),
			field(_('容差'), E('input', {
				'id': 'shinra-urltest-tolerance',
				'class': 'cbi-input-text',
				'type': 'number',
				'style': 'width: 100%;',
				'value': policy.urltest_params.tolerance
			})),
			field(_('倍率过滤'), shinraUi.checkboxInput({
				'id': 'shinra-rate-filter-enabled',
				'checked': policy.rate_filter.enabled ? 'checked' : null
			})),
			field(_('倍率阈值'), E('input', {
				'id': 'shinra-rate-filter-threshold',
				'class': 'cbi-input-text',
				'type': 'number',
				'step': '0.1',
				'min': '0',
				'style': 'width: 100%;',
				'value': policy.rate_filter.threshold
			})),
			field(_('比较方式'), E('select', { 'id': 'shinra-rate-filter-operator', 'class': 'cbi-input-select', 'style': 'width: 100%;' }, [
				E('option', { 'value': '>=', 'selected': policy.rate_filter.operator === '>=' ? 'selected' : null }, '>='),
				E('option', { 'value': '>', 'selected': policy.rate_filter.operator === '>' ? 'selected' : null }, '>')
			])),
			field(_('作用范围'), E('select', { 'id': 'shinra-rate-filter-scope', 'class': 'cbi-input-select', 'style': 'width: 100%;' }, [
				E('option', { 'value': 'matched_regions', 'selected': policy.rate_filter.scope === 'matched_regions' ? 'selected' : null }, _('匹配区域')),
				E('option', { 'value': 'all', 'selected': policy.rate_filter.scope === 'all' ? 'selected' : null }, _('全部节点')),
				E('option', { 'value': 'none', 'selected': policy.rate_filter.scope === 'none' ? 'selected' : null }, _('停用'))
			])),
			field(_('匹配区域'), E('div', {}, keys.map(function(region) {
				return E('label', { 'style': 'display: inline-flex; align-items: center; gap: .25rem; margin: 0 .75rem .35rem 0;' }, [
					shinraUi.checkboxInput({
						'id': 'shinra-rate-filter-region-' + region,
						'checked': policy.rate_filter.matched_regions.indexOf(region) >= 0 ? 'checked' : null
					}),
					E('span', {}, region)
				]);
			}))),
			field(_('匹配区域动作'), E('select', { 'id': 'shinra-rate-filter-high-action', 'class': 'cbi-input-select', 'style': 'width: 100%;' }, [
				E('option', { 'value': 'drop', 'selected': policy.rate_filter.matched_high_rate_action === 'drop' ? 'selected' : null }, _('完全丢弃')),
				E('option', { 'value': 'raw', 'selected': policy.rate_filter.matched_high_rate_action === 'raw' ? 'selected' : null }, _('仅排除 URLTest'))
			])),
			field(_('未匹配区域动作'), E('select', { 'id': 'shinra-rate-filter-unmatched-action', 'class': 'cbi-input-select', 'style': 'width: 100%;' }, [
				E('option', { 'value': 'keep', 'selected': policy.rate_filter.unmatched_action === 'keep' ? 'selected' : null }, _('保留')),
				E('option', { 'value': 'drop', 'selected': policy.rate_filter.unmatched_action === 'drop' ? 'selected' : null }, _('丢弃'))
			])),
			field(_('识别格式'), E('div', {}, [
				E('label', { 'style': 'display: inline-flex; align-items: center; gap: .25rem; margin: 0 .75rem .35rem 0;' }, [
					shinraUi.checkboxInput({
						'id': 'shinra-rate-filter-pattern-number-x',
						'checked': policy.rate_filter.patterns.indexOf('number_x') >= 0 ? 'checked' : null
					}),
					E('span', {}, '1.5x / 2x')
				]),
				E('label', { 'style': 'display: inline-flex; align-items: center; gap: .25rem; margin: 0 .75rem .35rem 0;' }, [
					shinraUi.checkboxInput({
						'id': 'shinra-rate-filter-pattern-number-cn',
						'checked': policy.rate_filter.patterns.indexOf('number_times_cn') >= 0 ? 'checked' : null
					}),
					E('span', {}, '1.5倍 / 2倍')
				])
			])),
			field(_('识别 1x'), shinraUi.checkboxInput({
				'id': 'shinra-rate-filter-include-one',
				'checked': policy.rate_filter.include_integer_one ? 'checked' : null
			}))
		])
	]);
}

function fetchSafetySettings(policy) {
	let bypass = normalizeFetchBypass(policy.fetch_bypass);

	return E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; margin-top: .75rem;' }, [
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('局域网绕行')),
			field(_('启用'), shinraUi.checkboxInput({
				'id': 'shinra-fetch-bypass-enabled',
				'checked': bypass.enabled ? 'checked' : null,
				'change': function() {
					syncDraftFromMatrix();
				}
			})),
			field(_('允许局域网'), shinraUi.checkboxInput({
				'id': 'shinra-fetch-bypass-allow-lan',
				'checked': bypass.allow_lan ? 'checked' : null,
				'change': function() {
					syncDraftFromMatrix();
				}
			})),
			field(_('模式'), E('input', {
				'id': 'shinra-fetch-bypass-mode',
				'class': 'cbi-input-text',
				'style': 'width: 100%;',
				'readonly': 'readonly',
				'value': bypass.mode || DEFAULT_FETCH_BYPASS.mode
			})),
			field(_('优先级'), E('input', {
				'id': 'shinra-fetch-bypass-priority',
				'class': 'cbi-input-text',
				'type': 'number',
				'min': '7800',
				'max': '8099',
				'style': 'width: 100%;',
				'value': bypass.priority || DEFAULT_FETCH_BYPASS.priority
			}))
		]),
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('允许的主机')),
			sectionDescription(_('只有明确配置的局域网 IPv4 主机才会使用临时抓取绕行。每行一个主机，也可以用逗号分隔。')),
			E('textarea', {
				'id': 'shinra-fetch-bypass-hosts',
				'class': 'cbi-input-textarea',
				'style': 'width: 100%; min-height: 6rem; font: inherit;',
				'spellcheck': 'false'
			}, [ bypass.hosts.join('\n') ]),
			E('div', { 'style': 'color: #667; font-size: 12px; margin-top: .5rem;' }, _('这只影响订阅抓取，不会修改模板、候选配置、运行配置或策略组状态。'))
		])
	]);
}

function collapsible(title, subtitle, content, open) {
	return E('details', {
		'open': open ? 'open' : null,
		'style': sectionStyle()
	}, [
		E('summary', { 'style': 'cursor: pointer; list-style-position: inside;' }, [
			E('span', { 'style': 'font-weight: 700;' }, title),
			subtitle ? E('span', { 'style': 'display: block; color: #667; font-size: 12px; margin-top: .25rem;' }, subtitle) : E('span')
		]),
		content
	]);
}

function policyDetails(policy) {
	return collapsible(
		_('全局策略'),
		_('区域关键字、清洗关键字，以及生成 URLTest 组时使用的参数。'),
		policySettings(policy),
		false
	);
}

function fetchSafetyDetails(policy) {
	let bypass = normalizeFetchBypass(policy.fetch_bypass);
	let subtitle = bypass.enabled
		? _('已为 %d 个主机启用，优先级 %d。').format(bypass.hosts.length, bypass.priority)
		: _('已停用。直连刷新会保持当前路由行为。');

	return collapsible(
		_('抓取安全'),
		subtitle,
		fetchSafetySettings(policy),
		false
	);
}

function subscriptionUpdateSettings(policy) {
	let update = normalizeSubscriptionUpdate(policy.subscription_update);

	return E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; margin-top: .75rem;' }, [
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('调度策略')),
			field(_('自动刷新'), shinraUi.checkboxInput({
				'id': 'shinra-subscription-auto-update',
				'checked': update.auto_update ? 'checked' : null
			})),
			field(_('每日小时'), E('input', {
				'id': 'shinra-subscription-update-hour',
				'class': 'cbi-input-text',
				'type': 'number',
				'min': '0',
				'max': '23',
				'style': 'width: 100%;',
				'value': update.update_hour
			})),
			field(_('策略'), E('select', { 'id': 'shinra-subscription-update-strategy', 'class': 'cbi-input-select', 'style': 'width: 100%;' }, [
				E('option', { 'value': 'saved', 'selected': update.strategy === 'saved' ? 'selected' : null }, _('使用已保存的刷新策略')),
				E('option', { 'value': 'direct', 'selected': update.strategy === 'direct' ? 'selected' : null }, _('强制直连刷新')),
				E('option', { 'value': 'proxy', 'selected': update.strategy === 'proxy' ? 'selected' : null }, _('强制代理刷新'))
			])),
			field(_('启动时运行'), shinraUi.checkboxInput({
				'id': 'shinra-subscription-run-on-boot',
				'checked': update.run_on_boot ? 'checked' : null
			}))
		]),
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('边界')),
			sectionDescription(_('这里只保存自动刷新策略。调度器会按该策略触发后台任务。')),
			E('div', { 'style': 'color: #667; font-size: 12px; line-height: 1.6;' }, [
				_('调度任务：订阅刷新任务（subscription.refresh）。'),
				E('br'),
				_('手动刷新节点快照保持不变，不会发送 Telegram 通知。')
			])
		])
	]);
}

function subscriptionUpdateDetails(policy) {
	let update = normalizeSubscriptionUpdate(policy.subscription_update);
	let subtitle = update.auto_update
		? _('已启用：%d:00，策略 %s。').format(update.update_hour, update.strategy)
		: _('已停用。策略仍会保存。');

	return collapsible(
		_('自动刷新'),
		subtitle,
		subscriptionUpdateSettings(policy),
		false
	);
}

function sourceEditor(policy, index) {
	if (index == null)
		return E('div', { 'id': 'shinra-source-editor', 'style': 'display: none;' });

	let isNew = index === 'new';
	let source = isNew ? {
		id: '',
		name: '',
		url: '',
		enabled: true,
		allowed_regions: regionKeys(policy)
	} : policy.sources[index] || {};
	let keys = regionKeys(policy);

	return E('div', {
		'id': 'shinra-source-editor',
		'data-index': isNew ? '-1' : index,
		'style': 'position: fixed; inset: 0; z-index: 2000; display: flex; align-items: center; justify-content: center; padding: 1rem; background: rgba(15, 23, 42, .32);'
	}, [
		E('div', { 'style': 'width: min(720px, 100%); max-height: min(760px, calc(100vh - 2rem)); overflow: auto; border: 1px solid #d8dde6; border-radius: 10px; padding: 1rem; background: #fff; box-shadow: 0 18px 50px rgba(15, 23, 42, .22);' }, [
			E('div', { 'style': 'display: flex; justify-content: space-between; gap: 1rem; align-items: center; margin-bottom: .75rem;' }, [
				E('h3', { 'style': 'margin: 0;' }, isNew ? _('添加订阅源') : _('编辑订阅源')),
				E('button', { 'class': shinraMotion.buttonClass('btn cbi-button'), 'click': function(ev) { ev.preventDefault(); closeSourceEditor(); } }, _('取消'))
			]),
			field(_('名称'), E('input', { 'id': 'shinra-editor-name', 'class': 'cbi-input-text', 'style': 'width: 100%;', 'value': source.name || '' })),
			field(_('URL'), E('input', { 'id': 'shinra-editor-url', 'class': 'cbi-input-text', 'style': 'width: 100%;', 'value': source.url || '' })),
			field(_('启用'), shinraUi.checkboxInput({ 'id': 'shinra-editor-enabled', 'checked': source.enabled !== false ? 'checked' : null })),
			field(_('允许区域'), E('div', {}, keys.map(function(region) {
				return E('label', { 'style': 'display: inline-flex; align-items: center; gap: .35rem; border: 1px solid #ddd; border-radius: 6px; padding: .35rem .55rem; margin-right: .45rem; margin-bottom: .45rem;' }, [
					shinraUi.checkboxInput({
						'class': 'shinra-editor-region',
						'value': region,
						'checked': source.allowed_regions.indexOf(region) >= 0 ? 'checked' : null
					}),
					E('span', {}, region)
				]);
			}))),
			E('div', { 'id': 'shinra-editor-test-report', 'style': 'display: none; border: 1px solid #ddd; border-radius: 8px; padding: .65rem; margin-top: .75rem; overflow-wrap: anywhere;' }),
			E('div', { 'style': 'display: flex; justify-content: flex-end; gap: .5rem; flex-wrap: wrap; margin-top: .9rem;' }, [
				E('button', { 'class': shinraMotion.buttonClass('btn cbi-button'), 'click': function(ev) { ev.preventDefault(); closeSourceEditor(); } }, _('取消')),
				E('button', { 'class': shinraMotion.buttonClass('btn cbi-button'), 'click': function(ev) { ev.preventDefault(); testEditorSource(); } }, _('测试')),
				E('button', { 'class': shinraMotion.buttonClass('btn cbi-button cbi-button-save'), 'click': function(ev) { ev.preventDefault(); saveSourceEditor(); } }, _('保存草稿'))
			])
		])
	]);
}

function sourceRows(summary) {
	let sources = summary && Array.isArray(summary.sources) ? summary.sources : [];
	if (!sources.length)
		return [ E('div', { 'style': 'color: #667; padding: .35rem 0;' }, _('没有观测到订阅源。')) ];

	return sources.map(function(source) {
		return E('div', { 'class': shinraMotion.softRowClass(), 'style': 'display: grid; grid-template-columns: minmax(0, 1.4fr) 80px 90px minmax(0, 1fr); gap: .75rem; padding: .45rem 0; border-bottom: 1px solid #eee; align-items: center;' }, [
			E('div', { 'style': 'overflow-wrap: anywhere; font-weight: 600;' }, source.name || '-'),
			E('div', {}, source.ok ? _('成功') : _('失败')),
			E('div', {}, '%d'.format(source.node_count || 0)),
			E('div', { 'style': 'overflow-wrap: anywhere; color: #667;' }, source.error || '-')
		]);
	});
}

function nodesForSource(summary, sourceId) {
	let nodes = summary && Array.isArray(summary.nodes) ? summary.nodes : [];
	if (!sourceId || sourceId === '__all__')
		return nodes;

	return nodes.filter(function(node) {
		return (node.source_id || '') === sourceId;
	});
}

function activeSnapshotSource(summary) {
	let sources = summary && Array.isArray(summary.sources) ? summary.sources : [];
	let active = window.shinraNodeSnapshotSource || '__all__';
	if (active === '__all__')
		return active;

	for (let i = 0; i < sources.length; i++) {
		if ((sources[i].id || '') === active)
			return active;
	}

	return '__all__';
}

function setSnapshotSource(sourceId) {
	window.shinraNodeSnapshotSource = sourceId || '__all__';
	let container = document.getElementById('shinra-node-snapshot-summary');
	if (container)
		container.parentNode.replaceChild(snapshotSummary(window.shinraNodeSnapshotSummary || {}), container);
}

function nodeList(nodes) {
	if (!nodes.length)
		return E('div', { 'style': 'color: #667; padding: .7rem 0;' }, _('该订阅源没有观测到节点。'));

	return E('div', {}, nodes.slice(0, 80).map(function(node) {
		return E('div', { 'class': shinraMotion.softRowClass(), 'style': 'display: grid; grid-template-columns: minmax(0, 2fr) minmax(90px, .6fr) minmax(90px, .8fr); gap: .75rem; padding: .45rem 0; border-bottom: 1px solid #eee; align-items: center;' }, [
			E('div', { 'style': 'overflow-wrap: anywhere; font-weight: 600;' }, node.tag || '-'),
			E('div', { 'style': 'color: #667;' }, node.type || '-'),
			E('div', { 'style': 'color: #667;' }, node.source || '-')
		]);
	}));
}

function nodeTabs(summary) {
	let sources = summary && Array.isArray(summary.sources) ? summary.sources : [];
	let active = activeSnapshotSource(summary);
	let tabs = [ { name: '__all__', label: _('全部'), count: summary && summary.node_count || 0 } ].concat(sources.map(function(source) {
		return {
			name: source.id || '',
			label: source.name || _('未命名订阅源'),
			count: source.node_count || 0
		};
	}));
	let nodes = nodesForSource(summary, active);

	return E('div', { 'style': sectionStyle() }, [
		sectionTitle(_('节点摘要')),
		E('div', { 'style': 'display: flex; gap: .45rem; flex-wrap: wrap; margin-bottom: .85rem;' }, tabs.map(function(tab) {
			let selected = tab.name === active;
			return E('button', {
				'class': shinraMotion.buttonClass('btn cbi-button'),
				'style': selected ? 'border-color: #2563eb; background: #eff6ff; color: #1d4ed8;' : '',
				'click': function(ev) {
					ev.preventDefault();
					setSnapshotSource(tab.name);
				}
			}, '%s (%d)'.format(tab.label, tab.count));
		})),
		E('div', { 'style': 'display: grid; grid-template-columns: minmax(0, 2fr) minmax(90px, .6fr) minmax(90px, .8fr); gap: .75rem; color: #667; font-size: 12px; padding-bottom: .4rem; border-bottom: 1px solid #ddd;' }, [
			E('div', {}, _('标签')),
			E('div', {}, _('类型')),
			E('div', {}, _('来源'))
		]),
		nodeList(nodes)
	]);
}

function snapshotSummary(summary) {
	return E('div', { 'id': 'shinra-node-snapshot-summary' }, [
		E('div', { 'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: .75rem; margin-bottom: .75rem;' }, [
			shinraUi.statCard(_('节点'), '%d'.format(summary && summary.node_count || 0), { 'class': shinraMotion.cardClass() }),
			shinraUi.statCard(_('订阅源'), '%d'.format(summary && summary.source_count || 0), { 'class': shinraMotion.cardClass() }),
			shinraUi.statCard(_('策略'), summary && summary.refresh_strategy || 'direct', { 'class': shinraMotion.cardClass() }),
			shinraUi.statCard(_('更新时间'), shinraTime.formatMaybeTime(summary && summary.updated_at), { 'class': shinraMotion.cardClass() })
		]),
		E('div', { 'style': sectionStyle() }, [
			sectionTitle(_('订阅源摘要')),
			E('div', { 'style': 'display: grid; grid-template-columns: minmax(0, 1.4fr) 80px 90px minmax(0, 1fr); gap: .75rem; color: #667; font-size: 12px; padding-bottom: .4rem; border-bottom: 1px solid #ddd;' }, [
				E('div', {}, _('名称')),
				E('div', {}, _('状态')),
				E('div', {}, _('节点')),
				E('div', {}, _('错误'))
			]),
			E('div', {}, sourceRows(summary))
		]),
		nodeTabs(summary)
	]);
}

function snapshotDetails(summary) {
	return collapsible(
		_('节点快照'),
	_('%d 个节点，%d 个订阅源，更新于 %s').format(summary && summary.node_count || 0, summary && summary.source_count || 0, shinraTime.formatMaybeTime(summary && summary.updated_at)),
		snapshotSummary(summary),
		false
	);
}

function collectPolicyFromPage() {
	let policy = draftPolicy();
	let keys = regionKeys(policy);

	policy.refresh_strategy = getValue('shinra-refresh-strategy') === 'proxy' ? 'proxy' : 'direct';
	policy.region_keywords = {};
	keys.forEach(function(region) {
		policy.region_keywords[region] = getValue('shinra-region-keywords-' + region).split(',').map(function(value) {
			return value.trim();
		}).filter(function(value) {
			return value !== '';
		});
	});
	policy.manual_selector = {
		keywords: getValue('shinra-manual-selector-keywords').split(/[\n,]+/).map(function(value) {
			return value.trim();
		}).filter(function(value) {
			return value !== '';
		})
	};
	policy.banned_keywords = getValue('shinra-banned-keywords') || DEFAULT_BANNED_KEYWORDS;
	policy.urltest_params = {
		url: normalizeUrltestUrl(getValue('shinra-urltest-url')),
		interval: getValue('shinra-urltest-interval') || DEFAULT_URLTEST_PARAMS.interval,
		tolerance: Number(getValue('shinra-urltest-tolerance') || DEFAULT_URLTEST_PARAMS.tolerance)
	};
	policy.dns_urltest = {
		enabled: checked('shinra-dns-urltest-enabled'),
		keywords: getValue('shinra-dns-urltest-keywords').split(/[\n,]+/).map(function(value) {
			return value.trim();
		}).filter(function(value) {
			return value !== '';
		}),
		url: normalizeUrltestUrl(getValue('shinra-dns-urltest-url')),
		interval: getValue('shinra-dns-urltest-interval') || DEFAULT_DNS_URLTEST.interval,
		tolerance: Number(getValue('shinra-dns-urltest-tolerance') || DEFAULT_DNS_URLTEST.tolerance)
	};
	let rateRegions = [];
	keys.forEach(function(region) {
		if (checked('shinra-rate-filter-region-' + region))
			rateRegions.push(region);
	});
	let ratePatterns = [];
	if (checked('shinra-rate-filter-pattern-number-x'))
		ratePatterns.push('number_x');
	if (checked('shinra-rate-filter-pattern-number-cn'))
		ratePatterns.push('number_times_cn');
	policy.rate_filter = normalizeRateFilter({
		enabled: checked('shinra-rate-filter-enabled'),
		threshold: Number(getValue('shinra-rate-filter-threshold') || DEFAULT_RATE_FILTER.threshold),
		operator: getValue('shinra-rate-filter-operator') || DEFAULT_RATE_FILTER.operator,
		scope: getValue('shinra-rate-filter-scope') || DEFAULT_RATE_FILTER.scope,
		matched_regions: rateRegions,
		unmatched_action: getValue('shinra-rate-filter-unmatched-action') || DEFAULT_RATE_FILTER.unmatched_action,
		matched_high_rate_action: getValue('shinra-rate-filter-high-action') || DEFAULT_RATE_FILTER.matched_high_rate_action,
		patterns: ratePatterns,
		include_integer_one: checked('shinra-rate-filter-include-one')
	}, keys);
	delete policy.fetch_bypass;
	policy.subscription_update = normalizeSubscriptionUpdate({
		auto_update: checked('shinra-subscription-auto-update'),
		update_hour: Number(getValue('shinra-subscription-update-hour') || DEFAULT_SUBSCRIPTION_UPDATE.update_hour),
		strategy: getValue('shinra-subscription-update-strategy') || DEFAULT_SUBSCRIPTION_UPDATE.strategy,
		run_on_boot: checked('shinra-subscription-run-on-boot')
	});
	policy.sources = policy.sources.map(function(source, index) {
		let allowed = [];
		keys.forEach(function(region) {
			if (checked(matrixId(index, 'region', region)))
				allowed.push(region);
		});
		return {
			id: source.id,
			name: source.name,
			url: source.url,
			enabled: checked(matrixId(index, 'enabled')),
			allowed_regions: allowed
		};
	});

	setDraft(policy);
	return policy;
}

function syncDraftFromMatrix() {
	collectPolicyFromPage();
	setStatus(_('草稿已更新。请保存订阅设置以持久化更改。'), true);
}

function updateMain(policy, summary, editIndex) {
	let main = document.getElementById('shinra-subscriptions-main');
	if (main)
		main.parentNode.replaceChild(renderMain(policy, summary, editIndex), main);
}

function addSource() {
	let policy = collectPolicyFromPage();
	updateMain(policy, window.shinraNodeSnapshotSummary || {}, 'new');
}

function removeSource(index) {
	let policy = collectPolicyFromPage();
	policy.sources.splice(index, 1);
	setDraft(policy);
	updateMain(policy, window.shinraNodeSnapshotSummary || {}, null);
	setStatus(_('草稿已更新。请保存订阅设置以持久化更改。'), true);
}

function openSourceEditor(index) {
	updateMain(collectPolicyFromPage(), window.shinraNodeSnapshotSummary || {}, index);
}

function closeSourceEditor() {
	updateMain(collectPolicyFromPage(), window.shinraNodeSnapshotSummary || {}, null);
}

function testEditorSource() {
	let policy = collectPolicyFromPage();
	return testSource(
		getValue('shinra-editor-name').trim(),
		getValue('shinra-editor-url').trim(),
		policy.refresh_strategy,
		'shinra-editor-test-report'
	);
}

function refreshProgressText(refresh) {
	let task = refresh.task || {};
	let meta = task.meta && typeof task.meta === 'object' ? task.meta : {};
	if (refresh.scope === 'source')
		return _('正在刷新订阅源：%s...').format(refresh.source_name || meta.source_name || '-');
	return _('正在刷新节点快照：%d / %d，当前 %s。').format(task.completed_count || 0, task.total_count || 0, task.current_item || '-');
}

function refreshFinishedText(refresh) {
	let task = refresh.task || {};
	let status = task.status || '';
	if (refresh.scope === 'source') {
		if (status === 'success')
			return _('订阅源已刷新：%s。准备使用新节点时，请生成候选配置。').format(refresh.source_name || '-');
		if (status === 'failed_preserved')
			return _('订阅源刷新失败，已保留旧节点：%s。').format(refresh.source_name || '-');
	}
	if (status === 'success')
		return _('节点快照已刷新。准备使用新节点时，请生成候选配置。');
	if (status === 'partial')
		return _('节点快照部分刷新完成，请查看各订阅源结果。');
	return _('订阅刷新未完成：%s。').format(status || _('未知'));
}

function refreshTaskStale(task) {
	let updatedAt = task && task.updated_at ? Date.parse(task.updated_at) : NaN;
	return Number.isFinite(updatedAt) && Date.now() - updatedAt > 120000;
}

function redrawRefreshState() {
	updateMain(draftPolicy(), window.shinraNodeSnapshotSummary || {}, null);
	updateRefreshControls();
}

function waitRefresh(runId, attempt) {
	return callSubscriptionsRefreshStatus(runId).then(function(result) {
		let data = result && result.ok && result.data ? result.data : {};
		let refresh = activeRefresh();
		if (!refresh || refresh.run_id !== runId)
			return;
		if (!data.matches_run) {
			setActiveRefresh(null);
			setStatus(_('订阅刷新任务已被其他操作替换。'), false);
			redrawRefreshState();
			return;
		}

		refresh.task = data.task || {};
		setActiveRefresh(refresh);
		redrawRefreshState();
		if (!refreshStatusDone(refresh.task.status)) {
			setRefreshStatus(refreshTaskStale(refresh.task) ? _('订阅刷新任务超过两分钟没有更新，仍在等待后台恢复。') : refreshProgressText(refresh), !refreshTaskStale(refresh.task));
			return new Promise(function(resolve) {
				window.setTimeout(resolve, refreshTaskStale(refresh.task) ? 5000 : 1000);
			}).then(function() {
				return waitRefresh(runId, attempt + 1);
			});
		}

		return callNodeSnapshotSummary().then(function(summary) {
			if (summary && summary.ok && summary.data)
				updateSummary(summary.data);
			let ok = refresh.task.status === 'success';
			setStatus(refreshFinishedText(refresh), ok);
			redrawRefreshState();
		});
	}).catch(function(error) {
		let refresh = activeRefresh();
		if (refresh && refresh.run_id === runId) {
			setActiveRefresh(null);
			setStatus(error.message || String(error), false);
			redrawRefreshState();
		}
	});
}

function beginRefresh(result, scope, sourceId, sourceName) {
	let data = result && result.data ? result.data : {};
	let task = data.task || {};
	let runId = data.run_id || (task.meta && task.meta.run_id) || '';
	if (!runId) {
		setStatus(_('订阅刷新任务未返回运行标识。'), false);
		return;
	}

	setActiveRefresh({
		run_id: runId,
		scope: data.scope || (task.meta && task.meta.scope) || scope,
		source_id: data.source_id || (task.meta && task.meta.target_source_id) || sourceId || '',
		source_name: sourceName || '',
		task: task
	});
	redrawRefreshState();
	setRefreshStatus(refreshProgressText(activeRefresh()), true);
	return waitRefresh(runId, 0);
}

function refreshOneSource(index, retried) {
	let policy = collectPolicyFromPage();
	let source = policy.sources[index] || {};
	let sourceId = source.id || '';
	let sourceName = source.name || _('未命名订阅源');
	let strategy = policy.refresh_strategy || getValue('shinra-refresh-strategy') || 'direct';

	if (!sourceId) {
		if (!retried) {
			setStatus(_('Reloading saved subscription settings...'), true);
			return reloadPolicyFromBackend().then(function() {
				return refreshOneSource(index, true);
			}).catch(function(error) {
				setStatus(error.message || String(error), false);
			});
		}
		setStatus(_('请先保存订阅设置，再刷新单个订阅源。'), false);
		return Promise.resolve();
	}

	setStatus(_('正在提交订阅源刷新：%s...').format(sourceName), true);
	return callSubscriptionRefreshSourceStart(sourceId, strategy).then(function(result) {
		if (!(result && result.ok)) {
			setStatus('%s: %s'.format(result && (result.message || result.code) || _('刷新失败'), subscriptionFailureHint(result && (result.detail || result.code) || '')), false);
			return;
		}
		if (!(result.data && result.data.started)) {
			let task = result.data && result.data.task ? result.data.task : {};
			let runId = task.meta && task.meta.run_id || '';
			if (runId)
				return beginRefresh(result, task.meta && task.meta.scope || 'all', task.meta && task.meta.target_source_id || '', '');
			setStatus(_('已有%s正在运行，请稍后再试。').format(taskDisplayName(result, _('订阅刷新任务'))), false);
			return;
		}
		return beginRefresh(result, 'source', sourceId, sourceName);
	}).catch(function(error) {
		setStatus(error.message || String(error), false);
	});
}

function saveSourceEditor() {
	let editor = document.getElementById('shinra-source-editor');
	let index = editor ? Number(editor.getAttribute('data-index')) : -1;
	let policy = collectPolicyFromPage();
	let regions = [];
	let inputs = document.querySelectorAll ? document.querySelectorAll('.shinra-editor-region') : [];

	for (let i = 0; i < inputs.length; i++) {
		if (inputs[i].checked)
			regions.push(inputs[i].value);
	}

	if (index < 0 || !policy.sources[index])
		policy.sources.push({
			name: getValue('shinra-editor-name').trim(),
			url: getValue('shinra-editor-url').trim(),
			enabled: checked('shinra-editor-enabled'),
			allowed_regions: regions
		});
	else
		policy.sources[index] = {
			id: policy.sources[index].id || '',
			name: getValue('shinra-editor-name').trim(),
			url: getValue('shinra-editor-url').trim(),
			enabled: checked('shinra-editor-enabled'),
			allowed_regions: regions
		};

	setDraft(policy);
	updateMain(policy, window.shinraNodeSnapshotSummary || {}, null);
	setStatus(_('草稿已更新。请保存订阅设置以持久化更改。'), true);
}

function updateSummary(summary) {
	window.shinraNodeSnapshotSummary = summary || {};
	let container = document.getElementById('shinra-node-snapshot-summary');
	if (container)
		container.parentNode.replaceChild(snapshotSummary(summary), container);
	updateMain(draftPolicy(), summary || {}, null);
}

function reloadPolicyFromBackend() {
	return callSubscriptionsGet().then(function(result) {
		if (!(result && result.ok && result.data))
			return;

		let policy = parseSubscriptions(result.data.content || '{}');
		setDraft(policy);
		updateMain(policy, window.shinraNodeSnapshotSummary || {}, null);
	});
}

function renderMain(policy, summary, editIndex) {
	return E('div', { 'id': 'shinra-subscriptions-main' }, [
		sourceMatrix(policy, summary),
		E('div', { 'id': 'shinra-test-report', 'style': 'display: none; border: 1px solid #ddd; border-radius: 8px; padding: .65rem; margin: -.35rem 0 1rem; overflow-wrap: anywhere;' }),
		sourceEditor(policy, editIndex)
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			callSubscriptionsGet(),
			callNodeSnapshotSummary().catch(function(e) {
				return { ok: false, message: _('节点快照摘要加载失败'), detail: e.message || String(e) };
			}),
			callSubscriptionsRefreshStatus().catch(function(e) {
				return { ok: false, message: _('订阅刷新状态加载失败'), detail: e.message || String(e) };
			})
		]);
	},

	render: function(data) {
		let content = data && data[0] && data[0].ok && data[0].data ? data[0].data.content : '{}';
		let summary = data && data[1] && data[1].ok && data[1].data ? data[1].data : {};
		let refreshData = data && data[2] && data[2].ok && data[2].data ? data[2].data : {};
		let refreshTask = refreshData.task || {};
		let refreshMeta = refreshTask.meta && typeof refreshTask.meta === 'object' ? refreshTask.meta : {};
		if (!refreshStatusDone(refreshTask.status) && refreshMeta.run_id) {
			setActiveRefresh({
				run_id: refreshMeta.run_id,
				scope: refreshMeta.scope || 'all',
				source_id: refreshMeta.target_source_id || '',
				source_name: refreshMeta.source_name || '',
				task: refreshTask
			});
		} else {
			setActiveRefresh(null);
		}
		let policy = parseSubscriptions(content);
		shinraMotion.inject();
		window.shinraNodeSnapshotSummary = summary;
		setDraft(policy);

		let page = E('div', { 'class': 'cbi-map' }, [
			E('div', {}, [
				pageHeader(_('订阅'), _('管理 Sub-Store 输出订阅源、区域授权、清洗策略和 URLTest 参数。刷新只写入节点快照。')),
				shinraUi.statusBox('shinra-subscriptions-status', '', 'neutral', { margin: '0 0 .75rem' }),
				E('div', { 'style': 'display: flex; justify-content: flex-end; gap: .5rem; flex-wrap: wrap; margin: 0 0 .75rem;' }, [
					E('select', { 'id': 'shinra-refresh-strategy', 'class': 'cbi-input-select' }, [
						E('option', { 'value': 'direct', 'selected': policy.refresh_strategy === 'direct' ? 'selected' : null }, _('直连刷新')),
						E('option', { 'value': 'proxy', 'selected': policy.refresh_strategy === 'proxy' ? 'selected' : null }, _('代理刷新'))
					]),
					E('button', { 'class': shinraMotion.buttonClass('btn cbi-button cbi-button-save'), 'click': this.handleSave.bind(this) }, _('保存订阅设置')),
					E('button', { 'id': 'shinra-refresh-all', 'class': shinraMotion.buttonClass('btn cbi-button cbi-button-apply'), 'disabled': refreshInProgress() ? 'disabled' : null, 'click': this.handleRefresh.bind(this) }, _('刷新节点快照'))
				]),
				renderMain(policy, summary, null),
				subscriptionUpdateDetails(policy),
				policyDetails(policy),
				snapshotDetails(summary)
			])
		]);
		let refresh = activeRefresh();
		if (refresh)
			window.setTimeout(function() { waitRefresh(refresh.run_id, 0); }, 0);
		return page;
	},

	handleSave: function(ev) {
		if (ev)
			ev.preventDefault();
		let policy = collectPolicyFromPage();
		setStatus(_('正在保存订阅设置...'), true);
		return callSubscriptionsSave(JSON.stringify(policy, null, 2)).then(function(result) {
			if (result && result.ok)
				setStatus(_('订阅设置已保存。准备使用这些更改时，请生成候选配置。'), true);
			else
				setStatus('%s: %s'.format(result && (result.message || result.code) || _('保存失败'), result && (result.detail || result.code) || _('无详细信息')), false);
		}).catch(function(error) {
			setStatus(error.message || String(error), false);
		});
	},

	handleRefresh: function(ev) {
		if (ev)
			ev.preventDefault();
		let strategy = getValue('shinra-refresh-strategy') || '';
		setStatus(_('正在提交节点快照刷新...'), true);
		return callSubscriptionsRefreshStart(strategy).then(function(result) {
			if (!(result && result.ok)) {
				setStatus('%s: %s'.format(result && (result.message || result.code) || _('刷新失败'), subscriptionFailureHint(result && (result.detail || result.code) || '')), false);
				return;
			}

			if (!(result.data && result.data.started)) {
				let task = result.data && result.data.task ? result.data.task : {};
				let runId = task.meta && task.meta.run_id || '';
				if (runId)
					return beginRefresh(result, task.meta && task.meta.scope || 'all', task.meta && task.meta.target_source_id || '', '');
				setStatus(_('已有%s正在运行，请稍后再试。').format(taskDisplayName(result, _('订阅刷新任务'))), false);
				return;
			}
			return beginRefresh(result, 'all', '', '');
		}).catch(function(error) {
			setStatus(error.message || String(error), false);
		});
	},

	handleSaveApply: null,
	handleReset: null
});
