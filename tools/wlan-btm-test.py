#!/usr/bin/env python3
"""Tests für tools/wlan-btm.py: Fähigkeiten (BTM-Bit, 802.11k, FT, AKM) je Fassung, WNM-Frames, Kapselungen 105/127/TZSP."""
import importlib.util
import io
import os
import struct
import tempfile
import unittest
import warnings

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("wlanbtm", os.path.join(HERE, "wlan-btm.py"))
wb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wb)

CL = bytes.fromhex("02000000aa01")
CL2 = bytes.fromhex("02000000bb02")
AP = bytes.fromhex("02000000cc03")
BC = b"\xff" * 6


def hdr(sub, a1, a2, a3, prot=False):
    fc = (sub << 4) | (0x4000 if prot else 0)
    return struct.pack("<HH", fc, 0) + a1 + a2 + a3 + b"\x00\x00"


def ie(i, b):
    return bytes([i, len(b)]) + b


def rsn(*akms):
    b = struct.pack("<H", 1) + b"\x00\x0f\xac\x04" + struct.pack("<H", 1) + b"\x00\x0f\xac\x04"
    b += struct.pack("<H", len(akms)) + b"".join(b"\x00\x0f\xac" + bytes([a]) for a in akms)
    return b + b"\x8c\x00"


def assoc(cl, btm=True, ft=True, rrm=True, re=False, ssid=b"Haus"):
    el = ie(0, ssid) + ie(48, rsn(8, 9) if ft else rsn(8))
    if rrm:
        el += ie(70, b"\x73\x00\x00\x00\x00")
    if ft:
        el += ie(54, b"\x12\x34\x01")
    el += ie(127, bytes([0x04, 0x00, 0x08 if btm else 0x00, 0x00]))
    fixed = b"\x11\x00\x0a\x00" + (AP if re else b"")
    return hdr(2 if re else 0, AP, cl, AP) + fixed + el


def btm_req(cl):
    nb = ie(52, AP + b"\x00\x00\x00\x00" + b"\x7d\x24\x09")
    return hdr(13, cl, AP, AP) + bytes([10, 7, 1, 0x05]) + struct.pack("<H", 10) + bytes([255]) + nb


def btm_resp(cl, st):
    return hdr(13, AP, cl, AP) + bytes([10, 8, 1, st, 0])


def pcap(frames, link=105):
    b = struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, link)
    for k, f in enumerate(frames):
        b += struct.pack("<IIII", 1795300000 + k, 0, len(f), len(f)) + f
    return b


def radiotap(f, sig=-67, fcs=True):
    # present: Flags (Bit 1), dBm Antenna Signal (Bit 5); Länge 8 + 1 + 1 = 10
    rt = struct.pack("<BBHI", 0, 0, 10, (1 << 1) | (1 << 5)) + bytes([0x10 if fcs else 0]) + struct.pack("b", sig)
    return rt + f + (b"\xde\xad\xbe\xef" if fcs else b"")


def tzsp(f):
    t = bytes([1, 0]) + struct.pack(">H", 18) + b"\x01" + f
    udp = struct.pack(">HHHH", 40000, 37008, 8 + len(t), 0) + t
    ip = bytes([0x45, 0]) + struct.pack(">H", 20 + len(udp)) + b"\x00" * 4 + bytes([64, 17]) + b"\x00\x00" + \
        bytes([10, 0, 0, 1, 10, 0, 0, 2])
    return b"\x00" * 12 + b"\x08\x00" + ip + udp


