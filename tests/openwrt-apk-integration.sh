#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
	echo "usage: $0 /path/to/luci-app-shinra_*.apk" >&2
	exit 64
fi

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
APK_PATH="$(readlink -f -- "$1")"
OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.5}"
OPENWRT_IMAGE="openwrt/rootfs:x86_64-${OPENWRT_VERSION}"

docker run --rm --privileged \
	-v "${ROOT_DIR}:/workspace:ro" \
	-v "${APK_PATH}:/tmp/luci-app-shinra.apk:ro" \
	"${OPENWRT_IMAGE}" \
	/bin/ash -ec '
		setup="$(find / -maxdepth 4 -name setup.sh | head -n 1)"
		[ -n "$setup" ]
		cd "$(dirname "$setup")"
		[ -d ./scripts ] || ./setup.sh
		/bin/ash /workspace/tests/openwrt-apk-inside.sh /tmp/luci-app-shinra.apk
	'
