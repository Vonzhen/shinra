#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
	echo "usage: $0 /path/to/luci-app-shinra_*.apk" >&2
	exit 64
fi

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
APK_PATH="$(readlink -f -- "$1")"
OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.5}"
ROOTFS_DIR="$(mktemp -d)"
ROOTFS_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/x86/64/openwrt-${OPENWRT_VERSION}-x86-64-rootfs.tar.gz"

cleanup() {
	set +e
	sudo umount -l "${ROOTFS_DIR}/workspace" 2>/dev/null
	sudo umount -l "${ROOTFS_DIR}/dev" 2>/dev/null
	sudo umount -l "${ROOTFS_DIR}/sys" 2>/dev/null
	sudo umount -l "${ROOTFS_DIR}/proc" 2>/dev/null
	rm -rf "${ROOTFS_DIR}"
}
trap cleanup EXIT

curl --fail --location --retry 3 --output "${ROOTFS_DIR}/rootfs.tar.gz" "${ROOTFS_URL}"
sudo tar -xzf "${ROOTFS_DIR}/rootfs.tar.gz" -C "${ROOTFS_DIR}"
sudo mkdir -p "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/workspace" "${ROOTFS_DIR}/tmp/shinra-test"
sudo mount -t proc proc "${ROOTFS_DIR}/proc"
sudo mount -t sysfs sysfs "${ROOTFS_DIR}/sys"
sudo mount --rbind /dev "${ROOTFS_DIR}/dev"
sudo mount --make-rslave "${ROOTFS_DIR}/dev"
sudo mount --bind "${ROOT_DIR}" "${ROOTFS_DIR}/workspace"
sudo cp "${APK_PATH}" "${ROOTFS_DIR}/tmp/shinra-test/luci-app-shinra.apk"
sudo cp /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"

sudo chroot "${ROOTFS_DIR}" /bin/ash /workspace/tests/openwrt-apk-inside.sh /tmp/shinra-test/luci-app-shinra.apk
