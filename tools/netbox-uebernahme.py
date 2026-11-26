#!/usr/bin/env python3
"""netbox-uebernahme – Plan aus NetBox als Vorschlag für die Site-Daten (TODO 55, DT2.5).

Gegenrichtung zu netbox-import.py: Was in NetBox geplant ist, wird als unified diff gegen ein Site-Overlay gezeigt
(oder mit --schreiben dort eingetragen). NetBox selbst schreibt nie in cfm (DT2.2) – das Tool läuft beim Admin, und
übernommen wird erst mit upload-seed.sh --site (bzw. dem cfm-Editor) und einem Release.

  hosts/<gerät>.rsc  "ports" aus dem Custom Field cfm_port der Interfaces, "portDefault" aus cfm_port_default,
                     "links" aus Kabeln zwischen zwei Geräten mit Hostfile ("<port>"="<gerät>:<port>")
  leases.rsc         Adressen mit DNS-Namen in einem Prefix mit VLAN mit MAC (am Interface des Geräts bzw. der VM, sonst
                     "cfm-Lease <MAC>" in der Beschreibung wie vom Start-Import), die keinem cfm-Gerät gehören: neue Lease bzw. geänderte MAC/Adresse (Name = erstes Label des DNS-Namens)
  vlans.rsc          VLANs, die es nur in NetBox gibt, als Kommentar-Vorschlag am Ende (Zone, DHCP usw. entscheidet der Admin)

Nichts wird gelöscht: Was nur in cfm steht, nennt das Tool als Hinweis. Kommentare und Reihenfolge der Dateien bleiben;
neue Einträge kommen ans Ende des jeweiligen Blocks. Lässt sich ein Block nicht sicher lesen, gibt es einen Hinweis.

Aufruf (aus dem Wurzelverzeichnis des Repos):
  tools/netbox-uebernahme.py --overlay site-a --netbox https://netbox.example --token-file <ro-token> --site <slug>
  tools/netbox-uebernahme.py --overlay site-a --plan plan.json         # Plan aus netbox-abgleich.py --plan-speichern
  … --diff-datei vorschlag.diff    Diff zusätzlich als Datei (anwenden: patch -p1 -d site-a < vorschlag.diff)
  … --schreiben                    die Dateien im Overlay ändern
Exit-Code: 0 = keine Änderung, 1 = Vorschlag vorhanden, 2 = Fehler.
"""
import argparse
import difflib
import importlib.util
import ipaddress
import json
import os
import re
import sys
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("nbabgleich", os.path.join(HERE, "netbox-abgleich.py"))
ab = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ab)

ENTRY = re.compile(r'^(\s*)"([^"]+)"="([^"]*)"(;?)\s*$')
NAME_OK = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$")


def natkey(s):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", s)]


# ---------------------------------------------------------------- Hostfile

def _host_block(lines):
    """Zeilenbereich von ':global cfmHost {' bis zur schließenden '}' -> (start, ende) oder None"""
    st = next((i for i, l in enumerate(lines) if re.match(r"^:global cfmHost \{\s*$", l)), None)
    if st is None:
        return None
    en = next((i for i in range(st + 1, len(lines)) if re.match(r"^\}\s*$", lines[i])), None)
    return (st, en) if en is not None else None


