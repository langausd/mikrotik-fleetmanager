#!/usr/bin/env python3
"""Kleiner dyndns2-Server für das Labor (DR4.4): nimmt GET /nic/update?hostname=…&myip=… mit HTTP-Basic entgegen,
antwortet "good <ip>" und schreibt jede Anfrage als JSON-Zeile in eine Datei; GET /ip liefert die Adresse des
Aufrufers (Ersatz für api.ipify.org). Aufruf: ./fake-ddns.py <port> <datei> [user:passwort]"""
import base64
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(sys.argv[1]); DATEI = sys.argv[2]; AUTH = sys.argv[3] if len(sys.argv) > 3 else ""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, text):
        b = text.encode()
        self.send_response(code); self.send_header("Content-Type", "text/plain"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/ip":
            self.send(200, self.client_address[0] + "\n"); return
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        auth = ""
        h = self.headers.get("Authorization", "")
        if h.startswith("Basic "):
            try: auth = base64.b64decode(h[6:]).decode()
            except Exception: auth = "?"
        rec = {"t": int(time.time()), "path": u.path, "hostname": q.get("hostname", ""), "myip": q.get("myip", ""),
               "auth": auth, "ua": self.headers.get("User-Agent", ""), "from": self.client_address[0]}
        with open(DATEI, "a") as fh:
            fh.write(json.dumps(rec) + "\n")
        if AUTH and auth != AUTH:
            self.send(200, "badauth\n"); return
        self.send(200, "good " + q.get("myip", "") + "\n")


HTTPServer(("127.0.0.1", PORT), H).serve_forever()
