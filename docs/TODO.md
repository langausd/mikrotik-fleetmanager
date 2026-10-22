# TODO – geplante Verbesserungen

## Übersicht offener Punkte (Stand 2026-10-22)

Erledigtes ist unten durchgestrichen und bleibt als Befund stehen. Offen, grob nach Nutzen:

* **Erledigt am 2026-10-17 (Router-Umzug eines Standorts):** D83 (`mgmtExtra` hinter cfm-Routern bis ins
  MGMT-VLAN), D84 (WireGuard-Fernzugang mit VRRP: gemeinsamer Schlüssel, Endpoint VIP, Route für Geräte
  mit eigenem Ausgang). **Neu, offen:** 56 (vorhandene VLAN-Interfaces übernehmen), 57
  (`wg-client-setup.sh` ohne `wireguard-tools`), 58 (Gast-Schalter ohne Unterbrechung der übrigen SSIDs)
  und vier kleine Befunde unter „Bekannte Fehler“.
* **Erledigt am 2026-10-18 (Ausfalltests und LAN-DHCP am selben Standort):** D85 (ein startender
  VRRP-Backup ist kurz selbst Master – DHCP/WireGuard folgen dem Master erst nach 5 s), D86 (DNS/DHCP/NTP
  der Router auch aus dem LAN, wenn es zugleich ihr WAN ist; danach LAN-DHCP mit `dhcpGw` am Standort in
  Betrieb). Neu unter „Bekannte Fehler“: Umbenennen einer festen Lease löscht sie beim ersten Apply (behoben
  2026-10-19); Fehler im Werks-Skript des hAP be³ Media beim Start.
* **Erledigt am 2026-10-19:** zwei „Bekannte Fehler“ – Umbenennen einer festen Lease (übernommenes Objekt
  wird nicht mehr zugleich als verwaist entfernt) und Steering `kick` über 59 s (`$cfmSame` vergleicht Dauern
  als Zeit); `e2e.sh` 317, `e2e-vrrp.sh` 118, alles grün.
* **Erledigt am 2026-10-20:** „Bekannter Fehler“ SSID-Schalten (D64) – die Schalt-Skripte führen die
  Signatur des Regelblocks und den Merker der eigenen Radios nach, der nächste Apply baut nichts mehr neu
  auf; passen die Regeln nicht zum Schaltzustand, startet der Apply das Schalt-Skript; `e2e.sh` 323, grün.
* **Code-Review am 2026-10-20 (gesamtes Framework, Doku gegen den Code abgeglichen):** behoben – Betas
  holen Agent und `tools/upgrade-mirror.py` über den Kanal `development` (bisher `testing`, dort liegen nur
  RCs: eine Beta per `via=internet` scheiterte, D63), „Bekannter Fehler“ Adresse im Onboarding-VLAN auf einem
  Manager mit Rolle `router` (siehe unten), Abschlussmeldung von `upload-seed.sh` (riet nach jedem
  Framework-Upload zum Manager-Bootstrap), `wg-client-setup.sh connect` verlangte unnötig `wg`; entfernt – toter Code (`cfmLibVer`, ungenutzte Locals und
  Deklarationen, doppelte PEM-Umwandlung in `mgr-enroll`, Altlast `cfm-takeover` von vor D45); Doku –
  Befehlsreferenz, Dateiübersicht, NTP der Router, Update-Kanäle, Beispiele, fehlende Zeile D59. Neu offen:
  59 (NTP der Router), 60 (`rsc-check.py` auf ein Overlay mit Exporten). Labor 7.24.5: `e2e.sh` 323,
  `e2e-vrrp.sh` 118, Onboarding 14/15/18, `e2e-mlag.sh` 72, alles grün.
* **Erledigt am 2026-10-20 abends (Folgearbeiten zum Review, Auswahl des Nutzers):** 56 (vorhandene
  VLAN-Interfaces übernehmen, D87), 57 (`wg-client-setup.sh genkey` mit OpenSSL), 59 (NTP der Router,
  D88), 60 (`rsc-check.py` auf Overlays), „Bekannter Fehler“ `$cfmStatus` (holt veraltete Stände selbst ab,
  D89); Manager-Module aufgeteilt (`mgr-vault.rsc` aus `mgr-core`, `mgr-scan.rsc` aus `mgr-net`, beide
  vorher 47 KB nahe der 60-KB-Grenze, D26); Bootstrap des Managers stellt das RAM-Log schon vor dem ersten
  Release um (D79). Labor 7.24.5: `e2e.sh` 328, `e2e-vrrp.sh` 120, Onboarding 14/15/18, `e2e-mlag.sh` 72,
  alles grün.
* **Umgesetzt am 2026-10-20 (58a, D90), Test auf Hardware beim nächsten Gast-Schalten:** Gast-Schalter
  ohne Unterbrechung der übrigen SSIDs – feste WLAN-Interfaces (`create-enabled`), die Schalt-Skripte
  schalten nur die Interfaces der SSID; `tools/home-assistant/cfm_ssid.py` liest den Zustand an den
  Interfaces (die Kopie in Home Assistant erneuern). Labor 7.24.5: `e2e.sh` 325, grün. Seit 2026-10-21 an
  einem Standort in Betrieb (CAPsMAN mit eigenen Radios, vier APs; Plan danach leer), das erste Schalten steht aus.
* **Erledigt am 2026-10-22 (E17, Update auf `main` + eigene Radios der CRS418):** 24 (eigene Radios
  des CAPsMAN, D53) – Client-Test und FT-Roaming zu den CAPs bestanden, dabei auch das Neustart-Verhalten
  geklärt (RouterOS provisioniert die eigenen Radios dabei selbst, ohne den cfm-Agent).
* **Erledigt am 2026-10-22:** 52 (D91) – ein festes Lade-Lesezeichen „cfm“ startet cfm-Editor und
  cfm-Monitor in der Fassung vom Gerät; neue Fassungen kommen mit dem Framework-Update, das Lesezeichen bleibt.
* **Neu am 2026-10-22:** 61 (Trennschwelle per access-list, auch für Clients mit FT – erst von Hand an
  der Hardware prüfen, ob RouterOS per FT übernommene Verbindungen laufend prüft).
* **Vorbereitet, Test nur mit Hardware vor Ort** (Code fertig, standardmäßig aus, im Labor nur
  Darstellung und Prüfung): 40a (Gast/IoT im lokalen Fallback,
  D54), 39 (Steering je Band + Mindestsignal, D55).
* **Nur mit Hardware:** die Punkte unter „Noch nicht mit echter Hardware getestet“, dazu das
  eingebaute Update mit `via=internet` (38, D63; über den Spiegel auf einem hEX gelaufen).
* **RouterOS 7.25:** Befunde und Folgearbeiten aus dem Labor mit 7.25rc1: 48.
* **RouterOS 7.25:** noch nicht stable (2026-10-20: stable 7.24.5, testing 7.25rc2, development
  7.26beta3). Der Labortest aller Skripte lief am 2026-10-17 mit 7.25rc2 grün (48, wie entschieden: ohne
  stable bis zum Wochenende 17./18.10. mit dem RC); mit 7.25 stable `e2e.sh` wiederholen (48).
* **Einmalig beim nächsten Framework-Update jeder bestehenden Installation:** 47 (erstes Release mit dem
  ausgelagerten WLAN-Teil, D68).
* **Erledigt am 2026-10-16:** 53 (D81): Gerätesuche `$cfmFind` live am Manager, Lesezeichen cfm-WLAN heißt
  „cfm-Monitor“ mit Reiter Suche. **Entschieden, offen:** 54 (LibreNMS: SNMPv3 + Syslog). **Idee:** 55 (Netbox:
  Export oder als Quelle).
* **Erledigt am 2026-10-16:** 51 (D80): andere Funknetze im 2,4-GHz-Band (`wifi.rsc` → `others`) in
  den Kosten von `$cfmWifiScan`, Kanalvorschlag für neue Zigbee-/Thread-Netze, Kanalsatz 1/5/9; offen
  bleibt nur, Energie-Messungen der Koordinatoren einzubeziehen.
* **Zurückgestellt:** 25 (WebFig per HTTPS – bis Let's Encrypt über acme-dns steht), 22 (Disk-Logging
  – ein externer Syslog-Server ist geplant).
* **Erledigt am 2026-10-13 nachmittags:** RAM-Log ohne `system,info` (D79): Nach einem Framework-Update
  bestand der Puffer des Managers zur Hälfte aus Skript-Quelltext (RouterOS loggt Konfig-Änderungen samt
  Wert); Schlüssel `logMemory` in `global.rsc`.
  Dazu `tools/upgrade-mirror.py`: Zwei gleichzeitige Anfragen nach einer noch nicht zwischengespeicherten
  Datei schrieben dieselbe `.part`-Datei, die zweite brach ab (Labor mit leerem Zwischenspeicher, das
  eingebaute Update scheiterte); jetzt lädt eine Sperre jede Datei nur einmal.
* **Erledigt am 2026-10-13:** 50 (D78): MNDP mit Quelle `0.0.0.0` verwirft der input-Block still (an
  der Quelle nicht ohne Verlust abstellbar, siehe D78); ein Gerät mit eigener Adresse in einem
  Client-VLAN verwirft dort still (Site-Regel in der `post.rsc`).
* **Erledigt am 2026-10-12 abends:** Lesezeichen „cfm-WLAN“ (D77): Clients je AP live und Roaming als
  Zeitleiste, für Standorte ohne Home Assistant. Getestet gegen eine Attrappe der REST-API; offen ist
  der Test mit echten Clients (siehe „Noch nicht mit echter Hardware getestet“).
* **Erledigt am 2026-10-12 (sechste Remote-Runde):** 10 (Bonds im Hostfile, D74; MLAG-Paare in
  `mlag.rsc`, D75), 20 bis auf den Proxy (isolierte VLANs über APs und Switches hinweg, Freigaben mit
  Ports je Eintrag, D76). Review von D70–D73 vor dem nächsten Framework-Update einer Site: Die Sperre `cfmApplyBusy` wirkte nur
  in eine Richtung – jetzt wartet auch ein Apply, der während `$cfmCheck`/`$cfmShow` startet
  (`cfmMgrData`, `e2e.sh` 14j; im Labor nicht nachgestellt, das Fenster ist klein). RouterOS 7.25rc1:
  Globals über die API geprüft (48), 7.26beta1: `e2e.sh` grün, Changelog gesichtet (49). Labor: `lab.sh`
  mit freier Topologie (`LABLINKS`) und Kartentyp (`LABNIC`), neuer Test `e2e-mlag.sh`; 7.24.5 und
  7.25rc1: `e2e.sh` 294, `e2e-mlag.sh` alles grün. Bei der Durchsicht der Doku gefunden und behoben:
  `$cfmDiff` kannte `mlag.rsc` nicht als gemeinsame Datendatei.
* **Erledigt am 2026-10-11/13 (fünfte Remote-Runde):** Manifest-Regeln je Version aus dem Archiv (D70,
  schließt die Lücke von TODO 47 bei `$cfmPromote`), RouterOS 7.25: Host-Key-Prüfung des SSH-Clients aus
  (D71) und Versionsmeldung mit Kanal (sonst IP-Adresse beim Manager), Site-Daten führt der Manager
  (D72: `upload-seed.sh` ohne `--site` nur Framework-Code, `tools/pull-site.sh`), Editor als WebFig-
  Lesezeichen über die REST-API (D73, `tools/editor/`), Regel `json-typ` in `tools/rsc-check.py`,
  `$cfmPlan from=<verzeichnis> role=<rollen>` (Probelauf eines Umbaus, z.B. des Router-Umzugs). Labor
  7.24.5: `e2e.sh` 292, Onboarding 14/15/18, `e2e-vrrp.sh` 79, alles grün (auch 7.25rc1: e2e 292, Onboarding 14/15/18, VRRP 79); Übergang vom Stand vor D68
  durchgespielt (TODO 47). Labor auf 7.25rc1 siehe 48. Beim Probelauf des Router-Umzugs gefunden und
  behoben: Probelauf der Rolle `router` brach vor dem ersten VRRP ab; im Labor unter Last gefunden und
  behoben: Wettlauf zwischen Apply des Managers und `$cfmLoadData` (Sperre `cfmApplyBusy`).
* **Erledigt am 2026-10-11:** WLAN-Teil der Gerätebibliothek ausgelagert (`lib/lib-wifi.rsc`, D68;
  `lib.rsc` 46 → 23 KB), Apply lädt nur geänderte Dateien (D69; Labor: Reapply 1 s statt 16 s auf
  einem Switch, 48 s auf dem Manager). Beim Sichten gefunden und behoben: Der Agent merkte sich die
  geflashte RouterBOARD-Firmware so, dass `:deserialize` sie zur IP-Adresse machte – der Schutz gegen
  wiederholtes Flashen und Neustarten griff nie (DECISIONS, Abschnitt „Straffung und Laufzeit“).
* **Erledigt am 2026-10-08:** 2 (Benachrichtigungen per HTTP-POST, D66), 8 Rest (SFTP-/Host-Schlüssel
  rotieren, Manager zweiphasig, D67); beim Sichten gefunden und behoben: Der Backup-Manager hatte
  keine Geräte-User `cfmd-<name>`, Geräte konnten auch nach der Beförderung nicht von ihm ziehen
  (D67: gesperrt bereit, `$cfmPromoteManager` schaltet frei; Labor: `e2e.sh` 14g). Dazu `level`/`device`/`message` für einfache Webhook-Empfänger und der Hinweis auf neue
  RouterOS-Versionen (`ros`). Seit 2026-10-11 meldet auch der Backup-Manager, wenn der Primary per
  SFTP weg ist oder sein Tick steht.
