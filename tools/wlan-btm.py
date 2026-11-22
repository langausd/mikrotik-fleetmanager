#!/usr/bin/env python3
"""wlan-btm.py – Wechselvorschläge (802.11v BSS Transition) und Client-Fähigkeiten aus einem WLAN-Mitschnitt.

Zu TODO 62/97: Bekommt ein Client Wechselvorschläge, und kann er sie überhaupt? Liest einen Mitschnitt von
/interface/wifi/sniffer (pcap-file=…, oder als TZSP-Strom mit tcpdump aufgenommen) und zeigt je Client:

  * Fähigkeiten aus Association/Reassociation Request und Probe Request: BSS Transition (802.11v, Bit 19 der
    Extended Capabilities), 802.11k (RM Enabled Capabilities), FT (Mobility Domain), AKMs aus RSN.
    Fehlt das BTM-Bit, schickt der AP keine Vorschläge – dann wirkt nur die Trennschwelle (drop/join/hold, DW2.5).
  * Ablauf: Authentication (Open/FT/SAE), (Re)Association mit Status, Deauth/Disassoc mit Grund, Action-Frames.
    Ohne PMF sind WNM-Frames lesbar (BTM-Request mit Disassociation Imminent/Kandidaten, BTM-Response mit Status);
    mit PMF (WPA3) sind sie verschlüsselt – dann nur Richtung, Zeit und Länge („geschützt“).

  tools/wlan-btm.py mitschnitt.pcap --mac 02:00:00:00:00:AA [--mac …] [--alle] [--probe]

--mac   Client(s), mehrfach; ohne: alle Clients, die einen (Re)Association Request schicken
--alle  jeden Management-Frame der Clients zeigen (sonst Probe Requests nur zusammengefasst)
--probe Fähigkeiten auch aus Probe Requests ohne --mac (zufällige MACs der Handys erscheinen dann einzeln)

Linktypen: 105 (802.11), 127 (Radiotap, mit Signal), 1 (Ethernet mit TZSP, UDP 37008). Nur Standardbibliothek.
"""
import argparse
import importlib.util
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("pcapziele", os.path.join(HERE, "pcap-ziele.py"))
_pz = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_pz)
frames = _pz.frames


def mac_str(b):
    return ":".join("%02X" % x for x in b)


def norm_mac(s):
    h = "".join(c for c in s if c in "0123456789abcdefABCDEF")
    if len(h) != 12:
        sys.exit(f"keine MAC: {s}")
    return ":".join(h[i:i + 2] for i in range(0, 12, 2)).upper()


# ---------- Kapselung ----------

# Radiotap: Felder in Bit-Reihenfolge (Ausrichtung, Größe) bis dBm Antenna Signal (Bit 5)
RT_FIELDS = [(8, 8), (1, 1), (1, 1), (2, 4), (2, 2), (1, 1)]


def radiotap(b):
    """(802.11-Frame, Signal oder None)"""
    if len(b) < 8:
        return None, None
    ln = struct.unpack("<H", b[2:4])[0]
    present = [struct.unpack("<I", b[4:8])[0]]
    p = 8
    while present[-1] & 0x80000000 and p + 4 <= ln:
        present.append(struct.unpack("<I", b[p:p + 4])[0])
        p += 4
    sig, fcs = None, False
    pr = present[0]
    for bit, (al, sz) in enumerate(RT_FIELDS):
        if not pr & (1 << bit):
            continue
        p = (p + al - 1) // al * al
        if p + sz > ln:
            break
        if bit == 1:
            fcs = bool(b[p] & 0x10)
        if bit == 5:
            sig = struct.unpack("b", b[p:p + 1])[0]
        p += sz
    f = b[ln:]
    if fcs and len(f) >= 4:
        f = f[:-4]
    return f, sig


def tzsp(b):
    """Ethernet/IPv4/UDP 37008/TZSP -> 802.11-Frame (Kapselung 18) oder None"""
    if len(b) < 14:
        return None
    et, p = struct.unpack(">H", b[12:14])[0], 14
    while et in (0x8100, 0x88A8) and len(b) >= p + 4:
        et, p = struct.unpack(">H", b[p + 2:p + 4])[0], p + 4
    if et != 0x0800 or len(b) < p + 20:
        return None
    ihl = (b[p] & 0x0F) * 4
    if b[p + 9] != 17:
        return None
    u = p + ihl
    if len(b) < u + 8 or struct.unpack(">H", b[u + 2:u + 4])[0] != 37008:
        return None
    t = u + 8
    if len(b) < t + 4 or b[t] != 1 or struct.unpack(">H", b[t + 2:t + 4])[0] != 18:
        return None
    q = t + 4
    while q < len(b):
        tag = b[q]
        if tag == 1:
            return b[q + 1:]
        if tag == 0:
            q += 1
            continue
        if q + 1 >= len(b):
            return None
        q += 2 + b[q + 1]
    return None


def dot11(link, data):
    if link == 105:
        return data, None
    if link == 127:
        return radiotap(data)
    if link == 1:
        return tzsp(data), None
    return None, None


# ---------- 802.11 ----------

