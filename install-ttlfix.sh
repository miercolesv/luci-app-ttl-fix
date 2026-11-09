#!/bin/sh
# luci-app-ttlfix installer for OpenWrt (25.12, fw4/nftables, LuCI JS)
#   sh install-ttlfix.sh            install / update
#   sh install-ttlfix.sh uninstall  remove everything
set -e

FILES="/etc/config/ttlfix /usr/sbin/ttlfix /etc/init.d/ttlfix /etc/hotplug.d/iface/90-ttlfix /usr/share/luci/menu.d/luci-app-ttlfix.json /usr/share/rpcd/acl.d/luci-app-ttlfix.json /usr/share/ucitrack/luci-app-ttlfix.json /www/luci-static/resources/view/ttlfix.js"

if [ "$1" = "uninstall" ]; then
	/etc/init.d/ttlfix stop 2>/dev/null || true
	/etc/init.d/ttlfix disable 2>/dev/null || true
	for f in $FILES; do rm -f "$f"; done
	rm -f /var/run/ttlfix.nft
	rm -f /tmp/luci-indexcache*; rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null || true
	echo "ttlfix removed."
	exit 0
fi

for cmd in nft jsonfilter ifstatus; do
	command -v "$cmd" >/dev/null 2>&1 || { echo "missing: $cmd"; exit 1; }
done

mkdir -p "/etc/config"
if [ ! -f /etc/config/ttlfix ]; then
cat > '/etc/config/ttlfix' <<'__TTLFIX_EOF__'

config ttlfix 'main'
	option enabled '0'
	option ttl '64'
	option ipv6 '1'
	list interface 'wwan'
__TTLFIX_EOF__
chmod 644 '/etc/config/ttlfix'
fi

mkdir -p "/usr/sbin"
cat > '/usr/sbin/ttlfix' <<'__TTLFIX_EOF__'
#!/bin/sh
# ttlfix: rewrite TTL / hop limit on outgoing packets of selected interfaces.
# Uses its own nftables table (inet ttlfix), so it never touches fw4 and
# never needs a firewall restart.

. /lib/functions.sh
. /usr/share/libubox/jshn.sh

TABLE="ttlfix"
RULEFILE="/var/run/ttlfix.nft"

log() { logger -t ttlfix "$*"; }

resolve_dev() {
	# logical interface (e.g. wwan) -> L3 device (e.g. phy0-sta0)
	local dev
	dev="$(ifstatus "$1" 2>/dev/null | jsonfilter -q -e '@.l3_device')"
	[ -n "$dev" ] || dev="$(ifstatus "$1" 2>/dev/null | jsonfilter -q -e '@.device')"
	echo "$dev"
}

DEVS=""
add_dev() {
	local dev
	dev="$(resolve_dev "$1")"
	if [ -n "$dev" ]; then
		DEVS="${DEVS:+$DEVS, }\"$dev\""
	else
		log "interface '$1' is not up yet, skipped (will be applied when it comes up)"
	fi
}

remove_rules() {
	nft delete table inet "$TABLE" 2>/dev/null
	rm -f "$RULEFILE"
}