* **Erledigt am 2026-10-04:** 19 (Admin-SSH-Keys je Person, D65), 46 (`$cfmWifiScan` mit den eigenen
  Radios des CAPsMAN), 40 (`slaves-static` nur bei Bedarf), 23 (Warnung bei `wifi-qcom-ac`; die
  Unterstützung selbst bleibt offen), `$cfmStatus` blendet eine veraltete `bad`-Version aus. Im Labor
  gefunden: `/file/get` meldet gelöschte Dateien u.U. dauerhaft als Eintrag ohne Namen – die
  Existenzprüfungen verlangen jetzt einen Namen (DECISIONS, Labor-Eigenheiten).
* **Erledigt am 2026-10-02/03:** 11 (feste Leases und DNS-Namen, D62), 12 (`$cfmShow`/`$cfmDiff`,
  D61), 41 (`$cfmWifiScan` über den CAPsMAN, auf Hardware gelaufen, D60), 38 (Update bei 16 MB
  Flash über das eingebaute Update, Spiegel `tools/upgrade-mirror.py`, D63); dazu schaltbare SSIDs
  für Home Assistant (D64, neu auf Wunsch).
* **Erledigt am 2026-10-01:** 21 (Dateizugriff über den Namen, D59), 36 (Labortest), 44 (Rest,
  D58), „Manager-Ticks starten gleichzeitig“ (D57); Labortest des Watchdog-Rollbacks (`e2e.sh`
  Schritt 14d) und Probe des Router-Umzugs mit drei VRRP-Routern (`e2e-vrrp.sh`). Am 2026-09-30:
  28, 29, 30, 31, 35, 37, 38 (Vorab-Prüfung).
* **Vorbereitet, Test nur mit Hardware:** MLAG auf CRS3xx (Hardware-Offload, Ausfall eines Knotens,
  Umbau im laufenden Betrieb), isolierte VLANs an echten APs (gibt der CAPsMAN `interface-list` an die
  CAPs weiter? Wie sieht der Bridge-Filter WLAN-Frames?) und an Switch-Ports mit `hw=no`.
* **Größere Ausbauten:** 13–15, 18, 20 (Rest: Proxy als Ziel) sowie Netinstall/Branding (Onboarding).

## Onboarding: weitere Wege in den Onboarding-Zustand

Umgesetzt ist der **Push in die Werks-Config** (siehe README, Abschnitt Onboarding). Zwei weitere
Methoden wurden geprüft und für später vorgemerkt.

### 1. Netinstall-Station (Zero-Touch inkl. Neuinstallation)

**Idee:** Neues Gerät am Onboarding-Port, beim Einschalten die Reset-Taste halten (Bestandsgeräte:
`/system routerboard settings set boot-device=try-ethernet-once-then-nand` + Reboot). Ein
Netinstall-Server installiert RouterOS in einer festen Version samt Paketen (z.B. `wifi-qcom`)
und den cfm-Stub als *Konfigurationsskript* (`netinstall-cli -s cfm-stub.rsc`).

**Vorteile**
* kein Aufkleber-Passwort nötig (das Gerät wird neu installiert)
* definierte RouterOS-Version, sauberer Ausgangszustand
* laut MikroTik-Doku führt jeder spätere `reset-configuration` bzw. Reset-Knopf das
  Netinstall-Skript erneut aus → ein zurückgesetztes Gerät landet automatisch wieder im Onboarding
* `--mac <MAC>` begrenzt die Installation auf genau ein Gerät

