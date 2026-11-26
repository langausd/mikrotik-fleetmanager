#!/usr/bin/env python3
"""Tests für tools/netbox-abgleich.py: Export-Parser, Soll/Ist aus state/, NetBox-REST-Abbildung, Abgleich."""
import contextlib
import importlib.util
import io
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("nbabgleich", os.path.join(HERE, "netbox-abgleich.py"))
nb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nb)

EXPORT_SW1 = r"""# 2026-11-24 19:41:09 by RouterOS 7.25.1
/interface bridge add comment=cfm:br frame-types=admit-only-vlan-tagged name=bridge vlan-filtering=yes
/interface ethernet set [ find default-name=ether1 ] disable-running-check=no
/interface ethernet set [ find default-name=ether7 ] disabled=yes
/interface ethernet set [ find default-name=sfp1 ] name=uplink
/interface bonding add comment=cfm:bond:bond1 mode=802.3ad name=bond1 slaves=ether5,ether6
/interface vlan add comment="cfm:vlan:10 MGMT" interface=bridge name=vlan10 vlan-id=10
/interface vrrp add comment=cfm:vrrp:30 interface=vlan30 name=vrrp30 on-master=":delay 5s; :if ([/interface/vrrp/get [find name=vrrp30] running]) do={ /ip/dhcp-server/enable [find name=dhcp30] }" vrid=30
/interface wireguard add comment=cfm:wg listen-port=13231 name=wg-admin
/interface bridge port add bridge=bridge comment=cfm:bp:uplink frame-types=admit-only-vlan-tagged interface=uplink
/interface bridge port add bridge=bridge comment=cfm:bp:ether2 frame-types=admit-only-untagged-and-priority-tagged interface=ether2 pvid=20
/interface bridge port add bridge=bridge comment=cfm:bp:ether3 interface=ether3 pvid=30
/interface bridge port add bridge=bridge comment=cfm:bp:bond1 frame-types=admit-only-vlan-tagged interface=bond1
/interface bridge port add bridge=bridge comment=cfm:bp:ether7 interface=ether7 pvid=20
/interface bridge vlan add bridge=bridge tagged=bridge,uplink,bond1 vlan-ids=10
/interface bridge vlan add bridge=bridge tagged=bridge,uplink,ether3,bond1 \
    vlan-ids=20
/interface bridge vlan add bridge=bridge tagged=bridge,uplink,bond1 untagged=ether3 vlan-ids=30
/ip address add address=192.168.10.21/24 comment=cfm:ip:mgmt interface=vlan10 network=192.168.10.0
/ip address add address=192.168.30.1 comment=cfm:vip:30 interface=vrrp30 network=192.168.30.1
/ip address add address="192.168.250.1/24" interface=wg-admin network=192.168.250.0
"""


def soll_basis():
    """state/netbox.json wie von $cfmNetbox (Zahlen als 10.000000, leere Arrays als [])"""
    return {
        "v": 7, "t": 1, "g": {"domain": "internal", "mgmtVlan": 10.0},
        "vlans": {
            "10": {"name": "MGMT", "zone": "mgmt", "l3": True, "dhcp": "", "isolate": False, "net": "192.168.10.0/24", "gw": "192.168.10.1"},
            "20": {"name": "LAN", "zone": "lan", "l3": True, "dhcp": "", "isolate": False, "net": "192.168.20.0/24", "gw": "192.168.20.1"},
            "30": {"name": "IOT", "zone": "iot", "l3": True, "dhcp": "50-200", "isolate": False, "net": "192.168.30.0/24", "gw": "192.168.30.1"},
        },
        "leases": [{"vlan": 30.0, "name": "drucker", "mac": "02:00:00:00:00:30", "ip": "192.168.30.20"}],
        "wg": {"net": "192.168.250.0/24", "router": "192.168.250.1", "peers": [], "sites": []},
        "inv": {
            "rtr1": {"serial": "AAA111", "role": "router", "ring": 2.0, "ip": "192.168.10.251", "enrolled": True},
            "sw1": {"serial": "BBB222", "role": "switch", "ring": 1.0, "ip": "192.168.10.21", "enrolled": True},
        },
        "hosts": {
            "rtr1": {"hostfile": True, "ports": {"ether1": {"spec": "trunk", "untag": "", "tag": "10,20,30", "bridge": True, "disabled": False}},
                     "slaves": [], "links": {"ether1": "sw1:uplink"}},
            "sw1": {"hostfile": True, "slaves": {"ether5": "bond1", "ether6": "bond1"},
                    "bonds": {"bond1": {"slaves": "ether5,ether6"}},
                    "links": {"uplink": "rtr1:ether1", "ether8": "-"},
                    "ports": {
                        "uplink": {"spec": "trunk", "untag": "", "tag": "10,20,30", "bridge": True, "disabled": False},
                        "bond1": {"spec": "trunk", "untag": "", "tag": "10,20,30", "bridge": True, "disabled": False},
                        "ether3": {"spec": "hybrid:30", "untag": 30.0, "tag": "20", "bridge": True, "disabled": False},
                        "*": {"spec": "access:20", "untag": 20.0, "tag": "", "bridge": True, "disabled": False}}},
        },
    }


