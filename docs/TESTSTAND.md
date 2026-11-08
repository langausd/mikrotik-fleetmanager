# Teststand

Was im CHR-Labor und auf echter Hardware geprüft ist und was auf Hardware noch offen ist (Stand 2026-11-08).
Wie die Labortests laufen: [Admin-Guide Kapitel 12](admin-guide.md#12-testlabor) und
[tools/chr-lab/README.md](../tools/chr-lab/README.md). Nummern wie DW1.5 verweisen auf
[DECISIONS.md](DECISIONS.md), Nummern wie „TODO 58“ auf [TODO.md](TODO.md), Eigenheiten von RouterOS stehen in
[ROUTEROS-EIGENHEITEN.md](ROUTEROS-EIGENHEITEN.md).

Neue Ergebnisse kommen hierher: ein Laborlauf unter [Läufe je RouterOS-Version](#läufe-je-routeros-version), ein
Hardware-Ergebnis mit Datum unter [Bestanden](#bestanden), was noch fehlt unter [Offen auf Hardware](#offen-auf-hardware).

## Überblick

* **Labor:** Mit RouterOS 7.25.1 (zuvor 7.25, 7.24.2, 7.24.5, 7.25rc1 und 7.25rc2, der Gesamttest auch mit 7.26beta1) laufen
  alle vier Tests fehlerfrei – zuletzt am 2026-11-08 der Gesamttest (461 Prüfungen), drei VRRP-Router (137),
  LACP/MLAG/isolierte VLANs (72) und das Onboarding mit Werks-IP (14), im CAPs-Modus (15) und hinter einem nicht
  verwalteten Switch (18). Funkteile lassen sich auf CHR nicht testen.
* **Hardware:** cfm läuft an zwei Standorten mit 13 Geräten, alle mit RouterOS 7.25; an einem davon routen seit dem
  17.10. vier Geräte alle VLANs per VRRP hinter einer Fritz!Box. Die gefundenen Fehler sind behoben
  ([ERLEDIGT.md](ERLEDIGT.md#behobene-fehler)) oder stehen in [TODO.md](TODO.md#bekannte-fehler) unter „Bekannte Fehler“.
* **Noch nicht auf Hardware:** Beförderung und Rekey mit dem Backup-Manager (Spiegel und Ausfallmeldung am
  2026-11-08 bestanden), Onboarding gegen Werks-Configs von Routern
  und CRS-Switches, die Fixes vom 2026-11-04 (TODO 74: normale Passphrase bei PPSK, weitere SSIDs im lokalen
  Fallback, `cfm-iso` nach `slaves-static`), LACP-Bonds, MLAG und isolierte VLANs an Switches (DP2.1, DP2.2, DP3.1), dazu Einzelfragen unter [Offen auf Hardware](#offen-auf-hardware). Plane für jeden weiteren
  Gerätetyp einen Pilotbetrieb mit einem Testgerät ein. Neu seit 2026-11-05: `$cfmSniff mirror=` (DU2.3.1), Pakete
  auf dem Backup (TODO 7); der umschaltbare Port (DP1.4) nur an einem hAP be³ Media, nicht an einem CRS.

## Labor (CHR)

### Was die Tests abdecken

* `e2e.sh` (Gesamttest): Manager-Bootstrap mit Reset, Aufnahme, Firewall, Probelauf, `$cfmShow`/`$cfmDiff`,
  Prüfung, Rollback und Watchdog-Rollback, Backup-Manager, Schlüsselwechsel, Archiv, Router-Rolle mit festen
  Leases, DNS-Namen, NTP-Umleitung und Bandbreitenlimit, DNS der Router samt Selbstbedienung, Netzplan, PPSK
  (mit normaler Passphrase und `ppskOnly`), WLAN-Scan, CAPsMAN-Rolle und -Umzug, AP-Rolle mit `slaves-static`
  (zweiter Apply, Abgleich von `cfm-iso`), Mitschnitt per `$cfmSniff`, Bestandsgeräte, Admin-Keys je User, Benachrichtigungen, Gerätesuche,
  SNMPv3, Syslog-Inhalt, Feature-Module, ein RouterOS-Downgrade auf 7.24.1 und das eingebaute Update von einem
  Spiegel.
* `e2e-onboard.sh`: automatisches Onboarding mit Werks-IP (14 Prüfungen), im CAPs-Modus per DHCP (15) und hinter
  einem nicht verwalteten Switch (18).
* `e2e-vrrp.sh`: drei VRRP-Router hinter einem Internet-Router im LAN (5 VMs) – VIPs und DHCP nur auf dem Master,
  DHCP und DNS im LAN, das zugleich WAN ist, Zonen-Policy mit fester NAT-Adresse, `mgmtExtra`, WireGuard über die
  VIP, `asymRouting`, Ausfall und Rückkehr des Masters, kurzer Master-Ausflug eines Backups, Ausfall zweier Router.
* `e2e-mlag.sh`: LACP-Bonds, MLAG-Paar und isolierte VLANs (5 VMs, e1000-Karten).

### Läufe je RouterOS-Version

* **7.24.2:** Gesamttest grün (2026-10-02, 169).
* **7.24.5:** alle Skripte grün – 2026-10-02 `e2e.sh` 169, Onboarding 14/15/18, `e2e-vrrp.sh` 79; 2026-10-20 (Code-
  Review) `e2e.sh` 323, `e2e-vrrp.sh` 118, Onboarding 14/15/18, `e2e-mlag.sh` 72; 2026-10-20 abends `e2e.sh` 328,
  `e2e-vrrp.sh` 120, Onboarding 14/15/18, `e2e-mlag.sh` 72.
* **7.25rc1 (2026-10-12):** alle Skripte grün – `e2e.sh` 292, Onboarding 14/15/18, `e2e-vrrp.sh` 79. Abends mit
  DP2.1, DP2.2 und DP3.1: `e2e.sh` 294, `e2e-mlag.sh` grün. Befunde und Changelog-Punkte: TODO 48.
* **7.25rc2 (2026-10-13):** alle Skripte grün – `e2e.sh` 298 (mit DU3.2), Onboarding 14/15/18, `e2e-vrrp.sh` 79,
  `e2e-mlag.sh` 72; kein neuer Befund zu cfm.
* **7.25rc2 (2026-10-17, Stand DN1.2):** alle Skripte grün – `e2e.sh` 315, Onboarding 14/15/18, `e2e-vrrp.sh` 79,
  `e2e-mlag.sh` 72. Eine Forumsmeldung aus der Beta-Zeit (Skripte über ~16 kB nach einem Neustart ungültig) ließ
  sich nicht nachstellen: ein Skript mit 45 KB bleibt nach dem Neustart gültig und läuft per Scheduler `startup`.
* **7.25 stable (2026-10-25, erschienen 2026-10-22, Stand `47646d9`):** alle Skripte grün – `e2e.sh` 338 (ein ✘:
  MNDP-Prüfung in Schritt 14, ein bekannter Timing-Fehler, inzwischen behoben, zwei Labore parallel; von Hand
  nachgestellt: erstes Paket nach knapp 20 s, still verworfen), `e2e-vrrp.sh` 120, `e2e-mlag.sh` 72, Onboarding
  14/15/18. 7.25 meldet die Version als `7.25` ohne Kanal-Zusatz; der Agent hängt den Kanal an, `$cfmUpgrade`
  erkennt das Update (Schritt 13, DV1.6).
* **7.25, mit den folgenden Ausbauten:** `e2e.sh` 341 (2026-10-26, DW4.3), 347 und 354 (2026-10-27, DW2.6, DU4.2),
  359 (2026-10-28, DR2.7), 373 (2026-10-29, DU4.3), 374 und `e2e-vrrp.sh` 137 (2026-10-31, DR3.2), 402 (2026-10-31,
  DN3.1/DN3.2), 405 (2026-11-02, DU3.4), zuletzt 410 mit `e2e-vrrp.sh` 137, `e2e-mlag.sh` 72 und Onboarding 14
  (2026-11-02, DG4.6) – alles grün. 2026-11-04 (TODO 73, WLAN-Prüfung in `mgr-checkw.rsc`): 409 von 410, ein ✘
  in der Primary-Überwachung des Backups (Entwarnung „Tick“ blieb aus; vermutlich überschneidet sich der echte Tick
  von cm2 mit dem Test, Code unverändert, bisher nie aufgetreten). Übergang von Hand nachgestellt: ohne installiertes
  `cfm-mgr-checkw` lädt `$cfmCheck` die Datei aus `work/`, ein WLAN-Fehler kommt an, fehlt die Datei: Fehler statt
  ungeprüft.
  2026-11-05 (Fixes aus dem Hardware-Test: DW1.8.1, DW2.2.1, DP3.1.1, `$cfmSniff` DU2.3, Backup-Test ohne echten
  Tick von cm2): `e2e-vrrp.sh` 137, `e2e-mlag.sh` 72, Onboarding 14/15/18 grün; `e2e.sh` 430 von 431 – das ✘ lag
  am Test (startete den Agent für den Abgleich von `cfm-iso` per SSH als admin – so holt er kein Manifest und bricht
  vorher ab; jetzt per `$cfmPush`), danach 431 von 431.
  2026-11-05 abends, **RouterOS 7.25.1** (Ausbauten DP1.4, DU2.3.1, TODO 7 und 64, Laden per `:parse`): erster Lauf
  `e2e.sh` 445 von 448 (Paketspiegel: zwei Spiegel-Läufe zugleich, behoben mit einer Sperre; zweiter Apply nach
  `slaves-static` stellt noch einmal um, TODO „Bekannte Fehler“), `e2e-vrrp.sh` 137, `e2e-mlag.sh` 72, Onboarding
  14/15/18. Abschlusslauf 2026-11-05/06 mit Sperre und `:parse`: `e2e-vrrp.sh` 137, `e2e-mlag.sh` 72, Onboarding
  14/15/18 grün, `e2e.sh` 445 von 447 (Paketspiegel und Dock-Port grün; ✘ doppelte Notify-Meldungen – Tick von Hand
  neben dem Scheduler-Tick, behoben mit der Sperre `cfmNotBusy`, DU4.1 – und ppskOnly-Probelauf – Agent noch
  beschäftigt, Test wartet jetzt); Nachlauf `e2e.sh` 447 von 447.
  2026-11-06, Taster-Fix und rsc-check im Upload: `e2e.sh` 446 von 447 und 445 von 447 (je ein bis zwei bekannte
  Wackler: MNDP mit Quelle 0.0.0.0, zweiter Apply nach `slaves-static` – TODO „Bekannte Fehler“). Abends mit dem
  HA-Port-Schalter (DP1.4.1): erster Lauf 454 von 456 (cm2 holte v19 nicht – der Secret-Push lud Hostfiles und setzte
  damit `cfmHost` auf dem Manager; behoben, lädt keine mehr), danach **456 von 456**.
  2026-11-08 mit TODO 77 (`host=` ohne Groß-/Kleinschreibung, DM1.3): `e2e.sh` **461 von 461**, `e2e-vrrp.sh` 137,
  `e2e-mlag.sh` 72, Onboarding 14/15/18 – alle grün.
* **7.26beta1 (Kanal development, 2026-10-12):** `e2e.sh` grün (292); Changelog-Punkte: TODO 49.

## Hardware

### Geräte und Standorte

* **Erster Standort (Pilot ab 2026-09-17):** ein CRS418 als Router, Primary-Manager und CAPsMAN mit eigenen Radios,
  zwei hAP ax² als APs – Haupt-, Legacy-, Gast- und Test-SSID, Gast-VLAN mit Bandbreitenlimit, WireGuard.
* **Zweiter Standort (ab 2026-09-20/26):** zehn Geräte – der Manager als CHR in einer VM (PVE, Karte je VLAN; dabei
  kamen DP1.2, die Namensprüfung im Bootstrap, der Host-Key-Typ nach Reset und der Schutz des Inventars dazu),
  ein CRS328 als Core-Switch (übernommen ohne Reset, DO2.1), ein CRS310 als Switch der Server, ein hAP be³ als
  CAPsMAN mit eigenen Radios, APs (hAP be³, hAP ax³, cAP ax) mit lokalem Fallback, hEX und L009 als Switches. Seit
  dem 17.10. routen vier Geräte (hAP be³, CHR, CRS310, CRS328) alle VLANs per VRRP hinter einer Fritz!Box als
  Internet-Gateway, mit DHCP, festen Leases, DNS-Namen, DNS-Resolver und WireGuard-Zugang; LibreNMS und Graylog
  lesen mit.
* Alle Geräte laufen mit RouterOS 7.25 (vorher seit 7.23.1).

### Läufe mit RouterOS 7.25

* **Zweiter Standort (2026-10-25/26, 10 Geräte: hAP ax², hAP ax³, hAP be³ Media, cAP ax, CRS, hEX, CHR):**
  `$cfmUpgrade` je Gerät ohne Fehler (16-MB-hEX per `via=mirror`, ein CRS mit wenig Flash per `via=internet`),
  Firmware-Angleich mit zweitem Neustart wie erwartet. Befunde: Die eigenen Radios des CAPsMAN zeigen ohne
  eingebuchten Client `running=false`, ihr Bridge-Port `inactive` – Beacons gehen trotzdem raus, ein Client bucht
  sofort ein (CAPs zeigen `running` auch ohne Client). PoE-APs laufen nach dem Neustart des PoE-Gebers etwa 5 min mit
  alter Uhrzeit (NTP `waiting`), `$cfmStatus` zeigt solange falsche „ZULETZT“-Werte. **Kabel-Ports des hAP be³
  Media** (packet-loss-Fix): zwei Ports gegen einen Switch (2,5 Gbit/s, je eine VRF mit DHCP-Client), Ping, Zähler,
  Link-Wechsel und Neustart bestanden, Langzeit 6 h ohne Verlust, ohne FCS-Fehler und Link-Abbruch (ein FCS-Fehler
  nur im Neustartfenster des Switches).
* **Erster Standort (2026-10-27/28, 3 Geräte: CRS418 als Router/Manager/CAPsMAN, 2× hAP ax²):** `$cfmUpgrade` je
  Gerät, Firmware angeglichen. Die Neustarts brachten die CAP-Radios ohne `cfm-reprov` auf feste Interfaces
  (DW4.2/DW4.3). Lade-Lesezeichen, Client- und FT-Test (auch FT-SAE in einer WPA3-SSID) bestanden.

### Bestanden

Älteste zuerst; wo ein Teil offen bleibt, steht er unter [Offen auf Hardware](#offen-auf-hardware).

* **Manager-Bootstrap mit Reset** (`clean="yes"`, DO3.1) – 2026-09-20 auf einem CHR in PVE (Stufen 2 und 3 samt
  Übergabe per SFTP-`.auto.rsc`).
* **WLAN mit CAPsMAN** – zwei hAP ax² mit CAPsMAN, SSID-VLAN über den lokalen Datapath (DW1.3), WPA2/WPA3 + FT und
  Clients mit `ft-wpa3-psk` seit 2026-09-24, Roaming zwischen den APs (2026-09-25).
* **Onboarding eines hAP per PoE an ether1 im CAPs-Modus** – 2026-09-26 mit zwei APs (Neustart per
  `/interface/ethernet/poe/power-cycle` am verwalteten Switch, Lease im Onboarding-VLAN, Probe, Bootstrap, Enroll).
* **Umzug der Rolle `capsman`** (DW1.5) – 2026-09-27 von einer CHR auf einen hAP be³, vier APs folgten samt
  Zertifikatswechsel. Lokaler Fallback der Haupt-SSID (DW1.6) bei einem Abriss des CAPsMAN (cAP ax).
* **`$cfmShow objects=yes`** auf einem Manager mit vielen Skripten – 2026-10-03: CHR als Manager mit acht Modulen,
  109 Soll-Objekte, 9,5 KB – weit unter der Kürzung.
* **Kanal-Scan über den CAPsMAN** (DW3.3) – 2026-10-03, mit Pin-Vorschlag; mit den eigenen Radios eines hAP be³ als
  CAPsMAN (DW3.4) 2026-10-04.
* **Eingebautes Update** (DV1.5) – 2026-10-03: hEX RB750Gr3 von 7.23.1 auf 7.24.5 über `via=mirror` (Apache als
  Spiegel, `--export`), 2,4 MB frei, vier Pakete, gut 4 min samt Neustart; `mode` blieb danach auf `http`, der Agent
  prüft den Rückbau seitdem in einem späteren Lauf nach. Per `via=internet` 2026-10-25 auf einem CRS mit wenig Flash
  (7.25).
* **Admin-Keys je User** (DS3.3) – 2026-10-04 ohne Änderung an den vorhandenen Keys übernommen (gleiche
  Fingerprints).
* **Lesezeichen cfm-WLAN** (DU2.2) mit echten Clients – 2026-10-14 (zwei Standorte mit vier bzw. zwei APs):
  Zuordnung, Signal, Wechsel live und aus dem Log des CAPsMAN, Uhrzeit stimmt mit `cache: 'no-store'`. Wechsel
  erscheinen in den Ereignissen doppelt (live und „Log“).
* **Gerätesuche `$cfmFind`** (DU1.4) – 2026-10-16 an einem Standort: Suche nach SSID mit Band, Signal und Rate,
  Suche an einem Port (Fritz!Box mit 3 MACs), 9 Geräte in 3 s; danach den Ort eigener Geräte per LLDP
  korrigiert (sie standen an der MGMT-Karte des virtualisierten Managers).
* **VRRP mit vier Routern** – seit 2026-10-17 an einem Standort (hAP be³, CHR, CRS310, CRS328) mit DHCP nur am Master,
  WireGuard mit gemeinsamem Schlüssel (DR4.2) und `mgmtExtra` bis ins MGMT-VLAN (DR2.6); Ausfalltests per Neustart
  2026-10-18 (dabei gefunden: DR1.5); LAN-DHCP der Router neben der Fritz!Box
  (DN1.2, DR3.1) seit 2026-10-18.
* **Steering** (DW2.4) – 5 und 6 GHz mit Schwelle und Kick ab 2026-10-17; der Kick trennt Clients mit FT nicht, daher
  die **Trennschwelle je Band** (DW2.5): ab 2026-10-24 ausgerollt, Auswertung 2026-10-25 „wirkt wie gedacht“
  (Hysterese ohne Pendeln, je Trennung ~3 s ohne Verbindung).
* **Schaltbare Gast-SSID per Home Assistant** (DW4.1, seit 2026-10-21 mit festen Interfaces, DW4.2) – Grundzustand
  aus, Einschalten aus HA, Auto-Aus nach 50 h (z.B. 2026-10-31 22:41).
* **Eigene Radios des CAPsMAN** (DW1.7) – Client-Test und FT zu den CAPs 2026-10-22 (CRS418 mit zwei Radios);
  2026-10-29 auf einem hAP be³ mit Haupt-, IoT- und Gast-SSID, je im richtigen VLAN, Wechsel weg per FT.
* **NTP-Umleitung je VLAN** (DN2.2) – 2026-10-24 an einem Standort ausgerollt.
* **Lade-Lesezeichen „cfm“** (DT3.2) – 2026-10-26 in Firefox 153 ESR mit WebFig 7.25: Formular, falsches Passwort,
  Monitor auf dem CAPsMAN, Menü und Editor auf dem Manager, gemerkte Anmeldung (zweiter Standort); am ersten Standort
  2026-10-28.
* **Neuprovisionieren bei festen Interfaces** (DW4.3) – 2026-10-26: RouterOS legt sie neu an (gleiche Namen, neue
  Nummern, eingeschaltet); Erkennung veralteter CAP-Radios mit echten und verfälschten Regeln, `cfm-reprov` für vier
  CAPs.
* **„Erledigt“-Meldung für neue RouterOS-Versionen** (DU4.2) – 2026-10-27: Der erste Tick nach dem Update schickte
  `off` für `ros:7.25` („auf allen Geräten“) an Home Assistant.
* **Feste Leases und DNS-Namen** (DN1.1) – Namen an einem Standort mit drei VRRP-Routern seit 2026-10-28; neue
  Leases 2026-11-01 auf allen drei sofort auflösbar.
* **Bandbreitenlimit** (DR2.7) – Grundtest 2026-10-28/29 (CRS418, ein Client: 19,8 Mbit/s bei `limitClient` 20M,
  Queue bremst in beiden Richtungen, keine Gast-Verbindung im Fasttrack). 2026-10-29 am zweiten Standort (vier
  Router): Gast vorher ~300/30, mit `limit` 100M/20M und `limitClient` 50M/10M konsistent 51/11, CPU des Masters
  (hAP be³) höchstens 14 %; der Umbau des Firewall-Blocks kostete den CRS328 einmalig ~70 s bei 99 % CPU.
* **SNMPv3** (DU4.3) gegen LibreNMS – 2026-10-30 (10 Geräte, RouterOS 7.25, LibreNMS 26.6.1: authPriv SHA256/AES über
  die MGMT-Adresse, sysLocation aus dem Hostfile mit Umlauten, danach Probelauf 0/0/0). **Syslog im RFC-Format**
  2026-11-01 über Graylog 7.0: Facility `daemon`, Schwere aus dem Topic (warning 4, info 6, error 3), Zeit Ortszeit
  ohne Zone (Input-Zeitzone setzen), `source` = Identity; LibreNMS ordnet über den sysName zu (Integrationstest mit
  einer Warnung je Gerät). Befund: Nicht-ASCII-Bytes kommen als `?` an (DU3.4).
* **VIP als Gateway trotz Internet-Router im Netz** (DR3.2, `asymRouting`) – 2026-10-31 auf vier Routern: Ein Server
  mit der VIP als Gateway erreicht das Internet per HTTPS, DHCP-Clients behalten den Internet-Router als Gateway.
* **DNS der Router** (DN3.1) – 2026-10-31 auf vier Routern: Adliste mit 76 750 Namen (Cache ~6 MB, auch auf einem
  Router mit 256 MB genug frei), Sperre, Ausnahmen und Weiterleitung je Domain, Abfrage-Log nennt den Client.
  **DNS-Selbstbedienung** (DN3.2) am selben Tag: Freischaltung aus dem Client-VLAN nach 3 s wirksam, dauerhaft
  machen und löschen als Admin, 20 000 Log-Zeilen in 2,3 s gelesen. Abfrage-Log über Syslog an Graylog seit
  2026-11-01.
* **Bridge nach einem Rollback mit Neustart** – Datenpunkt 2026-11-01: hAP be³ (VRRP-Master, CAPsMAN, 7.25) ohne
  die Meldung „Bridge-Ports werden neu gestartet“, CAPs und Clients nach ~1 min wieder da.
* **Was über den Syslog geht** (DU3.4) – 2026-11-02: Ab dem zweiten Release mit dem neuen Manager-Code schickt der
  Manager statt ~1250 nur ~100 Zeilen je Release, cfm-Meldungen kommen ohne `?` an.
* **Feature-Module** (DG4.6) – 2026-11-02 am ersten Standort: Upload nur der genutzten Module, Release ringweise und
  ein zweites Release mit dem neuen Manager-Code, alle Geräte ohne Rollback, auf dem Manager genau die erwarteten
  Module.
* **Fremdgerät per MAC in ein anderes VLAN** (DW2.6) – 2026-11-05 am zweiten Standort (hAP be³ als CAPsMAN, 7.25):
  Laptop mit fester MAC an der Haupt-SSID (WPA3, an einem CAP auf 5 GHz) per MAC-Regel der Access-List in VLAN
  175, feste Lease, Internet ja, LAN nein. Der CAPsMAN gibt `vlan-id` aus der Access-List an die CAPs weiter.
* **WLAN-Hardware-Test** – 2026-11-04 am ersten Standort (CRS418 als CAPsMAN, zwei hAP ax², 7.25):
  **Gast-Limit** (DR2.7) mit zwei Clients je ≈ 20/5 Mbit/s; Gegenprobe ohne die Fasttrack-Ausnahmen 46/6 mit
  Verbindungen im Fasttrack – die Ausnahmen sind nötig. **Schaltbare SSID** (DW4.1/DW4.2): Grundzustand aus,
  Einschalten mit Ablauf, Aus/Ein startet das Radio nicht neu, andere SSIDs laufen ohne Unterbrechung. **PPSK**
  (DW2.2): Eintrag mit eigener Passphrase landet im VLAN des Eintrags, auch mit FT. Drei Fehler gefunden (Fallback,
  normale Passphrase bei PPSK, `cfm-iso` nach `slaves-static`), Fixes DW1.8.1, DW2.2.1, DP3.1.1 (TODO 74).
* **Backup-Manager** (`manager-backup`, DM3.1/DM3.2/DS2.5, DU4.1) – 2026-11-08 am ersten Standort (hAP be³ Media
  als `switch,ap,manager-backup`, 7.25.1, v102–v104): Aufnahme ohne Rollback, Spiegel im Takt (live, archive, meta),
  alle `cfmd-*` gesperrt, `$cfmPlan` des Geräts ohne Änderung. Ausfalltest: Primary (CHR) gestoppt, die Geräte
  liefen mit ihrem Stand weiter und zogen nichts vom Backup; nach 33 min ohne Spiegel kam `primary/on` am
  Webhook an, nach dem Neustart des Primary und dem nächsten Spiegel (v104) `primary/off`. Befund: Die Geräte
  versuchen in der Zeit den Backup per SSH und scheitern an den gesperrten Usern – 65 `login failure`
  (`system,error,critical`) in rund 25 min, auch im Syslog-Server; offen zur Entscheidung. Nach dem Neustart des
  CHR fehlten die Manager-Funktionen bis zum ersten Takt bzw. `/system script run cfm-mgr`.
* **Umschaltbarer Port aus Home Assistant** (DP1.4.1, TODO 76) – 2026-11-07 am ersten Standort (hAP be³ Media,
  7.25.1, v102): Release ohne Rollback (Gruppe `cfm-api`, User, Regelblock `capi`, Dienst `api` nur für HA; auf den
  vier Routern die Forward-Freigabe in die MGMT-Zone); das API-Passwort kam mit dem Secret-Push, nachdem der Manager
  selbst die neue Version hatte. HA schaltet per `cfm_port.py` in beide Richtungen, jeder Wechsel kommt als `ev`
  `port` am Webhook an. Ein Container von Hand auf dem Gerät (eigene Bridge, veth, NAT) blieb unberührt.


## Offen auf Hardware

* **Onboarding-Push gegen echte Werks-Configs:** Router (ether1 = WAN mit Firewall), CRS-Switches, Geräte mit
  `flash/`-Verzeichnis; Aufkleber-Passwort (beim einzigen Versuch, einem hAP ax³ mit RouterOS 7.8, passte es nicht –
  das Gerät hatte ein leeres Passwort, der Fallback griff). Im CAPs-Modus das LED-Verhalten je Modell.
* **Manager-Bootstrap mit Reset** auf einem Gerät mit `flash/`-Verzeichnis.
* **Bridge nach Neustart/Rollback:** Auf CHR nimmt eine Bridge mit VLAN-Filtering nach dem Boot sporadisch keine
  getaggten Frames an (cfm startet die Ports dann neu). Betrifft das auch Geräte mit Switch-Chip? Auf Hardware
  prüfen, ob die Log-Meldung „Bridge-Ports werden neu gestartet“ auftritt (bisher ein Datenpunkt ohne, siehe oben).
* **PPSK** (DW2.2): Die VLANs aus den Einträgen gelten, auch mit FT (2026-11-04). Offen: die normale Passphrase als
  Gruppeneintrag (DW2.2.1, Fix 2026-11-05, nur Labor), Roaming mit PPSK zwischen CAPs, `ppskOnly`.
* **Backup-Manager** (`manager-backup`, DM3.1/DM3.2/DS2.5) – bisher nur im Labor (`e2e.sh`: cm2, auch als
  `manager-backup,ap`). *2026-11-08 an einem Standort bestanden (siehe oben):* Spiegel, gesperrte Geräte-User,
  `primary/on`/`off` am Webhook, Geräte ziehen nicht vom Backup. Offen: Platz auf dem Backup über längere Zeit,
  zweiphasiger Rekey mit zwei echten Managern, die `login failure` der Geräte während eines Ausfalls (Befund);
  `$cfmPromoteManager` nur im Ernstfall.
* **Umschaltbarer Port** (DP1.4): Skripte und Taster an einem echten Gerät (Dockingstation), Bridge-Port mit
  Switch-Chip (`hw`), DHCP des Geräts am Port nach dem Umschalten. *2026-11-06 an einem Standort (hAP be³ Media, v100):
  Umschalten per Skript bestanden – Link-Abriss, Firmen-Laptop am Dock mit Pool-Adresse in VLAN 175 (MAC des Docks),
  Internet ja, LAN nein. Reset-Taster: startet Skripte erst mit Code in `on-event` und gesetzter `hold-time` (von Hand
  geprüft, Rolle angepasst). Abends, Release v101 mit dem Fix: Die Rolle ersetzt eine abweichende Belegung durch
  ihre eigene (auf Hardware bestätigt). Umschalten per Taster in beide Richtungen bestanden, Admin-Laptop am Dock:
  normal 177 mit `dock.42`, alt Pool-Adresse in 175, der Laptop folgt jedem Wechsel sofort per DHCP. Der
  Reset-Taster ist mechanisch unzuverlässig (normaler Druck 0 von 5, kräftiger 6 von 8, ohne Rückmeldung) – Schalten
  aus Home Assistant folgt (TODO 76). Bei jedem Umschalten ein `cfm-drop` für den DHCP-Discover des Geräts am Port
  (TODO, Bekannte Fehler). Offen: Release im alt-Zustand (darf nicht zurückschalten), Bridge-Port mit `hw` an einem
  CRS, Meldung an den Webhook beim Tasterdruck (gleicher Skriptrumpf wie beim Schalten aus HA, das 2026-11-07
  bestanden hat, siehe oben).*
* **`$cfmSniff mirror=<Port>`** (DU2.3.1): Eigenschaftsnamen je Switch-Chip, CPU als Spiegelziel, CPU-Last, sieht
  der Sniffer die gespiegelten Frames (TODO 75).
* **Pakete auf dem Backup-Manager** (TODO 7): Spiegel offener Aufträge und Laden nach einer Beförderung.
* **Hook Manager → Git-Host** per `ssh-exec` (die Pull-Seite `cfm-git-sync` ist getestet).
* **Rolle `router` auf einem CRS mit L3-Hardware-Offloading** (DR1.2): Schaltet sie `l3-hw-offloading` ab, läuft
  VRRP danach, und gibt es beim Umschalten einen Aussetzer im gerouteten Verkehr?
* **Feste NAT-Adresse** (`wan@<Adresse>`, DR2.3) bei VRRP: Wandert die Adresse mit dem Master, und übernimmt der neue
  Master den ausgehenden Verkehr ohne Hand-Eingriff (bestehende Verbindungen brechen ab, conntrack wird nicht
  abgeglichen)?
* **Feste Leases** (DN1.1): Stört eine schon dynamisch vergebene Lease derselben MAC das Anlegen der festen? (Am
  Standort vorher von Hand gelöscht.)
* **Schaltbare SSID** (DW4.1/DW4.2, TODO 58): Aufräumen der festen Interfaces eines abgebauten AP; bleiben beim
  Abschalten von `capsmanRadios` feste Interfaces der eigenen Radios stehen? Zusammenspiel mit `slaves-static`
  (DW1.8).
* **Weitere SSIDs im lokalen Fallback** (DW1.8, TODO 40a) und der Client-Test im Fallback. 2026-11-04 hing keine
  lokale Kopie an (SSID der CAP-Slaves nur in `monitor`→`about`); Fix DW1.8.1 mit zweitem Apply vom Agent, nur Labor.
* **MLO mit FT** unter 7.25 („wifi - add fast transition support for MLD devices“, DW2.3, TODO 48).
* **Neue Master-SSID mit eigenen Radios** (DW1.11): Schaltet der Secret-Push den CAPsMAN ein, provisioniert der
  erzwungene Apply die eigenen Radios mit allen SSIDs? (CHR hat keine Radios.) Beim nächsten Release mit neuer
  Master-SSID: Ausfall nur für die Dauer des Applys plus höchstens 30 s, Log `meldet nach dem Push Secrets v0`.
* **Fremdgerät per MAC in ein anderes VLAN** (DW2.6): Roaming zwischen APs (2026-11-05 nur an einem CAP getestet,
  siehe Bestanden), Roaming mit FT.
* **MLAG** (DP2.2) auf CRS3xx: Offload im Switch-Chip, Ausfall eines Knotens (Strom aus, nicht nur Link), Umbau eines
  Uplinks, über den der Weg zum Manager läuft (Labor: ein 802.3ad-Port ohne Gegenstelle leitet weiter),
  `mlag-lacp-fallback` ab 7.25. Ebenso LACP-Bonds (DP2.1).
* **Isolierte VLANs** (DP3.1) an echten APs: Der CAPsMAN gibt `interface-list` nicht an die CAPs weiter, und
  Client-Isolation trennt nicht zwischen den Radios eines AP (beides 2026-11-04). Offen: der Abgleich von `cfm-iso`
  durch den Agent (DP3.1.1, nur Labor) und der Test mit zwei Gästen an verschiedenen Radios. Sieht der
  Bridge-Filter WLAN-Frames als `ip` oder als `vlan` (Labor: virtio `ip`, e1000 `vlan`; die MAC-Regeln greifen in
  beiden Fällen)? An Switches: `hw=no` an isolierten
  Access-Ports (Durchsatz über die CPU).
* **Bandbreitenlimit** (DR2.7): zwei Clients gleichzeitig (Aufteilung, Gesamtgrenze); Gegenprobe der Annahme aus der
  MikroTik-Doku – Ausnahme kurz abschalten, läuft der Gast dann ungebremst?; CPU-Last der CRS418 unter Volllast.
* **`asymRouting`** (DR3.2, TODO 67): Ausfall des Internet-Routers – bleiben die internen Wege?; VRRP-Wechsel;
  Portfreigabe auf einen Host mit Gateway VIP.
* **Feature-Module** (DG4.6, TODO 73): `cfm-dnsreq` auf einem Router mit `dns.rsc`.
