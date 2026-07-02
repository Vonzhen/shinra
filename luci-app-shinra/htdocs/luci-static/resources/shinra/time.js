'use strict';
'require baseclass';

function pad(value) {
	return value < 10 ? '0' + value : String(value);
}

function formatLocalTime(value) {
	if (!value || typeof value !== 'string')
		return value || '-';
	if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(value))
		return value;

	const date = new Date(value);
	if (Number.isNaN(date.getTime()))
		return value;

	return '%s-%s-%s %s:%s:%s'.format(
		date.getFullYear(),
		pad(date.getMonth() + 1),
		pad(date.getDate()),
		pad(date.getHours()),
		pad(date.getMinutes()),
		pad(date.getSeconds())
	);
}

function formatMaybeTime(value, fallback) {
	if (value == null || value === '')
		return fallback || '-';
	return formatLocalTime(String(value));
}

return baseclass.extend({
	formatLocalTime: formatLocalTime,
	formatMaybeTime: formatMaybeTime
});
