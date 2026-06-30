#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/luci-app-shinra"
PACKAGE_MODE="${1:-ipk}"
BUILD_DIR="${ROOT_DIR}/build/${PACKAGE_MODE}"
PKG_DIR="${BUILD_DIR}/luci-app-shinra"
CONTROL_DIR="${PKG_DIR}/CONTROL"
APK_META_DIR="${PKG_DIR}/lib/apk/packages"
IPK_DEPENDS="luci-base, rpcd, rpcd-mod-ucode, ucode, ucode-mod-fs, ucode-mod-ubus, jsonfilter, sing-box, ip-full, ca-bundle, wget-ssl, coreutils-timeout, unzip"
APK_DEPENDS="luci-base rpcd rpcd-mod-ucode ucode ucode-mod-fs ucode-mod-ubus jsonfilter sing-box ip-full ca-bundle wget-ssl coreutils-timeout unzip"

fail() {
	echo "build.sh: $*" >&2
	exit 1
}

need_file() {
	[ -f "$1" ] || fail "missing required file: $1"
}

build_script_self="${BASH_SOURCE[0]}"

if [ "$PACKAGE_MODE" = "all" ]; then
	bash "$build_script_self" ipk
	bash "$build_script_self" apk
	exit 0
fi

if [ "$PACKAGE_MODE" != "ipk" ] && [ "$PACKAGE_MODE" != "apk" ]; then
	fail "unsupported package mode: ${PACKAGE_MODE}; use ipk, apk, or all"
fi

read_make_var() {
	local name="$1"
	awk -F ':=' -v key="$name" '$1 == key { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }' "${APP_DIR}/Makefile"
}

pkg_name="$(read_make_var PKG_NAME)"
pkg_version="$(read_make_var PKG_VERSION)"
pkg_release="$(read_make_var PKG_RELEASE)"
pkg_arch="$(read_make_var LUCI_PKGARCH)"
apk_version="${pkg_version}-r${pkg_release}"

[ -n "$pkg_name" ] || fail "PKG_NAME not found"
[ -n "$pkg_version" ] || fail "PKG_VERSION not found"
[ -n "$pkg_release" ] || fail "PKG_RELEASE not found"
[ -n "$pkg_arch" ] || pkg_arch="all"

need_file "${APP_DIR}/Makefile"
need_file "${APP_DIR}/root/etc/init.d/shinra"
need_file "${APP_DIR}/root/usr/share/rpcd/ucode/shinra.uc"
need_file "${APP_DIR}/root/usr/share/rpcd/acl.d/luci-app-shinra.json"
need_file "${APP_DIR}/root/usr/share/luci/menu.d/luci-app-shinra.json"
need_file "${APP_DIR}/root/usr/libexec/shinra-ensure-auto-task"
need_file "${APP_DIR}/htdocs/luci-static/resources/view/shinra/overview.js"

rm -rf "${BUILD_DIR}"
if [ "$PACKAGE_MODE" = "apk" ]; then
	mkdir -p "${APK_META_DIR}"
else
	mkdir -p "${CONTROL_DIR}"
fi

cp -a "${APP_DIR}/root/." "${PKG_DIR}/"
mkdir -p "${PKG_DIR}/www"
cp -a "${APP_DIR}/htdocs/." "${PKG_DIR}/www/"

chmod 0755 "${PKG_DIR}/etc/init.d/shinra"
chmod 0755 "${PKG_DIR}/etc/uci-defaults/90-shinra"
chmod 0755 "${PKG_DIR}/usr/libexec/shinra-ensure-auto-task"
chmod 0755 "${PKG_DIR}/usr/libexec/shinra-auto-task"
chmod 0755 "${PKG_DIR}/usr/libexec/shinra-runner"
chmod 0755 "${PKG_DIR}/usr/libexec/shinra-ruleset-sync-job"

write_ipk_scripts() {
cat > "${CONTROL_DIR}/control" <<EOF
Package: ${pkg_name}
Version: ${pkg_version}-${pkg_release}
Architecture: ${pkg_arch}
Maintainer: Von <noreply@example.com>
Section: luci
Priority: optional
Depends: ${IPK_DEPENDS}
Description: Shinra sing-box TUN control panel for LuCI.
EOF

cat > "${CONTROL_DIR}/postinst" <<'EOF'
#!/bin/sh

set -e

if [ -z "${IPKG_INSTROOT:-}" ]; then
	if [ -x /etc/uci-defaults/90-shinra ]; then
		/etc/uci-defaults/90-shinra || true
	fi

	if [ -x /usr/libexec/shinra-ensure-auto-task ]; then
		/usr/libexec/shinra-ensure-auto-task || true
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
}

