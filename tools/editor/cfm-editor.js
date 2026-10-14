// cfm-Editor (D73): Lesezeichen für WebFig des Managers. Läuft in der WebFig-Seite und spricht die
// REST-API derselben Adresse an (kein CORS, nichts auf dem Manager installiert). Bearbeitet die
// Site-Daten in <mgrPath>/work/ (der Manager führt sie, D72); lib/ und roles/ nur lesen, die kommen
// per tools/upload-seed.sh. Befehle laufen per :execute im Hintergrund, die Ausgabe kommt aus einer
// Datei (REST bricht lange Aufrufe sonst ab). Bauen: tools/editor/build.py -> install.html
(() => {
  if (window.__cfmEd) { window.__cfmEd.show(); return; }
  const MAX = 60000;                       // wie $cfmParseWork: /file get liest nur ~60 KB
  const ENDE = '@@cfm-ende@@';
  const S = { auth: null, base: '', files: [], cur: null, text: '', busy: false };
  const $ = (sel) => root.querySelector(sel);
  const el = (tag, attrs, ...kids) => {
    const e = document.createElement(tag);
    Object.entries(attrs || {}).forEach(([k, v]) => k.startsWith('on') ? e.addEventListener(k.slice(2), v) : e.setAttribute(k, v));
    kids.forEach((k) => e.append(k));
    return e;
  };
  // RouterOS-String: \ " $ maskieren, Zeilenumbruch als \n
  const esc = (s) => String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\$/g, '\\$').replace(/\r/g, '').replace(/\n/g, '\\n');
  const bytes = (s) => new TextEncoder().encode(s).length;
  // Meldungen der Imports beim Laden der Manager-Funktionen gehören nicht zur Ausgabe
  const clean = (t) => t.replace(/\r/g, '').split('\n').filter((l) => !/^Script file loaded and executed successfully$/.test(l.trim())).join('\n');

  const css = `
#cfmed{position:fixed;inset:0;z-index:2147483000;background:#f4f5f4;color:#1d2321;font:13px system-ui,sans-serif;display:flex;flex-direction:column}
#cfmed *{box-sizing:border-box}
#cfmed header{display:flex;align-items:center;gap:8px;padding:6px 10px;background:#13534b;color:#fff;flex-wrap:wrap}
#cfmed header b{font-size:14px;margin-right:8px}
#cfmed button{font:inherit;padding:4px 10px;border:1px solid #9aa;border-radius:4px;background:#fff;color:#1d2321;cursor:pointer}
#cfmed button:disabled{opacity:.5;cursor:default}
#cfmed button.prim{background:#13534b;color:#fff;border-color:#13534b}
#cfmed header button{border-color:#fff3}
#cfmed input,#cfmed select{font:inherit;padding:3px 6px;border:1px solid #9aa;border-radius:4px}
#cfmed .sp{flex:1}
#cfmed main{flex:1;display:flex;min-height:0}
#cfmed nav{width:260px;overflow:auto;border-right:1px solid #ccd;background:#fff;padding:6px 0}
#cfmed nav h4{margin:8px 10px 4px;font-size:11px;text-transform:uppercase;color:#667}
#cfmed nav div{padding:2px 10px 2px 16px;cursor:pointer;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#cfmed nav div:hover{background:#e6efed}
#cfmed nav div.akt{background:#13534b;color:#fff}
#cfmed nav div.ro{color:#778}
#cfmed section{flex:1;display:flex;flex-direction:column;min-width:0}
#cfmed .bar{display:flex;gap:6px;align-items:center;padding:6px 8px;border-bottom:1px solid #ccd;flex-wrap:wrap;background:#fafbfa}
#cfmed .ed{flex:1;display:flex;min-height:0;font:12.5px/1.45 ui-monospace,Menlo,Consolas,monospace}
#cfmed .gut{width:48px;overflow:hidden;text-align:right;padding:6px 6px 6px 0;color:#99a;background:#f0f1f0;white-space:pre;user-select:none}
#cfmed textarea{flex:1;border:0;padding:6px 8px;resize:none;font:inherit;white-space:pre;overflow:auto;outline:none;tab-size:2}
#cfmed textarea[readonly]{background:#f7f7f5}
#cfmed .stat{padding:3px 8px;font-size:12px;color:#556;border-top:1px solid #ccd;background:#fafbfa}
#cfmed pre{margin:0;height:34%;overflow:auto;padding:6px 8px;background:#1d2321;color:#dfe;font:12px/1.4 ui-monospace,Menlo,Consolas,monospace;white-space:pre-wrap}
#cfmed .login{margin:12vh auto;background:#fff;padding:20px 24px;border-radius:8px;box-shadow:0 2px 12px #0002;display:grid;gap:8px;width:320px}
#cfmed .fehler{color:#b3261e}`;

  const root = el('div', { id: 'cfmed' });
  root.append(el('style', {}, css));
  document.body.append(root);

  // ---------- REST ----------
  async function rest(method, path, body) {
    // cache: RouterOS schickt zu REST-Antworten Cache-Control max-age=31536000 (7.24.5) - ohne no-store
    // lieferte der Browser z.B. eine alte Dateiliste oder Job-Liste
    const r = await fetch('/rest' + path, {
      method, cache: 'no-store', headers: { Authorization: S.auth, 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const t = await r.text();
    let j = null;
    try { j = t ? JSON.parse(t) : null; } catch (e) { j = t; }
    if (!r.ok) throw new Error((j && (j.detail || j.message)) || (r.status + ' ' + t));
    return j;
  }
  const exec = async (script) => (await rest('POST', '/execute', { script, 'as-string': true })).ret || '';
  const read = async (id) => (await rest('POST', '/file/get', { '.id': id, 'value-name': 'contents' })).ret || '';
  const fileByName = async (name) => (await rest('GET', '/file?name=' + encodeURIComponent(name)))[0];

  // Manager-Befehl im Hintergrund, Ausgabe laufend in die Ausgabe-Ansicht
  async function run(title, cmd, globals) {
    if (S.busy) return;
    busy(true);
    const out = $('pre');
    out.textContent = '> ' + title + '\n';
    const fn = 'cfm-ed-' + Date.now() + '.txt';
    const decl = globals.map((g) => ':global ' + g + '; ').join('');
    const body = '/system script run cfm-mgr; ' + decl + ':onerror e in={ ' + cmd + ' } do={ :put ("FEHLER: " . $e) }; :put "' + ENDE + '"';
    try {
      const job = (await exec(':put [:execute script="' + esc(body) + '" file="' + fn + '"]')).trim();
      const t0 = Date.now();
      let txt = '', fertig = false;
      while (!fertig && Date.now() - t0 < 15 * 60 * 1000) {
        await new Promise((r) => setTimeout(r, 1000));
        const f = await fileByName(fn).catch(() => null);
        if (f) txt = (await read(f['.id'])).replace(/\r/g, '');
        fertig = txt.includes(ENDE);
        if (!fertig && job) {
          const jobs = await rest('GET', '/system/script/job').catch(() => []);
          if (!jobs.some((j) => j['.id'] === job)) fertig = true;   // Job weg, Ausgabe ist vollständig
        }
        out.textContent = '> ' + title + '\n' + clean(txt).replace(ENDE + '\n', '').replace(ENDE, '');
        out.scrollTop = out.scrollHeight;
      }
      if (!fertig) out.textContent += '\n(keine Rückmeldung nach 15 min - Log des Managers ansehen)';
      const f = await fileByName(fn).catch(() => null);
      if (f) await rest('DELETE', '/file/' + f['.id']).catch(() => {});
    } catch (e) {
      out.textContent += '\nFEHLER: ' + e.message;
    }
    busy(false);
  }

  // ---------- Anmeldung ----------
  function loginView() {
    root.querySelectorAll('header,main,.login').forEach((n) => n.remove());
    const u = el('input', { placeholder: 'Benutzer', autocomplete: 'username' });
    const p = el('input', { type: 'password', placeholder: 'Passwort', autocomplete: 'current-password' });
    const msg = el('div', { class: 'fehler' });
    const go = async () => {
      S.auth = 'Basic ' + btoa(String.fromCharCode(...new TextEncoder().encode(u.value + ':' + p.value)));
      try {
        const id = await rest('GET', '/system/identity');
        await mainView(id.name);
      } catch (e) { msg.textContent = 'Anmeldung fehlgeschlagen: ' + e.message; }
    };
    p.addEventListener('keydown', (e) => { if (e.key === 'Enter') go(); });
    root.append(el('div', { class: 'login' }, el('b', {}, 'cfm-Editor'),
      el('div', {}, 'Anmeldung an der REST-API dieses Managers (RouterOS-User mit Gruppe full).'),
      u, p, el('button', { class: 'prim', onclick: go }, 'Anmelden'), msg,
      el('button', { onclick: hide }, 'Schließen')));
    u.focus();
  }

  // ---------- Hauptansicht ----------
  async function mainView(identity) {
    root.querySelectorAll('header,main,.login').forEach((n) => n.remove());
    const hosts = el('select', { title: 'Gerät für den Probelauf' });
    const msg = el('input', { placeholder: 'Release-Notiz', size: 28 });
    root.append(el('header', {},
      el('b', {}, 'cfm-Editor – ' + identity),
      el('button', { onclick: check, 'data-cmd': 1 }, 'Prüfen'),
      el('button', { onclick: diff, 'data-cmd': 1 }, 'Diff zum Release'),
      hosts, el('button', { onclick: () => plan(hosts.value), 'data-cmd': 1 }, 'Probelauf'),
      msg, el('button', { onclick: () => release(msg.value), 'data-cmd': 1 }, 'Release (Ring 0)'),
      el('span', { class: 'sp' }),
      el('button', { onclick: hide }, 'Schließen')));
    const ta = el('textarea', { spellcheck: 'false', readonly: '' });
    const gut = el('div', { class: 'gut' });
    root.append(el('main', {},
      el('nav', {}),
      el('section', {},
        el('div', { class: 'bar' },
          el('button', { class: 'prim', onclick: save, id: 'cfmed-save', disabled: '' }, 'Speichern'),
          el('button', { onclick: reload }, 'Neu laden'),
          el('button', { onclick: newFile }, 'Neue Datei'),
          el('span', { id: 'cfmed-name' }, 'keine Datei gewählt')),
        el('div', { class: 'ed' }, gut, ta),
        el('div', { class: 'stat', id: 'cfmed-stat' }, ''),
        el('pre', {}, 'Bereit. Datei links wählen; Strg+S speichert.'))));
    ta.addEventListener('input', () => { lines(); status(); });
    ta.addEventListener('scroll', () => { gut.scrollTop = ta.scrollTop; });
    ta.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 's') { e.preventDefault(); save(); }
      if (e.key === 'Tab' && !ta.readOnly) { e.preventDefault(); ta.setRangeText('  ', ta.selectionStart, ta.selectionEnd, 'end'); lines(); }
    });
    await loadList();
    const inv = await exec('/system script run cfm-mgr; :global cfmInvLoad; :local s ""; :foreach n,d in=[$cfmInvLoad] do={ :set s ($s . $n . ",") }; :put ("H=" . $s)').catch(() => '');
    const hl = inv.split('\n').map((l) => l.trim()).find((l) => l.startsWith('H=')) || 'H=';
    hl.slice(2).split(',').filter(Boolean).sort((a, b) => a.localeCompare(b)).forEach((n) => hosts.append(el('option', {}, n)));
  }

  async function loadList() {
    const all = await rest('GET', '/file?.proplist=.id,name,size,type,last-modified');
    const core = all.find((f) => /(^|\/)work\/lib\/mgr-core\.rsc$/.test(f.name));
    if (!core) throw new Error('kein cfm-Manager: work/lib/mgr-core.rsc fehlt');
    S.base = core.name.replace(/\/work\/lib\/mgr-core\.rsc$/, '');
    const w = S.base + '/work/';
    S.files = all.filter((f) => f.name.startsWith(w) && f.type !== 'directory')
      .map((f) => ({ ...f, rel: f.name.slice(w.length), ro: /^(lib|roles)\//.test(f.name.slice(w.length)) }))
      .sort((a, b) => (a.ro - b.ro) || (a.rel.includes('/') - b.rel.includes('/')) || a.rel.localeCompare(b.rel));
    const nav = $('nav');
    nav.textContent = '';
    nav.append(el('h4', {}, 'Site-Daten'));
    let fw = false;
    S.files.forEach((f) => {
      if (f.ro && !fw) { fw = true; nav.append(el('h4', {}, 'Framework (nur lesen)')); }
      const d = el('div', { class: (f.ro ? 'ro ' : '') + (S.cur && S.cur.name === f.name ? 'akt' : ''), title: f.name + ' – ' + f.size + ' B, ' + f['last-modified'] }, f.rel);
      d.addEventListener('click', () => open(f));
      nav.append(d);
    });
  }

  function lines() {
    const ta = $('textarea');
    const n = ta.value.split('\n').length;
    $('.gut').textContent = Array.from({ length: n }, (_, i) => i + 1).join('\n') + '\n';
    $('.gut').scrollTop = ta.scrollTop;
  }
  const dirty = () => S.cur && !S.cur.ro && $('textarea').value !== S.text;
  function status() {
    if (!S.cur) return;
    const b = bytes($('textarea').value);
    $('#cfmed-stat').textContent = (dirty() ? '● geändert – ' : '') + b + ' von ' + MAX + ' Bytes' +
      (b > MAX ? ' – ZU GROSS, $cfmRelease weist die Datei ab' : '') + (S.cur.ro ? ' – nur lesen (kommt per upload-seed.sh)' : '') +
      ' – Stand ' + S.cur['last-modified'];
    $('#cfmed-save').disabled = !dirty() || S.busy;
  }

  async function open(f) {
    if (dirty() && !confirm('Ungespeicherte Änderungen an ' + S.cur.rel + ' verwerfen?')) return;
    try {
      const txt = await read(f['.id']);
      S.cur = f; S.text = txt;
      const ta = $('textarea');
      ta.value = txt; ta.readOnly = f.ro; ta.scrollTop = 0;
      $('#cfmed-name').textContent = f.name;
      root.querySelectorAll('nav div').forEach((d) => d.classList.toggle('akt', d.textContent === f.rel));
      lines(); status();
    } catch (e) { $('pre').textContent = 'FEHLER beim Lesen: ' + e.message; }
  }
  async function reload() {
    if (dirty() && !confirm('Ungespeicherte Änderungen an ' + S.cur.rel + ' verwerfen und neu laden?')) return;
    if (S.cur) S.text = $('textarea').value;   // die Rückfrage in open() ist damit beantwortet
    await loadList();
    if (S.cur) { const f = S.files.find((x) => x.name === S.cur.name); if (f) await open(f); }
  }

  async function save() {
    if (!dirty() || S.busy) return;
    const txt = $('textarea').value;
    if (bytes(txt) > MAX && !confirm('Die Datei ist größer als ' + MAX + ' Bytes – $cfmRelease weist sie ab. Trotzdem speichern?')) return;
    const out = $('pre');
    try {
      const now = await fileByName(S.cur.name);
      if (!now) throw new Error('Datei gibt es auf dem Manager nicht mehr');
      if (now['last-modified'] !== S.cur['last-modified'] &&
        !confirm(S.cur.rel + ' wurde inzwischen auf dem Manager geändert (' + now['last-modified'] + '). Trotzdem überschreiben?')) return;
      await rest('PATCH', '/file/' + now['.id'], { contents: txt });
      const f = await fileByName(S.cur.name);
      S.cur = { ...S.cur, ...f, rel: S.cur.rel, ro: S.cur.ro };
      S.text = txt;
      let syn = '';
      if (/\.rsc$/.test(S.cur.name)) {
        syn = await exec(':onerror e in={ :local x [:parse [/file/get "' + esc(S.cur.name) + '" contents]]; :put "Syntax ok" } do={ :put ("Syntaxfehler: " . $e) }');
      }
      out.textContent = 'Gespeichert: ' + S.cur.name + ' (' + bytes(txt) + ' Bytes). ' + syn.trim() +
        '\nWirksam erst mit einem Release; vorher „Prüfen“ und „Probelauf“.';
      await loadList(); status();
    } catch (e) { out.textContent = 'FEHLER beim Speichern: ' + e.message; }
  }

  async function newFile() {
    const rel = prompt('Neue Datei unter ' + S.base + '/work/ (z.B. hosts/ap3.rsc, authorized_keys.anna):');
    if (!rel) return;
    if (!/^(hosts\/)?[A-Za-z0-9][A-Za-z0-9._-]*$/.test(rel) || /^(lib|roles)\//.test(rel)) { alert('Name nicht erlaubt: nur Site-Daten, z.B. hosts/<name>.rsc'); return; }
    try {
      await rest('PUT', '/file', { name: S.base + '/work/' + rel, contents: '' });
      await loadList();
      const f = S.files.find((x) => x.rel === rel);
      if (f) await open(f);
    } catch (e) { $('pre').textContent = 'FEHLER beim Anlegen: ' + e.message; }
  }

  function busy(b) {
    S.busy = b;
    root.querySelectorAll('button[data-cmd]').forEach((x) => { x.disabled = b; });
    status();
  }
  const unsaved = () => dirty() && !confirm('Ungespeicherte Änderungen an ' + S.cur.rel + ' – sie zählen nicht. Trotzdem fortfahren?');

  // ---------- Befehle des Managers ----------
  function check() {
    if (unsaved()) return;
    // Prüfer aus work/ wie $cfmRelease (D59)
    run('Prüfen ($cfmParseWork, $cfmCheck)',
      ':onerror x in={ /import file-name=([$cfmMB] . "/work/lib/mgr-check.rsc") verbose=no } do={}; :global cfmCheck; ' +
      ':local p [$cfmParseWork]; :if ([:len $p] > 0) do={ :put ("Größe/Syntax:" . $p) } else={ :put "Größe und Syntax: ok" }; ' +
      ':local ck [$cfmCheck]; :foreach w in=($ck->"warn") do={ :put ("Warnung: " . $w) }; :foreach x in=($ck->"err") do={ :put ("Fehler: " . $x) }; ' +
      ':put ([:len ($ck->"err")] . " Fehler, " . [:len ($ck->"warn")] . " Warnungen")',
      ['cfmMB', 'cfmParseWork', 'cfmCheck']);
  }
  function diff() { if (!unsaved()) run('Diff work/ zum letzten Release ($cfmDiff)', '$cfmDiff', ['cfmDiff']); }
  function plan(h) {
    if (unsaved() || !h) return;
    if (!/^[A-Za-z0-9._-]+$/.test(h)) return;
    run('Probelauf $cfmPlan host=' + h, '$cfmPlan host="' + esc(h) + '"', ['cfmPlan']);
  }
  function release(m) {
    if (unsaved()) return;
    if (!confirm('Release aus work/ erstellen und an Ring 0 verteilen?' + (m ? '\nNotiz: ' + m : ''))) return;
    run('Release ($cfmRelease, Ring 0)', '$cfmRelease msg="' + esc(m ? ' ' + m : '') + '"', ['cfmRelease']);
  }

  function hide() {
    if (dirty() && !confirm('Ungespeicherte Änderungen an ' + S.cur.rel + ' verwerfen?')) return;
    root.style.display = 'none';
  }
  window.__cfmEd = { show: () => { root.style.display = 'flex'; } };
  loginView();
})();
