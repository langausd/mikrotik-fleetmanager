# Gast-WLAN aus Home Assistant schalten

Anleitung für die Einbindung in Home Assistant (HA). Sie setzt kein Wissen über cfm oder RouterOS
voraus. Die Netzseite richtet der Netz-Admin ein (Admin-Guide 6.7 und 6.8, Entscheidung D64), die
konkreten Werte bekommst du von ihm.

**Ergebnis:** ein Schalter `switch.gast_wlan` mit echtem Zustand und optional ein Sensor, der zeigt,
wann sich das Gast-WLAN selbst wieder abschaltet.

---

## 1. Wie es funktioniert

```
Home Assistant ──RouterOS-API, TCP 8728──▶ CAPsMAN (zentraler WLAN-Controller)
  command_line-Schalter                      ├─ Skript cfm-ssid-guest-on   ─┐ nimmt die SSID in die
  └─ cfm_ssid.py (Hilfsskript)               ├─ Skript cfm-ssid-guest-off  ─┘ Konfiguration der APs auf/heraus
                                             ├─ Provisioning-Regeln        ◀── Zustand (on/off)
                                             └─ Datei cfm/ssid-guest.txt   ◀── Zeitpunkt des Auto-Aus
```

* Der **CAPsMAN** ist der MikroTik, der alle Access Points (APs) steuert. Auf ihm legt cfm für jede
  schaltbare SSID zwei Skripte an: `cfm-ssid-<key>-on` und `cfm-ssid-<key>-off`. `<key>` ist der
  interne Name der SSID, beim Gast-WLAN `guest`.
* HA meldet sich über die **RouterOS-API** mit einem **Lese-User** an (Gruppe `read,api,test`). Der
  User darf nichts an der Konfiguration ändern, aber genau diese beiden Skripte starten. Die Skripte
  ändern dann die Konfiguration im eigenen Namen (`dont-require-permissions`).
* Das **Hilfsskript** `cfm_ssid.py` (nur Python-Standardbibliothek) spricht die API. Es startet die
  Skripte und liest den Zustand. Der Zustand kommt aus der tatsächlichen Konfiguration des CAPsMAN,
  nicht aus einer Merkvariable.
* **Auto-Aus:** Ist an der SSID ein Auto-Aus eingestellt (z.B. 50 h), schaltet der CAPsMAN sie nach
  dieser Zeit selbst ab. Er prüft alle 10 Minuten. HA muss dafür nichts tun.
* Der Zustand **bleibt** über Neustarts und Konfigurations-Releases erhalten. Ohne je geschaltet zu
  sein, gilt der Grundzustand, den der Netz-Admin festlegt (beim Gast-WLAN: aus).

**Wichtig fürs Verhalten:** Bei jedem Schalten senden alle APs etwa 3 Sekunden lang **gar kein**
WLAN, auch nicht die anderen SSIDs. Verbundene Geräte melden sich danach von selbst wieder an.
Deshalb nicht in kurzen Abständen schalten, keine Automationen, die hin- und herschalten können, und
keinen „Toggle bei jeder Statusänderung“.

## 2. Werte vom Netz-Admin

| Wert | Beispiel | Bedeutung |
|---|---|---|
| Host | `192.168.10.2` | MGMT-Adresse des CAPsMAN |
| Port | `8728` | RouterOS-API, unverschlüsselt |
| User | `homeassistant` | Lese-User aus `capsmanApi` |
| Passwort | – | dasselbe wie in der Integration „Mikrotik Router“, falls die schon eingerichtet ist (Admin-Guide 6.7) |
| Schlüssel | `guest` | `<key>` der SSID; die Skripte heißen `cfm-ssid-guest-on/-off` |
| SSID / Auto-Aus | `Gast` / `50h` | nur zur Anzeige |

Die Adresse von HA muss der Netz-Admin in `capsmanApi.from` eingetragen haben, sonst kommt keine
Verbindung zustande. Ist die Integration „Mikrotik Router“ für den CAPsMAN schon eingerichtet, sind
User und Freigabe bereits vorhanden.

## 3. Einbau

### 3.1 Dateien ablegen

Im Konfigurationsverzeichnis von HA (bei HA OS und HA Container: `/config`):

```
/config/cfm/cfm_ssid.py     ← aus diesem Repo: tools/home-assistant/cfm_ssid.py
/config/cfm/cfm_ssid.json   ← Zugangsdaten, siehe unten
```

`cfm_ssid.json`:

