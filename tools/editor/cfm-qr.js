// cfm-qr.js – QR-Code-Encoder für das WLAN-Schild im cfm-Editor (DT3.4.1). build.py setzt die Datei an der
// Marke im Editor ein; eigene Datei, damit tools/editor/cfm-qr-test.py sie allein prüfen kann (gjs + zbar).
// Kein CDN: Der Editor lädt seinen Code vom Gerät. Byte-Modus (UTF-8), Fehlerkorrektur M wie tools/wifi-sign.py,
// Version 1–40 nach Bedarf, Maske nach den Strafpunkten der Norm (ISO/IEC 18004).
const cfmQr = (() => {
  // Je Version (Index 1–40) bei Stufe M: Fehlerkorrektur-Bytes je Block und Zahl der Blöcke
  const ECC = [0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28,
    28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28];
  const BLK = [0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29,
    31, 33, 35, 37, 38, 40, 43, 45, 47, 49];
  // Galois-Feld GF(256), Polynom 0x11D
  const mul = (x, y) => {
    let z = 0;
    for (let i = 7; i >= 0; i--) { z = (z << 1) ^ ((z >>> 7) * 0x11d); z ^= ((y >>> i) & 1) * x; }
    return z & 0xff;
  };
  const divisor = (d) => {
    const r = new Array(d).fill(0);
    r[d - 1] = 1;
    let root = 1;
    for (let i = 0; i < d; i++) {
      for (let j = 0; j < d; j++) { r[j] = mul(r[j], root); if (j + 1 < d) r[j] ^= r[j + 1]; }
      root = mul(root, 2);
    }
    return r;
  };
  const remainder = (data, div) => {
    const r = div.map(() => 0);
    data.forEach((b) => {
      const f = b ^ r.shift();
      r.push(0);
      div.forEach((c, i) => { r[i] ^= mul(c, f); });
    });
    return r;
  };
  const rawModules = (v) => {
    let n = (16 * v + 128) * v + 64;
    if (v >= 2) { const a = Math.floor(v / 7) + 2; n -= (25 * a - 10) * a - 55; if (v >= 7) n -= 36; }
    return n;
  };
  const dataCodewords = (v) => Math.floor(rawModules(v) / 8) - ECC[v] * BLK[v];
  const alignPos = (v) => {
    if (v === 1) return [];
    const n = Math.floor(v / 7) + 2;
    const size = v * 4 + 17;
    const step = v === 32 ? 26 : Math.ceil((v * 4 + 4) / (n * 2 - 2)) * 2;
    const r = [6];
    for (let p = size - 7; r.length < n; p -= step) r.splice(1, 0, p);
    return r;
  };
  const MASK = [
    (x, y) => (x + y) % 2 === 0, (x, y) => y % 2 === 0, (x) => x % 3 === 0, (x, y) => (x + y) % 3 === 0,
    (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0, (x, y) => (x * y) % 2 + (x * y) % 3 === 0,
    (x, y) => ((x * y) % 2 + (x * y) % 3) % 2 === 0, (x, y) => ((x + y) % 2 + (x * y) % 3) % 2 === 0,
  ];

  // Strafpunkte der Norm: Läufe ab 5 gleichen Modulen, 2x2-Blöcke, Finder-ähnliche Muster, Hell/Dunkel-Verhältnis
  function penalty(m) {
    const n = m.length;
    let p = 0;
    const line = (get) => {
      for (let i = 0; i < n; i++) {
        let run = 1;
        for (let j = 1; j <= n; j++) {
          if (j < n && get(i, j) === get(i, j - 1)) { run++; continue; }
          if (run >= 5) p += run - 2;
          run = 1;
        }
        for (let j = 0; j + 11 <= n; j++) {
          const s = [];
          for (let k = 0; k < 11; k++) s.push(get(i, j + k) ? 1 : 0);
          const t = s.join('');
          if (t === '10111010000' || t === '00001011101') p += 40;
        }
      }
    };
    line((i, j) => m[i][j]);
    line((i, j) => m[j][i]);
    for (let y = 0; y + 1 < n; y++) {
      for (let x = 0; x + 1 < n; x++) {
        const c = m[y][x];
        if (c === m[y][x + 1] && c === m[y + 1][x] && c === m[y + 1][x + 1]) p += 3;
      }
    }
    let dark = 0;
    m.forEach((row) => row.forEach((c) => { if (c) dark++; }));
    p += Math.floor(Math.abs(dark * 20 - n * n * 10) / (n * n)) * 10;
    return p;
  }

  // text -> {size, mod}: mod[y][x] true = dunkel, ohne Ruhezone
  function encode(text) {
    const bytes = Array.from(new TextEncoder().encode(text));
    let v = 1;
    while (v <= 40 && 4 + (v < 10 ? 8 : 16) + bytes.length * 8 > dataCodewords(v) * 8) v++;
    if (v > 40) throw new Error('Text zu lang für einen QR-Code');
    // Bitstrom: Modus 0100, Länge, Daten, Ende, auffüllen
    const bits = [];
    const put = (val, len) => { for (let i = len - 1; i >= 0; i--) bits.push((val >>> i) & 1); };
    put(4, 4);
    put(bytes.length, v < 10 ? 8 : 16);
    bytes.forEach((b) => put(b, 8));
    const cap = dataCodewords(v) * 8;
    put(0, Math.min(4, cap - bits.length));
    put(0, (8 - (bits.length % 8)) % 8);
    for (let pad = 0xec; bits.length < cap; pad ^= 0xec ^ 0x11) put(pad, 8);
    const data = [];
    for (let i = 0; i < bits.length; i += 8) data.push(parseInt(bits.slice(i, i + 8).join(''), 2));
    // Blöcke mit Reed-Solomon, verschränkt
    const nb = BLK[v];
    const el = ECC[v];
    const raw = Math.floor(rawModules(v) / 8);
    const nShort = nb - (raw % nb);
    const shortLen = Math.floor(raw / nb);
    const div = divisor(el);
    const blocks = [];
    for (let i = 0, k = 0; i < nb; i++) {
      const len = shortLen - el + (i < nShort ? 0 : 1);
      const d = data.slice(k, k + len);
      k += len;
      const e = remainder(d, div);
      if (i < nShort) d.push(0);
      blocks.push(d.concat(e));
    }
    const cw = [];
    for (let i = 0; i < blocks[0].length; i++) {
      blocks.forEach((b, j) => { if (i !== shortLen - el || j >= nShort) cw.push(b[i]); });
    }
    // Matrix mit Funktionsmustern
    const size = v * 4 + 17;
    const mod = Array.from({ length: size }, () => new Array(size).fill(false));
    const fn = Array.from({ length: size }, () => new Array(size).fill(false));
    const set = (x, y, d) => { mod[y][x] = d; fn[y][x] = true; };
    for (let i = 0; i < size; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0); }
    [[3, 3], [size - 4, 3], [3, size - 4]].forEach(([cx, cy]) => {
      for (let dy = -4; dy <= 4; dy++) {
        for (let dx = -4; dx <= 4; dx++) {
          const x = cx + dx;
          const y = cy + dy;
          const dist = Math.max(Math.abs(dx), Math.abs(dy));
          if (x >= 0 && x < size && y >= 0 && y < size) set(x, y, dist !== 2 && dist !== 4);
        }
      }
    });
    const ap = alignPos(v);
    ap.forEach((ay, i) => ap.forEach((ax, j) => {
      const last = ap.length - 1;
      if ((i === 0 && j === 0) || (i === 0 && j === last) || (i === last && j === 0)) return;
      for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(ax + dx, ay + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
    }));
    const format = (mask) => {
      const d = (0 << 3) | mask;           // Stufe M = 00
      let r = d;
      for (let i = 0; i < 10; i++) r = (r << 1) ^ ((r >>> 9) * 0x537);
      const b = ((d << 10) | r) ^ 0x5412;
      const bit = (i) => ((b >>> i) & 1) === 1;
      for (let i = 0; i <= 5; i++) set(8, i, bit(i));
      set(8, 7, bit(6)); set(8, 8, bit(7)); set(7, 8, bit(8));
      for (let i = 9; i < 15; i++) set(14 - i, 8, bit(i));
      for (let i = 0; i < 8; i++) set(size - 1 - i, 8, bit(i));
      for (let i = 8; i < 15; i++) set(8, size - 15 + i, bit(i));
      set(8, size - 8, true);
    };
    format(0);                              // reserviert die Felder vor dem Einsetzen der Daten
    if (v >= 7) {
      let r = v;
      for (let i = 0; i < 12; i++) r = (r << 1) ^ ((r >>> 11) * 0x1f25);
      const b = (v << 12) | r;
      for (let i = 0; i < 18; i++) {
        const d = ((b >>> i) & 1) === 1;
        const a = size - 11 + (i % 3);
        const c = Math.floor(i / 3);
        set(a, c, d); set(c, a, d);
      }
    }
    // Daten im Zickzack von unten rechts
    let bi = 0;
    for (let right = size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let vert = 0; vert < size; vert++) {
        for (let j = 0; j < 2; j++) {
          const x = right - j;
          const y = ((right + 1) & 2) === 0 ? size - 1 - vert : vert;
          if (!fn[y][x] && bi < cw.length * 8) { mod[y][x] = ((cw[bi >>> 3] >>> (7 - (bi & 7))) & 1) === 1; bi++; }
        }
      }
    }
    const apply = (mask) => {
      for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) if (!fn[y][x] && MASK[mask](x, y)) mod[y][x] = !mod[y][x];
    };
    let best = 0;
    let bestP = Infinity;
    for (let mask = 0; mask < 8; mask++) {
      apply(mask); format(mask);
      const p = penalty(mod);
      if (p < bestP) { bestP = p; best = mask; }
      apply(mask);
    }
    apply(best); format(best);
    return { size, mod, version: v, mask: best };
  }

  // SVG mit Ruhezone von 4 Modulen, ein Pfad aus Rechtecken je Zeilenlauf
  function svg(text) {
    const q = encode(text);
    const n = q.size + 8;
    let d = '';
    q.mod.forEach((row, y) => {
      for (let x = 0; x < q.size; x++) {
        if (!row[x]) continue;
        let w = 1;
        while (x + w < q.size && row[x + w]) w++;
        d += 'M' + (x + 4) + ' ' + (y + 4) + 'h' + w + 'v1h-' + w + 'z';
        x += w - 1;
      }
    });
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + n + ' ' + n + '" shape-rendering="crispEdges">' +
      '<rect width="' + n + '" height="' + n + '" fill="#fff"/><path fill="#000" d="' + d + '"/></svg>';
  }

  // WLAN-Zugang wie tools/wifi-sign.py: WPA für WPA2 (auch gemischt), SAE nur bei reinem WPA3, nopass ohne Schlüssel
  const authType = (sec) => {
    const s = String(sec || '').toLowerCase();
    if (!s || s === 'none') return 'nopass';
    if (s.includes('wpa3') && !s.includes('wpa2') && !s.includes('wpa-')) return 'SAE';
    return 'WPA';
  };
  const wifiEsc = (s) => String(s).replace(/([\\;,:"])/g, '\\$1');
  const wifi = (ssid, pass, typ) => 'WIFI:T:' + typ + ';S:' + wifiEsc(ssid) + ';' + (typ !== 'nopass' ? 'P:' + wifiEsc(pass) + ';' : '') + ';';

  return { encode, svg, authType, wifi };
})();
