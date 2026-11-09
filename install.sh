#!/bin/sh
# Install or update luci-app-ttlfix from the latest GitHub release.
# Picks the .apk (OpenWrt 25.12+) or .ipk (24.10 and older) automatically.
#
#   wget -qO- https://raw.githubusercontent.com/miercolesv/luci-app-ttl-fix/main/install.sh | sh
#
# Or install a package file you already have:  sh install.sh /tmp/luci-app-ttlfix-<ver>.apk
set -e

REPO="miercolesv/luci-app-ttl-fix"
TMP="/tmp/ttlfix-install"

say() { echo ">> $*"; }
die() { echo "!! $*" >&2; exit 1; }

if command -v apk >/dev/null 2>&1; then
	PM=apk; EXT=apk
elif command -v opkg >/dev/null 2>&1; then
	PM=opkg; EXT=ipk
else
	die "neither apk nor opkg found - is this OpenWrt?"
fi
say "Package manager: $PM"

rm -rf "$TMP"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

if [ -n "$1" ]; then
	[ -f "$1" ] || die "file not found: $1"
	PKG="$1"
	say "Using local file $PKG"
else
	say "Looking up the latest release of $REPO..."
	wget -qO "$TMP/release.json" "https://api.github.com/repos/$REPO/releases/latest" \
		|| die "could not reach GitHub (check the router's internet connection)"
	TAG="$(grep -o '"tag_name": *"[^"]*"' "$TMP/release.json" | cut -d'"' -f4)"
	URL="$(grep -o "https://[^\"]*/releases/download/[^\"]*\.$EXT" "$TMP/release.json" | head -n1)"
	SUMS_URL="$(grep -o 'https://[^"]*/releases/download/[^"]*/SHA256SUMS' "$TMP/release.json" | head -n1)"
	[ -n "$URL" ] || die "no .$EXT package in release $TAG"
	say "Latest release: $TAG"

	PKG="$TMP/${URL##*/}"
	say "Downloading ${URL##*/}..."
	wget -qO "$PKG" "$URL" || die "download failed"

	if [ -n "$SUMS_URL" ]; then
		say "Checking SHA256..."
		wget -qO "$TMP/SHA256SUMS" "$SUMS_URL" || die "could not download SHA256SUMS"
		WANT="$(grep " ${PKG##*/}\$" "$TMP/SHA256SUMS" | cut -d' ' -f1)"
		HAVE="$(sha256sum "$PKG" | cut -d' ' -f1)"
		[ -n "$WANT" ] && [ "$WANT" = "$HAVE" ] || die "checksum mismatch for ${PKG##*/}"
		say "Checksum OK"
	fi
fi

say "Updating package lists (for dependencies)..."
if [ "$PM" = apk ]; then
	apk update
	say "Installing ${PKG##*/}..."
	apk add --allow-untrusted "$PKG"
else
	opkg update
	say "Installing ${PKG##*/}..."
	opkg install "$PKG"
fi

say "Done. Open LuCI -> Network -> TTL fix (reload the page if the menu entry is missing)."
