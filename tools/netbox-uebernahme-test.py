#!/usr/bin/env python3
"""Tests für tools/netbox-uebernahme.py: Hostfile (ports, portDefault, links), leases.rsc, vlans.rsc, Ablauf."""
import contextlib
import importlib.util
import io
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("nbu", os.path.join(HERE, "netbox-uebernahme.py"))
U = importlib.util.module_from_spec(spec)
spec.loader.exec_module(U)

SW1 = """# sw1 – Kommentar bleibt
:global cfmHost {
  "location"="Keller";
  "portDefault"="off";
  "ports"={
    "ether1"="trunk";
    "ether2"="access:30"
  };
  "stpPrio"="0xE000"
}
"""
RTR1 = """:global cfmHost {
  "ports"={"ether1"="trunk";"ether2"="wan"};
  "routerId"=1
}
"""
AP1 = """# ap1
:global cfmHost {
  "location"="Flur"
}
"""
LEASES = """# Kopf mit Beispiel
#  :global cfmLeases {
#    "30"={"drucker"={"mac"="02:00:00:00:00:30";"ip"=20};
:global cfmLeases {
  "30"={
    "drucker"={"mac"="02:00:00:00:00:AA";"ip"=20};
    "kamera"={"mac"="02:00:00:00:00:BB";"ip"=21;"wifi"="yes"}
  }
}
"""
VLANS = """:global cfmVlans {
  "10"={"name"="MGMT";"zone"="mgmt"};
  "30"={"name"="IOT";"zone"="iot";"dhcp"="50-200"}
}
"""


def plan(**kw):
    p = {"site": "s1", "devices": {
        "sw1": {"port_default": "off"}, "rtr1": {"port_default": ""}, "ap1": {"port_default": "trunk"},
        "neu1": {"port_default": ""}},
        "interfaces": {
            "sw1": {"ether1": {"type": "1000base-t", "spec": "trunk"}, "ether2": {"type": "1000base-t", "spec": "access:40"},
                    "ether5": {"type": "1000base-t", "spec": "hybrid:30"}, "bond1": {"type": "lag", "spec": "trunk"}},
            "rtr1": {"ether1": {"type": "1000base-t", "spec": "trunk"}, "ether2": {"type": "1000base-t", "spec": ""},
                     "ether3": {"type": "1000base-t", "spec": "access:30"}},
            "ap1": {"ether1": {"type": "1000base-t", "spec": "trunk"}}},
        "cables": [["rtr1", "ether1", "sw1", "ether1"], ["sw1", "ether8", "pc", "eth0"]],
        "vlans": {"10": "MGMT", "30": "IOT", "40": "KAMERA"},
        "prefixes": {"192.168.30.0/24": 30, "10.40.0.0/24": 40}}
    p.update(kw)
    return p


class FakeNB:
    def __init__(self, prefixes, ips, ifs):
        self.prefixes, self.ips, self.ifs = prefixes, ips, ifs

    def get(self, path, **f):
        if path == "dcim/sites":
            return [{"id": 1}]
        if path == "ipam/prefixes":
            return self.prefixes
        if path == "ipam/ip-addresses":
            return [a for a in self.ips if a["address"].startswith(f["parent"].rsplit(".", 1)[0] + ".")]
        if path in ("dcim/interfaces", "virtualization/interfaces"):
            return [i for i in self.ifs.get(path, []) if i["id"] == f["id"]]
        raise AssertionError(path)