SUB = {0: "Association Request", 1: "Association Response", 2: "Reassociation Request",
       3: "Reassociation Response", 4: "Probe Request", 5: "Probe Response", 8: "Beacon",
       10: "Disassociation", 11: "Authentication", 12: "Deauthentication", 13: "Action", 14: "Action No Ack"}
AUTH_ALG = {0: "Open", 1: "Shared Key", 2: "FT", 3: "SAE", 4: "FILS", 5: "FILS-PFS", 6: "FILS-PK"}
AKM = {1: "802.1X", 2: "PSK", 3: "FT-802.1X", 4: "FT-PSK", 5: "802.1X-SHA256", 6: "PSK-SHA256", 8: "SAE",
       9: "FT-SAE", 11: "802.1X-SuiteB", 12: "802.1X-SuiteB-192", 18: "OWE", 24: "SAE-EXT", 25: "FT-SAE-EXT"}
BTM_STATUS = {0: "Accept", 1: "Reject: unspecified", 2: "Reject: insufficient beacons",
              3: "Reject: insufficient capacity", 4: "Reject: BSS termination undesired",
              5: "Reject: BSS termination delay", 6: "Reject: candidate list provided",
              7: "Reject: no suitable candidates", 8: "Reject: leaving ESS"}
CAT = {0: "Spectrum", 3: "Block Ack", 4: "Public", 5: "Radio Measurement", 6: "FT", 8: "SA Query",
       10: "WNM", 21: "VHT", 30: "HE", 31: "Protected HE"}
WNM = {6: "BTM Query", 7: "BTM Request", 8: "BTM Response", 26: "Notification Request"}
RM = {0: "Radio Measurement Request", 1: "Radio Measurement Report", 4: "Neighbor Report Request",
      5: "Neighbor Report Response"}


def ies(b):
    out, p = {}, 0
    while p + 2 <= len(b):
        i, ln = b[p], b[p + 1]
        if p + 2 + ln > len(b):
            break
        out.setdefault(i, b[p + 2:p + 2 + ln])
        p += 2 + ln
    return out


def caps(el):
    """Fähigkeiten aus den IEs: dict mit btm (True/False/None), rrm, ft, akm"""
    c = {}
    ext = el.get(127)
    c["btm"] = None if ext is None else (len(ext) >= 3 and bool(ext[2] & 0x08))
    c["rrm"] = 70 in el
    c["ft"] = 54 in el
    rsn = el.get(48)
    akms = []
    if rsn and len(rsn) >= 8:
        p = 2 + 4
        n = struct.unpack("<H", rsn[p:p + 2])[0]
        p += 2 + 4 * n
        if p + 2 <= len(rsn):
            n = struct.unpack("<H", rsn[p:p + 2])[0]
            p += 2
            for k in range(n):
                s = rsn[p + 4 * k:p + 4 * k + 4]
                if len(s) == 4:
                    akms.append(AKM.get(s[3], f"AKM {s[3]}") if s[:3] == b"\x00\x0f\xac" else s.hex())
    c["akm"] = akms
    ssid = el.get(0)
    c["ssid"] = ssid.decode("utf-8", "replace") if ssid else ""
    return c


def caps_str(c):
    b = {True: "ja", False: "NEIN", None: "? (keine Extended Capabilities)"}[c["btm"]]
    s = f"BTM (802.11v) {b}, 802.11k {'ja' if c['rrm'] else 'nein'}, FT {'ja' if c['ft'] else 'nein'}"
    if c["akm"]:
        s += ", AKM " + "/".join(c["akm"])
    return s


def parse(f):
    """802.11-Management-Frame -> dict oder None"""
    if len(f) < 24:
        return None
    fc = struct.unpack("<H", f[:2])[0]
    typ, sub = (fc >> 2) & 3, (fc >> 4) & 15
    if typ != 0:
        return None
    flags = fc >> 8
    r = {"sub": sub, "name": SUB.get(sub, f"Mgmt {sub}"), "prot": bool(flags & 0x40), "retry": bool(flags & 0x08),
         "a1": mac_str(f[4:10]), "a2": mac_str(f[10:16]), "a3": mac_str(f[16:22]), "len": len(f)}
    body = f[24:]
    if sub in (0, 2):
        r["caps"] = caps(ies(body[4 if sub == 0 else 10:]))
    elif sub == 4:
        r["caps"] = caps(ies(body))
    elif sub in (1, 3) and len(body) >= 6:
        r["status"] = struct.unpack("<H", body[2:4])[0]
        r["caps"] = caps(ies(body[6:]))
    elif sub == 11 and len(body) >= 6:
        alg, seq, st = struct.unpack("<HHH", body[:6])
        r["info"] = f"{AUTH_ALG.get(alg, alg)} Schritt {seq}, Status {st}"
    elif sub in (10, 12) and len(body) >= 2 and not r["prot"]:
        r["info"] = f"Grund {struct.unpack('<H', body[:2])[0]}"
    elif sub in (13, 14):
        if r["prot"]:
            r["info"] = f"geschützt (PMF), {len(f)} Byte – Inhalt verschlüsselt"
        elif len(body) >= 2:
            cat, act = body[0], body[1]
            name = CAT.get(cat, f"Kategorie {cat}")
            if cat == 10:
                name = WNM.get(act, f"WNM {act}")
                if act == 7 and len(body) >= 7:
                    mode, timer, valid = body[3], struct.unpack("<H", body[4:6])[0], body[6]
                    flags_s = [n for bit, n in ((1, "Kandidatenliste"), (2, "abgekürzt"),
                                                (4, "Trennung angekündigt"), (8, "BSS endet"),
                                                (16, "ESS endet")) if mode & bit]
                    nb = sum(1 for _ in _neighbors(body[7:]))
                    name += f" ({', '.join(flags_s) or 'ohne Flags'}; Timer {timer}, gültig {valid}; {nb} Kandidaten)"
                elif act == 8 and len(body) >= 4:
                    st = body[3]
                    name += f" (Status {st} {BTM_STATUS.get(st, '')})"
            elif cat == 5:
                name = RM.get(act, f"RM {act}")
            else:
                name += f" Aktion {act}"
            r["info"] = name
    return r


