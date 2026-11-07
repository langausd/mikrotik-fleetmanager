# Gast-WLAN und Ports aus Home Assistant schalten, Meldungen von cfm empfangen

Anleitung für die Einbindung in Home Assistant (HA): Abschnitte 1–6 schalten das Gast-WLAN,
[Abschnitt 7](#7-benachrichtigungen-von-cfm) empfängt Meldungen des Netz-Managers (DU4.1),
[Abschnitt 8](#8-umschaltbaren-port-schalten-dockingstation) schaltet einen Port, z.B. den einer Dockingstation, zwischen
normalem Netz und Gastnetz um (DP1.4.1). Sie setzt kein Wissen über cfm oder RouterOS
voraus. Die Netzseite richtet der Netz-Admin ein (Admin-Guide 6.7 und 6.8, Entscheidungen DW4.1 und DW4.2), die
konkreten Werte bekommst du von ihm.

**Ergebnis:** ein Schalter `switch.gast_wlan` mit echtem Zustand und optional Sensoren, die zeigen,
wann sich das Gast-WLAN selbst wieder abschaltet und wer gerade eingebucht ist.

---

## 1. Wie es funktioniert

```
Home Assistant ──RouterOS-API, TCP 8728──▶ CAPsMAN (zentraler WLAN-Controller)
  command_line-Schalter                      ├─ Skript cfm-ssid-guest-on   ─┐ schalten die WLAN-Interfaces
  └─ cfm_ssid.py (Hilfsskript)               ├─ Skript cfm-ssid-guest-off  ─┘ der Gast-SSID an/ab
                                             ├─ WLAN-Interfaces            ◀── Zustand (on/off)
                                             ├─ Datei cfm/ssid-guest.txt   ◀── Zeitpunkt des Auto-Aus
                                             └─ Registrierungstabelle,     ◀── eingebuchte Clients
                                                DHCP-Leases
```

* Der **CAPsMAN** ist der MikroTik, der alle Access Points (APs) steuert. Auf ihm legt cfm für jede
  schaltbare SSID zwei Skripte an: `cfm-ssid-<key>-on` und `cfm-ssid-<key>-off`. `<key>` ist der
  interne Name der SSID, beim Gast-WLAN `guest`.
* HA meldet sich über die **RouterOS-API** mit einem **Lese-User** an (Gruppe `read,api,test`). Der
  User darf nichts an der Konfiguration ändern, aber genau diese beiden Skripte starten. Die Skripte
  ändern dann die Konfiguration im eigenen Namen (`dont-require-permissions`).
* Das **Hilfsskript** `cfm_ssid.py` (nur Python-Standardbibliothek) spricht die API. Es startet die
  Skripte und liest den Zustand. Der Zustand kommt aus den WLAN-Interfaces des CAPsMAN, nicht aus
  einer Merkvariable.
* **Auto-Aus:** Ist an der SSID ein Auto-Aus eingestellt (z.B. 50 h), schaltet der CAPsMAN sie nach
  dieser Zeit selbst ab. Er prüft alle 10 Minuten. HA muss dafür nichts tun.
* Der Zustand **bleibt** über Neustarts und Konfigurations-Releases erhalten, ein Release ändert ihn
  nicht. Ohne je geschaltet zu sein, gilt der Grundzustand, den der Netz-Admin festlegt (beim
  Gast-WLAN: aus).

**Wichtig fürs Verhalten:** Beim Schalten geht nur die Gast-SSID an bzw. aus, die anderen SSIDs senden
weiter (DW4.2; vorher waren bei jedem Schalten alle APs etwa 3 Sekunden ganz ohne WLAN). Einmal, beim
ersten Schalten nach dieser Umstellung, provisioniert der CAPsMAN die APs noch neu: Dann sind sie etwa
3 Sekunden ohne WLAN, verbundene Geräte melden sich von selbst wieder an. Ein neu aufgenommener AP
kann die Gast-SSID bis zu 10 Minuten lang senden, auch wenn sie aus ist (der CAPsMAN prüft alle
10 Minuten). Auf echter Hardware ist noch offen, ob ein AP beim Schalten kurz das ganze Radio neu
startet. Deshalb weiter nicht in kurzen Abständen schalten, keine Automationen, die hin- und
herschalten können, und keinen „Toggle bei jeder Statusänderung“.

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
python3 /config/cfm/cfm_ssid.py guest on       # kein Output, Exit-Code 0
python3 /config/cfm/cfm_ssid.py guest state    # → on
python3 /config/cfm/cfm_ssid.py guest until    # → 2026-10-05T21:49:29+02:00 (Auto-Aus)
python3 /config/cfm/cfm_ssid.py guest off
python3 /config/cfm/cfm_ssid.py guest until    # → leer (aus bzw. ohne Auto-Aus)
python3 /config/cfm/cfm_ssid.py guest clients  # → {"clients": []} (aus bzw. niemand eingebucht)
```

| Aufruf | Ausgabe (stdout) | Exit-Code |
|---|---|---|
| `<key> on` / `<key> off` | nichts; kehrt erst zurück, wenn der CAPsMAN fertig ist (~1–3 s, beim ersten Schalten nach der Umstellung auf DW4.2 ~10 s) | 0, bei Fehler 1 |
| `<key> state` | `on` oder `off` | 0, bei Fehler 1 |
| `<key> until` | Zeitpunkt des Auto-Aus als ISO 8601 mit Zeitzone, leer wenn aus oder ohne Auto-Aus | 0, bei Fehler 1 |
| `<key> clients` | eingebuchte Clients der SSID als JSON in einer Zeile: `{"clients": [{"mac", "host", "ip", "interface", "ssid", "band", "signal", "uptime"}, …]}`, Hostname und IP aus den DHCP-Leases des CAPsMAN (leer, wenn keine Lease, also auch, wenn ein anderes Gerät DHCP-Server des Gast-VLANs ist), `signal` in dBm; leere Liste, wenn aus | 0, bei Fehler 1 |

Fehlermeldungen gehen nach stderr, beginnen mit `cfm_ssid:` und stehen dann auch im HA-Log
(Abschnitt 5). Optionen: `--config <Datei>` (andere Zugangsdatei), `--timeout <s>` (Standard 20).

Ohne Zugang zum Container (kein `python3` im Terminal-Add-on, Schutzmodus nicht abschaltbar): Sind die
Entitäten aus 3.3 schon angelegt, die Aktion `homeassistant.update_entity` auf `switch.gast_wlan` bzw.
`sensor.gast_wlan_auto_aus` ausführen (Entwicklerwerkzeuge → Aktionen). HA ruft dabei `state` bzw. `until`
im Container auf; danach Zustand der Entität und HA-Log ansehen (Abschnitt 5). Einen unveränderten
Zustand schreibt `command_line` nicht neu – kein Fehler im Log heißt dann: der Aufruf lief durch.

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

  # optional: wer gerade im Gast-WLAN ist (Anzahl, Liste im Attribut "clients"), siehe 3.4
  - sensor:
      name: Gast-WLAN Clients
      unique_id: cfm_ssid_guest_clients
      icon: mdi:account-multiple
      command: python3 /config/cfm/cfm_ssid.py guest clients
      value_template: '{{ value_json.clients | count }}'
      json_attributes:
        - clients
      availability: '{{ value_json is defined and value_json.clients is defined }}'
      command_timeout: 30
      # praktisch nie von selbst, die Automation in 3.4 fragt nur bei Gast an ab
      scan_interval: 86400
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

Für den Client-Sensor aus 3.3: alle 5 min, aber nur solange das Gast-WLAN an ist, und sofort nach
dem Schalten (beim Ausschalten leert sich die Liste). Bei 50 h Gast-WLAN sind das höchstens 600
Anmeldungen, ohne Gast-WLAN keine.

```yaml
automation:
  - alias: Gast-WLAN Clients aktualisieren
    triggers:
      - trigger: time_pattern
        minutes: "/5"
        id: takt
      - trigger: state
        entity_id: switch.gast_wlan
        to: ["on", "off"]
        id: geschaltet
    conditions:
      - condition: or
        conditions:
          - condition: trigger
            id: geschaltet
          - condition: state
            entity_id: switch.gast_wlan
            state: "on"
    actions:
      - action: homeassistant.update_entity
        target:
          entity_id: sensor.gast_wlan_clients
```

Die Liste enthält MACs und Hostnamen der Gäste. Wer das nicht in der HA-Datenbank haben will, nimmt
den Sensor im `recorder` aus (`exclude: entities: [sensor.gast_wlan_clients]`).

### 3.5 Mehrere schaltbare SSIDs

Jede SSID mit Schalter hat eigene Skripte. Im Hilfsskript ändert sich nur der Schlüssel (`event`
statt `guest` usw.). Für jede SSID einen eigenen `switch`-Block anlegen, mit eigenem `name` und
`unique_id`.

## 4. Was nicht geht und warum

* **Zustand über die globale Variable `cfmSsidguest`** (in der Integration „Mikrotik Router“
  als „Environment variable sensors“): Der Lese-User sieht `/system/script/environment` gar nicht,
  RouterOS zeigt globale Variablen über die API nur Usern mit `write` **und** `policy` (Labor:
  7.24.5 und 7.25rc1). Unter 7.24.5 ändert ein über die API gestartetes Skript die Variable außerdem
  nicht, sie käme erst nach bis zu 10 min nach; ab 7.25 setzt es sie gleich. Mehr Rechte für den
  HA-User sind keine Lösung, `policy` erlaubt die Benutzerverwaltung.
* **Nur die Taster der Integration „Mikrotik Router“** („Script switches“: Taster
  `cfm-ssid-guest-on`/`-off`): Schalten geht damit, aber HA kennt den Zustand nicht. Für reines
  Schalten ohne Anzeige reicht das, für einen Schalter mit Zustand braucht es Abschnitt 3.
* **Direkt an der Konfiguration schalten** (z.B. WLAN-Interfaces deaktivieren): Der User hat keine
  Schreibrechte. Genau das tun die Skripte in eigenem Namen.

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
| `state` meldet immer `on` | altes Hilfsskript (las den Zustand aus den Provisioning-Regeln, vor DW4.2) | `cfm_ssid.py` aus dem Repo neu nach `/config/cfm/` kopieren |
| `Timeout for command` (HA) | Antwort dauerte länger als `command_timeout` | Netzweg prüfen; `command_timeout` nicht unter 30 |

Zieht der CAPsMAN auf ein anderes Gerät um, bleiben User und Freigaben bei cfm aktuell. In HA ist
dann nur `host` in `cfm_ssid.json` zu ändern (und in der Integration „Mikrotik Router“).

## 6. Sicherheit

* Die API ist **unverschlüsselt** (Port 8728, im LAN so gewollt, DU2.1). Das Passwort des Lese-Users
  geht im Klartext über das Netz. Er kann Konfiguration und Clients lesen, aber nichts ändern außer
  über die Schalt-Skripte (Gast-WLAN am CAPsMAN, `cfm-port-*` an Geräten mit umschaltbarem Port).
* Der Port ist am CAPsMAN und an Geräten mit umschaltbarem Port nur für die Adressen aus `capsmanApi.from` offen.
* Wer `cfm_ssid.json` lesen kann, kann das Gast-WLAN und die Ports schalten und die Konfiguration dieser Geräte
  lesen (ohne Passwörter der WLANs).

## 7. Benachrichtigungen von cfm

Der Netz-Manager meldet Probleme der MikroTik-Geräte per HTTP-POST an einen **Webhook** von HA:
Konfigurationsfehler, stumme Geräte, APs ohne CAPsMAN, gescheiterte Updates, die Lizenz des Managers.
Jede Meldung kommt einmal beim Eintreten und einmal, wenn es wieder in Ordnung ist. HA leitet sie
z.B. aufs Handy weiter.

**Ablauf:** Du legst die Automation an und gibst dem Netz-Admin die URL; er trägt sie in cfm ein
(`global.rsc` `notify.url`, Admin-Guide 8.9) und schickt eine Probemeldung (`$cfmNotify test=yes`).

1. Eine zufällige Webhook-ID wählen (sie wirkt wie ein Passwort), z.B. `cfm-` plus 24 Zeichen aus
   `openssl rand -hex 12`.
2. Automation anlegen (YAML-Modus oder `automations.yaml`); `notify.mobile_app_…` ist der Dienst
   deiner Companion-App:

   ```yaml
   - alias: "cfm: Netzwerk-Meldung"
     mode: queued
     triggers:
       - trigger: webhook
         webhook_id: "cfm-<zufällige-id>"
         allowed_methods: [POST]
         local_only: true
     actions:
       - action: notify.mobile_app_<handy>
         data:
           title: "Netz {{ trigger.json.site }}"
           message: >-
             {{ '✅ ' if trigger.json.state == 'off' else '⚠️ ' }}{{ trigger.json.text }}
   ```

3. URL an den Netz-Admin: `http://<HA-Adresse>:8123/api/webhook/cfm-<zufällige-id>`.

**Felder** (`trigger.json`):

| Feld | Inhalt |
|---|---|
| `site` | Standort (z.B. `Haus`) |
| `host` | betroffenes Gerät (leer bei der Probemeldung) |
| `ev` | `apply`, `stumm`, `wlan`, `update`, `lizenz`, `ros`, `onboard`, `primary`, `primary-tick` (vom Backup-Manager: Primary weg bzw. hängt), `dnsreq` (von einem Router: Client hat per DNS-Selbstbedienung eine Domain freigeschaltet, DN3.2), `port` (vom Gerät mit dem Port: umgeschaltet, Abschnitt 8), `test` |
| `state` | `on` = eingetreten, `off` = wieder in Ordnung bzw. erledigt (bei `ros`: alle Geräte haben die Version, oder sie ist überholt), `once` = einmalig (Onboarding, Probe, `dnsreq`); bei `port` der neue Zustand `normal` oder `alt` |
| `msg` | Beschreibung ohne Standort und Gerät |
| `text` | fertiger Text: `<site>: <host> - <msg>` |
| `time` | Zeit des Managers |
| `level` | `error`, `warning` (auch jedes „wieder ok“), `action` (Admin-Eingriff nötig: Update gescheitert, Lizenz, neue RouterOS-Version), `info` (Probe) |
| `device` | betroffenes Gerät (bei Probe und neuer RouterOS-Version der Manager) |
| `message` | wie `text` |
| `key` | ordnet `on` und `off` einander zu: `<ev>:<host>` (z.B. `apply:ap1`), bei `ros` `ros:<Version>` |
| `ver` | nur bei `ros`: die Version (z.B. `7.25.1`) |
| `domain`, `client`, `result`, `until` | nur bei `dnsreq`: freigeschaltete Domain, IP des Clients, `allowed`/`extended`/`denied`, Ablauf (Unixzeit) |
| `port`, `interface` | nur bei `port`: Name des Ports aus `portSwitch` (z.B. `dock`), Interface am Gerät (z.B. `ether5`); `key` ist `port:<Gerät>:<Name>`, `level` `info` |

Ein Empfänger, der nur `level`, `device` und `message` auswertet (etwa `info` nur ins Log,
`action` als Aufgabe), funktioniert ohne Anpassung. Achtung: `dnsreq` hat `level` `action` und
`state` `once` – ein `off` kommt nie; wer daraus Aufgaben macht, schließt sie beim Erledigen von Hand
(oder legt für `dnsreq` gar keine an).

**Aufgaben schließen:** Macht HA aus Meldungen Einträge einer To-do-Liste, schließt das `off` mit
demselben `key` den offenen Eintrag – auch bei `ros`: Sind alle Geräte auf der neuen Version, kommt
`off` mit `RouterOS <Version> auf allen Geräten`; kommt vorher eine neuere Version, erst `off` für die
alte („überholt durch …“), dann `on` für die neue. Bleibt ein Gerät absichtlich auf einer älteren
Version, den Eintrag von Hand abhaken. `todo.update_item` findet einen Eintrag über Titel oder UID:
den `key` also in den Titel nehmen (z.B. `[apply:ap1] …`) oder die Einträge selbst durchsuchen
(`todo.get_items`, dann über die Beschreibung).

Nur Wichtiges aufs Handy, z.B. ohne „wieder ok“: Bedingung
`{{ trigger.json.state != 'off' }}` vor die Aktion setzen. Meldungen `port` (jedes Umschalten eines Ports) gehen
ebenfalls an diesen Webhook; wer sie nicht aufs Handy will: `{{ trigger.json.ev != 'port' }}` (Abschnitt 8.3 nutzt sie). `local_only: true` lässt nur Aufrufe aus
dem lokalen Netz zu; der Manager schickt aus dem LAN.

**Fehlersuche:** Kommt nichts an, steht im Log des Managers `cfm: Meldung nicht zugestellt …`
(Netzweg, Port 8123, falsche ID). HA beantwortet auch eine unbekannte Webhook-ID mit `200` – ein
Tippfehler in der ID fällt also nur dadurch auf, dass die Automation nicht auslöst (Trace der
Automation ansehen).

## 8. Umschaltbaren Port schalten (Dockingstation)

Ein Port mit `portSwitch` im Hostfile (DP1.4) hat zwei Zustände: **normal** (sein Profil, z.B. Haupt-VLAN ungetaggt
und alle anderen getaggt für den Admin-Laptop) und **alt** (z.B. nur das Gastnetz für einen Firmen-Laptop). Die
Skripte `cfm-port-<name>-normal` und `-alt` auf dem Gerät setzen den Zustand, trennen danach den Link für 3 s (das
Gerät am Port holt eine neue Adresse) und melden den Wechsel an den Webhook aus Abschnitt 7. HA startet die Skripte
über die RouterOS-API des Geräts – derselbe Lese-User und dasselbe Passwort wie beim Gast-WLAN, nur die Adresse ist
die des Geräts mit dem Port (DP1.4.1).

```
Home Assistant ──RouterOS-API, TCP 8728──▶ Gerät mit dem Port (z.B. Switch am Schreibtisch)
  command_line-Schalter                      ├─ Skript cfm-port-dock-alt     ─┐ setzen den Port
  └─ cfm_port.py (Hilfsskript)               ├─ Skript cfm-port-dock-normal  ─┘
                                             └─ Datei cfm/port-dock.txt     ◀── Zustand (normal/alt)
               ◀──Webhook (Abschnitt 7)─────── jeder Wechsel, auch vom Taster am Gerät
```

### 8.1 Werte vom Netz-Admin

| Wert | Beispiel | Bedeutung |
|---|---|---|
| Host | `192.168.10.30` | MGMT-Adresse des Geräts mit dem Port |
| Name | `dock` | Name aus `portSwitch`; die Skripte heißen `cfm-port-dock-normal/-alt` |
| User/Passwort | – | wie beim Gast-WLAN (`cfm_ssid.json`) |

Der Netz-Admin braucht dafür `capsmanApi` in `global.rsc` (Adresse von HA in `from`) und den Eintrag `portSwitch` im
Hostfile; nach dem Release öffnet das Gerät die API für HA (Admin-Guide, Feld `portSwitch`).

### 8.2 Datei ablegen und von Hand testen

`tools/home-assistant/cfm_port.py` nach `/config/cfm/cfm_port.py` – **neben** `cfm_ssid.py` (es nutzt dessen
API-Client und Zugangsdatei `cfm_ssid.json`; ohne Gast-WLAN-Schalter trotzdem beide Dateien und die JSON-Datei
ablegen). Im Container von HA (Abschnitt 3.2):

```sh
python3 /config/cfm/cfm_port.py 192.168.10.30 dock state    # → normal
python3 /config/cfm/cfm_port.py 192.168.10.30 dock alt       # kein Output, Exit-Code 0 nach ~4 s
python3 /config/cfm/cfm_port.py 192.168.10.30 dock state    # → alt
python3 /config/cfm/cfm_port.py 192.168.10.30 dock normal
```

| Aufruf | Ausgabe (stdout) | Exit-Code |
|---|---|---|
| `<host> <name> normal` / `alt` | nichts; kehrt zurück, wenn das Gerät fertig ist (Port umgestellt, Link 3 s getrennt, Meldung, ~4 s) | 0, bei Fehler 1 |
| `<host> <name> state` | `normal` oder `alt` | 0, bei Fehler 1 |

Fehler nach stderr mit `cfm_port:` (z.B. „Skript cfm-port-dock-alt fehlt“: kein `portSwitch` mit diesem Namen auf dem
Gerät). Optionen wie bei `cfm_ssid.py`: `--config`, `--timeout`.

### 8.3 `configuration.yaml` und Automation

```yaml
command_line:
  - switch:
      name: Dock im Gastnetz
      unique_id: cfm_port_dock
      icon: mdi:laptop
      command_on: python3 /config/cfm/cfm_port.py 192.168.10.30 dock alt
      command_off: python3 /config/cfm/cfm_port.py 192.168.10.30 dock normal
      command_state: python3 /config/cfm/cfm_port.py 192.168.10.30 dock state
      value_template: '{{ value == "alt" }}'
      availability: '{{ value in ["normal", "alt"] }}'
      command_timeout: 30
      # selten: Wechsel vom Taster meldet das Gerät per Webhook (Automation unten)
      scan_interval: 3600
```

Der Schalter ist **an**, wenn der Port im Gastnetz (alt) ist. Damit ein Wechsel am Taster sofort sichtbar wird, in der
Automation aus Abschnitt 7 (oder einer eigenen mit derselben Webhook-ID) bei `ev` = `port` den Schalter neu abfragen:

```yaml
       - if: "{{ trigger.json.ev == 'port' }}"
         then:
           - action: homeassistant.update_entity
             target:
               entity_id: switch.dock_im_gastnetz
         else:
           - action: notify.mobile_app_<handy>
             data:
               title: "Netz {{ trigger.json.site }}"
               message: >-
                 {{ '✅ ' if trigger.json.state == 'off' else '⚠️ ' }}{{ trigger.json.text }}
```

**Verhalten:** Jedes Schalten trennt den Link für 3 s, auch wenn der Port schon im gewünschten Zustand ist – keine
Automationen, die hin- und herschalten. Der Zustand bleibt über Neustarts und Releases erhalten. Im Zustand alt fehlt
dem Port das MGMT-VLAN: Ein Admin-Laptop am Dock erreicht die Geräte dann nur über WLAN; HA schaltet weiter, es
spricht das Gerät über das Netz an, nicht über den Port.
