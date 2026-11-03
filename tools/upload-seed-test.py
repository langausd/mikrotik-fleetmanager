#!/usr/bin/env python3
"""Tests für tools/upload-seed.sh gegen einen nachgebauten SFTP-Server (ein lokales Verzeichnis als Manager):
Feature-Module (DG4.6) nur hochladen, wenn die Site-Daten sie nutzen, nicht gebrauchte auf dem Manager entfernen."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODULE = sorted(f for f in os.listdir(ROOT / "cfm/work/lib") if f.count(".") == 2 and f.endswith(".rsc"))

# Nachbau von sftp: Befehle aus -b <datei>, -b - oder stdin; Pfade relativ zu FAKE_SFTP_ROOT. Im Batch bricht
# ein Fehler ab (außer mit "-" davor), "ls -1 <dir>" nennt den Pfad samt Verzeichnis wie RouterOS.
FAKE_SFTP = textwrap.dedent('''\
    #!/usr/bin/env python3
    import os, shutil, sys
    root = os.environ["FAKE_SFTP_ROOT"]
    args, batch, i = sys.argv[1:], None, 0
    while i < len(args):
        if args[i] in ("-b", "-P", "-i", "-o"):
            if args[i] == "-b":
                batch = args[i + 1]
            i += 2
        else:
            i += 1
    text = sys.stdin.read() if batch in (None, "-") else open(batch).read()
    log = open(os.environ["FAKE_SFTP_LOG"], "a")
    def rp(p):
        return os.path.join(root, p.lstrip("/"))
    rc = 0
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        print("sftp> " + line)
        log.write(line + "\\n")
        ign = line.startswith("-")
        cmd, *a = line.lstrip("-").split()
        try:
            if cmd == "pwd":
                print("Remote working directory: /")
            elif cmd == "ls":
                d = a[-1]
                for n in sorted(os.listdir(rp(d))):
                    print(d.rstrip("/") + "/" + n)
            elif cmd == "get":
                shutil.copy(rp(a[0]), a[1])
            elif cmd == "put":
                os.makedirs(os.path.dirname(rp(a[1])), exist_ok=True)
                shutil.copy(a[0], rp(a[1]))
            elif cmd == "mkdir":
                if os.path.isdir(rp(a[0])):   # wie RouterOS (upload-seed.sh blendet genau das aus)
                    print('remote mkdir "' + a[0] + '": Unknown status', file=sys.stderr)
                    rc = 0 if ign else 1
                    continue
                os.mkdir(rp(a[0]))
            elif cmd == "rm":
                os.remove(rp(a[0]))
            else:
                raise OSError("unbekannt: " + cmd)
        except OSError as e:
            print(line + ": " + str(e), file=sys.stderr)
            if not ign:
                rc = 1
                if batch is not None:
                    break
    sys.exit(rc)
''')


class UploadSeed(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.mgr = os.path.join(self.tmp, "mgr")
        os.makedirs(self.mgr)
        bin_ = os.path.join(self.tmp, "bin")
        os.makedirs(bin_)
        with open(os.path.join(bin_, "sftp"), "w") as fh:
            fh.write(FAKE_SFTP)
        os.chmod(os.path.join(bin_, "sftp"), 0o755)
        self.log = os.path.join(self.tmp, "sftp.log")
        self.env = dict(os.environ, PATH=bin_ + os.pathsep + os.environ["PATH"], FAKE_SFTP_ROOT=self.mgr,
                        FAKE_SFTP_LOG=self.log)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def upload(self, *args):
        r = subprocess.run([str(ROOT / "tools/upload-seed.sh"), "admin@manager", *args], env=self.env,
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r.stdout + r.stderr

    def lib(self):
        d = os.path.join(self.mgr, "cfm/work/lib")
        return sorted(f for f in os.listdir(d) if f in MODULE)

    def site(self, name, text):
        p = os.path.join(self.mgr, "cfm/work", name)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)

    def test_erstes_aufsetzen_ohne_site_daten_alle(self):
        # ohne Site-Daten auf dem Manager und ohne --site: im Zweifel alle Module
        out = self.upload()
        self.assertIn("keine Site-Daten auf dem Manager", out)
        self.assertEqual(self.lib(), MODULE)

    def test_vorlage_ohne_features(self):
        out = self.upload("--site")
        self.assertIn("Feature-Module nicht hochgeladen", out)
        self.assertEqual(self.lib(), ["capsman.reprov.rsc"])
        # Framework-Code kommt trotzdem
        self.assertTrue(os.path.isfile(os.path.join(self.mgr, "cfm/work/lib/lib.rsc")))
        self.assertTrue(os.path.isfile(os.path.join(self.mgr, "cfm/work/roles/router.rsc")))

    def test_site_daten_des_managers_entscheiden(self):
        self.upload("--all-features", "--site")
        self.assertEqual(self.lib(), MODULE)
        # auf dem Manager (z.B. im cfm-Editor) eingeschaltet: SNMP und DNS mit Selbstbedienung
        self.site("global.rsc", ':global cfmG {"users"={"netadmin"="full"};"snmp"={"from"={"192.168.10.5"}}}\n')
        self.site("dns.rsc", ':global cfmDns {"self"={"zones"={"lan"}}}\n')
        out = self.upload()
        self.assertEqual(self.lib(), ["base.snmp.rsc", "capsman.reprov.rsc", "router.dns.rsc", "router.dnsreq.rsc"])
        self.assertIn("Feature-Module auf dem Manager entfernt:", out)
        self.assertIn(" base.bond", out)
        # die Site-Daten selbst bleiben ohne --site unangetastet
        with open(os.path.join(self.mgr, "cfm/work/dns.rsc"), encoding="utf-8") as fh:
            self.assertIn('"self"', fh.read())

    def test_overlay_mit_site(self):
        ov = os.path.join(self.tmp, "site")
        os.makedirs(os.path.join(ov, "hosts"))
        shutil.copy(ROOT / "cfm/work/vlans.rsc", ov)
        with open(os.path.join(ov, "vlans.rsc"), "a", encoding="utf-8") as fh:
            fh.write(':set ($cfmVlans->"30"->"isolate") "yes"\n')
        with open(os.path.join(ov, "authorized_keys.netadmin"), "w") as fh:
            fh.write("ssh-ed25519 AAAA x\n")
        self.upload("--overlay", ov, "--site")
        self.assertEqual(self.lib(), ["base.iso.rsc", "base.sshkeys.rsc", "capsman.reprov.rsc"])
        # später ohne --site: zählen die Daten des Managers (dort liegen sie jetzt)
        self.upload("--overlay", ov)
        self.assertEqual(self.lib(), ["base.iso.rsc", "base.sshkeys.rsc", "capsman.reprov.rsc"])

    def test_all_features(self):
        self.upload("--site")
        out = self.upload("--all-features")
        self.assertNotIn("nicht hochgeladen (die Site", out)
        self.assertEqual(self.lib(), MODULE)


if __name__ == "__main__":
    unittest.main()