def set_map(text, key, want, hinweise, wer):
    """Block "key"={…} im Hostfile: Werte aus want setzen (nichts löschen). -> neuer Text"""
    if not want:
        return text
    lines = text.split("\n")
    hb = _host_block(lines)
    if not hb:
        hinweise.append("%s: kein ':global cfmHost {' über mehrere Zeilen - %s von Hand" % (wer, key))
        return text
    st, en = hb
    kre = re.compile(r'^(\s*)"%s"=\{(.*)$' % re.escape(key))
    bi = next((i for i in range(st + 1, en) if kre.match(lines[i])), None)
    if bi is None:
        # neuer Block als erster Eintrag (endet mit ";", weil danach noch etwas kommt) oder einziger
        last = en - 1 > st
        body = ['    "%s"="%s"%s' % (k, v, ";" if j < len(want) - 1 else "")
                for j, (k, v) in enumerate(sorted(want.items(), key=lambda x: natkey(x[0])))]
        new = ['  "%s"={' % key] + body + ["  }" + (";" if last else "")]
        lines[st + 1:st + 1] = new
        return "\n".join(lines)
    m = kre.match(lines[bi])
    rest = m.group(2)
    if rest.strip():
        # einzeilig: "ports"={"a"="b";"c"="d"};
        mm = re.match(r'^(.*?)\}(;?)\s*$', rest)
        if not mm:
            hinweise.append("%s: %s nicht lesbar - von Hand" % (wer, key))
            return text
        items = re.findall(r'"([^"]+)"="([^"]*)"', mm.group(1))
        cur = dict(items)
        order = [k for k, _ in items] + [k for k in sorted(want, key=natkey) if k not in dict(items)]
        cur.update(want)
        lines[bi] = '%s"%s"={%s}%s' % (m.group(1), key, ";".join('"%s"="%s"' % (k, cur[k]) for k in order), mm.group(2))
        return "\n".join(lines)
    # mehrzeilig
    ei = next((i for i in range(bi + 1, en + 1) if re.match(r"^\s*\}(;?)\s*$", lines[i])), None)
    if ei is None:
        hinweise.append("%s: Ende von %s nicht gefunden - von Hand" % (wer, key))
        return text
    rows = []
    for i in range(bi + 1, ei):
        if not lines[i].strip():
            continue
        e = ENTRY.match(lines[i])
        if not e:
            hinweise.append("%s: Zeile in %s nicht lesbar (%s) - von Hand" % (wer, key, lines[i].strip()))
            return text
        rows.append([e.group(1), e.group(2), e.group(3)])
    ind = rows[0][0] if rows else "    "
    have = {r[1] for r in rows}
    for r in rows:
        if r[1] in want:
            r[2] = want[r[1]]
    for k in sorted(want, key=natkey):
        if k not in have:
            rows.append([ind, k, want[k]])
    body = ['%s"%s"="%s"%s' % (r[0], r[1], r[2], ";" if j < len(rows) - 1 else "") for j, r in enumerate(rows)]
    lines[bi + 1:ei] = body
    return "\n".join(lines)


def set_scalar(text, key, val, hinweise, wer):
    lines = text.split("\n")
    hb = _host_block(lines)
    if not hb:
        hinweise.append("%s: kein ':global cfmHost {' - %s von Hand" % (wer, key))
        return text
    st, en = hb
    kre = re.compile(r'^(\s*)"%s"="([^"]*)"(;?)\s*$' % re.escape(key))
    for i in range(st + 1, en):
        m = kre.match(lines[i])
        if m:
            lines[i] = '%s"%s"="%s"%s' % (m.group(1), key, val, m.group(3))
            return "\n".join(lines)
    lines.insert(st + 1, '  "%s"="%s"%s' % (key, val, ";" if en - 1 > st else ""))
    return "\n".join(lines)


def host_values(text, key):
    """aktuelle Einträge eines Blocks (ein- oder mehrzeilig) und Skalare -> dict"""
    m = re.search(r'"%s"=\{(.*?)\}' % re.escape(key), text, re.S)
    return dict(re.findall(r'"([^"]+)"="([^"]*)"', m.group(1))) if m else {}


def host_scalar(text, key):
    m = re.search(r'^\s*"%s"="([^"]*)"' % re.escape(key), text, re.M)
    return m.group(1) if m else None


# ---------------------------------------------------------------- Leases

LBLOCK = re.compile(r'^  "(\d+)"=\{\s*$')
LENTRY = re.compile(r'^(\s*)"([A-Za-z0-9-]+)"=\{(.*)\}(;?)\s*$')


def parse_leases(text):
    """-> {vid: {name: {"mac", "ip", "line"}}} aus Block- und :set-Form"""
    r = {}
    vid = None
    for i, l in enumerate(text.split("\n")):
        if l.startswith("#"):
            continue
        b = LBLOCK.match(l)
        if b:
            vid = b.group(1)
            r.setdefault(vid, {})
            continue
        if re.match(r"^  \}", l):
            vid = None
            continue
        e = LENTRY.match(l)
        if e and vid:
            f = e.group(3)
            mac = re.search(r'"mac"="([^"]*)"', f)
            ip = re.search(r'"ip"=(\d+)', f)
            r[vid][e.group(2)] = {"mac": (mac.group(1) if mac else "").upper(), "ip": int(ip.group(1)) if ip else None, "line": i}
            continue
        s = re.match(r'^:set \(\$cfmLeases->"(\d+)"(?:->"([A-Za-z0-9-]+)")?\) (.*)$', l)
        if s:
            v = s.group(1)
            ents = [(s.group(2), s.group(3))] if s.group(2) else re.findall(r'"([A-Za-z0-9-]+)"=(\{[^{}]*\})', s.group(3))
            for n, f in ents:
                mac = re.search(r'"mac"="([^"]*)"', f)
                ip = re.search(r'"ip"=(\d+)', f)
                r.setdefault(v, {})[n] = {"mac": (mac.group(1) if mac else "").upper(), "ip": int(ip.group(1)) if ip else None,
                                          "line": None}
    return r


