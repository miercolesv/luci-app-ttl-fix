#!/bin/sh
# Build luci-app-ttlfix-<ver>.apk with OpenWrt's host apk tool (ImageBuilder/SDK:
# staging_dir/host/bin/apk), laid out the same way OpenWrt packs luci-app-* packages.
#   sh build-apk.sh /path/to/staging_dir/host/bin/apk [version] [outdir]
set -e

APK="$1"
VER="${2:-1.0.0-r1}"
OUT="${3:-.}"
PKG=luci-app-ttlfix
SRC="$(cd "$(dirname "$0")" && pwd)"

[ -x "$APK" ] || { echo "usage: $0 /path/to/host/bin/apk [version] [outdir]"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
STAGE="$WORK/files"
SCR="$WORK/scripts"
mkdir -p "$STAGE/www" "$STAGE/lib/apk/packages" "$SCR"

cp -a "$SRC/root/." "$STAGE/"
cp -a "$SRC/htdocs/." "$STAGE/www/"
# packaged files must be owned by root (a CI checkout belongs to another uid)
[ "$(id -u)" = 0 ] && chown -R 0:0 "$STAGE"

# OpenWrt package metadata files
echo /etc/config/ttlfix > "$STAGE/lib/apk/packages/$PKG.conffiles"
echo "/etc/config/ttlfix $(sha256sum "$STAGE/etc/config/ttlfix" | cut -d' ' -f1)" \
	> "$STAGE/lib/apk/packages/$PKG.conffiles_static"
( cd "$STAGE" && find . \( -type f -o -type l \) | sed 's#^\.##' | sort ) \
	> "$STAGE/lib/apk/packages/$PKG.list"

POSTINST='[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="'"$PKG"'"
add_group_and_user
default_postinst
[ -n "${IPKG_INSTROOT}" ] || { rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	exit 0
}'
printf '#!/bin/sh\n%s\n' "$POSTINST" > "$SCR/post-install"
printf '#!/bin/sh\nexport PKG_UPGRADE=1\n%s\n' "$POSTINST" > "$SCR/post-upgrade"
cat > "$SCR/pre-deinstall" <<EOF
#!/bin/sh
[ -s \${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. \${IPKG_INSTROOT}/lib/functions.sh
export root="\${IPKG_INSTROOT}"
export pkgname="$PKG"
default_prerm
EOF

mkdir -p "$OUT"
"$APK" mkpkg \
	--info "name:$PKG" \
	--info "version:$VER" \
	--info "description:LuCI support for TTL / hop limit override on upstream interfaces" \
	--info "arch:noarch" \
	--info "license:Apache-2.0" \
	--info "origin:feeds/luci/applications/$PKG" \
	--info "provides:$PKG-any" \
	--info "depends:libc luci-base nftables jsonfilter" \
	--script "post-install:$SCR/post-install" \
	--script "post-upgrade:$SCR/post-upgrade" \
	--script "pre-deinstall:$SCR/pre-deinstall" \
	--files "$STAGE" \
	--output "$OUT/$PKG-$VER.apk"

echo "built $OUT/$PKG-$VER.apk"
