#!/usr/bin/env python3
"""Befristeter Spiegel für das eingebaute RouterOS-Update (TODO 38, D63).

Geräte ohne Internet aktualisieren sich mit `$cfmUpgrade ver=<x.y.z> host=… via=mirror mirror=<IP>`:
Der Agent leitet upgrade.mikrotik.com per statischem DNS-Eintrag auf diesen Rechner um, stellt das
eingebaute Update auf HTTP und ruft /system/package/update/install auf. Das kommt auch mit 16 MB
Flash zurecht (RouterOS lädt dann in den RAM).

Der Spiegel liefert NEWESTa7.<Kanal> mit der festen Version (ein Update kann nur auf die angebotene
Version gehen) und holt alles andere (CHANGELOG, Pakete, packages.csv) bei Bedarf von
https://upgrade.mikrotik.com in den Zwischenspeicher. Ohne Internet hier vorher die Dateien unter
<dir>/routeros/<ver>/ ablegen. Pakete sind von MikroTik signiert; geprüft wird zusätzlich die
NPK-Kennung.

  sudo tools/upgrade-mirror.py 7.24.5                # Port 80 auf allen Adressen
  tools/upgrade-mirror.py 7.24.5 --port 8080         # ohne root (nur mit Weiterleitung auf 80)
  tools/upgrade-mirror.py 7.24.5 --prefetch arm64:routeros,wifi-qcom mmips:routeros

Läuft auf Port 80 schon ein Webserver, legt --export die Dateien statisch dort ab und beendet sich
(danach wieder löschen):
  tools/upgrade-mirror.py 7.24.5 --prefetch mmips:routeros,dude
  sudo tools/upgrade-mirror.py 7.24.5 --dir ~/.cache/cfm-upgrade-mirror --offline --export /var/www/html

Geräte erreichen den Spiegel auf Port 80 der angegebenen Adresse (RouterOS fragt immer Port 80).
"""
import argparse
import http.server
import os
import re
import shutil
import sys
import time
import urllib.request

UPSTREAM = "https://upgrade.mikrotik.com/routeros/"
NPK_MAGIC = b"\x1e\xf1\xd0\xba"
VER_RE = r"\d+\.\d+(?:\.\d+)?(?:(?:alpha|beta|rc)\d+)?"


def channel(ver):
    return "testing" if re.search(r"(alpha|beta|rc)", ver) else "stable"


def pkg_name(pkg, ver, arch):
    # x86 heißt ohne Suffix (routeros-7.24.5.npk), alle anderen mit (routeros-7.24.5-arm64.npk)
    return f"{pkg}-{ver}.npk" if arch in ("x86", "x86_64", "") else f"{pkg}-{ver}-{arch}.npk"


class Mirror:
    def __init__(self, ver, cache, offline=False):
        self.ver, self.cache, self.offline = ver, cache, offline
        self.newest = f"{ver} {int(time.time())}\n".encode()

    def local(self, rel):
        return os.path.join(self.cache, "routeros", rel)

    def fetch(self, rel):
        """Datei aus dem Zwischenspeicher oder von MikroTik; None, wenn es sie nicht gibt."""
        path = self.local(rel)
        if os.path.isfile(path):
            return path
        if self.offline:
            return None
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".part"
        try:
            with urllib.request.urlopen(UPSTREAM + rel, timeout=60) as r, open(tmp, "wb") as f:
                while True:
                    b = r.read(1 << 20)
                    if not b:
                        break
                    f.write(b)
        except Exception as e:                              # noqa: BLE001 - jede Störung = nicht da
            print(f"  upstream {rel}: {e}", file=sys.stderr)
            if os.path.exists(tmp):
                os.remove(tmp)
            return None
        if rel.endswith(".npk"):
            with open(tmp, "rb") as f:
                if f.read(4) != NPK_MAGIC:
                    print(f"  {rel}: keine NPK-Kennung, verworfen", file=sys.stderr)
                    os.remove(tmp)
                    return None
        os.replace(tmp, path)
        print(f"  geladen: {rel} ({os.path.getsize(path)} Bytes)", file=sys.stderr)
        return path


