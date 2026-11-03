// cfm-DNS (DN3.2): Lesezeichen für WebFig eines Routers (Rolle router mit dns.rsc self). Zeigt die DNS-Abfragen
// aus dem RAM-Puffer cfmdns (DN3.1): gesperrte Namen der letzten Minuten, Top-Domains, Freischaltungen. Ein User
// der Gruppe cfm-dns (self.user, nur Lesen) sieht nur die Abfragen der eigenen IP, ein User mit Schreibrecht
// alle. „Freischalten anfragen“ schreibt per /execute einen Log-Eintrag und startet das Skript cfm-dnsreq: es
// schaltet die Domain für self.hours frei (außer self.deny) und meldet sie an notify.url. Admins machen eine
// befristete Freischaltung dauerhaft (dnsui:perm) oder entfernen sie. Liest per REST derselben Adresse (kein
// CORS), das Log immer ganz (RouterOS filtert REST-Abfragen des Logs nicht nach Zeit oder .id).
// Bauen: tools/editor/build.py -> install.html
(() => {
  const STAND = '@@STAND@@';
  const alt = window.__cfmDns;
  if (alt && alt.stand === STAND) { alt.show(); return; }
  if (alt && alt.drop) alt.drop();
  document.getElementById('cfmdns')?.remove();
  const S = { ident: '', user: '', admin: false, ip: '', ips: [], sel: '', every: 30, win: 15, timer: null, busy: false,
    q: {}, names: {}, st: [], dur: 0, deny: [], self: false, err: '', last: 0, filt: '', tab: 'block' };
  const el = (tag, attrs, ...kids) => {
    const e = document.createElement(tag);
    Object.entries(attrs || {}).forEach(([k, v]) => k.startsWith('on') ? e.addEventListener(k.slice(2), v) : e.setAttribute(k, v));
    kids.forEach((k) => e.append(k));
    return e;
  };
  const hm = (t) => new Date(t).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
  const hms = (t) => new Date(t).toLocaleTimeString('de-DE');

  const css = `
#cfmdns{position:fixed;inset:0;z-index:2147483000;background:#f4f5f4;color:#1d2321;font:13px system-ui,sans-serif;display:flex;flex-direction:column}
#cfmdns *{box-sizing:border-box}
#cfmdns header{display:flex;align-items:center;gap:8px;padding:6px 10px;background:#13534b;color:#fff;flex-wrap:wrap}
#cfmdns header b{font-size:14px;margin-right:8px}
#cfmdns button{font:inherit;padding:4px 10px;border:1px solid #9aa;border-radius:4px;background:#fff;color:#1d2321;cursor:pointer}
#cfmdns button.prim{background:#13534b;color:#fff;border-color:#13534b}
#cfmdns button.klein{padding:1px 8px;font-size:12px}
#cfmdns input,#cfmdns select{font:inherit;padding:3px 6px;border:1px solid #9aa;border-radius:4px}
#cfmdns .sp{flex:1}
#cfmdns .st{font-size:12px;opacity:.9}
#cfmdns header .tab{background:transparent;color:#fff;border-color:#fff6}
#cfmdns header .tab.akt{background:#fff;color:#13534b;border-color:#fff}
#cfmdns main{flex:1;overflow:auto;padding:10px}
#cfmdns table{border-collapse:collapse;background:#fff;border:1px solid #ccd;width:100%}
#cfmdns th{text-align:left;padding:4px 8px;font-size:12px;background:#eef1ef;white-space:nowrap}
#cfmdns td{padding:3px 8px;border-top:1px solid #eef;font-size:12px;white-space:nowrap}
#cfmdns td.m{font:12px ui-monospace,Menlo,Consolas,monospace}
#cfmdns td.w{white-space:normal;word-break:break-all}
#cfmdns .note{font-size:12px;color:#556;margin:6px 0}
#cfmdns .hinweis{background:#fff3c4;border:1px solid #e6cf6e;border-radius:6px;padding:8px 10px;margin-bottom:8px}
#cfmdns .ok{background:#e3f1e5;border:1px solid #9ccaa3;border-radius:6px;padding:8px 10px;margin-bottom:8px}
#cfmdns .rot{color:#b3261e}
#cfmdns .gr{color:#2e7d32}
#cfmdns .ff{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-bottom:8px}
#cfmdns .login{margin:12vh auto;background:#fff;padding:20px 24px;border-radius:8px;box-shadow:0 2px 12px #0002;display:grid;gap:8px;width:340px}
#cfmdns .fehler{color:#b3261e}`;
  const root = el('div', { id: 'cfmdns' });
  root.append(el('style', {}, css));
  document.body.append(root);
  const $ = (sel) => root.querySelector(sel);

  // ---------- REST (wie cfm-Monitor: no-store, Anmeldung per XHR) ----------
  async function rest(method, path, body) {
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
  const xhrLogin = (u, p) => new Promise((res) => {
    const x = new XMLHttpRequest();
    x.open('GET', '/rest/system/identity', true, u, p);
    x.onload = () => res(x.status); x.onerror = () => res(0);
    x.send();
  });
  const sess = (k, v) => {
    try {
      if (v === undefined) return sessionStorage.getItem(k) || '';
      if (v) sessionStorage.setItem(k, v); else sessionStorage.removeItem(k);
    } catch (e) { return ''; }
  };

  // ---------- Wer bin ich? ----------
  // Rechte: Schreibrecht in der Gruppe = Admin (sieht alle Clients, macht dauerhaft). Eigene IP: /user/active zeigt
  // jede REST-Anfrage mit Adresse - dieselbe Abfrage zweimal, gemeinsame Adressen bleiben (ein zweites Gerät mit
  // demselben User fällt so meist heraus, sonst Auswahl)
  async function whoami() {
    const u = (await rest('GET', '/user?name=' + encodeURIComponent(S.user)))[0];
    if (!u) throw new Error('User ' + S.user + ' nicht gefunden');
    const g = (await rest('GET', '/user/group?name=' + encodeURIComponent(u.group)))[0] || {};
    S.admin = String(g.policy || '').split(/[;,]/).includes('write');
    let ips = null;
    for (let i = 0; i < 2; i++) {
      const a = new Set((await rest('GET', '/user/active')).filter((x) => x.name === S.user && x.via === 'rest-api' && x.address).map((x) => x.address));
      ips = ips ? new Set([...ips].filter((x) => a.has(x))) : a;
    }
    S.ips = [...ips];
    if (!S.ip || !S.ips.includes(S.ip)) S.ip = S.ips[0] || '';
    if (!S.sel) S.sel = S.admin ? '' : S.ip;
  }

  // Einstellungen der Selbstbedienung aus dem Skript cfm-dnsreq (vom Apply geschrieben): Dauer und deny
  async function loadSelf() {
    const s = (await rest('GET', '/system/script?name=cfm-dnsreq'))[0];
    S.self = !!s;
    if (!s) return;
    const src = String(s.source || '');
    const d = src.match(/:local dur (\d+)/);
    S.dur = d ? +d[1] : 0;
    const l = src.match(/:local deny \(\{([^}]*)\}\)/);
    S.deny = l ? [...l[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]) : [];
  }
  async function loadNames() {
    const n = {};
    try {
      for (const l of await rest('GET', '/ip/dhcp-server/lease?.proplist=address,host-name,comment')) {
        const nm = l.comment || l['host-name'];
        if (l.address && nm) n[l.address] = nm;
      }
    } catch (e) { /* ohne Namen weiter */ }
    S.names = n;
  }
  async function loadStatic() {
    S.st = (await rest('GET', '/ip/dns/static?type=FWD&.proplist=.id,name,comment,forward-to'))
      .filter((x) => /^(dnsui:|cfm:dnsallow:)/.test(String(x.comment || '')));
  }

  // ---------- Log lesen ----------
  // "query from <IP>: #n <Name>. <Typ>", "done query: #n <Name> <Antwort>"; NXDOMAIN/NODATA als eigener Text. Nur
  // ein Wort nach #n: bei A/AAAA mit dem gefragten Namen = gesperrt (Adliste, Hardware 7.25), sonst die Antwort
  // selbst (PTR: der Hostname, NS: der Name). Zeit "YYYY-MM-DD hh:mm:ss" oder nur "hh:mm:ss"
  function ltime(s) {
    s = String(s || '');
    let m = s.match(/^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)$/);
    if (m) return new Date(+m[1], m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime();
    m = s.match(/(\d\d):(\d\d):(\d\d)$/);
    if (m) { const d = new Date(); d.setHours(+m[1], +m[2], +m[3], 0); return d.getTime(); }
    return Date.now();
  }
  async function loadLog() {
    const l = await rest('GET', '/log?buffer=cfmdns&.proplist=time,message');
    const q = {};
    for (const e of l) {
      const m = String(e.message || '');
      let r = m.match(/^query from ([0-9a-fA-F.:]+): #(\d+) (\S+?)\.? (\S+)$/);
      if (r) { q[r[2]] = Object.assign(q[r[2]] || {}, { t: ltime(e.time), ip: r[1], name: r[3].toLowerCase(), type: r[4] }); continue; }
      r = m.match(/^done query: #(\d+) (.*)$/);
      if (!r) continue;
      const x = q[r[1]] || (q[r[1]] = {});
      if (r[2] === 'dns name does not exist') x.res = 'nx';
      else if (r[2].startsWith('dns name exists')) x.res = 'nodata';
      else {
        const p = r[2].split(' ');
        if (p.length > 1) { x.res = 'ok'; x.ans = p.slice(1).join(' '); } else if (/^(A|AAAA)$/.test(x.type || '') && p[0].replace(/\.$/, '').toLowerCase() === x.name) x.res = 'block';
        else { x.res = 'ok'; x.ans = p[0]; }
      }
    }
    for (const k in q) if (!q[k].ip) delete q[k];
    S.q = q;
  }

  async function poll() {
    if (S.busy || document.hidden) return;
    S.busy = true;
    try {
      await Promise.all([loadLog(), loadStatic()]);
      S.err = ''; S.last = Date.now();
    } catch (e) { S.err = e.message; }
    S.busy = false;
    render();
  }
  function stop() { if (S.timer) clearInterval(S.timer); S.timer = null; }
  function start() { stop(); S.timer = setInterval(poll, S.every * 1000); poll(); }

  // ---------- Freischalten ----------
  const valid = (d) => d.length <= 253 && /^[a-z0-9_]([a-z0-9_-]*[a-z0-9])?(\.[a-z0-9_]([a-z0-9_-]*[a-z0-9])?)+$/.test(d);
  const denied = (d) => S.deny.find((x) => d === x || d.endsWith('.' + x));
  async function request(name) {
    let d = prompt('Domain freischalten (gilt samt Subdomains und für alle Geräte in diesem Netz, ' + Math.round(S.dur / 3600) + ' h).\nZum Beispiel den Teil hinter dem ersten Punkt kürzen:', name);
    if (d === null) return;
    d = d.trim().toLowerCase().replace(/^\*\./, '').replace(/\.$/, '');
    if (!valid(d)) { note('rot', d + ' ist kein gültiger Domainname.'); return; }
    const dn = denied(d);
    if (dn) { note('rot', d + ' ist von der Selbstbedienung ausgenommen (' + dn + '). Bitte den Admin fragen.'); return; }
    note('', 'Anfrage für ' + d + ' läuft …');
    try {
      await rest('POST', '/execute', { script: ':log info "cfm-dnsreq: ' + d + ' ' + (S.ip || '') + '"; /system/script/run cfm-dnsreq', 'as-string': 'yes' });
      // Ergebnis aus der Log-Zeile des Skripts (Puffer memory, wenige hundert Zeilen)
      const l = await rest('GET', '/log?buffer=memory&.proplist=message');
      const z = l.map((e) => String(e.message)).filter((m) => m.startsWith('cfm: DNS-Freischaltung ' + d + ' ')).pop();
      await loadStatic();
      if (!z) note('hinweis', 'Anfrage abgeschickt, Ergebnis noch offen – das Skript läuft spätestens in einer Minute.');
      else note(/abgelehnt/.test(z) ? 'rot' : 'ok', z.replace(/^cfm: /, '').replace(/ req=\w+$/, '') + '. Neu laden der Seite (oder ein paar Sekunden warten) – Geräte merken sich die Sperre oft noch kurz.');
    } catch (e) { note('rot', 'Anfrage fehlgeschlagen: ' + e.message); }
    render();
  }
  async function perm(x) {
    try { await rest('PATCH', '/ip/dns/static/' + encodeURIComponent(x['.id']), { comment: 'dnsui:perm ' + (x.comment.split(' ')[1] || '') + ' ' + new Date().toISOString().slice(0, 10) }); await loadStatic(); render(); } catch (e) { note('rot', e.message); }
  }
  async function drop(x) {
    if (!confirm(x.name + ' wieder sperren?')) return;
    try { await rest('DELETE', '/ip/dns/static/' + encodeURIComponent(x['.id'])); await loadStatic(); render(); } catch (e) { note('rot', e.message); }
  }
  let msgBox = null;
  function note(cls, txt) { msgBox = txt ? { cls, txt } : null; render(); }

  // ---------- Darstellung ----------
  const who = (ip) => S.names[ip] ? S.names[ip] + ' (' + ip + ')' : ip;
  function rows() {
    const von = S.win ? Date.now() - S.win * 60e3 : 0;
    return Object.values(S.q).filter((x) => x.t >= von && (!S.sel || x.ip === S.sel));
  }
  function render() {
    const main = $('main');
    if (!main) return;
    const stEl = $('.st');
    if (stEl) stEl.textContent = (S.err ? 'Fehler: ' + S.err : S.last ? 'Stand ' + hms(S.last) : 'lädt …') + (S.busy ? ' …' : '');
    main.replaceChildren();
    if (msgBox) main.append(el('div', { class: msgBox.cls || 'note' }, msgBox.txt, ' ', el('button', { class: 'klein', onclick: () => note() }, 'ok')));
    if (!S.admin && !S.ip) main.append(el('div', { class: 'hinweis' }, 'Eigene IP nicht erkannt – bitte neu laden.'));
    if (!S.self) main.append(el('div', { class: 'hinweis' }, 'Auf diesem Router ist keine Selbstbedienung eingerichtet (dns.rsc self) – nur Ansicht.'));
    const r = rows();
    if (S.tab === 'block') {
      const g = {};
      for (const x of r) if (x.res === 'block') { const e = g[x.name] || (g[x.name] = { n: 0, t: 0, ips: new Set() }); e.n++; e.t = Math.max(e.t, x.t); e.ips.add(x.ip); }
      const l = Object.entries(g).sort((a, b) => b[1].t - a[1].t);
      main.append(el('div', { class: 'note' }, l.length + ' gesperrte Namen' + (S.win ? ' in den letzten ' + S.win + ' min' : '') + (S.sel ? ' für ' + who(S.sel) : ' (alle Clients)') + '. Gesperrt = Adliste, die Antwort ist 0.0.0.0.'));
      if (!r.length) main.append(el('div', { class: 'hinweis' }, 'Keine Abfragen gefunden. Fragt dieses Gerät einen anderen DNS-Server oder nutzt der Browser „DNS über HTTPS“ (DoH)? Dann sieht der Router nichts.'));
      if (l.length) {
        const tb = el('table', {}, el('tr', {}, el('th', {}, 'zuletzt'), el('th', {}, 'Name'), el('th', {}, 'Anzahl'), ...(S.sel ? [] : [el('th', {}, 'Clients')]), el('th', {}, '')));
        for (const [n, e] of l) {
          const fr = S.st.find((x) => n === x.name || n.endsWith('.' + x.name));
          tb.append(el('tr', {}, el('td', {}, hm(e.t)), el('td', { class: 'm w' }, n), el('td', {}, String(e.n)),
            ...(S.sel ? [] : [el('td', { class: 'w' }, [...e.ips].map(who).join(', '))]),
            el('td', {}, fr ? el('span', { class: 'gr' }, 'frei') : S.self ? el('button', { class: 'klein prim', onclick: () => request(n) }, 'Freischalten anfragen') : '')));
        }
        main.append(tb);
      }
    } else if (S.tab === 'top') {
      const g = {};
      for (const x of r) { const e = g[x.name] || (g[x.name] = { n: 0, t: 0, res: '', ans: '' }); e.n++; if (x.t >= e.t) { e.t = x.t; e.res = x.res || '?'; e.ans = x.ans || ''; } }
      const f = S.filt.toLowerCase();
      const l = Object.entries(g).filter(([n]) => !f || n.includes(f)).sort((a, b) => b[1].n - a[1].n).slice(0, 300);
      const inp = el('input', { placeholder: 'Name enthält …', value: S.filt });
      inp.addEventListener('change', () => { S.filt = inp.value; render(); });
      main.append(el('div', { class: 'ff' }, inp, el('span', { class: 'note' }, r.length + ' Abfragen, ' + Object.keys(g).length + ' Namen (die 300 häufigsten)')));
      const tb = el('table', {}, el('tr', {}, el('th', {}, 'Anzahl'), el('th', {}, 'Name'), el('th', {}, 'zuletzt'), el('th', {}, 'Ergebnis')));
      const rt = { ok: 'ok', block: 'gesperrt', nx: 'gibt es nicht', nodata: 'kein Eintrag', '?': '…' };
      for (const [n, e] of l) tb.append(el('tr', {}, el('td', {}, String(e.n)), el('td', { class: 'm w' }, n), el('td', {}, hm(e.t)),
        el('td', { class: 'w' + (e.res === 'block' ? ' rot' : '') }, rt[e.res] + (e.ans ? ' ' + e.ans : ''))));
      main.append(tb);
    } else {
      main.append(el('div', { class: 'note' }, 'Ausnahmen von der Adliste auf diesem Router: aus dns.rsc allow (fest), aus der Selbstbedienung (befristet, ' + Math.round(S.dur / 3600) + ' h) und dauerhaft gemachte (bitte nach dns.rsc allow übernehmen).'));
      const tb = el('table', {}, el('tr', {}, el('th', {}, 'Name'), el('th', {}, 'Art'), el('th', {}, 'bis / von'), el('th', {}, '')));
      for (const x of S.st.slice().sort((a, b) => a.name.localeCompare(b.name))) {
        const c = String(x.comment);
        const p = c.split(' ');
        let art = 'dns.rsc allow', info = '';
        if (c.startsWith('dnsui:tmp:')) { art = 'befristet'; info = hm(+p[0].slice(10) * 1000) + (p[1] ? ', ' + who(p[1]) : ''); }
        if (c.startsWith('dnsui:perm')) { art = 'dauerhaft (Selbstbedienung)'; info = (p[1] ? who(p[1]) : '') + (p[2] ? ', ' + p[2] : ''); }
        const kn = [];
        if (S.admin && art === 'befristet') kn.push(el('button', { class: 'klein prim', onclick: () => perm(x) }, 'dauerhaft'));
        if (S.admin && art !== 'dns.rsc allow') kn.push(el('button', { class: 'klein', onclick: () => drop(x) }, 'entfernen'));
        tb.append(el('tr', {}, el('td', { class: 'm w' }, x.name), el('td', {}, art), el('td', {}, info), el('td', {}, ...kn)));
      }
      main.append(tb);
    }
  }
  function tab(t) { S.tab = t; root.querySelectorAll('header .tab').forEach((b) => b.classList.toggle('akt', b.dataset.t === t)); render(); }

  function hide() { stop(); root.style.display = 'none'; }
  function show() { root.style.display = 'flex'; if ($('header')) start(); }
  window.__cfmDns = { stand: STAND, show, drop: () => { stop(); root.remove(); return true; } };

  async function mainView() {
    root.querySelectorAll('header,main,.login').forEach((n) => n.remove());
    try { await whoami(); await loadSelf(); await loadNames(); } catch (e) { loginView('Fehler: ' + e.message); return; }
    const sel = el('select', { title: 'Client' });
    const opts = [];
    if (S.admin) opts.push(['', 'alle Clients']);
    for (const ip of S.ips) opts.push([ip, 'ich: ' + who(ip)]);
    if (S.admin) for (const ip of Object.keys(S.names).sort()) if (!S.ips.includes(ip)) opts.push([ip, who(ip)]);
    for (const [v, l] of opts) { const o = el('option', { value: v }, l); if (v === S.sel) o.selected = true; sel.append(o); }
    sel.addEventListener('change', () => { S.sel = sel.value; if (S.ips.includes(sel.value)) S.ip = sel.value; render(); });
    const win = el('select', { title: 'Zeitraum' }, ...[[5, '5 min'], [15, '15 min'], [60, '1 h'], [0, 'alles im Log']].map(([v, l]) => {
      const o = el('option', { value: v }, l); if (v === S.win) o.selected = true; return o;
    }));
    win.addEventListener('change', () => { S.win = +win.value; render(); });
    const ev = el('select', { title: 'Neu laden alle …' }, ...[15, 30, 60].map((v) => { const o = el('option', { value: v }, 'alle ' + v + ' s'); if (v === S.every) o.selected = true; return o; }));
    ev.addEventListener('change', () => { S.every = +ev.value; start(); });
    const tb = (t, l) => { const b = el('button', { class: 'tab', type: 'button' }, l); b.dataset.t = t; b.addEventListener('click', () => tab(t)); return b; };
    root.append(el('header', {}, el('b', {}, 'cfm-DNS – ' + S.ident), tb('block', 'Gesperrt'), tb('top', 'Abfragen'), tb('allow', 'Freischaltungen'),
      el('span', { class: 'st' }, ''), el('span', { class: 'sp' }), (S.admin || S.ips.length > 1) ? sel : el('span', { class: 'st' }, S.ip ? 'ich: ' + who(S.ip) : ''), win, ev,
      el('button', { onclick: poll }, 'Neu laden'), el('button', { onclick: hide }, 'Schließen')), el('main', {}));
    tab(S.tab);
    start();
  }

  async function loginView(hinweis) {
    root.querySelectorAll('header,main,.login').forEach((n) => n.remove());
    S.user = sess('cfmRestUser');
    if (!hinweis && sess('cfmRestOk') === '1' && S.user) {
      let ok = false;
      try { S.ident = (await rest('GET', '/system/identity')).name; ok = true; } catch (e) { sess('cfmRestOk', ''); }
      if (ok) { mainView(); return; }
    }
    const u = el('input', { name: 'username', placeholder: 'Benutzer', autocomplete: 'username', value: S.user });
    const p = el('input', { name: 'password', type: 'password', placeholder: 'Passwort', autocomplete: 'current-password' });
    const msg = el('div', { class: 'fehler' }, hinweis || '');
    const go = async (e) => {
      e.preventDefault();
      msg.textContent = '';
      const st = await xhrLogin(u.value, p.value);
      if (st !== 200) { msg.textContent = 'Anmeldung fehlgeschlagen (' + (st || 'keine Verbindung') + ').'; p.select(); return; }
      sess('cfmRestOk', '1'); sess('cfmRestUser', u.value); S.user = u.value;
      try { S.ident = (await rest('GET', '/system/identity')).name; } catch (e2) { msg.textContent = 'Fehler: ' + e2.message; return; }
      mainView();
    };
    root.append(el('form', { class: 'login', onsubmit: go }, el('b', {}, 'cfm-DNS'),
      el('div', {}, 'DNS-Abfragen dieses Netzes: was gesperrt wurde, Freischaltung anfragen. Anmeldung an der REST-API dieses Routers (User für die DNS-Selbstbedienung oder Admin).'),
      u, p, el('button', { class: 'prim', type: 'submit' }, 'Anmelden'), msg,
      el('button', { type: 'button', onclick: hide }, 'Schließen')));
    (S.user ? p : u).focus();
  }

  loginView();
})();