def iface(t="1000base-t", mode=None, untag=None, tag=(), lag=None, spec=None, enabled=True):
    return {"type": t, "enabled": enabled, "mode": mode, "untag": untag, "tag": list(tag), "lag": lag, "spec": spec}


def plan_basis():
    return {
        "site": "s1",
        "devices": {
            "rtr1": {"serial": "AAA111", "model": "RB5009UG+S+IN", "part": "", "nbrole": "Router", "role": "router",
                     "port_default": None, "ip": "192.168.10.251", "status": "active"},
            "sw1": {"serial": "BBB222", "model": "CRS326-24G-2S+RM", "part": "", "nbrole": "Switch", "role": "switch",
                    "port_default": "access:20", "ip": "192.168.10.21", "status": "active"},
        },
        "interfaces": {
            "rtr1": {"ether1": iface(mode="tagged", tag=(10, 20, 30), spec="trunk")},
            "sw1": {
                "uplink": iface("10gbase-x-sfpp", mode="tagged-all", spec="trunk"),
                "bond1": iface("lag", mode="tagged-all", spec="trunk"),
                "ether2": iface(mode="access", untag=20),
                "ether3": iface(mode="tagged", untag=30, tag=(20,), spec="hybrid:30"),
                "ether5": iface(lag="bond1"), "ether6": iface(lag="bond1"),
                "ether7": iface(mode="access", untag=20),
                "ether8": iface(mode="access", untag=20),
                "vlan10": iface("virtual"),
            },
        },
        "cables": [["rtr1", "ether1", "sw1", "uplink"]],
        "vlans": {"10": "MGMT", "20": "LAN", "30": "IOT"},
        "prefixes": {"192.168.10.0/24": 10, "192.168.20.0/24": 20, "192.168.30.0/24": 30},
        "ips": [
            {"addr": "192.168.10.251/24", "dns": "", "dev": "rtr1", "if": "vlan10", "role": None},
            {"addr": "192.168.10.21/24", "dns": "", "dev": "sw1", "if": "vlan10", "role": None},
            {"addr": "192.168.10.1/24", "dns": "", "dev": None, "if": None, "role": "vip"},
            {"addr": "192.168.20.1/24", "dns": "", "dev": None, "if": None, "role": "vip"},
            {"addr": "192.168.30.1/24", "dns": "", "dev": None, "if": None, "role": "vip"},
            {"addr": "192.168.30.20/24", "dns": "drucker.internal", "dev": None, "if": None, "role": None},
            {"addr": "192.168.20.50/24", "dns": "nas.internal", "dev": None, "if": None, "role": None},
        ],
        "tunnels": {},
    }


def ist_basis():
    ex_sw1 = nb.parse_export(EXPORT_SW1.replace("/ip address add address=\"192.168.250.1/24\" interface=wg-admin network=192.168.250.0\n", ""))
    ex_rtr1 = nb.parse_export(
        "/interface bridge port add bridge=bridge frame-types=admit-only-vlan-tagged interface=ether1\n"
        "/interface bridge vlan add bridge=bridge tagged=bridge,ether1 vlan-ids=10,20,30\n"
        "/ip address add address=192.168.10.251/24 interface=vlan10 network=192.168.10.0\n")
    return {
        "rtr1": {"status": {"serial": "AAA111", "model": "RB5009UG+S+", "eth": ["ether1"],
                            "nb": [["ether1", "sw1", "uplink", "m02:00:00:00:00:01", "MikroTik"]]}, "export": ex_rtr1},
        "sw1": {"status": {"serial": "BBB222", "model": "CRS326-24G-2S+", "eth": ["uplink", "ether2", "ether3", "ether5", "ether6", "ether7", "ether8"],
                           "nb": [["uplink", "rtr1", "ether1", "m02:00:00:00:00:02", "MikroTik"]]}, "export": ex_sw1},
    }


def finde(items, bereich=None, obj=None, art=None, text=""):
    return [x for x in items if (bereich is None or x["bereich"] == bereich) and (obj is None or x["objekt"] == obj)
            and (art is None or x["art"] == art) and text in x["text"]]


