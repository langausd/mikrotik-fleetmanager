#!/usr/bin/env python3
"""Tests für tools/wifi-sign.py: wifi.rsc lesen, QR-Inhalt (Typ, Maskierung), PDF (nur mit segno und pycairo)."""
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("wifisign", os.path.join(HERE, "wifi-sign.py"))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)

WIFI = '''# Kommentar mit Beispiel: "ppsk"={"test"={"geraet1"={"vlan"=200}}}
#   "guest"={"ssid"="Falsch";"vlan"=1};
:global cfmWifi {
  "master"="main";
  "defaults"={"sec"="wpa2-psk,wpa3-psk";"ft"="yes";"pmf"="allowed"};
  "ssids"={
    "main"={"ssid"="Haus";"vlan"=2;"bands"="2,5";"sec"="wpa3-psk";"pmf"="required"};
    "guest"={"ssid"="Haus-Gast";"vlan"=21;"bands"="2,5";"isolation"="yes";"fallback"="yes"};
    "offen"={"ssid"="Cafe";"sec"="none"}
  };
  "radios"={"ap1"={"5"="5180"}}
}
'''


def have_pdf_libs():
    return all(importlib.util.find_spec(m) for m in ("segno", "cairo"))


class Parse(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        with open(os.path.join(self.d, "wifi.rsc"), "w", encoding="utf-8") as f:
            f.write(WIFI)

    def test_ssids_und_defaults(self):
        defaults, ssids = ws.parse_wifi(os.path.join(self.d, "wifi.rsc"))
        self.assertEqual(defaults["sec"], "wpa2-psk,wpa3-psk")
        self.assertEqual(ssids["guest"]["ssid"], "Haus-Gast")  # nicht die auskommentierte Zeile
        self.assertEqual(ssids["main"]["sec"], "wpa3-psk")
        self.assertEqual(sorted(ssids), ["guest", "main", "offen"])

    def test_fehlender_schluessel(self):
        with self.assertRaises(SystemExit) as cm:
            ws.main(["--overlay", self.d, "--ssid", "iot", "--passphrase-stdin"])
        self.assertIn("iot fehlt", str(cm.exception))


class Payload(unittest.TestCase):
    def test_typ(self):
        self.assertEqual(ws.auth_type("wpa2-psk,wpa3-psk"), "WPA")
        self.assertEqual(ws.auth_type("wpa2-psk"), "WPA")
        self.assertEqual(ws.auth_type("wpa3-psk"), "SAE")
        self.assertEqual(ws.auth_type("none"), "nopass")

    def test_maskierung(self):
        self.assertEqual(ws.qr_payload('a;b', 'p:w,"x\\', "WPA"), 'WIFI:T:WPA;S:a\\;b;P:p\\:w\\,\\"x\\\\;;')

    def test_offen_und_versteckt(self):
        self.assertEqual(ws.qr_payload("Cafe", "", "nopass"), "WIFI:T:nopass;S:Cafe;;")
        self.assertEqual(ws.qr_payload("X", "y", "WPA", hidden=True), "WIFI:T:WPA;S:X;P:y;H:true;;")


@unittest.skipUnless(have_pdf_libs(), "segno/pycairo fehlen (sudo apt install python3-segno python3-cairo)")
class Pdf(unittest.TestCase):
    def test_pdf_a4_und_rechte(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "wifi.rsc"), "w", encoding="utf-8") as f:
            f.write(WIFI)
        out = os.path.join(d, "s.pdf")
        r = subprocess.run([sys.executable, os.path.join(HERE, "wifi-sign.py"), "--overlay", d, "--ssid", "guest",
                            "--passphrase-stdin", "-o", out], input="geheim;123", capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        data = open(out, "rb").read()
        self.assertTrue(data.startswith(b"%PDF"))
        self.assertIn(b"595.27", data)  # MediaBox A4
        self.assertEqual(os.stat(out).st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