def lease_text(mac, ip):
    return '{"mac"="%s";"ip"=%d}' % (mac, ip)


def leases_apply(text, changes, hinweise):
    """changes: [(vid, name, mac, ip, alt)] alt = bestehender Eintrag oder None -> neuer Text"""
    lines = text.split("\n")
    for vid, name, mac, ip, alt in changes:
        if alt:
            if alt["line"] is None:
                hinweise.append("leases.rsc: %s (VLAN %s) steht als :set-Zeile - von Hand ändern auf %s .%d" % (name, vid, mac, ip))
                continue
            e = LENTRY.match(lines[alt["line"]])
            f = e.group(3)
            f = re.sub(r'"mac"="[^"]*"', '"mac"="%s"' % mac, f)
            f = re.sub(r'"ip"=\d+', '"ip"=%d' % ip, f)
            lines[alt["line"]] = '%s"%s"={%s}%s' % (e.group(1), name, f, e.group(4))
            continue
        ent = '"%s"=%s' % (name, lease_text(mac, ip))
        g = next((i for i, l in enumerate(lines) if l.startswith(":global cfmLeases")), None)
        if g is None:
            hinweise.append("leases.rsc: keine Zeile ':global cfmLeases' - %s von Hand" % name)
            continue
        if lines[g].strip() == ":global cfmLeases ({})":
            lines[g:g + 1] = [":global cfmLeases {", '  "%s"={' % vid, "    " + ent, "  }", "}"]
            continue
        bs = next((i for i in range(g, len(lines)) if lines[i] == '  "%s"={' % vid), None)
        if bs is not None:
            be = next((i for i in range(bs + 1, len(lines)) if re.match(r"^  \}", lines[i])), None)
            if be is None:
                hinweise.append("leases.rsc: Ende des Blocks %s nicht gefunden - %s von Hand" % (vid, name))
                continue
            if be > bs + 1 and not lines[be - 1].rstrip().endswith(";"):
                lines[be - 1] = lines[be - 1].rstrip() + ";"
            lines.insert(be, "    " + ent)
            continue
        # neuer Block vor der schließenden Klammer von cfmLeases
        ce = next((i for i in range(g + 1, len(lines)) if re.match(r"^\}\s*$", lines[i])), None)
        if ce is None:
            hinweise.append("leases.rsc: Ende von cfmLeases nicht gefunden - %s von Hand" % name)
            continue
        if ce > g + 1 and not lines[ce - 1].rstrip().endswith(";"):
            lines[ce - 1] = lines[ce - 1].rstrip() + ";"
        lines[ce:ce] = ['  "%s"={' % vid, "    " + ent, "  }"]
    return "\n".join(lines)


def netbox_leases(nb, site, cfm_devs):
    """Adressen mit DNS-Namen in Prefixen mit VLAN, Interface mit MAC, kein cfm-Gerät ->
    [{"vid", "name", "mac", "addr", "net"}], Hinweise"""
    sites = nb.get("dcim/sites", slug=site)
    if not sites:
        raise RuntimeError("Site %s gibt es in NetBox nicht" % site)
    out, hin = [], []
    low = {d.lower() for d in cfm_devs}
    for p in nb.get("ipam/prefixes", site_id=sites[0]["id"]):
        vid = (p.get("vlan") or {}).get("vid")
        if vid is None:
            continue
        net = ipaddress.ip_network(p["prefix"], strict=False)
        for a in nb.get("ipam/ip-addresses", parent=p["prefix"]):
            dns = (a.get("dns_name") or "").strip()
            if not dns:
                continue
            ao = a.get("assigned_object") or {}
            typ = a.get("assigned_object_type")
            owner = ((ao.get("device") or {}).get("name") if typ == "dcim.interface"
                     else (ao.get("virtual_machine") or {}).get("name") if typ == "virtualization.vminterface" else None)
            if owner and owner.lower() in low:
                continue  # Adresse eines cfm-Geräts
            if ab._v(a.get("role")) in ("vip", "vrrp", "anycast"):
                continue
            name = dns.split(".")[0]
            if not NAME_OK.match(name):
                hin.append("NetBox %s: DNS-Name %s ist kein gültiger Lease-Name" % (a["address"], dns))
                continue
            mac = ""
            if typ in ("dcim.interface", "virtualization.vminterface") and ao.get("id"):
                path = "dcim/interfaces" if typ == "dcim.interface" else "virtualization/interfaces"
                i = nb.get(path, id=ao["id"])
                i = i[0] if i else {}
                mac = i.get("mac_address") or (i.get("primary_mac_address") or {}).get("mac_address") or ""
            if not mac:
                # vom Start-Import (netbox-import.py): Beschreibung "cfm-Lease <MAC>"
                m = re.search(r"cfm-Lease ((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})", a.get("description") or "")
                mac = m.group(1) if m else ""
            if not mac:
                hin.append("NetBox %s (%s): keine MAC am Interface - keine Lease" % (a["address"], dns))
                continue
            out.append({"vid": str(vid), "name": name, "mac": mac.upper(),
                        "addr": a["address"].split("/")[0], "net": str(net)})
    return out, hin


