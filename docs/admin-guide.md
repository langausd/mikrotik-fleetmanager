# cfm – Admin-Guide

Für Netzwerk-Admins, die eine MikroTik-Flotte (etwa 5–20 Geräte, RouterOS 7) mit cfm betreiben
wollen: Konzept, Planung, Inbetriebnahme, tägliche Arbeit, Notfälle und eigene Templates.
Warum etwas so gebaut ist, steht in [DECISIONS.md](DECISIONS.md), offene Punkte in [TODO.md](TODO.md).

> **Teststand:** Im CHR-Labor mit RouterOS 7.24.2 laufen der Gesamttest (77 Prüfungen, darunter
> Manager-Bootstrap mit Reset, Probelauf, Firewall, Schlüsselwechsel, Netzplan, PPSK und ein
> RouterOS-Downgrade auf 7.24.1) und der Onboarding-Test (14 Prüfungen mit Werks-IP,
> 15 im CAPs-Modus per DHCP) fehlerfrei. Ein **erster Hardware-Pilot** lief mit zwei Geräten: einem
> CRS418 als Router, Primary-Manager und CAPsMAN (Rolle `router,manager`) und einem hAP ax² als AP.
> Die dabei gefundenen Fehler sind behoben (dynamische Bridge-VLAN-Einträge des Switch-Chips,
> Syslog-Einträge auf dem hAP ax², Aktivierung neuer RouterBOARD-Firmware, Seed-Upload), siehe
> [DECISIONS.md](DECISIONS.md#auf-hardware-verifizierte-routeros-eigenheiten). **Noch nicht** mit
> echter Hardware erprobt sind VRRP mit mehreren Routern, der Backup-Manager samt
> CAPsMAN-Übernahme, das automatische Onboarding gegen reale Werks-Configs, RouterOS-Updates mit
> Zusatzpaketen auf mehreren Architekturen, PPSK-VLANs und der Kanalbericht; offene Punkte stehen in
> [TODO.md](TODO.md). Plane für jeden weiteren Gerätetyp einen Pilotbetrieb mit einem Testgerät ein.

**Inhalt:** [1 Was cfm macht](#1-was-cfm-macht) · [2 Konzepte](#2-konzepte) ·
[3 Planung](#3-planung) · [4 Datenmodell](#4-datenmodell) · [5 Rollen](#5-rollen) ·
[6 Inbetriebnahme](#6-inbetriebnahme) · [7 Geräte aufnehmen](#7-geräte-aufnehmen) ·
[8 Tägliche Arbeit](#8-tägliche-arbeit) · [9 Notfälle](#9-sicherheitsnetze-und-notfälle) ·
[10 Sicherheit](#10-sicherheit) · [11 Eigene Templates](#11-eigene-templates) ·
[12 Testlabor](#12-testlabor) · [13 Befehle](#13-befehlsreferenz) ·
[14 Dateien und Objekte](#14-dateien-und-objekte) · [15 Fehlersuche](#15-fehlersuche)

---

## 1. Was cfm macht

* Ein **Config-Manager** (ein MikroTik) hält die Soll-Konfiguration der ganzen Flotte: VLANs,
  Port-Profile, Firewall-Zonen, WLAN, Benutzer, Gerätespezifika.
* Jedes Gerät gleicht sich selbst regelmäßig mit dieser Soll-Konfiguration ab. Änderungen gehen
  in **Canary-Ringen** raus, jedes Gerät sichert sich vorher und rollt bei Problemen selbst zurück.
* Der Manager ist gleichzeitig **wifi-CAPsMAN** für alle APs (mehrere SSIDs, WPA2/WPA3, 802.11r/k/v).
* Secrets (Passwörter, PSKs) liegen nur im **Vault** des Managers und werden per SSH verteilt.
* Die aktive Config jedes Geräts liegt zentral auf dem Manager und optional in einem **Git-Repo**.
* **Neue Geräte** im Werkszustand werden am Zielort weitgehend automatisch aufgenommen.
* **RouterOS-Updates** per Befehl: Der Manager lädt die Pakete und verteilt sie, sofort oder in
  einem Wartungsfenster.
* Jedes Gerät bekommt eine **minimale Firewall**, die nur Management-Zugriffe zulässt.
* Die **Verkabelung** wird per LLDP erfasst und gegen einen Soll-Stand geprüft; daraus entsteht
  ein Netzplan.

**Was cfm nicht macht:** kein Monitoring oder Alerting (es gibt Status, Logs und Syslog), keine
grafische Oberfläche (Terminal-Befehle am Manager), keine RouterOS-Updates ohne deinen Befehl,
und es konfiguriert nur, was die mitgelieferten Rollen abdecken. Alles andere bleibt
unangetastet oder kommt über eigene Templates dazu.

---

## 2. Konzepte

### Manager, Arbeitsstand und Versionen

Die **Source of Truth ist der Manager**. Dort liegt der Arbeitsstand in `cfm/work/`. Solange du
dort editierst, passiert auf den Geräten nichts. Erst `$cfmRelease` prüft Syntax und Inhalt,
friert den Stand als Version `archive/v<N>/` ein und gibt ihn an Ring 0 frei. Was ein Release auf
einem Gerät ändern würde, zeigt vorher der Probelauf `$cfmPlan`. Dieses Projektverzeichnis ist
nach dem Einrichten nur noch Vorlage und Referenz; die Historie liefern Archiv und Git-Sicherung.
Das Archiv behält die letzten `archiveKeep` Versionen und alle, die noch gebraucht werden.

### Agent auf jedem Gerät

Das Skript `cfm-agent` läuft 20 Sekunden nach jedem Booten, alle 15 Minuten (`interval`) und
sofort bei einem Push vom Manager:

1. Manifest `live/m/<Seriennummer>.mf` per SFTP vom ersten erreichbaren Manager holen
   (Fallback-Liste `managers`) und dessen MAC mit dem Geräteschlüssel prüfen.
2. Nur wenn sich etwas geändert hat (oder einmal täglich, `reapply`): Dateien laden, SHA-512
   prüfen, verschlüsseltes Backup ziehen, Watchdog scharf schalten.
3. Bibliothek, Daten, Hostfile und Rollen importieren; verwaiste Objekte entfernen.
4. Erreichbarkeit des Managers bestätigen. Sonst rollt der Watchdog nach 5 Minuten (`watchdog`)
   per `/system backup load` zurück.
5. Steht im Manifest ein RouterOS-Auftrag (`$cfmUpgrade`): Pakete vom Manager laden und sofort
   oder im Wartungsfenster neu starten.
6. Status und Export nach `cfm/out/` legen. Der Manager holt beides in seinem Tick ab (`mgrTick`,
   Standard alle 10 Minuten).

### Was cfm verwaltet und was nicht

cfm erkennt „seine“ Objekte am Kommentar:

| Kommentar | Bedeutung |
|---|---|
| `cfm:<key> …` | verwaltet: wird angelegt, angeglichen und entfernt, wenn es nicht mehr in den Daten steht |
| `cfm-override …` | bewusst lokal behalten (per Audit markiert); cfm legt kein Duplikat an |
| `cfm-sys:…` | framework-intern (Agent, Keys, Vault); weder aufgeräumt noch im Audit |
| kein Präfix | von Hand angelegt: nie angefasst, aber im Audit sichtbar |

Konsequenz: **Eine Zeile aus den Daten löschen genügt**, damit das Objekt auf allen Geräten
verschwindet, zum Beispiel ein VLAN. Hand-Änderungen an verwalteten Objekten werden beim
nächsten Apply zurückgesetzt.

### Rollen, Hostfile und Inventar

* **Rollen** (`roles/*.rsc`) sind die Templates. `base` gilt immer, dazu kommen `switch`, `ap`,
  `router`, `manager` oder `manager-backup`, auch kombiniert (`"router,manager"`).
* Das **Hostfile** `hosts/<name>.rsc` enthält die Gerätespezifika (Ports, Router-ID, WAN …).
  Optional kommt `hosts/<name>.post.rsc` mit freien Befehlen nach allen Rollen hinzu.
* Das **Inventar** `meta/inventory.rsc` ordnet Name ↔ Seriennummer, Rolle, Ring und MGMT-IP zu.
  Es ist Metadatum und wirkt sofort, ohne Release.

### Ringe

Jedes Gerät gehört zu Ring 0, 1 oder 2. Ein Release geht zuerst an Ring 0. Melden alle Geräte
eines Rings Erfolg, rückt die Version nach der Wartezeit (`ringSoak`, Standard 30 min bzw. 2 h)
in den nächsten Ring auf, oder sofort per `$cfmPromote`. Empfehlung: Ring 0 = ein unkritisches
Gerät je Typ plus Backup-Manager, Ring 2 = Primary-Manager und Core-Router.

### Secrets

Zentrale Secrets (Admin-Passwörter, WLAN-PSKs, Vault-Passwort) liegen als deaktivierte
`/ppp secret` namens `cfm:<key>` auf dem Manager. Diese erscheinen nicht im Export, sind aber im
verschlüsselten Backup enthalten. Der Manager schreibt sie per SSH direkt in die Geräte-Config,
als Datei existieren sie nie. Geräteschlüssel entstehen beim Aufnehmen des Geräts.

### Überblick

```
          ┌────────────── cm1 (Primary-Manager, CAPsMAN) ──────────────┐
 Admin ─▶ │ work/ ─$cfmRelease─▶ archive/vN + Manifeste    Vault       │ ─ssh-exec─▶ Git-Host
          │ meta/ (Inventar, Ringe)   state/<gerät>/ (Status, Export)   │
          └───▲ SFTP-Pull (nur lesend)    │ Push, Secrets, Abholen ─────┘
              │                           ▼
        rtr1 · sw1 · ap1 …  (cfm-agent)          cm2 (Backup-Manager, spiegelt cm1)
```

---

## 3. Planung

Bevor du etwas einspielst, kläre diese Punkte:

| Frage | Wo eintragen |
|---|---|
| MGMT-VLAN und -Subnetz, IPs der beiden Manager (Primary zuerst) | `global.rsc`: `mgmtVlan`, `managers`; `vlans.rsc` |
| Wer ist Gateway, DNS und NTP im MGMT-Netz? | Router-Rolle (VRRP-VIP `.gw`) oder externes Gateway; `global.rsc`: `dns`, `ntp` |
| VLANs und ihre Firewall-Zonen, was darf wohin? | `vlans.rsc` (`zone`), `global.rsc` (`policy`) |
| Einzelrouter oder VRRP? | Hostfile des Routers: `routerId` (weglassen = Einzelrouter) |
| Von wo administrierst du? | `global.rsc`: `mgmtAccess`, `mgmtExtra` (siehe Warnung) |
| Admin-Benutzer | `global.rsc`: `users`; Passwörter per `$cfmSecret` |
| SSIDs, VLANs der SSIDs, Kanäle | `wifi.rsc` |
| Welche Ports haben welches Profil? | Hostfiles |
| Ring je Gerät, Name je Gerät | Inventar |
| Git-Sicherung gewünscht? | `global.rsc`: `hook`; Git-Host einrichten |
| Platz für RouterOS-Pakete (ca. 20 MB je Architektur und Version) | `global.rsc`: `pkgPath` (leer = Flash des Managers) |

> **Warnung zum Management-Zugang:** Nach dem ersten Apply lassen alle Geräte SSH und Winbox nur
> noch aus den Zonen in `mgmtAccess` (Standard: `mgmt`) und aus `mgmtExtra` zu. Alle anderen
> Dienste (Telnet, FTP, WebFig, API) sind aus, MAC-Winbox gibt es nur im MGMT-VLAN. Zusätzlich
> verwirft die minimale Firewall auf Switches, APs und Managern alles, was nicht aus diesen Netzen
> kommt. Trage deinen Admin-PC in `mgmtExtra` ein, wenn er nicht im MGMT-VLAN hängt.

**Konventionen:**
* Subnetz eines VLANs ist `192.168.<VID>.0/24`, Gateway `.1` (änderbar per `gw`, eigenes Netz per `net`).
* VRRP: reale Router-IP `.250 + routerId`, VIP = Gateway, Priorität `210 − 10 · routerId` (routerId 1 ist
  bevorzugter Master).
* Interfaces heißen `vlan<VID>` bzw. `vrrp<VID>`, die Bridge heißt `bridge`.
* **VLAN 88 (`192.168.88.0/24`) ist für das Onboarding reserviert** und darf nicht anderweitig
  benutzt werden; es passt bewusst zur Werks-IP `192.168.88.1` neuer Geräte.

**Hardware und Software:**
* RouterOS ≥ `rosMin` (7.22); im CHR-Labor getestet mit 7.24.2, dazu ein Hardware-Pilot (CRS418,
  hAP ax²).
* Manager: jeder MikroTik mit genug Flash (das Archiv hält `archiveKeep` Versionen; RouterOS-Pakete
  brauchen ca. 20 MB je Architektur und Version, notfalls auf USB/NVMe per `pkgPath`) und mit
  Internetzugang für die Paket-Downloads, idealerweise mit Funk, falls er selbst auch AP sein soll
  (dann Rolle `ap` separat bedenken).
* APs brauchen den **neuen wifi-Stack** (`wifi-qcom`, ax-Geräte). Der alte `wireless`-Stack wird
  nicht unterstützt.

---

## 4. Datenmodell

Alle Dateien sind RouterOS-Skripte mit Arrays. Tipp: Syntaxfehler findet `$cfmRelease`, bevor
irgendetwas ausgerollt wird.

### `global.rsc`

| Schlüssel | Bedeutung | Standard |
|---|---|---|
| `mgmtVlan` | MGMT-VLAN | `10` |
| `managers` | Manager-IPs, Primary zuerst (Fallback-Reihenfolge der Geräte) | |
| `mgrPath` | Basisverzeichnis auf dem Manager | `cfm` |
| `domain`, `tz`, `ntp`, `dns`, `syslog` | Domain für DHCP, Zeitzone, NTP/DNS für Nicht-Router, Syslog-Ziel | |
| `interval` / `reapply` / `watchdog` | Agent-Takt / täglicher Voll-Apply / Rollback-Timeout | `15m` / `1d` / `5m` |
| `mgrTick` | Intervall des allgemeinen Manager-Ticks (Status, Ring-Aufstieg, Secret-Sync, Updates, Netzplan, Hook, Vault-Backup). Onboarding hat einen eigenen, festen 1m-Tick, unabhängig davon | `10m` |
| `ringSoak` | Wartezeit Ring 0→1 und 1→2; `"manual"` = nur per `$cfmPromote` | `{"30m";"2h"}` |
| `archiveKeep` | so viele Versionen bleiben im Archiv (plus alle, die Ringe oder Geräte nutzen) | `10` |
| `pkgPath` | Ablage der RouterOS-Pakete für `$cfmUpgrade`, leer = `<cfm>/pkg` | leer |
| `mgmtAccess`, `mgmtExtra` | Zonen bzw. Netze mit Management-Zugriff | `mgmt` / `{}` |
| `policy` | Zonen-Matrix: `von = Ziele` mit Zonen, `wan` (Internet), `*` (alles), `mtupdate` (nur MikroTik-Update-Server), `allow:<Liste>` (nur die Ziele der Liste). **NAT nur mit Kennzeichen:** `*wan` = masquerade, `wan@<Adresse>` = feste NAT-Adresse (bei VRRP wandert sie mit dem Master); gilt auch für `mtupdate` und `allow:…`. `wan` ohne Kennzeichen wird geroutet, der Upstream braucht eine Route zurück. Zonen ohne `*`/`wan`: DNS an externe Server wird auf den Router umgeleitet | |
| `allow` | Freigabelisten: `{"name"={"host.example.com";"203.0.113.10";"198.51.100.0/24"}}` | `{}` |
| `rosChannel`, `rosMin` | Update-Kanal und Mindestversion beim Onboarding | `stable`, `7.22` |
| `onboard` | `timeout` einer Onboarding-Sitzung, `mtHosts` (Update-Server) | `60m` |
| `users` | Admin-Benutzer → Gruppe | |
| `adminUser` | `disable` = Werks-User `admin` abschalten, sobald auf dem Gerät ein User aus `users` aktiv ist; `keep` = nicht anfassen | `disable` |
| `services` | aktive IP-Dienste mit Port (RouterOS-Namen: `telnet`, `ftp`, `www`, `www-ssl`, `api`, `api-ssl`, `ssh`, `winbox` – **nicht** `http`/`https`), alle anderen werden abgeschaltet | `ssh`, `winbox` |
| `hook` | Git-Host (`host`, `user`), leer = aus | |

### `vlans.rsc`

Schlüssel ist die VLAN-ID als String.

| Feld | Bedeutung |
|---|---|
| `name` | Anzeigename (landet im Kommentar) |
| `zone` | Firewall-Zone |
| `net`, `gw` | eigenes Subnetz bzw. Host-Anteil des Gateways (Standard `192.168.<VID>.0/24`, `.1`) |
| `dhcp`, `lease`, `dns` | DHCP-Bereich als Host-Anteile (`"100-200"`), Lease-Zeit, DNS für Clients |
| `l3` | `"no"` = reines L2-VLAN ohne Router-Interface |
| `onboard` | `"yes"` markiert das Onboarding-VLAN (genau eins) |

### `profiles.rsc` – Port-Profile

Im Hostfile als `"<port>"="<profil>[:<arg>]"`, zum Beispiel `"ether5"="access:40"`.

| Profil | Wirkung |
|---|---|
| `trunk` | alle VLANs tagged (inkl. Onboarding-VLAN für den Transport) |
| `trunk-ap` | nur MGMT und WLAN-Zonen tagged – für AP-Uplinks |
| `access:<vid>` | ein VLAN untagged, Edge-Port mit BPDU-Guard |
| `vport:<vid>` | wie `access`, aber ohne Edge und BPDU-Guard – für Karten virtueller Maschinen |
| `hybrid:<vid>` | ein VLAN untagged, alle anderen tagged |
| `wan` | nicht in der Bridge (WAN eines Routers) |
| `off` | nicht in der Bridge und abgeschaltet |

Eigene Profile: `tag` (`"*"`, Zonen, VIDs, `"!x"` schließt aus), `untag` (`"arg"` = Argument),
`edge`, `bridge`, `disabled`.

### `wifi.rsc`

* `ssids`: interner Schlüssel → `ssid`, `vlan`, `bands` (`"2,5"`); optional `sec`, `ft`, `pmf`,
  `isolation` als Abweichung von `defaults`. Die Passphrase kommt **nur** aus dem Vault:
  `$cfmSecret key=psk.<schlüssel> value=…`.
* `master`: die SSID, die das physische Radio trägt, alle anderen werden virtuelle APs.
* `channels`: Kanal-Pools je Band; `radios`: optional feste Kanäle je AP (`{"ap1"={"5"="5180"}}`).
* `reselect`: Uhrzeit der nächtlichen Kanal-Neuwahl (Standard `03:00`); je Band `skipDfs`
  (`10min-cac` meidet die Wetterradar-Kanäle mit 10 Minuten Wartezeit).
* `ppsk`: mehrere Passphrasen mit eigenem VLAN je SSID, z.B.
  `"ppsk"={"iot"={"kameras"={"vlan"=31;"isolation"="yes"}}}` (optional `expires`). Geht nur mit
  `sec="wpa2-psk"`, die VLAN-Zuordnung nur auf wifi-qcom-APs (RouterOS ≥ 7.17). Passphrase:
  `$cfmSecret key=ppsk.iot.kameras value=…`.

### `wireguard.rsc`

Admin-Fernzugang auf dem Router (siehe 8.8), Peers zählen als Zone `mgmt`.

* `listenPort`: UDP-Port des Routers (auf dem WAN-Interface offen, Quelle nicht beschränkt).
* `net`: eigenes Subnetz für Router (Host `.1`) und Peers, darf sich nicht mit einem VLAN aus
  `vlans.rsc` überschneiden (`$cfmCheck` prüft das) – so legt RouterOS die Route fürs ganze
  Subnetz automatisch über die WireGuard-Schnittstelle an, ohne Proxy-ARP-Tricks.
* `peers`: Key = Name; `pubkey` = Public Key des Peers; `addr` = Host-Anteil der Tunnel-IP in
  `net`. Leere `peers={}` = WireGuard-Interface bleibt aus. Der private Schlüssel des Routers
  wird lokal erzeugt (wie SSH-Host-Keys), steht nirgends in den Daten.

### `authorized_keys` (optional)

Persönliche Admin-SSH-Keys, **OpenSSH-Format** (kein RouterOS-Datenformat): eine Zeile je Key,
`<typ> <base64> [kommentar]`, z.B. `ssh-ed25519 AAAAC3... admin@laptop`. OpenSSH-Optionen vor dem
Typ (`command=...`, `no-port-forwarding`, …) werden nicht unterstützt; `#`-Zeilen und Leerzeilen
werden ignoriert.

Die Rolle `base` wendet die Datei auf **jedem** Gerät für **alle** Admin-User aus `global.rsc`
`users` an. Fehlt die Datei, bleiben `ssh-keys` unangetastet (Feature nicht genutzt). Existiert
sie, ist sie der vollständige Sollzustand: Keys, die nicht (mehr) drinstehen, werden bei jedem
Apply entfernt – auch von Hand hinzugefügte, denn `/user/ssh-keys` hat kein `comment`-Feld für
eine feinere Reconciliation. Revocation = Zeile löschen + `$cfmRelease`.

Das ist eine **Zusatzoption**, kein Ersatz für das Passwort-Login: `$cfmSecret key=user.<name>
value=…` funktioniert unabhängig davon immer, ein kaputter oder fehlender Key sperrt also nicht
aus. Auch kein Ersatz für die Geräteschlüssel der Rolle `manager` (`cfm`/`cfmd-<name>`) – die sind
Maschinen-Identität für Push/Pull, hier geht es um menschliche Admins.

`$cfmCheck` prüft grob das Zeilenformat (Typ-Präfix, mindestens ein Leerzeichen), nicht die
Gültigkeit des Base64-Teils. `tools/upload-seed.sh` lädt die Datei aus einem Overlay wie die
übrigen Top-Level-`.rsc`-Dateien mit hoch, obwohl sie selbst keine ist.

### `meta/inventory.rsc`

`"<name>"={"serial"=…;"role"=…;"ring"=0|1|2;"ip"=<MGMT-IP>}`. `$cfmEnroll` und `$cfmRegister`
pflegen die Datei selbst, du kannst sie aber auch direkt editieren (wirkt sofort).

### `hosts/<name>.rsc`

| Schlüssel | Bedeutung |
|---|---|
| `ports` | Port → Profil |
| `portDefault` | Profil für alle nicht genannten Ethernet-Ports |
| `stpPrio` | RSTP-Priorität der Bridge (z.B. `"0x4000"` für den Core) |
| `stp` | `"none"` schaltet RSTP auf der Bridge ab – für Router/Manager in einer VM mit einer Karte je VLAN (siehe D40). `$cfmCheck` warnt dann bei zwei Ports im selben VLAN oder mehreren Trunks |
| `igmp`, `dhcpSnoop` | nur Rolle `switch`: IGMP-Snooping, DHCP-Snooping (Trunks = trusted) |
| `routerId` | nur Rolle `router`: 1–4, schaltet VRRP ein (kleinere Zahl = höhere Priorität) |
| `wan` | nur Rolle `router`: `{"if"="vlan20";"gw"=…;"dns"=…}` oder `{"if"="ether1";"dhcp"="yes"}`, optional `"addr"` |
| `links` | erwartete Verkabelung für `$cfmLinks`: `{"ether1"="rtr1:ether2";"ether8"="-"}` (Gerät:Port, nur Gerät oder `-` für „hier hängt nichts“) |

Im Hostfile darfst du auch zentrale Daten gezielt überschreiben, etwa
`:global cfmVlans; :set ($cfmVlans->"119"->"l3") "no"`.

---

## 5. Rollen

| Rolle | Konfiguriert |
|---|---|
| `base` (immer) | Identity; Bridge mit VLAN-Filtering; Ports nach Profil; Bridge-VLAN-Tabelle; MGMT-VLAN, -IP, Route, DNS, NTP; IP-Dienste nur aus MGMT, `mgmtExtra` und dem WireGuard-Subnetz; SSH-Härtung; Zeitzone, Syslog; Admin-Benutzer (bis zum Secret-Push deaktiviert); Werks-User `admin` abschalten; minimale Firewall (Nicht-Router) und IPv6-input-Firewall (alle Geräte); Nachbarsuche (LLDP) auf allen Bridge-Ports; Firmware-Auto-Upgrade (neue RouterBOARD-Firmware aktiviert der Agent mit einem weiteren Neustart); persönliche Admin-SSH-Keys aus `authorized_keys` (optional); Agent |
| `switch` | IGMP-Snooping, DHCP-Snooping (bewusst schlank, Ports erledigt `base`) |
| `ap` | CAP des CAPsMAN (beide Manager als Adressen), Radios an den CAPsMAN übergeben |
| `router` | VLAN-Interfaces und Adressen; VRRP (optional) mit DHCP nur auf dem Master; Zonen-Listen; Firewall als geordneter Block mit den Chains `local-input`/`local-forward` für eigene Regeln; DNS; NTP-Server; NAT nur für gekennzeichnete Policy-Ziele; Freigabelisten (`allow`); DNS-Umleitung für Zonen ohne Internet; Update-Server-Adressliste; auf Switches mit L3-Hardware-Offloading (CRS3xx/5xx) schaltet sie das Routing im Switch-Chip ab (sonst umgeht es die Firewall, und VRRP funktioniert nicht); WireGuard-Fernzugang für Admins aus `wireguard.rsc` (optional, 8.8) |
| `manager` | Manager-Funktionen; SFTP-Gruppe der Geräte; Adresse und DHCP im Onboarding-VLAN; komplette CAPsMAN-Konfiguration aus `wifi.rsc` inkl. PPSK und Kanal-Neuwahl; Scheduler `cfm-mgr-tick` (alle `mgrTick`) und `cfm-mgr-onb-tick` (Onboarding, jede Minute) |
| `manager-backup` | wie `manager`, aber CAPsMAN passiv (Netwatch übernimmt, wenn der Primary ~3 min weg ist), spiegelt den Primary, Releases gesperrt |

Eigene Firewall-Regeln gehören auf allen Geräten in die Chain `local-input`, auf Routern
zusätzlich `local-forward`, zum Beispiel per `hosts/<name>.post.rsc`. Sie greifen vor dem finalen
Drop.

---

## 6. Inbetriebnahme

### 6.1 Vorlage anpassen

Lege deine Standortdaten als privates Overlay an; Git ignoriert die Verzeichnisse `site/` und
`site-*/`. `tools/new-site.py` legt es aus den Beispieldaten an, setzt Manager-Name, Uplink,
Admin-User und Management-Zugang ein und schreibt dazu eine `CHECKLISTE.md` und einen
`bootstrap-manager.rsc` mit ausgefülltem Kopf:

```bash
tools/new-site.py site --name cm1 --uplink ether1 --user <dein-user> --mgmt-extra <admin-pc>/32
```

Die mitgelieferten Beispiele sind ein fiktives Netz (VLAN 10, 192.168.10.0/24), keine fertige
Konfiguration: Arbeite die Checkliste ab (Adressen, Inventar, Hostfiles, WLAN). So bleiben deine
Daten aus dem Repo, und neue Versionen des Frameworks lassen sich einfach übernehmen.
`tools/upload-seed.sh` lädt aus dem Overlay nur die Daten (`*.rsc`, `authorized_keys`, `hosts/`,
`meta/` …); Notizen wie die Checkliste oder eigene CSV-Listen bleiben lokal. Die Bootstrap-Datei
gehört nicht nach `work/` (das wird an die Flotte verteilt), sondern ins Wurzelverzeichnis des
Geräts – `--bootstrap <datei>` nimmt sie beim selben Aufruf mit, ohne Pfad die
`bootstrap-manager.rsc` aus dem Overlay.

### 6.2 Primary-Manager

1. Den Manager mit einem Port an einen Trunk hängen, der das MGMT-VLAN tagged führt.
2. Die Vorlage hochladen, beim ersten Mal mit dem Inventar:
   ```bash
   tools/upload-seed.sh admin@<aktuelle-IP-des-Managers> --overlay site --seed-inventory
   ```
   Danach lebt das Inventar auf dem Manager (`$cfmRegister` und `$cfmEnroll` pflegen es). Spätere
   Uploads ohne `--seed-inventory` lassen es unangetastet, damit echte Seriennummern und Ringe nicht
   auf die lokale Vorlage zurückfallen; mit `--seed-inventory` bricht das Skript ab, sobald auf dem
   Gerät echte Seriennummern stehen (`--force` überschreibt trotzdem). Geht das Inventar doch
   verloren, holt `$cfmEnroll name=<name> ip=<ip> role=<rolle> ring=<n>` die Seriennummer vom Gerät
   zurück – sonst findet es sein Manifest nicht mehr, das unter der Seriennummer liegt. Jede Datei geht einzeln mit bis zu drei Versuchen hinüber;
   scheitert eine, bricht das Skript mit einer Meldung ab.
**Manager in einer VM:** Eine Karte je VLAN (`vport:<vid>`) und `stp="none"` im Hostfile (D40).
Der Reset im Bootstrap nummeriert die Karten neu – die Zuordnung danach über die MAC-Adressen
prüfen, nicht über die Reihenfolge. Das MGMT-VLAN kommt an einer solchen Karte ungetaggt an, der
Bootstrap legt es aber getaggt auf den Uplink: Der Manager ist über seine MGMT-IP deshalb erst
nach dem ersten Apply erreichbar, bis dahin über die Konsole des Hosts.

3. In `bootstrap/bootstrap-manager.rsc` den Kopf anpassen (`myname`, `ip` = `managers[0]`,
   `uplink`, `mv`, `gw`, `admin`, `role`), die Datei als `bootstrap-manager.rsc` ins
   Wurzelverzeichnis hochladen (oder gleich mit dem Seed: eine Kopie im Overlay und
   `tools/upload-seed.sh … --bootstrap`) und im Terminal ausführen:
   ```
   /import bootstrap-manager.rsc
   ```
   Mit `clean="yes"` (Standard) setzt sich das Gerät zuerst auf eine leere Config zurück, damit
   keine Reste der Werks- oder CAPs-Config bleiben, startet neu und führt den Bootstrap danach
   selbst aus. Die hochgeladenen Dateien, User, Passwörter und SSH-Schlüssel bleiben erhalten
   (`keep-users`), die SSH-Sitzung bricht ab. Nach dem Neustart ist der Manager über seine MGMT-IP
   am Uplink erreichbar; den Rest erledigt der Bootstrap als User cfm, sobald RouterOS
   hochgefahren ist. Den Fortschritt zeigt `/log print where message~"cfm: "`, am Ende steht
   `cfm: Primary-Manager bereit`. Scheitert der Bootstrap, steht der Grund dort
   (`cfm: Bootstrap fehlgeschlagen: …`); nach der Korrektur mit `clean="no"` erneut importieren.
   In `post` kannst du Befehle eintragen, die direkt nach dem Reset laufen, z.B. einen
   zusätzlichen Zugang; ein Fehler darin gibt nur eine Warnung im Log. Auf einem Gerät, das
   schon Manager ist, verweigert der Bootstrap den Reset; `clean="no"` baut auf der vorhandenen
   Config auf. Der Bootstrap richtet den MGMT-Zugang und den Manager-Schlüssel ein, erzeugt
   Release v1 und nimmt den Manager selbst als Gerät auf. Nach wenigen Minuten meldet
   `$cfmStatus` ihn mit v1.
4. **Manager mit PoE-Eingang nur an ether1** (z.B. hAP ax³): Starte ihn im CAPs-Modus
   (Reset-Taster beim Einstecken des PoE-Kabels halten, bis die LED nach etwa 10 s dauerhaft
   leuchtet). Dann ist ether1 ohne Firewall erreichbar, per DHCP aus deinem Netz oder mit Winbox
   über die MAC-Adresse. Seed und Bootstrap hochladen, `uplink "ether1"` lassen und importieren;
   der Reset entfernt die CAPs-Config wieder.

### 6.3 Secrets setzen

Im Terminal des Managers laden die Befehle mit `/system script run cfm-mgr`. Dann:

```
$cfmSecret key=user.netadmin value="…"      # für jeden Benutzer aus global.rsc users
$cfmSecret key=psk.main value="…"        # für jede SSID aus wifi.rsc
$cfmSecret key=vaultpw value="…"         # Passwort des verschlüsselten Vault-Backups
```

Bewahre `vaultpw` getrennt und sicher auf (Passwortmanager). Ohne es ist das Vault-Backup im
Notfall wertlos. Der Manager verteilt die Secrets automatisch, sobald ein Gerät „ok“ meldet.

Sobald dein Benutzer auf einem Gerät aktiv ist, schaltet cfm dort den Werks-User `admin` ab
(`adminUser`). Arbeite am Manager deshalb mit deinem eigenen Benutzer: Die Rolle `manager`
hinterlegt den Manager-Schlüssel auch für die Benutzer aus `users`, alle `$cfm…`-Befehle
funktionieren damit unverändert.

### 6.4 Reihenfolge der Geräte

1. **Router/Core zuerst.** Er stellt Gateway, DNS und NTP im MGMT-Netz und den Internetzugang
   für RouterOS-Updates beim Onboarding bereit.
2. **Switches entlang des Pfads**, damit MGMT- und Onboarding-VLAN überall ankommen.
3. **Backup-Manager** (Rolle z.B. `switch,manager-backup`), anschließend `managers` in
   `global.rsc` prüfen und releasen.
4. **APs.**

### 6.5 Git-Sicherung (optional)

Anleitung im Kopf von `tools/git-host/cfm-git-sync`. Kurz: Linux-Host mit User `cfm`, Forced
Command für den Manager-Schlüssel, am Manager ein Lese-User `cfm-git` mit dem Schlüssel des
Git-Hosts, in `global.rsc` `hook` setzen und die Host-IP in `mgmtExtra` aufnehmen. Gesichert
werden Arbeitsstand, Metadaten, Archiv, Geräte-Exporte und das verschlüsselte Vault-Backup
(`vault/*.bak`), bei jedem Release, Rollback, Onboarding und bei neuen Exporten.

---

## 7. Geräte aufnehmen

### 7.1 Automatisch: Push in die Werks-Config (empfohlen)

Voraussetzung: Router und Switches bis zum Zielport sind bereits aufgenommen.

1. **Registrieren** mit Seriennummer und Passwort vom Aufkleber (Geräte ohne
   Aufkleber-Passwort: `pw` weglassen):
   ```
   $cfmRegister name=ap3 serial=HG1234567 role=ap ring=1 ip=192.168.10.33 pw="…"
   ```
   Dazu `cfm/work/hosts/ap3.rsc` mit dem Uplink-Port anlegen und `$cfmRelease`.
2. **Port am Zielort freischalten:**
   ```
   $cfmOnboard sw=sw1 port=ether5 name=ap3
   ```
3. **Gerät im Werkszustand einstecken und einschalten.** Den Rest erledigt der Manager-Tick:
   Probe → Seriennummer prüfen → ggf. RouterOS-Update aus dem Internet → gerätespezifischer
   Bootstrap mit Reset auf eine leere Config → Enroll → erster Apply → Port zurück auf sein
   Profil. Den Fortschritt zeigt `$cfmOnboardStatus`, abbrechen geht mit `$cfmOnboardAbort`.

Das dauert je nach Update 5–15 Minuten. Zu beachten:
* immer nur **ein** Gerät gleichzeitig, und während einer Sitzung **nicht releasen**
  (ein Apply auf dem Switch würde den Port vorzeitig zurücksetzen);
* **Router** mit Werks-Config über einen **LAN-Port** anschließen, `ether1` ist dort WAN mit Firewall;
* **APs** müssen im Werkszustand per DHCP eine Adresse holen (CAPs-Modus) oder `192.168.88.1` haben;
* **Geräte mit PoE-Eingang nur an ether1** (z.B. hAP): Ihre normale Werks-Config macht ether1 zum
  WAN-Port mit Firewall, darüber geht kein Onboarding. Starte sie stattdessen im **CAPs-Modus**:
  Reset-Taster gedrückt halten, PoE-Kabel einstecken und erst loslassen, wenn die LED nach etwa
  10 s dauerhaft leuchtet (nach etwa 5 s blinkt sie, das wäre der normale Reset). Im CAPs-Modus ist
  ether1 ein Management-Port mit DHCP-Client ohne Firewall; der Manager findet das Gerät über seine
  DHCP-Lease im Onboarding-VLAN, der Rest läuft wie gewohnt. Ein laufendes Gerät bringst du mit
  `/system reset-configuration caps-mode=yes` in diesen Zustand;
* ein Fail-safe-Timer auf dem Switch setzt den Port spätestens nach `onboard.timeout` + 10 min zurück;
* ohne `name=` sucht der Manager unter allen registrierten, noch nicht aufgenommenen Geräten;
  unbekannte Seriennummern erscheinen in `$cfmPending` und werden per `$cfmApprove` freigegeben.

### 7.2 Manuell: Bootstrap-Datei

Für Sonderfälle oder wenn das Onboarding-VLAN (noch) nicht zur Verfügung steht:

1. `$cfmBootstrap` erzeugt `cfm/cfm-bootstrap.rsc` (mit den Manager-Schlüsseln).
2. Datei aufs Gerät bringen (Winbox → Files), im Kopf `ip` und `uplink` anpassen, `/import cfm-bootstrap.rsc`.
3. Am Manager: `$cfmEnroll name=sw3 ip=192.168.10.23 role=switch ring=1`.

Das Hostfile muss den Uplink-Port mit einem Trunk-Profil führen, sonst verliert das Gerät beim
ersten Apply seinen MGMT-Zugang (der Watchdog rollt dann zurück).

### 7.3 Bestandsgeräte übernehmen

Ein Gerät mit gewachsener Konfiguration lässt sich per Bootstrap und Enroll übernehmen. Vorher:

* `$cfmAudit host=<name>` zeigt alles, was cfm nicht verwaltet.
* Kollisionen entfernen, vor allem **Bridge-VLAN-Einträge mit mehreren VLAN-IDs**
  (`$cfmAudit host=<name> op=purge sel=A3`). Was bleiben soll, als Override markieren (`op=mark`).
* Die Umstellung auf VLAN-Filtering ist ein Eingriff. Am besten zuerst ein Gerät in Ring 0.

### 7.4 Gerätetausch und Reset

* **Tausch:** neues Gerät unter demselben Namen registrieren (neue Seriennummer, neues
  Aufkleber-Passwort) und per `$cfmOnboard … name=<name>` aufnehmen, oder manuell per
  Bootstrap und `$cfmEnroll`. Die alte Seriennummer und ihr Schlüssel werden ersetzt.
* **Zurückgesetztes Gerät:** einfach erneut `$cfmOnboard … name=<name>`. Das Aufkleber-Passwort
  bleibt dafür im Vault gespeichert.

---

## 8. Tägliche Arbeit

### 8.1 Dateien bearbeiten

Alle Befehle laufen im Terminal des Primary-Managers nach `/system script run cfm-mgr`.
Die Dateien unter `cfm/work/` bearbeitest du auf einem dieser Wege:
* im Terminal: `/file edit cfm/work/vlans.rsc contents`;
* in Winbox unter Files;
* per SFTP vom Admin-PC (`sftp admin@<manager>`: `get`, lokal editieren, `put`).
  Achtung: Dateien, die auf `.auto.rsc` enden, führt RouterOS beim Upload sofort aus.

### 8.2 Release und Rollout

```
$cfmRelease msg=" VLAN 180 für Kameras"
$cfmStatus                 # Ring 0 bekommt die Version zuerst
$cfmPromote                # optional: nächsten Ring sofort freigeben
```

`$cfmRelease` bricht bei Syntaxfehlern oder Dateien über 60 KB ab, bevor irgendetwas
ausgerollt wird, und ebenso bei inhaltlichen Fehlern (`$cfmCheck`): unbekannte VLANs, Zonen oder
Port-Profile, doppelte MGMT-IPs, Rollen ohne Datei. Mit `force=yes` releast du bewusst trotzdem.
Ohne `$cfmPromote` rücken die Ringe automatisch auf, sobald alle Geräte des vorigen Rings „ok“
melden und `ringSoak` abgelaufen ist.

### 8.3 Probelauf

```
$cfmPlan host=sw1
```

zeigt, was ein Release des aktuellen `work/` auf diesem Gerät ändern würde, ohne etwas
anzuwenden: je Änderung eine Zeile (`neu: …`, `geändert: … feld=wert`, `entfernt: …`,
`Regelblock … neu aufgebaut`), am Ende die Summe. Fehler der inhaltlichen Prüfung erscheinen
vorab. Der Probelauf überspringt `hosts/*.post.rsc`, weil dort beliebige Befehle stehen dürfen.
Das Ergebnis liegt auch in `cfm/state/<name>/plan.txt`.

### 8.4 Rezepte

| Aufgabe | Vorgehen |
|---|---|
| VLAN hinzufügen | Zeile in `vlans.rsc` mit `zone`; ggf. `policy` ergänzen → Release. Trunks tragen es automatisch |
| VLAN entfernen | Zeile löschen → Release. Interfaces, Adressen, DHCP, Bridge-Einträge verschwinden überall |
| Port umkonfigurieren | Profil im Hostfile ändern → Release |
| SSID ändern/hinzufügen | `wifi.rsc` → Release; neue SSID: `$cfmSecret key=psk.<key> value=…` |
| PSK wechseln | `$cfmSecret key=psk.<key> value=…` (kein Release nötig) |
| Admin-Benutzer | `users` in `global.rsc` → Release, dann `$cfmSecret key=user.<name> value=…` |
| Firewall-Freigabe zwischen Zonen | `policy` in `global.rsc` → Release |
| Internet für eine Zone | `policy`: `wan` (geroutet, Upstream kennt das Netz), `*wan` (masquerade) oder `wan@<Adresse>` (feste NAT-Adresse im WAN-Netz) → Release |
| Zone nur zu bestimmten Internet-Zielen (z.B. IoT-Cloud) | Liste in `allow` anlegen, `policy` z.B. `"iot"="allow:tuya"` (mit NAT `*allow:tuya`) → Release. Feiner als je Zone geht es über kleinere Zonen (eigenes VLAN je Gerätegruppe) |
| Eigene Firewall-Regel | Chain `local-input`/`local-forward` per `hosts/<router>.post.rsc` |
| Gerät sofort aktualisieren | `$cfmPush host=<name>`; Voll-Apply trotz gleicher Version: `force=yes` |
| Ring eines Geräts ändern | Inventar editieren (wirkt sofort) |
| Hand-Objekte finden | `$cfmAudit host=<name>` → `op=mark|purge sel=…` |
| Vorher sehen, was sich ändert | `$cfmPlan host=<name>` |
| RouterOS aktualisieren | `$cfmUpgrade ver=<x.y.z> ring=0`, später die anderen Ringe (siehe 8.6) |
| Geräteschlüssel erneuern | `$cfmRekey host=<name>` bzw. `all=yes` |
| Archiv verkleinern | `$cfmArchivePrune keep=5` (sonst automatisch mit `archiveKeep`) |
| Verkabelung prüfen, Netzplan | `$cfmLinks`; Soll einfrieren mit `accept=yes`, Graphviz/CSV mit `export=yes` (siehe 8.7) |
| Zweite Passphrase mit eigenem VLAN | `ppsk` in `wifi.rsc` → Release → `$cfmSecret key=ppsk.<ssid>.<name> value=…` |
| WLAN-Kanäle ansehen | `$cfmChannels` |

### 8.5 Überblick

* `$cfmStatus` zeigt je Gerät Ring, Soll- und Ist-Version, Ergebnis (`ok`, `failed …`,
  `bad vN`, `pend vN`), Secrets-Version, RouterOS-Version (bei offenem Auftrag mit Zielversion)
  und das Alter der letzten Meldung.
* Die aktive Config jedes Geräts liegt in `cfm/state/<name>/export.rsc`, der letzte Audit in
  `audit.txt`, beides auch im Git.
* Logs: auf jedem Gerät `/log print where message~"cfm"`, zentral per Syslog (`syslog`).
* `$cfmCollect host=<name>` holt Status und Export sofort statt beim nächsten Tick.

### 8.6 RouterOS-Updates

Updates laufen nur per Befehl:

```
$cfmUpgrade ver=7.25.1 host=sw1                         # sofort
$cfmUpgrade ver=7.25.1 ring=1 at="2026-10-01 02:00"     # einmaliges Wartungsfenster
$cfmUpgrade                                             # offene Aufträge und ihr Stand
$cfmUpgrade cancel=yes ring=1                           # Auftrag zurückziehen
```

* Der Manager lädt vorher alle nötigen Pakete (`routeros` und Zusatzpakete wie `wifi-qcom`) für
  alle Architekturen der betroffenen Geräte von download.mikrotik.com nach `pkgPath`. Fehlt eines,
  startet nichts. Architektur und Pakete meldet jedes Gerät in seinem Status.
* Die Geräte holen die Pakete per SFTP vom Manager, prüfen die Größe und starten sofort bzw. zum
  Zeitpunkt `at` neu. RouterOS prüft die Signatur der Pakete beim Installieren.
* Eine ältere Zielversion bedeutet **Downgrade** (`/system/package/downgrade`); die Konfiguration
  bleibt erhalten.
* Die Geräte laden die Pakete sofort, nur der Neustart wartet auf das Fenster. Ist das Fenster
  schon vorbei, wenn die Pakete da sind (Gerät war offline, Download zu langsam), startet das
  Gerät nicht und meldet „Fenster verpasst“. Erteile dann einen neuen Auftrag.
* Läuft ein Gerät nach dem Neustart nicht mit der Zielversion, meldet es „fehlgeschlagen“ und
  versucht es nicht erneut.
* Erledigte Aufträge trägt der Manager selbst aus, Paketversionen ohne Einsatz löscht er.
* Nutze die Ringe: erst Ring 0, prüfen, dann die anderen.
* Der Manager braucht Internetzugang, die Geräte nicht. Die Pakete werden nicht auf den
  Backup-Manager gespiegelt, offene Aufträge brauchen den Primary.

### 8.7 Verkabelung und Netzplan

Alle Geräte betreiben die Nachbarsuche (LLDP, MNDP, CDP) auf ihren Bridge-Ports und melden
ihre Nachbarn je Port mit jedem Agent-Lauf.

```
$cfmLinks                  # Links und Abweichungen anzeigen, schreibt cfm/state/netzplan.md
$cfmLinks accept=yes       # aktuellen Stand als Soll (Baseline) einfrieren
$cfmLinks export=yes       # zusätzlich netzplan.dot (Graphviz) und netzplan.csv
```

* Status je Link: `ok` (beide Seiten melden), `einseitig`, `extern` (Gerät außerhalb von cfm,
  z.B. ein Telefon mit LLDP), `neu` (nicht in der Baseline) und `fehlt` (in der Baseline, aber
  nicht mehr gemeldet).
* Feste Erwartungen im Hostfile: `"links"={"ether1"="rtr1:ether2";"ether8"="-"}` (Gerät:Port,
  nur Gerät oder `-` für „hier hängt nichts“). Sie gelten sofort aus `work/`, ohne Release.
* `netzplan.md` enthält ein Mermaid-Diagramm (rendert in Gitea, GitHub, GitLab und vielen
  Editoren) und die Link-Tabelle; neue Links sind dick, fehlende gestrichelt gezeichnet. Die Datei
  wird nur bei Änderungen neu geschrieben und landet mit der Git-Sicherung im Repo.
* Der Manager prüft alle 15 Minuten selbst und schreibt neue Abweichungen ins Log (`cfm: Netz:`).
* `$cfmChannels` zeigt die Kanäle der APs und warnt, wenn zwei APs am selben Switch denselben
  Kanal nutzen. Die Kanäle wählen die APs selbst aus den Pools in `wifi.rsc` (`reselect`).

### 8.8 WireGuard-Fernzugang

Für Admins, die Geräte ohne direkten Laptop-Zugriff erreichen müssen (kein Agent-Forwarding im
RouterOS-SSH-Client, daher kein Sprung über einen Manager möglich): ein WireGuard-Tunnel zum
Primary-Manager, dessen Peers als Zone `mgmt` zählen – volle Rechte wie ein Gerät im MGMT-VLAN.
Nur auf dem Router (Rolle `router`) aktiv, siehe `wireguard.rsc`.

**Server (einmalig pro Peer):**

1. Public Key des Admin-Laptops besorgen (siehe Client unten, Schritt 1).
2. Einmalig ein eigenes Subnetz in `wireguard.rsc` → `net` festlegen (darf keins von `vlans.rsc`
   sein, `$cfmCheck` prüft das). Dann je Peer eintragen: `"peers"={"<name>"={"pubkey"="<PUBKEY>";
   "addr"=<Host-Teil in net, frei>}}` → `$cfmRelease` + `$cfmPromote` bis zum Ring des Routers.
3. Der private Schlüssel des Routers wird beim ersten Anlegen der Schnittstelle automatisch
   erzeugt (wie SSH-Host-Keys) und bleibt auf dem Gerät – kein Vault-Eintrag. Öffentlichen
   Schlüssel abrufen: `/interface/wireguard/print`.
4. Firewall/Routing laufen automatisch mit: eigene Adresse (Host `.1`) auf der
   WireGuard-Schnittstelle (die verbundene Route fürs ganze Subnetz entsteht daraus von selbst,
   kein Proxy-ARP, keine Route je Peer nötig), das Subnetz in `cfm-mgmt` (Zugriff auf die eigenen
   Dienste des Routers) und eine offene Eingangsregel für den `listenPort` (UDP, von überall –
   Sicherheit kommt aus der Kryptografie, nicht aus einer Quell-IP-Beschränkung).

**Client (Linux mit NetworkManager, `tools/wg-client-setup.sh` statt GNOME-Panel):**

```
# 1) Einmalig: Schlüsselpaar erzeugen, Public Key für wireguard.rsc ausgeben
tools/wg-client-setup.sh genkey

# 2) Sobald der Router den Peer kennt (siehe oben) und dessen Public Key bekannt ist:
tools/wg-client-setup.sh connect --name cfm-mgmt \
  --endpoint <WAN-Adresse-des-Routers>:<listenPort> --server-pubkey <PUBKEY-ROUTER> \
  --address <peer-addr-aus-wireguard.rsc>/32 --allowed-ips <WG-Subnetz aus wireguard.rsc "net", z.B. 192.168.250.0/24>,<MGMT-Netz, z.B. 192.168.10.0/24>
nmcli connection up cfm-mgmt
```

`allowed-ips` braucht sowohl das WG-Subnetz selbst (um den Router unter seiner `.1`-Adresse zu
erreichen) als auch die Netze, die man über den Router routen will (z.B. das MGMT-VLAN, um andere
Geräte zu erreichen).

`--allowed-ips` bewusst eng auf die tatsächlich benötigten Subnetze fassen (nicht `192.168.0.0/16`
o.ä.) – sonst überlagert die Route das eigene lokale Netz des Laptops, falls es zufällig auch im
`192.168.0.0/16`-Bereich liegt, und bricht die normale Internetverbindung während der Tunnel aktiv
ist. Bei mehreren WireGuard-Verbindungen (z.B. weitere Standorte) auf sich nicht überschneidende
`allowed-ips` achten.

---

## 9. Sicherheitsnetze und Notfälle

| Situation | Automatisch | Deine Aufgabe |
|---|---|---|
| Fehler in einem Template | Gerät bricht ab, rollt per Backup zurück, meldet `failed …` und merkt die Version als `bad` | Fehler beheben, neu releasen (die neue Version ist nicht `bad`) |
| Gerät nach dem Apply unerreichbar | Watchdog rollt nach 5 min zurück, Ergebnis `rollback-watchdog` | Ursache (Ports/VLANs) im Hostfile beheben |
| Fehlerhafte Version schon in Ring 0 | Ringe 1 und 2 bekommen sie nicht | reparieren oder `$cfmRollback ver=<N>` |
| Zurück auf einen alten Stand | – | `$cfmRollback ver=<N> [all=yes]`. **Achtung:** überschreibt `work/` mit dem alten Stand |
| Primary-Manager fällt aus | Geräte ziehen vom Backup; der Backup-CAPsMAN übernimmt nach ~3 min | bei längerem Ausfall auf cm2 `$cfmPromoteManager`, dann `managers` tauschen und releasen |
| Primary kommt zurück | CAPsMAN des Backups schaltet sich ab | nach einer Beförderung den alten Primary neu als Backup aufsetzen |
| Onboarding hängt | Sitzung endet nach `onboard.timeout`, der Port fällt zurück | `$cfmOnboardStatus`, Log, ggf. `$cfmOnboardAbort` |
| Release stoppt mit „Prüfung“ | nichts wurde ausgerollt | Fehler beheben oder bewusst `force=yes` |
| RouterOS-Update schlägt fehl | Gerät bleibt auf der alten Version, Status `fehlgeschlagen`, kein weiterer Neustart | Log am Gerät lesen, `$cfmUpgrade cancel=yes host=<name>`, neuen Auftrag erteilen |
| Beide Manager verloren | – | Git-Kopie (`work/`, `meta/`, `archive/`) auf neuen Manager, Vault aus `vault/*.bak` (mit `vaultpw`) |

Zum Totalverlust: Das Vault-Backup ist ein vollständiges, verschlüsseltes RouterOS-Backup des
Managers. Am sichersten stellst du es auf **baugleicher** Hardware wieder her. Ob dabei auch alle
Schlüssel übernommen werden, ist nicht getestet. Andernfalls musst du die Geräte neu aufnehmen
(Bootstrap bzw. Onboarding), ihre Konfiguration kommt dann wieder aus dem Archiv.

---

## 10. Sicherheit

* **Vertrauensmodell:** Manager steuern Geräte über den User `cfm` mit ihrem Schlüssel. Geräte
  haben am Manager nur Lesezugriff (Gruppe `cfm-dev`). Jedes Manifest ist mit einem
  gerätespezifischen Schlüssel signiert, Dateien per SHA-512 geprüft. Rückmeldungen der Geräte
  liest der Manager nur als Daten und führt sie nie aus.
* **Identitätsprüfung:** Vor jedem Secret-Push beweist das Gerät per Challenge-Response, dass es
  seinen Geräteschlüssel kennt (`ssh-exec` prüft keine Host-Schlüssel). Ein Gerät, das sich nur
  unter der IP ausgibt, bekommt keine Secrets. `$cfmRekey` erneuert Geräteschlüssel, zum Beispiel
  bei Verdacht auf eine Kompromittierung.
* **Minimale Firewall:** Switches, APs und Manager lassen nur Antworten, ICMP und Verbindungen aus
  den Management-Netzen zu (MGMT, `mgmtAccess`, `mgmtExtra`), Manager zusätzlich DHCP für das
  Onboarding. Der Rest wird begrenzt geloggt (`cfm-drop`) und verworfen. Für IPv6 gilt auf allen
  Geräten: nur Antworten, ICMPv6 und Link-Local aus dem MGMT-VLAN. Router behalten ihre
  Zonen-Firewall.
* **Nachbarsuche:** LLDP/MNDP/CDP läuft auch an Access-Ports; Endgeräte sehen Modell, Version und
  Identität des Switches (bewusste Entscheidung für den Netzplan).
* **PPSK:** Passphrasen liegen nur im Vault und kommen per Secret-Push. Wer eine Passphrase kennt,
  landet in deren VLAN; vergib sie wie Schlüssel und begrenze Gäste-Passphrasen per `expires`.
* **Manager schützen:** Wer den Manager kontrolliert, kontrolliert die Flotte. Physischer Schutz,
  wenige Admins, Zugriff nur aus dem MGMT-Netz.
* **Werks-User `admin`:** Nach dem Onboarding-Reset hat er wieder das Aufkleber-Passwort, bei
  älteren Modellen ein **leeres Passwort**. Mit `adminUser="disable"` (Standard) schaltet cfm ihn ab,
  sobald auf dem Gerät ein eigener Benutzer aus `users` aktiv ist, nie vorher. Nach einem
  Secret-Push passiert das sofort, und ein von Hand wieder aktivierter `admin` wird beim nächsten
  Apply erneut abgeschaltet. Ausnahme für einzelne Geräte im Hostfile:
  `:global cfmG; :set ($cfmG->"adminUser") "keep"`.
* **Onboarding:** Das Onboarding-VLAN ist nur während einer Sitzung an genau einem Port
  untagged und erreicht nur die MikroTik-Update-Server. RouterOS prüft bei `ssh-exec`/`fetch`
  keine Host-Schlüssel. Sorge deshalb dafür, dass niemand anderes im Onboarding-VLAN hängt.
* **`vaultpw`** gehört offline in einen Passwortmanager, nicht auf den Manager allein.
* **Git-Host:** nur Forced Command für den Manager-Schlüssel, der Lese-User `cfm-git` am Manager.
* **Persönliche Admin-SSH-Keys:** optional über `authorized_keys` (siehe Datenmodell), Passwort
  bleibt immer zusätzlich gültig. Existiert die Datei, entfernt jeder Apply Keys, die nicht mehr
  drinstehen – auch von Hand hinzugefügte, `/user/ssh-keys` hat kein Feld für eine feinere
  Unterscheidung. Leg die Datei also nur an, wenn du sie auch pflegst.

---

## 11. Eigene Templates

Eigene Logik gehört in eine neue Rolle (`roles/<name>.rsc`) oder in `hosts/<name>.post.rsc`.

### Bausteine aus `lib/lib.rsc`

| Funktion | Zweck |
|---|---|
| `$cfmEnsure m=<menü> k=<key> p=({…}) [n=({…})] [a=({…})] [x="Text"]` | Objekt verwalten: anlegen, angleichen, bei Wegfall entfernen. `n` = natürlicher Schlüssel zum Übernehmen vorhandener Objekte, `a` = Werte nur beim Anlegen |
| `$cfmSet m=<menü> p=({…}) [n=({…})]` | Werte an Singletons oder eingebauten Objekten setzen (ohne Tag, ohne Aufräumen) |
| `$cfmBlock m=<menü> k=<key> l=<Liste>` | reihenfolge-sensitive Listen (Firewall, NAT, Provisioning) als Block |
| `$cfmNet <vid>`, `$cfmVids <spec>`, `$cfmProfile <spec>`, `$cfmHas <rolle>` | Adressdaten eines VLANs, VLAN-Mengen, Port-Profil, Rollenprüfung |

Beispiel:

```
:global cfmEnsure
$cfmEnsure m="/ip/dns/static" k="dns:nas" p=({"name"="nas.lan";"address"="192.168.20.20"})
```

Neue Menüs, die aufgeräumt werden sollen, gehören in die Liste `cfmMenus` in `lib/lib.rsc`.

**Probelauf beachten:** `$cfmPlan` führt die Rollen mit `cfmDry=true` aus. `$cfmEnsure`,
`$cfmSet` und `$cfmBlock` ändern dann nichts, direkte Befehle dagegen schon. Schreibe sie deshalb
als `:if ($cfmDry != true) do={ … }` (vorher `:global cfmDry`).

### RouterOS-Syntaxfallen

Diese Fallen zeigen sich erst beim echten Laden per `/import`, nicht beim Syntaxcheck:

* Funktionen **ohne eckige Klammern** aufrufen (`$cfmEnsure …`). Eine Zeile, die mit `[` beginnt,
  liest RouterOS u.U. als Fortsetzung der vorigen Zeile.
* Array-Literale in Aufrufen in runde Klammern: `p=({…})`.
* Kein `\"` in String-Argumenten eines Funktionsaufrufs, solche Strings vorher in eine Local legen.
* `:return` innerhalb von `:onerror … in={}` verlässt die Funktion nicht, ein Flag benutzen.
* Geräteabhängige Menüs (z.B. `/system routerboard`) in Leerzeichen-Schreibweise, sonst ist das
  Fehlen auf CHR/x86 ein nicht abfangbarer Syntaxfehler.

Die vollständige Liste steht in [DECISIONS.md](DECISIONS.md#im-chr-labor-verifizierte-routeros-eigenheiten-7242),
die auf Hardware gefundenen Eigenheiten (z.B. `find` liefert auch dynamische Einträge)
[gleich darunter](DECISIONS.md#auf-hardware-verifizierte-routeros-eigenheiten).

**Prüfskript:** `tools/rsc-check.py` findet diese Fallen ohne Gerät, dazu unausgeglichene
Klammern, zu große Dateien und Dotfiles unter `work/`:

```bash
tools/rsc-check.py                          # alle .rsc-Dateien im Repo
tools/rsc-check.py site/                    # dein Overlay
tools/rsc-check.py --regeln                 # Regeln mit Erklärung
git config core.hooksPath tools/git-hooks   # Pre-Commit-Hook: blockiert Commits mit Fehlern
```

Ist ein Fund gewollt, nimm die Zeile mit `# rsc-check: erlaubt <regel>` in der Zeile darüber
aus. Auf GitHub prüft die Action `rsc-check` jeden Push. Das Skript ersetzt weder `:parse`
(`$cfmRelease`) noch den Labortest: **Teste neue Templates im Labor**, bevor du sie releast.

---

## 12. Testlabor

`tools/chr-lab/` betreibt RouterOS-CHR-VMs in QEMU/KVM (Stern-Topologie: vm1 ist Manager und
„Switch“, vm2/vm3 hängen an dessen `ether2`/`ether3`).

```bash
cd tools/chr-lab
./lab.sh start 3          # CHR-Image chr-<version>.img in ~/.cache/cfm-chr-lab
./e2e.sh fresh            # Gesamttest: Aufnahme, Firewall, Probelauf, Prüfung, Rollback, Backup-Manager,
                          # Router, Archiv, Schlüsselwechsel, RouterOS-Downgrade, Netzplan, PPSK …
./e2e-onboard.sh fresh    # automatisches Onboarding eines "Werksgeräts" (Werks-IP 192.168.88.1)
./e2e-onboard.sh fresh dhcp   # dasselbe im CAPs-Modus (DHCP-Client, wie ein hAP an PoE/ether1)
./lab.sh stop
```

Das CHR-Image lädst du von download.mikrotik.com (`chr-<version>.img.zip`, entpacken). Mit
`./lab.sh ssh <n>` kommst du an die Konsole einer VM. Funkteile lassen sich auf CHR nicht testen.
Die Lab-Hostfiles setzen `adminUser="keep"`, weil `lab.sh` sich als `admin` anmeldet.
Der Update-Schritt lädt ein RouterOS-Paket (ca. 20 MB) aus dem Internet; dafür legt der Test auf
cm1 zwei Routen über `ether1` an. SFTP zwischen den CHRs ist langsam (etwa 100 KB/s), der Schritt
dauert deshalb einige Minuten.

---

## 13. Befehlsreferenz

Nach `/system script run cfm-mgr` im Terminal des Primary-Managers:

| Befehl | Wirkung |
|---|---|
| `$cfmRelease [msg="…"] [all=yes] [force=yes]` | `work/` prüfen und als neue Version an Ring 0 (bzw. alle) freigeben; `force=yes` trotz inhaltlicher Prüffehler |
| `$cfmCheck` | inhaltliche Prüfung von `work/` (läuft bei jedem Release) |
| `$cfmPlan host=<n>` | Probelauf: was ein Release von `work/` auf dem Gerät ändern würde |
| `$cfmArchivePrune [keep=<n>]` | alte Versionen löschen (automatisch nach jedem Release) |
| `$cfmPromote [ring=1\|2]` | Version des vorigen Rings freigeben |
| `$cfmRollback ver=<N> [all=yes]` | alten Stand als neue Version freigeben (überschreibt `work/`) |
| `$cfmStatus` | Flottenübersicht |
| `$cfmPush [host=<n>\|ring=<r>] [force=yes]` | sofortigen Pull auslösen |
| `$cfmCollect [host=<n>]` | Status und Export sofort abholen |
| `$cfmAudit host=<n> [op=report\|mark\|purge] [sel=all\|A1,A3]` | unverwaltete Objekte anzeigen, markieren, entfernen |
| `$cfmSecret key=<k> value=<v>` | Vault-Eintrag setzen (`user.<name>`, `psk.<ssid>`, `vaultpw`) |
| `$cfmSecretPush [host=<n>]` | Secrets sofort verteilen |
| `$cfmVaultBackup` | verschlüsseltes Manager-Backup nach `vault/` |
| `$cfmRekey host=<n>\|all=yes` | Geräteschlüssel erneuern |
| `$cfmUpgrade ver=<x.y.z> host=<n>\|ring=<r>\|all=yes [at="YYYY-MM-DD HH:MM"]` | RouterOS-Update oder -Downgrade, sofort oder im Wartungsfenster |
| `$cfmUpgrade` · `$cfmUpgrade cancel=yes host=…\|ring=…\|all=yes` | offene Aufträge anzeigen bzw. zurückziehen |
| `$cfmPkgPrune` | Paketversionen ohne Einsatz löschen (läuft automatisch) |
| `$cfmLinks [accept=yes] [export=yes]` | Verkabelung prüfen, Netzplan schreiben; Baseline einfrieren bzw. Graphviz/CSV |
| `$cfmChannels` | Kanäle der APs, Warnung bei gleichem Kanal an einem Switch |
| `$cfmRegister name= serial= ip= [role=] [ring=] [pw=]` | Gerät für das Onboarding registrieren |
| `$cfmOnboard sw= port= [name=]` · `$cfmOnboardStatus` · `$cfmOnboardAbort` | automatisches Onboarding |
| `$cfmPending` · `$cfmApprove serial= name= ip= [role=] [ring=]` | unbekannte Geräte |
| `$cfmBootstrap` | Bootstrap-Datei für die manuelle Aufnahme |
| `$cfmEnroll name= ip= [role=] [ring=] [rekey=yes]` | Gerät aufnehmen (manuell) |
| `$cfmTrust [host=<n>]` | Manager-Schlüssel an Geräte verteilen |
| `$cfmPromoteManager` | auf dem Backup: zum Primary befördern |

---

## 14. Dateien und Objekte

**Auf dem Manager** (`cfm/`, auf Geräten mit `flash/`-Verzeichnis `flash/cfm/`):

| Pfad | Inhalt |
|---|---|
| `work/` | Arbeitsstand (Daten, Rollen, Hostfiles, Bibliothek) |
| `archive/v<N>/` | freigegebene Versionen mit `index.dat` (Dateien + SHA-512) |
| `live/m/<serial>.mf` | signierte Manifeste je Gerät |
| `plan/` | Schnappschuss von `work/` für den Probelauf, mit Plan-Manifesten `plan/m/` |
| `pkg/<ver>/` | RouterOS-Pakete für `$cfmUpgrade` (oder unter `pkgPath`) |
| `meta/` | `inventory.rsc`, `rings.dat`, `vault.dat`, `keys/`, `onboard.dat`, `pending.dat`, `upgrade.dat`, `links.dat` (Baseline), `netcheck.dat` |
| `state/<name>/` | `status.dat`, `export.rsc`, `audit.txt`, `plan.txt` je Gerät |
| `state/netzplan.md` | Netzplan (Mermaid + Tabelle), auf Anforderung `netzplan.dot` und `netzplan.csv` |
| `vault/<name>-vault.bak` | verschlüsseltes Manager-Backup |

`.dat` statt `.json`, weil RouterOS lesenden SFTP-Nutzern `.json`- und `.backup`-Dateien verweigert.

**Auf jedem Gerät:** User `cfm` (Manager-Schlüssel), Skripte `cfm-agent` und `cfm-conf`, Scheduler
`cfm-agent` (Takt) und `cfm-agent-boot` (20 s nach jedem Neustart), Geräteschlüssel als `/ppp secret` `cfm:key`, Dateien `cfm/state.json`, `cfm/out/`,
`cfm/dl/`, `cfm/pre.backup`, beim Probelauf `cfm/pl/` und `cfm/out/plan.txt`; Firewall-Blöcke
`cfm:fwb…` (Nicht-Router) und `cfm:fw6…` (IPv6); Interface-Liste `DISC` (Nachbarsuche); während eines Applys der Scheduler
`cfm-watchdog`, nach einem übersprungenen Lauf `cfm-agent-retry`, während eines Onboardings auf dem
Switch `cfm-onboard-revert`, bei einem geplanten RouterOS-Update `cfm-upgrade` und die Pakete im
Wurzelverzeichnis.

---

## 15. Fehlersuche

| Symptom | Ursache | Abhilfe |
|---|---|---|
| Gerät meldet „kein Manager erreichbar“ | Route/Gateway im MGMT-Netz, Firewall, Manager-Dienste nur aus MGMT | Ping zum Manager vom Gerät, `managers` prüfen |
| „Manifest-MAC ungültig“ | Geräteschlüssel passt nicht mehr (Reset, Restore); direkt nach `$cfmRekey` kurzzeitig normal | `$cfmEnroll name=<n> ip=<ip> rekey=yes` |
| „Release abgebrochen (Prüfung)“ | inhaltlicher Fehler in `work/` | Meldung lesen und beheben; bewusst: `force=yes` |
| Secret-Push: „Identitätsprüfung fehlgeschlagen“ | Geräteschlüssel passt nicht, oder ein anderes Gerät antwortet unter der IP | Gerät prüfen; nach einem Reset `$cfmEnroll … rekey=yes` |
| Probelauf: „keine Antwort“ | Agent war gerade beschäftigt | später erneut |
| Update: `Fenster verpasst` / `fehlgeschlagen` | Pakete zu spät da bzw. Installation gescheitert | `$cfmUpgrade` zeigt den Stand, Log am Gerät, neuen Auftrag erteilen |
| Eigener Dienst am Gerät nicht erreichbar, Log `cfm-drop` | minimale Firewall | Regel in der Chain `local-input` oder Netz in `mgmtExtra` |
| `$cfmLinks`: Link `einseitig` | die Gegenstelle meldet (noch) keine Nachbarn | nächsten Agent-Lauf abwarten oder `$cfmPush host=<n>` |
| Log `cfm: Netz: fehlt …` | Kabel gezogen, umgesteckt oder Gerät aus | Verkabelung prüfen; gewollte Änderung: `$cfmLinks accept=yes` |
| PPSK-Client landet nicht im richtigen VLAN | VLAN fehlt auf dem AP-Uplink (`trunk-ap`) oder AP ohne wifi-qcom | Warnung von `$cfmCheck` beachten, Profil erweitern |
| „Hash stimmt nicht“ / „Download fehlgeschlagen“ | unvollständiges Archiv (z.B. auf dem Backup) | Primary prüfen, neu releasen |
| Ergebnis `failed <datei>: …`, Version `bad` | Fehler in Daten/Template, Gerät hat zurückgerollt | Meldung lesen, beheben, releasen |
| `rollback-watchdog` | Gerät hat nach dem Apply den Manager verloren | Ports/VLANs im Hostfile prüfen |
| `expected end of command` / `syntax error` | RouterOS-Syntaxfalle (Kapitel 11) | Template korrigieren, im Labor testen |
| Secrets-Version (SV) bleibt alt | Gerät per SSH nicht erreichbar oder Objekt fehlt noch | `$cfmSecretPush host=<n>`, Ausgabe prüfen |
| Kein Winbox/SSH mehr vom Admin-PC | Dienste nur aus `mgmtAccess`/`mgmtExtra` | Admin-PC in `mgmtExtra`, releasen |
| Anmeldung als `admin` geht nicht mehr | gewollt: `adminUser="disable"`, ein eigener Benutzer ist aktiv | mit dem eigenen Benutzer anmelden; Ausnahme per `adminUser="keep"` im Hostfile |
| Apply: „can not change dynamic“ | eine eigene Suche per `find` ohne `!dynamic` trifft einen dynamischen Eintrag (z.B. vom Switch-Chip angelegte Bridge-VLANs) | `$cfmEnsure`/`$cfmFind` verwenden oder `!dynamic` in die Suche aufnehmen |
| Log `cfm: RouterBOARD-Firmware … geflasht … Neustart zum Aktivieren` | gewollt: neue Firmware wird nach einem RouterOS-Update erst mit einem weiteren Neustart aktiv | nichts zu tun, der Agent startet einmal neu |
| `upload-seed.sh`: „ABBRUCH: … enthält echte Seriennummern“ | `--seed-inventory` auf einen Manager mit aufgenommenen Geräten | ohne `--seed-inventory` hochladen; nur mit `--force`, wenn das Inventar wirklich ersetzt werden soll |
| Bridge-Port inaktiv, Log „BPDU guard changed port role to disabled“ | Edge-Port (`access`) bekommt BPDUs, z.B. von der Bridge eines Virtualisierungshosts | Profil `vport:<vid>` verwenden, Port einmal `disabled=yes` und wieder `no` setzen |
| `upload-seed.sh`: „Seed unvollständig hochgeladen“ | einzelne Dateien auch nach drei Versuchen nicht übertragen | erneut aufrufen; Verbindung und freien Platz am Manager prüfen |
| Über WireGuard kein SSH/Winbox | Peer fehlt in `wireguard.rsc` oder ist noch nicht ausgerollt; Client-`allowed-ips` ohne das WireGuard-Subnetz | `$cfmCheck`, am Router `/interface/wireguard/peers/print`, Client-Konfiguration prüfen |
| Webfig o.ä. bleibt aus, obwohl in `services` eingetragen | falscher Dienstname (`http` statt `www`) | RouterOS-Namen verwenden (Kapitel 4, `services`) |
| Onboarding bleibt in `wait` | Gerät nicht erreichbar: Kabel, Router an `ether1`, falsches Aufkleber-Passwort | `$cfmOnboardStatus`, Log am Manager, Registrierung prüfen |
| Onboarding: „Seriennummer passt nicht“ | anderes Gerät am Port | Registrierung oder Gerät prüfen |
| Onboarding: „RouterOS … älter als …“ | kein Update möglich (Internet über den Router?) | Router-Rolle/`policy` `onboard`, notfalls von Hand updaten |

Hilfreich auf dem Gerät: `/log print where message~"cfm"` und `:put [/file get cfm/state.json contents]`.
Auf dem Manager: `$cfmStatus`, `$cfmOnboardStatus` und `/log print where message~"cfm"`.
