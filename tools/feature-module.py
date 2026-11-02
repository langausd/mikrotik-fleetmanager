#!/usr/bin/env python3
"""feature-module – welche Feature-Module (lib/<Rolle>.<Feature>.rsc, D104) braucht eine Site?

tools/upload-seed.sh lädt nur die Module hoch, deren Feature die Site-Daten nutzen, und entfernt die übrigen
auf dem Manager. Dieses Skript liest dazu die Site-Daten (global.rsc, vlans.rsc, wifi.rsc, wireguard.rsc, dns.rsc,
mlag.rsc, hosts/*.rsc, authorized_keys.<user>) und nennt die Module, die die Site nicht braucht. Dazu zählen
auch die Skript-Rümpfe (lib/<Rolle>.<Name>.rsc, $cfmBody), z.B. der Schalt-Skripte schaltbarer SSIDs.

Aufruf:
  tools/feature-module.py <site-verzeichnis> <lib-verzeichnis>         nicht gebrauchte Module, eins je Zeile
  tools/feature-module.py <site-verzeichnis> <lib-verzeichnis> --alle  alle Module mit Bedarf und Grund

Im Zweifel gilt ein Modul als gebraucht: Die Daten sind RouterOS-Skripte (Schleifen, :set), sie werden
nicht ausgeführt, sondern nur nach den Schlüsseln durchsucht. Ein Feature gilt nur dann als ungenutzt, wenn
jede Nennung seines Schlüssels eindeutig leer bzw. aus ist. Module ohne Regel hier gelten immer als
gebraucht. Gegenstück auf dem Manager: $cfmCheck lehnt ein Release ab, wenn ein genutztes Feature sein
Modul nicht hat (cfm/work/lib/mgr-check.rsc), die Rollen laden es per $cfmFeat (Bedingungen dort).
"""
import os
import re
import sys

MODUL = re.compile(r"^([a-z-]+)\.([a-z0-9-]+)\.rsc$")


def tokens(text):
    """Zerlegt RouterOS-Skript in Token (Kommentare entfernt): ("s", Text) für Strings, sonst ("p", Zeichen)
    bzw. ("w", Wort)."""
    out = []
    i, n = 0, len(text)
    zeilenanfang = True
    while i < n:
        c = text[i]
        if c == "\n":
            zeilenanfang = True
            i += 1
            continue
        if c in " \t\r":
            i += 1
            continue
        if c == "#" and (zeilenanfang or (out and out[-1] == ("p", ";"))):
            while i < n and text[i] != "\n":
                i += 1
            continue
        zeilenanfang = False
        if c == '"':
            j, s = i + 1, []
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n:
                    s.append(text[j + 1])
                    j += 2
                    continue
                s.append(text[j])
                j += 1
            out.append(("s", "".join(s)))
            i = j + 1
            continue
        if c in "{}()[];=":
            out.append(("p", c))
            i += 1
            continue
        j = i
        while j < n and text[j] not in ' \t\r\n"{}()[];=':
            j += 1
        out.append(("w", text[i:j]))
        i = j
    return out


def leer(toks, i):
    """Steht ab toks[i] ein leeres Array ({} bzw. ({}))?"""
    t = [x for x in toks[i:i + 4]]
    return t[:2] == [("p", "{"), ("p", "}")] or t[:4] == [("p", "("), ("p", "{"), ("p", "}"), ("p", ")")]


def wert(toks, i):
    """Einfacher Wert ab toks[i] (String oder Wort, auch in runden Klammern) oder None"""
    if i < len(toks) and toks[i][0] in "sw":
        return toks[i][1]
    if i + 2 < len(toks) and toks[i] == ("p", "(") and toks[i + 1][0] in "sw" and toks[i + 2] == ("p", ")"):
        return toks[i + 1][1]
    return None


def nennungen(toks, schluessel):
    """Positionen hinter jeder Nennung von "schluessel": hinter '=' (Array-Literal) oder None, wenn er
    anders vorkommt (z.B. :set ($cfmG->"snmp") …) - dann ist der Wert nicht ohne Ausführen bekannt."""
    r = []
    for i, t in enumerate(toks):
        if t == ("s", schluessel):
            r.append(i + 2 if i + 1 < len(toks) and toks[i + 1] == ("p", "=") else None)
    return r


def genutzt_wenn_nicht_leer(toks, schluessel):
    """Feature genutzt, sobald eine Nennung kein leeres Array ist (Arrays wie snmp, peers, self)"""
    return any(p is None or not leer(toks, p) for p in nennungen(toks, schluessel))


