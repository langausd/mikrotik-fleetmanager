#!/usr/bin/env python3
"""Tests für tools/pve/cfm-lease-pve.py: net0 lesen, Name/VLAN, Sweep mit Tag, Hook, Zustand, Aufruf am Manager."""
import contextlib
import importlib.util
import io
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("clp", os.path.join(HERE, "cfm-lease-pve.py"))
P = importlib.util.module_from_spec(spec)
spec.loader.exec_module(P)

VM = """boot: order=scsi0
name: web_01.lab
net0: virtio=02:00:00:aa:bb:01,bridge=vmbr0,firewall=1,tag=30
tags: cfm;prod
"""
CT = """arch: amd64
hostname: db1
net0: name=eth0,bridge=vmbr1,hwaddr=02:00:00:AA:BB:02,ip=dhcp,type=veth
tags: other
"""
CT_STATIC = """hostname: fix
net0: name=eth0,bridge=vmbr0,hwaddr=02:00:00:AA:BB:03,ip=192.168.30.9/24,gw=192.168.30.1,type=veth
tags: cfm
"""


class Fake:
    def __init__(self, guests, cfgs, answer="LEASE ok vlan=30 name=x mac=y ip=z\nRELEASE v9\nERGEBNIS ok\n"):
        self.guests, self.cfgs, self.answer, self.calls = guests, cfgs, answer, []

    def __call__(self, cmd, inp=None):
        self.calls.append(cmd)
        if cmd[0] == "pvesh":
            kind = cmd[2].rsplit("/", 1)[1]
            return 0, json.dumps([{"vmid": int(v)} for k, v in self.guests if k == kind]), ""
        if cmd[0] in ("qm", "pct") and cmd[1] == "config":
            return 0, self.cfgs[cmd[2]], ""
        if cmd[0] == "pct" and cmd[1] == "set":
            return 0, "", ""
        if cmd[0] == "ssh":
            return 0, self.answer.replace("\n", "\r\n"), ""
        raise AssertionError(cmd)


class T(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.c = dict(P.DEFAULTS, MANAGER="cfm-lease@10.0.0.2", STATE=self.d, NODE="pve1", VLAN_MAP="vmbr1=40")

    def run_main(self, fake, args, env=None):
        P.run = fake
        P.load_conf = lambda path=None: self.c
        out = io.StringIO()
        old = dict(os.environ)
        os.environ.update(env or {})
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
                rc = P.main(args)
        finally:
            os.environ.clear()
            os.environ.update(old)
        return rc, out.getvalue()

    def test_net_vm_und_ct(self):
        self.assertEqual(P.guest_net("qemu", P.parse_config(VM)), ("02:00:00:AA:BB:01", "vmbr0", "30", ""))
        self.assertEqual(P.guest_net("lxc", P.parse_config(CT)), ("02:00:00:AA:BB:02", "vmbr1", "", ""))
        self.assertEqual(P.guest_net("lxc", P.parse_config(CT_STATIC))[3], "192.168.30.9/24")

    def test_name(self):
        self.assertEqual(P.lease_name("web_01.lab"), "web-01-lab")
        self.assertEqual(P.lease_name("--a..b--"), "a-b")
        self.assertEqual(len(P.lease_name("x" * 80)), 63)

    def test_plan(self):
        a, _ = P.plan_guest(self.c, "qemu", "101", P.parse_config(VM))
        self.assertEqual(a, "add name=web-01-lab vlan=30 mac=02:00:00:AA:BB:01")
        a, _ = P.plan_guest(self.c, "lxc", "102", P.parse_config(CT))
        self.assertEqual(a, "add name=db1 vlan=40 mac=02:00:00:AA:BB:02")  # VLAN aus VLAN_MAP
        a, why = P.plan_guest(self.c, "lxc", "103", P.parse_config(CT_STATIC))
        self.assertIsNone(a)
        self.assertIn("feste Adresse", why)
        self.c["ACME"] = "yes"
        a, _ = P.plan_guest(dict(self.c, VLAN_MAP=""), "lxc", "102", P.parse_config(CT))
        self.assertIsNone(a)  # kein VLAN

    def test_sweep_nur_mit_tag_und_zustand(self):
        f = Fake([("qemu", "101"), ("lxc", "102"), ("lxc", "103")], {"101": VM, "102": CT, "103": CT_STATIC})
        rc, out = self.run_main(f, ["sweep"])
        self.assertEqual(rc, 0, out)
        ssh = [c for c in f.calls if c[0] == "ssh"]
        self.assertEqual(len(ssh), 1)  # 102 ohne Tag, 103 feste Adresse
        self.assertIn(':global cfmLeaseArg "add name=web-01-lab vlan=30 mac=02:00:00:AA:BB:01"; /system script run cfm-lease', ssh[0][-1])
        self.assertIn("101: RELEASE v9", out)
        self.assertIn("103: übersprungen (feste Adresse", out)
        # zweiter Lauf: Zustand bekannt -> kein Aufruf
        f.calls.clear()
        rc, out = self.run_main(f, ["sweep"])
        self.assertEqual([c for c in f.calls if c[0] == "ssh"], [])
        # net0 geändert (andere MAC) -> neuer Aufruf
        f.cfgs["101"] = VM.replace("02:00:00:aa:bb:01", "02:00:00:aa:bb:09")
        rc, out = self.run_main(f, ["sweep"])
        self.assertEqual(len([c for c in f.calls if c[0] == "ssh"]), 1)

    def test_fehler_vom_manager(self):
        f = Fake([("qemu", "101")], {"101": VM}, answer="ERGEBNIS fehler: Name web-01-lab schon vergeben\n")
        rc, out = self.run_main(f, ["sweep"])
        self.assertEqual(rc, 1)
        self.assertIn("101: ERGEBNIS fehler: Name web-01-lab schon vergeben", out)
        self.assertFalse(os.path.exists(os.path.join(self.d, "101.done")))

    def test_hook_setzt_tag(self):
        f = Fake([("lxc", "102")], {"102": CT})
        rc, out = self.run_main(f, ["hook"], env={"CTID": "102", "HN": "db1"})
        self.assertEqual(rc, 0, out)
        self.assertIn(["pct", "set", "102", "--tags", "other;cfm"], f.calls)
        self.assertEqual(len([c for c in f.calls if c[0] == "ssh"]), 1)
        rc, out = self.run_main(f, ["hook"])
        self.assertEqual(rc, 2)

    def test_probe(self):
        f = Fake([("qemu", "101")], {"101": VM})
        rc, out = self.run_main(f, ["sweep", "--probe"])
        self.assertIn("101: würde eintragen: add name=web-01-lab", out)
        self.assertEqual([c for c in f.calls if c[0] == "ssh"], [])


if __name__ == "__main__":
    unittest.main()
