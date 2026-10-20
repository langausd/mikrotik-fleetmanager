#!/usr/bin/env python3
"""Tests für tools/rsc-check.py: je Regel ein Fund und die Fälle, die kein Fund sein dürfen."""
import importlib.util
import os
import pathlib
import subprocess
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location("rsc_check", pathlib.Path(__file__).with_name("rsc-check.py"))
rc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rc)


def rules(text, path="x.rsc"):
    return sorted({f.rule for f in rc.check_file(path, text.encode())})


def lines(text, path="x.rsc"):
    return [(f.line, f.rule) for f in rc.check_file(path, text.encode())]


class KlammerAnfang(unittest.TestCase):
    def test_fund(self):
        self.assertEqual(lines(':global f\n[$f x=1]\n'), [(2, "klammer-anfang")])
        self.assertEqual(rules('  [/system/identity/get name]\n'), ["klammer-anfang"])

    def test_kein_fund(self):
        self.assertEqual(rules(':local a [$f x=1]\n$f x=1\n'), [])
        self.assertEqual(rules(':local a ($x .\n  [$f])\n'), [])       # Fortsetzung in Klammern
        self.assertEqual(rules(':if (true) do={ [$f] }\n'), [])        # nicht am Zeilenanfang
        self.assertEqual(rules('# [$f] im Kommentar\n'), [])


class LeeresArray(unittest.TestCase):
    def test_fund(self):
        self.assertEqual(lines(':global a {}\n'), [(1, "leeres-array")])
        self.assertEqual(lines('# x\n:global a {\n}\n'), [(2, "leeres-array")])
        self.assertEqual(rules(':local a {}\n'), ["leeres-array"])

    def test_kein_fund(self):
        self.assertEqual(rules(':global a ({})\n'), [])
        self.assertEqual(rules(':global a {\n  "x"=1\n}\n'), [])
        self.assertEqual(rules(':global p {\n  "peers"={\n  }\n}\n'), [])   # verschachtelt erlaubt
        self.assertEqual(rules(':global f do={}\n'), [])                     # leere Funktion
        self.assertEqual(rules('$f p=({})\n'), [])


class KommentarImArray(unittest.TestCase):
    def test_fund(self):
        self.assertEqual(lines(':global p {\n  "a"={"x"=1};\n  # Kommentar\n  "b"={"x"=2}\n}\n'),
                         [(3, "kommentar-im-array")])
        self.assertEqual(rules(':local v {\n  "a"=1;\n  # dazu\n  "b"=2\n}\n'), ["kommentar-im-array"])

    def test_kein_fund(self):
        self.assertEqual(rules('# davor\n:global p {\n  "a"=1\n}\n# danach\n'), [])
        self.assertEqual(rules(':global f do={\n  # im Funktionsrumpf\n  :return 1\n}\n'), [])
        self.assertEqual(rules(':onerror e in={\n  # im Fehlerblock\n  :put 1\n} do={ :put 2 }\n'), [])
        self.assertEqual(rules(':if (true) do={\n  :put 1\n} else={\n  # im else-Zweig\n  :put 2\n}\n'), [])
        self.assertEqual(rules(':foreach a in={"x";"y"} do={\n  # im Schleifenrumpf\n  :put $a\n}\n'), [])


class EscapeArgument(unittest.TestCase):
    def test_fund(self):
        self.assertEqual(rules('$cfmLog msg="a \\"b\\""\n'), ["escape-argument"])
        self.assertEqual(rules('$cfmLog "a \\"b\\""\n'), ["escape-argument"])
        self.assertEqual(rules(':local r [$f cmd="x \\"y\\""]\n'), ["escape-argument"])

    def test_kein_fund(self):
        self.assertEqual(rules(':local m "a \\"b\\""\n$cfmLog msg=$m\n'), [])
        self.assertEqual(rules('$f cmd=("a \\"" . $x . "\\"")\n'), [])  # Ausdruck in Klammern
        self.assertEqual(rules(':put "a \\"b\\""\n'), [])               # kein Funktionsaufruf
        self.assertEqual(rules('$f cmd=":put \\$x"\n'), [])             # \$ ist kein \"


