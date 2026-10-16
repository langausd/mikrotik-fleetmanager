// cfm-Monitor (D77, D81; bis 2026-10-16 „cfm-WLAN“): Lesezeichen für WebFig, zwei Reiter.
// WLAN: die WLAN-Clients aller APs live (eine Kachel je AP) und als Zeitleiste je Client, damit sich Roaming
// nachvollziehen lässt; nur in WebFig des CAPsMAN. Liest per REST derselben Adresse (kein CORS):
// Registrierungstabelle, WLAN-Interfaces (Feld cap = AP), CAPs, DHCP-Leases (Namen) und das Log
// (WLAN-Ereignisse von vor dem Öffnen). Ändert nichts am Gerät; der Verlauf bleibt im Browser (localStorage, 24 h).
// Suche: startet $cfmFind per :execute auf dem Manager (nur in dessen WebFig, User der Gruppe full) und zeigt
// die Treffer als Tabelle. Bauen: tools/editor/build.py -> install.html
(() => {
  // Steckt schon eine Fassung in der Seite: dieselbe nur einblenden, eine andere ersetzen (WebFig lädt
  // die Seite nicht neu, ein ersetztes Lesezeichen wirkte sonst erst nach F5). STAND setzt build.py ein.
  const STAND = '@@STAND@@';
  const alt = window.__cfmWl;
  if (alt && alt.stand === STAND) { alt.show(); return; }
  if (alt && alt.drop && !alt.drop()) { alt.show(); return; }
  document.getElementById('cfmwl')?.remove();
  const KEEP = 24 * 3600e3;
  const PAL = ['#1f77b4', '#e8710a', '#2ca02c', '#9467bd', '#8c564b', '#d6338a', '#12939a', '#a39e14', '#5f6b6d', '#c62828'];
  const S = { ident: '', tab: 'wlan', mgr: false, findOk: true, mgrAddr: '', every: 10, span: 3600e3, timer: null, busy: false, tick: 0, first: true,
    ifs: {}, caps: {}, names: {}, alias: {}, cur: {}, hist: {}, ev: [], logEv: [], logKeys: {}, off: 0, err: '', last: 0, saved: 0 };
  const KEY = 'cfm-wlan:' + location.host;
  const $ = (sel) => root.querySelector(sel);
  const el = (tag, attrs, ...kids) => {
    const e = document.createElement(tag);
    Object.entries(attrs || {}).forEach(([k, v]) => k.startsWith('on') ? e.addEventListener(k.slice(2), v) : e.setAttribute(k, v));
    kids.forEach((k) => e.append(k));
    return e;
  };
  const sv = (tag, attrs, ...kids) => {
    const e = document.createElementNS('http://www.w3.org/2000/svg', tag);
    Object.entries(attrs || {}).forEach(([k, v]) => e.setAttribute(k, v));
    kids.forEach((k) => e.append(k));
    return e;
  };
  const tip = (t) => sv('title', {}, t);
  const hm = (t) => new Date(t).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
  const hms = (t) => new Date(t).toLocaleTimeString('de-DE');
  // RouterOS-Dauer: "1w2d03:04:05", "3h4m5s", "250ms"
  function dur(s) {
    s = String(s || '');
    let t = 0;
    const c = s.match(/(\d+):(\d\d):(\d\d)$/);
    if (c) { t += c[1] * 3600 + c[2] * 60 + +c[3]; s = s.slice(0, c.index); }
    for (const m of s.matchAll(/(\d+)(ms|w|d|h|m|s)/g)) t += m[1] * { ms: 0.001, w: 604800, d: 86400, h: 3600, m: 60, s: 1 }[m[2]];
    return t;
  }
  const bandOf = (b) => { const m = String(b || '').match(/^(\d)ghz/); return m ? m[1] : ''; };
  const bandTxt = (b) => ({ 2: '2,4 GHz', 5: '5 GHz', 6: '6 GHz' })[b] || '?';
  const sigCol = (d) => d === null ? '#99a' : d >= -60 ? '#2e7d32' : d >= -67 ? '#7cb342' : d >= -75 ? '#f2a900' : d >= -82 ? '#ef6c00' : '#c62828';
  const name = (mac) => S.alias[mac] || (S.names[mac] && S.names[mac].name) || mac;
  const apCol = (ap) => {
    const l = Object.keys(apList()).sort();
    const i = l.indexOf(ap);
    return i < 0 ? '#99a' : PAL[i % PAL.length];
  };

  const css = `
#cfmwl{position:fixed;inset:0;z-index:2147483000;background:#f4f5f4;color:#1d2321;font:13px system-ui,sans-serif;display:flex;flex-direction:column}
#cfmwl *{box-sizing:border-box}
#cfmwl header{display:flex;align-items:center;gap:8px;padding:6px 10px;background:#13534b;color:#fff;flex-wrap:wrap}
#cfmwl header b{font-size:14px;margin-right:8px}
#cfmwl button{font:inherit;padding:4px 10px;border:1px solid #9aa;border-radius:4px;background:#fff;color:#1d2321;cursor:pointer}
#cfmwl button.prim{background:#13534b;color:#fff;border-color:#13534b}
#cfmwl input,#cfmwl select{font:inherit;padding:3px 6px;border:1px solid #9aa;border-radius:4px}
#cfmwl .sp{flex:1}
#cfmwl .st{font-size:12px;opacity:.9}
#cfmwl main{flex:1;overflow:auto;padding:10px}
#cfmwl h3{margin:14px 0 6px;font-size:13px;text-transform:uppercase;letter-spacing:.04em;color:#556}
#cfmwl .tiles{display:flex;flex-wrap:wrap;gap:10px}
#cfmwl .tile{background:#fff;border:1px solid #ccd;border-top:4px solid var(--c);border-radius:6px;padding:8px 10px;min-width:230px;flex:1 1 230px;max-width:420px}
#cfmwl .tile h4{margin:0 0 2px;font-size:14px;display:flex;gap:6px;align-items:baseline}
#cfmwl .tile .fr{font-size:11px;color:#667;margin-bottom:6px}
#cfmwl .tile .off{color:#b3261e;font-size:12px}
#cfmwl .cl{display:grid;grid-template-columns:1fr auto 64px 44px;gap:6px;align-items:center;padding:3px 4px;border-radius:4px;transition:background 1s}
#cfmwl .cl.neu{background:#fff3c4}
#cfmwl .cl .n{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;cursor:pointer}
#cfmwl .cl .n small{color:#778;margin-left:4px}
#cfmwl .bd{font-size:11px;padding:0 5px;border-radius:8px;background:#e6ecea;color:#334}
#cfmwl .bar{height:8px;background:#e6e8e6;border-radius:4px;overflow:hidden}
#cfmwl .bar i{display:block;height:100%}
#cfmwl .db{font:12px ui-monospace,Menlo,Consolas,monospace;text-align:right}
#cfmwl .leer{color:#889;font-size:12px}
#cfmwl .tl{background:#fff;border:1px solid #ccd;border-radius:6px;padding:6px;overflow:hidden}
#cfmwl .tl text{font:11px system-ui,sans-serif;fill:#1d2321}
#cfmwl .tl .ax{fill:#667}
#cfmwl .lg{display:flex;flex-wrap:wrap;gap:10px;font-size:12px;margin:6px 2px}
#cfmwl .lg span::before{content:"";display:inline-block;width:12px;height:12px;border-radius:2px;background:var(--c);margin-right:4px;vertical-align:-2px}
#cfmwl table{border-collapse:collapse;background:#fff;border:1px solid #ccd;width:100%}
#cfmwl td{padding:3px 8px;border-top:1px solid #eef;font-size:12px;white-space:nowrap}
#cfmwl td.w{white-space:normal}
#cfmwl header .tab{background:transparent;color:#fff;border-color:#fff6}
#cfmwl header .tab.akt{background:#fff;color:#13534b;border-color:#fff}
#cfmwl .ff{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-bottom:8px}
#cfmwl .ff input{width:110px}
#cfmwl .ff input.q{width:260px}
#cfmwl .ff label{font-size:12px;color:#556;display:flex;gap:4px;align-items:center}
#cfmwl .hits th{text-align:left;padding:4px 8px;font-size:12px;background:#eef1ef;cursor:pointer;white-space:nowrap;user-select:none}
#cfmwl .hits td a{color:#13534b;cursor:pointer;text-decoration:none;border-bottom:1px dotted #13534b}
#cfmwl .hits td.m{font:12px ui-monospace,Menlo,Consolas,monospace}
#cfmwl .hits .bar{display:inline-block;width:60px;vertical-align:middle;margin-right:6px}
#cfmwl .note{font-size:12px;color:#556;white-space:pre-wrap;margin:6px 0}
#cfmwl .login{margin:12vh auto;background:#fff;padding:20px 24px;border-radius:8px;box-shadow:0 2px 12px #0002;display:grid;gap:8px;width:340px}
#cfmwl .fehler{color:#b3261e}`;

  const root = el('div', { id: 'cfmwl' });
  root.append(el('style', {}, css));
  document.body.append(root);

  // ---------- REST ----------
  async function rest(method, path, body) {
    // cache: RouterOS schickt zu REST-Antworten Cache-Control max-age=31536000 (7.24.5) - ohne no-store
    // lieferte der Browser alte Registrierungstabellen und eine alte Uhrzeit. Zugangsdaten: siehe loginView
    const r = await fetch('/rest' + path, {
      method, cache: 'no-store', headers: { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const t = await r.text();
    let j = null;
    try { j = t ? JSON.parse(t) : null; } catch (e) { j = t; }
    if (!r.ok) throw new Error(r.status + ' ' + ((j && (j.detail || j.message)) || t));
    return j;
  }

  // ---------- Daten vom Gerät ----------
  // WLAN-Interfaces: dynamische Interfaces eines CAP tragen cap="<Identity>@<MAC>%…", eigene Radios nicht
  async function loadIfs() {
    const ifs = {};
    for (const i of await rest('GET', '/interface/wifi')) {
      const cap = String(i.cap || '');
      ifs[i.name] = { ap: cap ? cap.split('@')[0] : '', band: bandOf(i['channel.band']), freq: String(i['channel.frequency'] || ''),
        ssid: String(i['configuration.ssid'] || ''), master: String(i['master-interface'] || ''),
        off: i.disabled === 'true' || i.disabled === true };
    }
    for (const n in ifs) {
      const f = ifs[n], m = ifs[f.master];
      if (m) { f.ap = f.ap || m.ap; f.band = f.band || m.band; f.freq = f.freq || m.freq; }
      f.ap = f.ap || S.ident;
    }
    S.ifs = ifs;
  }
  async function loadCaps() {
    const c = {};
    for (const x of await rest('GET', '/interface/wifi/capsman/remote-cap').catch(() => [])) c[x.identity] = String(x.state || '');
    S.caps = c;
  }
  // Namen aus den Leases dieses Geräts (cfm-Lease: Name aus leases.rsc, sonst host-name)
  async function loadNames() {
    const n = {};
    for (const x of await rest('GET', '/ip/dhcp-server/lease').catch(() => [])) {
      const mac = String(x['mac-address'] || '').toUpperCase();
      if (!mac) continue;
      const m = String(x.comment || '').match(/^cfm:lease:\d+:(\S+)/);
      n[mac] = { name: m ? m[1] : String(x['host-name'] || ''), ip: String(x['active-address'] || x.address || '') };
    }
    S.names = n;
  }
  // Uhr des Geräts: Log-Zeiten sind Gerätezeit, die Proben Browserzeit
  async function loadClock() {
    const c = await rest('GET', '/system/clock');
    const t = devTime(c.date + ' ' + c.time, true);
    if (t) S.off = Date.now() - t;
  }
  function devTime(s, raw) {
    s = String(s || '').trim();
    const now = new Date(Date.now() - S.off);
    let d = null, m;
    if ((m = s.match(/^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)$/))) d = new Date(m[1], m[2] - 1, m[3], m[4], m[5], m[6]);
    else if ((m = s.match(/^(\d\d):(\d\d):(\d\d)$/))) d = new Date(now.getFullYear(), now.getMonth(), now.getDate(), m[1], m[2], m[3]);
    else if ((m = s.match(/^([a-z]{3})\/(\d\d)(?:\/(\d{4}))? (\d\d):(\d\d):(\d\d)$/i))) {
      d = new Date(m[3] || now.getFullYear(), 'janfebmaraprmayjunjulaugsepoctnovdec'.indexOf(m[1].toLowerCase()) / 3, m[2], m[4], m[5], m[6]);
    }
    if (!d || isNaN(d)) return 0;
    return raw ? d.getTime() : d.getTime() + S.off;
  }
  // WLAN-Ereignisse aus dem Log (CAPsMAN 7.24, Interface mit SSID in Klammern), z.B.
  // "AA:BB:CC:DD:EE:FF@ap1-5g(Demo) connected, signal strength -61"
  // "AA:BB:CC:DD:EE:FF@ap1-5g(Demo) roamed to AA:BB:CC:DD:EE:FF@ap2-6g(Demo), signal strength -77"
  // Bei roamed ist iface das neue Interface, prev das alte.
  async function loadLog() {
    let l;
    try { l = await rest('POST', '/log/print', { '.proplist': ['.id', 'time', 'topics', 'message'] }); } catch (e) { l = await rest('GET', '/log'); }
    const MI = '([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})@([^\\s,(]+)(?:\\([^)]*\\))?';
    const re = new RegExp(MI + '[:,]?\\s+(connected|disconnected|roamed)\\b(?:\\s+to\\s+' + MI + ')?[,:]?\\s*(.*)$');
    for (const x of l || []) {
      const msg = String(x.message || '');
      const m = msg.match(re);
      if (!m) continue;
      const k = x['.id'] + '|' + msg;
      if (S.logKeys[k]) continue;
      S.logKeys[k] = 1;
      const t = devTime(x.time);
      if (!t) continue;
      const sg = msg.match(/signal(?: strength)?[:=]?\s*(-\d+)/i);
      const to = m[3] === 'roamed' && m[5];
      S.logEv.push({ t, mac: m[1].toUpperCase(), iface: to || m[2], prev: to ? m[2] : '', kind: m[3], sig: sg ? +sg[1] : null, txt: m[6] });
    }
    S.logEv = S.logEv.filter((e) => e.t > Date.now() - KEEP).sort((a, b) => a.t - b.t);
  }

  // ---------- Abfrage ----------
  async function poll() {
    if (S.busy) return;
    S.busy = true;
    try {
      const every = (sec) => S.tick % Math.max(1, Math.round(sec / S.every)) === 0;
      if (every(60)) { await loadClock().catch(() => {}); await loadIfs(); await loadCaps(); await loadNames(); }
      if (every(30)) await loadLog().catch(() => {});
      S.tick++;
      const reg = await rest('GET', '/interface/wifi/registration-table');
      const now = Date.now();
      const seen = {};
      let neuIf = false;
      for (const r of reg || []) {
        const mac = String(r['mac-address'] || '').toUpperCase();
        if (!mac) continue;
        seen[mac] = 1;
        const iface = String(r.interface || '');
        if (!S.ifs[iface]) neuIf = true;
        const f = S.ifs[iface] || { ap: iface, band: '', freq: '', ssid: '' };
        const sg = parseInt(r.signal !== undefined ? r.signal : r['signal-strength'], 10);
        const up = dur(r.uptime);
        const c = { mac, iface, ap: f.ap, band: bandOf(r.band) || f.band, ssid: String(r.ssid || f.ssid), sig: isNaN(sg) ? null : sg,
          tx: String(r['tx-rate'] || ''), rx: String(r['rx-rate'] || ''), up, since: up ? now - up * 1000 : now };
        const o = S.cur[mac];
        if (!o) { if (!S.first) event(c.since, mac, 'connect', null, c); }
        else if (o.iface !== iface) event(c.since, mac, 'roam', o, c);
        else if (up + S.every + 5 < o.up) event(c.since, mac, 'reconnect', o, c);
        track(now, c, o);
        S.cur[mac] = c;
      }
      for (const mac in S.cur) {
        if (seen[mac]) continue;
        event(now, mac, 'disconnect', S.cur[mac], null);
        const h = S.hist[mac], s = h && h[h.length - 1];
        if (s && !s.to) s.to = s.last;
        delete S.cur[mac];
      }
      if (neuIf) S.tick = 0;            // unbekanntes Interface: beim nächsten Lauf neu einlesen
      S.first = false;
      S.err = '';
      S.last = now;
      if (now - S.saved > 60e3) save();
    } catch (e) {
      S.err = e.message;
      if (/^401/.test(e.message)) { stop(); restOk(false); loginView('Anmeldung abgelaufen - bitte neu anmelden.'); S.busy = false; return; }
    }
    S.busy = false;
    render();
  }
  function event(t, mac, kind, o, c) {
    S.ev.push({ t, mac, kind, from: o ? { ap: o.ap, band: o.band, sig: o.sig } : null, to: c ? { ap: c.ap, band: c.band, sig: c.sig } : null });
    if (S.ev.length > 1000) S.ev.splice(0, S.ev.length - 1000);
  }
  // Abschnitt je Verbindung: AP, Band, Zeitraum, Signalproben (nur bei Änderung >= 2 dB oder je Minute)
  function track(now, c, o) {
    const h = S.hist[c.mac] || (S.hist[c.mac] = []);
    let s = h[h.length - 1];
    if (!s || s.to || s.iface !== c.iface || (o && c.up + S.every + 5 < o.up)) {
      let from = c.since;
      if (s && !s.to) { s.to = Math.max(s.last, Math.min(now, from)); }
      if (s && s.to) from = Math.max(from, s.to);
      s = { iface: c.iface, ap: c.ap, band: c.band, from, to: 0, last: now, sig: [] };
      h.push(s);
    }
    s.last = now; s.ap = c.ap; s.band = c.band;
    const p = s.sig[s.sig.length - 1];
    if (c.sig !== null && (!p || Math.abs(p[1] - c.sig) >= 2 || now - p[0] >= 60e3)) s.sig.push([now, c.sig]);
  }

  // ---------- Verlauf im Browser ----------
  function save() {
    const lim = Date.now() - KEEP;
    for (const mac in S.hist) {
      S.hist[mac] = S.hist[mac].filter((s) => !s.to || s.to > lim);
      S.hist[mac].forEach((s) => { s.sig = s.sig.filter((p) => p[0] > lim); });
      if (!S.hist[mac].length) delete S.hist[mac];
    }
    S.ev = S.ev.filter((e) => e.t > lim);
    S.saved = Date.now();
    try { localStorage.setItem(KEY, JSON.stringify({ hist: S.hist, ev: S.ev, alias: S.alias })); } catch (e) { /* Speicher voll oder gesperrt */ }
  }
  function restore() {
    try {
      const d = JSON.parse(localStorage.getItem(KEY) || 'null');
      if (!d) return;
      S.hist = d.hist || {}; S.ev = d.ev || []; S.alias = d.alias || {};
      // offene Abschnitte aus einer früheren Sitzung enden bei ihrer letzten Probe
      for (const mac in S.hist) S.hist[mac].forEach((s) => { if (!s.to) s.to = s.last; });
    } catch (e) { /* ohne Verlauf weiter */ }
  }

  // ---------- Darstellung ----------
  function apList() {
    const a = {};
    for (const n in S.ifs) if (!S.ifs[n].off && !S.ifs[n].master) a[S.ifs[n].ap] = 1;
    for (const ap in S.caps) a[ap] = 1;
    for (const m in S.cur) a[S.cur[m].ap] = 1;
    return a;
  }
  function render() {
    const m = $('main');
    if (!m) return;
    const st = $('.st');
    st.textContent = (S.err ? 'Fehler: ' + S.err : S.last ? 'Stand ' + hms(S.last) : 'lädt …') + ' · ' + Object.keys(S.cur).length + ' WLAN-Clients';
    if (S.tab !== 'wlan') return;          // die Suche baut ihre Ansicht selbst (Eingaben behalten den Fokus)
    const top = m.scrollTop;
    m.replaceChildren(el('h3', {}, 'APs jetzt'), tiles(), el('h3', {}, 'Zeitleiste'), timeline(), el('h3', {}, 'Ereignisse'), events());
    m.scrollTop = top;
  }
  function tiles() {
    const box = el('div', { class: 'tiles' });
    const aps = Object.keys(apList()).sort();
    const now = Date.now();
    for (const ap of aps) {
      const fr = {};
      for (const n in S.ifs) { const f = S.ifs[n]; if (f.ap === ap && !f.master && !f.off && f.freq) fr[f.band] = bandTxt(f.band) + ' ' + f.freq; }
      const t = el('div', { class: 'tile', style: '--c:' + apCol(ap) },
        el('h4', {}, ap, el('small', { class: 'leer' }, ap === S.ident ? '(dieses Gerät)' : '')),
        el('div', { class: 'fr' }, Object.keys(fr).sort().map((b) => fr[b]).join(' · ') || ' '));
      if (S.caps[ap] && S.caps[ap] !== 'Ok') t.append(el('div', { class: 'off' }, 'CAP-Zustand: ' + S.caps[ap]));
      const cl = Object.values(S.cur).filter((c) => c.ap === ap).sort((a, b) => (b.sig ?? -999) - (a.sig ?? -999));
      if (!cl.length) t.append(el('div', { class: 'leer' }, 'keine Clients'));
      for (const c of cl) {
        const r = S.ev.slice().reverse().find((e) => e.mac === c.mac && e.kind === 'roam' && now - e.t < 60e3);
        const w = c.sig === null ? 0 : Math.max(4, Math.min(100, (c.sig + 90) / 60 * 100));
        const n = el('span', { class: 'n', title: c.mac + (S.names[c.mac] && S.names[c.mac].ip ? ' · ' + S.names[c.mac].ip : '') + ' · SSID ' + c.ssid + ' · ' + c.iface + ' · Rate ' + c.tx + ' / ' + c.rx + ' · verbunden seit ' + hms(c.since) + ' (Klick: umbenennen)' },
          name(c.mac), el('small', {}, r ? '← ' + r.from.ap : 'seit ' + hm(c.since)));
        n.addEventListener('click', () => rename(c.mac));
        t.append(el('div', { class: 'cl' + (r ? ' neu' : '') }, n, el('span', { class: 'bd' }, bandTxt(c.band)),
          el('div', { class: 'bar' }, el('i', { style: 'width:' + w + '%;background:' + sigCol(c.sig) })),
          el('span', { class: 'db' }, c.sig === null ? '?' : c.sig)));
      }
      box.append(t);
    }
    if (!aps.length) box.append(el('div', { class: 'leer' }, 'Keine WLAN-Interfaces gefunden - die WLAN-Ansicht gehört in WebFig des CAPsMAN.'));
    return box;
  }
  // Abschnitte aus dem Log (vor dem Öffnen der Seite): connected bis disconnected bzw. bis zur nächsten Verbindung
  function logSegs(mac) {
    const out = [];
    let o = null;
    for (const e of S.logEv) {
      if (e.mac !== mac) continue;
      if (o && (e.kind !== 'disconnected' || e.iface === o.iface)) { o.to = e.t; out.push(o); o = null; }
      if (e.kind === 'connected' || e.kind === 'roamed') {
        const f = S.ifs[e.iface] || { ap: e.iface, band: '' };
        o = { iface: e.iface, ap: f.ap, band: f.band, from: e.t, to: 0, sig: e.sig === null ? [] : [[e.t, e.sig]] };
      }
    }
    if (o) { o.to = S.cur[mac] && S.cur[mac].iface === o.iface ? Date.now() : o.from; out.push(o); }
    return out.filter((s) => s.to > s.from);
  }
  function timeline() {
    const now = Date.now(), t0 = now - S.span;
    const W = Math.max(600, ($('main').clientWidth || 1000) - 34), LW = 170, RH = 20, GAP = 5, TOP = 22;
    const x = (t) => LW + (Math.max(t0, Math.min(now, t)) - t0) / S.span * (W - LW - 8);
    const macs = new Set(Object.keys(S.cur));
    for (const mac in S.hist) if (S.hist[mac].some((s) => (s.to || now) > t0)) macs.add(mac);
    for (const e of S.logEv) if (e.t > t0) macs.add(e.mac);
    const rows = [...macs].sort((a, b) => (S.cur[b] ? 1 : 0) - (S.cur[a] ? 1 : 0) || name(a).localeCompare(name(b)));
    const H = TOP + rows.length * (RH + GAP) + 6;
    const g = sv('svg', { width: W, height: Math.max(H, 50), viewBox: '0 0 ' + W + ' ' + Math.max(H, 50) });
    const step = [[15 * 60e3, 2 * 60e3], [3600e3, 10 * 60e3], [6 * 3600e3, 3600e3], [Infinity, 3 * 3600e3]].find((s) => S.span <= s[0])[1];
    for (let t = Math.ceil(t0 / step) * step; t <= now; t += step) {
      g.append(sv('line', { x1: x(t), x2: x(t), y1: TOP - 4, y2: H, stroke: '#e3e6e3' }), sv('text', { x: x(t), y: 12, 'text-anchor': 'middle', class: 'ax' }, hm(t)));
    }
    rows.forEach((mac, i) => {
      const y = TOP + i * (RH + GAP);
      const nm = sv('text', { x: 4, y: y + 14 }, (S.cur[mac] ? '● ' : '○ ') + name(mac).slice(0, 26));
      nm.append(tip(mac + (S.names[mac] && S.names[mac].ip ? ' · ' + S.names[mac].ip : '')));
      g.append(sv('rect', { x: LW, y, width: W - LW - 8, height: RH, fill: '#f6f7f6' }), nm);
      const seg = (s, log) => {
        const a = x(s.from), b = x(s.to || now);
        if (b - a < 0.5) return;
        const r = sv('rect', { x: a, y: y + (log ? 3 : 0), width: Math.max(1, b - a), height: RH - (log ? 6 : 0), fill: apCol(s.ap), 'fill-opacity': log ? 0.35 : s.band === '2' ? 0.6 : 0.9 });
        const sg = s.sig.map((p) => p[1]);
        r.append(tip(s.ap + ' ' + bandTxt(s.band) + ' (' + s.iface + '), ' + hms(s.from) + '–' + (s.to ? hms(s.to) : 'jetzt') +
          (sg.length ? ', Signal ' + Math.max(...sg) + ' … ' + Math.min(...sg) + ' dBm' : '') + (log ? ' – aus dem Log' : '')));
        g.append(r);
        if (b - a > 34) g.append(sv('text', { x: a + 3, y: y + 14, fill: '#fff', style: 'fill:#fff;pointer-events:none' }, s.ap.slice(0, Math.floor((b - a) / 7)) + ' ' + (s.band === '2' ? '2,4' : s.band)));
        if (!log && s.sig.length) {
          const pts = s.sig.filter((p) => p[0] >= t0).map((p) => x(p[0]).toFixed(1) + ',' + (y + RH - (Math.max(-90, Math.min(-30, p[1])) + 90) / 60 * RH).toFixed(1));
          if (s.to === 0 && pts.length) pts.push(x(now).toFixed(1) + ',' + pts[pts.length - 1].split(',')[1]);
          if (pts.length > 1) g.append(sv('polyline', { points: pts.join(' '), fill: 'none', stroke: '#1d2321', 'stroke-opacity': 0.55, 'stroke-width': 1.2, style: 'pointer-events:none' }));
        }
      };
      logSegs(mac).forEach((s) => seg(s, true));
      (S.hist[mac] || []).forEach((s) => seg(s, false));
      const mark = (t, txt) => {
        const l = sv('path', { d: 'M' + x(t) + ' ' + (y - 2) + 'l-4 -5h8z', fill: '#1d2321' });
        l.append(tip(hms(t) + ' ' + txt));
        g.append(l);
      };
      const live = S.ev.filter((e) => e.mac === mac && e.t >= t0 && (e.kind === 'roam' || e.kind === 'reconnect'));
      live.forEach((e) => mark(e.t, evTxt(e)));
      // Wechsel aus dem Log, sofern nicht schon live erkannt (Abfrageabstand + Spielraum)
      for (const e of S.logEv) {
        if (e.mac !== mac || e.t < t0 || e.kind !== 'roamed') continue;
        if (live.some((v) => Math.abs(v.t - e.t) <= (S.every + 10) * 1000)) continue;
        mark(e.t, logTxt(e));
      }
    });
    if (!rows.length) g.append(sv('text', { x: LW, y: TOP + 14, class: 'ax' }, 'noch keine Daten in diesem Zeitraum'));
    const lg = el('div', { class: 'lg' });
    Object.keys(apList()).sort().forEach((ap) => lg.append(el('span', { style: '--c:' + apCol(ap) }, ap)));
    lg.append(el('small', { class: 'leer' }, 'kräftig 5/6 GHz, blass 2,4 GHz, schmal = aus dem Log; Linie = Signal (-90 … -30 dBm); ▼ = Wechsel'));
    return el('div', { class: 'tl' }, g, lg);
  }
  function evTxt(e) {
    const d = (p) => p ? p.ap + ' ' + bandTxt(p.band) + (p.sig !== null && p.sig !== undefined ? ' (' + p.sig + ' dBm)' : '') : '';
    return { roam: 'Wechsel ' + d(e.from) + ' → ' + d(e.to), reconnect: 'neu verbunden an ' + d(e.to), connect: 'verbunden an ' + d(e.to), disconnect: 'getrennt von ' + d(e.from) }[e.kind] || e.kind;
  }
  // Log-Ereignis wie die übrigen: AP und Band statt Interface, Grund ohne Signalangabe
  function logTxt(e) {
    const ifTxt = (n) => { const f = S.ifs[n]; return f ? f.ap + ' ' + bandTxt(f.band) : n; };
    const w = (e.prev ? ifTxt(e.prev) + ' → ' : '') + ifTxt(e.iface);
    const r = e.txt.replace(/,?\s*signal(?: strength)?[:=]?\s*-\d+/i, '').replace(/^[,\s]+/, '');
    return { connected: 'verbunden an ', disconnected: 'getrennt von ', roamed: 'Wechsel ' }[e.kind] + w +
      (e.sig !== null ? ' (' + e.sig + ' dBm)' : '') + (r ? ': ' + r : '');
  }
  function events() {
    const l = S.ev.map((e) => ({ t: e.t, mac: e.mac, txt: evTxt(e), src: '' }))
      .concat(S.logEv.map((e) => ({ t: e.t, mac: e.mac, txt: logTxt(e), src: 'Log' })))
      .filter((e) => e.t > Date.now() - S.span).sort((a, b) => b.t - a.t).slice(0, 80);
    if (!l.length) return el('div', { class: 'leer' }, 'keine Ereignisse in diesem Zeitraum');
    return el('table', {}, ...l.map((e) => el('tr', {}, el('td', {}, hms(e.t)), el('td', {}, name(e.mac)), el('td', { class: 'w' }, e.txt), el('td', { class: 'leer' }, e.src))));
  }
  function rename(mac) {
    const v = prompt('Name für ' + mac + ' (leer = Name aus DHCP):', S.alias[mac] || '');
    if (v === null) return;
    if (v.trim()) S.alias[mac] = v.trim(); else delete S.alias[mac];
    save(); render();
  }

  // ---------- Suche ($cfmFind auf dem Manager, D81) ----------
  const ENDE = '@@cfm-ende@@', JS = '@@cfm-json@@';
  // RouterOS-String: \ " $ maskieren, Zeilenumbruch als \n
  const esc = (s) => String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\$/g, '\\$').replace(/\r/g, '').replace(/\n/g, '\\n');
  const FK = ['host', 'port', 'ap', 'ssid', 'vlan', 'signal'];
  const F = { q: '', host: '', port: '', ap: '', ssid: '', vlan: '', signal: '', hits: null, note: '', busy: false, sort: 'ort', dir: 1 };
  // Manager? Sonst die Adresse, von der dieses Gerät zuletzt gezogen hat (state.json des Agents)
  async function detect() {
    S.mgr = ((await rest('GET', '/system/script?name=cfm-mgr').catch(() => [])) || []).length > 0;
    if (S.mgr) {
      // Manager-Module vor D81: dort ist $cfmFind noch der alte interne Helfer (heute $cfmIds)
      const net = ((await rest('GET', '/system/script?name=cfm-mgr-net').catch(() => [])) || [])[0];
      S.findOk = !net || net.source === undefined || String(net.source).includes(':global cfmFind do={');
      return;
    }
    for (const n of ['cfm/state.json', 'flash/cfm/state.json']) {
      try {
        const f = ((await rest('GET', '/file?name=' + encodeURIComponent(n))) || [])[0];
        if (!f) continue;
        const j = JSON.parse((await rest('POST', '/file/get', { '.id': f['.id'], 'value-name': 'contents' })).ret || '{}');
        if (j.mgr) { S.mgrAddr = String(j.mgr); return; }
      } catch (e) { /* nächster Pfad */ }
    }
  }
  async function search() {
    if (F.busy) return;
    if (!F.q && !FK.some((k) => F[k])) { F.note = 'Suchtext oder einen Filter angeben.'; findView(); return; }
    F.busy = true; F.note = 'Suche läuft (etwa eine Sekunde je Gerät) …'; findView();
    const cmd = '$cfmFind "' + esc(F.q) + '"' + FK.map((k) => F[k] ? ' ' + k + '="' + esc(F[k]) + '"' : '').join('') + ' quiet=yes';
    const body = '/system script run cfm-mgr; :global cfmFind; :onerror e in={ :put ("' + JS + '" . [:serialize to=json [' + cmd + ']]) } do={ :put ("FEHLER: " . $e) }; :put "' + ENDE + '"';
    const fn = 'cfm-mon-' + Date.now() + '.txt';
    let txt = '';
    try {
      const job = String((await rest('POST', '/execute', { script: ':put [:execute script="' + esc(body) + '" file="' + fn + '"]', 'as-string': true })).ret || '').trim();
      const t0 = Date.now();
      let fertig = false;
      while (!fertig && Date.now() - t0 < 5 * 60e3) {
        await new Promise((r) => setTimeout(r, 1000));
        // einzelne Fehlversuche (Verbindung) überstehen, erst die Frist bricht ab
        try {
          const f = ((await rest('GET', '/file?name=' + encodeURIComponent(fn))) || [])[0];
          if (f) txt = String((await rest('POST', '/file/get', { '.id': f['.id'], 'value-name': 'contents' })).ret || '').replace(/\r/g, '');
          fertig = txt.includes(ENDE);
          if (!fertig && job) {
            const jobs = await rest('GET', '/system/script/job');
            if (!jobs.some((j) => j['.id'] === job)) fertig = true;
          }
        } catch (e) { if (/^401/.test(e.message)) throw e; }
      }
      const f = ((await rest('GET', '/file?name=' + encodeURIComponent(fn)).catch(() => [])) || [])[0];
      if (f) await rest('DELETE', '/file/' + f['.id']).catch(() => {});
      const ls = txt.split('\n').filter((l) => l.trim() && l !== ENDE && !/^Script file loaded and executed successfully$/.test(l.trim()));
      const jl = ls.find((l) => l.startsWith(JS));
      const jt = jl ? jl.slice(JS.length).trim() : '';
      F.hits = jt ? JSON.parse(jt) : null;
      if (jl && !jt) ls.push('Der Manager lieferte nichts: $cfmFind fehlt dort (Framework vor D81?).');
      F.note = ls.filter((l) => !l.startsWith(JS)).join('\n') || (fertig ? '' : 'keine Rückmeldung nach 5 min');
      if (!Array.isArray(F.hits)) F.hits = [];
    } catch (e) {
      F.note = 'Fehler: ' + e.message + (/40[13]|permission|not allowed/i.test(e.message) ? ' – die Suche braucht einen User der Gruppe full' : '');
    }
    F.busy = false;
    findView();
  }
  // Treffer in Zeilen für die Tabelle; Name: eigener Name aus der WLAN-Ansicht, sonst aus cfm/DHCP
  function rows() {
    const arr = (v) => Array.isArray(v) ? v.map(String) : v === undefined || v === null || v === '' ? [] : [String(v)];
    return (F.hits || []).map((h) => {
      const b = Array.isArray(h.best) ? h.best.map(String) : [];
      const w = h.w && !Array.isArray(h.w) && h.w.ap !== undefined ? h.w : null;
      const mac = String(h.mac || '');
      const nm = S.alias[mac] || arr(h.name)[0] || '';
      const ips = arr(h.ip);
      const sig = w ? parseInt(w.sig, 10) : NaN;
      let info = '';
      if (w) info = 'seit ' + w.up + (w.rate ? ' · ' + Math.round(+w.rate / 1e6) + ' Mbit/s' : '');
      else if (b.length && (h.uplink === true || h.uplink === 'true')) info = 'über Uplink zu ' + b[3];
      else if (b.length) info = [b[3] ? 'Nachbar ' + b[3] : '', +b[4] > 1 ? b[4] + ' MACs am Port' : ''].filter(Boolean).join(', ');
      else info = 'nur ARP/Lease bei ' + String(h.src || '?');
      return { mac, nm, ips, dev: w ? String(w.ap) : b[0] || '', port: w ? '' : b[1] || '', band: w ? String(w.band) : '',
        vlan: String(w ? w.vid : b[2] || ''), ssid: w ? String(w.ssid) : '', sig: isNaN(sig) ? null : sig, info, wl: !!w,
        ort: w ? w.ap + ' ' + w.band : b.length ? b[0] + ' ' + b[1] : '' };
    });
  }
  function findView() {
    const m = $('main');
    if (!m || S.tab !== 'find') return;
    if (!S.mgr) {
      m.replaceChildren(el('div', { class: 'note' }, 'Die Suche läuft auf dem cfm-Manager. ' +
        (S.mgrAddr ? 'WebFig des Managers öffnen: http://' + S.mgrAddr + '/webfig/' : 'Dieses Gerät ist es nicht; WebFig des Managers öffnen.') +
        ' Dort das Lesezeichen erneut anklicken (User der Gruppe full).'));
      return;
    }
    if (!S.findOk) {
      m.replaceChildren(el('div', { class: 'note' }, 'Dieser Manager hat die Suche noch nicht: Seine Manager-Module sind älter als D81 ' +
        '(2026-10-16), dort ist $cfmFind noch ein interner Helfer. Sie kommt mit dem Framework-Update ' +
        '(upload-seed.sh, $cfmRelease), sobald der Manager die neue Version selbst angewendet hat (sein Ring).'));
      return;
    }
    let form = $('.ff');
    if (!form) {
      const inp = (k, ph, cls) => {
        const i = el('input', { placeholder: ph, value: F[k], class: cls || '' });
        i.addEventListener('input', () => { F[k] = i.value.trim(); });
        i.dataset.k = k;
        return i;
      };
      form = el('form', { class: 'ff', onsubmit: (e) => { e.preventDefault(); search(); } },
        inp('q', 'MAC, IP, Name, Gerät:Port, AP, SSID', 'q'),
        el('label', {}, 'Gerät', inp('host', 'z.B. sw1')), el('label', {}, 'Port', inp('port', 'ether7')),
        el('label', {}, 'AP', inp('ap', '')), el('label', {}, 'SSID', inp('ssid', '')),
        el('label', {}, 'VLAN', inp('vlan', '')), el('label', {}, 'Signal ≤', inp('signal', '-75')),
        el('button', { class: 'prim', type: 'submit' }, 'Suchen'),
        el('button', { type: 'button', onclick: () => { ['q', ...FK].forEach((k) => { F[k] = ''; }); form.querySelectorAll('input').forEach((i) => { i.value = ''; }); } }, 'Leeren'));
      m.replaceChildren(form, el('div', { class: 'res' }));
      form.querySelector('input').focus();
    }
    form.querySelectorAll('input').forEach((i) => { if (document.activeElement !== i) i.value = F[i.dataset.k]; });
    form.querySelector('button.prim').disabled = F.busy;
    const res = $('.res');
    const out = [];
    if (F.note) out.push(el('div', { class: 'note' }, F.note));
    if (F.hits && !F.busy) {
      const rs = rows();
      const key = { name: (r) => r.nm.toLowerCase() || '~', mac: (r) => r.mac, ip: (r) => r.ips[0] || '~', ort: (r) => r.ort.toLowerCase() || '~',
        vlan: (r) => +r.vlan || 0, ssid: (r) => r.ssid.toLowerCase() || '~', sig: (r) => r.sig === null ? 999 : r.sig }[F.sort];
      rs.sort((a, b) => { const x = key(a), y = key(b); return (x < y ? -1 : x > y ? 1 : 0) * F.dir; });
      // Klick sucht danach: alle anderen Angaben leeren
      const go = (set) => {
        ['q', ...FK].forEach((k) => { F[k] = ''; }); Object.assign(F, set);
        form.querySelectorAll('input').forEach((i) => { i.value = F[i.dataset.k]; });
        search();
      };
      const a = (txt, set, title) => { const x = el('a', { title: title || 'danach suchen' }, txt); x.addEventListener('click', () => go(set)); return x; };
      const th = (k, t) => { const h = el('th', { title: 'sortieren' }, t + (F.sort === k ? (F.dir > 0 ? ' ▲' : ' ▼') : '')); h.addEventListener('click', () => { F.dir = F.sort === k ? -F.dir : 1; F.sort = k; findView(); }); return h; };
      const tr = rs.map((r) => {
        const ort = r.wl ? [a(r.dev, { ap: r.dev }, 'Clients dieses APs'), ' ' + r.band]
          : r.dev ? [a(r.dev, { host: r.dev }, 'alles an diesem Gerät'), ' ', a(r.port, { host: r.dev, port: r.port }, 'was hängt an diesem Port?')] : ['–'];
        const w = r.sig === null ? 0 : Math.max(4, Math.min(100, (r.sig + 90) / 60 * 100));
        return el('tr', {}, el('td', {}, r.nm), el('td', { class: 'm' }, a(r.mac, { q: r.mac }, 'nur diese MAC')),
          el('td', { class: 'm', title: r.ips.join(', ') }, r.ips[0] || '', r.ips.length > 1 ? ' +' + (r.ips.length - 1) : ''),
          el('td', {}, ...ort), el('td', {}, r.vlan ? a(r.vlan, { vlan: r.vlan }, 'alles in diesem VLAN') : ''),
          el('td', {}, r.ssid ? a(r.ssid, { ssid: r.ssid }, 'alle Clients dieser SSID') : ''),
          el('td', { class: 'm' }, ...(r.sig === null ? [] : [el('div', { class: 'bar' }, el('i', { style: 'width:' + w + '%;background:' + sigCol(r.sig) })), String(r.sig)])),
          el('td', { class: 'w' }, r.info));
      });
      out.push(el('div', { class: 'note' }, rs.length + ' Treffer'));
      if (rs.length) out.push(el('table', { class: 'hits' }, el('tr', {}, th('name', 'Name'), th('mac', 'MAC'), th('ip', 'IP'), th('ort', 'Ort'),
        th('vlan', 'VLAN'), th('ssid', 'SSID'), th('sig', 'Signal'), el('th', {}, 'Info')), ...tr));
    }
    res.replaceChildren(...out);
  }
  function tab(t) {
    S.tab = t;
    root.querySelectorAll('header .tab').forEach((b) => b.classList.toggle('akt', b.dataset.t === t));
    root.querySelectorAll('header .wl').forEach((b) => { b.style.display = t === 'wlan' ? '' : 'none'; });
    const m = $('main');
    if (m) m.replaceChildren();
    if (t === 'wlan') render(); else findView();
  }

  // ---------- Rahmen ----------
  function stop() { clearInterval(S.timer); S.timer = null; }
  function start() { stop(); S.timer = setInterval(poll, S.every * 1000); poll(); }
  function hide() { stop(); save(); root.style.display = 'none'; }
  function show() { root.style.display = 'flex'; if (S.ident && root.querySelector('header')) start(); }
  window.__cfmWl = { stand: STAND, show, drop: () => { stop(); save(); root.remove(); return true; } };

  // Anmeldung: eigenes Formular (der Passwort-Manager füllt es wie die WebFig-Anmeldung derselben
  // Adresse), geprüft per XHR mit User/Passwort. Der Browser merkt sich die Daten dann für alle weiteren
  // REST-Aufrufe ohne Authorization-Kopf bis zum Schließen, auch für das andere Lesezeichen. Ohne
  // gemerkte Daten öffnete ein fetch ohne Kopf das Anmeldefenster des Browsers, in dem man sich nach
  // einem Tippfehler nicht mehr korrigieren kann - darum nur nach einer Anmeldung in diesem Tab
  // (sessionStorage cfmRestOk, ohne Passwort). XHR mit Daten öffnet das Fenster nie.
  const xhrLogin = (u, p) => new Promise((res) => {
    const x = new XMLHttpRequest();
    x.open('GET', '/rest/system/identity', true, u, p);
    x.onload = () => res(x.status); x.onerror = () => res(0);
    x.send();
  });
  const restOk = (v) => {
    try {
      if (v === undefined) return sessionStorage.getItem('cfmRestOk') === '1';
      if (v) sessionStorage.setItem('cfmRestOk', '1'); else sessionStorage.removeItem('cfmRestOk');
    } catch (e) { return false; }
  };
  async function loginView(hinweis) {
    root.querySelectorAll('header,main,.login').forEach((n) => n.remove());
    if (!hinweis && restOk()) {
      let ok = false;
      try { S.ident = (await rest('GET', '/system/identity')).name; ok = true; } catch (e) { restOk(false); }
      if (ok) { mainView(); return; }
    }
    const u = el('input', { name: 'username', placeholder: 'Benutzer', autocomplete: 'username' });
    const p = el('input', { name: 'password', type: 'password', placeholder: 'Passwort', autocomplete: 'current-password' });
    const msg = el('div', { class: 'fehler' }, hinweis || '');
    const go = async (e) => {
      e.preventDefault();
      msg.textContent = '';
      const st = await xhrLogin(u.value, p.value);
      if (st !== 200) { msg.textContent = 'Anmeldung fehlgeschlagen (' + (st || 'keine Verbindung') + ').'; p.select(); return; }
      restOk(true);
      try { S.ident = (await rest('GET', '/system/identity')).name; } catch (e2) { msg.textContent = 'Fehler: ' + e2.message; return; }
      mainView();
    };
    root.append(el('form', { class: 'login', onsubmit: go }, el('b', {}, 'cfm-Monitor'),
      el('div', {}, 'WLAN-Clients und Roaming (in WebFig des CAPsMAN, Lesen genügt) und Gerätesuche (in WebFig des Managers, Gruppe full). Anmeldung an der REST-API dieses Geräts.'),
      u, p, el('button', { class: 'prim', type: 'submit' }, 'Anmelden'), msg,
      el('button', { type: 'button', onclick: hide }, 'Schließen')));
    u.focus();
  }
  async function mainView() {
    root.querySelectorAll('header,main,.login').forEach((n) => n.remove());
    await detect();
    const span = el('select', { title: 'Zeitraum der Zeitleiste', class: 'wl' },
      ...[['15 min', 15 * 60e3], ['1 h', 3600e3], ['6 h', 6 * 3600e3], ['24 h', 24 * 3600e3]].map(([l, v]) => {
        const o = el('option', { value: v }, l); if (v === S.span) o.selected = true; return o;
      }));
    span.addEventListener('change', () => { S.span = +span.value; render(); });
    const ev = el('select', { title: 'Abfrage alle …', class: 'wl' },
      ...[5, 10, 30].map((v) => { const o = el('option', { value: v }, 'alle ' + v + ' s'); if (v === S.every) o.selected = true; return o; }));
    ev.addEventListener('change', () => { S.every = +ev.value; S.tick = 0; start(); });
    const tb = (t, l) => { const b = el('button', { class: 'tab', type: 'button' }, l); b.dataset.t = t; b.addEventListener('click', () => tab(t)); return b; };
    root.append(el('header', {}, el('b', {}, 'cfm-Monitor – ' + S.ident), tb('wlan', 'WLAN'), tb('find', 'Suche'), el('span', { class: 'st' }, ''),
      el('span', { class: 'sp' }), span, ev,
      el('button', { class: 'wl', onclick: () => { if (confirm('Verlauf im Browser löschen?')) { S.hist = {}; S.ev = []; save(); render(); } } }, 'Verlauf leeren'),
      el('button', { onclick: hide }, 'Schließen')), el('main', {}));
    S.first = true; S.cur = {}; S.tick = 0;
    start();
    // Start im Reiter Suche, wenn dies der Manager ist und kein WLAN hat (sonst nach der ersten Abfrage)
    tab(S.tab);
    setTimeout(() => { if (S.mgr && !Object.keys(apList()).length && S.tab === 'wlan') tab('find'); }, 3000);
  }

  restore();
  loginView();
})();