def _neighbors(b):
    p = 0
    while p + 2 <= len(b):
        if b[p] == 52:
            yield b[p + 2:p + 2 + b[p + 1]]
        p += 2 + b[p + 1]


# ---------- Auswertung ----------

def analyse(path, macs, alle=False, probe=False, out=sys.stdout):
    macs = {norm_mac(m) for m in macs}
    auto = not macs
    clients = {}   # MAC -> {"caps": {...}, "quelle": str, "n": {...}}
    events = []
    n_frames = n_mgmt = 0
    t0 = None
    for ts, link, data in frames(path):
        n_frames += 1
        f, sig = dot11(link, data)
        if not f:
            continue
        r = parse(f)
        if not r:
            continue
        n_mgmt += 1
        if t0 is None:
            t0 = ts
        sub = r["sub"]
        if auto and sub in (0, 2):
            macs.add(r["a2"])
        cl = r["a2"] if r["a2"] in macs else (r["a1"] if r["a1"] in macs else None)
        if cl is None and probe and sub == 4 and r["a1"] == "FF:FF:FF:FF:FF:FF":
            cl = r["a2"]
        if cl is None:
            continue
        von = "Client" if r["a2"] == cl else "AP " + r["a2"]
        c = clients.setdefault(cl, {"caps": None, "quelle": "", "n": {}})
        key = ("Client→AP " if von == "Client" else "AP→Client ") + r["name"]
        c["n"][key] = c["n"].get(key, 0) + 1
        if "caps" in r and von == "Client" and (c["caps"] is None or sub in (0, 2)):
            if sub in (0, 2) or c["quelle"] in ("", "Probe Request"):
                c["caps"], c["quelle"] = r["caps"], r["name"]
        if sub in (4, 5) and not alle:
            continue
        if sub in (8,):
            continue
        txt = r["name"]
        if "info" in r:
            txt = r["info"] if sub in (13, 14) else f"{txt}: {r['info']}"
        if "status" in r:
            txt += f" Status {r['status']}"
        if "caps" in r and von == "Client" and sub in (0, 2, 4):
            txt += f" [{caps_str(r['caps'])}" + (f", SSID {r['caps']['ssid']}" if r["caps"]["ssid"] else "") + "]"
        if r["retry"]:
            txt += " (Wiederholung)"
        events.append((ts, cl, von, txt, sig))

    print(f"{path}: {n_frames} Frames, {n_mgmt} Management-Frames", file=out)
    for ts, cl, von, txt, sig in events:
        zeit = time.strftime("%H:%M:%S", time.localtime(ts)) + f".{int(ts * 1000) % 1000:03d}"
        s = f" {sig} dBm" if sig is not None else ""
        print(f"  {zeit} {cl} {von:>20}{s}: {txt}", file=out)
    print("\nZusammenfassung je Client:", file=out)
    if not clients:
        print("  keine Frames der Clients (MAC richtig? Kanal des APs? Filter des Sniffers?)", file=out)
    for cl in sorted(clients):
        c = clients[cl]
        print(f"  {cl}:", file=out)
        if c["caps"]:
            print(f"    {caps_str(c['caps'])} (aus {c['quelle']})", file=out)
            if c["caps"]["btm"] is False:
                print("    → meldet KEIN BSS Transition: Der AP schickt keine Wechselvorschläge; nur die Trennschwelle "
                      "(drop/join/hold) bringt ihn zum Wechsel (DW2.5)", file=out)
        else:
            print("    Fähigkeiten unbekannt: kein (Re)Association/Probe Request im Mitschnitt – WLAN am Client aus "
                  "und wieder an, während der Sniffer läuft", file=out)
        for k in sorted(c["n"]):
            print(f"    {c['n'][k]:5d} × {k}", file=out)
    return clients


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("pcap")
    ap.add_argument("--mac", action="append", default=[])
    ap.add_argument("--alle", action="store_true")
    ap.add_argument("--probe", action="store_true")
    a = ap.parse_args()
    analyse(a.pcap, a.mac, a.alle, a.probe)


if __name__ == "__main__":
    main()
