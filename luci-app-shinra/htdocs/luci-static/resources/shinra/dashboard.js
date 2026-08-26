'use strict';
'require baseclass';

function trimTrailingSlashes(value) {
	return String(value || '').replace(/\/+$/, '');
}

function normalizePath(value, fallback) {
	let path = String(value || fallback || '/');
	if (path.charAt(0) !== '/')
		path = '/' + path;
	if (path.charAt(path.length - 1) !== '/')
		path += '/';
	return path;
}

function normalizeOrigin(value) {
	try {
		const url = new URL(String(value || ''));
		if (url.protocol !== 'http:' && url.protocol !== 'https:')
			return '';
		return url.origin;
	} catch (e) {
		return '';
	}
}

function currentOrigin() {
	return window.location.protocol + '//' + window.location.host;
}

function endpointHost(source) {
	let host = source && source.listen;
	if (!host || host === '0.0.0.0' || host === '::')
		host = window.location.hostname || location.hostname || '192.168.1.1';
	if (host.indexOf(':') >= 0 && host.charAt(0) !== '[')
		host = '[' + host + ']';
	return host;
}

function resolve(source) {
	source = source || {};
	const publicAccess = source.public_access || {};
	const configuredOrigin = normalizeOrigin(publicAccess.origin);
	const publicMode = publicAccess.enabled === true &&
		configuredOrigin !== '' &&
		configuredOrigin.toLowerCase() === normalizeOrigin(currentOrigin()).toLowerCase();

	if (publicMode) {
		const dashboardPath = normalizePath(publicAccess.dashboard_path, '/shinra/dashboard/');
		// NPS 0.34.x rewrites ordinary HTTP requests but forwards the original
		// RequestURI during WebSocket upgrades. Keep the API at origin root so
		// gRPC-Web and grpc-websockets both reach /daemon.StartedService/ intact.
		const apiPath = '/';
		const apiUrl = configuredOrigin + apiPath;
		return {
			mode: 'public',
			apiUrl: apiUrl,
			// Pass only a same-origin path. Dashboard resolves it against its own
			// public origin and deliberately rejects cross-origin query overrides.
			dashboardUrl: configuredOrigin + dashboardPath + '?api=' + encodeURIComponent(apiPath)
		};
	}

	const port = Number(source.listen_port || 20123);
	const directOrigin = 'http://' + endpointHost(source) + ':' + (Number.isFinite(port) ? port : 20123);
	return {
		mode: 'direct',
		apiUrl: directOrigin + '/',
		dashboardUrl: directOrigin + '/dashboard/'
	};
}

return baseclass.extend({
	resolve: resolve
});
