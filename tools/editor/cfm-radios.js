// cfm-radios.js – Kanalvorschlag von $cfmWifiScan in wifi.rsc übernehmen (cfm-Editor, DT3.5). build.py setzt die Datei
// an der Marke im Editor ein; eigene Datei, damit tools/editor/cfm-radios-test.py sie allein prüfen kann (node).
// Nur das gescannte Band wird je AP ersetzt: die Zeile "radios" der 2,4-GHz-Vorschläge nennt nur "2", die der
// 5/6-GHz-Vorschläge alle Bänder - Pins anderer Bänder, Listen und "off" bleiben so in jedem Fall stehen.
// Rückweg: der alte Eintrag "radios" als Kommentarzeile hinter dem Ende von :global cfmWifi {…}.
const cfmRadios = (() => {
  // Stelle des Eintrags "radios"={…} in wifi.rsc (Kommentarzeilen und Zeichenketten übersprungen) -> {start, end}
  function find(txt) {
    let i = 0;
    let lineStart = true;
    while (i < txt.length) {
      const c = txt[i];
      if (lineStart && /^[ \t]*#/.test(txt.slice(i, i + 200))) { const n = txt.indexOf('\n', i); i = n < 0 ? txt.length : n + 1; continue; }
      lineStart = c === '\n';
      if (c === '"') {
        if (txt.startsWith('"radios"=', i)) {
          const o = i + '"radios"='.length;
          if (txt[o] !== '{') throw new Error('"radios" ist kein Array');
          const e = close(txt, o);
          return { start: i, end: e };
        }
        i = skipStr(txt, i);
        continue;
      }
      i++;
    }
    return null;
  }
  function skipStr(txt, i) {
    let j = i + 1;
    while (j < txt.length && txt[j] !== '"') { if (txt[j] === '\\') j++; j++; }
    return j + 1;
  }
  // Index hinter der zu txt[o] = '{' passenden Klammer
  function close(txt, o) {
    let d = 0;
    let i = o;
    while (i < txt.length) {
      const c = txt[i];
      if (c === '"') { i = skipStr(txt, i); continue; }
      if (c === '{') d++;
      if (c === '}') { d--; if (d === 0) return i + 1; }
      i++;
    }
    throw new Error('Klammer zu "radios" nicht geschlossen');
  }
  // {"a"={"2"="2412";"5"="5180/80"};"b"={…}} -> [[ap, [[band, wert], …]], …] (Reihenfolge bleibt)
  function parse(s) {
    let i = 0;
    const ws = () => { while (i < s.length && /\s/.test(s[i])) i++; };
    const str = () => {
      ws();
      if (s[i] !== '"') throw new Error('Zeichenkette erwartet bei ' + JSON.stringify(s.slice(i, i + 20)));
      const e = skipStr(s, i);
      const v = s.slice(i + 1, e - 1);
      i = e;
      return v;
    };
    const arr = (inner) => {
      ws();
      if (s[i] !== '{') throw new Error('{ erwartet bei ' + JSON.stringify(s.slice(i, i + 20)));
      i++;
      const out = [];
      ws();
      if (s[i] === '}') { i++; return out; }
      for (;;) {
        const k = str();
        ws();
        if (s[i] !== '=') throw new Error('= erwartet hinter "' + k + '"');
        i++;
        ws();
        let v;
        // Werte als Rohtext (mit Anführungszeichen, wenn sie welche hatten) - so bleibt "2412" ein Text
        if (inner) {
          if (s[i] === '"') { const st = i; str(); v = s.slice(st, i); }
          else { const m = /^[-0-9]+/.exec(s.slice(i)); if (!m) throw new Error('Wert erwartet für "' + k + '"'); v = m[0]; i += m[0].length; }
        } else v = arr(true);
        out.push([k, v]);
        ws();
        if (s[i] === ';') { i++; continue; }
        if (s[i] === '}') { i++; return out; }
        throw new Error('; oder } erwartet bei ' + JSON.stringify(s.slice(i, i + 20)));
      }
    };
    const r = arr(false);
    ws();
    if (i !== s.length) throw new Error('Rest hinter dem Array: ' + JSON.stringify(s.slice(i, i + 20)));
    return r;
  }
  const q = (v) => '"' + v + '"';
  const unq = (v) => (v && v[0] === '"' ? v.slice(1, -1) : v);
  const apStr = (ap, bands) => q(ap) + '={' + bands.map(([b, v]) => q(b) + '=' + v).join(';') + '}';
  // Zeile aus der Ausgabe ('  wifi.rsc: "radios"={…}') -> Array-Text
  function lineValue(line) {
    const p = line.indexOf('"radios"=');
    if (p < 0) throw new Error('keine Zeile "radios"');
    return line.slice(p + '"radios"='.length).trim();
  }
  // txt = wifi.rsc, line = Zeile aus $cfmWifiScan, band = "2"|"5"|"6", note = Text für den Rückweg-Kommentar
  function apply(txt, line, band, note) {
    const r = find(txt);
    if (!r) throw new Error('wifi.rsc hat keinen Eintrag "radios" - erst "radios"={}; in :global cfmWifi anlegen');
    const oldTxt = txt.slice(r.start + '"radios"='.length, r.end);
    const cur = parse(oldTxt);
    const prop = parse(lineValue(line));
    const changes = [];
    prop.forEach(([ap, bands]) => {
      const nv = (bands.find(([b]) => b === band) || [])[1];
      if (nv === undefined) return;
      let e = cur.find(([a]) => a === ap);
      if (!e) { e = [ap, []]; cur.push(e); }
      const bb = e[1].find(([b]) => b === band);
      const ov = bb ? bb[1] : '';
      if (unq(ov) === unq(nv)) return;
      if (bb) bb[1] = nv; else e[1].push([band, nv]);
      changes.push(ap + ' ' + band + ': ' + (unq(ov) || '(ohne Pin)') + ' -> ' + unq(nv));
    });
    // Einrückung der Zeile mit "radios", eine Zeile je AP wie in den Site-Dateien
    const ls = txt.lastIndexOf('\n', r.start) + 1;
    const ind = /^[ \t]*/.exec(txt.slice(ls))[0];
    const pretty = '"radios"={' + (cur.length ? '\n' + cur.map(([a, b]) => ind + '  ' + apStr(a, b)).join(';\n') + '\n' + ind : '') + '}';
    let out = txt.slice(0, r.start) + pretty + txt.slice(r.end);
    if (changes.length) {
      const old1 = '"radios"={' + parse(oldTxt).map(([a, b]) => apStr(a, b)).join(';') + '}';
      const com = '# ' + note + ' (' + changes.join(', ') + '). Rückweg: ' + old1;
      // hinter das Ende des Arrays (erste Zeile "}" nach dem Eintrag), sonst ans Dateiende
      const m = /\n\}[ \t]*(\r?\n|$)/.exec(out.slice(r.start));
      if (m) {
        const at = r.start + m.index + m[0].length;
        out = out.slice(0, at) + (m[1] ? '' : '\n') + com + '\n' + out.slice(at);
      } else out = out.replace(/\n?$/, '\n') + com + '\n';
    }
    return { text: out, changes, pretty };
  }
  // Vorschläge aus der Ausgabe: [{name, kosten, line}]
  function proposals(out) {
    const res = [];
    const ls = String(out).split('\n');
    ls.forEach((l, i) => {
      const m = /^Vorschlag\s+(\S+)\s+Kosten\s+(\S+)/.exec(l);
      if (!m) return;
      for (let j = i + 1; j < Math.min(ls.length, i + 4); j++) {
        if (/^\s*wifi\.rsc: "radios"=/.test(ls[j])) { res.push({ name: m[1], kosten: m[2], line: ls[j].trim() }); break; }
        if (/^Vorschlag/.test(ls[j])) break;
      }
    });
    return res;
  }
  return { find, parse, apply, proposals };
})();
