# luci-app-ttlfix

LuCI page for OpenWrt that rewrites the TTL (and IPv6 hop limit) of packets leaving selected interfaces, e.g. `wwan` on a travel router.

It uses its own nftables table (`inet ttlfix`), so it never touches fw4 and doesn't need a firewall restart. Rules are re-applied by a hotplug hook when a selected interface comes up.

## Install

Download from [Releases](../../releases), copy to the router's `/tmp`, then:

| OpenWrt | Package | Command |
|---|---|---|
| 25.12+ | `.apk` | `apk add --allow-untrusted /tmp/luci-app-ttlfix-<ver>.apk` |
| 24.10 and older | `.ipk` | `opkg install /tmp/luci-app-ttlfix_<ver>_all.ipk` |

Or without a package manager: `sh install-ttlfix.sh` (and `sh install-ttlfix.sh uninstall` to remove).

Settings are under **Network → TTL fix**. Status from the shell: `ttlfix status`.

## Build

- `.ipk`: `python3 build-ipk.py <version> <outdir>` — no OpenWrt tools needed.
- `.apk`: `sh build-apk.sh /path/to/apk <version> <outdir>` — needs apk-tools v3 (OpenWrt SDK/ImageBuilder `staging_dir/host/bin/apk`, or Alpine 3.23+).
- In an OpenWrt tree: put this folder at `feeds/luci/applications/luci-app-ttlfix` and run `make package/luci-app-ttlfix/compile`.

## Release

Bump `PKG_VERSION` / `PKG_RELEASE` in the `Makefile`, then push a matching tag:

```sh
git tag v1.0.0-r1 && git push origin v1.0.0-r1
```

GitHub Actions builds both packages, adds `install-ttlfix.sh` and `SHA256SUMS`, and publishes the release. The workflow fails if the tag doesn't match the Makefile version.
