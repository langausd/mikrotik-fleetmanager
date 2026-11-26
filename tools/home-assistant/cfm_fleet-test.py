#!/usr/bin/env python3
"""Tests für cfm_fleet.py (TODO 99) ohne Gerät: API-Client durch eine Attrappe ersetzt."""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cfm_fleet as cf  # noqa: E402

FLEET_A = {"t": 1790000000, "manager": "cm1",
           "geraete": {"ap1": {"stumm": True, "seit": 1789990000, "ring": 1, "soll": 42, "ist": 41,
                               "apply": "ok", "ros": "7.25.2", "rosNeu": "7.25.3"},
                       "cm1": {"stumm": False, "ring": 2, "soll": 42, "ist": 42, "apply": "ok", "ros": "7.25.2",
                               "lizenz": "ok"}},
           "meldungen": [{"key": "stumm:ap1", "text": "stumm: kein Status", "seit": 1789990000},
                         {"key": "bpdu:sw1", "text": "Port ether5 von BPDU-Guard gesperrt – Profil vport", "seit": 1789995000}]}
FLEET_B = dict(FLEET_A, t=1780000000, manager="cm2")


class FakeApi:
    files = {}

    def __init__(self, host, port, user, password, timeout):
        if host not in self.files:
            raise OSError("keine Verbindung")
        self.host = host

    def cmd(self, path, *q, **kw):
        assert path == "/system/script/print" and q[0] == "?name=cfm-fleet", (path, q)
        c = self.files[self.host]
        return [{"source": c}] if c is not None else []


class FleetTest(unittest.TestCase):
    def setUp(self):
        self.orig = cf.Api
        cf.Api = FakeApi
        self.tmp = tempfile.mkdtemp()
        self.cfg = os.path.join(self.tmp, "cfm_ssid.json")
        with open(self.cfg, "w") as f:
            json.dump({"host": "192.168.10.5", "user": "homeassistant", "password": "x",
                       "managers": ["10.0.0.2", "10.0.0.3"]}, f)

    def tearDown(self):
        cf.Api = self.orig

    def run_(self, *args):
        out, err = io.StringIO(), io.StringIO()
        sys.argv = ["cfm_fleet.py", "--config", self.cfg] + list(args)
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = cf.main()
        return rc, out.getvalue(), err.getvalue()

    def test_neueste_gewinnt(self):
        # Backup (10.0.0.3) mit älterem Stand
        FakeApi.files = {"10.0.0.2": json.dumps(FLEET_A), "10.0.0.3": json.dumps(FLEET_B)}
        rc, out, _ = self.run_()
        self.assertEqual(rc, 0)
        j = json.loads(out)
        self.assertEqual((j["manager"], j["quelle"], j["anzahl"]), ("cm1", "10.0.0.2", 2))
        self.assertEqual(j["stand"], "2026-09-21T14:13:20+00:00")
        self.assertEqual(j["geraete"]["ap1"]["seit"], "2026-09-21T11:26:40+00:00")
        self.assertNotIn("seit", j["geraete"]["cm1"])
        self.assertEqual(j["meldungen"][1]["text"], "Port ether5 von BPDU-Guard gesperrt – Profil vport")

    def test_primary_aus(self):
        FakeApi.files = {"10.0.0.3": json.dumps(FLEET_B)}
        rc, out, _ = self.run_("10.0.0.2,10.0.0.3")
        self.assertEqual(json.loads(out)["quelle"], "10.0.0.3")

    def test_keiner(self):
        FakeApi.files = {"10.0.0.2": None}
        rc, out, err = self.run_()
        self.assertEqual(rc, 1)
        self.assertIn("10.0.0.2: kein Skript cfm-fleet", err)
        self.assertIn("10.0.0.3: keine Verbindung", err)


if __name__ == "__main__":
    unittest.main()
