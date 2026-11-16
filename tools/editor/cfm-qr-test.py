#!/usr/bin/env python3
"""Tests für tools/editor/cfm-qr.js (QR-Encoder des WLAN-Schilds im cfm-Editor, DT3.4.1).

Der Encoder läuft in gjs (GNOME-JavaScript), die Matrix wird als Graustufenbild mit libzbar dekodiert – geprüft
wird also, was ein Scanner liest, nicht eine bestimmte Maskenwahl. Dazu: die WIFI-Zeichenkette gleicht der von
tools/wifi-sign.py. Ohne gjs oder libzbar werden die Tests übersprungen (Debian: gjs, libzbar0t64).

  tools/editor/cfm-qr-test.py
"""
import ctypes
import ctypes.util
import importlib.util
import pathlib
import random
import shutil
import subprocess
import tempfile
import unittest

HIER = pathlib.Path(__file__).resolve().parent
QR_JS = HIER / "cfm-qr.js"


def zbar_lib():
    name = ctypes.util.find_library("zbar")
    if not name:
        return None
    z = ctypes.CDLL(name)
    z.zbar_image_scanner_create.restype = ctypes.c_void_p
    z.zbar_image_scanner_set_config.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    z.zbar_image_create.restype = ctypes.c_void_p
    z.zbar_image_set_format.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    z.zbar_image_set_size.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_uint]
    z.zbar_image_set_data.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p]
    z.zbar_scan_image.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    z.zbar_image_first_symbol.argtypes = [ctypes.c_void_p]
    z.zbar_image_first_symbol.restype = ctypes.c_void_p
    z.zbar_symbol_get_data.argtypes = [ctypes.c_void_p]
    z.zbar_symbol_get_data.restype = ctypes.c_void_p
    z.zbar_symbol_get_data_length.argtypes = [ctypes.c_void_p]
    z.zbar_symbol_get_data_length.restype = ctypes.c_uint
    z.zbar_image_destroy.argtypes = [ctypes.c_void_p]
    z.zbar_image_scanner_destroy.argtypes = [ctypes.c_void_p]
    return z


ZBAR = zbar_lib()
GJS = shutil.which("gjs")


