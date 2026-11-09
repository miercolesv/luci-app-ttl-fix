# Build inside an OpenWrt / LuCI feed tree:
#   place this folder at feeds/luci/applications/luci-app-ttlfix
#   make package/luci-app-ttlfix/compile

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for TTL / hop limit override
LUCI_DEPENDS:=+luci-base +nftables +jsonfilter
LUCI_PKGARCH:=all

PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0

define Package/luci-app-ttlfix/conffiles
/etc/config/ttlfix
endef

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
