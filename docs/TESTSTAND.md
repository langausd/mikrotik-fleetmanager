# Teststand

Was im CHR-Labor und auf echter Hardware geprüft ist und was auf Hardware noch offen ist (Stand 2026-11-24).
Wie die Labortests laufen: [Admin-Guide Kapitel 12](admin-guide.md#12-testlabor) und
[tools/chr-lab/README.md](../tools/chr-lab/README.md). Nummern wie DW1.5 verweisen auf
[DECISIONS.md](DECISIONS.md), Nummern wie „TODO 58“ auf [TODO.md](TODO.md), Eigenheiten von RouterOS stehen in
[ROUTEROS-EIGENHEITEN.md](ROUTEROS-EIGENHEITEN.md).

Neue Ergebnisse kommen hierher: ein Laborlauf unter [Läufe je RouterOS-Version](#läufe-je-routeros-version), ein
Hardware-Ergebnis mit Datum unter [Bestanden](#bestanden), was noch fehlt unter [Offen auf Hardware](#offen-auf-hardware).

## Überblick

* **Labor:** Mit RouterOS 7.25.2 (2026-11-25, `e2e.sh`), 7.25.1 (zuvor 7.25, 7.24.2, 7.24.5, 7.25rc1 und 7.25rc2, der Gesamttest auch mit 7.26beta1) laufen
  alle vier Tests fehlerfrei – zuletzt am 2026-11-24 der Gesamttest (563 Prüfungen, ein bekannter Zeitfehler einzeln nachgestellt grün), am 2026-11-22 der Gesamttest (544), VRRP (184), MLAG (72) und das Onboarding (14/15/18), am 2026-11-21 der Gesamttest (542), am 2026-11-20 der Gesamttest (532), am 2026-11-16 der Gesamttest (485), am 2026-11-12 abends der Gesamttest (477) und drei VRRP-Router mit
  Standortkopplung (184, dazu `asymRouting` mit Netzen DR3.2.1 und Standort ohne `pubkey` DR4.3.1), am Vormittag
  desselben Tages der Gesamttest (477, zwei veraltete Erwartungen korrigiert) und VRRP (164); am 2026-11-08 der Gesamttest (469), VRRP (137),
  LACP/MLAG/isolierte VLANs (72) und das Onboarding mit Werks-IP (14), im CAPs-Modus (15) und hinter einem nicht
  verwalteten Switch (18). Funkteile lassen sich auf CHR nicht testen.
* **Hardware:** cfm läuft an zwei Standorten mit 13 Geräten, alle mit RouterOS 7.25; an einem davon routen seit dem
  17.10. vier Geräte alle VLANs per VRRP hinter einer Fritz!Box. Die gefundenen Fehler sind behoben
  ([ERLEDIGT.md](ERLEDIGT.md#behobene-fehler)) oder stehen in [TODO.md](TODO.md#bekannte-fehler) unter „Bekannte Fehler“.
* **Noch nicht auf Hardware:** Beförderung und Rekey mit dem Backup-Manager (Spiegel und Ausfallmeldung am
  2026-11-08 bestanden), Onboarding gegen Werks-Configs von Routern
  und CRS-Switches, zwei Gäste an verschiedenen APs und der zweite Standort für die WLAN-Fixes (Rest von TODO 74), `txPower`/Band aus je AP
  (DW3.7), LACP-Bonds, MLAG und isolierte VLANs an Switches (DP2.1, DP2.2, DP3.1), dazu Einzelfragen unter [Offen auf Hardware](#offen-auf-hardware). Plane für jeden weiteren
  Gerätetyp einen Pilotbetrieb mit einem Testgerät ein. Neu seit 2026-11-05: `$cfmSniff mirror=` (DU2.3.1), Pakete
  auf dem Backup (TODO 7); der umschaltbare Port (DP1.4) nur an einem hAP be³ Media, nicht an einem CRS.

## Labor (CHR)

### Was die Tests abdecken

* `e2e.sh` (Gesamttest): Manager-Bootstrap mit Reset, Aufnahme, Firewall, Probelauf, `$cfmShow`/`$cfmDiff`,
  Prüfung, Rollback und Watchdog-Rollback, Backup-Manager, Schlüsselwechsel, Archiv, Router-Rolle mit festen
  Leases, DNS-Namen, NTP-Umleitung und Bandbreitenlimit, DNS der Router samt Selbstbedienung, Netzplan, PPSK
  (mit normaler Passphrase und `ppskOnly`), WLAN-Scan, CAPsMAN-Rolle und -Umzug, AP-Rolle mit Fallback-Skript
  `cfm-fallback` (Abschalten von `slaves-static`, Abgleich von `cfm-iso` nach dem Verbinden und im Agent, DW1.12),
  Pool/`txPower`/Band aus je AP (DW3.7), Mitschnitt per `$cfmSniff`, Bestandsgeräte, Admin-Keys je User, Benachrichtigungen, Gerätesuche, NetBox-Abgleich (`$cfmNetbox`, Ethernet-Ports im Status, `tools/netbox-abgleich.py` gegen einen kleinen Plan, DT2.3),
  SNMPv3, Syslog-Inhalt, Feature-Module, ein RouterOS-Downgrade auf 7.24.1 und das eingebaute Update von einem
  Spiegel; seit 2026-11-11 Freigaben nach Domain und je Client (Schritt 14m, DR2.8/DR2.9); seit 2026-11-16 die Ausgabe
  von `$cfmCheck` (Schritt 7), `$cfmIsPrimary` ohne Daten auf dem Backup (Schritt 10) und Manager-Module aus `work/`
  samt Sperre nach einem Rollback (Schritt 17, DM1.4); seit 2026-11-23 Zertifikate (Schritt 14n, DS3.6): Schlüssel und CSR
  auf dem Gerät, Signer mit Test-CA über SSH als `cfm-cert` ohne Schreibrecht, `cfm-cert-pull`, Import mit Kette, Bindung
  an `www-ssl`/`api-ssl`, Erneuern mit neuem Schlüssel, Aufräumen.
* `tools/editor/cfm-qr-test.py`: QR-Encoder des WLAN-Schilds (gjs erzeugt, libzbar dekodiert), auch in der CI.
* `tools/editor/cfm-radios-test.py`: Kanalvorschlag in `wifi.rsc` übernehmen (node; nur das gescannte Band, Rückweg-Kommentar), auch in der CI.
* `e2e-onboard.sh`: automatisches Onboarding mit Werks-IP (14 Prüfungen), im CAPs-Modus per DHCP (15) und hinter
  einem nicht verwalteten Switch (18).
* `e2e-vrrp.sh`: drei VRRP-Router hinter einem Internet-Router im LAN (5 VMs) – VIPs und DHCP nur auf dem Master,
  DHCP und DNS im LAN, das zugleich WAN ist, Zonen-Policy mit fester NAT-Adresse, `mgmtExtra`, WireGuard über die
  VIP, `asymRouting`, Ausfall und Rückkehr des Masters, kurzer Master-Ausflug eines Backups, Ausfall zweier Router;
  seit 2026-11-11 Standortkopplung (Schritt 5d: Gegenstelle in einer VRF auf inet, Schlüssel, Tunnel am Master, Routen
  über die VIP, Policy, DNS-Weiterleitung; 6/7: Tunnel folgt dem Master; 12: Abbau) und DynDNS gegen `fake-ddns.py`
  (DR4.3, DR4.4).
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
  2026-11-08 abends mit DS2.5.1/DM2.1.1/DR2.5.1 (SSH-Sperre am Backup, `cfm-mgr-boot`, DHCP-Discover still):
  `e2e.sh` 467 von 469 – die zwei roten waren veraltete Erwartungen an den input-Block (eine Regel mehr mit
  `dst-port=67`, 10 statt 9 Regeln), korrigiert und auf den laufenden VMs nachgeprüft; `e2e-vrrp.sh` 137,
  Onboarding 14/15/18. `e2e-mlag.sh` erst 71 von 72 (sw2 im zweiten Apply `add=6;rem=3;set=6`, einmalig, sw1 mit
  derselben Rolle sauber), Wiederholung 72 von 72.
  Mit DM1.1.1 (Module erst lesen, dann setzen) nur `e2e.sh`: 451 von 469 – rot nur Fremdursachen: Schritt 13 (ein
  Download von download.mikrotik.com scheiterte, 12 Folgefehler), cm2-Apply 4 min wegen Spiegel/SFTP (DM3.2, 4 Folgen),
  MNDP-Wackler, Schlüssel-Spiegel nach Rekey im Zeitfenster; Module und SSH-Sperre grün.
  2026-11-11/12 mit Standortkopplung, DynDNS und Freigaben nach Domain/je Client (DR4.3, DR4.4, DR2.8, DR2.9; Labor
  neu auf dem Arbeitsrechner aufgesetzt, 7.25.1): `e2e-vrrp.sh` erster Lauf 158 von 162 – die vier Tunnel-Pings in 5d:
  die `dst-nat`-Regel VIP:Port fehlte für die Standort-Tunnel (die Gegenstelle wechselte auf die reale Adresse des
  Masters, wie DR4.2), dazu im Test die VRF-Routen auf inet (`gateway=wgs@site2`) und das MGMT-Ziel; zweiter Lauf 162
  von 163 (Handshake nach der Preemption brauchte länger als 30 s), dritter Lauf **164 von 164**. `e2e.sh` 475 von 477
  – beide roten veraltete Erwartungen (15 statt 14 Manager-Module durch `mgr-checkn.rsc`, `address-list-extra-time`
  kommt als `00:30:00`), Schritt 14m inhaltlich grün (Liste füllt sich über den Router-DNS mit einer echten Antwort
  auf `www.example.com`). Erkenntnis: Der Endpoint der Gegenstelle bleibt nur mit `dst-nat` an der VIP; die
  Distanz-Umschaltung der Routen (Tunnel 1, VIP 10) trägt beim Ausfall, bei der Rückkehr und nach dem Neustart.
  2026-11-16 mit DG2.4.1 (`$cfmCheck` gibt aus), DM3.3 (Backup-Tick ohne Daten), DM1.4 (Manager-Module aus `work/`,
  Sperre nach einem Rollback, neuer Schritt 17), DT3.4.1/DT3.1.2 (Editor): `e2e.sh` erster Lauf 478 von 485 – rot nur
  Schritt 13, ein einmaliger Abbruch des Paket-Downloads auf cm1 (`/tool/fetch`: „Bad message“, 7 Folgefehler; derselbe
  Download gelang im selben Schritt kurz darauf und danach dreimal von Hand), Wiederholung **485 von 485**. Der
  QR-Encoder des Editors hat einen eigenen Test (`tools/editor/cfm-qr-test.py`, gjs + libzbar).
  2026-11-16/17 (Nachtschicht, DW3.6, DW3.7, DW1.12, `upload-seed.sh` mit `ssh`): `e2e.sh` erster Lauf (Stand mit 72)
  495 von 497 – beide rot im neuen Block zu 72: `tx-power` blieb nach dem Entfernen von `txPower` stehen (`$name` in
  `find where`, ROUTEROS-EIGENHEITEN) und eine falsch formulierte Prüfung; zweiter Lauf (alles) 493 von 501 – rot nur
  Schritt 13, wieder ein Abbruch des Paket-Downloads („Bad message“, 8 Folgefehler; vom Rechner aus gleich danach
  HTTP 200), alle neuen WLAN-Prüfungen grün; Wiederholung **501 von 501**. Dazu `upload-seed-test.py` 8,
  `feature-module-test.py` 12.
  2026-11-17/18 (Nachtschicht, DW1.12.1, DW3.8, DW3.9, `$cfmChannels` live): `e2e.sh` erster Lauf (Stand 88–91)
  503 von 504 – rot nur die DNS-Prüfung in Schritt 6 (Zeitpunkt, jetzt mit Wiederholung 5 × 4 s); zweiter Lauf (mit
  TODO 93) 507 von 515 – rot nur Schritt 13, wieder ein Abbruch des Paket-Downloads („Bad message“, 8 Folgefehler;
  vom Rechner aus gleich danach HTTP 200), alle 11 neuen Prüfungen zum Kanalvorschlag 5/6 GHz grün; Wiederholung
  **515 von 515**.
  2026-11-18/19 (DW1.12.2, DW3.9.1): `e2e.sh` mit TODO 94 500 von 514 – rot nur Schritt 13 (Abbruch des
  Paket-Downloads „Bad message“, 14 Folgefehler; von der VM gleich danach HTTP 200), die neue Prüfung „cfm-fallback
  räumt cfm-iso schon im ersten Takt auf“ grün. Erster Lauf mit TODO 95 hing in Schritt 14 (`cfmScanBlk`: `:find` mit
  Startposition sucht erst nach ihr, Endlosschleife bei `2412/ax/`; ROUTEROS-EIGENHEITEN); Funktion zeichenweise neu,
  sieben Fälle einzeln auf einer CHR geprüft; voller Lauf **513 von 517**: rot
  zwei Fehler im neuen Test selbst (Array-Argumente ohne `({…})`, `$out` überschrieben – korrigiert, beide Prüfungen
  einzeln am Manager-Stand nach dem Lauf grün) und zwei Zeitfehler ohne Bezug zu TODO 95 („ppskOnly im Probelauf“:
  Agent noch beschäftigt; „cm2 Apply v21“: `agentwait`-Timeout, Prüfung danach grün).
  2026-11-19/20 (Nachtschicht, TODO 96: DW3.9.2, DW2.3.1, DU3.5, DT3.5): `e2e.sh` erster Lauf 527 von 531 – rot
  drei Scan-Prüfungen (Startpunkt der Suche aus einem lückenhaften `radios`, angenommene Leistungsreserve zu hoch
  gewichtet – alle APs auf DFS; Code korrigiert) und die neue Prüfung „MLO wieder aus, Puffer cfmwdebug und Regel
  entfernt“ (die Prüfung selbst: `find where action="cfmwdebug"` trifft ohne die Aktion die Regeln von `memory`,
  ROUTEROS-EIGENHEITEN); zweiter Lauf 518 von 532 – rot nur Schritt 13 (Abbruch des Paket-Downloads „Bad message“,
  14 Folgefehler; vom Rechner aus gleich danach geladen); Wiederholung **532 von 532**. Mit dem Stand davor (Änderungen
  danach nur in `mgr-scan`, `$cfmAudit` und Kommentaren): `e2e-vrrp.sh` **184**, `e2e-mlag.sh` **72**,
  `e2e-onboard.sh` **14/15/18**. Dazu `cfm-radios-test.py` 6.
  2026-11-21 (TODO 92 DW3.10, Download-Wiederholung, MNDP-Prüfung): `e2e.sh` **542 von 542** im ersten Lauf – neu
  „Paket-Download: drei Versuche, dann Fehler“ (Version ohne Paket, Warnung je Fehlversuch, keine Reste), `dfs` je AP
  im Scan (Wetterradar nur für den AP mit `10min-cac`), im Apply (`skip-dfs-channels` am eigenen Kanal-Objekt, Pin
  erbt `dfs` des Bands) und in `$cfmCheck` (altes `skipDfs` mit Übersetzung abgelehnt, Pin auf Wetterradar Fehler bzw.
  in einer Liste Warnung); MNDP-Gegenprobe mit eigener raw-Regel grün. Mit demselben Stand `e2e-vrrp.sh` **184**,
  `e2e-mlag.sh` **72**, `e2e-onboard.sh` **14/15/18**.
  2026-11-22 (TODO 6 Berichtsgröße): `e2e.sh` **544 von 544** im ersten Lauf – neu in Schritt 6 „Probelauf über
  60 KB“ (1000 Hostnamen: Bericht gekürzt mit Zeilenzahl, Summe zählt alles, keine Zeitüberschreitung) und „Plan-Datei
  auf dem Manager unter 60 KB und lesbar“. Mit demselben Stand `e2e-vrrp.sh` **184**, `e2e-mlag.sh` **72**,
  `e2e-onboard.sh` **14/15/18**. Dazu `wlan-btm-test.py` 7 (seit 2026-11-24: 11). Dot1X/User Manager von Hand im Probe-Labor (Befunde in
  RADIUS.md §3 und ROUTEROS-EIGENHEITEN).
  2026-11-24 (TODO 55 Baustein 1, DT2.3: `$cfmNetbox`, Agent meldet `eth`): `e2e.sh` **562 von 563** im ersten Lauf – neu
  in Schritt 14 „Agent meldet die Ethernet-Ports“, „`$cfmNetbox`: Soll für 3 Geräte“ und zwei Prüfungen des Abgleichs
  (geplantes Kabel passt zu LLDP, ungeplantes gemeldet; Ports aus `eth`, Adressen aus Soll und Export, VLANs), alle grün.
  Rot nur „ppskOnly im Probelauf“ (Agent noch beschäftigt, „keine Antwort vom Probelauf“, wie am 2026-11-19);
  danach am selben Labor mit derselben Ausgangslage (PPSK-Release v47, Secrets) einzeln nachgestellt: grün. Dazu
  `netbox-abgleich-test.py` 29. `e2e-vrrp.sh`, `e2e-mlag.sh` und `e2e-onboard.sh` nicht wiederholt (Änderung nur im
  Status des Agents und in einem neuen Manager-Modul).
  2026-11-25 (TODO 55 Baustein 2, `tools/netbox-import.py`): kein neuer Lauf (kein RouterOS-Code geändert). Die neue
  Prüfung in Schritt 14 („NetBox-Import: Plan aus cfm ohne Abweichung“) mit dem Labor-Stand vom 24.11. (`nb-state`,
  3 Geräte, 21 Interfaces, 2 Kabel, 16 Adressen) von Hand nachgestellt: grün; derselbe Stand über die NetBox im
  Speicher importiert (61 Objekte) und zurückgelesen: 0 Abweichungen, nur die 4 erwarteten Hinweise „im Hostfile fehlt
  links“. Dazu `netbox-import-test.py` 12, `netbox-abgleich-test.py` 30.
  2026-11-25 (`6f11075`, Agent meldet `rb` per `:parse`, Zuordnung der Gerätetypen): `e2e.sh fresh` **564 von 564**
  im ersten Lauf (rund 2 h). Auf CHR fehlt `/system/routerboard`, der Fehler wird abgefangen, `rb` bleibt leer.
  2026-11-25 (TODO 55 Baustein 3, `global.rsc netbox`, User `cfm-netbox`): `e2e.sh fresh` 570 von 573 – alle Fehler in
  14o: `/file/read` lehnt RouterOS für einen User mit nur `read` ab („not enough permissions“). Umgebaut: Das Skript
  `cfm-netbox-run` gibt die Dateien selbst aus (`$cfmNetboxOut`), Zeilenenden kommen als LF. Schritt 14o danach am selben
  Labor einzeln: **9 von 9** (Ausgabe gleich SFTP für alle 3 Geräte, cm1 `export.rsc` ~530 KB in ~8 s; Abgleich
  `--lesend` 0 Abweichungen; GC räumt auf). Kein zweiter voller Lauf (Änderung nur im netbox-Block und einem neuen
  Manager-Modul-Teil, der übrige Lauf war grün). Dazu `netbox-abgleich-test.py` 33, `cfm_abgleich-test.py` 2.
  2026-11-25 abends, **RouterOS 7.25.2** (`59e3555`, CHR-Image 7.25.2): `e2e.sh fresh` **573 von 573** im ersten Lauf
  (20:24–22:20), damit auch Schritt 14o im vollen Lauf grün. Freigabe für das Update der Geräte auf 7.25.2.
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
* **WPA3-only und Steering nur per 802.11v** (DW2.4, DW2.5) – 2026-11-08 am ersten Standort (CAPsMAN hAP be³, fünf
  APs, 7.25.1), über Nacht und mit einem Rundgang: Kein Client scheiterte dauerhaft an WPA3-only (Fehler nur am
  Rand: `authentication timeout`, `FT failed`, `no cached PMK`); ein Linux-Client mit NetworkManager brauchte das
  Passwort neu. Roaming per FT ohne längere Lücke. 802.11v allein reicht nicht: Vorschläge auf 6 GHz gehen hinaus
  (`all 15` mit `count=15`), die Clients blieben trotzdem bei −78 bzw. −84; ohne Anmeldeschwelle Anmeldungen bei
  −80…−87. Danach Schwellen wieder an (Admin-Guide 8.16).
* **Backup-Manager** (`manager-backup`, DM3.1/DM3.2/DS2.5, DU4.1) – 2026-11-08 am ersten Standort (hAP be³ Media
  als `switch,ap,manager-backup`, 7.25.1, v102–v104): Aufnahme ohne Rollback, Spiegel im Takt (live, archive, meta),
  alle `cfmd-*` gesperrt, `$cfmPlan` des Geräts ohne Änderung. Ausfalltest: Primary (CHR) gestoppt, die Geräte
  liefen mit ihrem Stand weiter und zogen nichts vom Backup; nach 33 min ohne Spiegel kam `primary/on` am
  Webhook an, nach dem Neustart des Primary und dem nächsten Spiegel (v104) `primary/off`. Befund: Die Geräte
  versuchen in der Zeit den Backup per SSH und scheitern an den gesperrten Usern – 65 `login failure`
  (`system,error,critical`) in rund 25 min, auch im Syslog-Server – seither abgewiesen ohne Anmeldung (DS2.5.1).
  Nach dem Neustart des CHR fehlten die Manager-Funktionen bis zum ersten Takt bzw. `/system script run cfm-mgr` –
  seither `cfm-mgr-boot` (DM2.1.1). Beides im Labor, auf Hardware mit dem nächsten Release.
* **Umschaltbarer Port aus Home Assistant** (DP1.4.1, TODO 76) – 2026-11-07 am ersten Standort (hAP be³ Media,
  7.25.1, v102): Release ohne Rollback (Gruppe `cfm-api`, User, Regelblock `capi`, Dienst `api` nur für HA; auf den
  vier Routern die Forward-Freigabe in die MGMT-Zone); das API-Passwort kam mit dem Secret-Push, nachdem der Manager
  selbst die neue Version hatte. HA schaltet per `cfm_port.py` in beide Richtungen, jeder Wechsel kommt als `ev`
  `port` am Webhook an. Ein Container von Hand auf dem Gerät (eigene Bridge, veth, NAT) blieb unberührt.

* **`asymRouting` mit Netzen, Standort ohne `pubkey`, DynDNS `cloud`** (DR3.2.1, DR4.3.1, DR4.4) – 2026-11-13 an
  beiden Standorten, remote (vier VRRP-Router mit RouterOS 7.25.1 bzw. ein CRS418 als Router und CAPsMAN mit 7.25):
  Release mit `sites` ohne `pubkey` legt Schlüssel, Zone, Interface `wg-site-<name>` und die Portfreigabe an, **keine**
  Routen `cfm:rts`/`cfm:rtb` und keine DNS-Weiterleitung; der Weg über den LAN-LAN-Tunnel der Fritz!Boxen bleibt. Der
  Tunnel läuft nur am VRRP-Master, an den Backups ist er aus; den gemeinsamen Schlüssel bringt der Secret-Push, den
  die Rolle selbst anfordert (`sv=0`, Log „Schluessel … weicht vom gemeinsamen … ab“). `/ip/cloud` meldet je Router
  `<SN>.sn.mynetname.net` mit der öffentlichen Adresse (`status: updated`, Hinweis „behind a NAT“). **DR3.2.1:** Host
  mit Gateway VIP aus dem anderen Standort über den Fritz-Tunnel erreichbar – Ping und HTTP (200), die `notrack`-Regel
  für das Netz zählt (0 → 13 Pakete); Vergleichshost mit Fritz!Box-Gateway ebenso (TTL 62 gegen 61 zeigt den Weg der
  Antwort). Dabei: Steering 5 GHz mit `join`/`drop` braucht beim ersten Einschalten je Band eigene Datapaths – die
  CAP-Radios übernehmen sie erst nach `cfm-reprov` (Warnung im Plan), die Radios des CAPsMAN sofort.

* **Kanal-Pool und Sendeleistung 5 GHz** (TODO 72/87) – 2026-11-16 an einem Standort (CRS418 als CAPsMAN, zwei hAP ax²,
  7.25): Pegelmessung mit einem CAP als Empfänger (Scan vom CAPsMAN aus): `antenna-gain` ändert weder `tx-power` noch
  Pegel, `tx-power=10` senkt den Pegel um ~9,5 dB. Pool ohne 5745–5825, dafür DFS 5500–5580/5660–5700 (v39): CRS418
  27 dBm statt 14 (Pegel am CAP −70 → −51 dBm), hAP ax² 18 dBm (Maximum der Hardware) statt 14; 1 min CAC nach dem
  Wechsel auf einen DFS-Kanal. Framework-Update mit DM1.4/DG2.4.1 im selben Release: Module vorab importiert,
  `$cfmCheck` gibt selbst aus, alle Geräte `ok`.

* **PPSK mit normaler Passphrase und FT-Roaming** (DW2.2, DW2.2.1, TODO 74 b): Die VLANs aus den Einträgen gelten, auch mit FT (2026-11-04). *2026-11-12 (CRS418 als CAPsMAN,
  7.25, v37):* normale Passphrase als Gruppeneintrag (DW2.2.1) und PPSK nebeneinander in einer SSID, Secret-Push trennt
  verbundene PPSK-Clients nicht mehr, FT-Wechsel zwischen den Bändern eines Radios-Paars behält das VLAN (der Kommentar
  mit der Gruppe steht nur nach einer vollen Anmeldung). Ein neues Android-Profil
  meldete mit der PPSK zunächst „falsches Passwort“, ein späterer Versuch ging. *Korrektur 2026-11-13:* Die SSID bot
  nur WPA2 an (`authentication-types=wpa2-psk` an allen Radios) – die Vermutung „zuerst SAE“ trifft nicht zu, Ursache
  offen (Tippfehler oder WPA3 im Profil gewählt?), Wiederholung vor Ort.
  *2026-11-17 bestanden (v39):* normale Passphrase einer Test-SSID → `vlan-id=200` (ein erster Versuch brach nach 7 s
  ab, mit Lease aus VLAN 200 – der Schlüssel war angenommen, Ursache beim Handy); FT-Roaming mit PPSK (`ft-wpa2-psk`,
  VLAN 2) ap1 → ap2 → cm1 → ap1, auch zwischen den Bändern, Dauer-Ping ohne Verlust.
* **Weitere SSIDs im lokalen Fallback, Vorgeschichte** (DW1.8 bis 2026-11-16, TODO 40): 2026-11-04 hing keine
  lokale Kopie an (SSID der CAP-Slaves nur in `monitor`→`about`); Fix DW1.8.1 mit zweitem Apply vom Agent.
  *2026-11-12 (v37):* beide hAP ax² hängen die lokale Kopie `cfm-guest` an die Gast-Interfaces, ohne `force`-Push.
  Offen: der Client-Test im Fallback (CAPWAP zu einem AP sperren).
  *2026-11-16 (v39, hAP ax², 7.25; Trennung per Bridge-Filter `output` auf die CAPsMAN-MAC, 3 min):* die
  **Master-SSID sendet lokal weiter** (gleiche BSSID, Client nach ~10 s wieder verbunden, VLAN des Masters geht,
  Rückkehr ohne Aussetzer). Die **Gast-Kopie sendet nicht**: Laptop mit fester BSSID der Gast-SSID → NetworkManager
  `ssid-not-found` nach 16 s; Scan im Fallback zeigt am AP nur die Master-SSID, obwohl `cfm-guest` an den
  Gast-Interfaces hängt und sie nach der Rückkehr `running` sind. cfm greift im Fallback nicht ein (erst der
  Agent-Lauf meldet „WLAN im lokalen Fallback“). Diagnose (Log aus dem AP nach 60 s ohne CAPsMAN): nur die Master
  aktiv, die vom CAPsMAN angelegten Slaves deaktiviert oder weg – Ursache gefunden, neu gelöst mit DW1.12 (nächster Eintrag). Dabei 5 GHz im
  Fallback in DFS-CAC (lokale Kanalwahl). Clients ohne feste BSSID wechseln in 1–3 s zum Nachbarn.
* **Fallback weiterer SSIDs (DW1.12)** – 2026-11-18 an einem Standort (CRS418 als CAPsMAN, zwei hAP ax², 7.25, v40):
  Probelauf je AP `add=4;rem=0;set=2` (DW1.12.1: kein `entfernt: … wdp…`). Erster Apply schaltet `slaves-static` ab
  (CAP trennt ~4 s), `cfm-apfollow` startet den zweiten Apply ~50 s später von selbst, er entfernt je AP **10** alte
  statische virtuelle APs; danach je AP 4 dynamische Slaves und `fb-guest-wifi1/2` (aus). Gast über den CAPsMAN
  unverändert. Trennung per Bridge-Filter (3 min): „lokale Fallback-SSIDs an“ nach 11–18 s, 2,4 GHz im Scan ~33 s
  nach dem Abriss, 5 GHz (DFS) ~83 s; Laptop mit fester BSSID an beiden `fb-guest-…`, Lease im Gast-VLAN, Internet.
  Rückkehr: „aus“ 0–6 s nach dem Verbinden. **Befund:** den Gast-Slave am 5-GHz-Radio legt der CAP erst nach der
  CAC an – `cfm-fallback` trug nur zwei Takte nach dem Verbinden nach, der Slave stand bis zum nächsten Agent-Lauf
  (bis 15 min) ohne `cfm-iso` (zweimal reproduziert); die `fb-…` im Fallback ebenso. Fix DW1.12.2 (Abgleich in jedem
  Takt): *2026-11-23 bestanden (v42, ap2, TODO 94):* Fallback-SSIDs an nach ~20 s, bei der Rückkehr beide Gast-Slaves
  (2,4 und 5 GHz) in derselben Sekunde in `cfm-iso` („nachgetragen (cfm-fallback)“), Verweise auf die vorher neu
  angelegten Interfaces entfernt. Nicht geprüft: zwei Gäste im Fallback ohne Ping untereinander.

* **Kanalbreite in `radios`, Kanäle live, Vorschlag 5 GHz (DW3.8, TODO 91, DW3.9)** – 2026-11-18 am selben Standort:
  `$cfmCheck` warnt bei 5660–5700 mit 80 MHz vor der Blockgrenze 5725 (5580 nicht). `$cfmWifiScan band=5` lieferte
  „breit“ und „robust“ mit fertiger Zeile `radios`; „breit“ übernommen (zwei Radios vorher Gleichkanal 5500/80,
  −52 dBm untereinander; danach `/80`, `/80`, `/40` in getrennten Blöcken). Die CAPs übernehmen die Pins erst nach
  `cfm-reprov` am CAPsMAN (Admin-Guide 8.7), danach `$cfmChannels` live mit `*` wie geplant. Pegel an sechs Orten
  vorher/nachher (2026-11-19): im Mittel gleich, Randlage leicht besser; ein Radio nach dem Wechsel auf 5180 bei
  gleicher Leistung (18 dBm) 4–10 dB schwächer, Ursache offen. Fehler im Vorschlag (Breite `/20` wegen Zusatz `/D`,
  CAPsMAN-Radio `?` in der CAC, Fehlalarm Rolle) → DW3.9.1, Hardware offen (unten).
* **Zertifikate für WebFig und API** (DS3.6, 2026-11-23, an einem Standort, v42, 7.25, hAP ax² und CRS418): Schlüssel und
  CSR auf dem Gerät (mit dem zweiten Agent-Lauf nach dem Apply), Signer im anderen Standort per SSH als `cfm-cert`
  über eine Fritz!Box-Kopplung, certbot `--csr` mit acme-dns (~10 s je Gerät), `cfm-cert-pull`, Import der echten Kette
  von Let's Encrypt; `$cfmTlsStatus` alle drei `ok`, 89 Tage.

## Offen auf Hardware

* **Zertifikate – Rest** (DS3.6): Browser und `api-ssl` mit dem Namen (Home Assistant), Erneuern nach `renew` Tagen ohne
  Eingriff (erstmals ~Januar 2027), Signer für einen zweiten Manager (anderer Standort).
* **Je AP: Pool, `txPower`, Band aus** (DW3.7, 2026-11-16, Labor grün): Senkt `txPower` am CAP den Pegel wie an der
  CRS418 (Pegel an einem festen Empfänger, nicht nur `monitor`)? Übernimmt der CAP die Leistung aus der
  Master-Konfiguration des CAPsMAN, auch für die virtuellen APs? `"off"`: Regel `action=none` mit einem echten CAP,
  Radio aus im CAPsMAN-Betrieb und im Fallback, Zurücknehmen; eigene Radios des CAPsMAN-Geräts.
* **5-GHz-Pool mit DFS** (DW3.6, Vorlage seit 2026-11-16, an einem Standort seit v39): Begrenzt RouterOS 80 MHz auf
  5660–5700 korrekt (der 80-MHz-Block 5660–5720 reicht über 5725 MHz – erwartet 40 bzw. 20 MHz, `monitor` →
  `channel`)? CAC-Dauer nach einem Neustart des Radios, Verhalten bei Radar (Log `dfs`).
* **Standortkopplung und DynDNS** (DR4.3, DR4.4, 2026-11-11; Labor grün 2026-11-12): Tunnel zwischen zwei Standorten hinter Fritz!Boxen
  (Portfreigaben, DynDNS-Update beim echten Anbieter, Endpoint-Auflösung nach einem Adresswechsel), VRRP-Wechsel mit
  stehendem Tunnel, Fritz!Box-Routen für Clients mit dem Internet-Router als Gateway, DNS-Namen der Gegenseite.
  *2026-11-13:* beide Standorte vorbereitet ohne `pubkey`, Cloud-DDNS meldet (siehe oben); der Tunnel selbst folgt mit
  der Messung B (TODO 81).
* **Freigaben nach Domain und je Client** (DR2.8, DR2.9, 2026-11-11; Labor grün 2026-11-12): Füllt ein echtes IoT-Gerät die Adressliste über
  den Router-DNS (TTL, `address-list-extra-time`)? Regel mit Adresse + MAC an einem VRRP-Router; `tuya`-Liste an
  einem Standort auf Domains umgestellt (*2026-11-13 ausgerollt*: statische Einträge raus, `dnsal:`-Einträge am
  Router-DNS da; die Liste steht in keiner Policy, gefüllt erst beim Anlernen eines Tuya-Geräts).
* **Onboarding-Push gegen echte Werks-Configs:** Router (ether1 = WAN mit Firewall), CRS-Switches, Geräte mit
  `flash/`-Verzeichnis; Aufkleber-Passwort (beim einzigen Versuch, einem hAP ax³ mit RouterOS 7.8, passte es nicht –
  das Gerät hatte ein leeres Passwort, der Fallback griff). Im CAPs-Modus das LED-Verhalten je Modell.
* **Manager-Bootstrap mit Reset** auf einem Gerät mit `flash/`-Verzeichnis.
* **Bridge nach Neustart/Rollback:** Auf CHR nimmt eine Bridge mit VLAN-Filtering nach dem Boot sporadisch keine
  getaggten Frames an (cfm startet die Ports dann neu). Betrifft das auch Geräte mit Switch-Chip? Auf Hardware
  prüfen, ob die Log-Meldung „Bridge-Ports werden neu gestartet“ auftritt (bisher ein Datenpunkt ohne, siehe oben).
* **PPSK – Rest** (DW2.2): `ppskOnly`; SSIDs mit `ppsk` nur WPA2 (Daten oder `$cfmCheck`-Warnung, nicht entschieden –
  MikroTik: multi-passphrase nicht mit WPA3-PSK); zweiter Standort (TODO 74).
* **Backup-Manager** (`manager-backup`, DM3.1/DM3.2/DS2.5) – bisher nur im Labor (`e2e.sh`: cm2, auch als
  `manager-backup,ap`). *2026-11-08 an einem Standort bestanden (siehe oben):* Spiegel, gesperrte Geräte-User,
  `primary/on`/`off` am Webhook, Geräte ziehen nicht vom Backup. Offen: Platz auf dem Backup über längere Zeit,
  zweiphasiger Rekey mit zwei echten Managern, SSH-Sperre der Geräte am Backup (DS2.5.1) bei einem Ausfall;
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
* **Steering 2,4 GHz:** Beim Rundgang 2026-11-08 kein einziger Vorschlag, obwohl ein Client 25 s unter `threshold`
  lag (an einem Tag nur einer auf 2,4 GHz). Gezielt prüfen: Client 2 min unter der Schwelle halten, `count` als
  Zahl, Log `wireless,debug`.
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
  Abschalten von `capsmanRadios` feste Interfaces der eigenen Radios stehen?
* **Kanalvorschlag nach DW3.9.1 (TODO 95):** nach dem Framework-Upload `$cfmWifiScan band=5` am CAPsMAN: „Aktuell“
  mit den echten Breiten (z.B. `ap2=5180/80`, nicht `/20`), kein `cm1=?`, Anteil „Leistung“ für die hAP ax² 0;
  `$cfmCheck` ohne „radios nennt cm1 ohne Rolle“.
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
  Client-Isolation trennt nicht zwischen den Radios eines AP (beides 2026-11-04). *2026-11-12 (v37):* zwei Gäste an
  verschiedenen Radios des CAPsMAN (CRS418, 2,4 und 5 GHz) erreichen einander nicht mehr (Bridge-Filter, letzte
  Regel `drop`), Gateway und Internet gehen; `cfm-iso` an den APs enthält die Gast-Interfaces. Offen (TODO 74, geplant
  28./29.11. am zweiten Standort): zwei Gäste an verschiedenen APs und die Zähler am AP. Sieht der
  Bridge-Filter WLAN-Frames als `ip` oder als `vlan` (Labor: virtio `ip`, e1000 `vlan`; die MAC-Regeln greifen in
  beiden Fällen)? An Switches: `hw=no` an isolierten
  Access-Ports (Durchsatz über die CPU).
* **Bandbreitenlimit** (DR2.7): zwei Clients gleichzeitig (Aufteilung, Gesamtgrenze); Gegenprobe der Annahme aus der
  MikroTik-Doku – Ausnahme kurz abschalten, läuft der Gast dann ungebremst?; CPU-Last der CRS418 unter Volllast.
* **`asymRouting`** (DR3.2, TODO 67): Ausfall des Internet-Routers – bleiben die internen Wege?; VRRP-Wechsel;
  Portfreigabe auf einen Host mit Gateway VIP. **Netze** (DR3.2.1): bestanden 2026-11-13 (siehe oben); offen nur, dass
  die Regel mit dem `pubkey` der Standortkopplung entfällt (TODO 81).
* **Feature-Module** (DG4.6, TODO 73): `cfm-dnsreq` auf einem Router mit `dns.rsc`.
