#!/usr/bin/env python3
"""Tests für tools/netbox-import.py: Plan aus cfm, Import in eine NetBox im Speicher, Rundlauf über den Abgleich."""
import contextlib
import copy
import importlib.util
import io
import ipaddress
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, fn):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, fn))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


imp = _load("nbimport", "netbox-import.py")
ab = imp.ab
T = _load("nbabtest", "netbox-abgleich-test.py")


class MemNB:
    """NetBox im Speicher: POST/PATCH speichern flach, GET liefert verschachtelt wie die REST-API."""

    def __init__(self, version="4.6.4"):
        self.version = version
        self.db = {}
        self.nid = 0
        self.posts = []

    def status(self):
        return {"netbox-version": self.version}

    def _all(self, path):
        return self.db.setdefault(path, {})

    def obj(self, path, oid):
        return self._all(path).get(oid)

    def post(self, path, data):
        self.nid += 1
        o = copy.deepcopy(data)
        o["id"] = self.nid
        self._all(path)[self.nid] = o
        self.posts.append((path, data))
        if path == "dcim/cables":
            for side in ("a_terminations", "b_terminations"):
                for t in o[side]:
                    self.obj("dcim/interfaces", t["object_id"])["cable"] = self.nid
        return self.render(path, o)

    def patch(self, path, oid, data):
        o = self._all(path)[oid]
        for k, v in data.items():
            if k == "custom_fields":
                o.setdefault("custom_fields", {}).update(v)
            else:
                o[k] = v
        return self.render(path, o)

    # --- Darstellung wie die API ---
    def _dev_of_if(self, iid):
        i = self.obj("dcim/interfaces", iid)
        return self.obj("dcim/devices", i["device"]) if i else None

    def _ifref(self, iid):
        i = self.obj("dcim/interfaces", iid)
        return {"id": iid, "name": i["name"], "device": {"name": self.obj("dcim/devices", i["device"])["name"]}}

    def render(self, path, o):
        r = copy.deepcopy(o)
        val = lambda x: {"value": x} if x else None  # noqa: E731
        if path == "dcim/devices":
            dt = self.obj("dcim/device-types", o["device_type"])
            r["device_type"] = {"model": dt["model"], "part_number": dt.get("part_number", "")}
            rk = "role" if "role" in o else "device_role"
            r[rk] = {"name": self.obj("dcim/device-roles", o[rk])["name"]}
            r["status"] = val(o.get("status"))
            pi = o.get("primary_ip4")
            r["primary_ip4"] = {"address": self.obj("ipam/ip-addresses", pi)["address"]} if pi else None
            r.setdefault("custom_fields", {})
        elif path == "dcim/interfaces":
            r["device"] = {"name": self.obj("dcim/devices", o["device"])["name"]}
            r["type"] = val(o["type"])
            r["mode"] = val(o.get("mode"))
            uv = o.get("untagged_vlan")
            r["untagged_vlan"] = {"vid": self.obj("ipam/vlans", uv)["vid"]} if uv else None
            r["tagged_vlans"] = [{"vid": self.obj("ipam/vlans", x)["vid"]} for x in o.get("tagged_vlans") or []]
            r["lag"] = {"name": self.obj("dcim/interfaces", o["lag"])["name"]} if o.get("lag") else None
            r.setdefault("custom_fields", {})
            r.setdefault("enabled", True)
        elif path == "dcim/cables":
            for side in ("a_terminations", "b_terminations"):
                r[side] = [{"object_type": "dcim.interface", "object": self._ifref(t["object_id"])} for t in o[side]]
        elif path == "ipam/prefixes":
            r["vlan"] = {"vid": self.obj("ipam/vlans", o["vlan"])["vid"]} if o.get("vlan") else None
        elif path == "ipam/ip-addresses":
            r["role"] = val(o.get("role"))
            if o.get("assigned_object_id"):
                r["assigned_object"] = self._ifref(o["assigned_object_id"])
        elif path == "vpn/tunnel-terminations":
            r["tunnel"] = {"name": self.obj("vpn/tunnels", o["tunnel"])["name"]}
            r["termination"] = self._ifref(o["termination_id"])
        return r

    def _site_of(self, path, o):
        if path == "dcim/devices":
            return o["site"]
        if path == "dcim/interfaces":
            return self.obj("dcim/devices", o["device"])["site"]
        if path == "dcim/cables":
            return self._dev_of_if(o["a_terminations"][0]["object_id"])["site"]
        if path == "ipam/prefixes":
            return o.get("scope_id") or o.get("site")
        return o.get("site")

    def _match(self, path, o, k, v):
        vs = v if isinstance(v, list) else [v]
        if k == "site_id":
            return self._site_of(path, o) in vs
        if k == "device_id":
            if path == "dcim/interfaces":
                return o["device"] in vs
            if path == "ipam/ip-addresses":
                i = o.get("assigned_object_id")
                return bool(i) and self.obj("dcim/interfaces", i)["device"] in vs
            if path == "vpn/tunnel-terminations":
                return self.obj("dcim/interfaces", o["termination_id"])["device"] in vs
        if k == "group_id":
            return o.get("group") in vs
        if k == "tunnel_id":
            return o.get("tunnel") in vs
        if k == "address":
            return ab._host(o["address"]) in vs
        if k == "parent":
            return ipaddress.ip_address(ab._host(o["address"])) in ipaddress.ip_network(vs[0], strict=False)
        if k.endswith("_id") and k not in o:
            return o.get(k[:-3]) in vs
        return o.get(k) in vs

    def get(self, path, **f):
        out = []
        for o in self._all(path).values():
            if all(self._match(path, o, k, v) for k, v in f.items() if v is not None):
                out.append(self.render(path, o))
        return out


