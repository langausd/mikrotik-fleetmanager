#!/usr/bin/env python3
"""Flottenzustand von cfm (TODO 99) für Home Assistant: Skript cfm-fleet des Primary-Managers per API lesen.

Der Primary-Manager schreibt den Zustand als JSON in den Quelltext des Skripts cfm-fleet (nie ausgeführt; eine Datei
liefert /file/print über die API nur bis 4 KB) im Manager-Tick, wenn sich etwas ändert: je Gerät erreichbar oder stumm,
Release (Ring, Soll, Ist), Ergebnis des letzten Apply, RouterOS-Version, neuere Version und Zustand eines Updates,
beim Manager als CHR die Lizenz; dazu die offenen Meldungen (dieselben Zustände wie die Benachrichtigungen, DU4.1).
Spricht die RouterOS-API (Port 8728, unverschlüsselt) mit demselben Lese-User wie cfm_ssid.py (capsmanApi, Gruppe
read,api,test; den legt cfm auch auf den Managern an). Nutzt dessen API-Client und Zugangsdatei; beide Dateien liegen
nebeneinander. Nur Python-Standardbibliothek. Anleitung: docs/home-assistant.md, Abschnitt 9.

  cfm_fleet.py 192.168.10.2,192.168.10.3    # Manager der Reihe nach (Primary zuerst, wie managers in global.rsc)
  cfm_fleet.py                              # Manager aus "managers" in cfm_ssid.json

Es gibt keine gemeinsame Adresse der Manager: Das Skript fragt alle genannten und nimmt den neuesten Stand (Feld t),
damit ein alter Stand (z.B. eines früheren Primary) nicht gewinnt. Nicht erreichbare Manager überspringt es; erst wenn
keiner antwortet, endet es mit Fehler.

Ausgabe (eine Zeile JSON, für einen command_line-Sensor mit json_attributes):
  {"anzahl": <offene Meldungen>, "stand": "<ISO 8601>", "manager": "<Name>", "quelle": "<Adresse>",
   "geraete": {"ap1": {"stumm": false, "ring": 1, "soll": 42, "ist": 42, "apply": "ok", "ros": "7.25.2", …}, …},
   "meldungen": [{"key": "apply:ap1", "text": "…", "seit": "<ISO 8601>"}, …]}
Zeiten sind die Uhr des Managers (Unixzeit, wie $cfmStatus), hier als ISO 8601 in UTC.

Exit-Code 0 bei Erfolg, sonst 1 mit Meldung auf stderr (Home Assistant protokolliert sie).
"""
import argparse
import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cfm_ssid import Api, ApiError  # noqa: E402


def iso(t):
    try:
        return datetime.datetime.fromtimestamp(int(t), datetime.timezone.utc).isoformat()
    except (TypeError, ValueError, OverflowError, OSError):
        return None


def load_config(path):
    """Wie cfm_ssid.load_config, aber ohne Pflichtfeld host (das ist der CAPsMAN)."""
    try:
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        raise ApiError("Zugangsdaten %s nicht lesbar: %s" % (path, e))
    for k in ("user", "password"):
        if not cfg.get(k):
            raise ApiError("%s: \"%s\" fehlt" % (path, k))
    return cfg


def read_fleet(api):
    """Quelltext des Skripts cfm-fleet -> dict oder None, wenn es fehlt."""
    rows = api.cmd("/system/script/print", "?name=cfm-fleet", "=.proplist=source")
    if not rows:
        return None
    try:
        return json.loads(rows[0].get("source", ""))
    except ValueError as e:
        raise ApiError("Skript cfm-fleet ist kein JSON: %s" % e)


def ausgabe(fleet, quelle):
    ger = {}
    for n, g in (fleet.get("geraete") or {}).items():
        g = dict(g)
        if "seit" in g:
            g["seit"] = iso(g["seit"])
        ger[n] = g
    mel = []
    for m in fleet.get("meldungen") or []:
        m = dict(m)
        m["seit"] = iso(m.get("seit"))
        mel.append(m)
    return {"anzahl": len(mel), "stand": iso(fleet.get("t")), "manager": fleet.get("manager"), "quelle": quelle,
            "geraete": ger, "meldungen": mel}


def main():
    ap = argparse.ArgumentParser(description="Flottenzustand von cfm (Skript cfm-fleet) per RouterOS-API")
    ap.add_argument("hosts", nargs="?", help="MGMT-Adressen der Manager (Adresse[:Port]), durch Komma getrennt, Primary zuerst")
    ap.add_argument("--config", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "cfm_ssid.json"))
    ap.add_argument("--timeout", type=float, default=10, help="Sekunden je Verbindung/Antwort")
    a = ap.parse_args()
    try:
        cfg = load_config(a.config)
        hosts = [h.strip() for h in (a.hosts or ",".join(cfg.get("managers") or [])).split(",") if h.strip()]
        if not hosts:
            raise ApiError("keine Manager: als Argument oder \"managers\" in %s" % a.config)
        best, quelle, fehler = None, None, []
        for h in hosts:
            addr, _, port = h.partition(":")
            try:
                f = read_fleet(Api(addr, int(port or cfg.get("port", 8728)), cfg["user"], cfg["password"], a.timeout))
            except (ApiError, OSError) as e:
                fehler.append("%s: %s" % (h, e))
                continue
            if f is None:
                fehler.append("%s: kein Skript cfm-fleet" % h)
            elif best is None or int(f.get("t") or 0) > int(best.get("t") or 0):
                best, quelle = f, h
        if best is None:
            raise ApiError("; ".join(fehler))
        print(json.dumps(ausgabe(best, quelle), ensure_ascii=False))
    except (ApiError, OSError) as e:
        print("cfm_fleet: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