# ---------------------------------------------------------------- VLANs

def vlan_ids(text):
    return set(re.findall(r'^\s*"(\d+)"=\{', text, re.M))


# ---------------------------------------------------------------- Ablauf

def vorschlag(plan, overlay, nb_leases=None):
    """-> ({relpfad: (alt, neu)}, hinweise)"""
    files, hin = {}, []

    def rd(rel):
        try:
            with open(os.path.join(overlay, rel), encoding="utf-8") as f:
                return f.read()
        except OSError:
            return None
    hdir = os.path.join(overlay, "hosts")
    hosts = {}
    if os.path.isdir(hdir):
        for fn in os.listdir(hdir):
            if fn.endswith(".rsc") and not fn.endswith(".post.rsc"):
                hosts[fn[:-4].lower()] = fn[:-4]
    for dn in sorted(plan.get("devices") or {}):
        hn = hosts.get(dn.lower())
        if not hn:
            hin.append("NetBox-Gerät %s: kein Hostfile im Overlay (neues Gerät: $cfmEnroll, Hostfile anlegen)" % dn)
            continue
        rel = "hosts/%s.rsc" % hn
        alt = rd(rel)
        neu = alt
        d = plan["devices"][dn]
        ifs = plan.get("interfaces", {}).get(dn) or {}
        cur = host_values(alt, "ports")
        want = {}
        for ifn, e in ifs.items():
            spec = (e.get("spec") or "").strip()
            if e.get("type") in ("lag", "bridge", "virtual") or not spec:
                continue
            if cur.get(ifn) != spec:
                want[ifn] = spec
        for ifn in cur:
            if ifn in ifs and not (ifs[ifn].get("spec") or "").strip():
                hin.append("%s %s: in NetBox ohne cfm_port, im Hostfile %s (bleibt)" % (dn, ifn, cur[ifn]))
        neu = set_map(neu, "ports", want, hin, rel)
        pd = (d.get("port_default") or "").strip()
        if pd and host_scalar(alt, "portDefault") != pd:
            neu = set_scalar(neu, "portDefault", pd, hin, rel)
        # Kabel zwischen zwei Geräten mit Hostfile
        cl = host_values(alt, "links")
        lw = {}
        for a, ai, b, bi in plan.get("cables") or []:
            for x, xi, y, yi in ((a, ai, b, bi), (b, bi, a, ai)):
                if x == dn and y.lower() in hosts and cl.get(xi) != "%s:%s" % (y, yi):
                    lw[xi] = "%s:%s" % (y, yi)
        neu = set_map(neu, "links", lw, hin, rel)
        if neu != alt:
            files[rel] = (alt, neu)
    # Leases
    if nb_leases is not None:
        rel = "leases.rsc"
        alt = rd(rel)
        if alt is None:
            hin.append("leases.rsc fehlt im Overlay")
        else:
            have = parse_leases(alt)
            byname = {n: (v, e) for v, ls in have.items() for n, e in ls.items()}
            ch = []
            seen = set()
            for l in nb_leases:
                h = int(ipaddress.ip_address(l["addr"])) - int(ipaddress.ip_network(l["net"]).network_address)
                seen.add(l["name"])
                old = byname.get(l["name"])
                if old and old[0] != l["vid"]:
                    hin.append("Lease %s: in cfm VLAN %s, in NetBox VLAN %s - von Hand umziehen" % (l["name"], old[0], l["vid"]))
                    continue
                if old and old[1]["mac"] == l["mac"] and old[1]["ip"] == h:
                    continue
                ch.append((l["vid"], l["name"], l["mac"], h, old[1] if old else None))
            for n in sorted(byname):
                if n not in seen:
                    hin.append("Lease %s (VLAN %s) nur in cfm - bleibt" % (n, byname[n][0]))
            if ch:
                files[rel] = (alt, leases_apply(alt, ch, hin))
    # VLANs
    rel = "vlans.rsc"
    alt = rd(rel)
    if alt is not None:
        have = vlan_ids(alt)
        nets = {}
        for p, vid in (plan.get("prefixes") or {}).items():
            if vid is not None:
                nets.setdefault(str(vid), p)
        neu_v = [(v, n) for v, n in sorted((plan.get("vlans") or {}).items(), key=lambda x: int(x[0])) if v not in have]
        if neu_v:
            add = ["", "# Vorschlag aus NetBox (netbox-uebernahme.py) - zone, dhcp usw. ergänzen und in cfmVlans aufnehmen:"]
            for v, n in neu_v:
                net = nets.get(v)
                extra = ';"net"="%s"' % net if net and net != "192.168.%s.0/24" % v else ""
                add.append('#  "%s"={"name"="%s";"zone"="?"%s};' % (v, n, extra))
            neu = alt.rstrip("\n") + "\n" + "\n".join(add) + "\n"
            if neu != alt and "# Vorschlag aus NetBox" not in alt:
                files[rel] = (alt, neu)
            elif "# Vorschlag aus NetBox" in alt:
                hin.append("vlans.rsc: Vorschlag aus NetBox steht schon drin (%s)" % ", ".join(v for v, _ in neu_v))
    return files, hin


