#!/usr/bin/env python3
"""pcap-ziele.py – Internet-Ziele von Geräten aus einem Mitschnitt (Fritz!Box, /tool/sniffer).

Wofür: Ein Gerät soll ins IoT-VLAN, braucht aber die Cloud. Bevor es dort per allow-Liste (D39, D76)
freigegeben wird, muss man wissen, welche Namen und Ports es anspricht. Das Skript liest einen
Mitschnitt (pcap oder pcapng, z.B. von http://fritz.box/html/capture.html) und zeigt je Gerät (MAC):
DNS-Anfragen, TLS-Servernamen (SNI), HTTP-Host, Verbindungen ins Internet und im LAN – jeweils mit
dem Namen aus den DNS-Antworten – und schlägt am Ende eine allow-Liste für global.rsc vor.

  tools/pcap-ziele.py mitschnitt.eth                       # Übersicht aller Geräte
  tools/pcap-ziele.py mitschnitt.eth --mac 02:00:00:00:00:AA --leases site/leases.rsc
  tools/pcap-ziele.py a.eth b.pcapng --mac … --mac … --liste cloud

Ohne Fremdpakete (nur Python 3). QUIC (udp/443) ist verschlüsselt: dort hilft nur der DNS-Name.
"""
import argparse
import ipaddress
import re
import struct
import sys
import time
from collections import defaultdict

PRIVATE = [ipaddress.ip_network(n) for n in (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16", "100.64.0.0/10",
    "127.0.0.0/8", "224.0.0.0/4", "255.255.255.255/32", "0.0.0.0/32",
    "fc00::/7", "fe80::/10", "ff00::/8", "::1/128", "::/128")]


def is_private(ip):
    a = ipaddress.ip_address(ip)
    return any(a in n for n in PRIVATE)


def mac_str(b):
    return ":".join("%02X" % x for x in b)


# ---------- Dateiformate ----------