def encode(texts):
    """Liste von Texten -> Liste von (version, mask, matrix) aus cfm-qr.js (ein gjs-Lauf für alle)."""
    drv = QR_JS.read_text(encoding="utf-8") + """
const T = JSON.parse(%s);
T.forEach((t) => {
  const r = cfmQr.encode(t);
  print('#' + r.version + ' ' + r.mask);
  r.mod.forEach((row) => print(row.map((c) => (c ? '1' : '0')).join('')));
});
""" % repr(__import__("json").dumps(texts))
    with tempfile.TemporaryDirectory() as d:
        f = pathlib.Path(d) / "qr-test.js"
        f.write_text(drv, encoding="utf-8")
        out = subprocess.run([GJS, str(f)], capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        raise AssertionError("gjs: " + out.stderr[-500:])
    res = []
    for line in out.stdout.splitlines():
        if line.startswith("#"):
            v, m = line[1:].split()
            res.append((int(v), int(m), []))
        elif line:
            res[-1][2].append([c == "1" for c in line])
    return res


def js_eval(expr):
    drv = QR_JS.read_text(encoding="utf-8") + "\nprint(JSON.stringify(%s));\n" % expr
    with tempfile.TemporaryDirectory() as d:
        f = pathlib.Path(d) / "qr-eval.js"
        f.write_text(drv, encoding="utf-8")
        out = subprocess.run([GJS, str(f)], capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        raise AssertionError("gjs: " + out.stderr[-500:])
    return __import__("json").loads(out.stdout.strip().splitlines()[-1])


def decode(matrix, scale=4):
    """Matrix -> dekodierte Bytes (zbar), Ruhezone 4 Module."""
    n = len(matrix)
    w = (n + 8) * scale
    img = bytearray(b"\xff" * (w * w))
    for y, row in enumerate(matrix):
        for x, c in enumerate(row):
            if c:
                for dy in range(scale):
                    o = ((y + 4) * scale + dy) * w + (x + 4) * scale
                    img[o:o + scale] = b"\x00" * scale
    sc = ZBAR.zbar_image_scanner_create()
    ZBAR.zbar_image_scanner_set_config(sc, 0, 0, 1)          # ZBAR_NONE, ZBAR_CFG_ENABLE
    ZBAR.zbar_image_scanner_set_config(sc, 64, 4, 1)         # ZBAR_QRCODE, ZBAR_CFG_BINARY: Bytes ohne Zeichensatz-Raten
    im = ZBAR.zbar_image_create()
    ZBAR.zbar_image_set_format(im, int.from_bytes(b"Y800", "little"))
    ZBAR.zbar_image_set_size(im, w, w)
    buf = ctypes.create_string_buffer(bytes(img), len(img))
    ZBAR.zbar_image_set_data(im, ctypes.addressof(buf), len(img), None)
    n_sym = ZBAR.zbar_scan_image(sc, im)
    data = None
    if n_sym > 0:
        s = ZBAR.zbar_image_first_symbol(im)
        data = ctypes.string_at(ZBAR.zbar_symbol_get_data(s), ZBAR.zbar_symbol_get_data_length(s))
    ZBAR.zbar_image_destroy(im)
    ZBAR.zbar_image_scanner_destroy(sc)
    return data


@unittest.skipUnless(GJS and ZBAR, "gjs oder libzbar fehlt")
class QrTest(unittest.TestCase):
    def check(self, texts):
        for t, (v, m, mx) in zip(texts, encode(texts)):
            with self.subTest(text=t[:40], version=v):
                self.assertEqual(len(mx), v * 4 + 17)
                self.assertEqual(decode(mx), t.encode("utf-8"))

    def test_typisch(self):
        self.check(["WIFI:T:WPA;S:Demo-Gast;P:geheim123;;", "a", "WIFI:T:SAE;S:Gäste-WLAN;P:Ünïcödé € ok;;",
                    "WIFI:T:WPA;S:a\\;b\\,c;P:x\\:y\\\\z\\\";;"])

    def test_versionen(self):
        # Längen an den Grenzen der Versionen 1-12: Länge im 8- und 16-Bit-Feld, Versionsinfo ab 7, kurze/lange Blöcke
        rnd = random.Random(1)
        texts = []
        for n in (14, 15, 26, 27, 42, 43, 62, 63, 84, 85, 106, 107, 122, 123, 152, 153, 180, 181, 213, 214, 251, 252, 287, 288):
            texts.append("".join(rnd.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789;:,") for _ in range(n)))
        res = encode(texts)
        self.assertEqual(res[0][0], 1)   # 14 Bytes passen in Version 1-M
        self.assertEqual(res[1][0], 2)
        self.check(texts)

    def test_gross(self):
        rnd = random.Random(2)
        self.check(["".join(chr(rnd.randrange(32, 127)) for _ in range(n)) for n in (500, 1000, 2331)])

    def test_masken(self):
        # alle acht Masken kommen vor und dekodieren
        rnd = random.Random(3)
        texts = ["".join(chr(rnd.randrange(32, 127)) for _ in range(rnd.randrange(5, 120))) for _ in range(60)]
        res = encode(texts)
        self.assertEqual({m for _, m, _ in res}, set(range(8)))
        for t, (_, _, mx) in zip(texts, res):
            self.assertEqual(decode(mx), t.encode())


@unittest.skipUnless(GJS, "gjs fehlt")
class WifiTest(unittest.TestCase):
    def test_wie_wifi_sign(self):
        spec = importlib.util.spec_from_file_location("wifi_sign", HIER.parent / "wifi-sign.py")
        ws = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(ws)
        faelle = [("Demo-Gast", "geheim123", "wpa2-psk,wpa3-psk"), ("a;b,c", 'x:y\\z"', "wpa3-psk"),
                  ("Offen", "", "none"), ("IoT", "p", "wpa2-psk"), ("X", "y", "")]
        for ssid, pw, sec in faelle:
            with self.subTest(ssid=ssid, sec=sec):
                typ = ws.auth_type(sec)
                self.assertEqual(js_eval("cfmQr.authType(%r)" % sec), typ)
                self.assertEqual(js_eval("cfmQr.wifi(%s, %s, %r)" % (__import__("json").dumps(ssid), __import__("json").dumps(pw), typ)),
                                 ws.qr_payload(ssid, pw, typ))


if __name__ == "__main__":
    unittest.main()
