#!/usr/bin/env python3
"""netbox-import – einmaliger Start-Import cfm -> NetBox (TODO 55 Baustein 2, DT2.3).

Liest dieselben Daten wie tools/netbox-abgleich.py (Soll von $cfmNetbox, Ist aus status.dat und export.rsc) und legt
in NetBox an, was dort fehlt: Custom Fields, Site, Hersteller, Gerätetypen und -rollen, VLANs, Prefixe, Geräte,
Interfaces (mit cfm_port, 802.1Q-Modus, LAG), Kabel, IP-Adressen (samt primary IPv4) und Tunnel. Danach wird in NetBox
gepflegt und mit netbox-abgleich.py verglichen.

Vorhandenes wird nie geändert oder gelöscht, nur leere Felder werden gefüllt (Seriennummer, cfm_role,
cfm_port_default, cfm_port, 802.1Q-Modus, LAG, DNS-Name, Zuordnung einer Adresse, primary IPv4). Ein zweiter Lauf
legt nichts mehr an. Ohne --schreiben zeigt das Tool nur, was es täte (NetBox wird dabei nur gelesen).

Aufruf (aus dem Wurzelverzeichnis des Repos):
  tools/netbox-import.py --site <slug> --manager admin@192.168.10.2 --netbox https://netbox.example --token-file <f>
  tools/netbox-import.py … --schreiben                 # wirklich anlegen (Token mit Schreibrecht)
  tools/netbox-import.py --site <slug> --state <verz> --plan-speichern plan.json   # ohne NetBox: nur der Plan
Optionen wie netbox-abgleich.py: --state, --manager, --port, --base, --ver, --vlan-group, --ca, --unsicher.
Exit-Code: 0 = gelaufen, 2 = Fehler.
"""
import argparse
import importlib.util
import ipaddress
import json
import os
import re
import shutil
import sys
import tempfile
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("nbabgleich", os.path.join(HERE, "netbox-abgleich.py"))
ab = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ab)

_s = ab._s

CF = [("cfm_role", "cfm-Rollen", "dcim.device"), ("cfm_port_default", "cfm-Portprofil (Standard)", "dcim.device"),
      ("cfm_port", "cfm-Portprofil", "dcim.interface")]
ROLLEN = [("router", "Router"), ("switch", "Switch"), ("capsman", "Access Point"), ("ap", "Access Point"),
          ("cap", "Access Point"), ("manager", "Manager")]


def slug(s):
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9_]+", "-", str(s).lower())).strip("-") or "x"


def if_typ(name):
    n = name.lower()
    for pre, t in (("qsfp28", "100gbase-x-qsfp28"), ("qsfpplus", "40gbase-x-qsfpp"), ("sfp28", "25gbase-x-sfp28"),
                   ("sfp-sfpplus", "10gbase-x-sfpp"), ("sfpplus", "10gbase-x-sfpp"), ("sfp", "1000base-x-sfp"),
                   ("combo", "1000base-t"), ("ether", "1000base-t")):
        if n.startswith(pre):
            return t
    return "other"


def nb_rolle(roles):
    rs = ab._roles(roles)
    for k, name in ROLLEN:
        if k in rs:
            return name
    return "Netzwerkgerät"


# ---------------------------------------------------------------- Plan aus cfm (Format wie plan_from_netbox)

