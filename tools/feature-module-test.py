#!/usr/bin/env python3
"""Tests für tools/feature-module.py: welche Feature-Module (D104) eine Site braucht."""
import importlib.util
import os
import pathlib
import shutil
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("feature_module", pathlib.Path(__file__).with_name("feature-module.py"))
fm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fm)


class Bedarf(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        # Vorlage: kein Feature genutzt
        for f in ("global.rsc", "vlans.rsc", "wireguard.rsc", "dns.rsc", "mlag.rsc"):
            shutil.copy(ROOT / "cfm/work" / f, self.d)
        os.makedirs(os.path.join(self.d, "hosts"))
        shutil.copy(ROOT / "cfm/work/hosts/sw1.rsc", os.path.join(self.d, "hosts"))

    def tearDown(self):
        shutil.rmtree(self.d)

    def schreiben(self, name, text):
        with open(os.path.join(self.d, name), "w", encoding="utf-8") as fh:
            fh.write(text)

    def anhaengen(self, name, text):
        with open(os.path.join(self.d, name), "a", encoding="utf-8") as fh:
            fh.write(text)

    def genutzt(self):
        return sorted(m for m, (ja, _) in fm.bedarf(self.d).items() if ja)

    def test_vorlage_nutzt_nichts(self):
        self.assertEqual(self.genutzt(), [])
        # jede Regel gehört zu einem Modul der Vorlage, jedes Modul der Vorlage hat eine Regel
        self.assertEqual(sorted(fm.bedarf(self.d)), fm.module(ROOT / "cfm/work/lib"))

    def test_snmp(self):
        self.schreiben("global.rsc", ':global cfmG {"snmp"={"from"={"192.168.10.5"}}}\n')
        self.assertEqual(self.genutzt(), ["base.snmp"])
        self.schreiben("global.rsc", ':global cfmG {"snmp"=({})}\n# "snmp"={"from"={"x"}}\n')
        self.assertEqual(self.genutzt(), [])
        # per :set gesetzt: Wert unbekannt -> gebraucht
        self.schreiben("global.rsc", ':global cfmG {"snmp"={}}\n:set ($cfmG->"snmp") $x\n')
        self.assertEqual(self.genutzt(), ["base.snmp"])

    def test_iso_und_limit(self):
        self.anhaengen("vlans.rsc", ':set ($cfmVlans->"30"->"isolate") "yes"\n')
        self.assertEqual(self.genutzt(), ["base.iso"])
        self.schreiben("vlans.rsc", ':global cfmVlans {"30"={"isolate"="no";"limit"=""};"40"={"limitClient"="10M/2M"}}\n')
        self.assertEqual(self.genutzt(), ["router.limit"])

    def test_sshkeys(self):
        self.schreiben("authorized_keys.alice", "ssh-ed25519 AAAA x\n")
        self.schreiben("authorized_keys.bob~", "")
        self.assertEqual(self.genutzt(), ["base.sshkeys"])

    def test_wireguard(self):
        self.schreiben("wireguard.rsc", ':global cfmWg {"net"="10.9.0.0/24";"peers"={"laptop"={"addr"=2;"pubkey"="x"}}}\n')
        self.assertEqual(self.genutzt(), ["router.wg"])

    def test_dns(self):
        self.schreiben("dns.rsc", ':global cfmDns {"adlists"={"https://x/hosts"}}\n')
        self.assertEqual(self.genutzt(), ["router.dns"])
        self.schreiben("dns.rsc", ':global cfmDns {"self"={"zones"={"lan"}}}\n')
        self.assertEqual(self.genutzt(), ["router.dns", "router.dnsreq"])
        self.schreiben("dns.rsc", "# leer\n:global cfmDns ({})\n")
        self.assertEqual(self.genutzt(), [])

    def test_bonds(self):
        self.schreiben("hosts/srv1.rsc", ':global cfmHost {"bonds"={"bond1"={"slaves"="ether2,ether3"}}}\n')
        self.assertEqual(self.genutzt(), ["base.bond"])
        os.remove(os.path.join(self.d, "hosts/srv1.rsc"))
        self.schreiben("mlag.rsc", ':global cfmMlag {"p1"={"nodes"={"sw1";"sw2"}}}\n')
        self.assertEqual(self.genutzt(), ["base.bond"])

    def test_ausgabe(self):
        lib = tempfile.mkdtemp()
        try:
            for f in ("base.snmp.rsc", "base.neu.rsc", "lib.rsc", "mgr-core.rsc"):
                open(os.path.join(lib, f), "w").close()
            self.schreiben("global.rsc", ':global cfmG {"snmp"={"from"={"x"}}}\n')
            # ohne Regel (base.neu) immer gebraucht; lib.rsc und mgr-* sind keine Feature-Module
            self.assertEqual(fm.module(lib), ["base.neu", "base.snmp"])
            self.assertEqual([m for m in fm.module(lib) if not fm.bedarf(self.d).get(m, (True,))[0]], [])
        finally:
            shutil.rmtree(lib)


if __name__ == "__main__":
    unittest.main()