def make_handler(m):
    class Handler(http.server.BaseHTTPRequestHandler):
        def send_body(self, data=None, path=None, head=False):
            self.send_response(200)
            size = len(data) if data is not None else os.path.getsize(path)
            self.send_header("Content-Length", str(size))
            self.send_header("Content-Type", "application/octet-stream")
            self.end_headers()
            if head:
                return
            if data is not None:
                self.wfile.write(data)
            else:
                with open(path, "rb") as f:
                    while True:
                        b = f.read(1 << 20)
                        if not b:
                            break
                        self.wfile.write(b)

        def handle_req(self, head):
            rel = self.path.split("?", 1)[0]
            if not rel.startswith("/routeros/"):
                return self.send_error(404)
            rel = rel[len("/routeros/"):]
            if rel == f"NEWESTa7.{channel(m.ver)}":
                return self.send_body(data=m.newest, head=head)
            # nur die feste Version ausliefern; packages.csv auch für die installierte (Größenrechnung)
            mm = re.fullmatch(rf"({VER_RE})/([A-Za-z0-9._-]+)", rel)
            if not mm or (mm.group(1) != m.ver and mm.group(2) != "packages.csv"):
                return self.send_error(404)
            path = m.fetch(rel)
            if not path:
                return self.send_error(404)
            return self.send_body(path=path, head=head)

        def do_GET(self):
            self.handle_req(False)

        def do_HEAD(self):
            self.handle_req(True)

        def log_message(self, fmt, *args):
            print(f"{self.client_address[0]} {fmt % args}", file=sys.stderr)

    return Handler


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("version", help="Zielversion, z.B. 7.24.5 oder 7.25beta5")
    ap.add_argument("--port", type=int, default=80)
    ap.add_argument("--bind", default="0.0.0.0")
    ap.add_argument("--dir", default=os.path.expanduser("~/.cache/cfm-upgrade-mirror"),
                    help="Zwischenspeicher (Standard ~/.cache/cfm-upgrade-mirror)")
    ap.add_argument("--offline", action="store_true", help="nichts von MikroTik laden, nur den Zwischenspeicher")
    ap.add_argument("--prefetch", nargs="*", default=[], metavar="ARCH:PAKET,…",
                    help="vorab laden, z.B. arm64:routeros,wifi-qcom x86:routeros")
    ap.add_argument("--export", metavar="DOCROOT",
                    help="statt zu lauschen: Spiegel nach DOCROOT/routeros/ schreiben (vorhandener Webserver auf Port 80)")
    a = ap.parse_args(argv)
    if not re.fullmatch(VER_RE, a.version):
        ap.error(f"Version {a.version!r} nicht erkannt")
    m = Mirror(a.version, a.dir, a.offline)
    m.fetch(f"{a.version}/CHANGELOG")
    for spec in a.prefetch:
        arch, _, pkgs = spec.partition(":")
        for p in filter(None, pkgs.split(",")):
            if not m.fetch(f"{a.version}/{pkg_name(p, a.version, arch)}"):
                print(f"Vorab laden fehlgeschlagen: {p} ({arch})", file=sys.stderr)
                return 1
    if a.export:
        dst = os.path.join(a.export, "routeros")
        os.makedirs(os.path.join(dst, a.version), exist_ok=True)
        with open(os.path.join(dst, f"NEWESTa7.{channel(a.version)}"), "wb") as f:
            f.write(m.newest)
        src = m.local(a.version)
        n = 0
        for fn in sorted(os.listdir(src)) if os.path.isdir(src) else []:
            if not fn.endswith(".part"):
                shutil.copyfile(os.path.join(src, fn), os.path.join(dst, a.version, fn))
                n += 1
        for root, dirs, files in os.walk(dst):           # für den Webserver lesbar
            for x in dirs:
                os.chmod(os.path.join(root, x), 0o755)
            for x in files:
                os.chmod(os.path.join(root, x), 0o644)
        print(f"Spiegel für RouterOS {a.version} nach {dst} geschrieben ({n} Dateien + "
              f"NEWESTa7.{channel(a.version)}) - nach dem Update wieder löschen", file=sys.stderr)
        return 0
    srv = http.server.ThreadingHTTPServer((a.bind, a.port), make_handler(m))
    print(f"Spiegel für RouterOS {a.version} (Kanal {channel(a.version)}) auf {a.bind}:{a.port}, "
          f"Zwischenspeicher {a.dir} - Ende mit Strg+C", file=sys.stderr)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