def stille(fn, *a, **k):
    with contextlib.redirect_stdout(io.StringIO()):
        return fn(*a, **k)


def abweichungen(plan, soll, ist):
    return [x for x in ab.abgleich(plan, soll, ist) if x["art"] == "abweichung"]


class PlanTest(unittest.TestCase):
    def test_plan_rundlauf_ohne_netbox(self):
        """Der Plan aus cfm, als NetBox-Plan abgeglichen, ergibt keine Abweichung."""
        soll, ist = T.soll_basis(), T.ist_basis()
        plan = imp.plan_from_cfm(soll, ist, "s1")
        self.assertEqual(abweichungen(plan, soll, ist), [])

    def test_plan_inhalt(self):
        plan = imp.plan_from_cfm(T.soll_basis(), T.ist_basis(), "s1")
        sw = plan["interfaces"]["sw1"]
        self.assertEqual(sw["bond1"]["type"], "lag")
        self.assertEqual(sw["ether5"]["lag"], "bond1")
        self.assertEqual(sw["uplink"]["type"], "1000base-x-sfp")  # umbenannt aus sfp1
        self.assertEqual((sw["ether3"]["mode"], sw["ether3"]["untag"], sw["ether3"]["tag"], sw["ether3"]["spec"]),
                         ("tagged", 30, [20], "hybrid:30"))
        self.assertEqual((sw["ether2"]["mode"], sw["ether2"]["untag"], sw["ether2"]["spec"]), ("access", 20, None))
        self.assertTrue(sw["ether7"]["enabled"])  # im Soll aktiv (access:20); abgeschaltet ist er nur am Gerät
        self.assertEqual(plan["devices"]["sw1"]["port_default"], "access:20")
        self.assertEqual(plan["cables"], [["rtr1", "ether1", "sw1", "uplink"]])
        ips = {ab._host(x["addr"]): x for x in plan["ips"]}
        self.assertEqual(ips["192.168.30.20"]["dns"], "drucker.internal")
        self.assertEqual(ips["192.168.30.20"]["addr"], "192.168.30.20/24")
        self.assertEqual(ips["192.168.10.21"]["dev"], "sw1")
        self.assertEqual(ips["192.168.30.1"]["role"], "vrrp")

    def test_kabel_belegt(self):
        soll, ist = T.soll_basis(), T.ist_basis()
        ist["sw1"]["status"]["nb"].append(["ether2", "rtr1", "ether1", "", ""])
        plan = imp.plan_from_cfm(soll, ist, "s1")
        self.assertEqual(len(plan["cables"]), 1)
        self.assertTrue(any("schon belegt" in x for x in plan["notes"]))

    def test_geraet_ohne_ist(self):
        soll, ist = T.soll_basis(), T.ist_basis()
        del ist["rtr1"]
        plan = imp.plan_from_cfm(soll, ist, "s1")
        self.assertIn("vlan10", plan["interfaces"]["rtr1"])
        ips = {ab._host(x["addr"]): x for x in plan["ips"]}
        self.assertEqual((ips["192.168.10.251"]["dev"], ips["192.168.10.251"]["if"]), ("rtr1", "vlan10"))


