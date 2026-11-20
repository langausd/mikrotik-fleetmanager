#!/usr/bin/env python3
"""Tests für tools/editor/cfm-radios.js (Kanalvorschlag von $cfmWifiScan in wifi.rsc übernehmen, cfm-Editor DT3.5).

Läuft die Datei in node und prüft: nur das gescannte Band wird je AP ersetzt (Pins anderer Bänder, Listen und "off"
bleiben), Kommentarzeilen und Zeichenketten mit "radios" stören nicht, der Rückweg steht als Kommentar hinter dem
Array, ein Vorschlag gleich dem Plan ändert nichts, die Vorschläge werden aus der Ausgabe gelesen. Ohne node werden
die Tests übersprungen.

  tools/editor/cfm-radios-test.py
"""
import json
import pathlib
import shutil
import subprocess
import unittest

HIER = pathlib.Path(__file__).resolve().parent
JS = HIER / "cfm-radios.js"
NODE = shutil.which("node")

WIFI = """# Kopf
# alter Kommentar mit "radios"={"x"={"5"="5180"}}
:global cfmWifi {
  "master"="main";
  "ssids"={"main"={"ssid"="Test;{x}";"vlan"=20}};
  "radios"={
    "apA"={"2"="2412";"5"="5745"};
    "apB"={"2"="2437";"5"="5180";"6"="6215"};
    "apC"={"5"="5640,5660,5680";"2"="2462"};
    "apX"={"5"="off"}
  };
  "others"={}
}
# 2026-11-01 älterer Eintrag
"""

AUSGABE = """Kandidaten (Kanal/Breite) je AP: apA 25 apB 25 apC 4 - bis 80 MHz
Aktuell:          Kosten 27 apA=5745/80 apB=5180/80 apC=5660/40
Vorschlag breit  Kosten 20  apA=5745/80 apB=5260/80 apC=5660/40
  Anteile: fremde Netze 0, eigene APs 0, DFS 20, Leistung 0, Breite 0
  wifi.rsc: "radios"={"apA"={"2"="2412";"5"="5745/80"};"apB"={"2"="2437";"5"="5260/80";"6"="6215"};"apC"={"2"="2462";"5"="5660/40"};"apX"={"5"="off"}}
Vorschlag robust Kosten 3  apA=5745/80 apB=5825/20 apC=5660/40
  Anteile: fremde Netze 0, eigene APs 0, DFS 0, Leistung 3, Breite 0
  wifi.rsc: "radios"={"apA"={"2"="2412";"5"="5745/80"};"apB"={"2"="2437";"5"="5825/20";"6"="6215"};"apC"={"2"="2462";"5"="5660/40"};"apX"={"5"="off"}}
Pins mit Breite (DW3.8)
"""


def js(expr, **args):
    code = JS.read_text(encoding="utf-8") + "\nconst A = " + json.dumps(args) + ";\nprocess.stdout.write(JSON.stringify(" + expr + "));\n"
    r = subprocess.run([NODE, "-e", code], capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise AssertionError(r.stderr)
    return json.loads(r.stdout)


@unittest.skipIf(NODE is None, "node fehlt")
class Radios(unittest.TestCase):
    def test_vorschlaege_lesen(self):
        p = js("cfmRadios.proposals(A.o)", o=AUSGABE)
        self.assertEqual([x["name"] for x in p], ["breit", "robust"])
        self.assertEqual(p[0]["kosten"], "20")
        self.assertTrue(p[1]["line"].startswith('wifi.rsc: "radios"={"apA"'))

    def test_fuenf_ghz_nur_band_5(self):
        line = js("cfmRadios.proposals(A.o)[0].line", o=AUSGABE)
        r = js("cfmRadios.apply(A.t, A.l, '5', 'Test')", t=WIFI, l=line)
        t = r["text"]
        self.assertIn('    "apA"={"2"="2412";"5"="5745/80"};\n', t)
        self.assertIn('    "apB"={"2"="2437";"5"="5260/80";"6"="6215"};\n', t)
        # Liste je AP wird durch den Pin ersetzt, die Reihenfolge der Bänder bleibt
        self.assertIn('    "apC"={"5"="5660/40";"2"="2462"};\n', t)
        self.assertIn('    "apX"={"5"="off"}\n  };\n', t)
        self.assertEqual(len(r["changes"]), 3)
        # Rückweg-Kommentar direkt hinter dem Array, vor dem älteren Eintrag; alte Kommentarzeile unverändert
        self.assertIn('}\n# Test (apA 5: 5745 -> 5745/80, apB 5: 5180 -> 5260/80, apC 5: 5640,5660,5680 -> 5660/40). Rückweg: "radios"={"apA"={"2"="2412";"5"="5745"};"apB"', t)
        self.assertLess(t.index("# Test ("), t.index("# 2026-11-01"))
        self.assertIn('# alter Kommentar mit "radios"={"x"={"5"="5180"}}', t)
        self.assertIn('"ssid"="Test;{x}"', t)

    def test_zwei_ghz_behaelt_andere_baender(self):
        line = 'wifi.rsc: "radios"={"apA"={"2"="2462"};"apB"={"2"="2412"};"apD"={"2"="2437"}}'
        t = js("cfmRadios.apply(A.t, A.l, '2', 'Test').text", t=WIFI, l=line)
        self.assertIn('"apA"={"2"="2462";"5"="5745"}', t)
        self.assertIn('"apB"={"2"="2412";"5"="5180";"6"="6215"}', t)
        self.assertIn('"apD"={"2"="2437"}', t)
        self.assertIn('"apX"={"5"="off"}', t)

    def test_gleich_dem_plan(self):
        line = 'wifi.rsc: "radios"={"apA"={"2"="2412";"5"="5745"}}'
        r = js("cfmRadios.apply(A.t, A.l, '5', 'Test')", t=WIFI, l=line)
        self.assertEqual(r["changes"], [])
        self.assertNotIn("Rückweg", r["text"])

    def test_zweimal_uebernehmen(self):
        p = js("cfmRadios.proposals(A.o)", o=AUSGABE)
        t1 = js("cfmRadios.apply(A.t, A.l, '5', 'Eins').text", t=WIFI, l=p[0]["line"])
        t2 = js("cfmRadios.apply(A.t, A.l, '5', 'Zwei').text", t=t1, l=p[1]["line"])
        self.assertIn('"apB"={"2"="2437";"5"="5825/20";"6"="6215"}', t2)
        # beide Rückwege bleiben, der neuere oben; der Kommentar mit "radios" stört das Finden nicht
        self.assertLess(t2.index("# Zwei ("), t2.index("# Eins ("))
        self.assertEqual(t2.count('  "radios"={'), 1)

    def test_ohne_radios(self):
        with self.assertRaises(AssertionError):
            js("cfmRadios.apply(A.t, A.l, '5', 'x')", t=':global cfmWifi {\n  "master"="main"\n}\n', l='wifi.rsc: "radios"={}')


if __name__ == "__main__":
    unittest.main()
