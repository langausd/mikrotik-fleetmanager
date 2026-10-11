#!/usr/bin/env python3
"""Empfänger für cfm-Benachrichtigungen (D66) im Labor oder zum Ausprobieren.

    notify-sink.py <port> <datei> [--bind 127.0.0.1]

Nimmt POSTs an, schreibt je Meldung eine JSON-Zeile (UTF-8) in <datei> und antwortet 200.
Ungültiges JSON landet als {"invalid": …}; der Content-Type steht im Feld "_ct".
Im CHR-Labor erreichen die VMs den Host als 10.0.2.2 (QEMU-User-Net).
"""
import argparse
import http.server
import json

ap = argparse.ArgumentParser()
ap.add_argument("port", type=int)
ap.add_argument("out")
ap.add_argument("--bind", default="127.0.0.1")
args = ap.parse_args()


class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        try:
            d = json.loads(body.decode("utf-8"))
        except Exception as e:  # noqa: BLE001 - alles mitschreiben, was ankommt
            d = {"invalid": body.decode("utf-8", "replace"), "err": str(e)}
        d["_ct"] = self.headers.get("Content-Type", "")
        with open(args.out, "a", encoding="utf-8") as f:
            f.write(json.dumps(d, ensure_ascii=False) + "\n")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *a):
        pass


http.server.HTTPServer((args.bind, args.port), H).serve_forever()
