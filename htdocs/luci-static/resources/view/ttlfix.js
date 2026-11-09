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
