#!/usr/bin/env python3
"""Umschaltbarer Port (DP1.4, DP1.4.1) aus Home Assistant: normal/alt schalten, Zustand abfragen.

Spricht die RouterOS-API des Geräts mit dem Port (Port 8728, unverschlüsselt) mit demselben Lese-User wie
cfm_ssid.py (capsmanApi, Gruppe read,api,test). Nutzt dessen API-Client und Zugangsdatei; beide Dateien liegen
nebeneinander. Nur Python-Standardbibliothek. Anleitung: docs/home-assistant.md, Abschnitt 8.

  cfm_port.py <host> <name> normal   # startet cfm-port-<name>-normal auf dem Gerät
  cfm_port.py <host> <name> alt      # startet cfm-port-<name>-alt
  cfm_port.py <host> <name> state    # gibt "normal" oder "alt" aus

<host> ist die MGMT-Adresse des Geräts (z.B. 192.168.10.30), <name> der Name aus portSwitch im Hostfile (z.B.
dock). Zugangsdaten aus cfm_ssid.json neben diesem Skript (sonst --config); dessen "host" gilt hier nicht.

Die Skripte setzen den Zustand fest (kein Umschalten wie -toggle am Taster): Ein wiederholter Aufruf ändert nichts
am Ergebnis, trennt aber den Link erneut für 3 s. Der Zustand kommt aus <cfm>/port-<name>.txt, die die Skripte
nach jedem Wechsel schreiben (fehlt sie, ist der Port nie umgeschaltet worden: normal).

Exit-Code 0 bei Erfolg, sonst 1 mit Meldung auf stderr (Home Assistant protokolliert sie).
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cfm_ssid import Api, ApiError, load_config  # noqa: E402


def require_scripts(api, name):
    names = {r.get("name") for r in api.cmd("/system/script/print", "=.proplist=name")}
    for act in ("normal", "alt"):
        if "cfm-port-%s-%s" % (name, act) not in names:
            raise ApiError("Skript cfm-port-%s-%s fehlt – das Gerät hat keinen umschaltbaren Port \"%s\" "
                           "(portSwitch im Hostfile)" % (name, act, name))


def state(api, name):
    require_scripts(api, name)
    # <cfm> ist cfm oder flash/cfm
    for d in ("cfm", "flash/cfm"):
        rows = api.cmd("/file/print", "?name=%s/port-%s.txt" % (d, name), "=.proplist=contents")
        if rows:
            return "alt" if rows[0].get("contents", "").strip() == "alt" else "normal"
    return "normal"


def main():
    ap = argparse.ArgumentParser(description="Umschaltbarer Port (DP1.4) per RouterOS-API")
    ap.add_argument("host", help="MGMT-Adresse des Geräts")
    ap.add_argument("name", help="Name des Ports aus portSwitch (z.B. dock)")
    ap.add_argument("action", choices=("normal", "alt", "state"))
    ap.add_argument("--config", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "cfm_ssid.json"))
    ap.add_argument("--timeout", type=float, default=20, help="Sekunden je Verbindung/Antwort")
    a = ap.parse_args()
    if not re.match(r"^[a-z0-9]+$", a.name):
        ap.error("Name nur aus Kleinbuchstaben und Ziffern")
    try:
        cfg = load_config(a.config)
        api = Api(a.host, int(cfg.get("port", 8728)), cfg["user"], cfg["password"], a.timeout)
        if a.action == "state":
            print(state(api, a.name))
        else:
            require_scripts(api, a.name)
            # .run kehrt erst zurück, wenn das Skript durch ist (Port umgestellt, Link 3 s getrennt, Meldung)
            api.cmd("/system/script/run", number="cfm-port-%s-%s" % (a.name, a.action))
    except (ApiError, OSError) as e:
        print("cfm_port: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
