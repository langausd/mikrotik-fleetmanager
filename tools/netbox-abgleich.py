#!/usr/bin/env python3
"""netbox-abgleich – vergleicht die Planung in NetBox mit cfm (Soll) und den Geräten (Ist), TODO 55.

NetBox ist der Planungsstand, cfm bleibt führend (DT2.2): Das Tool ändert weder NetBox noch die Site-Daten, es
berichtet nur. Verglichen werden Geräte (Name, Seriennummer, Modell, Rolle, MGMT-IP), Ports (vorhanden,
cfm-Profil, 802.1Q-Modus in NetBox, Bond), Kabel (NetBox ↔ "links" der Hostfiles ↔ LLDP/MNDP), VLANs,
Prefixe, IP-Adressen (MGMT, Gateways, feste Leases, WireGuard, alle Adressen auf den Geräten) und Tunnel
(Standortkopplung).

Quellen:
  Soll  state/netbox.json und state/<gerät>/netbox.json, geschrieben von $cfmNetbox auf dem Manager
  Ist   state/<gerät>/status.dat (Seriennummer, Modell, Nachbarn, Ethernet-Ports) und state/<gerät>/export.rsc
  Plan  NetBox per REST-API (ab 3.7), oder eine zuvor mit --plan-speichern abgelegte Datei

Aufruf (aus dem Wurzelverzeichnis des Repos):
  tools/netbox-abgleich.py --netbox https://netbox.example --site <slug> --manager admin@192.168.10.2
  tools/netbox-abgleich.py --netbox … --site … --state <verz>     # state/ liegt schon lokal (Kopie vom Manager)
  tools/netbox-abgleich.py --plan plan.json --state <verz>        # ohne NetBox (Tests, offline)
Optionen: --token-file <datei> (sonst $NETBOX_TOKEN), --vlan-group <slug> (VLANs einer Gruppe statt der Site),
  --ver <N> ($cfmNetbox ver=, 0 = work/; Standard: letztes Release), --port, --base (wie upload-seed.sh),
  --plan-speichern <datei>, --json (Befunde als JSON), --alle (auch Infos: z.B. Adressen nur in NetBox).
Exit-Code: 0 = keine Abweichung, 1 = Abweichungen, 2 = Fehler.

NetBox-Felder (Custom Fields, Admin-Guide 8.x):
  Gerät      cfm_role (Text, z.B. "switch,manager"), cfm_port_default (Text, Profil wie portDefault)
  Interface  cfm_port (Text, Profil wie unter ports: trunk, trunk-ap, access:<vid>, hybrid:<vid>, …)
Ein Interface ohne cfm_port erbt cfm_port_default des Geräts (nur Ethernet-Ports, keine Bond-Slaves).
"""
import argparse
import ipaddress
import json
import os
import re
import shutil
import ssl
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

PHYS_SKIP = ("virtual", "bridge", "lag")


# ---------------------------------------------------------------- Ist: Export (terse)

def _tokens(line):
    """Zerlegt eine Export-Zeile in Wörter; "…" mit Escapes, [ … ] als ein Wort."""
    out, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        if c.isspace():
            i += 1
            continue
        if c == "[":
            j = line.find("]", i)
            j = n if j < 0 else j + 1
            out.append(line[i:j])
            i = j
            continue
        buf = []
        while i < n and not line[i].isspace():
            if line[i] == '"':
                i += 1
                while i < n and line[i] != '"':
                    if line[i] == "\\" and i + 1 < n:
                        i += 1
                    buf.append(line[i])
                    i += 1
                i += 1
            else:
                buf.append(line[i])
                i += 1
        out.append("".join(buf))
    return out


def _lines(text):
    """Export-Zeilen, Fortsetzungen (\\ am Zeilenende) zusammengefügt."""
    cur = ""
    for raw in text.replace("\r", "").split("\n"):
        if raw.endswith("\\"):
            cur += raw[:-1]
            continue
        cur += raw
        if cur.strip():
            yield cur.strip()
        cur = ""


def _kv(words):
    d = {}
    for w in words:
        if "=" in w and not w.startswith("["):
            k, v = w.split("=", 1)
            d[k] = v
    return d


def _s(x):
    """Wert aus RouterOS-JSON als Text: :serialize macht aus "10" die Zahl 10.000000 (ROUTEROS-EIGENHEITEN)"""
    if isinstance(x, bool):
        return "yes" if x else "no"
    if isinstance(x, float) and x.is_integer():
        return str(int(x))
    return "" if x is None else str(x)


def _vids(s):
    r = set()
    for p in _s(s).split(","):
        p = p.strip()
        if not p:
            continue
        if "-" in p:
            a, b = p.split("-", 1)
            r.update(range(int(a), int(b) + 1))
        elif p.isdigit():
            r.add(int(p))
    return r