class ReturnOnerror(unittest.TestCase):
    def test_fund(self):
        self.assertEqual(rules(':global f do={ :onerror e in={ :return 1 } do={} }\n'), ["return-onerror"])
        self.assertEqual(lines(':onerror e in={\n  :if (true) do={\n    :return 1\n  }\n} do={}\n'),
                         [(3, "return-onerror")])

    def test_kein_fund(self):
        self.assertEqual(rules(':onerror e in={ :set r 1 } do={}\n:return $r\n'), [])
        self.assertEqual(rules(':onerror e in={ :local g do={ :return 1 } } do={}\n'), [])
        self.assertEqual(rules(':onerror e in={ :set r 1 } do={ :return 0 }\n'), [])
        self.assertEqual(rules(':if (true) do={ :return 1 }\n'), [])


class Geraetemenue(unittest.TestCase):
    def test_fund(self):
        self.assertEqual(rules('/system/routerboard/settings/set auto-upgrade=yes\n'), ["geraetemenue"])
        self.assertEqual(rules(':local s [/interface/ethernet/switch/find]\n'), ["geraetemenue"])

    def test_kein_fund(self):
        self.assertEqual(rules('/system routerboard settings set auto-upgrade=yes\n'), [])
        self.assertEqual(rules('$cfmSet m="/system/routerboard/settings" p=({"auto-upgrade"="yes"})\n'), [])
        self.assertEqual(rules('# /system/routerboard\n/system/license/get system-id\n'), [])


class ArrayKlammern(unittest.TestCase):
    def test_fund(self):
        self.assertEqual(rules('$cfmEnsure m="/x" k="y" p={"a"=1}\n'), ["array-klammern"])

    def test_kein_fund(self):
        self.assertEqual(rules('$cfmEnsure m="/x" k="y" p=({"a"=1})\n'), [])
        self.assertEqual(rules(':if (true) do={ :put 1 } else={ :put 2 }\n'), [])
        self.assertEqual(rules(':foreach u in={"a";$b} do={ :put $u }\n'), [])


class ImportVerbose(unittest.TestCase):
    def test_fund(self):
        self.assertEqual(rules('/import x.rsc verbose=yes\n'), ["import-verbose"])

    def test_kein_fund(self):
        self.assertEqual(rules('/import x.rsc verbose=no\n'), [])
        self.assertEqual(rules('# /import x.rsc verbose=yes\n'), [])


class Syntax(unittest.TestCase):
    def test_fund(self):
        self.assertEqual(lines(':if (true) do={\n:put 1\n'), [(1, "syntax")])
        self.assertEqual(rules(':put "abc\n'), ["syntax"])
        self.assertEqual(rules(':put 1 }\n'), ["syntax"])
        self.assertEqual(rules(':put [:len (1]\n'), ["syntax"])

    def test_kein_fund(self):
        self.assertEqual(rules(':put "a { [ ( # b"\n'), [])
        self.assertEqual(rules(':local x 1 ;# Kommentar mit { und "\n'), [])
        self.assertEqual(rules(':put ("a" . \\\n  "b")\n'), [])                # Zeilenfortsetzung


class Ausnahme(unittest.TestCase):
    def test_zeile_darueber(self):
        self.assertEqual(rules('# rsc-check: erlaubt klammer-anfang\n[$f]\n'), [])

    def test_zeilenende(self):
        self.assertEqual(rules('/import x.rsc verbose=yes ;# rsc-check: erlaubt import-verbose\n'), [])

    def test_andere_regel_bleibt(self):
        self.assertEqual(rules('# rsc-check: erlaubt syntax\n[$f]\n'), ["klammer-anfang"])