def plan_from_cfm(soll, ist, site):
    """-> Plan im Format von netbox-abgleich.plan_from_netbox, dazu "notes" (Übersprungenes) und je Adresse "desc".
    Ein Abgleich dieses Plans gegen dasselbe Soll/Ist ergibt keine Abweichung."""
    inv = soll.get("inv") or {}
    hosts = soll.get("hosts") or {}
    g = soll.get("g") or {}
    dom = _s(g.get("domain"))
    mgmt = _s(g.get("mgmtVlan"))
    plan = {"site": site, "devices": {}, "interfaces": {}, "cables": [], "vlans": {}, "prefixes": {}, "ips": [],
            "tunnels": {}, "notes": []}
    nets = []
    for vid, v in (soll.get("vlans") or {}).items():
        plan["vlans"][str(vid)] = _s(v.get("name"))
        if v.get("net"):
            n = ipaddress.ip_network(v["net"], strict=False)
            nets.append(n)
            plan["prefixes"][str(n)] = int(vid)
    wg = soll.get("wg") or {}
    wg_on = bool(wg.get("peers")) and not isinstance(wg.get("peers"), list)
    if wg_on and wg.get("net"):
        n = ipaddress.ip_network(wg["net"], strict=False)
        nets.append(n)
        plan["prefixes"][str(n)] = None

    def mit_maske(addr):
        h = ab._host(addr)
        try:
            ip = ipaddress.ip_address(h)
        except ValueError:
            return None
        for n in nets:
            if ip in n:
                return "%s/%d" % (h, n.prefixlen)
        return addr if "/" in str(addr) else "%s/32" % h

    # --- Geräte und Interfaces ---
    for n, s in sorted(inv.items()):
        st = (ist.get(n) or {}).get("status") or {}
        ex = (ist.get(n) or {}).get("export") or {}
        h = hosts.get(n) or {}
        ports = h.get("ports") or {}
        serial = _s(st.get("serial") or s.get("serial"))
        if serial.startswith("SERIAL-"):
            serial = ""
        plan["devices"][n] = {
            "serial": serial, "model": _s(st.get("model")), "part": "", "rb": _s(st.get("rb")), "nbrole": nb_rolle(s.get("role")),
            "role": ",".join(sorted(ab._roles(s.get("role")))), "port_default": _s((ports.get("*") or {}).get("spec")) or None,
            "ip": _s(s.get("ip")) or None, "status": "active"}
        eth = list(st.get("eth") or [])
        if not eth and ex:
            eth = sorted(set(ex.get("eth_set") or []) | {p for p in (ex.get("bports") or {}) if p not in (ex.get("bonds") or {})})
        ren = {v: k for k, v in (ex.get("ren") or {}).items()}
        sp = ab.soll_ports(soll, n, eth)
        slaves = h.get("slaves") or {}
        if isinstance(slaves, list):
            slaves = {}
        bonds = set(h.get("bonds") or {}) | set(slaves.values()) | set(ex.get("bonds") or {})
        ifs = {}

        def iface(name, typ, se=None, spec=None):
            e = {"type": typ, "enabled": True, "mode": None, "untag": None, "tag": [], "lag": None, "spec": spec}
            if se and "bond" in se:
                e["lag"] = se["bond"]
            r = ab._resolved(se)
            if r:
                e["enabled"] = not r["disabled"]
                if r["bridge"]:
                    e["mode"] = "tagged" if r["tag"] else "access"
                    e["untag"] = r["untag"]
                    e["tag"] = sorted(r["tag"])
            ifs[name] = e
        for b in sorted(bonds):
            pe = ports.get(b)
            iface(b, "lag", pe, _s((pe or {}).get("spec")) or None)
        for p in eth:
            if p in ifs:
                continue
            pe = ports.get(p) if p != "*" else None
            spec = _s(pe.get("spec")) or None if pe else None
            iface(p, if_typ(ren.get(p, p)), sp.get(p), spec)
        for p in sorted(set(ports) - set(ifs) - {"*"}):
            if p not in eth and eth:
                plan["notes"].append("%s %s: steht im Hostfile, das Gerät hat keinen solchen Port - nicht angelegt" % (n, p))
            elif not eth:
                pe = ports[p]
                iface(p, if_typ(p), pe, _s(pe.get("spec")) or None)
        virt = {}
        for addr, ifn in ex.get("ips") or []:
            if ifn and ifn not in ifs:
                virt[ifn] = "bridge" if ifn == "bridge" else "virtual"
        for w in ex.get("wg") or []:
            if w not in ifs:
                virt[w] = "virtual"
        if s.get("ip") and not ex and mgmt:
            virt.setdefault("vlan" + mgmt, "virtual")
        for v, t in virt.items():
            iface(v, t)
        plan["interfaces"][n] = ifs

    # --- Kabel: links im Hostfile, sonst LLDP/MNDP; nur zwischen Geräten im Inventar ---
    used, seen = {}, set()

    def kabel(a, ai, b, bi, quelle):
        if b not in inv or bi not in plan["interfaces"].get(b, {}) or ai not in plan["interfaces"].get(a, {}):
            return
        key = frozenset([(a, ai), (b, bi)])
        if key in seen:
            return
        if (a, ai) in used or (b, bi) in used:
            plan["notes"].append("Kabel %s:%s - %s:%s (%s): Port schon belegt (%s) - nicht angelegt" % (
                a, ai, b, bi, quelle, used.get((a, ai)) or used.get((b, bi))))
            return
        seen.add(key)
        used[(a, ai)] = "%s:%s" % (b, bi)
        used[(b, bi)] = "%s:%s" % (a, ai)
        plan["cables"].append([a, ai, b, bi])
    nbs = {}
    for n in inv:
        for e in ((ist.get(n) or {}).get("status") or {}).get("nb") or []:
            if len(e) >= 3:
                nbs.setdefault(n, {}).setdefault(e[0], []).append((e[1], e[2]))
    for n in sorted(inv):
        for p, l in sorted(((hosts.get(n) or {}).get("links") or {}).items()):
            l = _s(l)
            if l == "-" or not l:
                continue
            if ":" in l:
                b, bi = l.split(":", 1)
                kabel(n, p, b, bi, "links")
            else:
                cand = [x for x in nbs.get(n, {}).get(p, []) if x[0] == l and x[1]]
                if cand:
                    kabel(n, p, l, cand[0][1], "links+LLDP")
                else:
                    plan["notes"].append("%s %s: links \"%s\" ohne Gegenport (kein LLDP) - Kabel nicht angelegt" % (n, p, l))
    for n in sorted(nbs):
        links = (hosts.get(n) or {}).get("links") or {}
        for p, xs in sorted(nbs[n].items()):
            if p in links:
                continue
            for b, bi in xs:
                if b in inv and bi:
                    kabel(n, p, b, bi, "LLDP")

    # --- IP-Adressen ---
    on_dev = {}
    for n in sorted(inv):
        for addr, ifn in ((ist.get(n) or {}).get("export") or {}).get("ips") or []:
            on_dev.setdefault(ab._host(addr), []).append((n, ifn, addr))
    ips = {}

    def ip(addr, dev=None, ifn=None, role=None, dns="", desc=""):
        a = mit_maske(addr)
        if not a:
            return
        h = ab._host(a)
        e = ips.get(h)
        if e is None:
            ips[h] = {"addr": a, "dns": dns, "dev": dev, "if": ifn, "role": role, "desc": desc}
            return
        if dns and not e["dns"]:
            e["dns"] = dns
        if desc and not e["desc"]:
            e["desc"] = desc
    for h, xs in sorted(on_dev.items()):
        devs = {d for d, _, _ in xs}
        if len(devs) > 1:
            ip(xs[0][2], role="vrrp" if any(f.startswith("vrrp") for _, f, _ in xs) else "vip",
               desc="auf " + ", ".join(sorted(devs)))
        else:
            d, f, a = xs[0]
            ip(a, d, f, "vrrp" if f.startswith("vrrp") else None)
    for n, s in sorted(inv.items()):
        if s.get("ip"):
            h = _s(s["ip"])
            if h in ips:
                if not ips[h]["dns"]:
                    ips[h]["dns"] = "%s.%s" % (n, dom) if dom else n
            elif mgmt:
                ip(h, n, "vlan" + mgmt, dns="%s.%s" % (n, dom) if dom else n, desc="MGMT")
    for vid, v in sorted((soll.get("vlans") or {}).items()):
        if v.get("gw") and v.get("l3", True):
            ip(v["gw"], desc="Gateway VLAN %s" % vid)
    for l in soll.get("leases") or []:
        if l.get("ip"):
            nm = _s(l.get("name"))
            ip(l["ip"], dns="%s.%s" % (nm, dom) if dom else nm, desc="cfm-Lease %s" % _s(l.get("mac")))
    if wg_on:
        if wg.get("router"):
            ip(wg["router"], desc="WireGuard Router")
        for pn, a in sorted((wg.get("peers") or {}).items()):
            ip(a, dns=pn, desc="WireGuard Peer %s" % pn)
    plan["ips"] = [ips[h] for h in sorted(ips, key=lambda x: tuple(int(o) for o in x.split(".")) if re.match(r"^[\d.]+$", x) else (999,))]

    # --- Tunnel: Standortkopplung ---
    sites = wg.get("sites") or {}
    if isinstance(sites, list):
        sites = {}
    plan["tunnel_status"] = {}
    for sn, sd in sorted(sites.items()):
        tn = "wg-site-" + sn
        plan["tunnels"][tn] = [n for n in sorted(inv) if tn in (((ist.get(n) or {}).get("export") or {}).get("wg") or [])]
        plan["tunnel_status"][tn] = "planned" if sd.get("prepared") else "active"
    return plan


