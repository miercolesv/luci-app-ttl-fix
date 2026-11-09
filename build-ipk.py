#!/usr/bin/env python3
"""Build luci-app-ttlfix_<ver>_all.ipk for opkg-based OpenWrt (24.10 and older),
using the same layout as OpenWrt's ipkg-build. No OpenWrt tools needed.

    python3 build-ipk.py [version] [outdir]
"""
import io, os, sys, tarfile, time

PKG = "luci-app-ttlfix"
VER = sys.argv[1] if len(sys.argv) > 1 else "1.0.0-r1"
OUT = sys.argv[2] if len(sys.argv) > 2 else "."
SRC = os.path.dirname(os.path.abspath(__file__))
MTIME = int(os.environ.get("SOURCE_DATE_EPOCH", time.time()))

FILES = [  # (source in this folder, path on router)
    ("root/etc/config/ttlfix", "etc/config/ttlfix"),
    ("root/etc/hotplug.d/iface/90-ttlfix", "etc/hotplug.d/iface/90-ttlfix"),
    ("root/etc/init.d/ttlfix", "etc/init.d/ttlfix"),
    ("root/etc/uci-defaults/80-luci-ttlfix", "etc/uci-defaults/80-luci-ttlfix"),
    ("root/usr/sbin/ttlfix", "usr/sbin/ttlfix"),
    ("root/usr/share/luci/menu.d/luci-app-ttlfix.json", "usr/share/luci/menu.d/luci-app-ttlfix.json"),
    ("root/usr/share/rpcd/acl.d/luci-app-ttlfix.json", "usr/share/rpcd/acl.d/luci-app-ttlfix.json"),
    ("root/usr/share/ucitrack/luci-app-ttlfix.json", "usr/share/ucitrack/luci-app-ttlfix.json"),
    ("htdocs/luci-static/resources/view/ttlfix.js", "www/luci-static/resources/view/ttlfix.js"),
]
EXEC = {"etc/init.d/ttlfix", "usr/sbin/ttlfix", "etc/hotplug.d/iface/90-ttlfix",
        "etc/uci-defaults/80-luci-ttlfix"}

POSTINST = """#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_postinst $0 $@
[ -n "${IPKG_INSTROOT}" ] || { rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	exit 0
}
"""
PRERM = """#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_prerm $0 $@
"""


def add(tar, name, data=None, mode=0o644, isdir=False):
    ti = tarfile.TarInfo("./" + name if name else ".")
    ti.uid = ti.gid = 0
    ti.uname = ti.gname = "root"
    ti.mtime = MTIME
    if isdir:
        ti.type, ti.mode = tarfile.DIRTYPE, 0o755
        tar.addfile(ti)
    else:
        ti.mode, ti.size = mode, len(data)
        tar.addfile(ti, io.BytesIO(data))


def targz(build):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz", format=tarfile.GNU_FORMAT) as t:
        build(t)
    return buf.getvalue()


def data_tar(t):
    add(t, "", isdir=True)
    dirs = sorted({"/".join(dst.split("/")[:i]) for _, dst in FILES
                   for i in range(1, dst.count("/") + 1)})
    for d in dirs:
        add(t, d, isdir=True)
    for src, dst in FILES:
        add(t, dst, open(os.path.join(SRC, src), "rb").read(),
            0o755 if dst in EXEC else 0o644)


data = targz(data_tar)
size = sum(os.path.getsize(os.path.join(SRC, s)) for s, _ in FILES)
control = f"""Package: {PKG}
Version: {VER}
Depends: libc, luci-base, nftables, jsonfilter
Source: feeds/luci/applications/{PKG}
SourceName: {PKG}
License: Apache-2.0
Section: luci
URL: https://github.com/openwrt/luci
Architecture: all
Installed-Size: {size}
Description:  LuCI support for TTL / hop limit override on upstream interfaces
"""


def control_tar(t):
    add(t, "", isdir=True)
    add(t, "control", control.encode())
    add(t, "conffiles", b"/etc/config/ttlfix\n")
    add(t, "postinst", POSTINST.encode(), 0o755)
    add(t, "prerm", PRERM.encode(), 0o755)


ctrl = targz(control_tar)


def outer(t):
    add(t, "debian-binary", b"2.0\n")
    add(t, "data.tar.gz", data)
    add(t, "control.tar.gz", ctrl)


os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, f"{PKG}_{VER}_all.ipk")
open(path, "wb").write(targz(outer))
print("built", path)