class ExportTest(unittest.TestCase):
    def test_tokens(self):
        w = nb._tokens('/interface ethernet set [ find default-name=sfp1 ] name=uplink comment="a \\"b\\" c"')
        self.assertEqual(w, ["/interface", "ethernet", "set", "[ find default-name=sfp1 ]", "name=uplink", 'comment=a "b" c'])

    def test_parse(self):
        ex = nb.parse_export(EXPORT_SW1)
        self.assertEqual(ex["ren"], {"sfp1": "uplink"})
        self.assertIn("uplink", ex["eth_set"])
        self.assertEqual(ex["eth_off"], {"ether7"})
        self.assertEqual(ex["bonds"], {"bond1": ["ether5", "ether6"]})
        self.assertEqual(ex["vlans"], {"vlan10": 10})
        self.assertEqual(ex["wg"], ["wg-admin"])
        self.assertIn(("192.168.30.1", "vrrp30"), ex["ips"])
        self.assertIn(("192.168.250.1/24", "wg-admin"), ex["ips"])
        # Fortsetzungszeile (\ am Zeilenende)
        self.assertTrue(any(bv["vids"] == {20} and "ether3" in bv["tagged"] for bv in ex["bvlans"]))

    def test_ist_ports(self):
        ip = nb.ist_ports(nb.parse_export(EXPORT_SW1))
        self.assertEqual(ip["uplink"], {"untag": None, "tag": {10, 20, 30}, "disabled": False})
        self.assertEqual(ip["ether2"]["untag"], 20)
        self.assertEqual(ip["ether3"], {"untag": 30, "tag": {20}, "disabled": False})
        self.assertTrue(ip["ether7"]["disabled"])

    def test_modell_passt(self):
        self.assertTrue(nb.modell_passt("C52iG-5HaxD2HaxD-TC", "", "hAP ax²", "C52iG-5HaxD2HaxD"))
        self.assertTrue(nb.modell_passt("CRS326-24G-2S+RM", "", "CRS326-24G-2S+"))
        self.assertFalse(nb.modell_passt("CRS326-24G-2S+RM", "", "hAP ax²"))
        self.assertFalse(nb.modell_passt("RB", "", "RB5009UG+S+"))  # zu kurz für einen Präfix-Treffer

    def test_s(self):
        self.assertEqual(nb._s(10.0), "10")
        self.assertEqual(nb._s(None), "")
        self.assertEqual(nb._vids(20.0), {20})
        self.assertEqual(nb._vids("10,20-22"), {10, 20, 21, 22})


class LesendTest(unittest.TestCase):
    def test_ro_parse(self):
        # so gibt RouterOS es über SSH aus: :put hängt \r\n an, Stücke zu je CHUNK Bytes
        daten = "zeile1\nzweite Zeile mit Ümlaut\n".encode("utf-8")
        a, b = daten[:20], daten[20:]   # Schnitt mitten im Ü
        raw = (b"##CFMF cfm/state/a\r\n##CFMC 0\r\n" + a + b"\r\n##CFMC 20\r\n" + b + b"\r\n"
               b"##CFMF cfm/state/b NONE\r\n##CFMF cfm/state/c\r\n")
        r = nb._ro_parse(raw)
        self.assertEqual(r["cfm/state/a"], daten)
        self.assertIsNone(r["cfm/state/b"])
        self.assertEqual(r["cfm/state/c"], b"")

    def test_ro_save(self):
        raw = (b"CFMNB=1\r\n##CFMF flash/cfm/state/netbox.json\r\n##CFMC 0\r\n{\"inv\":{}}\r\n"
               b"##CFMF flash/cfm/state/sw1/status.dat\r\n##CFMC 0\r\nx\r\n"
               b"##CFMF flash/cfm/state/sw1/export.rsc NONE\r\n##CFMF cfm/state/../boese\r\n##CFMC 0\r\ny\r\n")
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(nb._ro_save(raw, d), 1)
            self.assertEqual(open(os.path.join(d, "netbox.json"), "rb").read(), b'{"inv":{}}')
            self.assertEqual(open(os.path.join(d, "sw1", "status.dat"), "rb").read(), b"x")
            self.assertFalse(os.path.exists(os.path.join(d, "sw1", "export.rsc")))
            self.assertFalse(os.path.exists(os.path.join(os.path.dirname(d), "boese")))
        with self.assertRaisesRegex(RuntimeError, "keine Ausgabe"):
            nb._ro_save(b"", "/nicht")
        with self.assertRaisesRegex(RuntimeError, "netbox.json fehlt"):
            nb._ro_save(b"CFMNB=0\r\n", "/nicht")


