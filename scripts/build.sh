#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/luci-app-shinra"
BUILD_DIR="${ROOT_DIR}/build/ipk"
PKG_DIR="${BUILD_DIR}/luci-app-shinra"
CONTROL_DIR="${PKG_DIR}/CONTROL"

fail() {
	echo "build.sh: $*" >&2
	exit 1
}

need_file() {
	[ -f "$1" ] || fail "missing required file: $1"
}

read_make_var() {
	local name="$1"
	awk -F ':=' -v key="$name" '$1 == key { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }' "${APP_DIR}/Makefile"
}

pkg_name="$(read_make_var PKG_NAME)"
pkg_version="$(read_make_var PKG_VERSION)"
pkg_release="$(read_make_var PKG_RELEASE)"
pkg_arch="$(read_make_var LUCI_PKGARCH)"

[ -n "$pkg_name" ] || fail "PKG_NAME not found"
[ -n "$pkg_version" ] || fail "PKG_VERSION not found"
[ -n "$pkg_release" ] || fail "PKG_RELEASE not found"
[ -n "$pkg_arch" ] || pkg_arch="all"

need_file "${APP_DIR}/Makefile"
need_file "${APP_DIR}/root/etc/init.d/shinra"
need_file "${APP_DIR}/root/usr/share/rpcd/ucode/shinra.uc"
need_file "${APP_DIR}/root/usr/share/rpcd/acl.d/luci-app-shinra.json"
need_file "${APP_DIR}/root/usr/share/luci/menu.d/luci-app-shinra.json"
need_file "${APP_DIR}/htdocs/luci-static/resources/view/shinra/overview.js"

rm -rf "${BUILD_DIR}"
mkdir -p "${CONTROL_DIR}"

cp -a "${APP_DIR}/root/." "${PKG_DIR}/"
mkdir -p "${PKG_DIR}/www"
cp -a "${APP_DIR}/htdocs/." "${PKG_DIR}/www/"

chmod 0755 "${PKG_DIR}/etc/init.d/shinra"
chmod 0755 "${PKG_DIR}/etc/uci-defaults/90-shinra"
chmod 0755 "${PKG_DIR}/usr/libexec/shinra-auto-task"

cat > "${CONTROL_DIR}/control" <<EOF
Package: ${pkg_name}
Version: ${pkg_version}-${pkg_release}
Architecture: ${pkg_arch}
Maintainer: Von <noreply@example.com>
Section: luci
Priority: optional
Depends: luci-base, rpcd, rpcd-mod-ucode, ucode, ucode-mod-fs, ucode-mod-ubus, jsonfilter, sing-box, ip-full, ca-bundle, wget-ssl
Description: Shinra sing-box TUN control panel for LuCI.
EOF

cat > "${CONTROL_DIR}/postinst" <<'EOF'
#!/bin/sh

set -e

if [ -z "${IPKG_INSTROOT:-}" ]; then
	if [ -x /etc/uci-defaults/90-shinra ]; then
		/etc/uci-defaults/90-shinra || true
	fi

	/etc/init.d/rpcd restart 2>/dev/null || true
	/etc/init.d/uhttpd restart 2>/dev/null || true
fi

exit 0
EOF

cat > "${CONTROL_DIR}/prerm" <<'EOF'
#!/bin/sh

set -e

if [ -z "${IPKG_INSTROOT:-}" ]; then
	/etc/init.d/shinra stop 2>/dev/null || true

	if [ -f /etc/crontabs/root ]; then
		sed -i '\#/usr/libexec/shinra-auto-task#d' /etc/crontabs/root 2>/dev/null || true
		/etc/init.d/cron restart 2>/dev/null || true
	fi
fi

exit 0
EOF

chmod 0755 "${CONTROL_DIR}/postinst" "${CONTROL_DIR}/prerm"

if ! command -v ipkg-build >/dev/null 2>&1; then
	fail "ipkg-build not found. Install it or let GitHub Actions fetch OpenWrt scripts/ipkg-build."
fi

(
	cd "${ROOT_DIR}"
	ipkg-build "${PKG_DIR}" "${ROOT_DIR}"
)

echo "Built ${ROOT_DIR}/${pkg_name}_${pkg_version}-${pkg_release}_${pkg_arch}.ipk"
