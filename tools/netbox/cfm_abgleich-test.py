#!/usr/bin/env python3
"""Tests für tools/netbox/cfm_abgleich.py (Custom Script): Die Abbildung der NetBox-Objekte (ORM) ergibt denselben Plan
wie der REST-Weg von netbox-abgleich.py. Dafür wird eine NetBox im Speicher (aus netbox-import-test.py) per Start-Import
gefüllt und einmal über REST, einmal als Objekte mit den ORM-Attributen gelesen."""
import importlib.util
import ipaddress
import os
import sys
import unittest
from types import SimpleNamespace as NS

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


sys.path.insert(0, TOOLS)
cs = _load("cfm_abgleich", os.path.join(HERE, "cfm_abgleich.py"))
it = _load("nbimporttest", os.path.join(TOOLS, "netbox-import-test.py"))
ab = it.ab


class Menge(list):
    def all(self):
        return self


def objekte(nb, rk="role"):
    """MemNB-Inhalt -> Objekte mit den Attributen der NetBox-Modelle"""
    vl = {i: NS(vid=o["vid"], name=o["name"]) for i, o in nb._all("ipam/vlans").items()}
    types = {i: NS(model=o["model"], part_number=o.get("part_number", "")) for i, o in nb._all("dcim/device-types").items()}
    roles = {i: NS(name=o["name"]) for i, o in nb._all("dcim/device-roles").items()}
    ips = {}
    devs = {}
    for i, o in nb._all("dcim/devices").items():
        d = NS(name=o["name"], serial=o.get("serial", ""), device_type=types[o["device_type"]], status=o["status"],
               custom_field_data=o.get("custom_fields") or {}, primary_ip4=None)
        setattr(d, rk, roles[o.get("role") or o.get("device_role")])
        devs[i] = d
    ifs = {}
    for i, o in nb._all("dcim/interfaces").items():
        ifs[i] = NS(pk=i, name=o["name"], device=devs[o["device"]], type=o["type"], enabled=o.get("enabled", True),
                    mode=o.get("mode") or "", untagged_vlan=vl.get(o.get("untagged_vlan")),
                    tagged_vlans=Menge(vl[x] for x in o.get("tagged_vlans") or []),
                    custom_field_data=o.get("custom_fields") or {}, cable=o.get("cable"), link_peers=[], lag=None)
    for i, o in nb._all("dcim/interfaces").items():
        if o.get("lag"):
            ifs[i].lag = ifs[o["lag"]]
    for c in nb._all("dcim/cables").values():
        a, b = c["a_terminations"][0]["object_id"], c["b_terminations"][0]["object_id"]
        ifs[a].link_peers = [ifs[b]]
        ifs[b].link_peers = [ifs[a]]
    for i, o in nb._all("ipam/ip-addresses").items():
        ips[i] = NS(pk=i, address=o["address"], dns_name=o.get("dns_name", ""), role=o.get("role") or "",
                    assigned_object=ifs.get(o.get("assigned_object_id")))
    for i, o in nb._all("dcim/devices").items():
        if o.get("primary_ip4"):
            devs[i].primary_ip4 = ips[o["primary_ip4"]]
    prefixes = [NS(prefix=o["prefix"], vlan=vl.get(o.get("vlan"))) for o in nb._all("ipam/prefixes").values()]
    # wie plan_from_orm: Adressen in den Prefixen der Site plus die an Interfaces
    sel = []
    for p in prefixes:
        net = ipaddress.ip_network(p.prefix)
        sel += [a for a in ips.values() if ipaddress.ip_address(a.address.split("/")[0]) in net]
    sel += [a for a in ips.values() if a.assigned_object is not None]
    terms = [NS(tunnel=NS(name=nb.obj("vpn/tunnels", o["tunnel"])["name"]), termination=ifs[o["termination_id"]])
             for o in nb._all("vpn/tunnel-terminations").values()]
    return list(devs.values()), list(ifs.values()), list(vl.values()), prefixes, sel, terms


class OrmTest(unittest.TestCase):
    def setUp(self):
        t = it.ImportTest("test_rundlauf")
        t.setUp()
        self.soll, self.ist, self.plan = t.soll, t.ist, t.plan
        self.t = t

    def test_orm_gleich_rest(self):
        nb = it.MemNB()
        self.t.importiere(nb)
        rest = ab.plan_from_netbox(nb, "s1")
        orm = cs.plan_aus_objekten("s1", *objekte(nb))
        for k in ("devices", "interfaces", "vlans", "prefixes", "tunnels"):
            self.assertEqual(orm[k], rest[k], k)
        self.assertEqual(sorted(map(sorted, orm["cables"])), sorted(map(sorted, rest["cables"])))
        key = lambda x: x["addr"]  # noqa: E731
        self.assertEqual(sorted(orm["ips"], key=key), sorted(rest["ips"], key=key))
        self.assertEqual([x for x in ab.abgleich(orm, self.soll, self.ist) if x["art"] == "abweichung"], [])

    def test_netbox_37_device_role_ohne_vpn(self):
        nb = it.MemNB("3.7.8")
        self.t.importiere(nb)
        d, i, v, p, a, _ = objekte(nb, rk="device_role")
        orm = cs.plan_aus_objekten("s1", d, i, v, p, a, None)
        self.assertEqual(orm["devices"]["rtr1"]["nbrole"], "Router")
        self.assertIsNone(orm["tunnels"])


if __name__ == "__main__":
    unittest.main()