def unified(files):
    out = []
    for rel in sorted(files):
        a, b = files[rel]
        out.extend(difflib.unified_diff(a.splitlines(True), b.splitlines(True), "a/" + rel, "b/" + rel))
    return "".join(x if x.endswith("\n") else x + "\n" for x in out)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Plan aus NetBox als Vorschlag für die Site-Daten (TODO 55, DT2.5)")
    ap.add_argument("--overlay", required=True, help="Site-Overlay (Verzeichnis mit hosts/, leases.rsc, vlans.rsc)")
    ap.add_argument("--plan", help="NetBox-Plan aus Datei (netbox-abgleich.py --plan-speichern; ohne Leases)")
    ap.add_argument("--netbox")
    ap.add_argument("--site")
    ap.add_argument("--token-file")
    ap.add_argument("--ca")
    ap.add_argument("--unsicher", action="store_true")
    ap.add_argument("--vlan-group")
    ap.add_argument("--diff-datei")
    ap.add_argument("--schreiben", action="store_true", help="Dateien im Overlay ändern")
    a = ap.parse_args(argv)
    try:
        if not os.path.isdir(a.overlay):
            raise RuntimeError("Overlay %s gibt es nicht" % a.overlay)
        nbl, nbh = None, []
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
            nb = ab.NetBox(a.netbox, tok, a.ca, a.unsicher)
            plan = ab.plan_from_netbox(nb, a.site, a.vlan_group)
            nbl, nbh = netbox_leases(nb, a.site, list(plan.get("devices") or {}))
        files, hin = vorschlag(plan, a.overlay, nbl)
    except urllib.error.HTTPError as e:
        print("FEHLER: NetBox %s %s" % (e.code, e.reason), file=sys.stderr)
        return 2
    except (RuntimeError, OSError, ValueError) as e:
        print("FEHLER: %s" % e, file=sys.stderr)
        return 2
    d = unified(files)
    sys.stdout.write(d)
    for h in nbh + hin:
        print("Hinweis: " + h)
    if a.diff_datei:
        with open(a.diff_datei, "w", encoding="utf-8") as f:
            f.write(d)
    if a.schreiben:
        for rel, (_, neu) in files.items():
            with open(os.path.join(a.overlay, rel), "w", encoding="utf-8") as f:
                f.write(neu)
        print("%d Dateien im Overlay geändert - prüfen (git diff), dann upload-seed.sh --site und Release" % len(files))
    elif files:
        print("%d Dateien mit Vorschlag%s - mit --schreiben ins Overlay übernehmen" % (
            len(files), " (auch in %s)" % a.diff_datei if a.diff_datei else ""))
    else:
        print("Keine Änderung: Das Overlay entspricht dem Plan in NetBox.")
    return 1 if files else 0


if __name__ == "__main__":
    sys.exit(main())