def nur_leer(toks, name):
    """Datei leer oder nur ":global <name> ({})" bzw. "{}" (wie dns.rsc, mlag.rsc in der Vorlage)"""
    return toks in ([], [("w", ":global"), ("w", name), ("p", "("), ("p", "{"), ("p", "}"), ("p", ")")],
                    [("w", ":global"), ("w", name), ("p", "{"), ("p", "}")])


def lesen(site, name):
    p = os.path.join(site, name)
    if not os.path.isfile(p):
        return None
    with open(p, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def bedarf(site):
    """{Modul: (gebraucht, Grund)} für die Module mit Regel"""
    r = {}
    g = tokens(lesen(site, "global.rsc") or "")
    snmp = genutzt_wenn_nicht_leer(g, "snmp")
    r["base.snmp"] = (snmp, "global.rsc snmp" + ("" if snmp else " leer"))

    v = tokens(lesen(site, "vlans.rsc") or "")
    iso = False
    for p in nennungen(v, "isolate"):
        if p is None or wert(v, p) not in ("no", ""):
            iso = True
    r["base.iso"] = (iso, "vlans.rsc isolate" + ("" if iso else " nirgends an"))

    keys = sorted(f for f in os.listdir(site) if f.startswith("authorized_keys.") and not f.endswith("~")) \
        if os.path.isdir(site) else []
    r["base.sshkeys"] = (bool(keys), ", ".join(keys) if keys else "keine authorized_keys.<user>")

    w = tokens(lesen(site, "wireguard.rsc") or "")
    wg = genutzt_wenn_nicht_leer(w, "peers")
    r["router.wg"] = (wg, "wireguard.rsc peers" + ("" if wg else " leer"))

    lim = False
    for k in ("limit", "limitClient"):
        for p in nennungen(v, k):
            if p is None or wert(v, p) != "":
                lim = True
    r["router.limit"] = (lim, "vlans.rsc limit/limitClient" + ("" if lim else " nirgends"))

    # dns.rsc: ungenutzt nur als ":global cfmDns ({})" (bzw. leer oder fehlt); die Rolle lädt das Modul
    # bei jedem nicht leeren cfmDns
    d = tokens(lesen(site, "dns.rsc") or "")
    dleer = nur_leer(d, "cfmDns")
    r["router.dns"] = (not dleer, "dns.rsc" + (" leer" if dleer else ""))
    selbst = not dleer and genutzt_wenn_nicht_leer(d, "self")
    r["router.dnsreq"] = (selbst, "dns.rsc self" + ("" if selbst else " fehlt"))

    # Bonds: mlag.rsc mit einem Paar oder bonds in einem Hostfile
    grund = []
    if not nur_leer(tokens(lesen(site, "mlag.rsc") or ""), "cfmMlag"):
        grund.append("mlag.rsc")
    hd = os.path.join(site, "hosts")
    for f in sorted(os.listdir(hd)) if os.path.isdir(hd) else []:
        if f.endswith(".rsc") and genutzt_wenn_nicht_leer(tokens(lesen(hd, f) or ""), "bonds"):
            grund.append("hosts/" + f + " bonds")
    r["base.bond"] = (bool(grund), ", ".join(grund) if grund else "keine bonds, mlag.rsc leer")

    # schaltbare SSIDs (D64): Rümpfe von cfm-ssid-<key>-on/-off und cfm-ssid-check; cfm-reprov immer (CAPsMAN)
    wi = tokens(lesen(site, "wifi.rsc") or "")
    sw = any(p is None or wert(wi, p) != "" for p in nennungen(wi, "switch"))
    for m in ("capsman.ssid", "capsman.ssidcheck"):
        r[m] = (sw, "wifi.rsc switch" + ("" if sw else " an keiner SSID"))
    r["capsman.reprov"] = (True, "CAPsMAN immer (cfm-reprov)")
    return r


def module(lib):
    return sorted(f[:-4] for f in os.listdir(lib) if MODUL.match(f)) if os.path.isdir(lib) else []


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 2:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    site, lib = args
    b = bedarf(site)
    for m in module(lib):
        gebraucht, grund = b.get(m, (True, "keine Regel - immer hochladen"))
        if "--alle" in argv:
            print(f"{'ja  ' if gebraucht else 'nein'} lib/{m}.rsc ({grund})")
        elif not gebraucht:
            print(f"lib/{m}.rsc")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
