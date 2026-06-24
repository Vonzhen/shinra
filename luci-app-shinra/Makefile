include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-shinra
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

LUCI_TITLE:=Shinra sing-box TUN control panel
LUCI_DEPENDS:=+luci-base +rpcd +rpcd-mod-ucode +ucode +ucode-mod-fs +ucode-mod-ubus +jsonfilter +sing-box +ip-full +ca-bundle +wget-ssl
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