class T(unittest.TestCase):
    def setUp(self):
        warnings.simplefilter("ignore", ResourceWarning)  # frames() aus pcap-ziele.py schließt die Datei nicht

    def run_on(self, data, **kw):
        with tempfile.NamedTemporaryFile(suffix=".pcap", delete=False) as fh:
            fh.write(data)
        try:
            buf = io.StringIO()
            res = wb.analyse(fh.name, kw.pop("macs", []), out=buf, **kw)
            return res, buf.getvalue()
        finally:
            os.unlink(fh.name)

    def test_caps_und_btm(self):
        res, out = self.run_on(pcap([assoc(CL), btm_req(CL), btm_resp(CL, 0)]), macs=["02:00:00:00:aa:01"])
        c = res["02:00:00:00:AA:01"]["caps"]
        self.assertTrue(c["btm"] and c["rrm"] and c["ft"])
        self.assertEqual(c["akm"], ["SAE", "FT-SAE"])
        self.assertIn("BTM Request (Kandidatenliste, Trennung angekündigt; Timer 10, gültig 255; 1 Kandidaten)", out)
        self.assertIn("BTM Response (Status 0 Accept)", out)

    def test_ohne_btm_bit(self):
        res, out = self.run_on(pcap([assoc(CL, btm=False, ft=False, rrm=False, re=True)]), macs=["020000-00aa01"])
        c = res["02:00:00:00:AA:01"]["caps"]
        self.assertIs(c["btm"], False)
        self.assertFalse(c["ft"] or c["rrm"])
        self.assertIn("meldet KEIN BSS Transition", out)
        self.assertIn("Reassociation Request", out)

    def test_geschuetzt(self):
        f = hdr(13, CL, AP, AP, prot=True) + b"\x00" * 40
        res, out = self.run_on(pcap([f]), macs=[wb.mac_str(CL)])
        self.assertIn("geschützt (PMF)", out)
        self.assertIn("AP→Client Action", "\n".join(res[wb.mac_str(CL)]["n"]))

    def test_radiotap_signal_fcs(self):
        res, out = self.run_on(pcap([radiotap(assoc(CL)), radiotap(btm_resp(CL, 7), sig=-81)], link=127),
                               macs=[wb.mac_str(CL)])
        self.assertTrue(res[wb.mac_str(CL)]["caps"]["btm"])
        self.assertIn("-81 dBm", out)
        self.assertIn("Status 7 Reject: no suitable candidates", out)

    def test_tzsp(self):
        res, _ = self.run_on(pcap([tzsp(assoc(CL, btm=False))], link=1), macs=[wb.mac_str(CL)])
        self.assertIs(res[wb.mac_str(CL)]["caps"]["btm"], False)

    def test_auto_und_probe(self):
        probe = hdr(4, BC, CL2, BC) + ie(0, b"") + ie(127, b"\x00\x00\x08")
        res, out = self.run_on(pcap([assoc(CL), probe]))
        self.assertIn(wb.mac_str(CL), res)
        self.assertNotIn(wb.mac_str(CL2), res)
        res, _ = self.run_on(pcap([assoc(CL), probe]), probe=True)
        self.assertTrue(res[wb.mac_str(CL2)]["caps"]["btm"])
        self.assertEqual(res[wb.mac_str(CL2)]["quelle"], "Probe Request")

    def test_assoc_schlaegt_probe(self):
        probe = hdr(4, BC, CL, BC) + ie(127, b"\x00\x00\x00")
        res, _ = self.run_on(pcap([probe, assoc(CL)]), macs=[wb.mac_str(CL)])
        self.assertTrue(res[wb.mac_str(CL)]["caps"]["btm"])
        self.assertEqual(res[wb.mac_str(CL)]["quelle"], "Association Request")

    def probe(self, ssid, btm, ext=None):
        ext = ext if ext is not None else bytes([0x04, 0x00, 0x08 if btm else 0x00, 0x00])
        return hdr(4, BC, CL, BC) + ie(0, ssid) + ie(70, b"\x73\x00\x00\x00\x00") + ie(127, ext)

    def test_fassungen_getrennt_ohne_assoc(self):
        # Befund 2026-11-22: gezielte Probes für die eigene SSID ohne BTM-Bit, Wildcard-Probes mit
        fr = [self.probe(b"Haus", False), self.probe(b"", True), self.probe(b"Haus", False), self.probe(b"", True)]
        res, out = self.run_on(pcap(fr), macs=[wb.mac_str(CL)])
        fa = res[wb.mac_str(CL)]["fassungen"]
        self.assertEqual(len(fa), 2)
        self.assertEqual(sorted(f["n"] for f in fa.values()), [2, 2])
        self.assertIn("Probe Request gezielt, SSID Haus: BTM (802.11v) NEIN, 802.11k ja (2×", out)
        self.assertIn("Probe Request Wildcard, ohne SSID: BTM (802.11v) ja, 802.11k ja (2×", out)
        self.assertIn("in manchen Probe Requests ja, in anderen nein – maßgeblich ist der Association Request", out)
        self.assertNotIn("meldet KEIN BSS Transition", out)
        self.assertNotIn("FT nein", out)   # FT nicht aus Probe Requests ableiten

    def test_assoc_je_ssid(self):
        fr = [self.probe(b"Haus", False), assoc(CL, ssid=b"Haus"), assoc(CL, btm=False, ft=False, ssid=b"Gast")]
        res, out = self.run_on(pcap(fr), macs=[wb.mac_str(CL)])
        self.assertIn("Association Request, SSID Gast: BTM (802.11v) NEIN, 802.11k ja, FT nein", out)
        self.assertIn("Association Request, SSID Haus: BTM (802.11v) ja, 802.11k ja, FT ja, AKM SAE/FT-SAE", out)
        self.assertIn("→ SSID Haus: meldet BSS Transition", out)
        self.assertIn("→ SSID Gast: meldet KEIN BSS Transition", out)
        # Association Request vor den Probe Requests
        self.assertLess(out.index("Association Request, SSID Gast"), out.index("Probe Request gezielt, SSID Haus"))

    def test_assoc_wechselnd(self):
        res, out = self.run_on(pcap([assoc(CL), assoc(CL, btm=False)]), macs=[wb.mac_str(CL)])
        self.assertIn("nicht in jedem Association Request", out)

    def test_ext_caps_kurz(self):
        res, out = self.run_on(pcap([self.probe(b"", None, ext=b"\x04\x00")]), macs=[wb.mac_str(CL)])
        self.assertIn("NEIN (Extended Capabilities nur 2 Byte)", out)


if __name__ == "__main__":
    unittest.main()