def parse_export(text):
    """-> {"ren": {default-name: name}, "eth_set": [...], "bports": {if: {...}}, "bvlans": [...],
    "ips": [(adresse, interface)], "bonds": {name: [slaves]}, "vlans": {name: vid}, "wg": [namen]}"""
    r = {"ren": {}, "eth_set": [], "eth_off": set(), "bports": {}, "bvlans": [], "ips": [], "bonds": {},
         "vlans": {}, "wg": []}
    for line in _lines(text):
        if line.startswith("#") or not line.startswith("/"):
            continue
        w = _tokens(line)
        if len(w) < 2:
            continue
        menu = []
        k = 0
        while k < len(w) and "=" not in w[k] and not w[k].startswith("[") and w[k] not in ("add", "set"):
            menu.append(w[k])
            k += 1
        path = " ".join(menu)
        verb = w[k] if k < len(w) else ""
        kv = _kv(w[k + 1:])
        find = next((x for x in w if x.startswith("[")), "")
        if path == "/interface ethernet" and verb == "set":
            m = re.search(r"default-name=(\S+)", find)
            if m:
                dn = m.group(1)
                nm = kv.get("name", dn)
                if nm != dn:
                    r["ren"][dn] = nm
                r["eth_set"].append(nm)
                if kv.get("disabled") == "yes":
                    r["eth_off"].add(nm)
        elif path == "/interface bridge port" and verb == "add":
            r["bports"][kv.get("interface", "")] = {
                "pvid": int(kv.get("pvid", "1")), "frames": kv.get("frame-types", "admit-all"),
                "disabled": kv.get("disabled") == "yes"}
        elif path == "/interface bridge vlan" and verb == "add":
            r["bvlans"].append({"vids": _vids(kv.get("vlan-ids")),
                                "tagged": [x for x in kv.get("tagged", "").split(",") if x],
                                "untagged": [x for x in kv.get("untagged", "").split(",") if x]})
        elif path == "/ip address" and verb == "add":
            if kv.get("address"):
                r["ips"].append((kv["address"], kv.get("interface", "")))
        elif path == "/interface bonding" and verb == "add":
            r["bonds"][kv.get("name", "")] = [x for x in kv.get("slaves", "").split(",") if x]
        elif path == "/interface vlan" and verb == "add":
            r["vlans"][kv.get("name", "")] = int(kv.get("vlan-id", "0") or 0)
        elif path == "/interface wireguard" and verb == "add":
            r["wg"].append(kv.get("name", ""))
    return r


def ist_ports(ex):
    """Ports in der Bridge laut Export -> {port: {"untag": vid|None, "tag": set, "disabled": bool}}"""
    out = {}
    for p, bp in ex["bports"].items():
        untag = None if bp["frames"] == "admit-only-vlan-tagged" else bp["pvid"]
        out[p] = {"untag": untag, "tag": set(), "disabled": bp["disabled"] or p in ex["eth_off"]}
    for bv in ex["bvlans"]:
        for p in bv["tagged"]:
            if p in out:
                out[p]["tag"] |= bv["vids"]
        for p in bv["untagged"]:
            if p in out and out[p]["untag"] is None:
                out[p]["untag"] = min(bv["vids"]) if bv["vids"] else None
    for p in out.values():
        if p["untag"] is not None:
            p["tag"].discard(p["untag"])
    return out


# ---------------------------------------------------------------- Soll und Ist aus state/

def _readjson(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def load_state(d):
    """-> (soll, ist). soll = state/netbox.json mit "hosts" aus state/<n>/netbox.json; ist = {n: {status, export}}"""
    soll = _readjson(os.path.join(d, "netbox.json"))
    if not soll:
        raise RuntimeError("%s/netbox.json fehlt oder ist kein JSON - $cfmNetbox auf dem Manager gelaufen?" % d)
    soll["hosts"] = {}
    ist = {}
    for n in soll.get("inv", {}):
        h = _readjson(os.path.join(d, n, "netbox.json"))
        if h is not None:
            soll["hosts"][n] = h
        st = _readjson(os.path.join(d, n, "status.dat"))
        ex = None
        try:
            with open(os.path.join(d, n, "export.rsc"), encoding="utf-8", errors="replace") as f:
                ex = parse_export(f.read())
        except OSError:
            pass
        if st is not None or ex is not None:
            ist[n] = {"status": st or {}, "export": ex}
    return soll, ist


def _sshopts(port):
    return ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "LogLevel=ERROR", "-p", str(port)]


def fetch_state(dest, port, base, ver, out):
    """$cfmNetbox auf dem Manager starten, dann state/ (nur die nötigen Dateien) per SFTP nach out holen."""
    arg = "" if ver is None else " ver=%d" % ver
    cmd = '/system script run cfm-mgr; :global cfmNetbox; :put ("CFMNB=" . [$cfmNetbox%s])' % arg
    r = subprocess.run(["ssh"] + _sshopts(port) + [dest, cmd], capture_output=True, text=True, timeout=600)
    m = re.search(r"CFMNB=(\d+)", r.stdout)
    if not m:
        raise RuntimeError("$cfmNetbox auf %s: %s" % (dest, (r.stdout + r.stderr).strip()[-400:]))
    sopt = _sshopts(port)
    sopt[sopt.index("-p")] = "-P"

    def sftp(batch):
        subprocess.run(["sftp", "-q", "-b", "-"] + sopt + [dest], input=batch, capture_output=True, text=True,
                       timeout=600)
    sftp("get %s/state/netbox.json %s/netbox.json\n" % (base, out))
    soll = _readjson(os.path.join(out, "netbox.json")) or {}
    b = []
    for n in soll.get("inv", {}):
        os.makedirs(os.path.join(out, n), exist_ok=True)
        for f in ("netbox.json", "status.dat", "export.rsc"):
            b.append("-get %s/state/%s/%s %s/%s/%s" % (base, n, f, out, n, f))
    sftp("\n".join(b) + "\n")
    return int(m.group(1))