class StateTest(unittest.TestCase):
    def test_load_state(self):
        with tempfile.TemporaryDirectory() as d:
            s = soll_basis()
            hosts = s.pop("hosts")
            with open(os.path.join(d, "netbox.json"), "w") as f:
                json.dump(s, f)
            os.makedirs(os.path.join(d, "sw1"))
            with open(os.path.join(d, "sw1", "netbox.json"), "w") as f:
                json.dump(hosts["sw1"], f)
            with open(os.path.join(d, "sw1", "status.dat"), "w") as f:
                json.dump({"serial": "BBB222"}, f)
            with open(os.path.join(d, "sw1", "export.rsc"), "w") as f:
                f.write(EXPORT_SW1)
            soll, ist = nb.load_state(d)
            self.assertEqual(set(soll["hosts"]), {"sw1"})
            self.assertEqual(set(ist), {"sw1"})
            self.assertEqual(ist["sw1"]["export"]["bonds"]["bond1"], ["ether5", "ether6"])

    def test_load_state_ohne_netbox_json(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(RuntimeError):
                nb.load_state(d)


class FakeNB:
    def __init__(self, data, vpn=True):
        self.data = data
        self.vpn = vpn
        self.calls = []

    def get(self, path, **params):
        self.calls.append((path, params))
        if path.startswith("vpn/") and not self.vpn:
            raise RuntimeError("404")
        key = path + ("?" + "&".join("%s=%s" % kv for kv in sorted(params.items())) if params else "")
        return self.data.get(key, self.data.get(path, []))


class NetBoxTest(unittest.TestCase):
    def daten(self):
        dev = lambda n: {"name": n, "device": {"id": 1 if n == "rtr1" else 2, "name": n}}
        return {
            "dcim/sites?slug=s1": [{"id": 5}],
            "dcim/devices": [
                {"id": 1, "name": "rtr1", "serial": "AAA111", "device_type": {"model": "RB5009"},
                 "device_role": {"name": "Router"}, "primary_ip4": {"address": "192.168.10.251/24"},
                 "custom_fields": {"cfm_role": "router", "cfm_port_default": ""}, "status": {"value": "active"}},
                {"id": 2, "name": "sw1", "serial": "", "device_type": {"model": "CRS326"}, "role": {"name": "Switch"},
                 "primary_ip4": None, "custom_fields": {"cfm_port_default": "access:20"}},
                {"id": 3, "name": None},
            ],
            "dcim/interfaces": [
                {"device": {"name": "rtr1"}, "name": "ether1", "type": {"value": "1000base-t"}, "enabled": True,
                 "mode": {"value": "tagged"}, "untagged_vlan": None, "tagged_vlans": [{"vid": 10}, {"vid": 20}],
                 "lag": None, "custom_fields": {"cfm_port": "trunk"}},
                {"device": {"name": "sw1"}, "name": "ether5", "type": {"value": "1000base-t"}, "enabled": True,
                 "mode": None, "untagged_vlan": None, "tagged_vlans": [], "lag": {"name": "bond1"}, "custom_fields": {}},
                {"device": {"name": "fremd"}, "name": "x", "type": {"value": "1000base-t"}},
            ],
            "dcim/cables": [
                {"a_terminations": [{"object_type": "dcim.interface", "object": {"name": "ether1", "device": {"name": "rtr1"}}}],
                 "b_terminations": [{"object_type": "dcim.interface", "object": {"name": "uplink", "device": {"name": "sw1"}}}]},
                {"a_terminations": [{"object_type": "dcim.frontport", "object": {"name": "1"}}],
                 "b_terminations": [{"object_type": "dcim.interface", "object": {"name": "ether9", "device": {"name": "sw1"}}}]},
            ],
            "ipam/vlans": [{"vid": 10, "name": "MGMT"}],
            "ipam/prefixes": [{"prefix": "192.168.10.0/24", "vlan": {"vid": 10}}],
            "ipam/ip-addresses?parent=192.168.10.0/24": [
                {"id": 11, "address": "192.168.10.251/24", "dns_name": "", "assigned_object_type": "dcim.interface",
                 "assigned_object": {"name": "vlan10", "device": {"name": "rtr1"}}, "role": None},
                {"id": 12, "address": "192.168.10.1/24", "dns_name": "gw", "assigned_object_type": None,
                 "assigned_object": None, "role": {"value": "vip"}}],
            "ipam/ip-addresses": [
                {"id": 11, "address": "192.168.10.251/24", "assigned_object_type": "dcim.interface",
                 "assigned_object": {"name": "vlan10", "device": {"name": "rtr1"}}},
                {"id": 13, "address": "10.0.0.2/30", "assigned_object_type": "dcim.interface",
                 "assigned_object": {"name": "ether8", "device": {"name": "rtr1"}}}],
            "vpn/tunnel-terminations": [
                {"tunnel": {"name": "wg-site-b"}, "termination": {"name": "wg-site-b", "device": {"name": "rtr1"}}}],
        }

    def test_plan(self):
        f = FakeNB(self.daten())
        p = nb.plan_from_netbox(f, "s1")
        self.assertEqual(set(p["devices"]), {"rtr1", "sw1"})
        self.assertEqual(p["devices"]["rtr1"]["nbrole"], "Router")  # device_role (3.x)
        self.assertEqual(p["devices"]["rtr1"]["ip"], "192.168.10.251")
        self.assertIsNone(p["devices"]["rtr1"]["port_default"])  # leerer Text = nicht gesetzt
        self.assertEqual(p["devices"]["sw1"]["port_default"], "access:20")
        self.assertEqual(p["interfaces"]["rtr1"]["ether1"]["tag"], [10, 20])
        self.assertEqual(p["interfaces"]["rtr1"]["ether1"]["mode"], "tagged")
        self.assertEqual(p["interfaces"]["sw1"]["ether5"]["lag"], "bond1")
        self.assertEqual(p["cables"], [["rtr1", "ether1", "sw1", "uplink"]])
        self.assertEqual(p["vlans"], {"10": "MGMT"})
        self.assertEqual(sorted(a["addr"] for a in p["ips"]), ["10.0.0.2/30", "192.168.10.1/24", "192.168.10.251/24"])
        self.assertEqual(p["tunnels"], {"wg-site-b": ["rtr1"]})
        self.assertIn(("ipam/vlans", {"site_id": 5}), f.calls)

    def test_plan_vlan_gruppe_und_ohne_vpn(self):
        f = FakeNB(self.daten(), vpn=False)
        p = nb.plan_from_netbox(f, "s1", vlan_group="g1")
        self.assertIn(("ipam/vlans", {"group": "g1"}), f.calls)
        self.assertIsNone(p["tunnels"])

    def test_site_fehlt(self):
        with self.assertRaises(RuntimeError):
            nb.plan_from_netbox(FakeNB({}), "s1")

    def test_token_art(self):
        seen = {}

        class R:
            def __init__(self, req):
                seen["auth"] = req.get_header("Authorization")

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

            def read(self):
                return b'{"results": [], "next": null}'
        orig = nb.urllib.request.urlopen
        nb.urllib.request.urlopen = lambda req, timeout=0: R(req)
        try:
            nb.NetBox("http://x", "nbt_abc.def").get("dcim/sites")
            self.assertEqual(seen["auth"], "Bearer nbt_abc.def")
            nb.NetBox("http://x", "0123abcd").get("dcim/sites")
            self.assertEqual(seen["auth"], "Token 0123abcd")
            nb.urllib.request.urlopen = lambda req, timeout=0, context=None: (seen.update(ctx=context), R(req))[1]
            nb.NetBox("https://x", "t", unsicher=True).get("dcim/sites")
            self.assertEqual(seen["ctx"].verify_mode, nb.ssl.CERT_NONE)
        finally:
            nb.urllib.request.urlopen = orig


class AbgleichTest(unittest.TestCase):
    def run_(self, plan=None, soll=None, ist=None, alle=False):
        return nb.abgleich(plan or plan_basis(), soll or soll_basis(), ist if ist is not None else ist_basis(), alle)

    def test_alles_gleich(self):
        items = self.run_()
        self.assertEqual([x for x in items if x["art"] == "abweichung"], [], items)

    def test_geraete(self):
        p = plan_basis()
        p["devices"]["sw9"] = dict(p["devices"]["sw1"])
        p["devices"]["sw1"]["serial"] = "XXX"
        p["devices"]["sw1"]["role"] = "switch,manager"
        p["devices"]["rtr1"]["model"] = "hAP ax3"
        p["devices"]["rtr1"]["ip"] = "192.168.10.250"
        items = self.run_(p)
        self.assertTrue(finde(items, "Geräte", "sw9", "abweichung", "nicht im cfm-Inventar"))
        self.assertTrue(finde(items, "Geräte", "sw1", "abweichung", "Seriennummer NetBox XXX, Gerät BBB222"))
        self.assertTrue(finde(items, "Geräte", "sw1", "abweichung", "Rolle"))
        self.assertTrue(finde(items, "Geräte", "rtr1", "hinweis", "Modell NetBox hAP ax3"))
        self.assertTrue(finde(items, "Geräte", "rtr1", "abweichung", "MGMT-IP NetBox 192.168.10.250"))
        # Modell CRS326-24G-2S+RM passt zu board-name CRS326-24G-2S+
        self.assertFalse(finde(items, "Geräte", "sw1", text="Modell"))

    def test_inventar_ohne_netbox(self):
        p = plan_basis()
        del p["devices"]["sw1"]
        items = self.run_(p)
        self.assertTrue(finde(items, "Geräte", "sw1", "abweichung", "nicht in NetBox"))

    def test_platzhalter_seriennummer(self):
        s = soll_basis()
        s["inv"]["sw1"]["serial"] = "SERIAL-SW1"
        ist = ist_basis()
        ist["sw1"]["status"].pop("serial")
        items = self.run_(soll=s, ist=ist)
        self.assertFalse(finde(items, "Geräte", "sw1", text="Seriennummer"))

    def test_ports(self):
        p = plan_basis()
        ifs = p["interfaces"]["sw1"]
        ifs["ether3"]["spec"] = "access:30"           # Profil weicht ab
        ifs["ether2"]["untag"] = 30                    # erbt access:20, 802.1Q sagt 30
        ifs["ether9"] = iface()                        # gibt es am Gerät nicht
        ifs["ether6"]["lag"] = None                    # Slave nicht im LAG
        del ifs["ether7"]                              # am Gerät, fehlt in NetBox
        del ifs["ether8"]
        ifs["uplink"]["mode"] = None                   # Modus nicht gepflegt
        items = self.run_(p)
        self.assertTrue(finde(items, "Ports", "sw1 ether3", "abweichung", "Profil NetBox access:30, cfm hybrid:30"))
        self.assertTrue(finde(items, "Ports", "sw1 ether2", "abweichung", "untagged 30, Profil access:20 ergibt untagged 20"))
        self.assertTrue(finde(items, "Ports", "sw1 ether9", "abweichung", "keinen solchen Port"))
        self.assertTrue(finde(items, "Ports", "sw1 ether6", "abweichung", "Slave von bond1"))
        self.assertTrue(finde(items, "Ports", "sw1 ether7", "abweichung", "fehlt in NetBox"))
        self.assertTrue(finde(items, "Ports", "sw1", "hinweis", "nicht gepflegt: uplink"))
        self.assertTrue(finde(items, "Ports", "sw1 ether8", "abweichung", "fehlt in NetBox"))

    def test_port_ohne_cfm_port(self):
        p = plan_basis()
        p["devices"]["sw1"]["port_default"] = None
        items = self.run_(p)
        self.assertTrue(finde(items, "Ports", "sw1 ether2", "abweichung", "cfm access:20, in NetBox kein cfm_port"))

    def test_port_ist_weicht_ab(self):
        ist = ist_basis()
        ist["sw1"]["export"]["bports"]["ether2"]["pvid"] = 40
        items = self.run_(ist=ist)
        self.assertTrue(finde(items, "Ports", "sw1 ether2", "hinweis", "Release noch nicht angewendet"))

    def test_port_bpdu_gesperrt(self):
        # TODO 100: der Agent meldet den von BPDU-Guard gesperrten Port; statt "Release noch nicht angewendet"
        ist = ist_basis()
        ist["sw1"]["status"]["bpdu"] = ["ether2"]
        ist["sw1"]["export"]["bports"]["ether2"]["pvid"] = 40
        items = self.run_(ist=ist)
        self.assertTrue(finde(items, "Ports", "sw1 ether2", "abweichung", "von BPDU-Guard gesperrt"))
        self.assertTrue(finde(items, "Ports", "sw1 ether2", "abweichung", "statt access:20"))
        self.assertFalse(finde(items, "Ports", "sw1 ether2", "hinweis", "Release noch nicht angewendet"))

    def test_tagged_all(self):
        p = plan_basis()
        p["vlans"]["99"] = "TEST"
        items = self.run_(p)
        self.assertTrue(finde(items, "Ports", "sw1 uplink", "abweichung", "tagged 10,20,30,99"))

    def test_kabel(self):
        p = plan_basis()
        p["cables"] = [["sw1", "uplink", "rtr1", "ether2"], ["sw1", "ether8", "pc1", "eth0"]]
        items = self.run_(p)
        self.assertTrue(finde(items, "Kabel", "sw1 uplink", "abweichung", "NetBox rtr1:ether2, Hostfile links rtr1:ether1"))
        self.assertTrue(finde(items, "Kabel", "sw1 uplink", "abweichung", "LLDP/MNDP sieht rtr1:ether1"))
        self.assertTrue(finde(items, "Kabel", "sw1 ether8", "abweichung", "hier hängt nichts"))
        self.assertTrue(finde(items, "Kabel", "rtr1 ether1", "abweichung", "LLDP/MNDP sieht sw1:uplink, in NetBox kein Kabel"))

    def test_kabel_extern_hinweis(self):
        """Pilot-Standort 2026-11-25: Fritzbox und PC (nur MAC) am Router - kein Gerät von cfm, daher Hinweis"""
        ist = ist_basis()
        ist["rtr1"]["status"]["nb"] += [["ether5", "fritz.box", "LAN:1", "m02:00:00:00:00:41", "AVM"],
                                        ["ether6", "", "", "m02:00:00:00:00:42", ""]]
        items = self.run_(ist=ist)
        self.assertTrue(finde(items, "Kabel", "rtr1 ether5", "hinweis", "fritz.box:LAN:1, in NetBox kein Kabel (Gerät außerhalb"))
        self.assertTrue(finde(items, "Kabel", "rtr1 ether6", "hinweis", "LLDP/MNDP sieht 02:00:00:00:00:42, in NetBox"))

    def test_kabel_vorschlag(self):
        s = soll_basis()
        del s["hosts"]["rtr1"]["links"]
        items = self.run_(soll=s)
        self.assertTrue(finde(items, "Kabel", "rtr1 ether1", "hinweis", 'Vorschlag: "ether1"="sw1:uplink"'))

    def test_vlans_prefixe(self):
        p = plan_basis()
        del p["vlans"]["30"]
        p["vlans"]["99"] = "X"
        p["vlans"]["20"] = "Büro"
        p["prefixes"]["192.168.30.0/24"] = 31
        del p["prefixes"]["192.168.20.0/24"]
        p["prefixes"]["10.9.0.0/16"] = None
        items = self.run_(p, alle=True)
        self.assertTrue(finde(items, "VLANs", "30", "abweichung", "fehlt in NetBox"))
        self.assertTrue(finde(items, "VLANs", "99", "abweichung", "nicht in vlans.rsc"))
        self.assertTrue(finde(items, "VLANs", "20", "hinweis", "Name NetBox Büro, cfm LAN"))
        self.assertTrue(finde(items, "Prefixe", "192.168.30.0/24", "abweichung", "VLAN NetBox 31, cfm 30"))
        self.assertTrue(finde(items, "Prefixe", "192.168.20.0/24", "abweichung", "fehlt in NetBox"))
        self.assertTrue(finde(items, "Prefixe", "10.9.0.0/16", "info", "nur in NetBox"))

    def test_wireguard_ohne_peers_kein_soll(self):
        items = self.run_()
        self.assertFalse(finde(items, text="WireGuard"))
        s = soll_basis()
        s["wg"]["peers"] = {"laptop": "192.168.250.2"}
        items = self.run_(soll=s)
        self.assertTrue(finde(items, "Prefixe", "192.168.250.0/24", "abweichung"))
        self.assertTrue(finde(items, "IP-Adressen", "192.168.250.2", "abweichung", "WireGuard Peer"))

    def test_ips(self):
        p = plan_basis()
        p["ips"] = [a for a in p["ips"] if not a["addr"].startswith("192.168.20.1/")]
        p["ips"].append({"addr": "192.168.10.99/24", "dns": "", "dev": "sw1", "if": "vlan10", "role": None})
        for a in p["ips"]:
            if a["addr"].startswith("192.168.30.20/"):
                a["dns"] = "printer.internal"
            if a["addr"].startswith("192.168.10.251/"):
                a["if"] = "ether1"
        ist = ist_basis()
        ist["sw1"]["export"]["ips"].append(("192.168.30.251/24", "vlan30"))
        items = self.run_(p, ist=ist)
        self.assertTrue(finde(items, "IP-Adressen", "192.168.20.1", "abweichung", "Gateway VLAN 20"))
        self.assertTrue(finde(items, "IP-Adressen", "192.168.30.251", "abweichung", "auf sw1 vlan30, fehlt in NetBox"))
        self.assertTrue(finde(items, "IP-Adressen", "192.168.10.99", "abweichung", "nicht auf dem Gerät"))
        self.assertTrue(finde(items, "IP-Adressen", "192.168.30.20", "hinweis", "DNS-Name in NetBox printer.internal, cfm drucker"))
        self.assertTrue(finde(items, "IP-Adressen", "192.168.10.251", "hinweis", "Interface rtr1 ether1"))
        # Adresse nur in NetBox (nicht cfm, nicht Gerät): nur mit --alle
        self.assertFalse(finde(items, "IP-Adressen", "192.168.20.50"))
        self.assertTrue(finde(self.run_(p, ist=ist, alle=True), "IP-Adressen", "192.168.20.50", "info"))

    def test_vip_auf_zwei_routern(self):
        ist = ist_basis()
        ist["rtr1"]["export"]["ips"].append(("192.168.30.1", "vrrp30"))
        items = self.run_(ist=ist)
        self.assertFalse(finde(items, "IP-Adressen", "192.168.30.1"))
        p = plan_basis()
        for a in p["ips"]:
            if a["addr"].startswith("192.168.30.1/"):
                a["role"] = None
        items = self.run_(p, ist=ist)
        self.assertTrue(finde(items, "IP-Adressen", "192.168.30.1", "hinweis", "Rolle VIP"))

    def test_mgmt_falsches_geraet(self):
        p = plan_basis()
        for a in p["ips"]:
            if a["addr"].startswith("192.168.10.21/"):
                a["dev"] = "rtr1"
        items = self.run_(p)
        self.assertTrue(finde(items, "IP-Adressen", "192.168.10.21", "abweichung", "MGMT von sw1, in NetBox rtr1"))

    def test_tunnel(self):
        s = soll_basis()
        s["wg"]["sites"] = {"b": {"endpoint": "b.example:13232", "port": "13232", "nets": "192.168.120.0/24", "domain": "", "prepared": False},
                            "c": {"endpoint": "", "port": "13233", "nets": "", "domain": "", "prepared": True}}
        p = plan_basis()
        p["tunnels"] = {"wg-site-b": ["rtr1"], "alt": ["rtr1"]}
        items = self.run_(p, s, alle=True)
        self.assertFalse(finde(items, "Tunnel", "b"))
        self.assertTrue(finde(items, "Tunnel", "c", "abweichung", "kein Tunnel in NetBox"))
        self.assertTrue(finde(items, "Tunnel", "alt", "info"))
        p["tunnels"] = None
        self.assertTrue(finde(self.run_(p, s), "Tunnel", None, "hinweis", "VPN-Modul"))

    def test_kein_ist(self):
        items = self.run_(ist={})
        self.assertTrue(finde(items, "Geräte", "sw1", "hinweis", "kein Ist"))


class MainTest(unittest.TestCase):
    def test_nur_plan(self):
        with tempfile.TemporaryDirectory() as d:
            pf, ziel = os.path.join(d, "plan.json"), os.path.join(d, "neu.json")
            with open(pf, "w") as f:
                json.dump(plan_basis(), f)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = nb.main(["--plan", pf, "--plan-speichern", ziel])
            self.assertEqual(rc, 0)
            self.assertIn("Plan gespeichert", out.getvalue())
            with open(ziel) as f:
                self.assertEqual(json.load(f), json.loads(json.dumps(plan_basis())))

    def test_main(self):
        with tempfile.TemporaryDirectory() as d:
            s = soll_basis()
            hosts = s.pop("hosts")
            st = os.path.join(d, "state")
            os.makedirs(st)
            with open(os.path.join(st, "netbox.json"), "w") as f:
                json.dump(s, f)
            for n, h in hosts.items():
                os.makedirs(os.path.join(st, n))
                with open(os.path.join(st, n, "netbox.json"), "w") as f:
                    json.dump(h, f)
            with open(os.path.join(st, "sw1", "export.rsc"), "w") as f:
                f.write(EXPORT_SW1)
            pf = os.path.join(d, "plan.json")
            with open(pf, "w") as f:
                json.dump(plan_basis(), f)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = nb.main(["--plan", pf, "--state", st])
            self.assertIn(rc, (0, 1))
            self.assertIn("NetBox-Abgleich: Site s1 <-> cfm v7", out.getvalue())
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                nb.main(["--plan", pf, "--state", st, "--json"])
            self.assertIsInstance(json.loads(out.getvalue()), list)
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                self.assertEqual(nb.main(["--plan", pf, "--state", os.path.join(d, "fehlt")]), 2)

    def test_bericht(self):
        t = nb.bericht([{"bereich": "Ports", "art": "abweichung", "objekt": "sw1 ether2", "text": "x"},
                        {"bereich": "Geräte", "art": "hinweis", "objekt": "sw1", "text": "y"}], "Kopf")
        self.assertLess(t.index("Geräte"), t.index("Ports"))
        self.assertIn("1 Abweichungen, 1 Hinweise", t)
        self.assertIn("Keine Abweichungen.", nb.bericht([], "Kopf"))


if __name__ == "__main__":
    unittest.main()