```json
{"host": "192.168.10.2", "port": 8728, "user": "homeassistant", "password": "…"}
```

Das Passwort steht nur in dieser Datei, also nicht in der `configuration.yaml` und nicht in der
Prozessliste. Leserechte nur für den Besitzer: `chmod 600 /config/cfm/cfm_ssid.json`. Sie landet in
den HA-Backups.

### 3.2 Von Hand testen

HA führt `command_line`-Befehle **im Container von Home Assistant** aus (bei HA OS im Container
`homeassistant`, nicht im Terminal-Add-on). Der Test muss deshalb dort laufen, damit Python-Version
und Netzweg stimmen, bei HA OS z.B. mit `docker exec -it homeassistant sh` (Add-on „Advanced SSH &
Web Terminal“ mit abgeschaltetem Schutzmodus):

```sh
python3 /config/cfm/cfm_ssid.py guest state    # → off
python3 /config/cfm/cfm_ssid.py guest on       # kein Output, Exit-Code 0; APs ~3 s ohne WLAN
python3 /config/cfm/cfm_ssid.py guest state    # → on
python3 /config/cfm/cfm_ssid.py guest until    # → 2026-10-05T21:49:29+02:00 (Auto-Aus)
python3 /config/cfm/cfm_ssid.py guest off
python3 /config/cfm/cfm_ssid.py guest until    # → leer (aus bzw. ohne Auto-Aus)
```

| Aufruf | Ausgabe (stdout) | Exit-Code |
|---|---|---|
| `<key> on` / `<key> off` | nichts; kehrt erst zurück, wenn der CAPsMAN fertig ist (~1–3 s) | 0, bei Fehler 1 |
| `<key> state` | `on` oder `off` | 0, bei Fehler 1 |
| `<key> until` | Zeitpunkt des Auto-Aus als ISO 8601 mit Zeitzone, leer wenn aus oder ohne Auto-Aus | 0, bei Fehler 1 |

Fehlermeldungen gehen nach stderr, beginnen mit `cfm_ssid:` und stehen dann auch im HA-Log
(Abschnitt 5). Optionen: `--config <Datei>` (andere Zugangsdatei), `--timeout <s>` (Standard 20).

### 3.3 `configuration.yaml`

```yaml
command_line:
  - switch:
      name: Gast-WLAN
      unique_id: cfm_ssid_guest
      icon: mdi:wifi
      command_on: python3 /config/cfm/cfm_ssid.py guest on
      command_off: python3 /config/cfm/cfm_ssid.py guest off
      command_state: python3 /config/cfm/cfm_ssid.py guest state
      value_template: '{{ value == "on" }}'
      # Fehler (Router nicht erreichbar o.ä.) → "nicht verfügbar" statt fälschlich "aus"
      availability: '{{ value in ["on", "off"] }}'
      command_timeout: 30
      scan_interval: 300

  # optional: wann sich das Gast-WLAN selbst abschaltet
  - sensor:
      name: Gast-WLAN Auto-Aus
      unique_id: cfm_ssid_guest_until
      icon: mdi:timer-off-outline
      command: python3 /config/cfm/cfm_ssid.py guest until
      device_class: timestamp
      # leer = aus oder kein Auto-Aus → "nicht verfügbar" statt einer Warnung im Log
      availability: '{{ value is not none and value | length > 0 }}'
      command_timeout: 30
      scan_interval: 3600
```

Danach HA einmal neu starten. Spätere Änderungen übernimmt die Aktion `command_line.reload`.

So verhält sich der Schalter:

* Nach dem Umlegen fragt HA den Zustand sofort neu ab. Der Schalter zeigt also nach 1–3 s den
  echten Zustand.
* Änderungen, die nicht von HA kommen (Auto-Aus, Schalten von Hand am Router), sieht HA erst bei der
  nächsten Abfrage, also nach höchstens `scan_interval`. Beim Auto-Aus kommen bis zu 10 min Prüftakt
  des CAPsMAN dazu.
* **Abfrageintervall nicht verkürzen:** Jede Abfrage ist eine eigene API-Anmeldung und schreibt zwei
  Zeilen ins Log des CAPsMAN („logged in … via api“, „logged out“). Mit dem HA-Standard von 30 s
  wären das rund 5.800 Zeilen am Tag, und der Speicher-Log (1.000 Zeilen) würde alle paar Stunden
  komplett überschrieben. Mit 300 s und 3600 s sind es knapp 630 Zeilen am Tag.