class ImportTest(unittest.TestCase):
    def setUp(self):
        self.soll, self.ist = T.soll_basis(), T.ist_basis()
        self.soll["wg"] = {"net": "192.168.250.0/24", "router": "192.168.250.1", "peers": {"laptop": "192.168.250.34"},
                           "sites": {"b": {"endpoint": "b.example.org", "port": "13232", "nets": "", "domain": "",
                                           "prepared": True}}}
        self.ist["rtr1"]["export"]["wg"] = ["wg-admin", "wg-site-b"]
        self.ist["rtr1"]["export"]["ips"].append(("192.168.250.1/24", "wg-admin"))
        self.plan = imp.plan_from_cfm(self.soll, self.ist, "s1")

    def importiere(self, nb, schreiben=True, **kw):
        out = io.StringIO()
        i = imp.Importer(nb, "s1", schreiben, out=out, **kw)
        i.run(self.plan)
        return i, out.getvalue()

    def test_rundlauf(self):
        """Import in eine leere NetBox, dann Abgleich über die REST-Abbildung: keine Abweichung."""
        nb = MemNB()
        i, _ = self.importiere(nb)
        self.assertGreater(i.neu, 30)
        plan = ab.plan_from_netbox(nb, "s1")
        self.assertEqual(abweichungen(plan, self.soll, self.ist), [])
        self.assertEqual(plan["tunnels"], {"wg-site-b": ["rtr1"]})
        self.assertEqual(plan["devices"]["sw1"]["ip"], "192.168.10.21")
        self.assertEqual(plan["interfaces"]["sw1"]["ether3"]["spec"], "hybrid:30")
        t = list(nb._all("vpn/tunnels").values())[0]
        self.assertEqual((t["status"], t["encapsulation"]), ("planned", "wireguard"))

    def test_zweiter_lauf_legt_nichts_an(self):
        nb = MemNB()
        self.importiere(nb)
        n = len(nb.posts)
        i, _ = self.importiere(nb)
        self.assertEqual((i.neu, i.ergaenzt), (0, 0))
        self.assertEqual(len(nb.posts), n)

    def test_vorhandener_prefix_bekommt_vlan(self):
        """Pilot-Standort 2026-11-25: Prefix von Hand angelegt, ohne VLAN -> VLAN ergänzen, nicht doppelt anlegen"""
        nb = MemNB()
        p, vid = next((p, v) for p, v in sorted(self.plan["prefixes"].items()) if v is not None)
        o = nb.post("ipam/prefixes", {"prefix": p, "status": "active"})
        i, out = self.importiere(nb)
        self.assertIn("~ Prefix %s (VLAN %s): vlan" % (p, vid), out)
        self.assertTrue(nb.obj("ipam/prefixes", o["id"]).get("vlan"))
        self.assertEqual(len([x for x in nb._all("ipam/prefixes").values() if x["prefix"] == p]), 1)

    def test_probelauf_schreibt_nicht(self):
        nb = MemNB()
        i, out = self.importiere(nb, schreiben=False)
        self.assertEqual(nb.posts, [])
        self.assertGreater(i.neu, 30)
        self.assertIn("+ Gerät sw1", out)
        self.assertIn("+ Kabel rtr1:ether1 - sw1:uplink", out)

    def test_vorhandenes_bleibt_leeres_wird_gefuellt(self):
        nb = MemNB()
        site = nb.post("dcim/sites", {"name": "S1", "slug": "s1"})
        mf = nb.post("dcim/manufacturers", {"name": "MikroTik", "slug": "mikrotik"})
        dt = nb.post("dcim/device-types", {"manufacturer": mf["id"], "model": "CRS326-24G-2S+", "slug": "crs"})
        ro = nb.post("dcim/device-roles", {"name": "Core", "slug": "core"})
        d = nb.post("dcim/devices", {"name": "sw1", "site": site["id"], "role": ro["id"], "device_type": dt["id"],
                                     "serial": "", "custom_fields": {"cfm_role": "switch,manager"}})
        e2 = nb.post("dcim/interfaces", {"device": d["id"], "name": "ether2", "type": "1000base-t",
                                         "custom_fields": {"cfm_port": "access:30"}})
        i, out = self.importiere(nb)
        o = nb.obj("dcim/devices", d["id"])
        self.assertEqual(o["serial"], "BBB222")                       # leer -> gefüllt
        self.assertEqual(o["custom_fields"]["cfm_role"], "switch,manager")  # vorhanden -> bleibt
        self.assertEqual(o["custom_fields"]["cfm_port_default"], "access:20")
        self.assertEqual(o["role"], ro["id"])
        self.assertEqual(nb.obj("dcim/interfaces", e2["id"])["custom_fields"]["cfm_port"], "access:30")
        self.assertEqual(nb.obj("dcim/interfaces", e2["id"])["mode"], "access")  # Modus war leer
        self.assertIn("~ Gerät sw1: custom_fields, serial", out)
        self.assertEqual(len([x for x in nb._all("dcim/devices").values() if x["name"] == "sw1"]), 1)

    def test_geraetetyp_aus_library(self):
        """hAP ax² meldet board-name "hAP ax²", die Library heißt C52iG-5HaxD2HaxD-TC: Treffer über rb"""
        self.ist["rtr1"]["status"].update({"model": "hAP ax²", "rb": "C52iG-5HaxD2HaxD"})
        self.ist["sw1"]["status"]["model"] = "CRS326-24G-2S+"
        self.plan = imp.plan_from_cfm(self.soll, self.ist, "s1")
        nb = MemNB()
        mf = nb.post("dcim/manufacturers", {"name": "MikroTik", "slug": "mikrotik"})
        hap = nb.post("dcim/device-types", {"manufacturer": mf["id"], "model": "C52iG-5HaxD2HaxD-TC", "slug": "a"})
        nb.post("dcim/device-types", {"manufacturer": mf["id"], "model": "CRS326-24G-2S+RM", "slug": "b"})
        din = nb.post("dcim/device-types", {"manufacturer": mf["id"], "model": "CRS326-24G-2S+IN", "slug": "c"})
        i, out = self.importiere(nb)
        devs = {d["name"]: d for d in nb._all("dcim/devices").values()}
        self.assertEqual(devs["rtr1"]["device_type"], hap["id"])
        self.assertEqual(devs["sw1"]["device_type"], din["id"])  # mehrere passen: kürzester, dann alphabetisch
        self.assertIn("mehrere passen", out)
        self.assertNotIn("+ Gerätetyp", out)
        plan = ab.plan_from_netbox(nb, "s1")
        self.assertFalse([x for x in ab.abgleich(plan, self.soll, self.ist) if "Modell" in x["text"]])

    def test_geraetetyp_ohne_rb_vom_gleichen_modell(self):
        """Gerät ohne rb (offline, alter Agent) bekommt den Typ eines Geräts gleichen Modells mit rb"""
        self.ist["rtr1"]["status"].update({"model": "hAP ax²"})
        self.ist["rtr1"]["status"].pop("rb", None)
        self.ist["sw1"]["status"].update({"model": "hAP ax²", "rb": "C52iG-5HaxD2HaxD"})
        self.plan = imp.plan_from_cfm(self.soll, self.ist, "s1")
        nb = MemNB()
        mf = nb.post("dcim/manufacturers", {"name": "MikroTik", "slug": "mikrotik"})
        hap = nb.post("dcim/device-types", {"manufacturer": mf["id"], "model": "C52iG-5HaxD2HaxD-TC", "slug": "a"})
        i, out = self.importiere(nb)
        devs = {d["name"]: d for d in nb._all("dcim/devices").values()}
        self.assertEqual(devs["rtr1"]["device_type"], hap["id"])
        self.assertEqual(devs["sw1"]["device_type"], hap["id"])
        self.assertNotIn("+ Gerätetyp", out)

    def test_geraetetyp_hap_ax2_nicht_ax3(self):
        """Pilot-Standort 2026-11-25: board-name "hAP ax^2", in NetBox gibt es "hAP ax³" (anderer Standort) und den Library-Typ"""
        self.ist["rtr1"]["status"].update({"model": "hAP ax^2", "rb": "C52iG-5HaxD2HaxD"})
        self.ist["sw1"]["status"].update({"model": "hAP ax^2"})
        self.ist["sw1"]["status"].pop("rb", None)
        self.plan = imp.plan_from_cfm(self.soll, self.ist, "s1")
        nb = MemNB()
        mf = nb.post("dcim/manufacturers", {"name": "MikroTik", "slug": "mikrotik"})
        nb.post("dcim/device-types", {"manufacturer": mf["id"], "model": "hAP ax³", "slug": "x"})
        hap = nb.post("dcim/device-types", {"manufacturer": mf["id"], "model": "C52iG-5HaxD2HaxD-TC", "slug": "a"})
        i, out = self.importiere(nb)
        devs = {d["name"]: d for d in nb._all("dcim/devices").values()}
        self.assertEqual(devs["rtr1"]["device_type"], hap["id"])
        self.assertEqual(devs["sw1"]["device_type"], hap["id"])
        self.assertNotIn("mehrere passen", out)
        self.assertFalse(ab.modell_passt("hAP ax³", "", "hAP ax^2"))
        self.assertTrue(ab.modell_passt("hAP ax²", "", "hAP ax^2"))

    def test_geraetetyp_neu_mit_teilenummer(self):
        self.ist["rtr1"]["status"].update({"model": "hAP ax²", "rb": "C52iG-5HaxD2HaxD"})
        self.plan = imp.plan_from_cfm(self.soll, self.ist, "s1")
        nb = MemNB()
        self.importiere(nb)
        t = [x for x in nb._all("dcim/device-types").values() if x["model"] == "hAP ax²"][0]
        self.assertEqual(t["part_number"], "C52iG-5HaxD2HaxD")
        # Interface-Vorlagen aus den physischen Ports von rtr1 (ohne VLAN/WireGuard/Bridge)
        vl = [x for x in nb._all("dcim/interface-templates").values() if x["device_type"] == t["id"]]
        phys = [p for p, e in self.plan["interfaces"]["rtr1"].items() if e["type"] not in ("lag", "bridge", "virtual")]
        self.assertEqual(sorted(x["name"] for x in vl), sorted(phys))
        self.assertTrue(phys)

    def test_typ_yaml(self):
        self.ist["rtr1"]["status"].update({"model": "hAP be³ Media", "rb": "MA53UG+HbeH"})
        self.plan = imp.plan_from_cfm(self.soll, self.ist, "s1")
        i, out = self.importiere(MemNB(), schreiben=False)
        t = [x for x in i.neue_typen if x["model"] == "hAP be³ Media"][0]
        y = imp.typ_yaml(t)
        self.assertIn("model: hAP be³ Media\n", y)
        self.assertIn("part_number: MA53UG+HbeH\n", y)
        self.assertIn("  - name: ether1\n    type: 1000base-t\n", y)
        self.assertNotIn("vlan", y.split("interfaces:")[1].split("# power-ports")[0])
        self.assertEqual(imp._yq("a: b"), "'a: b'")
        self.assertEqual(imp.slug("mikrotik-hAP be³ Media"), "mikrotik-hap-be3-media")
        self.assertEqual(imp.slug("mikrotik-C53UiG+5HPaxD2HPaxD"), "mikrotik-c53uig-plus-5hpaxd2hpaxd")

    def test_netbox_37(self):
        nb = MemNB("3.7.8")
        self.importiere(nb)
        d = list(nb._all("dcim/devices").values())[0]
        self.assertIn("device_role", d)
        cf = list(nb._all("extras/custom-fields").values())[0]
        self.assertIn("content_types", cf)
        p = list(nb._all("ipam/prefixes").values())[0]
        self.assertIn("site", p)
        t = list(nb._all("vpn/tunnels").values())[0]
        self.assertEqual(t["encapsulation"], "ip-ip")

    def test_prefix_scope_ab_42(self):
        nb = MemNB("4.2.0")
        self.importiere(nb)
        p = list(nb._all("ipam/prefixes").values())[0]
        self.assertEqual(p["scope_type"], "dcim.site")

    def test_vlan_gruppe(self):
        nb = MemNB()
        g = nb.post("ipam/vlan-groups", {"name": "G", "slug": "g"})
        self.importiere(nb, vlan_group="g")
        self.assertTrue(all(v.get("group") == g["id"] for v in nb._all("ipam/vlans").values()))
        with self.assertRaises(RuntimeError):
            self.importiere(MemNB(), vlan_group="fehlt")


class MainTest(unittest.TestCase):
    def test_main_ohne_netbox(self):
        import json
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            s = T.soll_basis()
            hosts = s.pop("hosts")
            with open(os.path.join(d, "netbox.json"), "w") as f:
                json.dump(s, f)
            for n, h in hosts.items():
                os.makedirs(os.path.join(d, n))
                with open(os.path.join(d, n, "netbox.json"), "w") as f:
                    json.dump(h, f)
            with open(os.path.join(d, "sw1", "export.rsc"), "w") as f:
                f.write(T.EXPORT_SW1)
            pf = os.path.join(d, "plan.json")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = imp.main(["--site", "s1", "--state", d, "--plan-speichern", pf])
            self.assertEqual(rc, 0)
            self.assertIn("Plan aus cfm v7: 2 Geräte", out.getvalue())
            self.assertIn("rtr1: kein Ist vom Gerät", out.getvalue())
            with open(pf) as f:
                self.assertIn("sw1", json.load(f)["devices"])


if __name__ == "__main__":
    unittest.main()