# ---------------------------------------------------------------- Plan: NetBox REST

class NetBox:
    def __init__(self, url, token, ca=None, unsicher=False):
        self.url = url.rstrip("/")
        self.token = token
        self.ctx = None
        if unsicher:
            self.ctx = ssl._create_unverified_context()
        elif ca:
            self.ctx = ssl.create_default_context(cafile=ca)

    def get(self, path, **params):
        q = []
        for k, v in params.items():
            for x in (v if isinstance(v, (list, tuple)) else [v]):
                q.append((k, str(x)))
        q.append(("limit", "500"))
        url = self.url + "/api/" + path.strip("/") + "/?" + urllib.parse.urlencode(q)
        out = []
        while url:
            data = self.fetch(url)
            out.extend(data.get("results", []))
            url = data.get("next")
        return out

    def fetch(self, url, method="GET", data=None):
        auth = ("Bearer " if self.token.startswith("nbt_") else "Token ") + self.token
        hdr = {"Authorization": auth, "Accept": "application/json"}
        body = None
        if data is not None:
            body = json.dumps(data).encode("utf-8")
            hdr["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=body, headers=hdr, method=method)
        kw = {"context": self.ctx} if self.ctx else {}
        with urllib.request.urlopen(req, timeout=60, **kw) as r:
            return json.loads(r.read().decode("utf-8") or "{}")

    def status(self):
        return self.fetch(self.url + "/api/status/")

    # nur für tools/netbox-import.py (Start-Import); der Abgleich liest nur
    def post(self, path, data):
        return self.fetch(self.url + "/api/" + path.strip("/") + "/", "POST", data)

    def patch(self, path, oid, data):
        return self.fetch(self.url + "/api/%s/%d/" % (path.strip("/"), oid), "PATCH", data)


def _v(x, key="value"):
    return x.get(key) if isinstance(x, dict) else x


def _cf(o, k):
    v = (o.get("custom_fields") or {}).get(k)
    return v.strip() if isinstance(v, str) and v.strip() else None


def _term(t):
    """Kabel-Ende -> (gerät, interface) oder None (Front-Port, Circuit …)"""
    if t.get("object_type") != "dcim.interface":
        return None
    o = t.get("object") or {}
    return ((o.get("device") or {}).get("name"), o.get("name"))


def plan_from_netbox(nb, site, vlan_group=None):
    sites = nb.get("dcim/sites", slug=site)
    if not sites:
        raise RuntimeError("Site %s gibt es in NetBox nicht" % site)
    sid = sites[0]["id"]
    plan = {"site": site, "devices": {}, "interfaces": {}, "cables": [], "vlans": {}, "prefixes": {}, "ips": [],
            "tunnels": {}}
    ids = {}
    for d in nb.get("dcim/devices", site_id=sid):
        if not d.get("name"):
            continue
        ids[d["id"]] = d["name"]
        dt = d.get("device_type") or {}
        role = d.get("role") or d.get("device_role") or {}
        pip = (d.get("primary_ip4") or {}).get("address")
        plan["devices"][d["name"]] = {
            "serial": d.get("serial") or "", "model": dt.get("model") or "", "part": dt.get("part_number") or "",
            "nbrole": role.get("name") or "", "role": _cf(d, "cfm_role"), "port_default": _cf(d, "cfm_port_default"),
            "ip": pip.split("/")[0] if pip else None, "status": _v(d.get("status"))}
        plan["interfaces"][d["name"]] = {}
    for i in nb.get("dcim/interfaces", site_id=sid):
        dn = (i.get("device") or {}).get("name")
        if dn not in plan["interfaces"]:
            continue
        plan["interfaces"][dn][i["name"]] = {
            "type": _v(i.get("type")) or "", "enabled": i.get("enabled", True), "mode": _v(i.get("mode")),
            "untag": (i.get("untagged_vlan") or {}).get("vid"),
            "tag": sorted(v["vid"] for v in (i.get("tagged_vlans") or []) if v.get("vid") is not None),
            "lag": (i.get("lag") or {}).get("name"), "spec": _cf(i, "cfm_port")}
    for c in nb.get("dcim/cables", site_id=sid):
        a = [_term(t) for t in c.get("a_terminations") or []]
        b = [_term(t) for t in c.get("b_terminations") or []]
        a = [x for x in a if x]
        b = [x for x in b if x]
        if len(a) == 1 and len(b) == 1:
            plan["cables"].append([a[0][0], a[0][1], b[0][0], b[0][1]])
    vl = nb.get("ipam/vlans", group=vlan_group) if vlan_group else nb.get("ipam/vlans", site_id=sid)
    for v in vl:
        plan["vlans"][str(v["vid"])] = v.get("name") or ""
    seen = set()

    def addip(a):
        if a["id"] in seen:
            return
        seen.add(a["id"])
        ao = a.get("assigned_object") or {}
        dev = (ao.get("device") or {}).get("name") if a.get("assigned_object_type") == "dcim.interface" else None
        plan["ips"].append({"addr": a["address"], "dns": a.get("dns_name") or "", "dev": dev,
                            "if": ao.get("name") if dev else None, "role": _v(a.get("role"))})
    for p in nb.get("ipam/prefixes", site_id=sid):
        plan["prefixes"][p["prefix"]] = (p.get("vlan") or {}).get("vid")
        for a in nb.get("ipam/ip-addresses", parent=p["prefix"]):
            addip(a)
    if ids:
        for a in nb.get("ipam/ip-addresses", device_id=list(ids)):
            addip(a)
        try:
            for t in nb.get("vpn/tunnel-terminations", device_id=list(ids)):
                tn = (t.get("tunnel") or {}).get("name")
                term = t.get("termination") or {}
                dev = (term.get("device") or {}).get("name")
                if tn:
                    plan["tunnels"].setdefault(tn, [])
                    if dev and dev not in plan["tunnels"][tn]:
                        plan["tunnels"][tn].append(dev)
        except Exception:  # NetBox < 3.7: kein VPN-Modul
            plan["tunnels"] = None
    return plan


# ---------------------------------------------------------------- Abgleich

class Befunde:
    def __init__(self):
        self.items = []

    def add(self, bereich, art, obj, text):
        self.items.append({"bereich": bereich, "art": art, "objekt": obj, "text": text})

    def abw(self, bereich, obj, text):
        self.add(bereich, "abweichung", obj, text)

    def hinweis(self, bereich, obj, text):
        self.add(bereich, "hinweis", obj, text)

    def info(self, bereich, obj, text):
        self.add(bereich, "info", obj, text)


def _norm(s):
    return re.sub(r"[^a-z0-9]", "", str(s or "").lower())


def modell_passt(model, part, board, rb=None):
    """NetBox-Gerätetyp (Modell, Teilenummer) passt zum Gerät: board-name (z.B. "hAP ax²", "CRS326-24G-2S+") oder
    Routerboard-Modell (z.B. "C52iG-5HaxD2HaxD"); die Library hängt oft noch etwas an (RM, IN, TC)."""
    have = [_norm(x) for x in (model, part) if x]
    want = [_norm(x) for x in (board, rb) if x]
    return any(h and w and (h == w or (len(w) >= 4 and h.startswith(w)) or (len(h) >= 4 and w.startswith(h)))
               for h in have for w in want)


def _roles(s):
    return set(x.strip() for x in str(s or "").split(",") if x.strip() and x.strip() != "base")


def _host(addr):
    return str(addr).split("/")[0]


def soll_ports(soll, name, eth):
    """Soll je Port: {port: {"spec","untag","tag","bridge","disabled"} | {"bond": name}}; eth = Ethernet-Ports"""
    h = (soll.get("hosts") or {}).get(name) or {}
    ports = h.get("ports") or {}
    slaves = h.get("slaves") or {}
    out = {}
    for p, e in ports.items():
        if p != "*":
            out[p] = e
    if isinstance(slaves, list):  # leeres Array serialisiert RouterOS als []
        slaves = {}
    for p in eth:
        if p in slaves:
            out[p] = {"bond": slaves[p]}
        elif p not in out and "*" in ports:
            out[p] = ports["*"]
    return out


def _resolved(e):
    if not e or "bond" in e or e.get("err"):
        return None
    untag = int(_s(e["untag"])) if _s(e.get("untag")).isdigit() else None
    return {"untag": untag, "tag": _vids(e.get("tag")), "bridge": bool(e.get("bridge", True)),
            "disabled": bool(e.get("disabled"))}


def _plan_native(pi, all_vids):
    """802.1Q-Einstellung eines NetBox-Interfaces -> {"untag","tag"} oder None (kein Modus gepflegt)"""
    mode = pi.get("mode")
    if not mode:
        return None
    untag = pi.get("untag")
    if mode == "access":
        return {"untag": untag, "tag": set()}
    if mode == "tagged-all":
        return {"untag": untag, "tag": set(all_vids) - {untag}}
    return {"untag": untag, "tag": set(pi.get("tag") or [])}


def _fmt(r):
    t = []
    if r["untag"] is not None:
        t.append("untagged %s" % r["untag"])
    if r["tag"]:
        t.append("tagged " + ",".join(str(x) for x in sorted(r["tag"])))
    return " ".join(t) or "keine VLANs"


def abgleich(plan, soll, ist, alle=False):
    B = Befunde()
    inv = soll.get("inv") or {}
    pdev = plan.get("devices") or {}
    soll_vids = set(int(v) for v in (soll.get("vlans") or {}) if str(v).isdigit())

    # --- Geräte ---
    for n in sorted(set(pdev) | set(inv)):
        p, s, i = pdev.get(n), inv.get(n), (ist.get(n) or {}).get("status") or {}
        if p and not s:
            B.abw("Geräte", n, "in NetBox, nicht im cfm-Inventar")
            continue
        if s and not p:
            B.abw("Geräte", n, "im cfm-Inventar, nicht in NetBox (Site %s)" % plan.get("site"))
            continue
        serial = _s(i.get("serial") or s.get("serial"))
        if p["serial"] and serial and not str(serial).startswith("SERIAL-") and p["serial"] != serial:
            B.abw("Geräte", n, "Seriennummer NetBox %s, Gerät %s" % (p["serial"], serial))
        elif not p["serial"] and serial and not str(serial).startswith("SERIAL-"):
            B.hinweis("Geräte", n, "Seriennummer fehlt in NetBox (Gerät: %s)" % serial)
        board = i.get("model")
        if board and (p["model"] or p["part"]):
            if not modell_passt(p["model"], p["part"], board, i.get("rb")):
                B.hinweis("Geräte", n, "Modell NetBox %s, Gerät meldet %s" % (
                    p["model"] or p["part"], board + (" (%s)" % i["rb"] if i.get("rb") else "")))
        if p["role"] is not None and _roles(p["role"]) != _roles(s.get("role")):
            B.abw("Geräte", n, "Rolle NetBox (cfm_role) %s, Inventar %s" % (p["role"], s.get("role")))
        elif p["role"] is None:
            B.hinweis("Geräte", n, "cfm_role fehlt in NetBox (Inventar: %s)" % s.get("role"))
        if p["ip"] and s.get("ip") and p["ip"] != s.get("ip"):
            B.abw("Geräte", n, "MGMT-IP NetBox %s (primary IPv4), Inventar %s" % (p["ip"], s.get("ip")))
        if n in inv and n not in ist:
            B.hinweis("Geräte", n, "kein Ist vom Gerät (state/%s fehlt - nicht aufgenommen oder nicht erreichbar)" % n)

    # --- Ports ---
    for n in sorted(set(pdev) & set(inv)):
        pif = (plan.get("interfaces") or {}).get(n) or {}
        st = (ist.get(n) or {}).get("status") or {}
        ex = (ist.get(n) or {}).get("export")
        eth = list(st.get("eth") or [])
        if not eth and ex:
            eth = sorted(set(ex["eth_set"]) | {p for p in ex["bports"] if p not in ex["bonds"]})
        bonds = set((ex or {}).get("bonds", {}))
        sp = soll_ports(soll, n, eth or [k for k, v in pif.items() if v["type"] not in PHYS_SKIP])
        sh = (soll.get("hosts") or {}).get(n) or {}
        bonds |= {k for k in (sh.get("bonds") or {})}
        bonds |= set((sh.get("slaves") or {}).values())
        phys = {k: v for k, v in pif.items() if v["type"] not in ("virtual", "bridge") and
                not str(v["type"]).startswith("ieee802.11")}
        if eth:
            for p in sorted(set(phys) - set(eth) - bonds):
                if phys[p]["type"] != "lag":
                    B.abw("Ports", "%s %s" % (n, p), "in NetBox, das Gerät hat keinen solchen Port")
            for p in sorted(set(eth) - set(pif)):
                B.abw("Ports", "%s %s" % (n, p), "am Gerät, fehlt in NetBox")
        for b in sorted(bonds - set(pif)):
            B.abw("Ports", "%s %s" % (n, b), "Bond in cfm, fehlt in NetBox (Interface Typ LAG)")
        ip_ports = ist_ports(ex) if ex else {}
        nomode = []
        pdef = pdev[n]["port_default"]
        all_vids = set(int(v) for v in plan.get("vlans") or {} if str(v).isdigit()) or soll_vids
        for p in sorted(set(phys) | set(sp)):
            if p == "*":
                continue
            pi, se = phys.get(p), sp.get(p)
            obj = "%s %s" % (n, p)
            if se and "bond" in se:
                if pi and pi.get("lag") != se["bond"]:
                    B.abw("Ports", obj, "Slave von %s in cfm, in NetBox LAG %s" % (se["bond"], pi.get("lag") or "keiner"))
                continue
            if not pi:
                if se and p not in eth and p not in bonds:
                    B.hinweis("Ports", obj, "steht im Hostfile (%s), fehlt in NetBox und am Gerät" % _s(se.get("spec")))
                continue
            pspec = pi["spec"] or (pdef if pi["type"] not in ("lag",) and not pi.get("lag") else None)
            sspec = _s(se.get("spec")) or None if se else None
            if pspec != sspec:
                if pspec and sspec:
                    B.abw("Ports", obj, "Profil NetBox %s, cfm %s" % (pspec, sspec))
                elif pspec:
                    B.abw("Ports", obj, "Profil NetBox %s, cfm ohne Profil (nicht in ports/portDefault)" % pspec)
                else:
                    B.abw("Ports", obj, "cfm %s, in NetBox kein cfm_port (und kein cfm_port_default)" % sspec)
            rs = _resolved(se)
            if se and se.get("err"):
                B.abw("Ports", obj, "Profil %s in cfm nicht auflösbar: %s" % (sspec, se["err"]))
            if rs and pspec == sspec:
                pn = _plan_native(pi, all_vids)
                if pn is None:
                    if rs["bridge"]:
                        nomode.append(p)
                elif not rs["bridge"]:
                    B.hinweis("Ports", obj, "802.1Q-Modus %s in NetBox, Profil %s ist nicht in der Bridge" % (pi["mode"], sspec))
                elif pn["untag"] != rs["untag"] or pn["tag"] != rs["tag"]:
                    B.abw("Ports", obj, "802.1Q in NetBox %s, Profil %s ergibt %s" % (_fmt(pn), sspec, _fmt(rs)))
                if rs["disabled"] == pi.get("enabled", True):
                    B.hinweis("Ports", obj, "NetBox %s, Profil %s %s" % (
                        "aktiv" if pi.get("enabled", True) else "abgeschaltet", sspec,
                        "schaltet ab" if rs["disabled"] else "ist aktiv"))
            if rs and ex is not None and rs["bridge"]:
                ii = ip_ports.get(p)
                if ii is None:
                    B.hinweis("Ports", obj, "Soll %s (%s), am Gerät nicht in der Bridge - Release noch nicht angewendet?" % (sspec, _fmt(rs)))
                elif ii["untag"] != rs["untag"] or ii["tag"] != rs["tag"]:
                    B.hinweis("Ports", obj, "Soll %s (%s), Gerät %s - Release noch nicht angewendet?" % (sspec, _fmt(rs), _fmt(ii)))
        if nomode:
            B.hinweis("Ports", n, "802.1Q-Modus in NetBox nicht gepflegt: " + ", ".join(nomode))

    # --- Kabel ---
    peer_plan = {}
    for a, ai, b, bi in plan.get("cables") or []:
        peer_plan[(a, ai)] = (b, bi)
        peer_plan[(b, bi)] = (a, ai)
    for n in sorted(set(pdev) & set(inv)):
        links = ((soll.get("hosts") or {}).get(n) or {}).get("links") or {}
        nbs = {}
        for e in ((ist.get(n) or {}).get("status") or {}).get("nb") or []:
            if len(e) >= 3:
                nbs.setdefault(e[0], []).append((e[1], e[2]))
        ports = {p for (d, p) in peer_plan if d == n} | set(links) | set(nbs)
        for p in sorted(ports):
            obj = "%s %s" % (n, p)
            pp = peer_plan.get((n, p))
            ptxt = "%s:%s" % pp if pp else "nichts"
            sl = links.get(p)
            if sl is not None:
                sl = _s(sl)
                if sl == "-":
                    if pp:
                        B.abw("Kabel", obj, "NetBox %s, Hostfile links: hier hängt nichts" % ptxt)
                elif ":" in sl:
                    if not pp or "%s:%s" % pp != sl:
                        B.abw("Kabel", obj, "NetBox %s, Hostfile links %s" % (ptxt, sl))
                elif not pp or pp[0] != sl:
                    B.abw("Kabel", obj, "NetBox %s, Hostfile links %s" % (ptxt, sl))
            elif pp and pp[0] in inv:
                B.hinweis("Kabel", obj, "NetBox %s, im Hostfile fehlt links (Vorschlag: \"%s\"=\"%s\")" % (ptxt, p, ptxt))
            seen = nbs.get(p) or []
            if seen:
                if not pp:
                    B.abw("Kabel", obj, "LLDP/MNDP sieht %s, in NetBox kein Kabel" % ", ".join("%s:%s" % x for x in seen))
                elif not any(x[0] == pp[0] and (not x[1] or x[1] == pp[1]) for x in seen):
                    B.abw("Kabel", obj, "NetBox %s, LLDP/MNDP sieht %s" % (ptxt, ", ".join("%s:%s" % x for x in seen)))
            elif pp and pp[0] in inv and n in ist and ist[n].get("status"):
                B.hinweis("Kabel", obj, "NetBox %s, kein Nachbar gemeldet (Link aus oder keine Nachbarsuche)" % ptxt)

    # --- VLANs ---
    sv = {str(k): _s(v.get("name")) for k, v in (soll.get("vlans") or {}).items()}
    pv = plan.get("vlans") or {}
    for vid in sorted(set(sv) | set(pv), key=lambda x: int(x) if x.isdigit() else 0):
        if vid not in pv:
            B.abw("VLANs", vid, "in cfm (%s), fehlt in NetBox" % sv[vid])
        elif vid not in sv:
            B.abw("VLANs", vid, "in NetBox (%s), nicht in vlans.rsc" % pv[vid])
        elif _norm(pv[vid]) != _norm(sv[vid]):
            B.hinweis("VLANs", vid, "Name NetBox %s, cfm %s" % (pv[vid], sv[vid]))

    # --- Prefixe ---
    snets = {}
    for vid, v in (soll.get("vlans") or {}).items():
        if v.get("net"):
            snets[str(ipaddress.ip_network(v["net"], strict=False))] = int(vid)
    wg = soll.get("wg") or {}
    if not wg.get("peers"):  # ohne Peers bleibt der Fernzugang aus (wireguard.rsc): kein Netz, keine Adresse
        wg = {"sites": wg.get("sites")}
    if wg.get("net"):
        snets[str(ipaddress.ip_network(wg["net"], strict=False))] = None
    pp_ = {}
    for k, v in (plan.get("prefixes") or {}).items():
        try:
            pp_[str(ipaddress.ip_network(k, strict=False))] = v
        except ValueError:
            pass
    for net in sorted(set(snets) | set(pp_)):
        if net not in pp_:
            B.abw("Prefixe", net, "in cfm (%s), fehlt in NetBox" % ("VLAN %s" % snets[net] if snets[net] else "WireGuard"))
        elif net not in snets:
            B.info("Prefixe", net, "nur in NetBox")
        elif snets[net] and pp_[net] != snets[net]:
            B.abw("Prefixe", net, "VLAN NetBox %s, cfm %s" % (pp_[net] or "keins", snets[net]))

    # --- IP-Adressen ---
    pips = {}
    for a in plan.get("ips") or []:
        pips.setdefault(_host(a["addr"]), []).append(a)
    sips = {}

    def s_add(ip, was, dev=None, dns=None):
        if ip:
            sips.setdefault(ip, []).append({"was": was, "dev": dev, "dns": dns})
    for n, s in inv.items():
        s_add(s.get("ip"), "MGMT", n)
    for vid, v in (soll.get("vlans") or {}).items():
        if v.get("gw") and v.get("l3", True):
            s_add(v["gw"], "Gateway VLAN %s" % vid)
    for l in soll.get("leases") or []:
        s_add(l.get("ip"), "Lease VLAN %s" % _s(l.get("vlan")), dns=_s(l.get("name")))
    if wg.get("router"):
        s_add(wg["router"], "WireGuard Router")
    for pn, a in (wg.get("peers") or {}).items():
        s_add(a, "WireGuard Peer", dns=pn)
    iips = {}
    for n, x in ist.items():
        for addr, ifn in ((x.get("export") or {}).get("ips") or []):
            iips.setdefault(_host(addr), []).append((n, ifn))
    dom = str((soll.get("g") or {}).get("domain") or "")
    for ip in sorted(set(sips) | set(iips) | set(pips), key=lambda x: tuple(int(o) for o in x.split(".")) if re.match(r"^[\d.]+$", x) else (999,)):
        pl, sl, il = pips.get(ip) or [], sips.get(ip) or [], iips.get(ip) or []
        was = ", ".join(sorted(set(e["was"] for e in sl)))
        if (sl or il) and not pl:
            if sl:
                auf = " (auf %s)" % ", ".join("%s %s" % x for x in il) if il else ""
                B.abw("IP-Adressen", ip, "in cfm (%s)%s, fehlt in NetBox" % (was, auf))
            else:
                B.abw("IP-Adressen", ip, "auf %s, fehlt in NetBox" % ", ".join("%s %s" % x for x in il))
            continue
        if pl and not sl and not il:
            pa = pl[0]
            if pa["dev"] in inv:
                B.abw("IP-Adressen", ip, "in NetBox auf %s %s, nicht auf dem Gerät" % (pa["dev"], pa["if"]))
            elif alle:
                B.info("IP-Adressen", ip, "nur in NetBox%s" % (" (%s)" % pa["dns"] if pa["dns"] else ""))
            continue
        devs_ist = {d for d, _ in il}
        for pa in pl:
            if pa["dev"] and il and pa["dev"] not in devs_ist:
                B.abw("IP-Adressen", ip, "NetBox auf %s, Gerät: %s" % (pa["dev"], ", ".join("%s %s" % x for x in il)))
            elif pa["dev"] and il:
                ifs = {f for d, f in il if d == pa["dev"]}
                if pa["if"] not in ifs:
                    B.hinweis("IP-Adressen", ip, "NetBox Interface %s %s, Gerät %s" % (pa["dev"], pa["if"], ", ".join(sorted(ifs))))
        for e in sl:
            if e["was"] == "MGMT" and not any(pa["dev"] == e["dev"] for pa in pl):
                B.abw("IP-Adressen", ip, "MGMT von %s, in NetBox %s" % (e["dev"], ", ".join(pa["dev"] or "nicht zugewiesen" for pa in pl)))
            if e["dns"]:
                names = {_norm(pa["dns"]) for pa in pl}
                want = {_norm(e["dns"]), _norm("%s.%s" % (e["dns"], dom))}
                if not names & want:
                    B.hinweis("IP-Adressen", ip, "%s: DNS-Name in NetBox %s, cfm %s" % (e["was"], ", ".join(pa["dns"] or "leer" for pa in pl), e["dns"]))
        if len(il) > 1 and len(devs_ist) > 1 and not any(pa["role"] in ("vip", "vrrp", "anycast") for pa in pl):
            B.hinweis("IP-Adressen", ip, "auf mehreren Geräten (%s) - in NetBox Rolle VIP/VRRP setzen" % ", ".join(sorted(devs_ist)))

    # --- Tunnel (Standortkopplung) ---
    sites = (wg.get("sites") or {})
    tun = plan.get("tunnels")
    if tun is None:
        if sites:
            B.hinweis("Tunnel", "-", "NetBox ohne VPN-Modul (vor 3.7): Standortkopplung nicht abgeglichen")
    else:
        names = {t: t for t in tun}
        names.update({t[len("wg-site-"):]: t for t in tun if t.startswith("wg-site-")})
        for sn in sorted(sites):
            if sn not in names:
                B.abw("Tunnel", sn, "Standortkopplung wg-site-%s in cfm, kein Tunnel in NetBox" % sn)
        for t in sorted(tun):
            key = t[len("wg-site-"):] if t.startswith("wg-site-") else t
            if key not in sites:
                B.info("Tunnel", t, "nur in NetBox (an %s)" % ", ".join(tun[t]))
    if not alle:
        B.items = [x for x in B.items if x["art"] != "info"]
    return B.items


# ---------------------------------------------------------------- Ausgabe

ART = {"abweichung": "✘", "hinweis": "!", "info": "·"}
BEREICHE = ["Geräte", "Ports", "Kabel", "VLANs", "Prefixe", "IP-Adressen", "Tunnel"]


def bericht(items, kopf):
    out = [kopf]
    for b in BEREICHE:
        xs = [x for x in items if x["bereich"] == b]
        if not xs:
            continue
        out.append("")
        out.append(b)
        for x in xs:
            out.append("  %s %-22s %s" % (ART[x["art"]], x["objekt"], x["text"]))
    na = sum(1 for x in items if x["art"] == "abweichung")
    nh = sum(1 for x in items if x["art"] == "hinweis")
    out.append("")
    out.append("%d Abweichungen, %d Hinweise" % (na, nh) if items else "Keine Abweichungen.")
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description="NetBox-Planung mit cfm abgleichen (TODO 55)")
    ap.add_argument("--netbox", help="URL der NetBox")
    ap.add_argument("--token-file")
    ap.add_argument("--site", help="Slug der NetBox-Site")
    ap.add_argument("--vlan-group")
    ap.add_argument("--ca", help="CA-Zertifikat (PEM) für eine NetBox mit eigenem Zertifikat")
    ap.add_argument("--unsicher", action="store_true", help="Zertifikat der NetBox nicht prüfen")
    ap.add_argument("--plan", help="NetBox-Plan aus Datei statt per API")
    ap.add_argument("--plan-speichern")
    ap.add_argument("--state", help="lokale Kopie von state/ (statt --manager)")
    ap.add_argument("--manager", help="user@host des Primary-Managers")
    ap.add_argument("--port", type=int, default=22)
    ap.add_argument("--base", default="cfm")
    ap.add_argument("--ver", type=int)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--alle", action="store_true")
    a = ap.parse_args(argv)
    tmp = None
    try:
        if a.plan:
            with open(a.plan, encoding="utf-8") as f:
                plan = json.load(f)
        else:
            if not a.netbox or not a.site:
                ap.error("--netbox und --site (oder --plan) angeben")
            tok = os.environ.get("NETBOX_TOKEN", "")
            if a.token_file:
                with open(a.token_file, encoding="utf-8") as f:
                    tok = f.read().strip()
            if not tok:
                ap.error("API-Token fehlt (--token-file oder NETBOX_TOKEN)")
            plan = plan_from_netbox(NetBox(a.netbox, tok, a.ca, a.unsicher), a.site, a.vlan_group)
        if a.plan_speichern:
            with open(a.plan_speichern, "w", encoding="utf-8") as f:
                json.dump(plan, f, indent=1, ensure_ascii=False, sort_keys=True)
            if not a.state and not a.manager:
                # nur NetBox lesen (z.B. vor dem Rollout von $cfmNetbox): Plan speichern, kurz zusammenfassen
                print("Plan gespeichert: %s (%s)" % (a.plan_speichern, ", ".join(
                    "%s %d" % (k, len(v)) for k, v in sorted(plan.items()) if isinstance(v, (list, dict)))))
                return 0
        if a.state:
            d = a.state
        elif a.manager:
            tmp = tempfile.mkdtemp(prefix="cfm-nb-")
            fetch_state(a.manager, a.port, a.base, a.ver, tmp)
            d = tmp
        else:
            ap.error("--state oder --manager angeben")
        soll, ist = load_state(d)
        items = abgleich(plan, soll, ist, a.alle)
    except (RuntimeError, OSError, ValueError) as e:
        print("FEHLER: %s" % e, file=sys.stderr)
        return 2
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)
    if a.json:
        json.dump(items, sys.stdout, indent=1, ensure_ascii=False)
        sys.stdout.write("\n")
    else:
        src = "v%s" % soll.get("v") if soll.get("v") else "work/"
        sys.stdout.write(bericht(items, "NetBox-Abgleich: Site %s <-> cfm %s" % (plan.get("site", "?"), src)))
    return 1 if any(x["art"] == "abweichung" for x in items) else 0


if __name__ == "__main__":
    sys.exit(main())