def read_pcap(f, hdr):
    e = "<" if hdr[:4] in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1") else ">"
    nano = hdr[:4] in (b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d")
    link = struct.unpack(e + "I", hdr[20:24])[0] & 0xFFFF
    while True:
        rh = f.read(16)
        if len(rh) < 16:
            return
        ts, tf, incl, _ = struct.unpack(e + "IIII", rh)
        yield ts + tf / (1e9 if nano else 1e6), link, f.read(incl)


def read_pcapng(f, first):
    links = []
    e = "<"
    bh = first
    while len(bh) == 12:
        bt = struct.unpack(e + "I", bh[:4])[0]
        if bt == 0x0A0D0D0A:
            e = "<" if bh[8:12] == b"\x4d\x3c\x2b\x1a" else ">"
            links = []
        blen = struct.unpack(e + "I", bh[4:8])[0]
        if blen < 12:
            return
        body = bh[8:12] + f.read(blen - 12)
        body = body[:blen - 12]
        if bt == 1:
            # Zeitauflösung aus if_tsresol (Option 9), Standard Mikrosekunden; /tool/sniffer schreibt 9 = ns
            div, p = 1e6, 8
            while p + 4 <= len(body):
                code, olen = struct.unpack(e + "HH", body[p:p + 4])
                if code == 0:
                    break
                if code == 9 and olen >= 1:
                    v = body[p + 4]
                    div = float(2 ** (v & 0x7F)) if v & 0x80 else 10.0 ** v
                p += 4 + (olen + 3) // 4 * 4
            links.append((struct.unpack(e + "H", body[:2])[0], div))
        elif bt == 6:
            iid, th, tl, cap, _ = struct.unpack(e + "IIIII", body[:20])
            link, div = links[iid] if iid < len(links) else (1, 1e6)
            yield ((th << 32) | tl) / div, link, body[20:20 + cap]
        elif bt == 3:
            yield 0.0, links[0][0] if links else 1, body[4:]
        bh = f.read(12)


def frames(path):
    """Pakete einer Datei, stückweise gelesen (Mitschnitte vom ganzen LAN werden schnell GB groß)"""
    f = open(path, "rb")
    hdr = f.read(24)
    if hdr[:4] == b"\x0a\x0d\x0d\x0a":
        f.seek(0)
        return read_pcapng(f, f.read(12))
    if hdr[:4] in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\xc3\xd4", b"\xa1\xb2\x3c\x4d"):
        return read_pcap(f, hdr)
    sys.exit(f"{path}: weder pcap noch pcapng")


# ---------- Schichten ----------

def l2(link, b):
    """-> (src_mac, dst_mac, ethertype, payload) oder None"""
    if link == 1:  # Ethernet
        if len(b) < 14:
            return None
        dst, src, et = b[0:6], b[6:12], struct.unpack(">H", b[12:14])[0]
        p = b[14:]
        while et in (0x8100, 0x88A8) and len(p) >= 4:
            et, p = struct.unpack(">H", p[2:4])[0], p[4:]
        return mac_str(src), mac_str(dst), et, p
    if link == 113:  # Linux cooked
        return mac_str(b[6:12]), "", struct.unpack(">H", b[14:16])[0], b[16:]
    if link == 276:  # Linux cooked v2
        return mac_str(b[12:18]), "", struct.unpack(">H", b[0:2])[0], b[20:]
    if link in (101, 228, 229, 12):  # rohes IP
        v = b[0] >> 4 if b else 0
        return "", "", 0x0800 if v == 4 else 0x86DD, b
    if link in (105, 127):  # 802.11 (mit Radiotap)
        if link == 127:
            b = b[struct.unpack("<H", b[2:4])[0]:]
        if len(b) < 24:
            return None
        fc = struct.unpack("<H", b[0:2])[0]
        if (fc >> 2) & 3 != 2 or fc & 0x4000:  # nur unverschlüsselte Datenframes
            return None
        tods, fromds = fc >> 8 & 1, fc >> 9 & 1
        a1, a2, a3 = b[4:10], b[10:16], b[16:22]
        src = a3 if fromds and not tods else a2
        dst = a3 if tods and not fromds else a1
        h = 24 + (2 if fc >> 4 & 8 else 0) + (6 if tods and fromds else 0)
        p = b[h:]
        if p[:3] != b"\xaa\xaa\x03" or len(p) < 8:
            return None
        return mac_str(src), mac_str(dst), struct.unpack(">H", p[6:8])[0], p[8:]
    return None


def l3(et, p):
    """-> (src_ip, dst_ip, proto, l4payload) oder None"""
    if et == 0x0800 and len(p) >= 20:
        ihl = (p[0] & 15) * 4
        if (struct.unpack(">H", p[6:8])[0] & 0x1FFF) != 0:
            return None  # Folgefragment
        return (str(ipaddress.IPv4Address(p[12:16])), str(ipaddress.IPv4Address(p[16:20])), p[9],
                p[ihl:struct.unpack(">H", p[2:4])[0]] if struct.unpack(">H", p[2:4])[0] else p[ihl:])
    if et == 0x86DD and len(p) >= 40:
        nh, q = p[6], p[40:]
        while nh in (0, 43, 60) and len(q) >= 8:  # Hop-by-Hop, Routing, Destination
            nh, q = q[0], q[(q[1] + 1) * 8:]
        return str(ipaddress.IPv6Address(p[8:24])), str(ipaddress.IPv6Address(p[24:40])), nh, q
    return None


def dns_name(m, off, depth=0):
    labels = []
    while off < len(m) and depth < 20:
        n = m[off]
        if n == 0:
            return ".".join(labels), off + 1
        if n & 0xC0 == 0xC0:
            ptr = struct.unpack(">H", m[off:off + 2])[0] & 0x3FFF
            rest, _ = dns_name(m, ptr, depth + 1)
            if rest:
                labels.append(rest)
            return ".".join(labels), off + 2
        labels.append(m[off + 1:off + 1 + n].decode("ascii", "replace"))
        off += 1 + n
    return ".".join(labels), off


QTYPES = {1: "A", 28: "AAAA", 5: "CNAME", 65: "HTTPS", 64: "SVCB", 12: "PTR", 16: "TXT", 33: "SRV"}


def dns(m):
    """-> (is_response, [(qname, qtype)], [(owner, type, value)]) oder None"""
    if len(m) < 12:
        return None
    flags, qd, an = struct.unpack(">HHH", m[2:8])
    off, qs, ans = 12, [], []
    try:
        for _ in range(qd):
            n, off = dns_name(m, off)
            qs.append((n.lower(), QTYPES.get(struct.unpack(">H", m[off:off + 2])[0], "?")))
            off += 4
        for _ in range(an):
            n, off = dns_name(m, off)
            t, _, _, rl = struct.unpack(">HHIH", m[off:off + 10])
            off += 10
            rd = m[off:off + rl]
            if t == 1 and rl == 4:
                ans.append((n.lower(), "A", str(ipaddress.IPv4Address(rd))))
            elif t == 28 and rl == 16:
                ans.append((n.lower(), "AAAA", str(ipaddress.IPv6Address(rd))))
            elif t == 5:
                ans.append((n.lower(), "CNAME", dns_name(m, off)[0].lower()))
            off += rl
    except (struct.error, IndexError, ValueError):
        pass
    return bool(flags & 0x8000), qs, ans


def tls_sni(p):
    try:
        if len(p) < 43 or p[0] != 0x16 or p[5] != 0x01:
            return None
        off = 9 + 2 + 32
        off += 1 + p[off]
        off += 2 + struct.unpack(">H", p[off:off + 2])[0]
        off += 1 + p[off]
        end = off + 2 + struct.unpack(">H", p[off:off + 2])[0]
        off += 2
        while off + 4 <= min(end, len(p)):
            t, ln = struct.unpack(">HH", p[off:off + 4])
            if t == 0:
                nl = struct.unpack(">H", p[off + 7:off + 9])[0]
                return p[off + 9:off + 9 + nl].decode("ascii", "replace").lower()
            off += 4 + ln
    except (struct.error, IndexError):
        pass
    return None


def http_host(p):
    if not re.match(rb"^(GET|POST|PUT|HEAD|DELETE|OPTIONS|PATCH|CONNECT) ", p[:8]):
        return None
    m = re.search(rb"\r\n[Hh]ost:\s*([^\r\n:]+)", p[:2048])
    return m.group(1).decode("ascii", "replace").lower() if m else None


# ---------- Auswertung ----------

class Dev:
    def __init__(self):
        self.ips = set()
        self.pkts = 0
        self.t0 = self.t1 = None
        self.queries = defaultdict(int)       # (name, typ) -> Anzahl
        self.conns = defaultdict(lambda: [0, set()])  # (proto, ip, port) -> [Pakete, {Namen aus SNI/Host}]
        self.lan = defaultdict(int)           # (proto, ip, port) -> Pakete


def proto_port(proto, l4, outbound):
    if proto in (6, 17) and len(l4) >= 4:
        sp, dp = struct.unpack(">HH", l4[0:4])
        return ("tcp" if proto == 6 else "udp"), (dp if outbound else sp), l4
    return {1: "icmp", 58: "icmp6"}.get(proto, f"ip{proto}"), 0, b""


def load_leases(path):
    names = {}
    for m in re.finditer(r'"([^"]+)"=\{"mac"="([0-9A-Fa-f:]{17})"', open(path).read()):
        names.setdefault(m.group(2).upper(), m.group(1))
    return names


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="+", help="Mitschnitt(e), pcap oder pcapng")
    ap.add_argument("--mac", action="append", default=[], help="nur dieses Gerät (mehrfach möglich)")
    ap.add_argument("--leases", help="leases.rsc für Gerätenamen")
    ap.add_argument("--liste", default="cloud", help="Name der vorgeschlagenen allow-Liste (Standard: cloud)")
    a = ap.parse_args()
    want = {m.upper() for m in a.mac}
    names = load_leases(a.leases) if a.leases else {}

    devs = defaultdict(Dev)
    ip2names = defaultdict(set)
    for path in a.files:
        for ts, link, b in frames(path):
            r = l2(link, b)
            if not r:
                continue
            smac, _, et, p = r
            r = l3(et, p)
            if not r:
                continue
            sip, dip, proto, l4 = r
            # DNS-Antworten aller Geräte: IP -> Namen (auch der gefragte Name vor einem CNAME)
            if proto == 17 and len(l4) >= 8 and struct.unpack(">H", l4[0:2])[0] == 53:
                d = dns(l4[8:])
                if d and d[0]:
                    asked = d[1][0][0] if d[1] else None
                    for owner, t, val in d[2]:
                        if t in ("A", "AAAA"):
                            ip2names[val].add(owner)
                            if asked:
                                ip2names[val].add(asked)
            if not is_private(sip) and is_private(dip):
                continue  # Antworten aus dem Internet: nur für die DNS-Zuordnung oben
            key = smac or sip
            if want and key not in want:
                continue
            dv = devs[key]
            dv.pkts += 1
            dv.ips.add(sip)
            dv.t0 = ts if dv.t0 is None else min(dv.t0, ts)
            dv.t1 = ts if dv.t1 is None else max(dv.t1, ts)
            pr, port, seg = proto_port(proto, l4, True)
            if pr == "udp" and port == 53:
                d = dns(seg[8:])
                if d and not d[0]:
                    for q in d[1]:
                        dv.queries[q] += 1
            if is_private(dip):
                # Broadcast/Multicast, DHCP, mDNS und SSDP sagen nichts über Dienste im LAN
                if not dip.startswith(("224.", "239.", "255.", "ff")) and not (pr == "udp" and port in (67, 68, 5353, 1900)):
                    dv.lan[(pr, dip, port)] += 1
                continue
            c = dv.conns[(pr, dip, port)]
            c[0] += 1
            if pr == "tcp" and len(seg) >= 20:
                data = seg[(seg[12] >> 4) * 4:]
                n = tls_sni(data) or http_host(data)
                if n:
                    c[1].add(n)

    if not devs:
        sys.exit("keine passenden Pakete (MAC richtig? Mitschnitt von der richtigen Schnittstelle?)")

    def fmt_t(t):
        return time.strftime("%d.%m. %H:%M:%S", time.localtime(t)) if t else "?"

    order = sorted(devs, key=lambda k: -sum(c[0] for c in devs[k].conns.values()))
    if not want:
        print("Geräte im Mitschnitt (Pakete ins Internet / gesamt) – Einzelheiten mit --mac:")
        for k in order:
            dv = devs[k]
            print(f"  {k:17}  {names.get(k, ''):24} {sum(c[0] for c in dv.conns.values()):6} / {dv.pkts:<6}"
                  f" {', '.join(sorted(i for i in dv.ips if ':' not in i))}")
        return

    for k in order:
        dv = devs[k]
        print(f"\n== {k} {names.get(k, '')}  {', '.join(sorted(dv.ips))}")
        print(f"   {dv.pkts} Pakete, {fmt_t(dv.t0)} – {fmt_t(dv.t1)}")
        if dv.queries:
            print("DNS-Anfragen:")
            for (n, t), c in sorted(dv.queries.items()):
                print(f"  {n:50} {t:5} ×{c}")
        allow = defaultdict(set)   # Name oder IP -> {proto/port}
        if dv.conns:
            print("Ins Internet (Protokoll/Port, Ziel, Pakete, Namen):")
            for (pr, ip, port), (c, sni) in sorted(dv.conns.items(), key=lambda x: (x[0][0], x[0][2], x[0][1])):
                nm = sorted(sni) or sorted(ip2names.get(ip, ()))
                pp = f"{pr}/{port}" if port else pr
                print(f"  {pp:9} {ip:39} ×{c:<5} {', '.join(nm)}")
                if pr in ("tcp", "udp"):
                    # Vorschlag: SNI/Host vor dem gefragten DNS-Namen; ohne Namen die IP (kann wechseln!)
                    tgt = sorted(sni) or [n for n in sorted(ip2names.get(ip, ())) if (n, "A") in dv.queries or (n, "AAAA") in dv.queries] or [ip]
                    for t in tgt[:1]:
                        allow[t].add((pr, port))
        if dv.lan:
            print("Im LAN (Protokoll/Port, Ziel, Pakete):")
            for (pr, ip, port), c in sorted(dv.lan.items()):
                print(f"  {pr + '/' + str(port) if port else pr:9} {ip:39} ×{c}")
        if allow:
            print('Vorschlag für global.rsc (allow, D39/D76) – prüfen, nicht blind übernehmen:')
            ent = []
            for t in sorted(allow):
                byp = defaultdict(list)
                for pr, port in sorted(allow[t]):
                    byp[pr].append(str(port))
                for pr, ports in byp.items():
                    ent.append(f'"{t}:{pr}/{",".join(ports)}"')
            print(f'  "{a.liste}"={{{";".join(ent)}}}')
            if any(re.match(r"^[0-9a-f:.]+$", t) for t in allow):
                print("  Hinweis: Einträge mit IP statt Namen – die Adresse kann wechseln, Namen bevorzugen.")
            if any(pr == "udp" and port == 123 for v in allow.values() for pr, port in v):
                print("  Hinweis: udp/123 = NTP. Die Router sind NTP-Server für alle Zonen; nur freigeben, wenn das Gerät")
                print("           einen festen Zeitserver nutzt und ohne Zeit nicht arbeitet.")


if __name__ == "__main__":
    main()
