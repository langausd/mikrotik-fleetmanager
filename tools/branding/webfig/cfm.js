// cfm auf der WebFig-Login-Seite (DT3.3, Prototyp): wird vom Branding-Paket als weitere Datei der Login-Seite
// ausgeliefert (gleicher Pfad wie index2.html) und von index2.html eingebunden (siehe index2.fragment.html).
// Knopf „cfm“ neben dem Login: nimmt Benutzer/Passwort aus dem Login-Formular (#name, #password), meldet sich per XHR an
// der REST-API derselben Adresse an (wie das Lade-Lesezeichen, DT3.1.1/DT3.2), lädt web/cfm-editor.js, cfm-monitor.js
// oder cfm-dns.js vom Gerät (cfm/dl/web/ vor cfm/work/web/) und startet sie in dieser Seite. Lädt nichts aus dem Netz.
// Unterschied zu tools/editor/cfm-loader.js: kein eigenes Formular (das der Login-Seite wird genutzt), Fehler im
// #error-Feld der Seite, Menü in einem eigenen Kasten unter dem Formular.
(() => {
  const APPS = [
    { file: 'cfm-editor.js', title: 'cfm-Editor', note: 'Site-Daten bearbeiten, Probelauf, Release', where: 'nur auf dem Manager' },
    { file: 'cfm-monitor.js', title: 'cfm-Monitor', note: 'WLAN-Clients live, Gerätesuche', where: 'auf dem Manager und dem CAPsMAN' },
    { file: 'cfm-dns.js', title: 'cfm-DNS', note: 'Gesperrte Namen, Freischaltung anfragen', where: 'auf den Routern' },
  ];
  const DIRS = ['cfm/dl/web/', 'flash/cfm/dl/web/', 'cfm/work/web/', 'flash/cfm/work/web/'];
  const $ = (id) => document.getElementById(id);
  const el = (tag, attrs, ...kids) => {
    const e = document.createElement(tag);
    Object.entries(attrs || {}).forEach(([k, v]) => k.startsWith('on') ? e.addEventListener(k.slice(2), v) : e.setAttribute(k, v));
    kids.forEach((k) => e.append(k));
    return e;
  };
  const err = (t) => { const e = $('error'); if (e) e.textContent = t; };

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
  async function find(file) {
    for (const d of DIRS) {
      const l = await rest('GET', '/file?.proplist=.id,name,size&name=' + encodeURIComponent(d + file));
      if (l && l[0]) return l[0];
    }
    return null;
  }
  async function start(f) {
    const src = (await rest('POST', '/file/get', { '.id': f['.id'], 'value-name': 'contents' })).ret || '';
    if (src.length < 100) throw new Error(f.name + ' ist leer oder unvollständig');
    // Die Login-Seite bleibt das Dokument; die Werkzeuge bauen ihre Oberfläche selbst (position:fixed)
    new Function(src)();
  }
  async function menu() {
    let ident = '';
    try { ident = (await rest('GET', '/system/identity')).name; } catch (e) { restOk(false); err('cfm: Anmeldung an der REST-API fehlgeschlagen.'); return; }
    const found = await Promise.all(APPS.map((a) => find(a.file)));
    const box = $('cfmbox') || el('div', { id: 'cfmbox' });
    box.replaceChildren(el('b', {}, 'cfm – ' + ident));
    APPS.forEach((a, i) => box.append(found[i]
      ? el('button', { type: 'button', class: 'cfm prim', onclick: () => start(found[i]).catch((e) => err('cfm: ' + e.message)) }, a.title, el('br'), el('small', {}, a.note))
      : el('button', { type: 'button', class: 'cfm', disabled: '', title: a.where }, a.title, el('br'), el('small', {}, 'nicht auf diesem Gerät (' + a.where + ')'))));
    if (!found.some(Boolean)) box.append(el('small', {}, 'Keine cfm-Werkzeuge auf diesem Gerät (Framework hochladen und releasen, DT3.2).'));
    ($('login') || document.body).after(box);
    const n = found.filter(Boolean);
    if (n.length === 1) start(n[0]).catch((e) => err('cfm: ' + e.message));
  }
  async function go(ev) {
    ev.preventDefault();
    err('');
    if (!restOk()) {
      const u = ($('name') || {}).value || '', p = ($('password') || {}).value || '';
      const st = await xhrLogin(u, p);
      if (st !== 200) { err('cfm: Anmeldung fehlgeschlagen (' + (st || 'keine Verbindung') + ').'); return; }
      restOk(true);
      try { sessionStorage.setItem('cfmRestUser', u); } catch (e) { /* ohne Merker fragt cfm-DNS selbst */ }
    }
    menu().catch((e) => err('cfm: ' + e.message));
  }
  function init() {
    const form = $('login');
    if (!form || $('cfmbtn')) return;
    // Knopf hinter den Login-Knopf der Seite; type=button, damit er das Formular nicht abschickt
    form.append(el('button', { id: 'cfmbtn', type: 'button', class: 'cfm', onclick: go, title: 'cfm-Editor, cfm-Monitor oder cfm-DNS auf diesem Gerät starten' }, 'cfm'));
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