# ---------------------------------------------------------------- Schreiben

class Importer:
    def __init__(self, nb, site, schreiben=False, vlan_group=None, out=None):
        self.nb = nb
        self.site = site
        self.schreiben = schreiben
        self.vlan_group = vlan_group
        self.out = out or sys.stdout
        self.neu = 0
        self.ergaenzt = 0
        self.fake = 0
        self._typen = None
        st = nb.status()
        m = re.match(r"(\d+)\.(\d+)", str(st.get("netbox-version", "")))
        self.ver = (int(m.group(1)), int(m.group(2))) if m else (4, 0)

    def log(self, zeichen, text):
        self.out.write("  %s %s\n" % (zeichen, text))

    def one(self, path, **f):
        if any(isinstance(v, int) and v < 0 for v in f.values()):
            return None  # Probelauf: Bezug auf ein noch nicht angelegtes Objekt
        r = self.nb.get(path, **f)
        return r[0] if r else None

    def create(self, path, data, was):
        self.neu += 1
        self.log("+", was)
        if not self.schreiben:
            self.fake -= 1
            return dict(data, id=self.fake)
        return self.nb.post(path, data)

    def fill(self, path, obj, data, was):
        """leere Felder füllen; data nur mit Feldern, die in obj leer sind"""
        if not data:
            return obj
        self.ergaenzt += 1
        self.log("~", "%s: %s" % (was, ", ".join(sorted(data))))
        if not self.schreiben or obj["id"] < 0:
            return obj
        return self.nb.patch(path, obj["id"], data)

    def get_or_create(self, path, filt, data, was):
        o = self.one(path, **filt)
        return o if o else self.create(path, data, was)

    def geraetetyp(self, mf, model, rb):
        """Gerätetyp von MikroTik: gleiches Modell/gleiche Teilenummer, sonst einer, der mit board-name oder
        Routerboard-Modell beginnt (Library: "C52iG-5HaxD2HaxD-TC" für "hAP ax²"/C52iG-5HaxD2HaxD); sonst neu."""
        if self._typen is None:
            self._typen = [] if mf["id"] < 0 else self.nb.get("dcim/device-types", manufacturer_id=mf["id"])
        exakt = [t for t in self._typen if model in (t.get("model"), t.get("part_number")) or
                 (rb and rb in (t.get("model"), t.get("part_number")))]
        # rb (Routerboard-Modell) ist eindeutiger als der board-name: Treffer darüber zuerst
        cand = exakt or ([t for t in self._typen if rb and ab.modell_passt(t.get("model"), t.get("part_number"), None, rb)]
                         or [t for t in self._typen if ab.modell_passt(t.get("model"), t.get("part_number"), model, rb)])
        if cand:
            cand.sort(key=lambda t: (len(t.get("model") or ""), t.get("model") or ""))
            if len(cand) > 1:
                self.log("!", "Gerätetyp für %s: mehrere passen (%s), nehme %s" % (
                    model, ", ".join(t["model"] for t in cand), cand[0]["model"]))
            return cand[0]
        data = {"manufacturer": mf["id"], "model": model, "slug": slug("mikrotik-" + model)}
        if rb and rb != model:
            data["part_number"] = rb
        t = self.create("dcim/device-types", data, "Gerätetyp %s%s (nicht in NetBox, ohne Interface-Vorlagen)" % (
            model, " / " + rb if rb and rb != model else ""))
        self._typen.append(t)
        return t

    def run(self, plan):
        v4 = self.ver >= (4, 0)
        # Custom Fields
        for name, label, ot in CF:
            self.get_or_create("extras/custom-fields", {"name": name},
                               {"name": name, "label": label, "type": "text",
                                ("object_types" if v4 else "content_types"): [ot]}, "Custom Field %s" % name)
        site = self.get_or_create("dcim/sites", {"slug": self.site},
                                  {"name": self.site, "slug": self.site, "status": "active"}, "Site %s" % self.site)
        sid = site["id"]
        mf = self.get_or_create("dcim/manufacturers", {"slug": "mikrotik"}, {"name": "MikroTik", "slug": "mikrotik"},
                                "Hersteller MikroTik")
        roles, types = {}, {}
        # rb je Modell von irgendeinem Gerät: Ein Gerät ohne rb (offline, alter Agent) bekommt denselben Typ
        rbm = {}
        for d in plan["devices"].values():
            if d.get("rb"):
                rbm.setdefault(d["model"] or "RouterOS", d["rb"])
        for d in plan["devices"].values():
            r = d["nbrole"]
            if r not in roles:
                roles[r] = self.get_or_create("dcim/device-roles", {"slug": slug(r)},
                                              {"name": r, "slug": slug(r), "color": "607d8b"}, "Geräterolle %s" % r)["id"]
            m = d["model"] or "RouterOS"
            if m not in types:
                types[m] = self.geraetetyp(mf, m, d.get("rb") or rbm.get(m, ""))["id"]
        # VLANs
        vl = {}
        gid = None
        if self.vlan_group:
            g = self.one("ipam/vlan-groups", slug=self.vlan_group)
            if not g:
                raise RuntimeError("VLAN-Gruppe %s gibt es in NetBox nicht" % self.vlan_group)
            gid = g["id"]
        for vid, name in sorted(plan["vlans"].items(), key=lambda x: int(x[0])):
            f = {"vid": int(vid), "group_id": gid} if gid else {"vid": int(vid), "site_id": sid}
            data = {"vid": int(vid), "name": name or "VLAN %s" % vid, "status": "active"}
            data.update({"group": gid} if gid else {"site": sid})
            vl[int(vid)] = self.get_or_create("ipam/vlans", f, data, "VLAN %s %s" % (vid, name))["id"]
        # Prefixe
        for p, vid in sorted(plan["prefixes"].items()):
            if self.one("ipam/prefixes", prefix=p):
                continue
            data = {"prefix": p, "status": "active"}
            if vid is not None and vid in vl:
                data["vlan"] = vl[vid]
            else:
                data["description"] = "WireGuard"
            if self.ver >= (4, 2):
                data.update({"scope_type": "dcim.site", "scope_id": sid})
            else:
                data["site"] = sid
            self.create("ipam/prefixes", data, "Prefix %s%s" % (p, " (VLAN %s)" % vid if vid else ""))
        # Geräte
        dev = {}
        rk = "role" if v4 else "device_role"
        for n, d in sorted(plan["devices"].items()):
            o = self.one("dcim/devices", name=n, site_id=sid)
            cf = {"cfm_role": d["role"] or None, "cfm_port_default": d["port_default"]}
            if not o:
                o = self.create("dcim/devices", {"name": n, "site": sid, rk: roles[d["nbrole"]], "status": "active",
                                                 "device_type": types[d["model"] or "RouterOS"], "serial": d["serial"],
                                                 "custom_fields": {k: v for k, v in cf.items() if v}}, "Gerät %s" % n)
            else:
                ch = {}
                if d["serial"] and not o.get("serial"):
                    ch["serial"] = d["serial"]
                ocf = o.get("custom_fields") or {}
                ncf = {k: v for k, v in cf.items() if v and not ocf.get(k)}
                if ncf:
                    ch["custom_fields"] = ncf
                o = self.fill("dcim/devices", o, ch, "Gerät %s" % n)
            dev[n] = o
        # Interfaces (LAGs zuerst, die Slaves zeigen darauf)
        ifid = {}
        for n, ifs in sorted(plan["interfaces"].items()):
            did = dev[n]["id"]
            have = {} if did < 0 else {i["name"]: i for i in self.nb.get("dcim/interfaces", device_id=did)}
            for name, e in sorted(ifs.items(), key=lambda x: (x[1]["type"] != "lag", x[0])):
                data = {}
                if e["spec"]:
                    data["custom_fields"] = {"cfm_port": e["spec"]}
                if e["mode"]:
                    data["mode"] = e["mode"]
                    if e["untag"] in vl:
                        data["untagged_vlan"] = vl[e["untag"]]
                    if e["mode"] == "tagged":
                        data["tagged_vlans"] = [vl[x] for x in e["tag"] if x in vl]
                if e["lag"] and (n, e["lag"]) in ifid:
                    data["lag"] = ifid[(n, e["lag"])]
                o = have.get(name)
                if not o:
                    data.update({"device": did, "name": name, "type": e["type"], "enabled": e["enabled"]})
                    o = self.create("dcim/interfaces", data, "Interface %s %s%s" % (n, name, " (%s)" % e["spec"] if e["spec"] else ""))
                else:
                    ch = {}
                    if data.get("custom_fields") and not (o.get("custom_fields") or {}).get("cfm_port"):
                        ch["custom_fields"] = data["custom_fields"]
                    if data.get("mode") and not ab._v(o.get("mode")):
                        ch.update({k: data[k] for k in ("mode", "untagged_vlan", "tagged_vlans") if k in data})
                    if data.get("lag") and not o.get("lag"):
                        ch["lag"] = data["lag"]
                    o = self.fill("dcim/interfaces", o, ch, "Interface %s %s" % (n, name))
                ifid[(n, name)] = o["id"]
                ifid[(n, name, "cable")] = o.get("cable")
        # Kabel
        for a, ai, b, bi in plan["cables"]:
            ia, ib = ifid.get((a, ai)), ifid.get((b, bi))
            if ia is None or ib is None:
                continue
            if ifid.get((a, ai, "cable")) or ifid.get((b, bi, "cable")):
                self.log("=", "Kabel %s:%s - %s:%s: ein Ende hat schon ein Kabel" % (a, ai, b, bi))
                continue
            self.create("dcim/cables", {"a_terminations": [{"object_type": "dcim.interface", "object_id": ia}],
                                        "b_terminations": [{"object_type": "dcim.interface", "object_id": ib}],
                                        "status": "connected"}, "Kabel %s:%s - %s:%s" % (a, ai, b, bi))
        # IP-Adressen
        ipid = {}
        for e in plan["ips"]:
            h = ab._host(e["addr"])
            o = self.one("ipam/ip-addresses", address=h)
            iid = ifid.get((e["dev"], e["if"])) if e["dev"] else None
            if not o:
                data = {"address": e["addr"], "status": "active"}
                if e["dns"]:
                    data["dns_name"] = e["dns"]
                if e["role"]:
                    data["role"] = e["role"]
                if e.get("desc"):
                    data["description"] = e["desc"][:200]
                if iid is not None:
                    data.update({"assigned_object_type": "dcim.interface", "assigned_object_id": iid})
                o = self.create("ipam/ip-addresses", data, "IP %s%s%s" % (
                    e["addr"], " %s %s" % (e["dev"], e["if"]) if iid is not None else "", " (%s)" % e["dns"] if e["dns"] else ""))
            else:
                ch = {}
                if e["dns"] and not o.get("dns_name"):
                    ch["dns_name"] = e["dns"]
                if e["role"] and not ab._v(o.get("role")):
                    ch["role"] = e["role"]
                if iid is not None and not o.get("assigned_object_id") and not o.get("assigned_object"):
                    ch.update({"assigned_object_type": "dcim.interface", "assigned_object_id": iid})
                o = self.fill("ipam/ip-addresses", o, ch, "IP %s" % e["addr"])
            ipid[h] = (o["id"], e["dev"] if iid is not None else None)
        for n, d in sorted(plan["devices"].items()):
            x = ipid.get(d["ip"] or "")
            if x and x[1] == n and not dev[n].get("primary_ip4"):
                self.fill("dcim/devices", dev[n], {"primary_ip4": x[0]}, "Gerät %s primary IPv4 %s" % (n, d["ip"]))
        # Tunnel (ab 3.7; WireGuard als Kapselung ab 4.0)
        if plan["tunnels"] and self.ver < (3, 7):
            self.log("=", "NetBox vor 3.7 ohne VPN-Modul: Tunnel nicht angelegt")
            return
        for tn, devs in sorted(plan["tunnels"].items()):
            t = self.get_or_create("vpn/tunnels", {"name": tn}, {
                "name": tn, "status": (plan.get("tunnel_status") or {}).get(tn, "active"),
                "encapsulation": "wireguard" if v4 else "ip-ip", "description": "cfm-Standortkopplung (WireGuard)"},
                "Tunnel %s" % tn)
            have = set()
            if t["id"] > 0:
                for x in self.nb.get("vpn/tunnel-terminations", tunnel_id=t["id"]):
                    have.add(x.get("termination_id") or (x.get("termination") or {}).get("id"))
            for n in devs:
                iid = ifid.get((n, tn))
                if iid is None or iid in have:
                    continue
                self.create("vpn/tunnel-terminations", {"tunnel": t["id"], "role": "peer",
                                                        "termination_type": "dcim.interface", "termination_id": iid},
                            "Tunnel %s an %s %s" % (tn, n, tn))