class JsonTyp(unittest.TestCase):
    def test_fund(self):
        self.assertEqual(lines(':local s ({})\n:set ($s->"ros") [/system/resource/get version]\n:put [:serialize to=json $s]\n'),
                         [(2, "json-typ")])
        self.assertEqual(lines(':local v [/system routerboard get upgrade-firmware]\n:set ($st->"fw") $v\n'
                               ':put [:serialize to=json $st]\n'), [(2, "json-typ")])
        # über eine :parse-Funktion (Menü fehlt auf CHR) wie beim Fehler der Firmware-Sperre
        self.assertEqual(lines(':local fu [:parse ":return [/system/routerboard/get upgrade-firmware]"]\n'
                               ':set u [$fu]\n:set ($st->"fw") $u\n:put [:serialize to=json $st]\n'),
                         [(3, "json-typ")])
        self.assertEqual(rules(':local ix ({"d"=([/system/clock/get date] . " x")})\n:put [:serialize to=json $ix]\n'),
                         ["json-typ"])

    def test_kein_fund(self):
        # Präfix davor, kein JSON in der Datei, gleichnamige Local in einer anderen Funktion
        self.assertEqual(rules(':set ($s->"fw") ("v" . [/system/resource/get version])\n:put [:serialize to=json $s]\n'), [])
        self.assertEqual(rules(':set ($s->"ros") [/system/resource/get version]\n'), [])
        self.assertEqual(rules(':global a do={\n  :local cur [/system/resource/get version]\n}\n'
                               ':global b do={\n  :set ($s->"f") $cur\n  :put [:serialize to=json $s]\n}\n'), [])
        self.assertEqual(rules('# rsc-check: erlaubt json-typ\n:set ($s->"ros") [/system/resource/get version]\n'
                               ':put [:serialize to=json $s]\n'), [])

class Dateien(unittest.TestCase):
    def test_groesse(self):
        big = "# " + "x" * (rc.GROESSE_MAX + 10) + "\n"
        self.assertEqual(rc.check_file("cfm/work/lib/a.rsc", big.encode())[0][2:4], (rc.FEHLER, "dateigroesse"))
        mid = "# " + "x" * (rc.GROESSE_HINWEIS + 10) + "\n"
        self.assertEqual(rc.check_file("cfm/work/lib/a.rsc", mid.encode())[0][2:4], (rc.HINWEIS, "dateigroesse"))
        self.assertEqual(rc.check_file("cfm/work/meta/x.dat", big.encode())[0][2:4], (rc.FEHLER, "dateigroesse"))

    def test_groesse_overlay(self):
        # TODO 60: in einem Overlay zählt die Größe nur für Dateien, die upload-seed.sh hochlädt
        big = "# " + "x" * (rc.GROESSE_MAX + 10) + "\n"
        self.assertEqual(rc.check_file("site/ist/export.rsc", big.encode(), upload=False), [])
        self.assertEqual(rc.check_file("site/hosts/sw1.rsc", big.encode())[0][2:4], (rc.FEHLER, "dateigroesse"))
        self.assertEqual([rc.hochgeladen(x) for x in ("vlans.rsc", "hosts/sw1.rsc", "meta/inventory.rsc",
                                                       "ist/export.rsc", "umzug/2026/leases-A.rsc")],
                         [True, True, True, False, False])

    def test_dotfile(self):
        self.assertEqual(rules("", "cfm/work/hosts/.sw1.rsc"), ["dotfile"])
        self.assertEqual(rules("", "tools/.x.rsc"), [])

    def test_git(self):
        # Pre-Commit-Hook (--staged) und Standardlauf liefern je Datei (Pfad, Inhalt, hochgeladen)
        with tempfile.TemporaryDirectory() as d:
            subprocess.run(["git", "init", "-q", d], check=True)
            os.makedirs(os.path.join(d, "cfm/work/lib"))
            with open(os.path.join(d, "cfm/work/lib/a.rsc"), "w") as fh:
                fh.write(":put 1\n")
            subprocess.run(["git", "-C", d, "add", "cfm/work/lib/a.rsc"], check=True)
            for staged in (True, False):
                self.assertEqual(list(rc.files_from_git(d, staged)), [("cfm/work/lib/a.rsc", b":put 1\n", True)])


if __name__ == "__main__":
    unittest.main()
