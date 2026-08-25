#!/bin/ash

set -eux

APK_PACKAGE="${1:?missing APK package path}"

apk update >/dev/null
apk add ca-bundle >/dev/null
apk add --allow-untrusted "$APK_PACKAGE" >/dev/null

test -x /etc/init.d/shinra
test -f /etc/shinra/dashboard.json
test -f /usr/share/rpcd/ucode/shinra.uc
test -f /www/luci-static/resources/view/shinra/panel.js

mkdir -p /var/run/ubus
/sbin/ubusd &
UBUSD_PID=$!
/sbin/rpcd &
RPCD_PID=$!

cleanup() {
	kill "$RPCD_PID" "$UBUSD_PID" 2>/dev/null || true
}
trap cleanup EXIT

ready=0
for _ in $(seq 1 20); do
	if ubus list shinra >/dev/null 2>&1; then
		ready=1
		break
	fi
	sleep 1
done

[ "$ready" -eq 1 ]

ubus call shinra dashboard_source_get >/tmp/dashboard-source.json
ubus call shinra api_status >/tmp/api-status.json
ubus call shinra overview_status >/tmp/overview-status.json
ubus call shinra config_generate >/tmp/generate.json
ubus call shinra config_check_candidate >/tmp/check.json

for result in /tmp/dashboard-source.json /tmp/api-status.json /tmp/overview-status.json /tmp/generate.json /tmp/check.json; do
	[ "$(jsonfilter -i "$result" -e '@.ok')" = "true" ]
done

test -f /etc/shinra/runtime/candidate.json
! grep -q '"clash_api"' /etc/shinra/runtime/candidate.json
grep -q '"tag": "shinra-api"' /etc/shinra/runtime/candidate.json
grep -q '"type": "api"' /etc/shinra/runtime/candidate.json