apply_rules() {
	local enabled ttl ipv6

	config_load ttlfix
	config_get_bool enabled main enabled 0
	config_get ttl main ttl 64
	config_get_bool ipv6 main ipv6 1

	if [ "$enabled" != "1" ]; then
		remove_rules
		log "disabled"
		return 0
	fi

	case "$ttl" in
		''|*[!0-9]*) log "invalid ttl '$ttl'"; return 1 ;;
	esac
	if [ "$ttl" -lt 1 ] || [ "$ttl" -gt 255 ]; then
		log "ttl '$ttl' out of range 1-255"
		return 1
	fi

	DEVS=""
	config_list_foreach main interface add_dev

	if [ -z "$DEVS" ]; then
		remove_rules
		log "no active interfaces, nothing applied"
		return 0
	fi

	mkdir -p "${RULEFILE%/*}"
	{
		echo "table inet $TABLE {"
		echo "	chain postrouting {"
		echo "		type filter hook postrouting priority 300; policy accept;"
		echo "		oifname { $DEVS } ip ttl set $ttl"
		[ "$ipv6" = "1" ] && echo "		oifname { $DEVS } ip6 hoplimit set $ttl"
		echo "	}"
		echo "}"
	} > "$RULEFILE.tmp"

	# validate first, then swap atomically
	if ! nft -c -f "$RULEFILE.tmp" 2>/dev/null; then
		log "generated rules failed validation, nothing changed"
		rm -f "$RULEFILE.tmp"
		return 1
	fi

	{ echo "table inet $TABLE"; echo "delete table inet $TABLE"; cat "$RULEFILE.tmp"; } | nft -f - \
		&& mv "$RULEFILE.tmp" "$RULEFILE" \
		&& log "applied: ttl $ttl on $DEVS"
}

status() {
	if nft list table inet "$TABLE" >/dev/null 2>&1; then
		echo "active"
		nft list table inet "$TABLE" | grep -E 'oifname'
	else
		echo "inactive"
	fi
}

case "$1" in
	apply|start|reload) apply_rules ;;
	stop|remove) remove_rules ;;
	status) status ;;
	*) echo "usage: $0 apply|remove|status"; exit 1 ;;
esac
__TTLFIX_EOF__
chmod 755 '/usr/sbin/ttlfix'

mkdir -p "/etc/init.d"
cat > '/etc/init.d/ttlfix' <<'__TTLFIX_EOF__'
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
	/usr/sbin/ttlfix apply
}

stop_service() {
	/usr/sbin/ttlfix remove
}

reload_service() {
	/usr/sbin/ttlfix apply
}

service_triggers() {
	procd_add_reload_trigger "ttlfix"
}
__TTLFIX_EOF__
chmod 755 '/etc/init.d/ttlfix'

mkdir -p "/etc/hotplug.d/iface"
cat > '/etc/hotplug.d/iface/90-ttlfix' <<'__TTLFIX_EOF__'
#!/bin/sh
# Re-apply when one of the selected interfaces comes up
# (its device name can change, e.g. after joining a new hotel network).

[ "$ACTION" = "ifup" ] || exit 0
/etc/init.d/ttlfix enabled || exit 0

. /lib/functions.sh
config_load ttlfix
config_get_bool enabled main enabled 0
[ "$enabled" = "1" ] || exit 0

match=0
check_iface() { [ "$1" = "$INTERFACE" ] && match=1; }
config_list_foreach main interface check_iface
[ "$match" = "1" ] || exit 0

/usr/sbin/ttlfix apply
__TTLFIX_EOF__
chmod 644 '/etc/hotplug.d/iface/90-ttlfix'

mkdir -p "/usr/share/luci/menu.d"
cat > '/usr/share/luci/menu.d/luci-app-ttlfix.json' <<'__TTLFIX_EOF__'
{
	"admin/network/ttlfix": {
		"title": "TTL fix",
		"order": 90,
		"action": {
			"type": "view",
			"path": "ttlfix"
		},
		"depends": {
			"acl": [ "luci-app-ttlfix" ],
			"uci": { "ttlfix": true }
		}
	}
}
__TTLFIX_EOF__
chmod 644 '/usr/share/luci/menu.d/luci-app-ttlfix.json'

mkdir -p "/usr/share/rpcd/acl.d"
cat > '/usr/share/rpcd/acl.d/luci-app-ttlfix.json' <<'__TTLFIX_EOF__'
{
	"luci-app-ttlfix": {
		"description": "Grant access to TTL fix configuration",
		"read": {
			"file": {
				"/usr/sbin/ttlfix status": [ "exec" ]
			},
			"uci": [ "ttlfix" ]
		},
		"write": {
			"file": {
				"/usr/sbin/ttlfix": [ "exec" ]
			},
			"uci": [ "ttlfix" ]
		}
	}
}
__TTLFIX_EOF__
chmod 644 '/usr/share/rpcd/acl.d/luci-app-ttlfix.json'