**Voraussetzungen / offene Fragen**
* Netinstall-Server: Linux (`netinstall-cli`) oder als Container auf einem MikroTik
  ([tikoci/netinstall](https://github.com/tikoci/netinstall), ARM/ARM64 per QEMU-Emulation;
  braucht `container`-Paket, `/system/device-mode` mit Container, USB-/NVMe-Speicher)
* Netinstall arbeitet per BOOTP/TFTP auf Layer 2: Der Container muss im Onboarding-VLAN hängen
* Etherboot braucht einen Handgriff am Gerät (Reset-Taste beim Einschalten)
* Paketquellen (npk je Architektur) müssen auf dem Server liegen und gepflegt werden

### 2. Push + Branding-Paket (Reset-fest ohne Neuinstallation)

**Idee:** Wie der umgesetzte Push, zusätzlich installiert der Manager beim ersten Onboarding ein
Branding-Paket (`.dpk`, erzeugt im mikrotik.com-Konto unter „Branding maker“) mit dem cfm-Stub
als *Default configuration*. Laut Doku stellt danach jeder Reset (auch per Reset-Knopf) diese
Default-Config wieder her → Re-Onboarding ohne Aufkleber-Passwort und ohne Netinstall-Server.

**Offene Fragen**
* Branding-Paket je Architektur? Nutzungsbedingungen des Branding Makers prüfen
* Stub-Änderungen (z.B. neue Manager-Schlüssel) erfordern ein neues `.dpk` für alle Geräte
* Zusammenspiel mit `/system/reset-configuration no-defaults=yes` (Stufe 2 des Pushs)

## Noch nicht mit echter Hardware getestet

Erster Hardware-Pilot (2026-09-17): ein CRS418 als Router, Primary-Manager und CAPsMAN
(`router,manager`) und ein hAP ax² als AP. Zweiter Einsatz (2026-09-20): Primary-Manager als CHR in
einem PVE-Cluster, Karte je VLAN – dabei kamen D40 (`stp="none"`, Profil `vport`), die
Namensprüfung im Bootstrap, der Host-Key-Typ nach Reset und der Schutz des Inventars dazu.
Rollout an einem zweiten Standort (ab 2026-09-26): neun Geräte – CRS328 als Core-Switch ohne Reset
übernommen (routet noch selbst, D43), hAP be³ als CAPsMAN (D45) und AP (Wi-Fi 7, D44/D48), hAP ax³
und cAP ax als APs, hEX und L009 als Switches; Onboarding im CAPs-Modus, CAPsMAN-Umzug, lokaler Fallback (D46)
und `$cfmUpgrade` mit Zusatzpaketen (arm, arm64) liefen dort. Die gefundenen Fehler sind behoben
([DECISIONS.md](DECISIONS.md#auf-hardware-verifizierte-routeros-eigenheiten)). Offen bleiben:

* Onboarding-Push gegen echte Werks-Configs: Router (ether1 = WAN mit Firewall), CRS-Switches,
  Geräte mit `flash/`-Verzeichnis; Aufkleber-Passwort (beim einzigen Versuch, einem hAP ax³ mit
  RouterOS 7.8, passte es nicht – das Gerät hatte ein leeres Passwort, der Fallback griff)
* ~~Onboarding eines hAP per PoE an ether1 im CAPs-Modus~~ – am 2026-09-26 mit zwei APs gelaufen
  (Neustart per `/interface/ethernet/poe/power-cycle` am verwalteten Switch, Lease im
  Onboarding-VLAN, Probe, Bootstrap, Enroll); offen bleibt das LED-Verhalten je Modell
* ~~Manager-Bootstrap mit Reset (`clean="yes"`)~~ – am 2026-09-20 auf einem CHR in PVE gelaufen
  (Stufen 2 und 3 samt Übergabe per SFTP-`.auto.rsc`). Offen bleibt derselbe Weg auf einem Gerät
  mit `flash/`-Verzeichnis
* Bridge nach Neustart/Rollback: Auf CHR nimmt eine Bridge mit VLAN-Filtering nach dem Boot
  sporadisch keine getaggten Frames an (cfm startet die Ports dann neu). Betrifft das auch Geräte
  mit Switch-Chip? Auf Hardware prüfen, ob die Log-Meldung „Bridge-Ports werden neu gestartet“ auftritt.
* PPSK-VLANs, VRRP mit mehreren Routern (im Labor mit drei Routern geprobt, `e2e-vrrp.sh` 79/79,
  2026-10-01: Failover, Rückkehr mit Preemption, Neustart, Ausfall zweier Router, DHCP nur auf dem
  Master, Zonen-Policy, feste NAT-Adresse; dabei die Rolle `router` korrigiert, siehe DECISIONS
  „Rolle `router` mit VRRP“). ~~Umzug der Rolle `capsman`~~ (D45) am 2026-09-27 von
  einer CHR auf einen hAP be³ gelaufen, vier APs folgten samt Zertifikatswechsel. Zwei APs
  (hAP ax²) mit CAPsMAN, SSID-VLAN über den lokalen Datapath (D41), WPA2/WPA3 + FT und Clients
  mit `ft-wpa3-psk` laufen seit 2026-09-24, Roaming zwischen den beiden APs klappt (2026-09-25)
* Hook Manager → Git-Host per `ssh-exec` (die Pull-Seite `cfm-git-sync` ist getestet)
* Rolle `router` auf einem CRS mit L3-Hardware-Offloading (D37): schaltet sie `l3-hw-offloading` ab,
  läuft VRRP danach, und gibt es beim Umschalten einen Aussetzer im gerouteten Verkehr?
* Feste NAT-Adresse (`wan@<Adresse>`, D38) bei VRRP: Wandert die Adresse mit dem Master, und
  übernimmt der neue Master den ausgehenden Verkehr ohne Hand-Eingriff (bestehende Verbindungen
  brechen ab, conntrack wird nicht abgeglichen)?
* Feste Leases und DNS-Namen (D62) auf einem Hardware-Router, bei VRRP auf allen Routern; dabei
  prüfen, ob eine schon dynamisch vergebene Lease derselben MAC das Anlegen der festen stört.
* ~~Eingebautes Update über cfm (D63) auf einem Gerät mit 16 MB Flash~~ – gelaufen 2026-10-03: hEX
  RB750Gr3 von 7.23.1 auf 7.24.5 über `via=mirror` (Apache als Spiegel, `--export`), 2,4 MB frei, vier
  Pakete, gut 4 min samt Neustart. Befund: `mode` blieb danach auf `http` – der Agent prüft den
  Rückbau jetzt in einem späteren Lauf nach. `via=internet` noch nicht über cfm gelaufen.
* Schaltbare SSID (D64) auf Hardware mit Home Assistant: `command_line`-Schalter mit
  `tools/home-assistant/cfm_ssid.py` ([home-assistant.md](home-assistant.md)), Auto-Aus. Im Labor
  per API geprüft (2026-10-03): Starten mit `read,api,test` + `dont-require-permissions`, Zustand aus
  den Regeln, Ablauf aus der Datei; `:global cfmSsid<key>` ist für HA nicht lesbar (D64). Seit D90
  Zustand an den Interfaces, dazu die offenen Fragen aus 58.
* **MLAG (D75)** auf CRS3xx: Offload im Switch-Chip, Ausfall eines Knotens (Strom aus, nicht nur Link),
  Umbau eines Uplinks, über den der Weg zum Manager läuft (Labor: ein 802.3ad-Port ohne Gegenstelle
  leitet weiter), `mlag-lacp-fallback` ab 7.25.
* **Isolierte VLANs (D76)** an echten APs: Gibt der CAPsMAN `interface-list` des Datapath an die CAPs
  weiter (sonst trägt die Rolle `ap` die Interfaces beim Apply ein – neu verbundene erst beim nächsten
  Apply)? Sieht der Bridge-Filter WLAN-Frames als `ip` oder als `vlan` (Labor: virtio `ip`, e1000
  `vlan`; die MAC-Regeln greifen in beiden Fällen)? Trennt Client-Isolation auch zwischen den Radios
  eines AP? An Switches: `hw=no` an isolierten Access-Ports (Durchsatz über die CPU).
* ~~**Lesezeichen cfm-WLAN (D77)** mit echten Clients~~ – *erledigt 2026-10-14* (zwei Standorte mit vier bzw.
  zwei APs): Zuordnung, Signal, Wechsel live und aus dem Log des CAPsMAN
  (`<MAC>@<Interface>(<SSID>) roamed to <MAC>@<Interface>(<SSID>), signal strength …`), Uhrzeit stimmt
  mit `cache: 'no-store'`. Wechsel erscheinen in den Ereignissen doppelt (live und „Log“).
* ~~`$cfmShow objects=yes` auf einem Manager mit vielen Skripten~~ – auf Hardware gelaufen
  (2026-10-03): CHR als Manager mit acht Modulen, 109 Soll-Objekte, 9,5 KB – weit unter der Kürzung.

## Bekannte Fehler

* **Labor: Die MNDP-Prüfung in `e2e.sh` Schritt 14 schlägt vereinzelt fehl** (2026-10-20, ein Lauf von vier,
  drei Labore parallel): In den 40 s mit `pvid=10` an cm1:ether3 kam kein MNDP-Paket von cm2 an (Zähler der
  Regel 0, kein Log), obwohl `discover-interval` 30 s ist; derselbe Code bestand im Parallellauf. Beheben:
  statt fest 40 s auf das erste Paket warten (bis etwa 70 s).
* ~~**Umbenennen einer festen Lease löscht sie beim ersten Apply**~~ (Befund 2026-10-18, 7.24.5): In
  `leases.rsc` dieselbe Lease (gleiche MAC und Adresse) unter neuem Namen → der Plan zeigt
  `übernommen: … lease:<VID>:<neu>` (Kommentar wird umgeschrieben) **und** `entfernt: … lease:<VID>:<alt>` –
  beides trifft dasselbe Objekt, danach fehlt die Lease auf allen Routern. Erst ein zweiter Apply
  (`$cfmPush host=<r> force=yes`) legt sie neu an. Der DNS-Name ist richtig. Bis zur Korrektur: nach einem
  Umbenennen die Leases prüfen und ggf. erneut pushen. Beheben: Objekte, die in diesem Lauf übernommen wurden,
  nicht mehr als verwaist entfernen (gilt vermutlich für jeden `$cfmEnsure`-Typ mit natürlichem Schlüssel);
  Labor: `e2e.sh` mit Umbenennen einer Lease. – *behoben 2026-10-19:* `$cfmEnsure` nimmt beim Übernehmen
  den bisherigen `cfm:`-Schlüssel des Objekts aus dem Index, `$cfmPrune` sieht es nicht mehr als verwaist
  (gilt für alle Typen). Labor: `e2e.sh` Schritt 9 benennt eine Lease um.
* ~~**Steering `kick` über 59 s ist nie idempotent**~~ (Befund 2026-10-17): `wifi.rsc` → `kick`="90s"
  setzt `transition-time=90s`, RouterOS liest `1m30s` zurück – jeder Apply auf dem CAPsMAN meldet
  `geändert: /interface/wifi/steering wst:<n>: transition-time` (set=2). Harmlos; beheben durch
  Normalisieren (Sekunden in RouterOS-Schreibweise) vor dem Vergleich oder in `$cfmEnsure` allgemein für Zeiten.
  – *behoben 2026-10-19:* `$cfmSame` vergleicht zwei Dauern als Text (`1m30s`, `90s`) über `:totime`.
* ~~**Nach dem Schalten einer SSID (D64) baut der nächste Apply das Provisioning neu**~~ (Befund 2026-10-19,
  7.24.5): Die Skripte `cfm-ssid-<key>-on/-off` ändern `slave-configurations` direkt, die Signatur des
  Regelblocks `wprov` (`sig=` im Kommentar) und `<cfm>/wifi-local.txt` stammen aber vom letzten Apply. Der
  nächste Apply meldet `Regelblock /interface/wifi/provisioning wprov neu aufgebaut` mit gleichem Inhalt und
  provisioniert die eigenen Radios des CAPsMAN neu (`capsmanRadios`, ~3 s ohne WLAN). Beheben: die Skripte
  auch Signatur und Merker nachführen lassen, oder Signatur und Merker ohne die schaltbaren SSIDs bilden
  und deren Zustand getrennt vergleichen. – *behoben 2026-10-20 (D64):* Die Skripte führen beides nach
  (Tabelle je Kombination der Schaltzustände aus dem Apply); passen Regeln und Zustand nicht zusammen,
  startet der Apply das Schalt-Skript. Labor: `e2e.sh` Schritt 14. *Seit D90 gegenstandslos:* Schalten
  ändert die Regeln nicht mehr, Tabelle und Nachführung sind entfallen.
* ~~**Manager mit Rolle `router` im Onboarding-VLAN:**~~ Dieselbe Adresse (`.250+routerId`) legen die
  Onboarding-Funktion (`obip:<VID>`) und die Rolle `router` (`ip:<VID>`) an; die Rollen übernehmen sie
  abwechselnd (`übernommen: /ip/address ip:88` und Kommentarwechsel in jedem Plan; seit der Korrektur der
  Lease-Umbenennung 2026-10-19 erscheinen beide als „übernommen“). Harmlos, aber jeder Apply zählt sie mit. Eine der beiden sollte die Adresse der anderen als ihre ansehen.
  – *behoben 2026-10-20 (Code-Review):* Legt die Rolle `router` im Onboarding-VLAN dieselbe Adresse an
  (VRRP `.250+routerId`, sonst das Gateway), lässt die Rolle `manager` ihre `obip:<VID>` weg; die Adresse
  gehört dann `ip:<VID>`. Der erste Apply danach übernimmt sie einmal (`übernommen: … ip:<VID>`), danach
  bleibt der Plan leer. Labor: mit `lib/lib.rsc` auf einer CHR nachgestellt (eine Adresse, zuletzt als
  `obip:88` getaggt): vorher je Lauf `set=2`, nachher einmal `set=1`, danach 0; `e2e-vrrp.sh` als
  Regression (dort liegen Manager- und Router-Adresse verschieden). Am Standort mit dem nächsten Release
  prüfen: Probelauf des Managers ohne `ip:88`.
* **hAP be³ Media meldet beim Start einen Fehler im Werks-Skript** (Befund 2026-10-18, 7.24.5):
  `error while running customized default configuration script: no such item (/interface/wifi/get; line 1)`,
  obwohl `/system/default-configuration` kein eigenes Skript hat. Vermutlich sucht das Werks-Skript ein
  WLAN-Interface unter dem Werksnamen (cfm benennt sie um). Ohne erkennbare Folge; Ursache offen.
* **`$cfmAudit op=purge` meldet FEHLER für dynamische Folgeobjekte** (Befund 2026-10-17: ein
  VLAN-Interface samt Adresse entfernt, zwei FEHLER-Zeilen für Objekte, die RouterOS dazu dynamisch
  angelegt hatte): Sie verschwinden mit dem entfernten Objekt, das Löschen danach scheitert.
  Harmlos, aber verwirrend; dynamische Einträge beim Purge überspringen.
* ~~**`$cfmStatus` zeigt bis zum nächsten Manager-Tick den alten Stand:**~~ – *behoben 2026-10-20 (D89):*
  `$cfmStatus` holt den Status von Geräten mit Ist ≠ Soll oder ausstehendem Apply vorher selbst ab. Labor:
  `e2e.sh` Schritt 11. – Nach einem Release stand ein
  Gerät noch mit der alten Version da, obwohl es längst angewendet hatte; erst `$cfmCollect` holte den
  Status. Vorschlag: `$cfmStatus` holt veraltete Status selbst ab (oder weist auf `$cfmCollect` hin).
* ~~**Labor 2026-10-11: cm1 nimmt keine Anmeldung mehr an.**~~ – *geklärt und behoben 2026-10-12:* Wettlauf
  zwischen dem Apply des Managers und `$cfmLoadData` (DECISIONS, Umsetzungsentscheidungen, Sperre
  `cfmApplyBusy`); nachgestellt in Labor B (Push an cm1 plus paralleles `$cfmLoadData` → `adminUser`
  aus `global.rsc` statt aus dem Hostfile), mit der Sperre nicht mehr, `e2e.sh` Schritt 14i. Der
  Fehler bestand schon vorher; unter Last (zwei Labore parallel) wurde das Fenster groß genug.
  Ursprünglicher Befund: Im ersten `e2e.sh`-Lauf mit D70/D71
  (7.24.5, parallel zu einem zweiten Labor) scheiterte ab Schritt 14 jede Anmeldung an cm1: admin
  (leeres Passwort) und netadmin per SSH und an der seriellen Konsole, `cfmd-sw1` per SFTP-Key von sw1,
  `/system/ssh-exec` von cm2 als `cfm`.
  Der Manager-Tick von cm1 lief weiter, er meldete sich alle 10 min per Key an cm2 und sw1 an. Mit demselben
  Code und Diagnose alle 5 s (freier Speicher 40 MB, Platz 68 MB) lief Schritt 14 danach fehlerfrei. Die
  VM-Disks gingen mit dem nächsten `fresh` verloren. Tritt es wieder auf: VM nicht neu aufsetzen, Disk
  sichern (`qemu-img convert`), dann zuerst prüfen, ob cm1 neu gestartet ist (Uptime im Status) und ob
  ein Rollback lief (Log von cm2/sw1 und `cfm/state/cm1/status.dat` im Spiegel von cm2).
* ~~**Manager-Ticks starten gleichzeitig:**~~ – *erledigt (D57):* Der allgemeine Tick wartet bis zu
  60 s auf einen laufenden Onboarding-Tick und setzt während seiner Arbeit `cfmTickBusy`, der
  Onboarding-Tick wartet bis zu 30 s darauf und lässt dann seine Minute aus. – `cfm-mgr-tick` (alle `mgrTick`) und `cfm-mgr-onb-tick` (jede
  Minute) haben beide `start-time=startup` und laufen deshalb zur selben Sekunde los, im Labor mit
  `mgrTick=1m` jede Minute. Bisher nur als Zeitversatz beobachtet (Onboarding-Test: Status von ob1
  und Rückstellung des Onboarding-Ports einige Sekunden später, einmal ein leerer Status beim Lesen).
  Vorschlag damals: Start des Onboarding-Ticks versetzen oder beide Ticks gegenseitig ausschließen.
  Vor D57 (D42) übersprang sich nur jeder Tick selbst, solange sein eigener Vorlauf noch lief.
* ~~**WireGuard-Fernzugang: Rückweg zu cm1 selbst startet nicht zuverlässig ohne Anstoß.**~~ –
  *erledigt, am 2026-09-24 auf Hardware bestätigt:* Nach frischem `nmcli connection up` läuft der
  Verkehr zum MGMT-Netz sofort durch den Tunnel (Quelle ist die Tunnel-Adresse), SSH zu cm1 klappt
  auf Anhieb. Ursache war das früher überlappende
  Peer-Subnetz im MGMT-Netz (RouterOS legt dafür keine Route an, dazu Proxy-ARP); seit dem eigenen
  WireGuard-Subnetz (`wireguard.rsc` → `net`) ist das behoben.

## Verbesserungsplan (Stand 2026-09-12)

Reihenfolge: 0 → 1 → 2, 3, 4 → 6, 7 → Rest nach Bedarf.

**0. Pilotbetrieb mit echter Hardware** – ein Gerät je Typ (Router, Switch, AP, Manager); deckt
die oben genannten ungetesteten Punkte ab. Größter Risikominderer vor jedem neuen Feature.
*Begonnen 2026-09-17* mit CRS418 (Router + Manager) und hAP ax² (AP), seit 2026-09-26 ein
zweiter Standort mit Switches, eigenem CAPsMAN und Manager in einer VM (siehe oben). Auf Hardware
fehlen noch der Backup-Manager und VRRP mit mehreren Routern.

### Kurzfristig (großer Nutzen, wenig Aufwand)

1. ~~**`manager.rsc` aufteilen**~~ – *erledigt (D26):* `lib/mgr-core.rsc`, `mgr-enroll.rsc`,
   `mgr-onboard.rsc`, `mgr-auto.rsc` (je höchstens 21 KB statt 53 KB in einer Datei; RouterOS liest
   per `/file get` nur etwa 60 KB, `$cfmRelease` lehnt größere Dateien ab).
2. ~~**Benachrichtigungen**~~ – *erledigt (D66):* `global.rsc` `notify` (HTTP-POST mit JSON, z.B. an
   einen Webhook von Home Assistant), je Zustandswechsel: Apply-Fehler/Rollback, stumm, WLAN lokal,
   Update fehlgeschlagen, Onboarding gescheitert, CHR-Lizenz; Labor: `e2e.sh` Schritt 14f. Der
   Backup-Manager meldet einen stummen Primary (SFTP weg oder Tick steht). – (E-Mail oder Push-Dienst wie
   ntfy/Telegram) bei Fehler/Rollback, stummen Geräten, gescheitertem Onboarding, CAPs im lokalen
   Fallback (D46).
3. ~~**Archiv aufräumen**~~ – *erledigt (D27):* nach jedem Release und auf dem Backup-Spiegel;
   behalten werden `archiveKeep` (10) plus alle von Ringen/Geräten genutzten Versionen.
4. ~~**Prüfskript für RouterOS-Fallen**~~ – *erledigt (D34):* `tools/rsc-check.py` (Zeile beginnt
   mit `[`, `\"` in Argumenten, `:return` in `:onerror`, Slash-Syntax für geräteabhängige Menüs,
   Array-Klammern, `verbose=yes`, Klammern, Dateigröße, Dotfiles), Pre-Commit-Hook
   `tools/git-hooks/pre-commit`, GitHub Action `rsc-check`. Offen: `:parse` und `e2e.sh` in der CI
   (bisher bewusst lokal im Labor).
5. ~~**Inhaltliche Prüfung beim Release**~~ – *erledigt (D27):* `$cfmCheck`, Fehler stoppen das
   Release (`force=yes` übergeht sie), fehlende Hostfiles sind Warnungen.

### Mittelfristig

6. ~~**Plan-Modus**~~ – *erledigt (D29):* `$cfmPlan host=<n>`, Probelauf gegen `work/` (ohne
   `*.post.rsc`). Offen: Grenze der Berichtsgröße bei sehr großen Plänen prüfen.
7. ~~**RouterOS-Versionspflege**~~ – *erledigt (D30):* `$cfmUpgrade` (sofort oder einmaliges
   Wartungsfenster, auch Downgrade), Pakete vom Manager, automatisches Aufräumen. RouterBOOT-Firmware
   nach dem Update *erledigt*: `agent.rsc` erkennt `current-firmware != upgrade-firmware` (auf
   Hardware bestätigt: hAP AX² blieb nach einem RouterOS-Update sonst dauerhaft auf der alten
   Firmware stehen) und stößt selbst einen weiteren Neustart an. Zusatzpakete (`wifi-qcom-be`,
   `container`, `iot`, `ups` …) auf arm und arm64 auf Hardware gelaufen (2026-09-26). Offen: Pakete
   auf den Backup-Manager spiegeln. ~~Vorabversionen im Labortest~~ (TODO 36, erledigt).
8. ~~**Identitätsprüfung vor dem Secret-Push**~~ – *erledigt (D28):* Challenge-Response mit dem
   Geräteschlüssel; Erneuerung per `$cfmRekey`. ~~Offen: SFTP-Schlüssel (`cfmd-<name>`) rotieren
   (bisher nur per `$cfmEnroll … rekey=yes`).~~ – *erledigt (D67):* `$cfmRekey … sftp=yes`, bei
   Managern zweiphasig (neuer Trust-Key erst auf allen Geräten, sonst Abbruch); der Backup-Manager legt
   die Geräte-User aus dem Spiegel selbst an. Labor: `e2e.sh` Schritt 14g.
9. ~~**Minimale Firewall auf allen Geräten**~~ – *erledigt (D31):* Default-Drop auf Nicht-Routern,
   IPv6-input auf allen Geräten. Offen: IPv6-Forward auf Routern (mit Punkt 13).
10. ~~**Link-Bündel (Bonding/LACP) als Port-Profil** für Uplinks.~~ – *erledigt 2026-10-12:* Hostfile
    `bonds` (D74), MLAG-Paare zentral in `mlag.rsc` (D75). Labor: `e2e-mlag.sh` (fünf VMs, e1000). Offen:
    Test auf Hardware (CRS3xx mit Marvell-Chip: MLAG im Switch-Chip), Verhalten beim Umbau eines
    Uplinks, über den der Weg zum Manager läuft.
11. ~~**Feste DHCP-Leases und DNS-Namen aus zentralen Daten**~~ – *erledigt (D62):* `leases.rsc` je
    VLAN, die Rolle `router` legt Leases und DNS-Namen `<name>.<domain>` (Leases und aufgenommene
    Geräte) an; Standard-Domain `internal`. Labor: `e2e.sh` Schritt 9.
12. ~~**Effektive Config und Diff anzeigen**~~ – *erledigt (D61):* `$cfmShow host=<n> [ver=] [objects=yes]`
    (Daten bzw. Soll-Objekte per Probelauf), `$cfmDiff [ver=A] [to=B]` (Dateien, betroffene Geräte,
    Zeilen der Datendateien). Labor: `e2e.sh` Schritt 9.

### Größere Ausbauten

13. **IPv6** (Präfixe je VLAN, Router Advertisements, IPv6-Firewall).
14. **Zentrale Admin-Anmeldung per RADIUS** (User Manager auf dem Manager).
15. **WireGuard-Rolle** (Fernzugang, Standortkopplung; Schlüssel aus dem Vault).
16. ~~**WLAN-Ausbau**~~ – *erledigt (D32):* PPSK per Multi-Passphrase-Gruppen, nächtliche
    Kanal-Neuwahl, Kanalbericht `$cfmChannels`. Offen: **WPA2/WPA3-Enterprise** (externer RADIUS
    oder User Manager); Kanalbericht und PPSK-VLANs mit echten APs testen (CHR hat keine Radios).
17. ~~**Verkabelung prüfen per LLDP**~~ – *erledigt (D33):* `$cfmLinks` mit Baseline und
    Hostfile-Angaben, `netzplan.md` (Mermaid + Tabelle), `export=yes` für Graphviz/CSV.
18. **Optional Git als Arbeitsort** mit Review vor dem Release – bewusste Alternative zu D4,
    z.B. bei mehreren Admins.
19. ~~**Individuelle `authorized_keys` je Admin-Benutzer**~~ – *erledigt (D65):* `work/authorized_keys.<user>`
    je Person, Abgleich über den Fingerprint, Users ohne Datei unangetastet, die gemeinsame Datei gilt
    nicht mehr. Labor: `e2e.sh` Schritt 14e. Hardware 2026-10-04: neun Geräte von der gemeinsamen Datei
    umgestellt, die drei vorhandenen Keys blieben ohne Änderung stehen (gleiche Fingerprints). – Aktuell (D35) gilt eine einzige
    `authorized_keys`-Datei für ALLE User aus `global.rsc` `users`; bei mehreren Admins sollte
    jeder Benutzer nur seine eigenen Keys bekommen (z.B. `authorized_keys.<user>` oder Zuordnung
    innerhalb der Datei), inkl. Revocation pro Person statt nur global.
20. **IoT-Isolation ausbauen** – *bis auf den Proxy erledigt 2026-10-12 (D76):* `isolate="yes"` am VLAN
    mit Ausnahmen `isolateAllow`, Filter am Eingang der Client-Ports (Access-Ports mit `hw=no`,
    WLAN über die Liste `cfm-iso`), Freigaben mit Ports je Eintrag (`"ziel:tcp/443"`). Labor:
    `e2e-mlag.sh` Schritt 10, `e2e.sh` Schritt 9. Offen: Test an echten APs und Switches (siehe
    „Noch nicht mit echter Hardware getestet“), Proxy als Ziel. – (nach D38/D39): gerätespezifische Freigaben über kleinere Zonen
    erproben (eigenes VLAN/PPSK-Gruppe je Gerätegruppe); Freigaben nur für bestimmte Ports;
    Proxy als Ziel (transparent, Filter nach Domain) für Geräte, deren Cloud-Adressen häufig
    wechseln. WLAN-Client-Isolation trennt laut MikroTik nur Clients am selben AP – für
    isolierte Zonen über mehrere APs zusätzlich einen Bridge-Filter auf den APs (nur zum Gateway).
    – **Freigaben je Client** (Wunsch 2026-10-13): eine Freigabeliste nur für einzelne Clients einer
    Zone gelten lassen (Quelle = Namen aus `leases.rsc` oder IPs), statt für die ganze Zone und ohne
    eigenes VLAN. Anlass: Ein einzelnes Gerät braucht seine Cloud (z.B. ein PV-Wechselrichter),
    `iot="*allow:<Liste>"` erlaubt diese Ziele aber jedem Gerät der Zone. Bis dahin gilt sie zonenweit.
21. ~~**Weniger `/file/find` im Manager-Tick**~~ – *erledigt (D59):* Zugriffe auf bekannte Dateinamen per
    `/file/get <Name>` statt Suche (CHR, 600 Dateien: 0,05 statt 8 ms), `cfmMB` je Sitzung gemerkt,
    `archiveKeep` standardmäßig 5, `$cfmRelease` lädt den Prüfer aus `work/`. Nachtrag 2026-10-11:
    auch die Geräte prüfen bekannte Namen per `get`; schneller wird das Apply erst durch D69 (DECISIONS,
    „Straffung und Laufzeit“). Offen: auf Geräten mit
    USB-Stick prüfen, ob er die Dateiliste bremst. – Hardware-Befund (CRS418, RouterOS 7.22.2): eine
    `/file/find`-Suche kostet ca. 0,23 ms je Datei in `/file` (624 Dateien: 120 ms, 351: 80 ms).
    Fast jede Funktion (`cfmMB`, `cfmWrite`, `cfmRead`, `cfmJson`) sucht sich ihre Datei so;
    ein Tick lief mit 624 Dateien 87 s, nach dem Aufräumen (`archiveKeep` 3, Supout weg) 33 s.
    Überlappende minütliche Läufe führten zu `action timed out` und aufgestauten Scheduler-Jobs
    (Abhilfe: Job-Sperre je Scheduler, Onboarding-Tick lädt im Leerlauf nichts,
    Schrittmarken `cfm: tick …` im Log). Offen: `cfmMB` einmal zwischenspeichern, Dateisuchen
    bündeln, `archiveKeep` als Default niedriger; auf Geräten mit USB-Stick prüfen, ob er die
    Dateiliste bremst. Auch `$cfmRelease` gegen den eigenen Prüfer: nach einem Framework-Update
    meldet der alte Prüfer auf dem Manager neue Zonenkennzeichen (`*wan`) als Fehler, das erste
    Release braucht dann `force=yes` (Henne-Ei; künftig Prüfer aus dem neuen Archiv laden).
22. **Fehlgeschlagener Apply löst über den Watchdog einen Reboot aus (Design-Falle, kein Bug)** –
    *Disk-Logging zurückgestellt (2026-10-01): Ein externer Syslog-Server ist geplant; den Grund eines
    Rollbacks meldet der Agent schon vor dem Neustart (`res` in `$cfmStatus`).* –
    Hardware-Befund, 2026-09-22: ein ungültiges RouterOS-Property (`local-forwarding` im
    WLAN-Datapath – ein Feld des alten CAPsMAN `/caps-man`, das es im wifi-Paket nicht gibt; RouterOS
    lehnt es als "bad parameter" ab) ließ `$cfmImportAll` auf
    cm1 mit einem Script-Fehler abbrechen; die Standard-Fehlerbehandlung markiert die Version als
    `bad` und rollt per `/system/backup/load` zurück - das lädt IMMER neu (RouterOS-Eigenheit,
    kein Rollback ohne Reboot möglich). Bei einem Manager, der sein eigener Primary ist, heißt
    das: ein einziges kaputtes Property in `roles/manager.rsc` bringt cm1 bei JEDEM Release in
    eine Reboot-Schleife, bis der Fehler im Quelltext behoben ist - `$cfmRelease`/`force=yes`
    verhindert das nicht, weil der interne Prüfer (`mgr-check`) RouterOS-Property-Namen nicht
    kennt. Zusätzlich: RouterOS löscht sein Log beim Reboot (RAM-Puffer) - die entscheidende
    Fehlerzeile war beim ersten und zweiten Reboot bereits weg, erst nach Einrichten von
    Disk-Logging (`/system/logging/action/add target=disk ...`) wurde die eigentliche Meldung
    ("bad parameter local-forwarding") sichtbar. Für produktive Manager erwägen: testweiser Apply
    (`$cfmPlan`) VOR dem echten Release stärker bewerben, oder Disk-Logging für warning/critical
    standardmäßig für Primary-Manager vorsehen (Flash-Verschleiß gegen Abwägen).
23. **APs mit `wifi-qcom-ac`** (hAP ac², cAP ac u.ä.): Laut MikroTik-Doku übernehmen sie `vlan-id`
    nicht vom CAPsMAN – der Datapath `cfm-cap` (D41) reicht dort nicht. Die Rolle `ap` müsste je
    Radio bzw. virtuellem AP einen statischen Bridge-Port mit der PVID der SSID anlegen, und der
    CAPsMAN dürfte solchen CAPs keinen Datapath mit `vlan-id` schicken. Erst mit einem solchen
    Gerät umsetzen und testen. *Seit 2026-10-04 warnen die Rolle `ap` (Log, Probelauf) und `$cfmCheck`
    (aus den gemeldeten Paketen), wenn ein AP das Paket hat.*
24. ~~**Eigene Radios des Managers**~~ – *erledigt (D53):* Hostfile `capsmanRadios="yes"` auf dem
    CAPsMAN provisioniert dessen eigene Radios über den eigenen CAPsMAN
    (`/interface/wifi/radio/provision [find where local]`, dieselben Regeln wie für die CAPs). Auf
    Hardware seit 2026-10-03 an (hAP be³, G5A). Client-Test und FT zu den CAPs bestanden (E17,
    2026-10-22, CRS418: Bridge-Port/VLAN korrekt, Roaming cm1-5g ↔ ap1-5g beidseitig); dabei auch das
    Verhalten bei einem Neustart des Geräts geklärt: RouterOS provisioniert die eigenen Radios dabei
    selbst neu, ohne den cfm-Agent (Einzelheiten D53).
25. **WebFig per HTTPS** – *zurückgestellt (2026-10-01), bis Let's Encrypt über acme-dns mit einer
    öffentlichen Domain steht (dann Zertifikat per DNS-Challenge statt selbstsigniert).* – `services` kennt `www-ssl`, die Rolle `base` setzt aber nur Port und
    Adressen; ohne Zertifikat lauscht RouterOS dort nicht. Bis dahin geht das Web-Interface nur
    per `www` (HTTP, Passwort unverschlüsselt, auf die Management-Netze begrenzt). Umsetzung:
    je Gerät ein selbstsigniertes Zertifikat (oder von einer CA auf dem Manager signiert) anlegen,
    an `www-ssl` hängen und bei Namens-/Adressänderung erneuern; danach `www` abschalten.
26. ~~**Fremder CAPsMAN im MGMT-VLAN**~~ – Hardware-Befund: Läuft im MGMT-VLAN noch ein anderer
    wifi-CAPsMAN (z.B. auf dem bisherigen Core-Switch), meldet sich ein frisch aufgenommener CAP per
    Discovery dort an, obwohl `caps-man-addresses` auf die cfm-Manager zeigt, und übernimmt dessen
    CA und Zertifikat. Danach scheitert die Verbindung zum cfm-Manager an
    `ssl: no trusted CA certificate found` bzw. `missing key`. Abhilfe von Hand: `caps-man-names`
    auf die Identities der Manager setzen, die fremden Zertifikate löschen und `certificate` einmal
    auf `none` und zurück auf `request` setzen. *Behoben mit D45:* Die Rolle `ap` setzt
    `caps-man-names`/`-addresses` aus dem Manifest-Feld `cm` (Rolle `capsman`) und erneuert die
    CAPsMAN-Zertifikate, wenn der CAP an einem anderen CAPsMAN hängt oder `cm` sich ändert; `base`
    schaltet auf allen anderen verwalteten Geräten den CAPsMAN-Dienst ab. Ein CAPsMAN auf einem
    Gerät außerhalb von cfm bleibt möglich – `caps-man-names` hält die CAPs davon fern.
27. ~~**Unnötige Änderungen bei jedem Apply**~~ – *behoben (drei Ursachen, siehe unten)* – `geändert: /interface/bridge br: priority` auf einer
    Bridge mit `protocol-mode=none` und `gesetzt: /user: disabled` auf dem Manager erscheinen bei
    jedem Apply, obwohl sich nichts ändert. Harmlos, verrauscht aber Log und Probelauf.
    Behoben: `priority` bei `stp="none"` (ohne RSTP liefert RouterOS keinen Wert, `base` setzt sie dann
    nicht mehr). Behoben: `al:mgmt:<ip>/32` (RouterOS speichert Adresslisten-Einträge ohne `/32`) – `cfmSame`
    vergleicht Hostadressen jetzt ohne Präfix.
    Behoben (Befund 2026-09-28): `stpPrio` in Großbuchstaben (`"0xE000"`) – RouterOS liefert `0xe000`
    (als Text), der Textvergleich schlug fehl, `priority` wurde bei jedem Apply neu gesetzt (set=1).
    `cfmSame` vergleicht Zahlen in Textform (dezimal oder `0x…`) jetzt numerisch.
28. ~~**`$cfmPush` an nicht aufgenommene Geräte**~~ – *erledigt (D49):* Nur Geräte mit Geräteschlüssel
    im Vault gelten als aufgenommen; Push, Secret-Push, Trust, Rekey, Collect, Auto-Promote und
    `$cfmUpgrade` lassen die übrigen aus, `$cfmPush` nennt sie in einer Sammelzeile, `$cfmStatus` zeigt
    „nicht aufgenommen“. – `$cfmRelease all=yes` stößt jeden
    Inventar-Eintrag an, auch Platzhalter ohne Seriennummer (Befund 2026-09-29: drei noch nicht
    aufgenommene Geräte erzeugen bei jedem Release eine Fehlerzeile, beim Secret-Push eine Warnung). Das erzeugt Fehlerzeilen und trifft im
    Zweifel ein fremdes Gerät, das gerade die geplante Adresse hat. Einträge ohne echte
    Seriennummer überspringen.
29. ~~**Zugang und Upload**~~ – *erledigt:* `upload-seed.sh` prüft die Anmeldung vorab und erklärt,
    dass ein SSH-Key nötig ist; Admin-Guide korrigiert (Kapitel 4 `authorized_keys`, Sicherheit,
    Fehlersuche). – `tools/upload-seed.sh` nutzt `sftp -b`: Ohne SSH-Key bricht es nur mit
    `Connection closed` ab. Klare Meldung ausgeben (Key nötig, Batch-SFTP fragt kein Passwort ab).
    Admin-Guide (`authorized_keys`): Hat ein User einen Key, lehnt RouterOS dessen SSH-Login per
    Passwort ab (`/ip/ssh always-allow-password-login=no`); nur Winbox geht weiter mit Passwort.
30. ~~**Dienst `reverse-proxy`**~~ – *erledigt:* steht in der Dienstliste, aus, sofern nicht in
    `services`; `$cfmCheck` meldet unbekannte Dienstnamen und doppelte Ports. – Befund: Der Dienst
    (neu in RouterOS 7.2x, Port 443) fehlte in der Dienstliste der Rolle `base` und blieb aktiv, ohne
    Adressbeschränkung.
31. ~~**Onboarding an einem nicht verwalteten Switch**~~ – *erledigt (D50):* `$cfmOnboard manual=yes
    [name=] [sw= port=]`, Labortest `e2e-onboard.sh manual`. – `$cfmOnboard sw= port=` setzt voraus, dass
    der Switch aufgenommen ist, sonst lässt sich der Port nicht schalten. Beim ersten Gerät hinter
    einem noch nicht übernommenen Core-Switch (Hardware-Befund) musste der Port von Hand in das
    Onboarding-VLAN (PVID) und die Sitzung von Hand in `meta/onboard.dat` angelegt werden; der
    Manager versuchte dabei in jedem Tick, sich am Switch anzumelden. Vorschlag: `$cfmOnboard
    port=manual` (bzw. `sw=-`): kein Umschalten, kein Fail-safe, am Ende kein Push – der Admin
    schaltet den Port selbst hin und zurück.
32. ~~**6 GHz und Wi-Fi 7 (MLO)**~~ – *umgesetzt (D48):* MLO standardmäßig aus, 6 GHz mit Security je
    Band; offen nur noch lokales MLO bzw. MLO mit mehreren SSIDs, falls es je gebraucht wird.
    Hardware-Befund mit einem Tri-Band-AP (`wifi-qcom-be`): Das
    dritte Radio (6 GHz, `6ghz-ax`/`6ghz-be`) bleibt deaktiviert, weil `wifi.rsc` nur die Bänder
    2 und 5 kennt; der CAPsMAN legt außerdem dynamisch ein MLO-Interface (`mld*`) an. Offen:
    Kanal-Pool für Band `6` in `channels`, Provisioning-Regel dafür, 6 GHz verlangt WPA3-SAE mit
    PMF (kein WPA2-Übergang), Umgang mit MLO. `vlan-id` aus dem Datapath funktioniert mit
    `wifi-qcom-be` (`max-vlans=4095`).
    MLO-Befund: Der CAPsMAN fasst die Radios eines Wi-Fi-7-CAP bei gleicher SSID zu einem
    MLD-Interface zusammen; dafür kommen Bridge und `vlan-id` ebenfalls nicht vom CAPsMAN (wie D41).
    Behoben in der Rolle `ap` per `/interface/wifi/cap mld-datapath` mit eigenem Datapath im VLAN der
    Master-SSID. Offen: Da es nur ein `mld-datapath` je CAP gibt, bräuchten weitere SSIDs mit MLO
    eigene Lösungen (MLO für Slave-SSIDs abschalten oder `mld-static` + eigene Datapaths).
33. ~~**Bestandsgeräte, die noch selbst routen**~~ (Hardware-Befund, Core-Switch mit L3 im Switch-Chip):
    Neu in der Rolle `base`: Hostfile-Schlüssel
    `cpuVlans` (Bridge bleibt in VLANs mit eigenen VLAN-Interfaces getaggt), `gw`/`dns`/`ntp` (statt
    MGMT-Gateway bzw. globaler Werte – sonst zeigt ein Gerät, das selbst das MGMT-Gateway ist, auf
    sich selbst), `bridgeFrames` (Bridge nimmt weiter ungetaggte Frames an, z.B. eine Adresse in VLAN 1);
    der Agent-Scheduler wird immer eingeschaltet; `$cfmEnroll … noapply=yes` nimmt ein Gerät ohne
    ersten Apply auf, damit vorher `$cfmPlan` läuft. *Erledigt (D43):* Admin-Guide 7.3 (Ablauf ohne
    Reset, cfm-Tags vorab, Freigaben in `local-input`), Labortest `e2e.sh` Schritt 14b (cm2: Overrides
    und zurück, sw1: Enroll ohne Apply). Hardware: Core-Switch und hEX so übernommen.
34. ~~**Bootstrap-Default-Route ohne cfm-Tag**~~ – Mit `gw=` im Hostfile legte die Rolle `base` eine
    zweite Default-Route an, die Bootstrap-Route blieb stehen → ECMP über zwei Gateways. Behoben in
    `lib/bootstrap-body.rsc` (Route mit Tag `cfm:rt:default`). *Erledigt:* Labortest `e2e.sh` Schritt
    14b (cm2 per Bootstrap aufgenommen, mit `gw=` genau eine Default-Route).
35. ~~**Agent aus einer Admin-Sitzung gestartet**~~ – `/system script run cfm-agent` aus einer SSH-Sitzung
    eines Admin-Users scheitert mit „kein Manager erreichbar“: `/tool/fetch` (SFTP) nimmt den privaten
    Schlüssel des aufrufenden Users, den nur `cfm` hat. *Doku erledigt* (Admin-Guide 7.3 und
    Fehlersuche: immer `$cfmPush host=…`); *erledigt:* Der Agent erkennt den Besitzer des Jobs und
    meldet „der Agent läuft als <user> … `$cfmPush host=<n>` verwenden“ (Terminal und Log).
36. ~~**Vorabversionen in `$cfmUpgrade`**~~ – *erledigt:* Labortest `e2e.sh` Schritt 13 (12 Fälle für
    `$cfmVerGe`, `check=yes` auf eine Beta der nächsten Version ergibt „upgrade“). – `$cfmVerGe` las „7.25beta5“ als 7.0 (`[:tonum "25beta5"]`
    ist `nil`) und stufte ein Update von 7.24.4 als Downgrade ein (`/system/package/downgrade`).
    Hardware-Befund: hAP be³ Media, dessen Switch-Ports erst ab 7.25beta4 funktionieren, dort von
    Hand aktualisiert. Behoben in `lib/mgr-onboard.rsc` (alpha < beta < rc < fertig), auf RouterOS
    7.24.4 mit 16 Fällen geprüft; Labortest (e2e) offen.
37. ~~**Mindestgröße in `$cfmPkgFetch`**~~ – *erledigt (D52):* NPK-Kennung (`1e f1 d0 ba`) statt
    Mindestgröße, `$cfmUpgrade … check=yes` listet fehlende Pakete samt Ablageort, der Auftrag nennt
    alle auf einmal. Offen: Prüfsummen von MikroTik (falls es eine Liste gibt). – Pakete unter 100 KB galten als kaputter Download und wurden
    gelöscht; echte Zusatzpakete sind kleiner (`ups` für `arm` ~45 KB). Grenze auf 20 KB gesenkt
    (Admin-Guide 8.6: Pakete für einen Manager ohne Internet von Hand ablegen).
    Besser: echte Prüfung (NPK-Kennung am Dateianfang oder Größe aus einer Prüfsummenliste von
    MikroTik). Außerdem: Ohne Internet am Manager müssen alle installierten Pakete eines Geräts vorab
    in `<pkgPath>/<ver>/` liegen – `$cfmUpgrade` könnte die fehlenden vor dem Auftrag auflisten.
38. ~~**RouterOS-Update auf Geräten mit 16 MB Flash**~~ (hEX RB750Gr3, CRS328 u.ä.) – *erledigt
    (D63):* `$cfmUpgrade … via=internet|via=mirror mirror=<IP>` nutzt das eingebaute Update des
    Geräts, der Spiegel ist `tools/upgrade-mirror.py`; Labor: `e2e.sh` Schritt 13e. tmpfs geht nicht
    (Laborversuch 2026-10-03). Auf Hardware: hEX mit 2,4 MB frei über den Spiegel aktualisiert. – *Vorab-Prüfung
    erledigt (D51):* Agent meldet den freien Platz (`fs`), `$cfmUpgrade` erteilt zu vollen Geräten
    keinen Auftrag, der Agent prüft vor dem Download erneut. Offen bleibt das Update selbst (tmpfs
    oder eingebautes Update, nur mit Hardware testbar). – `$cfmUpgrade` lädt
    die Pakete per SFTP in den Flash des Geräts; dort sind oft nur 2–3 MB frei, `routeros` braucht
    ~12 MB. Das eingebaute Update (`/system/package/update`) kommt damit zurecht, braucht aber Internet
    am Gerät. Optionen: Pakete in eine tmpfs-Disk (`/disk add type=tmpfs`) laden und von dort
    installieren, falls RouterOS das zulässt; oder für solche Geräte das eingebaute Update über einen
    Proxy/Update-Pfad des Managers. `$cfmUpgrade` sollte vorab den freien Platz prüfen und klar abbrechen.
39. **Mindestsignal für Clients** – *vorbereitet (D55):* `wifi.rsc` `steer` je Band (802.11v-Vorschläge
    an Clients unter der Schwelle, optional Trennen nach `kick`) und `minSignal` für die Anmeldung,
    standardmäßig aus. Vor Ort: Abdeckung prüfen, Schwellen je Band ermitteln, dann einschalten. – Hardware-Befund Roaming-Test mit FT: Die
    Wechsel selbst dauern meist unter 1 s, aber Clients bleiben lange an einem schwachen AP hängen
    (z.B. −79 dBm auf 2,4 GHz, viele kurze Aussetzer), obwohl ein stärkerer AP in Reichweite ist; ein
    Client verlor sogar erst die Verbindung, bevor er wechselte. FT beschleunigt nur den Wechsel, nicht
    die Entscheidung dazu. Idee: `/interface/wifi/access-list` mit `signal-range` aus `wifi.rsc`
    rendern (z.B. Clients unter −75 dBm abweisen bzw. trennen), optional je Band oder AP; dazu prüfen,
    ob die Steering-Einstellungen (`rrm`/`wnm`, BSS Transition) aktiv zum Wechsel auffordern.
    Risiko: In Randbereichen ohne besseren AP verliert ein Client dann ganz die Verbindung – vorher
    die Abdeckung prüfen (Löcher zwischen APs). Steering trennt Clients mit FT nicht → 61.
40. **Lokaler Fallback der APs (D46), offene Punkte** (a vorbereitet, b/c/d/e erledigt) – *40a vorbereitet
    (D54):* `fallback="yes"` an einer SSID schaltet `slaves-static` ein und hängt den virtuellen APs
    eine lokale Kopie an; Test vor Ort (CAPsMAN-Dienst kurz aus). Hardware-Befund beim Ausrollen
    (2026-10-02): Das erste Setzen von `slaves-static=no` (vorher nicht gesetzt) trennt jeden AP kurz
    vom CAPsMAN (3–24 s, „configuration changed“), danach nie wieder. ~~Verbesserung: den Wert nur
    setzen, wenn ein `fallback` es verlangt oder er gerade `yes` ist.~~ – *erledigt 2026-10-04*
    (Labor: `e2e.sh` 14c; ein AP, der den Wert schon gesetzt hat, bleibt unberührt). – Umgesetzt ist die `master`-SSID je Radio
    (`capsman-or-local`, Hardware-Test mit einem cAP ax). Offen: (a) weitere SSIDs als lokale
    virtuelle APs – ob `/interface/wifi/cap slaves-static=yes` die vom CAPsMAN angelegten virtuellen
    APs im Fallback mit ihrer lokalen Konfiguration weiterlaufen lässt, erst mit einer zweiten aktiven
    SSID auf Hardware testen; bis dahin fallen Gast/IoT im Fallback aus. (b) Client im Fallback
    – ~~geprüft~~ 2026-09-27: bei einem CAPsMAN-Ausfall aller APs meldete sich ein Handy nach 2 s
    lokal an und blieb im VLAN der SSID erreichbar. (c) ~~MLO~~ – geklärt: im Fallback ohne MLO (Radios vom Werks-MLD `mld1`
    gelöst, D46); lokales MLO wäre ein eigener Ausbau. ~~(d) Anzeige, wenn ein AP im
    Fallback läuft~~ – erledigt: Der Agent meldet `wfb` (CAP an, aber kein CAPsMAN verbunden) und
    schreibt eine Warnung ins Log, `$cfmStatus` zeigt „WLAN lokal“; eine Benachrichtigung hängt an 2. (e) ~~Dynamisches MLD~~ – ein
    CAPsMAN auf einem hAP be³ legte das MLD eines Wi-Fi-7-CAP beim ersten Kontakt abgeschaltet an
    (siehe Hardware-Eigenheiten); 2026-09-27 geprüft: von Hand eingeschaltet, blieb es nach einem
    Neustart des CAPsMAN an, und nach einer Neuprovisionierung (neue Namen, D47) legte er es aktiv
    an. Nur beim allerersten Kontakt eines CAP prüfen.
41. ~~**Kanalplan per Scan**~~ (entschieden 2026-09-27: fester Plan, gelegentlich neu optimieren) –
    *erledigt (D56, D60):* `$cfmWifiScan` scannt über den CAPsMAN (der CAP selbst lehnt den Scan ab,
    der CAPsMAN liefert erst ab ~10 s Ergebnisse) und schlägt Pins für 1/6/11 und 1/5/9/13 vor.
    Hardware 2026-10-03: Feldnamen `address`, `channel` („2437/ax“), `signal`, `ssid`; 30–42 Netze je
    AP auf 2,4 GHz. Die Zeile „Aktuell“ blieb leer, weil `monitor` auf einem CAP keinen Kanal liefert
    – der Agent liest ihn jetzt aus `about`. Eine Messung ohne Netze ergibt keinen Vorschlag mehr
    (vorher „alle auf 2412, Kosten 0“). –
    Manager-Befehl `$cfmWifiScan`: über den CAPsMAN von jedem AP aus scannen
    (`/interface/wifi/scan cap-wifiN duration=…`, nur Radios ohne Clients oder mit Hinweis), fremde
    Netze und ihre Kanäle je AP sammeln, einen Pin-Vorschlag für `wifi.rsc → radios` berechnen
    (Kanalsätze 1/6/11 und 1/5/9/13, fremde APs mit festem Kanal als Randbedingung, Gewicht nach
    Signalstärke) und ausgeben. Ob 3 oder 4 Kanäle besser sind, im Betrieb mit beiden Plänen
    vergleichen (Paketverlust der Clients auf 2,4 GHz). Ohne Pins wählt der CAPsMAN die Kanäle bei
    jeder Neuverbindung neu – nach einem Aussetzer also womöglich andere.
42. ~~**Seriennummern mit `/` (CHR)**~~ – *behoben:* Manager, Backup-Spiegel und Agent bilden den
    Manifest-Dateinamen gleich (`/` → `_`); Inventar, Status und Vault behalten die echte Seriennummer.
    Befund run46: sw1 `d22cZ/i6gUB` verwarf danach jedes Manifest („Manifest-MAC ungültig“). – Labor-Befund 2026-09-27: Die System-ID einer frischen CHR-VM
    begann mit `/` (`/G9Di3fN32A`). Der Manifest-Pfad `live/m/<serial>.mf` wird dann zu
    `live/m//….mf`; RouterOS legt die Datei beim ersten Mal an, `/file/find` findet sie unter diesem
    Namen aber nicht wieder, jedes weitere `$cfmWrite` scheitert mit „file already exists“ – jedes
    Release bricht nach dem Archiv ab. RouterBOARD-Seriennummern sind alphanumerisch (nicht
    betroffen). Lösung: Seriennummer für Dateinamen einheitlich umsetzen (z.B. `/`→`_`), auf Agent-
    und Manager-Seite gleich; `$cfmEnroll` sollte solche Zeichen melden.
43. ~~**`/ip/service address` ist ab RouterOS 7.24 veraltet**~~ – *behoben:* `base` setzt
    `available-from`, sofern das Eigenschafts-Array es kennt, sonst `address` (7.23 und älter). – Befund 2026-09-27 (hAP be³, 7.25beta):
    Setzt die Rolle `base` `address`, meldet RouterOS „deprecation warning: address … will be
    removed in future versions“ und übernimmt den Wert nach `available-from`. `get` liefert beide
    Felder, der Vergleich bleibt deshalb idempotent. Vor dem Wegfall auf `available-from` umstellen,
    ältere Versionen kennen nur `address` → Feldname nach der Version wählen (oder nach dem
    Eigenschafts-Array von `get`).
44. ~~**Agent auf einem Backup-Manager fragt sich selbst**~~ – *Rest erledigt (D58):* auch der Abruf des
    Manifests (normal und im Watchdog-Lauf) wiederholt mit 8/16/32/64 s Pause; die Dateien ebenso.
    Labor (run57b): Fällt der Apply des Backup-Managers in seinen eigenen Spiegel-Sync, dauert er so
    gut 3 min statt 25 s – er gelingt aber. Der Spiegel-Sync selbst wird nicht gesperrt (bewusst,
    Entscheidung 2026-10-01). – *behoben:* `$cfmFetch` überspringt die
    eigenen Adressen, wenn es den Geräte-User lokal nicht gibt (der Primary behält seinen SFTP-Weg zu
    sich selbst); `$cfmGetFiles` versucht es bis zu fünfmal mit 10/20/30/40 s Pause. Labor-Befund run45/48/49:
    Solange der Backup-Manager seinen Spiegel zieht (~1 min), beantwortet der SFTP-Server des Primary
    keine weiteren Downloads – auch nicht den Agent des Primary selbst; drei Versuche in 30 s reichten
    nicht. Offen: den Spiegel-Sync und die Agent-Läufe gegeneinander sperren statt nur zu warten; der Abruf
    des Manifests selbst wird noch nicht wiederholt (run50/51: „kein Manager erreichbar“ auf cm2
    während des Syncs, ein Labortest in 14c scheiterte dadurch einmal). Betrifft nur Standorte mit
    Backup-Manager. – Labor-Befund 2026-09-27: Erreicht der
    Agent von cm2 (`manager-backup`) den Primary nicht (Timeout, während cm2 seinen Spiegel
    synchronisiert), versucht er die nächste Manager-Adresse – seine eigene – mit dem Geräte-User
    `cfmd-<name>`, den es dort nicht gibt („login failure … critical“ im Log, danach „kein Manager
    erreichbar“). Der nächste Lauf holt es nach. Eigene Adresse aus der Liste nehmen oder dort lokal
    aus dem Spiegel lesen; ein einmaliger Timeout sollte einen kurzen Wiederholversuch auslösen.
45. **RouterOS 7.24.5 (2026-09-29)** – Changelog-Punkte, die cfm berühren: „scheduler scripts with the
    default start date and time not being triggered (introduced in v7.24)“ betrifft `cfm-watchdog`,
    `cfm-agent-retry`, `cfm-onboard-revert` und die Bootstrap-Stufen (alle ohne `start-time`); im
    Labor feuern sie unter 7.24.2 und 7.24.5 (Watchdog-Rollback: `e2e.sh` Schritt 14d). Außerdem
    „poe-out – fix loss of PoE-out capability on CRS328-24P-4S+ after a reboot“ (Core-Switch, der
    APs per PoE versorgt) und für den hAP be³ Media VLAN-Offloading im Switch-Chip und stabilere
    Ethernet-Ports (womöglich der Fehler der Kabel-Ports unter 7.24.2–7.24.4). Der Labortest aller
    Skripte auf 7.24.5 ist grün (e2e 169, Onboarding 14/15/18, `e2e-vrrp.sh` 79), e2e auf 7.24.2
    ebenso. Update auf Hardware: vor Ort.

46. ~~**`$cfmWifiScan` mit den eigenen Radios des CAPsMAN**~~ – *erledigt 2026-10-04:* Der CAPsMAN
    scannt mit, wenn er ein eigenes Interface `<Name>-<Band>g` hat (also mitfunkt), und steht dann im
    Vorschlag; sein Agent meldet die Kanäle seiner eigenen Radios (`$cfmChannels`, Zeile „Aktuell“).
    Ohne dieses Interface bleibt er draußen (abgeschaltete Radios gehören nicht in den Plan).
    `host=` ersetzt nur diesen AP in der letzten Messung, statt sie zu überschreiben (eine Messung eines
    anderen Bands ersetzt es ganz). Hardware 2026-10-04: hAP be³ als CAPsMAN mit drei eigenen Radios in
    `$cfmChannels` und im Vorschlag, `host=` mit vier APs aus einer früheren Messung zusammengeführt. – Der Scan und der Pin-Vorschlag umfassen nur
    Geräte mit Rolle `ap`. Funkt der CAPsMAN selbst mit (`capsmanRadios`), fehlt er in der Rechnung;
    seine Radios lassen sich direkt scannen (auch abgeschaltet, Hardware 2026-10-03). Einbauen, damit
    ein Vorschlag alle Sender kennt.
47. **Erstes Release nach dem Update auf D68 (einmalig je bestehender Installation)** – Das erste Release nach
    dem Hochladen baut noch der installierte Manager-Code. Der kennt `lib/lib-wifi.rsc` nicht, die
    Manifeste der WLAN-Geräte (Rollen `ap`, `capsman`, `manager`) nennen die Datei dann nicht. Geräte,
    die seit ihrem letzten Apply neu gestartet sind, haben die WLAN-Funktionen nicht mehr im Speicher
    und brechen mit „lib/lib-wifi.rsc fehlt im Manifest (D68)“ ab: Rollback mit Neustart, die
    Version gilt als `bad`. Die übrigen laufen mit den Funktionen aus dem Speicher durch. Vorgehen:
    1. Framework wie gewohnt hochladen.
    2. Am Manager vor dem Release den neuen Manifest-Bau aus `work/` laden:
       `/system script run cfm-mgr; /import cfm/work/lib/mgr-core.rsc verbose=no`
    3. Gleich danach in derselben Sitzung `$cfmRelease msg="…"` (ringweise oder `all=yes`); der
       Manager-Tick lädt sonst wieder den installierten Code. **Korrektur 2026-10-11:** Schritt 2 gilt
       vor **jedem** Befehl, der Manifeste baut (`$cfmRelease`, `$cfmPromote`, `$cfmEnroll`,
       `$cfmUpgrade`), bis der Manager die neue Version selbst angewendet hat (`$cfmStatus`). Ein
       `$cfmPromote ring=1` aus einer neuen Sitzung baute sonst mit dem alten Code alle Manifeste neu,
       ohne `lib-wifi` auch für Ring 0. Ab D70 (Regeln je Version aus dem Archiv) entfällt der Handgriff
       bei künftigen Updates; für den ersten Sprung auf D70 bleibt er nötig. Achtung `ringSoak`: Nach
       dessen erstem Wert befördert der Manager-Tick den nächsten Ring selbst, mit dem installierten
       Code. Ring 1 und 2 deshalb vorher von Hand befördern (je mit dem Import) oder gleich `all=yes`.
    4. Prüfen: `$cfmStatus` ohne Fehler; das Manifest eines AP nennt den WLAN-Teil, z.B.
       `:put [:find [/file/get cfm/live/m/<Seriennummer>.mf contents] "lib-wifi"]` (Zahl, nicht leer).
    Falls Schritt 2 vergessen wurde: Sobald der Manager die Version angewendet hat, `$cfmManifests`,
    dann je zurückgerolltem Gerät `$cfmPush host=<name> force=yes`. Im Labor (2026-10-11) mit dem
    Stand von v19 durchgespielt: alle drei Geräte ok, nur der Manager bekam den WLAN-Teil.
48. **RouterOS 7.25 (Labor mit 7.25rc1, 2026-10-11)** – Changelog-Punkte und Laborbefunde, die cfm
    berühren:
    * ~~SSH-Client prüft Host-Keys~~ – *erledigt (D71).* Ein frisches oder zurückgesetztes 7.25 brach den
      Bootstrap ab („host key not trusted“), nach einem Update bleibt die Prüfung aus.
    * ~~Version ohne Kanal~~ – *erledigt:* Der Agent meldet `7.25.1 (stable)`; ohne Kanal machte
      `:deserialize` beim Manager eine IP-Adresse daraus (DECISIONS, Labor-Eigenheiten).
    * **PoE-Firmware:** 7.25 aktualisiert die PoE-Firmware der 802.3at/bt-Geräte, laut Changelog mit
      kurzer Unterbrechung an allen PoE-Ports. Betrifft Switches, die APs per PoE versorgen: Update im
      Wartungsfenster, die APs starten mit.
    * **FT für MLD-Geräte** („wifi - add fast transition support for MLD devices“): D48 hat MLO
      abgeschaltet, weil der hAP be³ als MLD kein FT anbot. Nach dem Update auf 7.25 mit einem Client
      prüfen, ob MLO mit FT jetzt geht (`wifi.rsc` `mlo`).
    * ~~**Globals über die API**~~ – *geprüft 2026-10-12 (7.25rc1 gegen 7.24.5):* Ein über die API
      gestartetes Skript setzt jetzt `:global`-Variablen in der gemeinsamen Umgebung (7.24.5: nicht).
      Lesen kann `/system/script/environment` weiterhin nur ein User mit `write` und `policy` (getestet
      mit read+api+rest-api+test, +policy, +write, +sensitive: „not enough permissions“). Für den
      Gast-Schalter (D64) ändert sich nichts: HA liest den Zustand weiter per API (bis D90 aus den Regeln,
      seitdem an den Interfaces); `cfmSsid<key>`
      auf der Konsole stimmt ab 7.25 auch nach dem Schalten aus HA.
    * **WebFig** zeigt Dateiinhalte weiter nicht an (D73, Lesezeichen-Editor).
    * **Labor mit 7.25rc1 (2026-10-12):** alle Skripte grün – `e2e.sh` 292, Onboarding 14/15/18,
      `e2e-vrrp.sh` 79. Mit 7.25 stable nur `e2e.sh` wiederholen, sofern der Changelog nichts Neues
      zu SSH, fetch, Skripten oder `/file` nennt. Abends mit D74–D76: `e2e.sh` 294, `e2e-mlag.sh` grün.
    * **Labor mit 7.25rc2 (2026-10-13):** alle Skripte grün – `e2e.sh` 298 (mit D79), Onboarding
      14/15/18, `e2e-vrrp.sh` 79, `e2e-mlag.sh` 72; kein neuer Befund zu cfm.
    * **Labor mit 7.25rc2 (2026-10-17, Stand D82):** alle Skripte grün – `e2e.sh` 315, Onboarding 14/15/18,
      `e2e-vrrp.sh` 79, `e2e-mlag.sh` 72. Eine Forumsmeldung aus der Beta-Zeit (Skripte über ~16 kB nach
      einem Neustart ungültig) ließ sich nicht nachstellen: ein Skript mit 45 KB bleibt nach dem Neustart
      gültig und läuft per Scheduler `startup`. Changelog-Durchsicht für einen Standort: nichts, was ein
      Update vor einem Router-Umbau nötig macht; das PoE-Firmware-Update (kurze Unterbrechung aller
      PoE-Ports) gehört in ein eigenes Wartungsfenster; unter rc1 meldete ein Nutzer hAP-ax³-CAPs mit
      fehlenden SSIDs (zu rc2 noch keine Meldungen).
49. **RouterOS 7.26beta1 (Kanal development, 2026-10-01)** – `e2e.sh` im Labor grün (2026-10-12, 292).
    Punkte aus dem Changelog, die cfm berühren können:
    * „l3hw - add VRRP hardware offloading support“: D37 schaltet für VRRP das Routing im Switch-Chip
      ab. Mit 7.26 prüfen, ob ein CRS als VRRP-Router im Chip routen kann (Zonen-Firewall bleibt aber in
      der CPU – also nur für Netze ohne Filter interessant).
    * „switch - add interface-list support to port isolation“: Alternative für isolierte Kabel-Ports
      (D76) im Switch-Chip statt `hw=no`.
    * „bridge - add a per-VLAN DHCP snooping option“ (Rolle `switch`, `dhcpSnoop`).
    * „cmr - add initial implementation of centralised platform for RouterOS devices, allowing updates,
      monitoring, alerts“: eine zentrale Verwaltung von MikroTik selbst – beobachten, wie weit sie reicht.
    * „wifi - add a default-country parameter in radio settings“, „ethernet - move the port bandwidth
      setting to the switch port menu“ (cfm setzt beides nicht).
50. ~~**Broadcasts füllen das Log der Nicht-Router**~~ – *erledigt 2026-10-13 (D78):* MNDP mit Quelle
    `0.0.0.0` verwirft der input-Block `fwb` still, vor dem Log. Zuerst an der Quelle (`7635c5e`: VMs mit
    `stp="none"` ohne MNDP), am selben Tag zurückgenommen: Die VM fehlte dann in Winbox, und gezielt nur
    für die Karte geht es nicht (Labor, D78); das Gerät mit
    eigener Adresse im Client-VLAN verwirft dort per `local-input` still (Site-Regel, an dem Standort
    ausgerollt: kein `cfm-drop` mehr aus dem VLAN). Befund 2026-10-12: Die minimale Firewall (D31)
    loggt jedes verworfene Paket an das Gerät selbst (Chain `input`), auch Broadcasts. Weitergeleitet
    wird davon alles normal: Der Filter sieht nur, was an das Gerät geht, nicht den Verkehr der Clients
    untereinander. Zwei Quellen an einem Standort, jeweils über 80 % der 1000 Zeilen des RAM-Logs (es
    reichte nur etwa 7 h zurück, WLAN-Ereignisse (D77) und Fehler fallen früh heraus, über Syslog
    entsteht dieselbe Menge):
    * **MNDP des Managers in einer VM:** Die Nachbarsuche läuft auf allen Bridge-Ports (D33). Über seine
      Karte im MGMT-VLAN (D40, ohne eigene Adresse an der Karte) sendet er MNDP (UDP 5678) mit Quelle
      `0.0.0.0` an 255.255.255.255, alle 30 s. Jedes Gerät im MGMT-VLAN verwirft das (Quelle nicht in
      `cfm-mgmt`) und loggt es; die MNDP-Pakete mit seiner MGMT-Adresse kommen durch.
    * **Gerät mit eigener Adresse in einem Client-VLAN** (z.B. ein AP mit NAT-Käfig per `post.rsc`):
      bekommt jeden Broadcast dieses VLANs zugestellt (Discovery von Medienservern UDP 32412/32414,
      SSDP, NetBIOS, MNDP anderer Geräte).
    Verworfen: Broadcast/Multicast allgemein ohne Log verwerfen bzw. das Log enger begrenzen
    (behandelt nur die Wirkung, der Nutzer wollte die Ursachen beheben); für MNDP mit Quelle `0.0.0.0`
    blieb nur der Empfänger, und die Regel trifft genau diese Pakete.

51. ~~**Kanalplanung mit den anderen Funknetzen im 2,4-GHz-Band**~~ (Idee des Nutzers, 2026-10-13) –
    *erledigt 2026-10-16 (D80):* `wifi.rsc` → `others`, Kosten mit Nähe-Gewicht (auch Bluetooth und
    Milight), Kanalvorschlag für Zigbee/Thread mit `auto`, Kanalsatz 1/5/9, Warnung in `$cfmCheck`.
    Offen: Energie-Messungen der Koordinatoren einbeziehen. Befund und Herleitung:
    `$cfmWifiScan`/`$cfmChannels` (D56) sehen nur WLAN. Im selben Haus funken oft auch Zigbee, Thread,
    Bluetooth (classic und LE) und proprietäre Funkbrücken (z.B. Milight). Beides berücksichtigen:
    * **Andere Netze bei der Wahl der WLAN-Kanäle:** Site-Daten (z.B. ein Schlüssel in `wifi.rsc`)
      nennen die Netze mit Art und Kanal; `$cfmChannels` rechnet sie in die Kosten ein oder schließt
      WLAN-Kanäle aus, die ein Netz mit festem Kanal überdecken, und warnt, wenn ein Pin das tut.
    * **Kanalvorschlag für neue Netze:** Für ein 802.15.4-Netz mit Kanal `auto` (ein neues Thread- oder
      Zigbee-Netz) den Kanal mit dem größten Abstand zu den WLAN-Kanälen des Plans und zu den übrigen
      802.15.4-Netzen vorschlagen; 26 nur nachrangig (manche Geräte beherrschen ihn nicht oder nur mit
      weniger Leistung).

    | Funk | Kanäle | Verhalten |
    |---|---|---|
    | WLAN 20 MHz | Mitte 2407 + 5·n MHz, belegt Mitte ±10 MHz | fester Kanal je AP (Pins) |
    | 802.15.4 (Zigbee, Thread) | 11–26: 2405 + 5·(k−11) MHz, je etwa 2 MHz | fester Kanal je Netz, jedes Netz einen eigenen. Zigbee wechselt mit Aufwand (schlafende Endgeräte folgen erst beim Aufwachen, manche gar nicht), Thread über das Pending Dataset ohne Neuanlernen |
    | Bluetooth classic | 79 × 1 MHz, 2402–2480 MHz | springt, AFH meidet belegte Kanäle von selbst |
    | Bluetooth LE | 40 × 2 MHz, Advertising 37/38/39 = 2402/2426/2480 MHz | Advertising auf festen Kanälen, Daten springen nach Kanalliste |
    | Milight (LT8900/PL1167) | 2402 + n MHz, je Gerätetyp drei feste Kanäle: RGBW 9/40/71 (2411/2442/2473 MHz), CCT 4/39/74, RGB+CCT 8/39/70 | jeder Befehl auf allen drei Kanälen, ohne Rückmeldung |

    Folgerungen für die Kanalsätze von D56 (umgesetzt in D80):
    * **1/5/9/13** deckt 2402–2482 MHz lückenlos ab, jeder 802.15.4-Kanal liegt in einem WLAN-Kanal.
      Frei wird einer nur, wenn ein WLAN-Kanal im ganzen Haus frei bleibt. Ohne 13 (also **1/5/9**)
      sind 24–26 frei, 23 liegt nur 2 MHz über WLAN 9. Den Satz 1/5/9 probiert `$cfmWifiScan` seit D80
      mit; Sätze aus allen Kombinationen abzuleiten wurde nicht gewählt (Rechenzeit auf dem Manager, D80).
    * **1/6/11:** 15 und 20 liegen in den Lücken, 25 und 26 über 11 (11 endet 2 MHz vor 25). Daher
      stammt die übliche Zigbee-Empfehlung 15/20/25. Auch BLE 38 und 39 liegen außerhalb.
    * Milight RGBW: unter 1/5/9/13 liegen alle drei Kanäle in WLAN-Kanälen, unter 1/5/9 ist 2473 MHz frei.
    * Ein AP direkt neben einem Koordinator kann dessen Empfänger auch auf einem freien Kanal
      übersteuern: 1–2 m Abstand.

    Entschieden 2026-10-16 (D80): Kosten mit Nähe-Gewicht, Daten in `wifi.rsc`, Bluetooth und Milight
    als Kosten. Noch offen: ob Messungen der Koordinatoren einfließen (Energie-Scan je 802.15.4-Kanal aus
    den ZHA-Diagnosedaten bzw. `commissioner energy` in OpenThread; die MikroTik-Radios sehen nur WLAN).
    Quellen: [Zigbee2MQTT, Zigbee-Netz](https://www.zigbee2mqtt.io/guide/configuration/zigbee-network.html),
    [OpenThread Channel Manager](https://docs.silabs.com/openthread/2.5.0/openthread-api/api-channel-manager),
    [TI SWRA475A, BLE-Koexistenz mit WLAN](https://www.ti.com/document-viewer/lit/html/SWRA475A/coexistence-swra4755506),
    [Argenox, BLE Advertising](https://argenox.com/library/bluetooth-low-energy/ble-advertising-primer),
    [esp8266_milight_hub, Funkparameter](https://github.com/sidoh/esp8266_milight_hub/blob/master/lib/Radio/MiLightRadioConfig.cpp),
    [Milight-Funkprotokoll (Hackaday)](https://hackaday.io/project/5888-reverse-engineering-the-milight-on-air-protocol/log/18456-in-the-radio-domain).

52. ~~**Lesezeichen ohne Hantieren**~~ (Wunsch des Nutzers, 2026-10-15) – *erledigt 2026-10-22 (D91): festes
    Lade-Lesezeichen „cfm“, das die Fassung vom Gerät startet (`cfm/work/web/`, mit dem Release zu Manager und
    CAPsMAN); entschieden aus den Wegen unten, im Labor geprüft (Verteilung je Rolle, Laden per REST mit nachgebildetem
    Browser). Offen: im echten Browser an einem Standort nach dem nächsten Framework-Update einmal anlegen
    und die alten Lesezeichen löschen.* –
    Die Lesezeichen von D73/D77 müssen
    aus `install.html` in die Leiste gezogen und nach jeder neuen Fassung ersetzt werden. Auf dem Gerät
    selbst lässt sich nichts installieren: Wegen fehlender CORS-Header muss der Code unter derselben Adresse
    laufen wie `/rest`, `www` liefert keine eigenen Dateien aus, Skins sind nur JSON, Hotspot-Seiten liegen
    unter einer anderen Adresse (Befunde in DECISIONS, Eigenheiten). Bekannte, vorerst verworfene Wege:
    * **Festes Lade-Lesezeichen, Code auf dem Gerät:** ein winziges Lesezeichen „cfm“, einmal angelegt;
      es liest `cfm-editor.js`/`cfm-monitor.js` über die bestehende WebFig-Sitzung (`fetchFile` über
      `/jsproxy`, im Labor geprüft) vom Gerät und startet sie. Updates kommen mit `upload-seed.sh`.
      Dagegen: undokumentierte WebFig-Interna (Rückfall: Laden per REST nach der Anmeldung); der CAPsMAN
      braucht die Dateien auch, wenn er nicht der Manager ist.
    * **Userscript** (Violentmonkey/Tampermonkey): einmal `cfm.user.js` installieren, es blendet in jeder
      WebFig-Seite Knöpfe für Editor und WLAN ein, Updates per `@updateURL` aus dem öffentlichen Repo.
      Dagegen: Browser-Erweiterung nötig (D73), Code aus dem Netz.
    * **Container auf dem Gerät** (RouterOS-Container bzw. „Apps“), der die Seite ausliefert und `/rest`
      durchreicht; im Browser nichts. Dagegen: Container-Paket und Speicher nötig (ein CRS328 im Einsatz hat 1,6 MB frei,
      hAPs knapp).
53. ~~**Gerätesuche `$cfmFind` und Lesezeichen „cfm-Monitor“**~~ (Wunsch des Nutzers, entschieden 2026-10-16) –
    *erledigt 2026-10-16 (D81, Admin-Guide 8.10/8.11): `$cfmFind`, der bisherige interne Helfer heißt
    `$cfmIds`; Lesezeichen cfm-Monitor mit den Reitern WLAN und Suche. Offen: Test der Suche an einem
    Standort (Labor: e2e Schritt 14, Antworten eines Standorts per `data=`, Lesezeichen gegen die Labor-VM).* –
    Für den Betrieb: auffällige Geräte schnell finden, nach MAC, IP, Name oder Port bzw. AP/SSID/Signal.
    * **Entschieden:** Live-Suche am Manager, `$cfmFind <text>` (Teiltext über MAC, IP, Name, Port). Der
      Manager fragt die Geräte per ssh-exec ab (wie `$cfmSecretPush`); gesucht wird auf dem Gerät durch
      eine kleine lib-Funktion, ssh-exec stößt sie nur kurz an (lange Befehle: „action timed out“).
      Quellen: FDB (`/interface/bridge/host`), ARP/IPv6-Nachbarn der Router, DHCP-Leases und
      `leases.rsc`, Registrierungstabelle des CAPsMAN (AP, SSID, Signal, Rate). Den Endport bestimmt der
      Manager über die Uplinks (Ports mit Infrastruktur-Nachbarn aus `nb`/`$cfmLinks`, Port-Profile).
      Kein Verlauf und keine Tick-/Flash-Last – Verlauf liefert LibreNMS (54). Verworfen: Schnappschuss
      je Tick mit Index auf dem Manager, Python-Tool am Admin-PC, nur LibreNMS.
    * **Bedienung:** Terminal und ein Suchfeld im Lesezeichen, das `$cfmFind` per `:execute file=` auf
      dem Manager startet (wie der cfm-Editor). Das Lesezeichen „cfm-WLAN“ (D77) heißt dann
      **„cfm-Monitor“** (`tools/editor/`, `install.html`, `build.py`, tools/README, Admin-Guide 8.10).
    * Grenzen: In Netzen mit fremdem DHCP (z.B. Fritz!Box) kennt cfm IPs nur aus der ARP-Tabelle eines
      eigenen Routers mit Adresse im VLAN, Namen nur aus `leases.rsc`. Rolle `ap` läuft im Labor nicht
      (CHR ohne Radios) – WLAN-Teil nur mit Hardware testbar.
54. **LibreNMS anbinden: SNMPv3 und Syslog** (entschieden 2026-10-16) – LibreNMS übernimmt Verlauf und
    Messwerte (FDB/ARP mit Suche, LLDP-Karte, Port-Graphen, Alerts) und wird der geplante externe
    Syslog-Server (22). Rolle `base`: SNMPv3 authPriv nur von der LibreNMS-Adresse, Freigabe UDP 161 im
    input-Block, Schlüssel `snmp` in `global.rsc`, Passwort über den Vault/`$cfmSecretPush`; `syslog`
    zeigt auf LibreNMS. Optional: Geräte aus dem Inventar per LibreNMS-API anlegen. Vorher am hAP per
    `snmpwalk` prüfen, was das `wifi`-Paket über SNMP liefert (seit 7.17 „wifi fields“ in der
    MIKROTIK-MIB; ob die Clients am CAPsMAN dabei sind, ist offen – sonst bleiben Signal/SSID bei
    `$cfmFind`/cfm-Monitor). Standorte, die nur per WireGuard erreichbar sind: Peer für den LibreNMS-Server.
    * **Netz (entschieden 2026-10-16):** Steht der LibreNMS-Server in einem Client-VLAN, bekommt er eine
      **zweite Schnittstelle im MGMT-VLAN** (feste Adresse, ohne Gateway, kein IP-Forwarding auf dem
      Host). SNMP-Abfragen und Syslog laufen nur über diese Adresse, Weboberfläche, Updates und Alerts
      über die bisherige. Die Geräte geben SNMP nur dieser MGMT-Adresse frei – nicht über `mgmtExtra`,
      das vollen Management-Zugang gäbe. Verworfen: ganz ins MGMT-VLAN (dort kein Internet für Updates
      und Alerts), im Client-VLAN lassen mit gezielter Freigabe (Monitoring-Zugang aus dem Client-LAN).
55. **Netbox** (Idee, 2026-10-16, vorerst nicht) – zwei Varianten merken:
    * **Einweg-Export cfm → Netbox:** Tool liest das Overlay (`pull-site.sh`), `inventory.rsc`,
      `vlans.rsc`, `leases.rsc` und `netzplan.csv` (`$cfmLinks`) und legt per API Site, Geräte
      (Modell, Seriennummer, Rolle, RouterOS-Version), Interfaces, MGMT-IPs, VLANs, Prefixe, feste IPs
      mit DNS-Namen und Kabel an. Nur Doku, für die Fehlersuche wenig Nutzen.
    * **Netbox als Quelle:** Netbox erzeugt `vlans.rsc`/`leases.rsc` u.a. Widerspricht D72 (der Manager
      führt die Site-Daten, der cfm-Editor schreibt hinein) – bräuchte eine neue Entscheidung, wer gewinnt.
56. ~~**Vorhandene VLAN-Interfaces an Bridge und VLAN-ID übernehmen**~~ (entschieden 2026-10-17) – *erledigt
    2026-10-20 (D87):* `$cfmVlanKey` sucht zuerst `vlan<VID>`, sonst ein VLAN-Interface auf der Bridge mit
    dieser VLAN-ID; die Rollen übernehmen es und benennen es um. Labor: `e2e.sh` Schritt 9. – `router`
    (`vlan:<VID>`) und `base` (MGMT-VLAN) übernehmen ein vorhandenes VLAN-Interface nur, wenn es schon
    `vlan<VID>` heißt. Heißt es anders (z.B. `GAST`, `IOT` aus einer Konfiguration von Hand), legt der
    Probelauf ein zweites Interface mit derselben VID auf der Bridge an (`neu: /interface/vlan vlan:<VID>`),
    der Apply scheitert oder doppelt das VLAN. Befund beim Router-Umzug eines Standorts: dort vorher
    von Hand umbenannt. Umsetzen: natürlicher Schlüssel `interface` + `vlan-id`, beim Übernehmen in
    `vlan<VID>` umbenennen (Verweise in RouterOS gehen über die ID, Adressen bleiben am Interface).
    Labor: `e2e.sh` mit einem vorher angelegten VLAN-Interface unter fremdem Namen, Probelauf zeigt
    „übernommen“, Apply ohne Duplikat, Adresse bleibt.
57. ~~**`wg-client-setup.sh` ohne `wireguard-tools`**~~ (Befund 2026-10-17) – *erledigt 2026-10-20:* `genkey`
    nimmt ohne `wg` OpenSSL (Weg wie unten); drei so erzeugte Schlüssel gegen eine eigene X25519-Rechnung
    und gegen RouterOS (öffentlicher Schlüssel eines `wireguard`-Interface) geprüft. – Das Skript bricht ohne `wg` ab,
    auf einem Admin-Rechner ohne root lässt sich das Paket aber nicht nachinstallieren. NetworkManager
    kann WireGuard selbst; nur die Schlüssel brauchen `wg`. Ersatz mit OpenSSL: privater Schlüssel =
    die letzten 32 Byte von `openssl genpkey -algorithm X25519 -outform DER`, Base64; öffentlicher
    über den PKCS#8-Kopf `302e020100300506032b656e04220420` + privater Schlüssel →
    `openssl pkey -inform DER -pubout -outform DER`, letzte 32 Byte. Am Standort so gemacht und
    gegen RouterOS geprüft (Handshake). Umsetzen: `genkey` und `connect` fallen auf OpenSSL zurück,
    wenn `wg` fehlt; `--keepalive` mit VRRP als Standard 25. *Nachtrag Code-Review 2026-10-20:* `connect`
    braucht `wg` gar nicht (nur `nmcli`), die Prüfung am Anfang verlangte es trotzdem – jetzt prüft das
    Skript `wg` nur noch bei `genkey`; `--keepalive` ist schon seit dem ersten Stand Standard 25. Offen
    bleibt nur der OpenSSL-Weg in `genkey`.
58. **Schaltbare SSID ohne Unterbrechung der übrigen** (entschieden 2026-10-17) – *(a) umgesetzt 2026-10-20
    (D90), seit 2026-10-21 an einem Standort ausgerollt, Test beim ersten Schalten offen:* Provisioning mit
    `create-enabled`, die Skripte schalten nur die
    Interfaces der SSID; Umstieg und Rückweg im Admin-Guide 6.8. Auf Hardware klären: Startet das Abschalten
    eines virtuellen AP das Radio neu? Was macht erneutes Provisionieren bei vorhandenen festen Interfaces
    (neue SSID in `wifi.rsc`, geänderter Pin)? Aufräumen der festen Interfaces eines abgebauten AP (bisher von
    Hand, Admin-Guide 7.4); bleiben beim Abschalten von `capsmanRadios` feste Interfaces der eigenen Radios
    stehen? Zusammenspiel mit `slaves-static` (D54). (b) bleibt der Rückfall. – Ausgangslage: `cfm-ssid-<key>-on/-off`
    (D64) ändern die Provisioning-Regeln und provisionieren alle Radios neu; das baut je Radio Master und
    alle virtuellen APs neu auf, alle SSIDs aller APs sind gleichzeitig ~3 s weg. Zwei Ansätze, in dieser
    Reihenfolge: (a) **statische Interfaces** – Provisioning mit `action=create-enabled` statt
    `create-dynamic-enabled`; feste Interfaces auf dem CAPsMAN lassen sich einzeln ab-/anschalten
    (dynamische nicht: „can not change dynamic interface“). Auf Hardware prüfen (CHR hat keine Radios):
    Betrifft das Abschalten nur den virtuellen AP, oder startet RouterOS das Radio trotzdem neu? Dazu
    klären: Aufräumen fester Interfaces, wenn ein AP verschwindet; Namen (`name-format`) und die Zuordnung in
    Home Assistant; Zusammenspiel mit `slaves-static` (D54). (b) Falls (a) nichts bringt: **nacheinander
    provisionieren** – je AP `/interface/wifi/radio/provision` mit einigen Sekunden Abstand, damit nie alle
    APs gleichzeitig dunkel sind und Clients zu einem Nachbarn wechseln können; die Unterbrechung je AP bleibt.
59. ~~**NTP der Router**~~ (Code-Review 2026-10-20) – *erledigt am selben Tag (D88):* `wan.ntp` (Text oder
    Liste), sonst `wan.dns`, sonst `0/1.pool.ntp.org`; mit `wan.dhcp` zusätzlich `use-peer-ntp`. Labor:
    `e2e.sh` Schritt 9, `e2e-vrrp.sh` Schritt 4. – Die Rolle `router` stellt ihren eigenen NTP-Client auf den
    DNS-Server aus dem Hostfile-Eintrag `wan` (`dns`), ohne ihn (auch bei `wan.dhcp`) fest auf
    `0.de.pool.ntp.org,1.de.pool.ntp.org`; `ntp` aus `global.rsc` und aus dem Hostfile gilt nur für
    Nicht-Router (Admin-Guide, Kapitel 4). Das setzt voraus, dass der DNS-Server auch NTP anbietet (ein
    DSL- oder Kabel-Router meist ja, ein öffentlicher DNS wie 1.1.1.1 nicht), und der Pool ist auf
    Deutschland festgelegt. Vorschlag: optional `"ntp"` im Eintrag `wan` (oder ein Schlüssel in
    `global.rsc`), sonst wie bisher; als Rückfall `pool.ntp.org` ohne Länderkennung; bei `wan.dhcp`
    `use-peer-ntp=yes` erwägen. Offen: wo der Schlüssel hingehört (Entscheidung).
60. ~~**`rsc-check.py` auf ein Overlay mit Exporten**~~ (Code-Review 2026-10-20) – *erledigt am selben Tag:*
    In einem als Verzeichnis übergebenen Overlay prüft es die Größe nur für Dateien, die `upload-seed.sh`
    hochlädt; Test in `tools/rsc-check-test.py`. – Die Regel `dateigroesse`
    (60 KB) gilt für jede `.rsc`-Datei. Liegen im Overlay Exporte als Notiz (z.B. `ist/<gerät>.rsc`, die
    `upload-seed.sh` gar nicht hochlädt), meldet `tools/rsc-check.py site-…/` sie als Fehler; die Vorlage der
    `STAND.md` (`new-site.py`) verlangt aber „ohne Fund“. Vorschlag: außerhalb von `cfm/work/` die Größe nur
    für Dateien prüfen, die `upload-seed.sh` hochlädt (oberste Ebene, `hosts/`, `roles/`, `lib/`, `meta/`),
    sonst höchstens als Hinweis.
61. **Trennschwelle per access-list, auch mit FT** (Wunsch des Nutzers, 2026-10-22; Anlass: Steering trennt
    FT-Clients nicht, 39/D55) – Befund an einem Standort (18./19.10.): `steer` mit `kick` trennte einen
    Client ohne FT zuverlässig nach `after` + `kick`, ein Handy mit `ft-wpa3-psk` nie (18 min bei −88…−93 dBm);
    `minSignal` (access-list `reject`) griff bei einem Wechsel per FT nicht (Wechsel mit −83 bei Schwelle −80).
    Laut RouterOS-Doku prüft die access-list nur Verbindungen **laufend**, die eine Regel **angenommen** hat
    (`signal-range`, `time`), und trennt sie, wenn das Signal länger als `allow-signal-out-of-range` außerhalb
    liegt (Standard `0s`, `always` = nur bei der Anmeldung). Die Regel `wacl:min` lehnt nur ab – eine
    angenommene Verbindung unter der Schwelle trennt sie also nie. `interface` nimmt auch eine Interface-Liste.
    Idee: je Band (oder AP) eine `accept`-Regel mit `signal-range=<Schwelle>..0` und
    `allow-signal-out-of-range=<Zeit>` vor `wacl:min`, dazu `reject` darunter; `interface` = eine Liste der
    WLAN-Interfaces des Bands. Seit D90 sind die Interfaces fest – der Grund aus D55 („Interfaces der CAPs
    entstehen dynamisch“) fällt weg, solange alle Interfaces fest sind. **Offen, vor dem Bauen von Hand an
    der Hardware prüfen:** (1) Wird eine per FT übernommene Verbindung überhaupt einer Regel zugeordnet und
    laufend geprüft? Der Befund oben spricht eher dagegen; dann bringt der Weg für FT-Clients nichts.
    (2) Wirkt eine Regel mit `interface=<Liste>` am CAPsMAN auf die Interfaces der CAPs (`wacl:min` am
    CAPsMAN wirkt dort)? (3) Trennt sie hart – ohne vorherige 802.11v-Vorschläge, auch wenn kein besserer AP
    da ist (Randbereiche, siehe 39). Vorab-Test ohne Framework am CAPsMAN, z.B.
    `/interface/wifi/access-list add interface=<AP>-6g signal-range=-72..0 allow-signal-out-of-range=20s
    action=accept comment=test place-before=0`, Client mit FT dorthin wechseln lassen und entfernen. Im Labor
    nicht prüfbar (CHR ohne Radios).