write_apk_scripts() {
	find "${PKG_DIR}" -type f,l -printf '/%P\n' | sort > "${APK_META_DIR}/${pkg_name}.list"

	cat > "${APK_META_DIR}/${pkg_name}.conffiles" <<EOF
/etc/shinra/main-profile.json
/etc/shinra/profile-source.json
/etc/shinra/notify.json
/etc/shinra/zashboard-source.json
/etc/shinra/subscriptions.json
/etc/shinra/node-snapshot.json
/etc/shinra/runtime/config.json
EOF

	while IFS= read -r file; do
		[ -f "${PKG_DIR}${file}" ] || continue
		sha256sum "${PKG_DIR}${file}" | sed "s#${PKG_DIR}/##" >> "${APK_META_DIR}/${pkg_name}.conffiles_static"
	done < "${APK_META_DIR}/${pkg_name}.conffiles"

	cat > "${BUILD_DIR}/post-install" <<'EOF'
#!/bin/sh

[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0

if [ -z "${IPKG_INSTROOT:-}" ]; then
	if [ -x /etc/uci-defaults/90-shinra ]; then
		/etc/uci-defaults/90-shinra || true
	fi

	if [ -x /usr/libexec/shinra-ensure-auto-task ]; then
		/usr/libexec/shinra-ensure-auto-task || true
	fi

	/etc/init.d/rpcd restart 2>/dev/null || true
	/etc/init.d/uhttpd restart 2>/dev/null || true
fi

exit 0
EOF

	cat > "${BUILD_DIR}/post-upgrade" <<'EOF'
#!/bin/sh

[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0

if [ -z "${IPKG_INSTROOT:-}" ]; then
	if [ -x /etc/uci-defaults/90-shinra ]; then
		/etc/uci-defaults/90-shinra || true
	fi

	if [ -x /usr/libexec/shinra-ensure-auto-task ]; then
		/usr/libexec/shinra-ensure-auto-task || true
	fi

	/etc/init.d/rpcd restart 2>/dev/null || true
	/etc/init.d/uhttpd restart 2>/dev/null || true
fi

exit 0
EOF

	cat > "${BUILD_DIR}/pre-deinstall" <<'EOF'
#!/bin/sh

if [ -z "${IPKG_INSTROOT:-}" ]; then
	/etc/init.d/shinra stop 2>/dev/null || true

	if [ -f /etc/crontabs/root ]; then
		sed -i '\#/usr/libexec/shinra-auto-task#d' /etc/crontabs/root 2>/dev/null || true
		/etc/init.d/cron restart 2>/dev/null || true
	fi
fi

exit 0
EOF

	chmod 0755 "${BUILD_DIR}/post-install" "${BUILD_DIR}/post-upgrade" "${BUILD_DIR}/pre-deinstall"
}

build_ipk() {
	write_ipk_scripts

	if ! command -v ipkg-build >/dev/null 2>&1; then
		fail "ipkg-build not found. Install it or let GitHub Actions fetch OpenWrt scripts/ipkg-build."
	fi

	(
		cd "${ROOT_DIR}"
		ipkg-build "${PKG_DIR}" "${ROOT_DIR}"
	)

	echo "Built ${ROOT_DIR}/${pkg_name}_${pkg_version}-${pkg_release}_${pkg_arch}.ipk"
}

build_apk() {
	write_apk_scripts

	if ! command -v apk >/dev/null 2>&1; then
		fail "apk not found. Install apk-tools to build APK packages."
	fi

	apk mkpkg \
		--info "name:${pkg_name}" \
		--info "version:${apk_version}" \
		--info "description:Shinra sing-box TUN control panel for LuCI." \
		--info "arch:${pkg_arch}" \
		--info "origin:https://github.com/Vonzhen/shinra" \
		--info "url:" \
		--info "maintainer:Von <noreply@example.com>" \
		--info "provides:" \
		--script "post-install:${BUILD_DIR}/post-install" \
		--script "post-upgrade:${BUILD_DIR}/post-upgrade" \
		--script "pre-deinstall:${BUILD_DIR}/pre-deinstall" \
		--info "depends:${APK_DEPENDS}" \
		--files "${PKG_DIR}" \
		--output "${ROOT_DIR}/${pkg_name}_${apk_version}_${pkg_arch}.apk"

	echo "Built ${ROOT_DIR}/${pkg_name}_${apk_version}_${pkg_arch}.apk"
}

if [ "$PACKAGE_MODE" = "apk" ]; then
	build_apk
else
	build_ipk
fi
