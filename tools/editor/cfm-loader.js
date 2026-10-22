// cfm (TODO 52, D91): Lade-Lesezeichen für WebFig, einmal anlegen. Meldet an der REST-API derselben Adresse an
// (wie cfm-Editor/cfm-Monitor) und startet deren aktuelle Fassung vom Gerät: web/cfm-editor.js und
// web/cfm-monitor.js kommen mit tools/upload-seed.sh auf den Manager und mit dem Release zu den Rollen manager
// und capsman (cfm/dl/web/). Lädt nichts aus dem Netz. Bauen: tools/editor/build.py -> install.html
(() => {
  document.getElementById('cfmld')?.remove();
  const APPS = [
    { file: 'cfm-editor.js', title: 'cfm-Editor', note: 'Site-Daten bearbeiten, Probelauf, Release', where: 'nur auf dem Manager' },
    { file: 'cfm-monitor.js', title: 'cfm-Monitor', note: 'WLAN-Clients live, Gerätesuche', where: 'auf dem Manager und dem CAPsMAN' },
  ];
  // freigegebener Stand (Agent, cfm/dl) vor dem hochgeladenen (Manager, work/ - erst nach dem Release verteilt)
  const DIRS = ['cfm/dl/web/', 'flash/cfm/dl/web/', 'cfm/work/web/', 'flash/cfm/work/web/'];
  const el = (tag, attrs, ...kids) => {
    const e = document.createElement(tag);
    Object.entries(attrs || {}).forEach(([k, v]) => k.startsWith('on') ? e.addEventListener(k.slice(2), v) : e.setAttribute(k, v));
    kids.forEach((k) => e.append(k));
    return e;
  };
  const root = el('div', { id: 'cfmld' }, el('style', {}, `
#cfmld{position:fixed;top:12vh;left:50%;transform:translateX(-50%);z-index:2147483001;width:340px;background:#fff;color:#1d2321;font:13px system-ui,sans-serif;padding:20px 24px;border-radius:8px;box-shadow:0 2px 16px #0003;display:grid;gap:8px}
#cfmld *{box-sizing:border-box}
#cfmld input,#cfmld button{font:inherit;padding:4px 10px;border:1px solid #9aa;border-radius:4px}
#cfmld button{background:#fff;color:#1d2321;cursor:pointer;text-align:left}
#cfmld button:disabled{opacity:.5;cursor:default}
#cfmld button.prim{background:#13534b;color:#fff;border-color:#13534b}
#cfmld small{color:#667}
#cfmld .fehler{color:#b3261e}`));
  document.body.append(root);
  const close = () => root.remove();
  const box = (...kids) => { root.querySelectorAll('form,div.k').forEach((n) => n.remove()); root.append(...kids); };

  // cache: no-store wie in den Lesezeichen (RouterOS schickt max-age=31536000)
  async function rest(method, path, body) {
    const r = await fetch('/rest' + path, {
      method, cache: 'no-store', headers: { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const t = await r.text();
    let j = null;
    try { j = t ? JSON.parse(t) : null; } catch (e) { j = t; }
    if (!r.ok) throw new Error((j && (j.detail || j.message)) || (r.status + ' ' + t));
    return j;
  }
  // Anmeldung wie in cfm-editor.js: XHR mit User/Passwort, danach schickt der Browser die Daten bei jedem
  // REST-Aufruf mit (bis zum Schließen, auch für Editor und Monitor); Merker cfmRestOk ohne Passwort
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

  function loginView(hinweis) {
    const u = el('input', { name: 'username', placeholder: 'Benutzer', autocomplete: 'username' });
    const p = el('input', { name: 'password', type: 'password', placeholder: 'Passwort', autocomplete: 'current-password' });
    const msg = el('div', { class: 'fehler' }, hinweis || '');
    const go = async (e) => {
      e.preventDefault();
      msg.textContent = '';
      const st = await xhrLogin(u.value, p.value);
      if (st !== 200) { msg.textContent = 'Anmeldung fehlgeschlagen (' + (st || 'keine Verbindung') + ').'; p.select(); return; }
      restOk(true);
      menu().catch((e2) => { msg.textContent = 'Fehler: ' + e2.message; });
    };
    box(el('form', { onsubmit: go, style: 'display:grid;gap:8px' }, el('b', {}, 'cfm'),
      el('div', {}, 'Anmeldung an der REST-API dieses Geräts (Editor: User der Gruppe full, Monitor: Leserecht genügt).'),
      u, p, el('button', { class: 'prim', type: 'submit' }, 'Anmelden'), msg,
      el('button', { type: 'button', onclick: close }, 'Schließen')));
    u.focus();
  }

  // erste Fundstelle je Datei; ein Gerät ohne Rolle manager/capsman hat keine
  async function find(file) {
    for (const d of DIRS) {
      const l = await rest('GET', '/file?.proplist=.id,name,size&name=' + encodeURIComponent(d + file));
      if (l && l[0]) return l[0];
    }
    return null;
  }

  async function start(f, msg) {
    msg.textContent = '';
    try {
      const src = (await rest('POST', '/file/get', { '.id': f['.id'], 'value-name': 'contents' })).ret || '';
      if (src.length < 100) throw new Error(f.name + ' ist leer oder unvollständig');
      close();
      new Function(src)();
    } catch (e) { msg.textContent = 'Fehler: ' + e.message; }
  }

  async function menu() {
    let ident = '';
    try { ident = (await rest('GET', '/system/identity')).name; } catch (e) { restOk(false); loginView('Bitte erneut anmelden.'); return; }
    const found = await Promise.all(APPS.map((a) => find(a.file)));
    const msg = el('div', { class: 'fehler' });
    const knoepfe = APPS.map((a, i) => found[i]
      ? el('button', { class: 'prim', onclick: () => start(found[i], msg) }, a.title, el('br'), el('small', { style: 'color:#dfe' }, a.note))
      : el('button', { disabled: '', title: a.where }, a.title, el('br'), el('small', {}, 'nicht auf diesem Gerät (' + a.where + ')')));
    box(el('div', { class: 'k', style: 'display:grid;gap:8px' }, el('b', {}, 'cfm – ' + ident), ...knoepfe,
      found.some(Boolean) ? '' : el('small', {}, 'Keine cfm-Lesezeichen auf diesem Gerät: Framework mit tools/upload-seed.sh hochladen und releasen (D91), oder die vollständigen Lesezeichen aus install.html nehmen.'),
      msg, el('button', { type: 'button', onclick: close }, 'Schließen')));
    // nur eine Fundstelle: gleich starten
    const n = found.filter(Boolean);
    if (n.length === 1) start(n[0], msg);
  }

  if (restOk()) menu().catch((e) => loginView('Fehler: ' + e.message)); else loginView();
})();