class T(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.d, "hosts"))
        for n, t in (("sw1", SW1), ("rtr1", RTR1), ("ap1", AP1)):
            with open(os.path.join(self.d, "hosts", n + ".rsc"), "w") as f:
                f.write(t)
        with open(os.path.join(self.d, "hosts", "sw1.post.rsc"), "w") as f:
            f.write("# post\n")
        for n, t in (("leases.rsc", LEASES), ("vlans.rsc", VLANS)):
            with open(os.path.join(self.d, n), "w") as f:
                f.write(t)

    def test_hostfile_mehrzeilig(self):
        files, hin = U.vorschlag(plan(), self.d)
        neu = files["hosts/sw1.rsc"][1]
        self.assertIn('    "ether1"="trunk";\n    "ether2"="access:40";\n    "ether5"="hybrid:30"\n  };', neu)
        self.assertIn("# sw1 – Kommentar bleibt", neu)
        self.assertIn('"stpPrio"="0xE000"', neu)
        self.assertNotIn("bond1", neu)  # LAG nicht als Port
        self.assertIn('  "links"={\n    "ether1"="rtr1:ether1"\n  };', neu)  # nur Kabel zu Geräten mit Hostfile
        self.assertNotIn("pc:eth0", neu)

    def test_hostfile_einzeilig_und_hinweis(self):
        files, hin = U.vorschlag(plan(), self.d)
        neu = files["hosts/rtr1.rsc"][1]
        self.assertIn('"ports"={"ether1"="trunk";"ether2"="wan";"ether3"="access:30"};', neu)
        self.assertIn("rtr1 ether2: in NetBox ohne cfm_port, im Hostfile wan (bleibt)", hin)
        self.assertIn('"links"={', neu)

    def test_hostfile_ohne_ports(self):
        files, hin = U.vorschlag(plan(), self.d)
        neu = files["hosts/ap1.rsc"][1]
        self.assertIn(':global cfmHost {\n  "portDefault"="trunk";\n  "ports"={\n    "ether1"="trunk"\n  };\n  "location"="Flur"\n}', neu)
        self.assertTrue(any("neu1: kein Hostfile" in h for h in hin))

    def test_parse_ergebnis_bleibt_routeros(self):
        """jede geänderte Datei: Klammern ausgeglichen, letzte Zeile eines Blocks ohne ';'"""
        files, _ = U.vorschlag(plan(), self.d)
        for rel, (_, neu) in files.items():
            body = "\n".join(l for l in neu.split("\n") if not l.startswith("#"))
            self.assertEqual(body.count("{"), body.count("}"), rel)
            self.assertNotRegex(body, r";\n\s*\}", rel)

    def test_keine_aenderung(self):
        p = plan(devices={"sw1": {"port_default": "off"}}, interfaces={"sw1": {
            "ether1": {"type": "x", "spec": "trunk"}, "ether2": {"type": "x", "spec": "access:30"}}}, cables=[],
            vlans={"30": "IOT"})
        files, _ = U.vorschlag(p, self.d)
        self.assertEqual(files, {})

    def test_vlans_als_kommentar(self):
        files, _ = U.vorschlag(plan(), self.d)
        neu = files["vlans.rsc"][1]
        self.assertIn('#  "40"={"name"="KAMERA";"zone"="?";"net"="10.40.0.0/24"};', neu)
        self.assertTrue(neu.startswith(VLANS))

    def test_leases(self):
        nb = FakeNB([{"prefix": "192.168.30.0/24", "vlan": {"vid": 30}}, {"prefix": "192.168.10.0/24", "vlan": {"vid": 10}}], [
            # aus dem Start-Import: MAC in der Beschreibung, gleich wie cfm
            {"address": "192.168.30.20/24", "dns_name": "drucker.internal", "description": "cfm-Lease 02:00:00:00:00:AA"},
            # Adresse geändert
            {"address": "192.168.30.25/24", "dns_name": "kamera.internal", "description": "cfm-Lease 02:00:00:00:00:BB"},
            # neue VM mit MAC am Interface
            {"address": "192.168.30.60/24", "dns_name": "web1.internal", "assigned_object_type": "virtualization.vminterface",
             "assigned_object": {"id": 7, "virtual_machine": {"name": "web1"}}},
            # cfm-Gerät: keine Lease
            {"address": "192.168.10.21/24", "dns_name": "sw1.internal", "assigned_object_type": "dcim.interface",
             "assigned_object": {"id": 3, "device": {"name": "sw1"}}},
            # ohne MAC
            {"address": "192.168.30.61/24", "dns_name": "ohne.internal"}],
            {"virtualization/interfaces": [{"id": 7, "primary_mac_address": {"mac_address": "02:00:00:00:00:07"}}]})
        l, hin = U.netbox_leases(nb, "s1", ["sw1", "rtr1"])
        self.assertEqual([x["name"] for x in l], ["drucker", "kamera", "web1"])
        self.assertTrue(any("ohne.internal" in h for h in hin))
        files, hin = U.vorschlag(plan(), self.d, l)
        neu = files["leases.rsc"][1]
        self.assertIn('    "kamera"={"mac"="02:00:00:00:00:BB";"ip"=25;"wifi"="yes"};\n    "web1"={"mac"="02:00:00:00:00:07";"ip"=60}\n  }', neu)
        self.assertIn('#    "30"={"drucker"={"mac"="02:00:00:00:00:30";"ip"=20};', neu)  # Kopf unverändert

    def test_leases_leere_form_und_neuer_block(self):
        l = [{"vid": "30", "name": "a", "mac": "02:00:00:00:00:01", "addr": "192.168.30.70", "net": "192.168.30.0/24"},
             {"vid": "40", "name": "b", "mac": "02:00:00:00:00:02", "addr": "10.40.0.5", "net": "10.40.0.0/24"}]
        neu = U.leases_apply(":global cfmLeases ({})\n", [(x["vid"], x["name"], x["mac"], 70 if x["vid"] == "30" else 5, None) for x in l], [])
        self.assertEqual(neu, ':global cfmLeases {\n  "30"={\n    "a"={"mac"="02:00:00:00:00:01";"ip"=70}\n  };\n  "40"={\n'
                              '    "b"={"mac"="02:00:00:00:00:02";"ip"=5}\n  }\n}\n')
        self.assertEqual(U.parse_leases(neu)["40"]["b"]["ip"], 5)

    def test_main_schreiben(self):
        import json
        pf = os.path.join(self.d, "plan.json")
        with open(pf, "w") as f:
            json.dump(plan(), f)
        dfile = os.path.join(self.d, "v.diff")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = U.main(["--overlay", self.d, "--plan", pf, "--diff-datei", dfile])
        self.assertEqual(rc, 1)
        self.assertIn("+++ b/hosts/sw1.rsc", out.getvalue())
        self.assertIn("mit --schreiben", out.getvalue())
        with open(os.path.join(self.d, "hosts", "sw1.rsc")) as f:
            self.assertEqual(f.read(), SW1)
        with contextlib.redirect_stdout(io.StringIO()):
            U.main(["--overlay", self.d, "--plan", pf, "--schreiben"])
            rc = U.main(["--overlay", self.d, "--plan", pf])
        self.assertEqual(rc, 0)  # zweiter Lauf: nichts mehr (VLAN-Vorschlag steht schon drin)


if __name__ == "__main__":
    unittest.main()
