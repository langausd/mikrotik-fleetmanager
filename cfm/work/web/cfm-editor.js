// cfm-editor.js 758e2b4411cb - erzeugt von tools/editor/build.py, nicht von Hand ändern
(() => {
const STAND = '758e2b4411cb';
const alt = window.__cfmEd;
if (alt && alt.stand === STAND) { alt.show(); return; }
if (alt && alt.drop && !alt.drop()) { alt.show(); return; }
document.getElementById('cfmed')?.remove();
const MAX = 60000;                       // wie $cfmParseWork: /file get liest nur ~60 KB
const ENDE = '@@cfm-ende@@';
const S = { base: '', files: [], cur: null, text: '', busy: false };
const $ = (sel) => root.querySelector(sel);
const el = (tag, attrs, ...kids) => {
const e = document.createElement(tag);
Object.entries(attrs || {}).forEach(([k, v]) => k.startsWith('on') ? e.addEventListener(k.slice(2), v) : e.setAttribute(k, v));
kids.forEach((k) => e.append(k));
return e;
};
const esc = (s) => String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\$/g, '\\$').replace(/\r/g, '').replace(/\n/g, '\\n');
const bytes = (s) => new TextEncoder().encode(s).length;
const clean = (t) => t.replace(/\r/g, '').split('\n').filter((l) => !/^Script file loaded and executed successfully$/.test(l.trim())).join('\n');
const cfmQr = (() => {
const ECC = [0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28,
28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28];
const BLK = [0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29,
31, 33, 35, 37, 38, 40, 43, 45, 47, 49];
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
function encode(text) {
const bytes = Array.from(new TextEncoder().encode(text));
let v = 1;
while (v <= 40 && 4 + (v < 10 ? 8 : 16) + bytes.length * 8 > dataCodewords(v) * 8) v++;
if (v > 40) throw new Error('Text zu lang für einen QR-Code');
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
const cfmRadios = (() => {
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
function lineValue(line) {
const p = line.indexOf('"radios"=');
if (p < 0) throw new Error('keine Zeile "radios"');
return line.slice(p + '"radios"='.length).trim();
}
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
const ls = txt.lastIndexOf('\n', r.start) + 1;
const ind = /^[ \t]*/.exec(txt.slice(ls))[0];
const pretty = '"radios"={' + (cur.length ? '\n' + cur.map(([a, b]) => ind + '  ' + apStr(a, b)).join(';\n') + '\n' + ind : '') + '}';
let out = txt.slice(0, r.start) + pretty + txt.slice(r.end);
if (changes.length) {
const old1 = '"radios"={' + parse(oldTxt).map(([a, b]) => apStr(a, b)).join(';') + '}';
const com = '# ' + note + ' (' + changes.join(', ') + '). Rückweg: ' + old1;
const m = /\n\}[ \t]*(\r?\n|$)/.exec(out.slice(r.start));
if (m) {
const at = r.start + m.index + m[0].length;
out = out.slice(0, at) + (m[1] ? '' : '\n') + com + '\n' + out.slice(at);
} else out = out.replace(/\n?$/, '\n') + com + '\n';
}
return { text: out, changes, pretty };
}
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
#cfmed main{flex:1;display:flex;min-height:0;position:relative}
#cfmed nav{width:260px;overflow:auto;border-right:1px solid #ccd;background:#fff;padding:6px 0}
#cfmed nav h4{margin:8px 10px 4px;font-size:11px;text-transform:uppercase;color:#667}
#cfmed nav div{padding:2px 10px 2px 16px;cursor:pointer;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#cfmed nav div:hover{background:#e6efed}
#cfmed nav div.akt{background:#13534b;color:#fff}
#cfmed nav div.ro{color:#778}
#cfmed section{flex:1;display:flex;flex-direction:column;min-width:0}
#cfmed .cfmed-bar{display:flex;gap:6px;align-items:center;padding:6px 8px;border-bottom:1px solid #ccd;flex-wrap:wrap;background:#fafbfa}
#cfmed .cfmed-bar>*{visibility:visible!important;opacity:1!important}
#cfmed .cfmed-bar>button,#cfmed .cfmed-bar>span,#cfmed .cfmed-bar>b,#cfmed .cfmed-bar>label,#cfmed .cfmed-bar>select{display:inline-block!important}
#cfmed .ed{flex:1;display:flex;min-height:0;font:12.5px/1.45 ui-monospace,Menlo,Consolas,monospace}
#cfmed .gut{width:48px;overflow:hidden;text-align:right;padding:6px 6px 6px 0;color:#99a;background:#f0f1f0;white-space:pre;user-select:none}
#cfmed textarea{flex:1;border:0;padding:6px 8px;resize:none;font:inherit;white-space:pre;overflow:auto;outline:none;tab-size:2}
#cfmed textarea[readonly]{background:#f7f7f5}
#cfmed .stat{padding:3px 8px;font-size:12px;color:#556;border-top:1px solid #ccd;background:#fafbfa}
#cfmed pre{margin:0;height:34%;overflow:auto;padding:6px 8px;background:#1d2321;color:#dfe;font:12px/1.4 ui-monospace,Menlo,Consolas,monospace;white-space:pre-wrap}
#cfmed .login{margin:12vh auto;background:#fff;padding:20px 24px;border-radius:8px;box-shadow:0 2px 12px #0002;display:grid;gap:8px;width:320px}
#cfmed .fehler{color:#b3261e}
#cfmed .sign{position:absolute;inset:0;z-index:5;display:flex;background:#e9ecea}
#cfmed .sign .ctl{width:300px;padding:12px;display:flex;flex-direction:column;gap:8px;background:#fff;border-right:1px solid #ccd;overflow:auto}
#cfmed .sign .ctl label{display:flex;flex-direction:column;gap:3px;font-size:12px;color:#556}
#cfmed .sign .vor{flex:1;overflow:auto;padding:16px}
#cfmed .blatt{width:210mm;height:297mm;background:#fff;color:#000;box-shadow:0 2px 10px #0003;transform-origin:0 0;position:relative;
font-family:"DejaVu Sans",Arial,sans-serif;text-align:center;overflow:hidden}
#cfmed .blatt .t1{position:absolute;top:24mm;left:18mm;right:18mm;font-size:40pt;font-weight:bold;line-height:1.1}
#cfmed .blatt .t2{position:absolute;top:39mm;left:18mm;right:18mm;font-size:26pt;color:#595959}
#cfmed .blatt .qr{position:absolute;top:52mm;left:45mm;width:120mm;height:120mm}
#cfmed .blatt .qr svg{width:100%;height:100%;display:block}
#cfmed .blatt .scan{position:absolute;top:174mm;left:18mm;right:18mm;font-size:11pt;color:#595959}
#cfmed .blatt .unten{position:absolute;top:186mm;left:18mm;right:18mm}
#cfmed .blatt .lab{font-size:13pt;color:#595959;margin-top:5mm}
#cfmed .blatt .wert{font-size:30pt;font-weight:bold;overflow-wrap:anywhere;margin-top:2mm}
#cfmed .blatt .pw{font:bold 26pt "DejaVu Sans Mono",Consolas,monospace;margin-top:2mm;white-space:pre;line-height:1.3}
#cfmed .blatt .hint{position:absolute;bottom:18mm;left:18mm;right:18mm;font-size:12pt;color:#595959}
@media print{body>*:not(#cfmed){display:none!important}
#cfmed{position:static!important;display:block!important;background:#fff}
#cfmed>header,#cfmed main>:not(.sign){display:none!important}
#cfmed main{display:block}
#cfmed .sign{position:static;display:block;background:#fff}
#cfmed .sign .ctl{display:none}
#cfmed .sign .vor{padding:0;overflow:visible}
#cfmed .sign .vor>div{width:auto!important;height:auto!important}
#cfmed .blatt{transform:none!important;box-shadow:none}
@page{size:A4;margin:0}}`;
const root = el('div', { id: 'cfmed' });
root.append(el('style', {}, css));
document.body.append(root);
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
const exec = async (script) => (await rest('POST', '/execute', { script, 'as-string': true })).ret || '';
const read = async (id) => (await rest('POST', '/file/get', { '.id': id, 'value-name': 'contents' })).ret || '';
const fileByName = async (name) => (await rest('GET', '/file?name=' + encodeURIComponent(name)))[0];
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
busy(false);
return clean(txt).replace(ENDE, '');
} catch (e) {
out.textContent += '\nFEHLER: ' + e.message;
}
busy(false);
return '';
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
async function loginView(hinweis) {
root.querySelectorAll('header,main,.login').forEach((n) => n.remove());
if (!hinweis && restOk()) {
let ok = false;
try { const id = await rest('GET', '/system/identity'); S.ident = id.name; ok = true; } catch (e) { restOk(false); }
if (ok) { await mainView(S.ident).catch((e3) => { $('pre').textContent = 'FEHLER: ' + e3.message; }); return; }
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
try { const id = await rest('GET', '/system/identity'); S.ident = id.name; } catch (e2) { msg.textContent = 'Fehler: ' + e2.message; return; }
await mainView(S.ident).catch((e3) => { $('pre').textContent = 'FEHLER: ' + e3.message; });
};
root.append(el('form', { class: 'login', onsubmit: go }, el('b', {}, 'cfm-Editor'),
el('div', {}, 'Anmeldung an der REST-API dieses Managers (RouterOS-User mit Gruppe full).'),
u, p, el('button', { class: 'prim', type: 'submit' }, 'Anmelden'), msg,
el('button', { type: 'button', onclick: hide }, 'Schließen')));
u.focus();
}
async function mainView(identity) {
root.querySelectorAll('header,main,.login').forEach((n) => n.remove());
const hosts = el('select', { title: 'Gerät für den Probelauf' });
const msg = el('input', { placeholder: 'Release-Notiz', size: 28 });
const ring = el('select', { title: 'Ring für $cfmPromote' },
el('option', { value: '' }, 'nächster Ring'), el('option', { value: '1' }, 'Ring 1'), el('option', { value: '2' }, 'Ring 2'));
root.append(el('header', {},
el('b', {}, 'cfm-Editor – ' + identity),
el('button', { onclick: check, 'data-cmd': 1 }, 'Prüfen'),
el('button', { onclick: diff, 'data-cmd': 1 }, 'Diff zum Release'),
hosts, el('button', { onclick: () => plan(hosts.value), 'data-cmd': 1 }, 'Probelauf'),
msg, el('button', { onclick: () => release(msg.value), 'data-cmd': 1 }, 'Release (Ring 0)'),
ring, el('button', { onclick: () => promote(ring.value), 'data-cmd': 1, title: 'Version des vorigen Rings freigeben ($cfmPromote)' }, 'Promote'),
el('button', { onclick: fleetStatus, 'data-cmd': 1, title: 'Flottenübersicht ($cfmStatus)' }, 'Status'),
el('button', { onclick: sign, 'data-cmd': 1, title: 'WLAN-Schild als A4-PDF (QR-Code, SSID, Passphrase aus dem Vault)' }, 'WLAN-Schild'),
el('button', { onclick: channels, 'data-cmd': 1, title: 'Kanal und Sendeleistung je AP, live vom CAPsMAN ($cfmChannels)' }, 'Kanäle'),
el('button', { onclick: () => scanBar(hosts), 'data-cmd': 1, title: 'Kanal-Scan der APs mit Vorschlag ($cfmWifiScan), Vorschlag in wifi.rsc übernehmen' }, 'WLAN-Scan'),
el('span', { class: 'sp' }),
el('button', { onclick: hide }, 'Schließen')));
const ta = el('textarea', { spellcheck: 'false', readonly: '' });
const gut = el('div', { class: 'gut' });
root.append(el('main', {},
el('nav', {}),
el('section', {},
el('div', { class: 'cfmed-bar' },
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
.map((f) => ({ ...f, rel: f.name.slice(w.length), ro: /^(lib|roles|web)\//.test(f.name.slice(w.length)) }))
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
if (!/^(hosts\/)?[A-Za-z0-9][A-Za-z0-9._-]*$/.test(rel) || /^(lib|roles|web)\//.test(rel)) { alert('Name nicht erlaubt: nur Site-Daten, z.B. hosts/<name>.rsc'); return; }
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
function check() {
if (unsaved()) return;
run('Prüfen ($cfmParseWork, $cfmCheck)',
':onerror x in={ /import file-name=([$cfmMB] . "/work/lib/mgr-check.rsc") verbose=no } do={}; :global cfmCheck; ' +
':local p [$cfmParseWork]; :if ([:len $p] > 0) do={ :put ("Größe/Syntax:" . $p) } else={ :put "Größe und Syntax: ok" }; ' +
':local ck [$cfmCheck quiet=yes]; :foreach w in=($ck->"warn") do={ :put ("Warnung: " . $w) }; :foreach x in=($ck->"err") do={ :put ("Fehler: " . $x) }; ' +
':foreach x in=($ck->"note") do={ :put ("Hinweis: " . $x) }; ' +
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
m = (m || '').trim();
if (!m && !confirm('Achtung: Die Release-Notiz ist leer.\nArchiv, Git-Hook und Log zeigen dann nur die Versionsnummer.\n\nTrotzdem ohne Notiz releasen?')) return;
if (!confirm('Release aus work/ erstellen und an Ring 0 verteilen?' + (m ? '\nNotiz: ' + m : '\n(ohne Notiz)'))) return;
run('Release ($cfmRelease, Ring 0)', '$cfmRelease msg="' + esc(m ? ' ' + m : '') + '"', ['cfmRelease']);
}
function promote(r) {
if (r !== '' && r !== '1' && r !== '2') return;
if (!confirm((r ? 'Ring ' + r : 'Den nächsten Ring') + ' auf die Version des vorigen Rings heben ($cfmPromote)?\nDie Geräte des Rings bekommen sie sofort per Push.')) return;
run('Promote ($cfmPromote' + (r ? ' ring=' + r : '') + ')', '$cfmPromote' + (r ? ' ring=' + r : ''), ['cfmPromote']);
}
function fleetStatus() { run('Flottenübersicht ($cfmStatus)', '$cfmStatus', ['cfmStatus']); }
function channels() { run('Kanäle der APs ($cfmChannels)', '$cfmChannels', ['cfmChannels']); }
function scanBar(hosts) {
const alt = $('.scanbar');
if (alt) { alt.remove(); return; }
const band = el('select', { title: 'Band' }, el('option', { value: '5' }, '5 GHz'), el('option', { value: '6' }, '6 GHz'), el('option', { value: '2' }, '2,4 GHz'));
const all = el('input', { type: 'checkbox', title: 'alle EU-Kanäle statt des Pools aus wifi.rsc (all=yes, 5/6 GHz)' });
const dat = el('input', { type: 'checkbox', title: 'mit der letzten Messung rechnen, ohne neuen Scan (data=yes)' });
const ap = el('select', { title: 'nur dieser AP neu (host=), die übrigen aus der letzten Messung' }, el('option', { value: '' }, 'alle APs'));
Array.from(hosts.options).forEach((o) => ap.append(el('option', { value: o.value }, o.value)));
const vor = el('span', { class: 'vor' });
const go = el('button', { class: 'prim', 'data-cmd': 1 }, 'Scan starten');
go.addEventListener('click', async () => {
if (unsaved()) return;
const b = band.value;
let cmd = '$cfmWifiScan band=' + b;
if (all.checked && b !== '2') cmd += ' all=yes';
if (dat.checked) cmd += ' data=yes';
else if (ap.value && /^[A-Za-z0-9._-]+$/.test(ap.value)) cmd += ' host="' + esc(ap.value) + '"';
if (!dat.checked && !confirm('Die APs scannen nacheinander (je Radio ~10 s, verbundene Clients wechseln kurz zum Nachbarn).\nJetzt scannen?')) return;
vor.textContent = '';
const out = await run('WLAN-Scan (' + cmd + ')', cmd, ['cfmWifiScan']);
const ps = cfmRadios.proposals(out);
if (!ps.length) { vor.textContent = 'kein Vorschlag'; return; }
ps.forEach((p) => vor.append(el('button', { onclick: () => takeOver(p, b), title: p.line }, '„' + p.name + '“ übernehmen (Kosten ' + p.kosten + ')')));
});
const bar = el('div', { class: 'cfmed-bar scanbar' }, el('b', {}, 'WLAN-Scan'), band,
el('label', {}, all, ' alle EU-Kanäle'), el('label', {}, dat, ' letzte Messung'), ap, go, vor,
el('button', { onclick: () => bar.remove() }, 'Schließen'));
$('pre').before(bar);
}
async function takeOver(p, band) {
const f = S.files.find((x) => x.rel === 'wifi.rsc');
if (!f) { $('pre').textContent += '\nwifi.rsc nicht gefunden'; return; }
if (!S.cur || S.cur.name !== f.name) await open(f);
if (!S.cur || S.cur.name !== f.name) return;
const ta = $('textarea');
const tag = new Date().toISOString().slice(0, 10);
let r;
try { r = cfmRadios.apply(ta.value, p.line, band, tag + ' Kanalvorschlag „' + p.name + '“ ' + band + ' GHz übernommen (cfm-Editor)'); } catch (e) { $('pre').textContent += '\nFEHLER beim Übernehmen: ' + e.message; return; }
if (!r.changes.length) { $('pre').textContent += '\n\nVorschlag „' + p.name + '“ = laufender Plan in wifi.rsc – nichts zu ändern.'; return; }
ta.value = r.text;
lines(); status();
$('pre').textContent += '\n\nIn wifi.rsc übernommen (noch NICHT gespeichert), Rückweg als Kommentar unter dem Array:\n  ' +
r.changes.join('\n  ') + '\nWeiter: Speichern (Strg+S), „Prüfen“, „Probelauf“ für den CAPsMAN, „Release (Ring 0)“; meldet der CAPsMAN ' +
'„CAP-Radio … veraltet“, dort cfm-reprov. DFS-Kanäle senden erst nach der CAC (≥ 60 s).';
$('pre').scrollTop = $('pre').scrollHeight;
}
async function sign() {
if (S.busy || $('.sign')) return;
busy(true);
const out = $('pre');
let d = null;
try {
const t = await exec('/system script run cfm-mgr; :global cfmLoadData; :global cfmWifi; :local v [$cfmLoadData]; ' +
':local df ($cfmWifi->"defaults"); :local o ({}); :foreach k,x in=($cfmWifi->"ssids") do={ ' +
':local sec [:tostr ($x->"sec")]; :if ([:len $sec] = 0) do={ :set sec [:tostr ($df->"sec")] }; :local pp ""; ' +
':foreach n,e in=($cfmWifi->"ppsk"->$k) do={ :set pp ($pp . $n . ",") }; ' +
':set ($o->$k) ({"ssid"=[:tostr ($x->"ssid")];"sec"=$sec;"ppsk"=$pp;"only"=[:tostr ($x->"ppskOnly")]}) }; ' +
':put ("J=" . [:serialize to=json ({"v"=$v;"s"=$o})])');
const j = t.split('\n').map((l) => l.trim()).find((l) => l.startsWith('J='));
if (!j) throw new Error('keine WLAN-Daten vom Manager: ' + clean(t).trim().slice(0, 200));
d = JSON.parse(j.slice(2));
} catch (e) { out.textContent = 'FEHLER beim Lesen der WLAN-Daten: ' + e.message; busy(false); return; }
busy(false);
const ssids = Array.isArray(d.s) ? {} : (d.s || {});
const keys = Object.keys(ssids).sort((a, b) => a.localeCompare(b));
if (!keys.length) { out.textContent = 'Keine SSID in wifi.rsc (v' + d.v + ').'; return; }
const selS = el('select', {});
keys.forEach((k) => selS.append(el('option', { value: k }, ssids[k].ssid + ' (' + k + ')')));
if (ssids.guest) selS.value = 'guest';
const selP = el('select', {});
const t1 = el('input', {});
const hint = el('input', { placeholder: 'z.B. Gültigkeit oder Ansprechpartner' });
const info = el('div', { class: 'fehler' });
const druck = el('button', { class: 'prim', onclick: () => window.print() }, 'Drucken / als PDF speichern');
const vor = el('div', { class: 'vor' });
const pane = el('div', { class: 'sign' },
el('div', { class: 'ctl' },
el('b', {}, 'WLAN-Schild'),
el('div', {}, 'Stand: Release v' + d.v + ' (was die Geräte ausstrahlen). Passphrase aus dem Vault.'),
el('label', {}, 'SSID', selS),
el('label', {}, 'Passphrase', selP),
el('label', {}, 'Überschrift (deutsch | englisch)', t1),
el('label', {}, 'Hinweis unten (optional)', hint),
druck,
el('button', { onclick: () => pane.remove() }, 'Schließen'),
info,
el('div', { style: 'font-size:11px;color:#667' }, 'Im Druckdialog A4, Ränder „keine“, Skalierung 100 %. Das PDF enthält die Passphrase – nicht ins Repo legen.')),
vor);
$('main').append(pane);
const pass = {};
const fillP = () => {
const k = selS.value;
const x = ssids[k];
selP.textContent = '';
if (x.only !== 'yes') selP.append(el('option', { value: 'psk.' + k }, 'Passphrase der SSID (psk.' + k + ')'));
String(x.ppsk || '').split(',').filter(Boolean).forEach((n) => selP.append(el('option', { value: 'ppsk.' + k + '.' + n }, 'PPSK ' + n + ' (ppsk.' + k + '.' + n + ')')));
t1.value = /gast|guest/i.test(k + ' ' + x.ssid) ? 'Gäste-WLAN | Guest Wi-Fi' : 'WLAN | Wi-Fi';
};
const draw = async () => {
const x = ssids[selS.value];
const key = selP.value;
info.textContent = '';
if (!key && cfmQr.authType(x.sec) !== 'nopass') { info.textContent = 'Keine Passphrase wählbar (ppskOnly ohne ppsk-Eintrag).'; druck.disabled = true; return; }
const typ = !key ? 'nopass' : (key.startsWith('ppsk.') ? 'WPA' : cfmQr.authType(x.sec));
let pw = '';
if (typ !== 'nopass') {
if (pass[key] === undefined) {
try {
const r = await exec(':local i [/ppp/secret/find where name="' + esc('cfm:' + key) + '"]; :if ([:len $i] = 0) do={ :put "P-" } else={ :put ("P=" . [/ppp/secret/get $i password]) }');
const l = r.replace(/\r/g, '').split('\n').find((z) => z.startsWith('P=') || z.startsWith('P-')) || '';
pass[key] = l.startsWith('P=') ? l.slice(2) : '';
} catch (e) { info.textContent = 'Vault nicht lesbar: ' + e.message; druck.disabled = true; return; }
}
pw = pass[key];
if (!pw) { info.textContent = 'Vault: cfm:' + key + ' fehlt ($cfmSecret key=' + key + ' value=…)'; }
}
const [de, en] = t1.value.includes('|') ? t1.value.split('|').map((z) => z.trim()) : [t1.value.trim(), ''];
const qr = el('div', { class: 'qr' });
qr.innerHTML = cfmQr.svg(cfmQr.wifi(x.ssid, pw, typ));
const unten = el('div', { class: 'unten' },
el('div', { class: 'lab' }, 'Netzwerk / Network'), el('div', { class: 'wert' }, x.ssid));
if (typ !== 'nopass') {
const zeilen = (pw.match(/.{1,24}/g) || ['']).join('\n');
unten.append(el('div', { class: 'lab' }, 'Passwort / Password'), el('div', { class: 'pw' }, zeilen));
}
const blatt = el('div', { class: 'blatt' },
el('div', { class: 't1' }, de), el('div', { class: 't2' }, en && en !== de ? en : ''), qr,
el('div', { class: 'scan' }, 'QR-Code mit der Kamera scannen · Scan the QR code with your camera'), unten,
el('div', { class: 'hint' }, hint.value));
const mm = 96 / 25.4;
const sc = Math.min(1, (vor.clientWidth - 32) / (210 * mm), (vor.clientHeight - 32) / (297 * mm));
blatt.style.transform = 'scale(' + sc + ')';
vor.textContent = '';
vor.append(el('div', { style: 'width:' + (210 * mm * sc) + 'px;height:' + (297 * mm * sc) + 'px' }, blatt));
druck.disabled = !!info.textContent;
};
selS.addEventListener('change', () => { fillP(); draw(); });
selP.addEventListener('change', draw);
t1.addEventListener('input', draw);
hint.addEventListener('input', draw);
fillP();
await draw();
}
function hide() {
if (dirty() && !confirm('Ungespeicherte Änderungen an ' + S.cur.rel + ' verwerfen?')) return;
root.style.display = 'none';
}
window.__cfmEd = {
stand: STAND,
show: () => { root.style.display = 'flex'; },
drop: () => {
if (dirty() && !confirm('Neue Fassung des cfm-Editors: ungespeicherte Änderungen an ' + S.cur.rel + ' verwerfen?')) return false;
root.remove();
return true;
},
};
loginView();
})();
