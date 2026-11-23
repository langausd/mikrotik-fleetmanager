#!/usr/bin/env python3
"""cfm-cert-signer – signiert die CSRs der cfm-Geräte (DS3.6) und stößt die Manager an.

Läuft auf einem Linux-Host (z.B. dem acme-dns-Server), per systemd-Timer alle paar Minuten:

  1. Je Manager per SSH als User cfm-cert (nur ssh,read) alle state/<gerät>/tls.csr lesen.
  2. Jeden neuen CSR prüfen (Signatur, CN unter einer erlaubten Domain, SAN nur DNS:<CN>) und signieren:
     mode "certbot" = Let's Encrypt per DNS-01 (certbot --csr mit acme-dns-Hook), mode "testca" = eigene
     Test-CA mit openssl (Labor). Das Ergebnis (Zertifikat + Kette) liegt in <outdir>/<CN>.pem; ein
     HTTP-Dienst liefert outdir aus (nur für die Manager freigeben).
  3. Gab es neue Zertifikate, auf dem Manager /system script run cfm-cert-pull starten.

Schlüssel sieht der Signer nie: Die Geräte erzeugen sie selbst. Ein CSR, der schon signiert wurde (gleicher
öffentlicher Schlüssel), wird nicht noch einmal signiert; die Geräte erneuern selbst rechtzeitig (tls.renew).

  cfm-cert-signer.py -c /etc/cfm-cert-signer.json [--dry-run] [--once-cn <CN>]
  cfm-cert-signer.py -c … --cnames     # CNAME-Zeilen für alle bekannten CNs (für die DNS-Zone)

Konfiguration (JSON):
  {"managers": [{"host": "192.0.2.1", "user": "cfm-cert", "key": "/root/.ssh/cfm-cert", "path": "cfm"}],
   "domains": ["site.example"],            # erlaubte Suffixe (CN = <name>.<domain>)
   "outdir": "/srv/cfm-certs", "state": "/var/lib/cfm-cert-signer/state.json",
   "mode": "certbot",
   "certbot": {"hook": "/etc/letsencrypt/acme-dns/acme-dns-auth.py", "account": "cfm-mikrotik",
               "staging": false, "cname_target": "<uuid>.acme-dns.example"},
   "testca": {"cert": "ca/int.pem", "key": "ca/int.key", "chain": "ca/int.pem", "days": 20}}
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time

CSR_RE = re.compile(r"-----BEGIN CERTIFICATE REQUEST-----.*?-----END CERTIFICATE REQUEST-----", re.S)


def log(msg):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def run(cmd, inp=None, env=None, timeout=300):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True, env=env, timeout=timeout)


def ssh(m, command, timeout=120):
    cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=accept-new",
           "-o", "LogLevel=ERROR",
           "-p", str(m.get("port", 22))]
    if m.get("key"):
        cmd += ["-i", m["key"]]
    if m.get("known_hosts"):
        cmd += ["-o", "UserKnownHostsFile=" + m["known_hosts"]]
    cmd += ["%s@%s" % (m.get("user", "cfm-cert"), m["host"]), command]
    return run(cmd, timeout=timeout)


def read_csrs(m):
    """-> {gerät: csr_pem} vom Manager (state/<gerät>/tls.csr)."""
    base = m.get("path", "cfm")
    rx = "^" + base + "/state/[^/]+/tls.csr\\$"
    cmd = (':foreach f in=[/file/find where name~"%s"] do={ :put ("##CFM " . [/file/get $f name]); '
           ':put [/file/get $f contents] }' % rx)
    r = ssh(m, cmd)
    if r.returncode != 0:
        raise RuntimeError("SSH zu %s: %s" % (m["host"], (r.stderr or r.stdout).strip()[:300]))
    out = {}
    cur = None
    buf = []
    for line in r.stdout.replace("\r", "").split("\n") + ["##CFM -"]:
        if line.startswith("##CFM "):
            if cur:
                mm = CSR_RE.search("\n".join(buf))
                if mm:
                    out[cur] = mm.group(0) + "\n"
            name = line[6:].strip()
            parts = name.split("/")
            cur = parts[-2] if len(parts) >= 3 else None
            buf = []
        else:
            buf.append(line)
    return out


def csr_info(pem):
    """-> (cn, [dns-sans], pubkey_sha256) oder Fehler."""
    with tempfile.NamedTemporaryFile("w", suffix=".csr", delete=False) as f:
        f.write(pem)
        fn = f.name
    try:
        r = run(["openssl", "req", "-in", fn, "-noout", "-verify", "-subject", "-text"])
        if r.returncode != 0 or "verify OK" not in (r.stdout + r.stderr):
            raise ValueError("CSR-Signatur ungültig")
        m = re.search(r"subject=.*?CN\s*=\s*([^,/\n]+)", r.stdout)
        if not m:
            raise ValueError("CSR ohne CN")
        cn = m.group(1).strip().lower()
        sans = [s.lower() for s in re.findall(r"DNS:([^,\s]+)", r.stdout)]
        pk = run(["openssl", "req", "-in", fn, "-noout", "-pubkey"]).stdout
        return cn, sans, hashlib.sha256(pk.encode()).hexdigest()
    finally:
        os.unlink(fn)


def cert_pubkey(pem_file):
    r = run(["openssl", "x509", "-in", pem_file, "-noout", "-pubkey"])
    return hashlib.sha256(r.stdout.encode()).hexdigest() if r.returncode == 0 else ""


def sign_testca(cfg, cn, csr_file, out_full):
    t = cfg["testca"]
    with tempfile.TemporaryDirectory() as td:
        ext = os.path.join(td, "ext")
        with open(ext, "w") as f:
            f.write("basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\n"
                    "extendedKeyUsage=serverAuth\nsubjectAltName=DNS:%s\n" % cn)
        crt = os.path.join(td, "crt")
        r = run(["openssl", "x509", "-req", "-in", csr_file, "-CA", t["cert"], "-CAkey", t["key"],
                 "-CAcreateserial", "-CAserial", os.path.join(td, "srl"), "-days", str(t.get("days", 20)),
                 "-out", crt, "-extfile", ext])
        if r.returncode != 0:
            raise RuntimeError("openssl: " + r.stderr.strip()[:300])
        with open(out_full, "w") as o:
            o.write(open(crt).read())
            o.write(open(t.get("chain", t["cert"])).read())


def sign_certbot(cfg, cn, csr_file, out_full):
    c = cfg["certbot"]
    with tempfile.TemporaryDirectory() as td:
        cmd = ["certbot", "certonly", "--non-interactive", "--agree-tos", "--csr", csr_file,
               "--manual", "--preferred-challenges", "dns", "--manual-auth-hook", c["hook"],
               "--cert-path", os.path.join(td, "cert.pem"), "--chain-path", os.path.join(td, "chain.pem"),
               "--fullchain-path", os.path.join(td, "full.pem")]
        if c.get("staging"):
            cmd.append("--staging")
        if c.get("email"):
            cmd += ["-m", c["email"]]
        env = dict(os.environ)
        if c.get("account"):
            env["ACMEDNS_ACCOUNT"] = c["account"]
        r = run(cmd, env=env, timeout=600)
        full = os.path.join(td, "full.pem")
        if r.returncode != 0 or not os.path.exists(full):
            raise RuntimeError("certbot: " + (r.stderr or r.stdout).strip()[-500:])
        with open(out_full, "w") as o:
            o.write(open(full).read())


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-c", "--config", required=True)
    ap.add_argument("--dry-run", action="store_true", help="nur lesen und prüfen, nichts signieren")
    ap.add_argument("--cnames", action="store_true", help="CNAME-Zeilen für alle bekannten CNs ausgeben")
    ap.add_argument("--force", metavar="CN", help="diesen CN neu signieren, auch wenn der CSR bekannt ist")
    a = ap.parse_args()
    cfg = json.load(open(a.config))
    outdir = cfg.get("outdir", "/srv/cfm-certs")
    stf = cfg.get("state", os.path.join(outdir, ".state.json"))
    try:
        state = json.load(open(stf))
    except (OSError, ValueError):
        state = {}
    domains = [d.lower().strip(".") for d in cfg.get("domains", [])]
    sign = sign_certbot if cfg.get("mode", "certbot") == "certbot" else sign_testca

    if a.cnames:
        tgt = cfg.get("certbot", {}).get("cname_target", "<ziel>")
        for cn in sorted(state):
            print("_acme-challenge.%s.  CNAME  %s." % (cn, tgt.strip(".")))
        return 0

    os.makedirs(outdir, exist_ok=True)
    rc = 0
    for m in cfg["managers"]:
        try:
            csrs = read_csrs(m)
        except Exception as e:  # noqa: BLE001 - ein Manager darf die anderen nicht aufhalten
            log("FEHLER %s" % e)
            rc = 1
            continue
        new = 0
        for dev, pem in sorted(csrs.items()):
            try:
                cn, sans, pk = csr_info(pem)
                if not any(cn.endswith("." + d) for d in domains):
                    raise ValueError("CN %s liegt unter keiner erlaubten Domain %s" % (cn, domains))
                if any(s != cn for s in sans):
                    raise ValueError("CSR %s nennt weitere Namen %s" % (cn, sans))
                out = os.path.join(outdir, cn + ".pem")
                if state.get(cn, {}).get("pk") == pk and os.path.exists(out) and a.force != cn \
                        and cert_pubkey(out) == pk:
                    continue
                if a.dry_run:
                    log("%s (%s): neuer CSR - würde signieren" % (dev, cn))
                    continue
                log("%s (%s): signiere (%s)" % (dev, cn, cfg.get("mode", "certbot")))
                with tempfile.NamedTemporaryFile("w", suffix=".csr", delete=False) as f:
                    f.write(pem)
                    cf = f.name
                tmp = out + ".tmp"
                try:
                    sign(cfg, cn, cf, tmp)
                finally:
                    os.unlink(cf)
                if cert_pubkey(tmp) != pk:
                    os.unlink(tmp)
                    raise RuntimeError("Zertifikat passt nicht zum CSR")
                os.chmod(tmp, 0o644)
                os.replace(tmp, out)
                state[cn] = {"pk": pk, "dev": dev, "mgr": m["host"], "t": int(time.time())}
                new += 1
                log("%s (%s): Zertifikat bereit" % (dev, cn))
            except Exception as e:  # noqa: BLE001
                log("FEHLER %s: %s" % (dev, e))
                rc = 1
        if new and not a.dry_run:
            tmpst = stf + ".tmp"
            os.makedirs(os.path.dirname(stf) or ".", exist_ok=True)
            json.dump(state, open(tmpst, "w"), indent=1, sort_keys=True)
            os.replace(tmpst, stf)
            r = ssh(m, "/system script run cfm-cert-pull", timeout=300)
            out = " | ".join(x.strip() for x in (r.stdout + r.stderr).replace("\r", "").splitlines() if x.strip())
            log("%s: cfm-cert-pull -> %s" % (m["host"], out[-400:]))
            if r.returncode != 0:
                rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