def main(argv=None):
    ap = argparse.ArgumentParser(description="Start-Import cfm -> NetBox (TODO 55 Baustein 2)")
    ap.add_argument("--site", required=True, help="Slug der NetBox-Site (wird angelegt, wenn sie fehlt)")
    ap.add_argument("--netbox", help="URL der NetBox (ohne: nur den Plan bauen)")
    ap.add_argument("--token-file")
    ap.add_argument("--ca")
    ap.add_argument("--unsicher", action="store_true")
    ap.add_argument("--vlan-group")
    ap.add_argument("--schreiben", action="store_true", help="wirklich anlegen (sonst Probelauf)")
    ap.add_argument("--plan-speichern")
    ap.add_argument("--state")
    ap.add_argument("--manager")
    ap.add_argument("--port", type=int, default=22)
    ap.add_argument("--base", default="cfm")
    ap.add_argument("--ver", type=int)
    a = ap.parse_args(argv)
    tmp = None
    try:
        if a.state:
            d = a.state
        elif a.manager:
            tmp = tempfile.mkdtemp(prefix="cfm-nbi-")
            ab.fetch_state(a.manager, a.port, a.base, a.ver, tmp)
            d = tmp
        else:
            ap.error("--state oder --manager angeben")
        soll, ist = ab.load_state(d)
        plan = plan_from_cfm(soll, ist, a.site)
        if a.plan_speichern:
            with open(a.plan_speichern, "w", encoding="utf-8") as f:
                json.dump(plan, f, indent=1, ensure_ascii=False, sort_keys=True)
        print("Plan aus cfm %s: %d Geräte, %d Interfaces, %d Kabel, %d VLANs, %d Prefixe, %d Adressen, %d Tunnel" % (
            "v%s" % _s(soll.get("v")) if soll.get("v") else "work/", len(plan["devices"]),
            sum(len(x) for x in plan["interfaces"].values()), len(plan["cables"]), len(plan["vlans"]),
            len(plan["prefixes"]), len(plan["ips"]), len(plan["tunnels"])))
        for x in plan["notes"]:
            print("  ! " + x)
        for n in sorted(soll.get("inv") or {}):
            if n not in ist:
                print("  ! %s: kein Ist vom Gerät - Modell, Ports und Kabel fehlen, nur MGMT-Adresse" % n)
        if not a.netbox:
            return 0
        tok = os.environ.get("NETBOX_TOKEN", "")
        if a.token_file:
            with open(a.token_file, encoding="utf-8") as f:
                tok = f.read().strip()
        if not tok:
            ap.error("API-Token fehlt (--token-file oder NETBOX_TOKEN)")
        imp = Importer(ab.NetBox(a.netbox, tok, a.ca, a.unsicher), a.site, a.schreiben, a.vlan_group)
        print("NetBox %d.%d, Site %s - %s" % (imp.ver[0], imp.ver[1], a.site,
                                               "schreibe" if a.schreiben else "Probelauf (nichts wird angelegt)"))
        imp.run(plan)
        print("%d %s, %d %s" % (imp.neu, "angelegt" if a.schreiben else "anzulegen", imp.ergaenzt,
                                "ergänzt" if a.schreiben else "zu ergänzen"))
        if not a.schreiben and (imp.neu or imp.ergaenzt):
            print("Mit --schreiben anlegen (Token mit Schreibrecht), danach tools/netbox-abgleich.py.")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:600]
        print("FEHLER: NetBox %s %s: %s" % (e.code, e.reason, body), file=sys.stderr)
        return 2
    except (RuntimeError, OSError, ValueError) as e:
        print("FEHLER: %s" % e, file=sys.stderr)
        return 2
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