mkdir -p "/usr/share/ucitrack"
cat > '/usr/share/ucitrack/luci-app-ttlfix.json' <<'__TTLFIX_EOF__'
{
	"config": "ttlfix",
	"init": "ttlfix"
}
__TTLFIX_EOF__
chmod 644 '/usr/share/ucitrack/luci-app-ttlfix.json'

mkdir -p "/www/luci-static/resources/view"
cat > '/www/luci-static/resources/view/ttlfix.js' <<'__TTLFIX_EOF__'
'use strict';
'require view';
'require form';
'require fs';
'require poll';
'require tools.widgets as widgets';

function renderStatus(res) {
	var out = ((res && res.stdout) || '').trim().split('\n');
	var active = out[0] === 'active';
	var rules = out.slice(1).map(function(l) { return l.trim(); }).filter(Boolean);

	return E('div', {}, [
		E('p', {}, [
			E('strong', {}, _('Status') + ': '),
			E('span', { 'style': 'color:' + (active ? 'green' : 'gray') },
				active ? _('Active') : _('Inactive'))
		]),
		rules.length ? E('pre', { 'style': 'white-space:pre-wrap' }, rules.join('\n')) : ''
	]);
}

return view.extend({
	load: function() {
		return fs.exec('/usr/sbin/ttlfix', [ 'status' ]).catch(function() { return null; });
	},

	render: function(statusRes) {
		var m, s, o;

		m = new form.Map('ttlfix', _('TTL fix'),
			_('Sets a fixed TTL (IPv4) and hop limit (IPv6) on packets leaving the selected interfaces, so traffic from devices behind this router looks like it comes from a single device. Uses its own nftables table; the firewall is not restarted.'));

		s = m.section(form.NamedSection, 'main', 'ttlfix');
		s.anonymous = true;

		o = s.option(form.DummyValue, '_status', _('Current state'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return E('div', { 'id': 'ttlfix-status' }, renderStatus(statusRes));
		};

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.rmempty = false;

		o = s.option(form.Value, 'ttl', _('TTL / hop limit'),
			_('64 matches Linux, Android, macOS and iOS. 128 matches Windows.'));
		o.datatype = 'range(1,255)';
		o.placeholder = '64';
		o.default = '64';
		o.value('64', '64 (Linux, Android, Apple)');
		o.value('128', '128 (Windows)');
		o.rmempty = false;

		o = s.option(widgets.NetworkSelect, 'interface', _('Interfaces'),
			_('Upstream interfaces to apply this to, usually the hotel or client Wi-Fi uplink (e.g. wwan). Reapplied automatically whenever one comes up.'));
		o.multiple = true;
		o.nocreate = true;
		o.rmempty = false;

		o = s.option(form.Flag, 'ipv6', _('Also set IPv6 hop limit'));
		o.default = '1';
		o.rmempty = false;

		poll.add(function() {
			return fs.exec('/usr/sbin/ttlfix', [ 'status' ]).then(function(res) {
				var el = document.getElementById('ttlfix-status');
				if (el) {
					while (el.firstChild) el.removeChild(el.firstChild);
					el.appendChild(renderStatus(res));
				}
			}).catch(function() {});
		}, 5);

		return m.render();
	}
});
__TTLFIX_EOF__
chmod 644 '/www/luci-static/resources/view/ttlfix.js'

set +e
/etc/init.d/ttlfix enable
/etc/init.d/ttlfix restart
rm -f /tmp/luci-indexcache*; rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload

echo "ttlfix installed. Open LuCI -> Network -> TTL fix (reload the page)."
echo "It starts disabled; enable it there or with:"
echo "  uci set ttlfix.main.enabled=1 && uci commit ttlfix && /etc/init.d/ttlfix reload"
