#!/usr/bin/env python3
"""Schaltbare SSID (D64) aus Home Assistant: ein- und ausschalten, Zustand abfragen.

Spricht die RouterOS-API des CAPsMAN (Port 8728, unverschlüsselt, D47) mit dem Lese-User aus
capsmanApi (Gruppe read,api,test) und braucht nur die Python-Standardbibliothek; es läuft also im
Container von Home Assistant ohne Zusatzpakete. Anleitung: docs/home-assistant.md.

  cfm_ssid.py guest on       # startet cfm-ssid-guest-on auf dem CAPsMAN (APs ~3 s ohne WLAN)
  cfm_ssid.py guest off      # startet cfm-ssid-guest-off
  cfm_ssid.py guest state    # gibt "on" oder "off" aus
  cfm_ssid.py guest until    # Zeitpunkt des Auto-Aus (ISO 8601), leer ohne Auto-Aus

Zugangsdaten in einer JSON-Datei (Standard: cfm_ssid.json neben diesem Skript, sonst --config):
  {"host": "<MGMT-IP des CAPsMAN>", "user": "homeassistant", "password": "…"}   (optional "port")

Der Zustand kommt aus den Provisioning-Regeln des CAPsMAN (enthält eine Regel die Konfiguration
cfm-<key> bzw. cfm-<key>-<Band>g, sendet die SSID), der Ablauf aus <cfm>/ssid-<key>.txt. Die
globale Variable cfmSsid<key> taugt dafür nicht: Die API zeigt /system/script/environment nur Usern
mit write und policy, und ein über die API gestartetes Skript ändert sie nicht (Labor 7.24.5).

Exit-Code 0 bei Erfolg, sonst 1 mit Meldung auf stderr (Home Assistant protokolliert sie).
"""
import argparse
import datetime
import json
import os
import re
import socket
import sys


class ApiError(Exception):
    pass


class Api:
    """Minimaler Client für die RouterOS-API (Login ab RouterOS 6.43)."""

    def __init__(self, host, port, user, password, timeout):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.cmd("/login", name=user, password=password)

    @staticmethod
    def _enc_len(n):
        if n < 0x80:
            return bytes([n])
        if n < 0x4000:
            return (n | 0x8000).to_bytes(2, "big")
        if n < 0x200000:
            return (n | 0xC00000).to_bytes(3, "big")
        if n < 0x10000000:
            return (n | 0xE0000000).to_bytes(4, "big")
        return b"\xf0" + n.to_bytes(4, "big")

    def _read(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ApiError("Verbindung vom Router geschlossen")
            buf += chunk
        return buf

    def _read_word(self):
        c = self._read(1)[0]
        if c < 0x80:
            n = c
        elif c < 0xC0:
            n = ((c & 0x3F) << 8) | self._read(1)[0]
        elif c < 0xE0:
            n = ((c & 0x1F) << 16) | int.from_bytes(self._read(2), "big")
        elif c < 0xF0:
            n = ((c & 0x0F) << 24) | int.from_bytes(self._read(3), "big")
        else:
            n = int.from_bytes(self._read(4), "big")
        return self._read(n).decode("utf-8", "replace")

    def cmd(self, path, *queries, **attrs):
        """Befehl senden; liefert die !re-Zeilen als Dicts, wirft ApiError bei !trap/!fatal."""
        words = [path] + ["=%s=%s" % (k.replace("_", "-"), v) for k, v in attrs.items()]
        words += list(queries)
        for w in words:
            b = w.encode("utf-8")
            self.sock.sendall(self._enc_len(len(b)) + b)
        self.sock.sendall(b"\x00")
        rows, err = [], None
        while True:
            sentence = []
            while True:
                w = self._read_word()
                if w == "":
                    break
                sentence.append(w)
            if not sentence:
                continue
            kind = sentence[0]
            fields = dict(w[1:].split("=", 1) for w in sentence[1:] if w.startswith("=") and "=" in w[1:])
            if kind == "!re":
                rows.append(fields)
            elif kind == "!trap":
                err = fields.get("message", "unbekannter Fehler")
            elif kind == "!fatal":
                raise ApiError(" ".join(sentence[1:]) or "fatal")
            elif kind == "!done":
                if err:
                    raise ApiError(err)
                return rows


def load_config(path):
    try:
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        raise ApiError("Zugangsdaten %s nicht lesbar: %s" % (path, e))
    for k in ("host", "user", "password"):
        if not cfg.get(k):
            raise ApiError("%s: \"%s\" fehlt" % (path, k))
    return cfg


def require_scripts(api, key):
    # Fehlen die Skripte, ist das Gerät nicht (mehr) der CAPsMAN oder die SSID nicht schaltbar
    names = {r.get("name") for r in api.cmd("/system/script/print", "=.proplist=name")}
    for act in ("on", "off"):
        if "cfm-ssid-%s-%s" % (key, act) not in names:
            raise ApiError("Skript cfm-ssid-%s-%s fehlt – Gerät ist nicht der CAPsMAN oder die SSID "
                           "hat kein \"switch\" in wifi.rsc" % (key, act))


def state(api, key):
    require_scripts(api, key)
    pat = re.compile(r"^cfm-%s(-[0-9]+g)?$" % re.escape(key))
    for r in api.cmd("/interface/wifi/provisioning/print", "=.proplist=comment,slave-configurations"):
        if not r.get("comment", "").startswith("cfm:wprov:"):
            continue
        if any(pat.match(c) for c in r.get("slave-configurations", "").split(",")):
            return "on"
    return "off"


def until(api, key):
    # Ablauf aus <cfm>/ssid-<key>.txt ("on <Unix-Zeit>"); <cfm> ist cfm oder flash/cfm
    if state(api, key) != "on":
        return ""
    for d in ("cfm", "flash/cfm"):
        rows = api.cmd("/file/print", "?name=%s/ssid-%s.txt" % (d, key), "=.proplist=contents")
        if rows:
            m = re.match(r"^on ([0-9]+)", rows[0].get("contents", ""))
            if m:
                return datetime.datetime.fromtimestamp(int(m.group(1)), datetime.timezone.utc).astimezone().isoformat()
    return ""


def main():
    ap = argparse.ArgumentParser(description="Schaltbare SSID (D64) per RouterOS-API")
    ap.add_argument("key", help="Schlüssel der SSID in wifi.rsc (z.B. guest)")
    ap.add_argument("action", choices=("on", "off", "state", "until"))
    ap.add_argument("--config", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "cfm_ssid.json"))
    ap.add_argument("--timeout", type=float, default=20, help="Sekunden je Verbindung/Antwort")
    a = ap.parse_args()
    if not re.match(r"^[a-z0-9]+$", a.key):
        ap.error("Schlüssel nur aus Kleinbuchstaben und Ziffern")
    try:
        cfg = load_config(a.config)
        api = Api(cfg["host"], int(cfg.get("port", 8728)), cfg["user"], cfg["password"], a.timeout)
        if a.action in ("on", "off"):
            require_scripts(api, a.key)
            # .run kehrt erst zurück, wenn das Skript durch ist (Regeln, Zustand, Neuprovisionieren)
            api.cmd("/system/script/run", number="cfm-ssid-%s-%s" % (a.key, a.action))
        elif a.action == "state":
            print(state(api, a.key))
        else:
            print(until(api, a.key))
    except (ApiError, OSError) as e:
        print("cfm_ssid: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