### 3.4 Sensor nach dem Schalten aktualisieren (optional)

Mit `scan_interval: 3600` zeigt der Auto-Aus-Sensor die neue Zeit sonst erst bis zu einer Stunde
nach dem Einschalten. Diese Automation holt sie sofort:

```yaml
automation:
  - alias: Gast-WLAN Auto-Aus aktualisieren
    triggers:
      - trigger: state
        entity_id: switch.gast_wlan
        to: ["on", "off"]
    actions:
      - action: homeassistant.update_entity
        target:
          entity_id: sensor.gast_wlan_auto_aus
```

### 3.5 Mehrere schaltbare SSIDs

Jede SSID mit Schalter hat eigene Skripte. Im Hilfsskript ändert sich nur der Schlüssel (`event`
statt `guest` usw.). Für jede SSID einen eigenen `switch`-Block anlegen, mit eigenem `name` und
`unique_id`.

## 4. Was nicht geht und warum

* **Zustand über die globale Variable `cfmSsidguest`** (in der Integration „Mikrotik Router“
  als „Environment variable sensors“): Der Lese-User sieht `/system/script/environment` gar nicht,
  RouterOS zeigt globale Variablen über die API nur Usern mit `write` **und** `policy`. Außerdem
  ändert ein über die API gestartetes Skript die Variable nicht, sie käme erst nach bis zu 10 min
  nach. Beides im Labor geprüft (RouterOS 7.24.5). Mehr Rechte für den HA-User sind keine Lösung,
  `policy` erlaubt die Benutzerverwaltung.
* **Nur die Taster der Integration „Mikrotik Router“** („Script switches“: Taster
  `cfm-ssid-guest-on`/`-off`): Schalten geht damit, aber HA kennt den Zustand nicht. Für reines
  Schalten ohne Anzeige reicht das, für einen Schalter mit Zustand braucht es Abschnitt 3.
* **Direkt an der Konfiguration schalten** (z.B. WLAN-Interfaces deaktivieren): Der User hat keine
  Schreibrechte, und die Interfaces der APs sind dynamisch, RouterOS lässt sie nicht abschalten.

## 5. Fehlersuche

Ein Schalter oder Sensor „nicht verfügbar“ heißt: Das Hilfsskript ist mit Exit-Code 1
ausgestiegen. Die Meldung steht im HA-Log (Einstellungen → System → Protokolle, Suche
`command_line` bzw. `cfm_ssid`). Mehr Details:

```yaml
logger:
  logs:
    homeassistant.components.command_line: debug
```

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `Connection refused` / `timed out` | Router nicht erreichbar oder Firewall: HA-Adresse fehlt in `capsmanApi.from`, Routing zwischen HA-Netz und MGMT-Netz | Netz-Admin; Erreichbarkeit aus dem HA-Container prüfen |
| `invalid user name or password` | Passwort in `cfm_ssid.json` falsch oder User noch nicht freigeschaltet | Passwort vom Netz-Admin |
| `Skript cfm-ssid-guest-on fehlt` | Der Host ist nicht (mehr) der CAPsMAN (Gerät gewechselt) oder die SSID ist nicht schaltbar | neuen Host vom Netz-Admin, in `cfm_ssid.json` eintragen |
| `not enough permissions` | Skripte ohne `dont-require-permissions` (sollte cfm nie anlegen) | Netz-Admin |
| `Zugangsdaten … nicht lesbar` | Pfad oder JSON-Syntax von `cfm_ssid.json` | Datei prüfen |
| `Timeout for command` (HA) | Antwort dauerte länger als `command_timeout` | Netzweg prüfen; `command_timeout` nicht unter 30 |

Zieht der CAPsMAN auf ein anderes Gerät um, bleiben User und Freigaben bei cfm aktuell. In HA ist
dann nur `host` in `cfm_ssid.json` zu ändern (und in der Integration „Mikrotik Router“).

## 6. Sicherheit

* Die API ist **unverschlüsselt** (Port 8728, im LAN so gewollt, D47). Das Passwort des Lese-Users
  geht im Klartext über das Netz. Er kann Konfiguration und Clients lesen, aber nichts ändern außer
  über die beiden Schalt-Skripte.
* Der Port ist am CAPsMAN nur für die Adressen aus `capsmanApi.from` offen.
* Wer `cfm_ssid.json` lesen kann, kann das Gast-WLAN schalten und die Konfiguration des CAPsMAN
  lesen (ohne Passwörter der WLANs).
