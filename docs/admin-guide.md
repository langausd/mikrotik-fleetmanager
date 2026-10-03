# cfm – Admin-Guide

Für Netzwerk-Admins, die eine MikroTik-Flotte (etwa 5–20 Geräte, RouterOS 7) mit cfm betreiben
wollen: Konzept, Planung, Inbetriebnahme, tägliche Arbeit, Notfälle und eigene Templates.
Warum etwas so gebaut ist, steht in [DECISIONS.md](DECISIONS.md), offene Punkte in [TODO.md](TODO.md).

> **Teststand:** Im CHR-Labor mit RouterOS 7.24.5 (zuvor 7.24.2) laufen der Gesamttest (über 190
> Prüfungen, darunter Manager-Bootstrap mit Reset, Probelauf, `$cfmShow`/`$cfmDiff`, Firewall,
> Schlüsselwechsel, Backup-Manager, Router-Rolle mit festen Leases und DNS-Namen, Netzplan, PPSK,
> CAPsMAN-Rolle, ein RouterOS-Downgrade auf 7.24.1 und das eingebaute Update von einem Spiegel), der
> Onboarding-Test (14 Prüfungen mit Werks-IP, 15 im CAPs-Modus per DHCP, 18 hinter einem nicht
> verwalteten Switch) und die Probe mit drei VRRP-Routern (79 Prüfungen) fehlerfrei. Auf **Hardware** läuft cfm an zwei Standorten: ein CRS418 als Router, Primary-Manager
> und CAPsMAN mit zwei hAP ax² (Roaming mit FT bestätigt), und ein zweiter Standort mit neun Geräten – der
> Manager als CHR in einer VM, ein CRS328 als Core-Switch (übernommen ohne Reset, routet noch
> selbst), ein hAP be³ als CAPsMAN, APs (hAP be³, hAP ax³, cAP ax) mit lokalem Fallback, hEX und
> L009 als Switches, RouterOS 7.23.1 bis 7.25beta5. Automatisches Onboarding im CAPs-Modus,
> CAPsMAN-Umzug, RouterOS-Updates mit Zusatzpaketen (arm, arm64) und der Kanal-Scan über den
> CAPsMAN liefen dort. Die gefundenen
> Fehler sind behoben, siehe [DECISIONS.md](DECISIONS.md#auf-hardware-verifizierte-routeros-eigenheiten).
> **Noch nicht** mit echter Hardware erprobt sind VRRP mit mehreren Routern, der Backup-Manager,
> das Onboarding gegen Werks-Configs von Routern und CRS-Switches, PPSK-VLANs, feste Leases und
> DNS-Namen sowie das eingebaute Update über cfm auf einem Gerät mit 16 MB Flash; offene Punkte
> stehen in [TODO.md](TODO.md). Plane für jeden weiteren Gerätetyp
> einen Pilotbetrieb mit einem Testgerät ein.

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
* Ein Gerät mit der Rolle `capsman` ist **wifi-CAPsMAN** für alle APs (mehrere SSIDs, WPA2/WPA3,
  802.11r/k/v); ohne diese Rolle übernimmt das übergangsweise der Manager. Fällt der CAPsMAN aus,
  senden die APs mit einer lokalen Kopie der Haupt-SSID weiter (D45/D46).
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

Aufräumen und Audit umfassen die Menüs aus `cfmMenus` im Kopf von `lib/lib.rsc` (Bridge, VLANs,
Adressen, Routen und Routing-Tabellen, DHCP samt statischer Leases, Firewall inkl. Mangle, DNS,
WLAN, Benutzer, Skripte, Scheduler …). Seit D62 gehören statische DHCP-Leases, Mangle-Regeln und
Routing-Tabellen dazu: Auf einem Bestandsgerät, das noch selbst DHCP macht, zeigt `$cfmAudit` die
von Hand angelegten festen Leases deshalb als unverwaltet – sie bleiben, solange du sie nicht per
`op=purge` entfernst.

### Rollen, Hostfile und Inventar

* **Rollen** (`roles/*.rsc`) sind die Templates. `base` gilt immer, dazu kommen `switch`, `ap`,
  `capsman`, `router`, `manager` oder `manager-backup`, auch kombiniert (`"router,manager"`).
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
          ┌───────────────────── cm1 (Primary-Manager) ────────────────┐
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
* RouterOS ≥ `rosMin` (7.22); im CHR-Labor getestet mit 7.24.2 und 7.24.5, auf Hardware 7.23.1 bis 7.25beta5
  (siehe Teststand oben).
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
| `domain` | Domain für DHCP und die DNS-Namen der Router (`<name>.<domain>`, D62). Nicht `.local` – das gehört mDNS (RFC 6762), Unicast-Einträge dort stören Bonjour/Avahi | `internal` (ICANN-Reservierung für private Netze) |
| `tz`, `ntp`, `dns`, `syslog` | Zeitzone, NTP/DNS für Nicht-Router, Syslog-Ziel | |
| `interval` / `reapply` / `watchdog` | Agent-Takt / täglicher Voll-Apply / Rollback-Timeout | `15m` / `1d` / `5m` |
| `mgrTick` | Intervall des allgemeinen Manager-Ticks (Status, Ring-Aufstieg, Secret-Sync, Updates, Netzplan, Hook, Vault-Backup). Onboarding hat einen eigenen, festen 1m-Tick, unabhängig davon; die beiden sperren sich gegenseitig (D57) | `10m` |
| `ringSoak` | Wartezeit Ring 0→1 und 1→2; `"manual"` = nur per `$cfmPromote` | `{"30m";"2h"}` |
| `archiveKeep` | so viele Versionen bleiben im Archiv (plus alle, die Ringe oder Geräte nutzen) | `5` |
| `pkgPath` | Ablage der RouterOS-Pakete für `$cfmUpgrade`, leer = `<cfm>/pkg` | leer |
| `mgmtAccess`, `mgmtExtra` | Zonen bzw. Netze mit Management-Zugriff | `mgmt` / `{}` |
| `policy` | Zonen-Matrix: `von = Ziele` mit Zonen, `wan` (Internet), `*` (alles), `mtupdate` (nur MikroTik-Update-Server), `allow:<Liste>` (nur die Ziele der Liste). **NAT nur mit Kennzeichen:** `*wan` = masquerade, `wan@<Adresse>` = feste NAT-Adresse (bei VRRP wandert sie mit dem Master); gilt auch für `mtupdate` und `allow:…`. `wan` ohne Kennzeichen wird geroutet, der Upstream braucht eine Route zurück. Zonen ohne `*`/`wan`: DNS an externe Server wird auf den Router umgeleitet | |
| `allow` | Freigabelisten: `{"name"={"host.example.com";"203.0.113.10";"198.51.100.0/24"}}` | `{}` |
| `rosChannel`, `rosMin` | Update-Kanal und Mindestversion beim Onboarding | `stable`, `7.22` |
| `onboard` | `timeout` einer Onboarding-Sitzung, `mtHosts` (Update-Server) | `60m` |
| `users` | Admin-Benutzer → Gruppe | |
| `adminUser` | `disable` = Werks-User `admin` abschalten, sobald auf dem Gerät ein User aus `users` aktiv ist; `keep` = nicht anfassen | `disable` |
| `services` | aktive IP-Dienste mit Port (RouterOS-Namen: `telnet`, `ftp`, `www`, `www-ssl`, `reverse-proxy`, `api`, `api-ssl`, `ssh`, `winbox` – **nicht** `http`/`https`), alle anderen werden abgeschaltet – auch `reverse-proxy`, den RouterOS 7.2x ab Werk auf Port 443 ohne Adressbeschränkung einschaltet. `$cfmCheck` meldet unbekannte Namen und doppelte Ports als Fehler | `ssh`, `winbox` |
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

* `ssids`: interner Schlüssel → `ssid`, `vlan`, `bands` (`"2,5"`, mit 6 GHz `"2,5,6"`); optional `sec`, `ft`, `pmf`,
  `isolation` als Abweichung von `defaults`. Die Passphrase kommt **nur** aus dem Vault:
  `$cfmSecret key=psk.<schlüssel> value=…`.
* `master`: die SSID, die das physische Radio trägt, alle anderen werden virtuelle APs.
* `channels`: Kanal-Pools je Band; `radios`: optional feste Kanäle je AP (`{"ap1"={"5"="5180"}}`).
  Ohne Pin wählt der CAPsMAN den Kanal bei jeder Neuverbindung eines APs aus dem Pool neu; der Pin
  gilt auch für den lokalen Fallback der APs (D46).
* `reselect`: Uhrzeit der nächtlichen Kanal-Neuwahl (Standard `03:00`); je Band `skipDfs`
  (`10min-cac` meidet die Wetterradar-Kanäle mit 10 Minuten Wartezeit).
* 6 GHz: Kanal-Eintrag `"6"` mit `band="6ghz-ax"` und der Security des Bands, z.B.
  `"sec"="wpa3-psk";"pmf"="required"` (6 GHz erlaubt kein WPA2, `$cfmCheck` meldet das). Solche
  Angaben im Kanal-Eintrag (`sec`, `ft`, `ftOverDs`, `pmf`) gelten für alle SSIDs auf dem Band und
  ergeben ein eigenes Profil `cfm-<schlüssel>-6g` mit derselben Passphrase (D48). Die `master`-SSID
  sendet auf allen Bändern aus `channels`, weitere SSIDs nur laut `bands` (z.B. `"2,5,6"`).
* `mlo`: Wi-Fi 7 Multi-Link, Standard `"disabled"` (D48). Ein MLD bietet kein FT an, Clients im
  FT-Verbund meiden den AP dann. Außerdem gibt es nur ein `mld-datapath` je CAP (`cfm-mld`, VLAN der
  `master`-SSID, D44), weitere SSIDs landeten per MLO dort. Nach dem Umschalten die Radios der
  Wi-Fi-7-CAPs neu provisionieren (siehe unten).
* Interface-Namen am CAPsMAN: `<Identity>-2g` bzw. `<Identity>-5g` (Provisioning `name-format`, D47)
  statt `cap-wifiN`; neu vergeben erst beim nächsten Provisionieren eines Radios
  (`/interface/wifi/radio/provision [find where !local]` am CAPsMAN, alle APs ~3 s weg). Nur die
  Radios der CAPs: `[find]` träfe auch die eigenen Radios des CAPsMAN (Flag `L`), die Regeln ohne
  `identity-regexp` würden sie als APs einschalten. Das MLD eines Wi-Fi-7-CAP heißt danach
  `mld-<Identity>-2g` (nur mit MLO); Radios ohne passende Regel (Band nicht in `channels`) behalten
  `cap-wifiN`.
* `steer`: Steering je Band (RouterOS ≥ 7.21, D55), z.B.
  `"steer"={"2"={"threshold"=-78;"after"="10s";"kick"="5m"};"5"={"threshold"=-75;"after"="10s"}}`.
  Liegt ein Client länger als `after` unter `threshold` (dBm), schlägt ihm der AP per 802.11v die
  Nachbar-APs derselben SSID vor (`count` Vorschläge alle `period`, Standard 3 alle 30 s); `kick`
  trennt ihn, wenn er danach noch bleibt (weglassen = nie trennen). Ob ein anderer AP ihn besser
  hört, prüft RouterOS nicht – Schwellen vor Ort ermitteln und erst vorsichtig (ohne `kick`)
  einschalten.
* `minSignal`: Mindestsignal bei der Anmeldung (dBm, ein Wert für alle Bänder), z.B. `-82`.
  Schwächere Clients weist der AP ab (access-list). Vorsicht in Randbereichen ohne zweiten AP.
* `fallback="yes"` an einer weiteren SSID (z.B. Gast): Sie sendet auch im lokalen Fallback der APs
  weiter (D54, `slaves-static`). Die `master`-SSID tut das immer (D46). Noch nicht auf Hardware
  geprüft – nach dem Einschalten den CAPsMAN-Dienst kurz abschalten und nachsehen.
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

### `leases.rsc`

Feste DHCP-Leases je VLAN (D62), wirksam auf Geräten mit Rolle `router` in VLANs mit `dhcp`
(bei VRRP auf allen Routern, der DHCP-Server läuft nur auf dem Master):

```
:global cfmLeases {
  "30"={"drucker"={"mac"="02:00:00:00:00:30";"ip"=20};"kamera-hof"={"mac"="02:00:00:00:00:31";"ip"=21}}
}
```

* `ip` ist der Host-Anteil im Netz des VLANs (wie `gw`/`dhcp` in `vlans.rsc`), hier `.20`.
* Der Name ist Kommentar der Lease (`cfm:lease:<VID>:<name>`) und DNS-Name `<name>.<domain>` auf
  den Routern. Die Router führen außerdem die Namen aller aufgenommenen Geräte mit ihrer
  MGMT-Adresse (`sw1.<domain>`).
* `$cfmCheck` prüft: VLAN vorhanden (Warnung ohne DHCP), Name aus Buchstaben, Ziffern und `-`
  und kein Gerätename, MAC gültig und je VLAN eindeutig, Adresse im Netz, eindeutig und nicht die
  des Gateways (Warnung für .251–.254, dort liegen die eigenen Adressen von VRRP-Routern).
* Die MAC darf klein geschrieben sein, die Rolle schreibt sie wie RouterOS groß.
* Ohne Einträge steht dort `:global cfmLeases ({})` – ein leeres `{}` wäre ein Syntaxfehler.
* Ältere Releases ohne diese Datei bleiben gültig (die Datei ist im Manifest optional).

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

Das ist eine **Zusatzoption**, kein Ersatz für das Passwort: `$cfmSecret key=user.<name> value=…`
gilt unabhängig davon weiter. Aber: Hat ein User einen Key, lehnt RouterOS **SSH**-Anmeldungen
dieses Users per Passwort ab (`/ip/ssh always-allow-password-login=no`, Werkseinstellung) – nur
Winbox und WebFig gehen weiter mit Passwort. Ein kaputter Key sperrt also nicht ganz aus, SSH
aber schon. Auch kein Ersatz für die Geräteschlüssel der Rolle `manager` (`cfm`/`cfmd-<name>`) – die sind
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
| `cpuVlans` | nur Nicht-Router: VLANs, in denen die Bridge (CPU) getaggt bleibt, z.B. `{165;175;177}` – für eigene VLAN-Interfaces aus der `post.rsc` oder eines Bestandsgeräts, das noch selbst routet (7.3). MGMT ist immer dabei |
| `gw`, `dns`, `ntp` | nur Nicht-Router: Default-Route, DNS- und NTP-Server statt MGMT-Gateway bzw. `dns`/`ntp` aus `global.rsc` – für ein Gerät, das selbst das MGMT-Gateway ist, oder einen eigenen Ausgang (z.B. ein NAT-Käfig direkt über den Internet-Router). `ntp` auch als Liste |
| `bridgeFrames` | `"admit-all"`: die Bridge (CPU) nimmt weiter ungetaggte Frames an, statt nur getaggte – für eine Adresse direkt auf der Bridge (VLAN 1), die erhalten bleiben soll |
| `capsmanRadios` | nur auf dem CAPsMAN: `"yes"` provisioniert dessen eigene Radios über den eigenen CAPsMAN – dieselben SSIDs, Pins (`radios` mit der Identity des CAPsMAN) und Namen wie bei den APs (D53). Neu provisioniert nur bei geänderten WLAN-Daten (kurzer Aussetzer der eigenen Radios); wieder `"no"` bzw. weglassen setzt die Radios zurück. Noch nicht auf Hardware geprüft |

Im Hostfile darfst du auch zentrale Daten gezielt überschreiben, etwa
`:global cfmVlans; :set ($cfmVlans->"119"->"l3") "no"`.

---

## 5. Rollen

| Rolle | Konfiguriert |
|---|---|
| `base` (immer) | Identity; Bridge mit VLAN-Filtering; Ports nach Profil; Bridge-VLAN-Tabelle; MGMT-VLAN, -IP, Route, DNS, NTP; IP-Dienste nur aus MGMT, `mgmtExtra` und dem WireGuard-Subnetz; SSH-Härtung; Zeitzone, Syslog; Admin-Benutzer (bis zum Secret-Push deaktiviert); Werks-User `admin` abschalten; minimale Firewall (Nicht-Router) und IPv6-input-Firewall (alle Geräte); Nachbarsuche (LLDP) auf allen Bridge-Ports; Firmware-Auto-Upgrade (passt die RouterBOARD-Firmware nicht zur RouterOS-Version, flasht der Agent sie und startet einmal neu); persönliche Admin-SSH-Keys aus `authorized_keys` (optional); Agent |
| `switch` | IGMP-Snooping, DHCP-Snooping (bewusst schlank, Ports erledigt `base`) |
| `ap` | CAP des CAPsMAN (Adresse und Name aus dem Manifest, D45); erneuert die CAPsMAN-Zertifikate nach einem Umzug oder bei einem fremden CAPsMAN; lokaler Fallback: jedes Radio trägt eine Kopie der `master`-SSID (`capsman-or-local`, PSK per Secret-Push, D46); lokale Datapaths `cfm-cap` (virtuelle APs), `cfm-<master>` (Radios) und `cfm-mld` (MLO bei Wi-Fi 7); weitere SSIDs mit `fallback="yes"` auch im Fallback (`slaves-static`, D54) |
| `capsman` | komplette CAPsMAN-Konfiguration aus `wifi.rsc` inkl. PPSK, Kanal-Pools, Pinning und Kanal-Neuwahl; Dienst im MGMT-VLAN – eingeschaltet erst, wenn die PSK der `master`-SSID gesetzt ist (D45). Genau ein Gerät; ohne übernimmt der Primary-Manager; mit Hostfile `capsmanRadios="yes"` auch die eigenen Radios (D53) |
| `router` | VLAN-Interfaces und Adressen; VRRP (optional) mit DHCP nur auf dem Master, die VRRP-Interfaces in den Zonen-Listen; Zonen-Listen; Firewall als geordneter Block mit den Chains `local-input`/`local-forward` für eigene Regeln; DNS; NTP-Server; NAT nur für gekennzeichnete Policy-Ziele; Freigabelisten (`allow`); feste DHCP-Leases aus `leases.rsc` und DNS-Namen `<name>.<domain>` für Leases und aufgenommene Geräte (D62); DNS-Umleitung für Zonen ohne Internet; Update-Server-Adressliste; auf Switches mit L3-Hardware-Offloading (CRS3xx/5xx) schaltet sie das Routing im Switch-Chip ab (sonst umgeht es die Firewall, und VRRP funktioniert nicht); WireGuard-Fernzugang für Admins aus `wireguard.rsc` (optional, 8.8) |
| `manager` | Manager-Funktionen; SFTP-Gruppe der Geräte; Adresse und DHCP im Onboarding-VLAN; CAPsMAN nur, solange kein Gerät die Rolle `capsman` hat; Scheduler `cfm-mgr-tick` (alle `mgrTick`) und `cfm-mgr-onb-tick` (Onboarding, jede Minute), die nicht gleichzeitig arbeiten (D57) |
| `manager-backup` | wie `manager`, aber ohne CAPsMAN, spiegelt den Primary, Releases gesperrt |

Eigene Firewall-Regeln gehören auf allen Geräten in die Chain `local-input`, auf Routern
zusätzlich `local-forward`, zum Beispiel per `hosts/<name>.post.rsc`. Sie greifen vor dem finalen
Drop.

---

## 6. Inbetriebnahme

### 6.1 Vorlage anpassen

Lege deine Standortdaten als privates Overlay an; Git ignoriert die Verzeichnisse `site/` und
`site-*/`. `tools/new-site.py` legt es aus den Beispieldaten an, setzt Manager-Name, Uplink,
Admin-User und Management-Zugang ein und schreibt dazu eine `STAND.md` und einen
`bootstrap-manager.rsc` mit ausgefülltem Kopf:

```bash
tools/new-site.py site --name cm1 --uplink ether1 --user <dein-user> --mgmt-extra <admin-pc>/32
```

Die mitgelieferten Beispiele sind ein fiktives Netz (VLAN 10, 192.168.10.0/24), keine fertige
Konfiguration: Arbeite die nächsten Schritte in der `STAND.md` ab (Adressen, Inventar, Hostfiles,
WLAN). So bleiben deine Daten aus dem Repo, und neue Versionen des Frameworks lassen sich einfach
übernehmen. Die `STAND.md` begleitet die Site danach weiter: oben der aktuelle Stand, dann ein
Logbuch (neueste Einträge oben), die nächsten Schritte und offene Punkte; ausführliche Analysen
gehören in eine `BEFUNDE.md` daneben. `tools/upload-seed.sh` lädt aus dem Overlay nur die Daten
(`*.rsc`, `authorized_keys`, `hosts/`, `meta/` …); Notizen wie diese oder eigene CSV-Listen bleiben
lokal. Die Bootstrap-Datei
gehört nicht nach `work/` (das wird an die Flotte verteilt), sondern ins Wurzelverzeichnis des
Geräts – `--bootstrap <datei>` nimmt sie beim selben Aufruf mit, ohne Pfad die
`bootstrap-manager.rsc` aus dem Overlay.

### 6.2 Primary-Manager

1. Den Manager mit einem Port an einen Trunk hängen, der das MGMT-VLAN tagged führt.

   **Manager in einer VM:** Eine Karte je VLAN (`vport:<vid>`) und `stp="none"` im Hostfile (D40).
   Der Reset im Bootstrap nummeriert die Karten neu – die Zuordnung danach über die MAC-Adressen
   prüfen, nicht über die Reihenfolge. Das MGMT-VLAN kommt an einer solchen Karte ungetaggt an, der
   Bootstrap legt es aber getaggt auf den Uplink: Der Manager ist über seine MGMT-IP deshalb erst
   nach dem ersten Apply erreichbar, bis dahin über die Konsole des Hosts.
2. Die Vorlage hochladen, beim ersten Mal mit dem Inventar:
   ```bash
   tools/upload-seed.sh admin@<aktuelle-IP-des-Managers> --overlay site --seed-inventory
   ```
   Danach lebt das Inventar auf dem Manager (`$cfmRegister` und `$cfmEnroll` pflegen es). Spätere
   Uploads ohne `--seed-inventory` lassen es unangetastet, damit echte Seriennummern und Ringe nicht
   auf die lokale Vorlage zurückfallen; mit `--seed-inventory` bricht das Skript ab, sobald auf dem
   Gerät echte Seriennummern stehen (`--force` überschreibt trotzdem). Geht das Inventar doch
   verloren, holt `$cfmEnroll name=<name> ip=<ip> role=<rolle> ring=<n>` die Seriennummer vom Gerät
   zurück – sonst findet es sein Manifest nicht mehr, das unter der Seriennummer liegt. Jede Datei
   geht einzeln mit bis zu drei Versuchen hinüber; scheitert eine, bricht das Skript mit einer
   Meldung ab. Das Skript braucht einen SSH-Key (Batch-SFTP fragt kein Passwort ab).
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
4. **CAPsMAN** (Rolle `capsman`, z.B. `switch,capsman`) – am besten ein Gerät ohne VM darunter;
   ohne übernimmt der Primary-Manager (6.6).
5. **APs.**

### 6.5 Git-Sicherung (optional)

Anleitung im Kopf von `tools/git-host/cfm-git-sync`. Kurz: Linux-Host mit User `cfm`, Forced
Command für den Manager-Schlüssel, am Manager ein Lese-User `cfm-git` mit dem Schlüssel des
Git-Hosts, in `global.rsc` `hook` setzen und die Host-IP in `mgmtExtra` aufnehmen. Gesichert
werden Arbeitsstand, Metadaten, Archiv, Geräte-Exporte und das verschlüsselte Vault-Backup
(`vault/*.bak`), bei jedem Release, Rollback, Onboarding und bei neuen Exporten.

### 6.6 CAPsMAN auf ein eigenes Gerät legen oder umziehen

Der CAPsMAN ist ein eigener Dienst (Rolle `capsman`, D45), unabhängig vom Config-Manager. Die APs
erfahren über ihr Manifest (Feld `cm`), wo er läuft; wandert die Rolle, folgen sie beim nächsten
Lauf, erneuern ihre CAPsMAN-Zertifikate und verbinden sich neu. Den kurzen Abriss überbrücken
sie mit ihrer lokalen Kopie der `master`-SSID (D46).

1. Alle Geräte auf einem Stand mit D45/D46 (Release, alle Ringe). Einträge `caps-man-names` in
   `hosts/*.post.rsc` entfernen, sie würden die Namen aus dem Manifest überschreiben.
2. Rolle vergeben: `$cfmEnroll name=<gerät> ip=<mgmt-ip> role=<bisher>,capsman`. Das nimmt das
   Gerät mit neuer Rolle neu auf (neuer Geräteschlüssel, Agent neu, erster Lauf) und baut die
   Manifeste aller Geräte neu – ab da zeigen sie auf den neuen CAPsMAN. `$cfmCheck` lehnt zwei
   CAPsMAN-Geräte ab.
3. Zuerst den neuen CAPsMAN anwenden lassen: `$cfmPush host=<gerät>`. Er bleibt aus, bis die
   Passphrasen da sind – sofort nachschieben: `$cfmSecretPush host=<gerät>` (sonst im nächsten Tick).
4. Die APs und den bisherigen CAPsMAN anstoßen: `$cfmPush host=<ap>` bzw. `$cfmPush ring=…`.
   Der alte CAPsMAN schaltet sich ab und räumt seine WLAN-Profile weg.
5. Prüfen: auf dem neuen CAPsMAN `/interface/wifi/print` (je AP dynamische `cap-wifi*`), auf einem
   AP `/interface/wifi/cap/print` (`current-caps-man-identity`).

Fällt der CAPsMAN länger aus, genauso auf ein anderes Gerät verschieben.

Hat das CAPsMAN-Gerät eigene Radios, funken sie mit `capsmanRadios="yes"` in seinem Hostfile mit
(D53). Zieht der CAPsMAN um, den Schalter im Hostfile des alten Geräts entfernen (setzt dessen
Radios zurück) und beim neuen setzen.

### 6.7 Clients je AP in Home Assistant (D47)

Die Registration-Tabelle des CAPsMAN zeigt alle Clients aller APs. Für einen Monitoring-Host (z.B.
Home Assistant) öffnet cfm dort die RouterOS-API, nur lesend und nur für dessen Adresse:

1. `global.rsc`: `"capsmanApi"={"from"={"<ip-des-HA>/32"};"user"="homeassistant"}`, Passwort in den
   Vault: `$cfmSecret key=user.homeassistant value=…`, `$cfmRelease` (bzw. Ringe durchlaufen lassen).
   Der CAPsMAN bekommt Dienst `api` (8728, nur diese Adresse), Gruppe `cfm-api` (`read,api,test`),
   den User und eine Freigabe in `local-input`; der Secret-Push setzt das Passwort und schaltet ihn ein.
2. Liegt HA außerhalb des MGMT-VLANs, gibt die Rolle `router` den Weg von `capsmanApi.from` zum
   CAPsMAN auf dem API-Port frei (Firewall-Block, Ziel aus dem Manifest). Ein Router ohne Rolle
   `router` (Bestandsgerät, das noch selbst routet) braucht die Freigabe in seiner `post.rsc`:
   ```
   :global cfmG; :global cfmMf; :global cfmBlock
   :local capi ($cfmG->"capsmanApi")
   :local fl ({})
   :if ([:typeof $capi] = "array") do={
     :local port [:tostr ($capi->"port")]
     :if ([:len $port] = 0) do={ :set port "8728" }
     :foreach c in=($cfmMf->"cm") do={ :foreach a in=($capi->"from") do={
       :set ($fl->[:len $fl]) ({"chain"="forward";"action"="accept";"protocol"="tcp";"src-address"=$a;"dst-address"=[:tostr ($c->"ip")];"dst-port"=$port}) } }
   }
   $cfmBlock m="/ip/firewall/filter" k="capifwd" l=$fl
   ```
   Ein neuer Regelblock steht ganz oben in `/ip/firewall/filter`, also vor eigenen Sperrregeln.
3. In HA die Integration einrichten: Host = MGMT-IP des CAPsMAN, Port 8728, ohne SSL, User/Passwort
   wie oben. Zieht der CAPsMAN um, dort die Adresse ändern (die Freigaben ziehen selbst mit).

---

## 7. Geräte aufnehmen

### 7.1 Automatisch: Push in die Werks-Config (empfohlen)

Voraussetzung: Router und Switches bis zum Zielport sind bereits aufgenommen (sonst
`manual=yes`, siehe Ende des Abschnitts).

1. **Registrieren** mit Seriennummer und Passwort vom Aufkleber (Geräte ohne
   Aufkleber-Passwort: `pw` weglassen):
   ```
   $cfmRegister name=ap3 serial=HG1234567 role=ap ring=1 ip=192.168.10.33 pw="…"
   ```
   Dazu `cfm/work/hosts/ap3.rsc` mit dem Uplink-Port anlegen und `$cfmRelease`.

   > **Tipp:** Die Seriennummer nicht abtippen, sondern den **Datamatrix-Code** auf dem
   > Aufkleber mit dem Handy scannen und per Copy & Paste einfügen. Ein Zahlen- oder
   > Buchstabendreher fällt sonst erst spät auf: Der Schlüssel `mac.<Seriennummer>` passt dann
   > nicht, das Framework erzeugt für das Gerät kein Manifest, und es bleibt still auf dem
   > Stand ohne Konfiguration.
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

**Switch am Zielport noch nicht aufgenommen** (z.B. das erste Gerät hinter einem Bestands-Switch,
D50): Den Port schaltest du selbst, der Manager erledigt den Rest wie oben.
```
$cfmOnboard manual=yes name=ap3 sw=core port=ether7     # sw/port nur als Notiz
```
1. Vorher den Port am Switch **von Hand** ins Onboarding-VLAN schalten: untagged, PVID = VID des
   Onboarding-VLANs (die Meldung nennt sie), `frame-types=admit-all`.
2. Gerät einstecken; Fortschritt mit `$cfmOnboardStatus` („Sitzung manuell …“).
3. Nach dem Ende (Erfolg, Fehler, Timeout oder `$cfmOnboardAbort`) steht im Log des Managers
   „Port jetzt von Hand zurück auf sein Profil stellen“ – cfm fasst den Port nie an, es gibt
   auch keinen Fail-safe-Timer.

### 7.2 Manuell: Bootstrap-Datei

Für Sonderfälle oder wenn das Onboarding-VLAN (noch) nicht zur Verfügung steht:

1. `$cfmBootstrap` erzeugt `cfm/cfm-bootstrap.rsc` (mit den Manager-Schlüsseln).
2. Datei aufs Gerät bringen (Winbox → Files), im Kopf `ip` und `uplink` anpassen, `/import cfm-bootstrap.rsc`.
3. Am Manager: `$cfmEnroll name=sw3 ip=192.168.10.23 role=switch ring=1`.

Das Hostfile muss den Uplink-Port mit einem Trunk-Profil führen, sonst verliert das Gerät beim
ersten Apply seinen MGMT-Zugang (der Watchdog rollt dann zurück).

### 7.3 Bestandsgeräte übernehmen

Zuerst sichern (`/export terse`, `/system/backup/save`) und das Hostfile aus dem echten Export
bauen – vor allem die Ports: Uplinks mit dem Profil, das die Gegenseite heute liefert (z.B.
`hybrid:<vid>`), Ports, hinter denen ein Switch hängen kann, mit `vport:<vid>` statt `access:<vid>`
(ohne BPDU-Guard, wie bisher).
Die Umstellung auf VLAN-Filtering ist ein Eingriff; am besten zuerst ein Gerät in Ring 0.

**Mit Reset** (nichts Eigenes muss bleiben): gerätespezifischer Bootstrap (`$cfmBootstrap
name=<n>`) aufs Gerät, `/system/reset-configuration no-defaults=yes keep-users=yes
skip-backup=yes run-after-reset=<n>-bootstrap.rsc`, danach `$cfmEnroll`. Eigene Funktionen (z.B.
ein NAT-Käfig, Freigaben) vorher in `hosts/<n>.post.rsc` übernehmen, sonst sind sie weg.

**Ohne Reset** (Skripte, Dienste o.ä. sollen bleiben – cfm lässt Objekte ohne cfm-Tag stehen):

1. Auf dem Gerät von Hand, was sonst der Bootstrap macht: User `cfm` (Gruppe `full`) mit dem
   Manager-Schlüssel (Inhalt wie `keys` in der Bootstrap-Datei), das MGMT-VLAN-Interface
   `vlan<mgmtVlan>` auf der Bridge `bridge` und die MGMT-Adresse. Heißen Bridge oder MGMT-Interface
   anders, vorab umbenennen oder mit dem cfm-Tag versehen (`comment="cfm:vlan:<vid> …"`).
   Passen mehrere Objekte auf dasselbe Suchmuster – etwa zwei Adressen am MGMT-Interface –, die
   richtige vorab taggen (`comment="cfm:ip:mgmt"`), sonst übernimmt die Rolle die erste gefundene.
2. `$cfmEnroll name=<n> ip=<ip> role=<rolle> ring=<0-2> noapply=yes` – Agent und Schlüssel werden
   installiert, der Agent-Scheduler bleibt aus.
3. `$cfmPlan host=<n>` zeigt jede Änderung des ersten Applys. Die Objekte aus `hosts/<n>.post.rsc`
   fehlen darin (Probelauf überspringt sie).
4. Anwenden mit `$cfmPush host=<n> force=yes`; der Apply schaltet den Scheduler ein. **Nicht**
   `/system script run cfm-agent` aus einer Admin-Sitzung: Der Download läuft mit dem Schlüssel
   des aufrufenden Users, den nur `cfm` hat („kein Manager erreichbar“).
5. `$cfmAudit host=<n>` zeigt, was cfm nicht verwaltet: Werks-Reste entfernen (`op=purge`), was
   bleiben soll, als Override markieren (`op=mark`) – vor allem **Bridge-VLAN-Einträge mit
   mehreren VLAN-IDs** (Kollision).

**Gerät routet noch selbst** (z.B. ein Core-Switch mit L3 im Switch-Chip vor dem Router-Umzug):
Rolle `switch` reicht, die L3-Objekte bleiben unverwaltet. Damit der erste Apply sie nicht
beschädigt (D43): im Hostfile `cpuVlans` (die Bridge bleibt in den VLANs der eigenen
VLAN-Interfaces getaggt), `gw`/`dns`/`ntp` (sonst zeigen Route, DNS und NTP auf das Gerät selbst),
ggf. `bridgeFrames="admit-all"`; in der `post.rsc` Freigaben in `local-input` für die Dienste, die
das Gerät für andere erbringt (DHCP UDP 67, NTP 123, SNMP 161, DNS …) – der input-Block der Rolle
`base` verwirft sonst alles außer MGMT.

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
Port-Profile, doppelte MGMT-IPs, Rollen ohne Datei, unbekannte IP-Dienste oder doppelte Ports in
`services`. Mit `force=yes` releast du bewusst trotzdem.
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
Die cfm-Objekte, die diese Datei beim letzten echten Apply angelegt hat, behält er trotzdem
(`… im Probelauf übersprungen, N Objekte daraus beibehalten`); Änderungen an der `.post.rsc`
selbst zeigt er nicht.
Das Ergebnis liegt auch in `cfm/state/<name>/plan.txt`.

**Effektive Konfiguration eines Geräts** (D61):

```
$cfmShow host=sw1              # Daten: Rollen, Ring, Hostfile, Ports mit Profil, VLANs, WLAN, Leases
$cfmShow host=sw1 ver=41       # dasselbe aus Release 41 statt aus work/
$cfmShow host=sw1 objects=yes  # Soll-Objekte: jedes Objekt, das cfm dort verlangt (Probelauf)
```

Ohne `objects` rechnet der Manager allein, auch für Geräte, die gerade nicht erreichbar sind.
`objects=yes` lässt das Gerät seine Rollen wie beim Probelauf durchgehen und listet alle
verlangten Objekte mit Schlüssel und Sollwerten (lange Werte gekürzt, ohne `post.rsc`); ein Agent
vor diesem Stand liefert stattdessen den normalen Plan.

**Unterschiede zwischen zwei Ständen** (D61):

```
$cfmDiff                       # letztes Release -> work/: was ändert das nächste Release?
$cfmDiff ver=40 to=41          # zwischen zwei Releases (to=work ist der Standard)
```

Ausgabe: geänderte, neue und entfernte Dateien, die betroffenen Geräte (bei gemeinsamen Dateien
wie `global.rsc` oder `lib/lib.rsc` alle), für Datendateien (`global`, `vlans`, `profiles`,
`wifi`, `wireguard`, `leases`, `hosts/*`, `authorized_keys`) die geänderten Zeilen
(`@@ Zeile <alt> / <neu>`, `-` alt, `+` neu). `lib/` und `roles/` erscheinen nur als Datei.

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
| Vorher sehen, was sich ändert | `$cfmDiff` (Dateien und Zeilen), `$cfmPlan host=<name>` (Objekte auf dem Gerät) |
| Effektive Konfiguration eines Geräts | `$cfmShow host=<name>` bzw. `objects=yes` |
| Feste Adresse und DNS-Name für ein Gerät im VLAN | `leases.rsc` → Release (nur mit Rolle `router`) |
| RouterOS aktualisieren | `$cfmUpgrade ver=<x.y.z> ring=0`, später die anderen Ringe (siehe 8.6) |
| Geräteschlüssel erneuern | `$cfmRekey host=<name>` bzw. `all=yes` |
| Archiv verkleinern | `$cfmArchivePrune keep=5` (sonst automatisch mit `archiveKeep`) |
| Verkabelung prüfen, Netzplan | `$cfmLinks`; Soll einfrieren mit `accept=yes`, Graphviz/CSV mit `export=yes` (siehe 8.7) |
| Zweite Passphrase mit eigenem VLAN | `ppsk` in `wifi.rsc` → Release → `$cfmSecret key=ppsk.<ssid>.<name> value=…` |
| WLAN-Kanäle ansehen | `$cfmChannels` |

### 8.5 Überblick

* `$cfmStatus` zeigt je Gerät Ring, Soll- und Ist-Version, Ergebnis (`ok`, `failed …`,
  `bad vN`, `pend vN`, `fw X!` = Firmware X trotz Neustart nicht aktiv, `WLAN lokal` = AP ohne Verbindung zum CAPsMAN,
  sendet nur die lokale Kopie der `master`-SSID, D46; `nicht aufgenommen` = Inventar-Eintrag ohne
  Geräteschlüssel, z.B. Platzhalter oder per `$cfmRegister` vorgemerkt – solche Geräte stößt der
  Manager nicht an, D49), Secrets-Version, RouterOS-Version (bei offenem Auftrag mit Zielversion)
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
$cfmUpgrade ver=7.25.1 all=yes check=yes                # Probe: Pakete, Platz - kein Auftrag
$cfmUpgrade                                             # offene Aufträge und ihr Stand
$cfmUpgrade cancel=yes ring=1                           # Auftrag zurückziehen
$cfmUpgrade ver=7.25.1 host=hex1 via=mirror mirror=192.168.10.50   # eingebautes Update vom Spiegel
$cfmUpgrade ver=7.25.1 host=core via=internet           # eingebautes Update, Gerät hat Internet
```

* Der Manager lädt vorher alle nötigen Pakete (`routeros` und Zusatzpakete wie `wifi-qcom`) für
  alle Architekturen der betroffenen Geräte von download.mikrotik.com nach `pkgPath` und prüft die
  NPK-Kennung am Dateianfang. Fehlt eines oder ist es ungültig, startet nichts; die Meldung nennt
  alle fehlenden Dateien auf einmal. Architektur, Pakete und freien Platz meldet jedes Gerät in
  seinem Status. Nicht aufgenommene Inventar-Einträge überspringt `ring=`/`all=yes` (D49).
* Vor dem Auftrag zeigt eine Tabelle je Gerät Version, Architektur, Bedarf, freien Platz und
  Urteil. `check=yes` zeigt nur diese Tabelle und die fehlenden Pakete (mit Download-URL und
  Ablageort) – ohne Download und ohne Auftrag, auch auf dem Backup-Manager (D52).
* **Platz:** Passen die Pakete plus 1 MB Reserve nicht in den gemeldeten freien Platz, bekommt das
  Gerät keinen Auftrag („zu wenig Platz … kein Auftrag“), die übrigen schon. Der Agent prüft vor
  dem Download noch einmal und lädt dann nichts („Platz fehlt: … KB frei, … KB nötig“ in
  `$cfmUpgrade`); nach dem Aufräumen einen neuen Auftrag erteilen (D51). Geräte mit
  `flash/`-Verzeichnis melden keinen Wert (ihre Wurzel liegt im RAM) und werden nicht geprüft.
* Die Geräte holen die Pakete per SFTP vom Manager, prüfen die Größe und starten sofort bzw. zum
  Zeitpunkt `at` neu. RouterOS prüft die Signatur der Pakete beim Installieren.
* Eine ältere Zielversion bedeutet **Downgrade** (`/system/package/downgrade`); die Konfiguration
  bleibt erhalten.
* Vorabversionen gehen genauso (`ver=7.25beta5`, `ver=7.25rc1`). Sie zählen als älter als die fertige
  Version: 7.25beta5 < 7.25rc1 < 7.25 < 7.25.1. Von 7.24.4 auf 7.25beta5 ist also ein Update,
  von 7.25beta5 zurück auf 7.24.4 ein Downgrade.
* Die Geräte laden die Pakete sofort, nur der Neustart wartet auf das Fenster. Ist das Fenster
  schon vorbei, wenn die Pakete da sind (Gerät war offline, Download zu langsam), startet das
  Gerät nicht und meldet „Fenster verpasst“. Erteile dann einen neuen Auftrag.
* Läuft ein Gerät nach dem Neustart nicht mit der Zielversion, meldet es „fehlgeschlagen“ und
  versucht es nicht erneut.
* Erledigte Aufträge trägt der Manager selbst aus, Paketversionen ohne Einsatz löscht er.
* Nutze die Ringe: erst Ring 0, prüfen, dann die anderen.
* Der Manager braucht Internetzugang, die Geräte nicht. Die Pakete werden nicht auf den
  Backup-Manager gespiegelt, offene Aufträge brauchen den Primary.
* **Manager ohne Internet:** alle installierten Pakete der betroffenen Geräte (je Architektur, z.B.
  `routeros`, `wifi-qcom`, `container`, `iot` …) vorab nach `<pkgPath>/<ver>/` legen
  (`<paket>-<ver>-<arch>.npk`, bei x86 ohne Architektur). Welche ein Gerät hat, steht in dessen
  Status (`pkgs`); am einfachsten vorab `$cfmUpgrade ver=… all=yes check=yes` aufrufen, das listet
  alle fehlenden Dateien. Platz auf dem Manager beachten; nicht mehr gebrauchte Pakete einer
  laufenden Version darfst du von Hand löschen.
* **Geräte mit 16 MB Flash** (hEX, CRS328 …) haben oft nur 2–3 MB frei, `routeros` braucht ~12 MB:
  Dort lehnt `$cfmUpgrade` den normalen Auftrag ab (TODO 38). Für sie gibt es das **eingebaute
  Update** (D63, `via=`): Das Gerät lädt selbst und kommt mit wenig Flash zurecht (RouterOS lädt dann
  in den RAM). Der Manager braucht dafür keine Pakete und prüft keinen Platz.
  * `via=internet`: Das Gerät braucht selbst Internet (und DNS).
  * `via=mirror mirror=<IP>`: Für Geräte ohne Internet. Auf einem Rechner, den die Geräte
    erreichen, läuft `sudo tools/upgrade-mirror.py <ver>` (Port 80; er holt die Dateien bei Bedarf
    von MikroTik und speichert sie zwischen, ohne Internet vorher unter `<dir>/routeros/<ver>/`
    ablegen). Der Agent leitet `upgrade.mikrotik.com` per statischem DNS-Eintrag
    (`cfm-sys:upgrade-mirror`) auf den Spiegel um und stellt das eingebaute Update auf HTTP; nach
    dem Update nimmt er beides zurück. Die Pakete sind von MikroTik signiert, RouterOS prüft das beim
    Installieren. Beim Wartungsfenster (`at=`) muss der Spiegel zu dieser Zeit laufen.
  * Nur Upgrades, und nur auf die Version, die Internet bzw. Spiegel anbieten: Bietet das Internet
    inzwischen eine neuere Version an, installiert der Agent nichts und meldet
    „fehlgeschlagen: internet bietet … statt …“. Vorabversionen holt er über den Kanal `testing`.

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
  Kanal nutzen. Die Kanäle wählt der CAPsMAN aus den Pools in `wifi.rsc` (Neuwahl `reselect`),
  feste Kanäle je AP über `radios`.
* `$cfmWifiScan [host=<ap>] [band=2] [duration=10s]` lässt alle APs nacheinander auf ihren Radios
  des Bands scannen (D56). Ein Radio unter CAPsMAN-Kontrolle lehnt den Scan am AP ab; cfm scannt
  deshalb auf dem CAPsMAN am Interface `<AP>-<Band>g` (D60), Radios ohne CAPsMAN direkt am AP.
  Unter 10 s Dauer liefert der CAPsMAN keine Ergebnisse, kürzere Angaben hebt der Befehl auf 10 s
  an. **Während des Scans verlässt das Radio seinen Kanal, verbundene Clients wechseln kurz zum
  Nachbarn** – also nicht zur Hauptnutzungszeit. Ausgabe je AP: fremde Netze nach
  Frequenz (Anzahl/stärkstes Signal), welche eigenen APs sich hören (BSSIDs vom CAPsMAN), die Kosten
  des aktuellen Stands und je ein Vorschlag für 1/6/11 und 1/5/9/13 samt fertiger Zeile für
  `radios` in `wifi.rsc` (dort von Hand übernehmen, bestehende 5/6-GHz-Pins ergänzen, Release).
  Die Messung liegt in `state/wifiscan.json`; `data=yes` rechnet ohne neuen Scan.

### 8.8 WireGuard-Fernzugang

Für Admins, die Geräte ohne direkten Laptop-Zugriff erreichen müssen (kein Agent-Forwarding im
RouterOS-SSH-Client, daher kein Sprung über einen Manager möglich): ein WireGuard-Tunnel zum
Router (Rolle `router`), dessen Peers als Zone `mgmt` zählen – volle Rechte wie ein Gerät im
MGMT-VLAN. Siehe `wireguard.rsc`.

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
| Primary-Manager fällt aus | Geräte ziehen vom Backup; ist der Primary zugleich CAPsMAN, senden die APs im lokalen Fallback weiter (ohne FT zwischen den APs) | bei längerem Ausfall auf cm2 `$cfmPromoteManager`, dann `managers` tauschen und releasen |
| Primary kommt zurück | – | nach einer Beförderung den alten Primary neu als Backup aufsetzen |
| CAPsMAN fällt aus | APs senden nach ~10 s mit der lokalen Kopie der `master`-SSID weiter (weitere SSIDs noch nicht, TODO 40); kommt er zurück, übernimmt er wieder | bei längerem Ausfall die Rolle `capsman` auf ein anderes Gerät verschieben (6.6) |
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
* **Persönliche Admin-SSH-Keys:** optional über `authorized_keys` (siehe Datenmodell). Das
  Passwort gilt danach nur noch für Winbox/WebFig, SSH verlangt den Key. Existiert die Datei, entfernt jeder Apply Keys, die nicht mehr
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
* Ein leeres Array direkt nach `:global`/`:local` (`{}`, auch über zwei Zeilen) ist ein Codeblock
  und beim `/import` ein Syntaxfehler – `({})` schreiben.
* Kein String-Literal mit Escape (`\n`, `\"`, `\$`) direkt als Argument einer eigenen Funktion –
  positionell wie `k="…"` ein Syntaxfehler, an der Konsole wie beim `/import`. In runde Klammern
  setzen (`$cfmWrite "x.json" ("{\"a\":1}")`) oder vorher in eine Local legen. Eingebaute Befehle
  (`:pick`, `/file/set …`) sind nicht betroffen.
* `:for i from=5 to=4` läuft rückwärts (zweimal) – Schleifen über eine möglicherweise leere
  Spanne vorher mit `:if` absichern.
* Kein Operator `!~` („cannot invert string“), stattdessen `!($x ~ "re")`.
* Fehlertexte aus `:onerror` nie per `=` vergleichen: RouterOS 7.24.4 hängt „ (:error; line N)“ an,
  also per `~ "^text"` prüfen.
* `:return` innerhalb von `:onerror … in={}` verlässt die Funktion nicht, ein Flag benutzen.
* Geräteabhängige Menüs (z.B. `/system routerboard`) in Leerzeichen-Schreibweise, sonst ist das
  Fehlen auf CHR/x86 ein nicht abfangbarer Syntaxfehler.

Die vollständige Liste steht im Kopf von `cfm/work/lib/lib.rsc` und in [DECISIONS.md](DECISIONS.md#im-chr-labor-verifizierte-routeros-eigenheiten-7242),
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
                          # Router, Leases/DNS, $cfmShow/$cfmDiff, Archiv, Schlüsselwechsel,
                          # RouterOS-Downgrade und Update vom Spiegel, Netzplan, PPSK, WLAN-Scan,
                          # Bestandsgeräte (Hostfile gw/dns/ntp/cpuVlans/bridgeFrames, Enroll ohne Apply) …
./e2e-onboard.sh fresh    # automatisches Onboarding eines "Werksgeräts" (Werks-IP 192.168.88.1)
./e2e-onboard.sh fresh dhcp   # dasselbe im CAPs-Modus (DHCP-Client, wie ein hAP an PoE/ether1)
./e2e-onboard.sh fresh manual # Switch gilt als nicht verwaltet ($cfmOnboard manual=yes)
./e2e-vrrp.sh             # Router-Umzug: drei VRRP-Router hinter einem Internet-Router im LAN (4 VMs)
./lab.sh stop
```

`e2e-vrrp.sh` startet vier VMs: cm1 (Manager, zentraler Switch, dritter Router), r1 und r2 als
Router, vm4 als nicht verwalteter Internet-Router mit je einer VRF als Client in IoT und Gast
(Daten in `seed-vrrp/`). Geprüft werden VIPs und DHCP nur auf dem Master, die Zonen-Policy samt
fester NAT-Adresse der Gäste, Ausfall und Rückkehr des Masters, sein Neustart und der Ausfall von
zwei Routern.
`lab.sh` nimmt das neueste `chr-*.img` im Labor-Verzeichnis; eine andere Version per
`CHR_IMG=…/chr-7.24.2.img ./e2e.sh fresh`. Zwei Labore gleichzeitig brauchen ein eigenes
Verzeichnis und eigene Port-Basen, z.B. `LAB=~/.cache/cfm-chr-lab-b LABPORT=2300 LABSOCK=13000
./e2e.sh fresh` (Standard 2200/12000). Ein laufendes `e2e*.sh` nie bearbeiten – bash liest es
stückweise; bei längeren Läufen aus einer Kopie des Baums starten.

Das CHR-Image lädst du von download.mikrotik.com (`chr-<version>.img.zip`, entpacken). Mit
`./lab.sh ssh <n>` kommst du an die Konsole einer VM. Funkteile lassen sich auf CHR nicht testen.
Die Lab-Hostfiles setzen `adminUser="keep"`, weil `lab.sh` sich als `admin` anmeldet.
Der Update-Schritt lädt ein RouterOS-Paket (ca. 20 MB) aus dem Internet; dafür legt der Test auf
cm1 zwei Routen über `ether1` an. SFTP zwischen den CHRs ist langsam (etwa 100 KB/s), der Schritt
dauert deshalb einige Minuten. Danach aktualisiert sich cm2 mit dem eingebauten Update über
`tools/upgrade-mirror.py` (D63): Die VMs erreichen den Spiegel als `10.0.2.100:80`, `lab.sh` leitet
das per QEMU auf `127.0.0.1:LABPORT+90` des Rechners weiter (braucht `nc`); der Zwischenspeicher
liegt unter `$LAB/mirror`.

---

## 13. Befehlsreferenz

Nach `/system script run cfm-mgr` im Terminal des Primary-Managers:

| Befehl | Wirkung |
|---|---|
| `$cfmRelease [msg="…"] [all=yes] [force=yes]` | `work/` prüfen und als neue Version an Ring 0 (bzw. alle) freigeben; `force=yes` trotz inhaltlicher Prüffehler |
| `$cfmCheck` | inhaltliche Prüfung von `work/` (läuft bei jedem Release) |
| `$cfmPlan host=<n>` | Probelauf: was ein Release von `work/` auf dem Gerät ändern würde |
| `$cfmShow host=<n> [ver=<N>] [objects=yes]` | effektive Konfiguration: zusammengeführte Daten bzw. Soll-Objekte vom Gerät (8.3) |
| `$cfmDiff [ver=<A>] [to=<B>\|work]` | Unterschiede zwischen zwei Ständen: Dateien, betroffene Geräte, Zeilen der Datendateien (8.3) |
| `$cfmArchivePrune [keep=<n>]` | alte Versionen löschen (automatisch nach jedem Release) |
| `$cfmPromote [ring=1\|2]` | Version des vorigen Rings freigeben |
| `$cfmRollback ver=<N> [all=yes]` | alten Stand als neue Version freigeben (überschreibt `work/`) |
| `$cfmStatus` | Flottenübersicht |
| `$cfmPush [host=<n>\|ring=<r>] [force=yes]` | sofortigen Pull auslösen (nur aufgenommene Geräte, D49) |
| `$cfmCollect [host=<n>]` | Status und Export sofort abholen |
| `$cfmAudit host=<n> [op=report\|mark\|purge] [sel=all\|A1,A3]` | unverwaltete Objekte anzeigen, markieren, entfernen |
| `$cfmSecret key=<k> value=<v>` | Vault-Eintrag setzen (`user.<name>`, `psk.<ssid>`, `vaultpw`) |
| `$cfmSecretPush [host=<n>]` | Secrets sofort verteilen |
| `$cfmVaultBackup` | verschlüsseltes Manager-Backup nach `vault/` |
| `$cfmRekey host=<n>\|all=yes` | Geräteschlüssel erneuern |
| `$cfmUpgrade ver=<x.y.z> host=<n>\|ring=<r>\|all=yes [at="YYYY-MM-DD HH:MM"]` | RouterOS-Update oder -Downgrade, sofort oder im Wartungsfenster |
| `$cfmUpgrade ver=<x.y.z> host=…\|ring=…\|all=yes check=yes` | Probe ohne Download und Auftrag: Bedarf, freier Platz, fehlende Pakete |
| `$cfmUpgrade ver=<x.y.z> host=…\|ring=… via=internet\|via=mirror mirror=<IP>` | eingebautes Update des Geräts, auch bei 16 MB Flash (D63, Spiegel: `tools/upgrade-mirror.py`) |
| `$cfmUpgrade` · `$cfmUpgrade cancel=yes host=…\|ring=…\|all=yes` | offene Aufträge anzeigen bzw. zurückziehen |
| `$cfmPkgPrune` | Paketversionen ohne Einsatz löschen (läuft automatisch) |
| `$cfmLinks [accept=yes] [export=yes]` | Verkabelung prüfen, Netzplan schreiben; Baseline einfrieren bzw. Graphviz/CSV |
| `$cfmChannels` | Kanäle der APs, Warnung bei gleichem Kanal an einem Switch |
| `$cfmWifiScan [host=<ap>] [band=2] [duration=10s] [data=yes]` | Kanal-Scan aller APs nacheinander über den CAPsMAN (Clients wechseln kurz), Pin-Vorschlag für 2,4 GHz |
| `$cfmRegister name= serial= ip= [role=] [ring=] [pw=]` | Gerät für das Onboarding registrieren |
| `$cfmOnboard sw= port= [name=]` · `$cfmOnboardStatus` · `$cfmOnboardAbort` | automatisches Onboarding |
| `$cfmOnboard manual=yes [name=] [sw= port=]` | Onboarding hinter einem nicht verwalteten Switch, Port schaltet der Admin (D50) |
| `$cfmPending` · `$cfmApprove serial= name= ip= [role=] [ring=]` | unbekannte Geräte |
| `$cfmBootstrap` | Bootstrap-Datei für die manuelle Aufnahme |
| `$cfmEnroll name= ip= [role=] [ring=] [rekey=yes] [noapply=yes]` | Gerät aufnehmen (manuell); `noapply=yes`: ohne ersten Apply, Scheduler aus (7.3) |
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
| `state/wifiscan.json` | letzte Messung von `$cfmWifiScan` (nur mit gemessenen Netzen) |
| `vault/<name>-vault.bak` | verschlüsseltes Manager-Backup |

`.dat` statt `.json`, weil RouterOS lesenden SFTP-Nutzern `.json`- und `.backup`-Dateien verweigert.

**Auf jedem Gerät:** User `cfm` (Manager-Schlüssel), Skripte `cfm-agent` und `cfm-conf`, Scheduler
`cfm-agent` (Takt) und `cfm-agent-boot` (20 s nach jedem Neustart), Geräteschlüssel als `/ppp secret` `cfm:key`, Dateien `cfm/state.json`, `cfm/out/`,
`cfm/dl/`, `cfm/pre.backup`, mit `hosts/<name>.post.rsc` `cfm/post.json` (deren cfm-Objekte, für
den Probelauf), beim Probelauf `cfm/pl/` und `cfm/out/plan.txt`; Firewall-Blöcke
`cfm:fwb…` (Nicht-Router) und `cfm:fw6…` (IPv6); Interface-Liste `DISC` (Nachbarsuche); während eines Applys der Scheduler
`cfm-watchdog`, nach einem übersprungenen Lauf `cfm-agent-retry`, während eines Onboardings auf dem
Switch `cfm-onboard-revert`, bei einem geplanten RouterOS-Update `cfm-upgrade` und die Pakete im
Wurzelverzeichnis, beim eingebauten Update über einen Spiegel der DNS-Eintrag `cfm-sys:upgrade-mirror`.

---

## 15. Fehlersuche

| Symptom | Ursache | Abhilfe |
|---|---|---|
| Gerät meldet „kein Manager erreichbar“ | Route/Gateway im MGMT-Netz, Firewall, Manager-Dienste nur aus MGMT | Ping zum Manager vom Gerät, `managers` prüfen. Der Agent hat da schon 2 min lang wiederholt (8/16/32/64 s, Log „Manifest nicht abrufbar – neuer Versuch“, D58); kurze Aussetzer, etwa während ein Backup-Manager spiegelt, fängt das ab |
| „Manifest-MAC ungültig“ | Geräteschlüssel passt nicht mehr (Reset, Restore); direkt nach `$cfmRekey` kurzzeitig normal | `$cfmEnroll name=<n> ip=<ip> rekey=yes` |
| „Release abgebrochen (Prüfung)“ | inhaltlicher Fehler in `work/` | Meldung lesen und beheben; bewusst: `force=yes` |
| Secret-Push: „Identitätsprüfung fehlgeschlagen“ | Geräteschlüssel passt nicht, oder ein anderes Gerät antwortet unter der IP | Gerät prüfen; nach einem Reset `$cfmEnroll … rekey=yes` |
| Probelauf: „keine Antwort“ | Agent war gerade beschäftigt | später erneut |
| Update: `Fenster verpasst` / `fehlgeschlagen` | Pakete zu spät da bzw. Installation gescheitert | `$cfmUpgrade` zeigt den Stand, Log am Gerät, neuen Auftrag erteilen |
| Eigener Dienst am Gerät nicht erreichbar, Log `cfm-drop` | minimale Firewall | Regel in der Chain `local-input` oder Netz in `mgmtExtra` |
| Agent meldet „kein Manager erreichbar - der Agent läuft als …“ (bzw. nur „kein Manager erreichbar“ und SFTP „authentication failure“) nach Start von Hand | `/system script run cfm-agent` aus einer Admin-Sitzung: der Download nimmt den Schlüssel des aufrufenden Users, nur `cfm` hat ihn | `$cfmPush host=<n>` am Manager (läuft als `cfm`) |
| Zwei Default-Routen (ECMP), eine ohne cfm-Tag | Bootstrap-Route eines vor dem Fix (TODO 34) aufgenommenen Geräts neben einer Route mit `gw=` aus dem Hostfile | die Route ohne Tag löschen |
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
| Log `cfm: WLAN im lokalen Fallback`, in `$cfmStatus` `WLAN lokal` | AP erreicht den CAPsMAN nicht (CAPsMAN aus, MGMT-Verbindung, Zertifikat) – nur die `master`-SSID läuft weiter | am CAPsMAN `/interface/wifi/capsman/print`, am AP `/interface/wifi/cap/print` (`current-caps-man-identity`) und das Log (`caps`) |
| Log `cfm: RouterBOARD-Firmware … geflasht … Neustart zum Aktivieren` | gewollt: neue Firmware wird nach einem RouterOS-Update erst mit einem weiteren Neustart aktiv | nichts zu tun, der Agent startet einmal neu |
| Log `cfm: RouterBOARD-Firmware … nach dem Neustart nicht aktiv`, in `$cfmStatus` `fw X!` | Flashen hat nicht gewirkt; der Agent startet dafür nur einmal neu | auf dem Gerät `/system/routerboard/print` prüfen, `/system/routerboard/upgrade`, dann `/system/reboot` |
| `upload-seed.sh`: „ABBRUCH: … enthält echte Seriennummern“ | `--seed-inventory` auf einen Manager mit aufgenommenen Geräten | ohne `--seed-inventory` hochladen; nur mit `--force`, wenn das Inventar wirklich ersetzt werden soll |
| Bridge-Port inaktiv, Log „BPDU guard changed port role to disabled“ | Edge-Port (`access`) bekommt BPDUs, z.B. von der Bridge eines Virtualisierungshosts | Profil `vport:<vid>` verwenden, Port einmal `disabled=yes` und wieder `no` setzen |
| `$cfmPush`: „kein Push (nicht aufgenommen): …“, `$cfmStatus`: `nicht aufgenommen` | Inventar-Eintrag ohne Geräteschlüssel (Platzhalter oder per `$cfmRegister` vorgemerkt) | gewollt; Gerät aufnehmen (Kapitel 7) oder Eintrag aus `meta/inventory.rsc` löschen |
| `$cfmUpgrade`: „zu wenig Platz für die Pakete … kein Auftrag“, Agent: „Platz fehlt“ | Pakete + 1 MB Reserve passen nicht in den freien Speicher (16-MB-Geräte) | aufräumen (`/file`), dann neuer Auftrag; sonst das eingebaute Update mit Internet am Gerät (TODO 38) |
| `$cfmUpgrade`: „Pakete fehlen oder sind ungültig“ | Manager ohne Internet oder Paket ohne NPK-Kennung (z.B. Fehlerseite) | die genannten Dateien von download.mikrotik.com nach `<pkgPath>/<ver>/` legen; vorab `check=yes` |
| Onboarding `manual=yes` beendet, Gerät hängt weiter im Onboarding-VLAN | gewollt: cfm fasst den Port bei `manual=yes` nicht an | Port am Switch von Hand auf sein Profil zurückstellen (Log-Hinweis) |
| `upload-seed.sh`: „keine SFTP-Anmeldung per SSH-Key“ (früher nur „Connection closed“) | das Skript nutzt Batch-SFTP, das kein Passwort abfragt | Public Key für den User auf dem Gerät hinterlegen, `ssh-agent` laden oder `SFTP_OPTS="-i <key>"` setzen |
| SSH-Anmeldung per Passwort wird abgelehnt, Winbox geht | der User hat einen SSH-Key (z.B. aus `authorized_keys`), RouterOS erlaubt dann per SSH nur noch den Key | mit dem Key anmelden; Key-Datei prüfen (Kapitel 4, `authorized_keys`) |
| `upload-seed.sh`: „Seed unvollständig hochgeladen“ | einzelne Dateien auch nach drei Versuchen nicht übertragen | erneut aufrufen; Verbindung und freien Platz am Manager prüfen |
| Über WireGuard kein SSH/Winbox | Peer fehlt in `wireguard.rsc` oder ist noch nicht ausgerollt; Client-`allowed-ips` ohne das WireGuard-Subnetz | `$cfmCheck`, am Router `/interface/wireguard/peers/print`, Client-Konfiguration prüfen |
| Webfig o.ä. bleibt aus, obwohl in `services` eingetragen | falscher Dienstname (`http` statt `www`) | RouterOS-Namen verwenden (Kapitel 4, `services`) |
| Onboarding bleibt in `wait` | Gerät nicht erreichbar: Kabel, Router an `ether1`, falsches Aufkleber-Passwort | `$cfmOnboardStatus`, Log am Manager, Registrierung prüfen |
| Onboarding: „Seriennummer passt nicht“ | anderes Gerät am Port | Registrierung oder Gerät prüfen |
| Onboarding: „RouterOS … älter als …“ | kein Update möglich (Internet über den Router?) | Router-Rolle/`policy` `onboard`, notfalls von Hand updaten |

Hilfreich auf dem Gerät: `/log print where message~"cfm"` und `:put [/file get cfm/state.json contents]`.
Auf dem Manager: `$cfmStatus`, `$cfmOnboardStatus` und `/log print where message~"cfm"`.
