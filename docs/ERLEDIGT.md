# Erledigt

Was aus [TODO.md](TODO.md) erledigt ist, mit den Nummern der Punkte (neue Punkte in TODO.md zählen weiter, ab 79).
Begründungen stehen in [DECISIONS.md](DECISIONS.md), Testergebnisse in [TESTSTAND.md](TESTSTAND.md).

* [Verlauf](#verlauf) – was wann erledigt wurde, neueste oben
* [Erledigte Punkte](#erledigte-punkte) – die Punkte des Verbesserungsplans mit Befund und Umsetzung
* [Frühere Fassungen](#frühere-fassungen) – Volltext der Punkte, die in TODO.md auf ihren offenen Rest gekürzt sind
* [Behobene Fehler](#behobene-fehler)

## Verlauf

* **Am 2026-11-08 abends (Befunde vom Backup-Manager):** Der unbeförderte Backup weist SSH der Geräte per TCP-Reset
  ab, bevor sie sich anmelden – kein `login failure` mehr während eines Ausfalls des Primary, Fehlversuche von Admins
  bleiben im Log (DS2.5.1). Nach einem Neustart lädt `cfm-mgr-boot` die Manager-Funktionen gleich (DM2.1.1). Der
  input-Block der Nicht-Router verwirft DHCP-Discover mit Quelle `0.0.0.0` still (DR2.5.1). Labor-Wackler MNDP
  nur entschärft (Senden anstoßen, 120 s – im zweiten Lauf wieder rot, offen). Neu: TODO 78 (Manager-Bibliothek beim Release aus `work/`).
* **Am 2026-11-08 (Backup-Manager am Standort, TODO 77):** Ein hAP be³ Media läuft als
  `switch,ap,manager-backup` an einem Standort: Spiegel im Takt, `cfmd-*` gesperrt. Ausfalltest mit gestopptem
  Primary bestanden, `primary/on` nach 33 min und `primary/off` nach der Rückkehr kamen am Webhook an (TESTSTAND).
  Befund dabei: Die Geräte versuchen während des Ausfalls den Backup und scheitern an den gesperrten Usern – 65
  `login failure` (`critical`) in rund 25 min, offen zur Entscheidung. Am selben Standort als v103 die Haupt-SSID nur
  WPA3 (Steering ohne kick/drop) und als v104 eine Forward-Freigabe IoT → MQTT-Broker. TODO 77 (DM1.3): `host=`
  ohne Groß-/Kleinschreibung. Behoben: `upload-seed.sh --site` lud die Labor-Hostfiles der Vorlage mit (Nachtrag
  DT2.2). Labor 7.25.1 grün: `e2e.sh` 461, vrrp 137, mlag 72, Onboarding 14/15/18. Danach am selben Standort
  WPA3-only mit Steering nur per 802.11v getestet: reicht nicht, Schwellen wieder an (Nachtrag DW2.4, Admin-Guide
  8.16, zwei Eigenheiten).
* **Am 2026-11-07 (HA-Port-Schalter am Standort):** Framework `0ca97f7` als v102 an allen 10 Geräten `ok`. TODO 76
  (DP1.4.1) bestanden: HA schaltet den Dock-Port per `cfm_port.py`, die Meldungen kommen am Webhook an (TESTSTAND).
  Das API-Passwort für das Gerät mit `portSwitch` kam erst mit `$cfmSecretPush` nach Ring 2: Den vom Apply
  angeforderten Push führte der Manager noch mit seiner alten Bibliothek aus. Neu: TODO 77 (Hostnamen ohne
  Groß-/Kleinschreibung).
* **Am 2026-11-06 (Abschluss der Vorbereitung, Rollout an einem Standort):** Labor 7.25.1 grün (`e2e.sh` 447,
  vrrp 137, mlag 72, Onboarding 14/15/18), Commit `673a944`. Dabei behoben: doppelte Benachrichtigungen bei zwei
  gleichzeitigen `$cfmNotifyTick` (Sperre `cfmNotBusy`, Nachtrag DU4.1, unten unter „Behobene Fehler“); der e2e-Test
  „ppskOnly im Probelauf“ wartet, bis der Agent frei ist. Neu: `upload-seed.sh` prüft vor dem Upload mit
  `rsc-check.py` und bricht bei Fehlern ab (`--no-check`, Nachtrag DT2.2) – Anlass: ein Hostfile mit Kommentar im
  Array-Literal erreichte den Manager, erst `$cfmCheck` fing es ab. Admin-Guide 8.1: Nach dem Import der neuen
  Manager-Bibliothek nicht mehr `cfm-mgr` starten (lädt die alten Skripte zurück). Hardware: Framework als v99 an
  allen 10 Geräten `ok` (v98 lief noch mit dem alten Manager-Code), Dock-Port (65b, DP1.4) als v100 an einem
  hAP be³ Media: Umschalten per Skript bestanden (Pool-Adresse in 175, Internet ja, LAN nein). Der Reset-Taster löste zunächst
  nicht aus; eingegrenzt mit Log-Befehl und Probe-Skript: `on-event` ist Code (nicht der Skriptname), und eine
  geänderte Belegung wirkt erst mit `hold-time` – Rolle entsprechend geändert (Nachtrag DP1.4, EIGENHEITEN), unten
  unter „Behobene Fehler“. Abends als v101 an allen 10 Geräten `ok`; die Rolle setzte am hAP be³ Media die eigene
  Taster-Belegung. Umschalten per Taster in beide Richtungen mit dem Admin-Laptop am Dock bestanden (65b auf
  Hardware bis auf `hw` an einem CRS und ein Release im alt-Zustand, [TESTSTAND.md](TESTSTAND.md)). Der Taster löst
  aber nur bei kräftigem Druck und auch dann nicht immer aus – Schalten aus Home Assistant vorgezogen (TODO 76).
* **Umgesetzt am 2026-11-05 (Vorbereitung eines Standort-Rollouts):** 7 (Nachtrag DV1.2) – der Backup-Manager
  spiegelt offene RouterOS-Aufträge samt Paketen; 64 (Nachtrag DU4.2) – ein später aufgenommenes oder
  zurückgestuftes Gerät öffnet die `ros`-Meldung wieder; 65b-Rückfall (DP1.4) – umschaltbarer Port per Skript und
  Reset- oder Mode-Taster; 75 (DU2.3.1) – `$cfmSniff mirror=<Port>` spiegelt gebrückten Verkehr zur CPU. Labor: `e2e.sh`;
  Hardware offen.
* **Umgesetzt am 2026-11-02:** 73 (DG4.6) – Feature-Module: Code einzelner Features (DNS,
  WireGuard, Bandbreitenlimit, Bonds/MLAG, isolierte VLANs, SNMP, Admin-SSH-Keys) und die Skripte des CAPsMAN in
  eigenen Dateien, nur bei Nutzung geladen; `upload-seed.sh` lädt nur, was die Site nutzt. Labor 7.25 grün
  (`e2e.sh` 410, vrrp 137, mlag 72, onboard 14); Hardware an einem Standort ohne DNS-Selbstbedienung ok, offen nur
  noch `cfm-dnsreq` auf einem Router mit `dns.rsc`.
* **Neu am 2026-11-02 (Abgleich mit den Plänen beider Standorte):** Backup-Manager unter „Offen auf Hardware“
  ([TESTSTAND.md](TESTSTAND.md#offen-auf-hardware)) (Test an einem Standort geplant 2026-11-07/08), 72 (Band je AP abschalten, Antennengewinn –
  nur bei Außenantenne).
* **Erledigt am 2026-11-01 (Hardware, ein Standort):** Syslog aller Geräte an Graylog 7.0, LibreNMS liest
  ihn über die Graylog-API je Gerät, DNS-Abfrage-Log (68) in eigenem Stream mit einer Woche Aufbewahrung –
  Admin-Guide 8.15, kein Code. Damit erledigt: offener Syslog-Punkt von 54/DU4.3 (Schwere richtig: warning 4,
  info 6, error 3) und der Syslog-Weg von 68; 22 (Disk-Logging) bleibt unnötig – der Grund eines
  fehlgeschlagenen Applys stand vor dem Rollback-Neustart in Graylog. Neu: 70 (Umlaute im Syslog), 71
  (Dateiinhalte im Syslog) – *beide am selben Tag umgesetzt (DU3.4):* Release-Archiv per `/file/copy`, Manager-Rekey
  ohne privaten Schlüssel als Dateiinhalt, Log-Meldungen in ASCII mit `rsc-check`-Regel `log-ascii`. Labor 7.25: `e2e.sh` 405, grün. Hardware
  2026-11-02 (v95/v96): Release-Syslog des Managers ~1250 → ~100 Zeilen.
* **Umgesetzt am 2026-10-31:** 67 (DR3.2) – `"asymRouting"="internet"` am WAN-VLAN: VIP als Gateway, obwohl der
  Internet-Router im selben Netz steht (`notrack` für Verkehr ins Internet). Labor 7.25: `e2e-vrrp.sh` 137,
  `e2e.sh` 374, grün. Offen auf Hardware (TODO 67).
* **Umgesetzt am 2026-10-31:** 68 (DN3.1) – DNS der Router aus `dns.rsc` (Upstream, Adlisten, Ausnahmen,
  Weiterleitung, Abfrage-Log) und 69 (DN3.2) – DNS-Selbstbedienung mit Lesezeichen cfm-DNS. Labor 7.25: `e2e.sh`
  402, `e2e-vrrp.sh` 137, grün. Hardware an einem Standort (vier Router, VRRP): DN3.1 v90, DN3.2 v91 – Freischaltung
  aus dem Client-VLAN binnen 3 s, dauerhaft machen und löschen als Admin ok. ~~Offen: Syslog-Weg des Abfrage-Logs (68).~~ Erledigt 2026-11-01 (Graylog, 8.15).
* **Erledigt am 2026-10-29:** die drei „Bekannten Fehler“ vom 2026-10-28 – Dateien beim Abholen überschreiben statt
  löschen, `force` löscht `bad`, neue Master-SSID: Nachfassen nach dem Push (DW1.11, Secret-Push sofort, erzwungener
  Apply für die eigenen Radios) – und 54 (DU4.3, SNMPv3 für LibreNMS, Syslog im RFC-Format); leeres `syslog` räumt Aktion und Einträge weg (beide Standorte schickten an ihren Manager, der keinen Syslog annimmt). Labor 7.25: `e2e.sh` 373 grün.
  Offen auf Hardware: eigene Radios nach dem Einschalten per Secret-Push; ~~Syslog an LibreNMS~~ (über Graylog
  bestanden 2026-11-01); SNMP gegen LibreNMS bestanden 2026-10-30.
* **Umgesetzt am 2026-10-28:** 66 (DR2.7) – Bandbreitenlimit je VLAN (`limit` gesamt, `limitClient` je Client, PCQ),
  Fasttrack-Ausnahme je Netz; Queue-Typen ohne `comment` über `cfmByName`. Labor 7.25: Limit und PCQ gemessen
  (unter der 1-Mbit/s-Grenze der CHR), `e2e.sh` 359, grün. Offen auf Hardware: Umgeht Fasttrack ohne die
  Ausnahme wirklich die Queue (CHR hat keinen Fast Path), Last der CPU auf der CRS418.
* **Am 2026-10-28/29 an einem Standort (Hardware, v31/v32):** DR2.7 ausgerollt und mit einem Gast-WLAN bestätigt
  (Limit greift in beiden Richtungen, keine Gast-Verbindung im Fasttrack); dazu drei neue „Bekannte Fehler“ – Datei
  beim Abholen gelöscht und gleichnamig neu geladen (Apply des Managers scheiterte, Rollback mit Neustart), `force`
  löscht `bad` nicht, neue SSIDs schalten den CAPsMAN bis zum Secret-Push aus.
* **Erledigt am 2026-10-27 (vor dem Update eines Standorts):** 65a (DW2.6, Client-VLAN je MAC über `"wifi"="yes"` an
  der Lease; Hardware-Test der Weitergabe an die CAPs offen), drei „Bekannte Fehler“ – Audit-Purge mit
  verschwundenen Folgeobjekten, Labor-Wackler MNDP (14) und `Rekey SFTP cm2` (14g). Labor 7.25: `e2e.sh` 347, grün.
* **Erledigt am 2026-10-27 vormittags:** 64 (DU4.2) – `ros` als Zustand mit „erledigt“-Meldung (`off`, sobald alle
  Geräte aktuell sind oder die Version überholt ist), Felder `key`/`ver` an den Meldungen. Labor 7.25: `e2e.sh` 354, grün.
* **Umgesetzt am 2026-10-26:** 58 (Teil „Neuprovisionieren mit festen Interfaces“, DW4.3) – der Apply warnt bei
  CAP-Radios, deren feste Interfaces nicht mehr zu den Regeln passen, `cfm-reprov` provisioniert sie
  nacheinander und setzt den Schaltzustand durch. Labor 7.25: `e2e.sh` 341, grün. **Neu:** 64 („Erledigt“-Meldung
  für `ros`), 65 (Fremdgerät per MAC ins Gäste-VLAN: (a) WLAN-Access-List, (b) Kabel wartet auf 802.1X).
* **Neu am 2026-10-23:** 62 (Mitschnitt der 802.11v-Vorschläge per Sniffer: schickt RouterOS sie einem
  Client mit FT, und wie antwortet er?).
* **Umgesetzt am 2026-10-23:** 61 (DW2.5) – Trennschwelle je Band (`drop`/`join`/`hold` im steer-Eintrag),
  trennt anders als der Steering-Kick auch Clients mit FT; an einem Standort von Hand erprobt und am
  2026-10-24 dort eingeschaltet (6 GHz).
* **Umgesetzt am 2026-10-23:** 63 (DN2.2) – NTP-Umleitung je VLAN (`"ntp"="redirect"`), für Geräte mit
  fest eingebautem NTP-Server; im Labor geprüft, am 2026-10-24 an einem Standort ausgerollt.
* **Erledigt am 2026-10-22 (Update auf `main` an einem Standort + eigene Radios der CRS418):** 24 (eigene Radios
  des CAPsMAN, DW1.7) – Client-Test und FT-Roaming zu den CAPs bestanden, dabei auch das Neustart-Verhalten
  geklärt (RouterOS provisioniert die eigenen Radios dabei selbst, ohne den cfm-Agent).
* **Erledigt am 2026-10-22:** 52 (DT3.2) – ein festes Lade-Lesezeichen „cfm“ startet cfm-Editor und
  cfm-Monitor in der Fassung vom Gerät; neue Fassungen kommen mit dem Framework-Update, das Lesezeichen bleibt.
* **Erledigt am 2026-10-20:** „Bekannter Fehler“ SSID-Schalten (DW4.1) – die Schalt-Skripte führen die
  Signatur des Regelblocks und den Merker der eigenen Radios nach, der nächste Apply baut nichts mehr neu
  auf; passen die Regeln nicht zum Schaltzustand, startet der Apply das Schalt-Skript; `e2e.sh` 323, grün.
* **Code-Review am 2026-10-20 (gesamtes Framework, Doku gegen den Code abgeglichen):** behoben – Betas
  holen Agent und `tools/upgrade-mirror.py` über den Kanal `development` (bisher `testing`, dort liegen nur
  RCs: eine Beta per `via=internet` scheiterte, DV1.5), „Bekannter Fehler“ Adresse im Onboarding-VLAN auf einem
  Manager mit Rolle `router` (siehe unten), Abschlussmeldung von `upload-seed.sh` (riet nach jedem
  Framework-Upload zum Manager-Bootstrap), `wg-client-setup.sh connect` verlangte unnötig `wg`; entfernt – toter Code (`cfmLibVer`, ungenutzte Locals und
  Deklarationen, doppelte PEM-Umwandlung in `mgr-enroll`, Altlast `cfm-takeover` von vor DW1.5); Doku –
  Befehlsreferenz, Dateiübersicht, NTP der Router, Update-Kanäle, Beispiele, fehlende Zeile DG4.1. Neu offen:
  59 (NTP der Router), 60 (`rsc-check.py` auf ein Overlay mit Exporten). Labor 7.24.5: `e2e.sh` 323,
  `e2e-vrrp.sh` 118, Onboarding 14/15/18, `e2e-mlag.sh` 72, alles grün.
* **Erledigt am 2026-10-20 abends (Folgearbeiten zum Review, Auswahl des Nutzers):** 56 (vorhandene
  VLAN-Interfaces übernehmen, DP1.3), 57 (`wg-client-setup.sh genkey` mit OpenSSL), 59 (NTP der Router,
  DN2.1), 60 (`rsc-check.py` auf Overlays), „Bekannter Fehler“ `$cfmStatus` (holt veraltete Stände selbst ab,
  DU1.5); Manager-Module aufgeteilt (`mgr-vault.rsc` aus `mgr-core`, `mgr-scan.rsc` aus `mgr-net`, beide
  vorher 47 KB nahe der 60-KB-Grenze, DM1.1); Bootstrap des Managers stellt das RAM-Log schon vor dem ersten
  Release um (DU3.2). Labor 7.24.5: `e2e.sh` 328, `e2e-vrrp.sh` 120, Onboarding 14/15/18, `e2e-mlag.sh` 72,
  alles grün.
* **Umgesetzt am 2026-10-20 (58a, DW4.2), Test auf Hardware beim nächsten Gast-Schalten:** Gast-Schalter
  ohne Unterbrechung der übrigen SSIDs – feste WLAN-Interfaces (`create-enabled`), die Schalt-Skripte
  schalten nur die Interfaces der SSID; `tools/home-assistant/cfm_ssid.py` liest den Zustand an den
  Interfaces (die Kopie in Home Assistant erneuern). Labor 7.24.5: `e2e.sh` 325, grün. Seit 2026-10-21 an
  einem Standort in Betrieb (CAPsMAN mit eigenen Radios, vier APs; Plan danach leer), das erste Schalten steht aus.
* **Erledigt am 2026-10-19:** zwei „Bekannte Fehler“ – Umbenennen einer festen Lease (übernommenes Objekt
  wird nicht mehr zugleich als verwaist entfernt) und Steering `kick` über 59 s (`$cfmSame` vergleicht Dauern
  als Zeit); `e2e.sh` 317, `e2e-vrrp.sh` 118, alles grün.
* **Erledigt am 2026-10-18 (Ausfalltests und LAN-DHCP am selben Standort):** DR1.5 (ein startender
  VRRP-Backup ist kurz selbst Master – DHCP/WireGuard folgen dem Master erst nach 5 s), DR3.1 (DNS/DHCP/NTP
  der Router auch aus dem LAN, wenn es zugleich ihr WAN ist; danach LAN-DHCP mit `dhcpGw` am Standort in
  Betrieb). Neu unter „Bekannte Fehler“: Umbenennen einer festen Lease löscht sie beim ersten Apply (behoben
  2026-10-19); Fehler im Werks-Skript des hAP be³ Media beim Start.
* **Erledigt am 2026-10-17 (Router-Umzug eines Standorts):** DR2.6 (`mgmtExtra` hinter cfm-Routern bis ins
  MGMT-VLAN), DR4.2 (WireGuard-Fernzugang mit VRRP: gemeinsamer Schlüssel, Endpoint VIP, Route für Geräte
  mit eigenem Ausgang). **Neu, offen:** 56 (vorhandene VLAN-Interfaces übernehmen), 57
  (`wg-client-setup.sh` ohne `wireguard-tools`), 58 (Gast-Schalter ohne Unterbrechung der übrigen SSIDs)
  und vier kleine Befunde unter „Bekannte Fehler“.
* **Erledigt am 2026-10-16:** 53 (DU1.4): Gerätesuche `$cfmFind` live am Manager, Lesezeichen cfm-WLAN heißt
  „cfm-Monitor“ mit Reiter Suche. ~~**Entschieden, offen:** 54 (LibreNMS: SNMPv3 + Syslog)~~ – umgesetzt 2026-10-29 (DU4.3). **Idee:** 55 (Netbox:
  Export oder als Quelle).
* **Erledigt am 2026-10-16:** 51 (DW3.5): andere Funknetze im 2,4-GHz-Band (`wifi.rsc` → `others`) in
  den Kosten von `$cfmWifiScan`, Kanalvorschlag für neue Zigbee-/Thread-Netze, Kanalsatz 1/5/9; offen
  bleibt nur, Energie-Messungen der Koordinatoren einzubeziehen.
* **Erledigt am 2026-10-13 nachmittags:** RAM-Log ohne `system,info` (DU3.2): Nach einem Framework-Update
  bestand der Puffer des Managers zur Hälfte aus Skript-Quelltext (RouterOS loggt Konfig-Änderungen samt
  Wert); Schlüssel `logMemory` in `global.rsc`.
  Dazu `tools/upgrade-mirror.py`: Zwei gleichzeitige Anfragen nach einer noch nicht zwischengespeicherten
  Datei schrieben dieselbe `.part`-Datei, die zweite brach ab (Labor mit leerem Zwischenspeicher, das
  eingebaute Update scheiterte); jetzt lädt eine Sperre jede Datei nur einmal.
* **Erledigt am 2026-10-13:** 50 (DR2.5): MNDP mit Quelle `0.0.0.0` verwirft der input-Block still (an
  der Quelle nicht ohne Verlust abstellbar, siehe DR2.5); ein Gerät mit eigener Adresse in einem
  Client-VLAN verwirft dort still (Site-Regel in der `post.rsc`).
* **Erledigt am 2026-10-12 abends:** Lesezeichen „cfm-WLAN“ (DU2.2): Clients je AP live und Roaming als
  Zeitleiste, für Standorte ohne Home Assistant. Getestet gegen eine Attrappe der REST-API; offen ist
  der Test mit echten Clients (inzwischen bestanden, [TESTSTAND.md](TESTSTAND.md#bestanden)).
* **Erledigt am 2026-10-12 (sechste Remote-Runde):** 10 (Bonds im Hostfile, DP2.1; MLAG-Paare in
  `mlag.rsc`, DP2.2), 20 bis auf den Proxy (isolierte VLANs über APs und Switches hinweg, Freigaben mit
  Ports je Eintrag, DP3.1). Review von DG2.5, DS1.5, DT2.2 und DT3.1 vor dem nächsten Framework-Update einer Site: Die Sperre `cfmApplyBusy` wirkte nur
  in eine Richtung – jetzt wartet auch ein Apply, der während `$cfmCheck`/`$cfmShow` startet
  (`cfmMgrData`, `e2e.sh` 14j; im Labor nicht nachgestellt, das Fenster ist klein). RouterOS 7.25rc1:
  Globals über die API geprüft (48), 7.26beta1: `e2e.sh` grün, Changelog gesichtet (49). Labor: `lab.sh`
  mit freier Topologie (`LABLINKS`) und Kartentyp (`LABNIC`), neuer Test `e2e-mlag.sh`; 7.24.5 und
  7.25rc1: `e2e.sh` 294, `e2e-mlag.sh` alles grün. Bei der Durchsicht der Doku gefunden und behoben:
  `$cfmDiff` kannte `mlag.rsc` nicht als gemeinsame Datendatei.
* ~~**Einmalig beim nächsten Framework-Update jeder bestehenden Installation:** 47~~ – an beiden Standorten
  erledigt (2026-10-11/14); bleibt als Anleitung für Installationen von vor DG4.3.
* **Erledigt am 2026-10-11/13 (fünfte Remote-Runde):** Manifest-Regeln je Version aus dem Archiv (DG2.5,
  schließt die Lücke von TODO 47 bei `$cfmPromote`), RouterOS 7.25: Host-Key-Prüfung des SSH-Clients aus
  (DS1.5) und Versionsmeldung mit Kanal (sonst IP-Adresse beim Manager), Site-Daten führt der Manager
  (DT2.2: `upload-seed.sh` ohne `--site` nur Framework-Code, `tools/pull-site.sh`), Editor als WebFig-
  Lesezeichen über die REST-API (DT3.1, `tools/editor/`), Regel `json-typ` in `tools/rsc-check.py`,
  `$cfmPlan from=<verzeichnis> role=<rollen>` (Probelauf eines Umbaus, z.B. des Router-Umzugs). Labor
  7.24.5: `e2e.sh` 292, Onboarding 14/15/18, `e2e-vrrp.sh` 79, alles grün (auch 7.25rc1: e2e 292, Onboarding 14/15/18, VRRP 79); Übergang vom Stand vor DG4.3
  durchgespielt (TODO 47). Labor auf 7.25rc1 siehe 48. Beim Probelauf des Router-Umzugs gefunden und
  behoben: Probelauf der Rolle `router` brach vor dem ersten VRRP ab; im Labor unter Last gefunden und
  behoben: Wettlauf zwischen Apply des Managers und `$cfmLoadData` (Sperre `cfmApplyBusy`).
* **Erledigt am 2026-10-11:** WLAN-Teil der Gerätebibliothek ausgelagert (`lib/lib-wifi.rsc`, DG4.3;
  `lib.rsc` 46 → 23 KB), Apply lädt nur geänderte Dateien (DG4.4; Labor: Reapply 1 s statt 16 s auf
  einem Switch, 48 s auf dem Manager). Beim Sichten gefunden und behoben: Der Agent merkte sich die
  geflashte RouterBOARD-Firmware so, dass `:deserialize` sie zur IP-Adresse machte – der Schutz gegen
  wiederholtes Flashen und Neustarten griff nie (DV1.6).
* **Erledigt am 2026-10-08:** 2 (Benachrichtigungen per HTTP-POST, DU4.1), 8 Rest (SFTP-/Host-Schlüssel
  rotieren, Manager zweiphasig, DS2.5); beim Sichten gefunden und behoben: Der Backup-Manager hatte
  keine Geräte-User `cfmd-<name>`, Geräte konnten auch nach der Beförderung nicht von ihm ziehen
  (DS2.5: gesperrt bereit, `$cfmPromoteManager` schaltet frei; Labor: `e2e.sh` 14g). Dazu `level`/`device`/`message` für einfache Webhook-Empfänger und der Hinweis auf neue
  RouterOS-Versionen (`ros`). Seit 2026-10-11 meldet auch der Backup-Manager, wenn der Primary per
  SFTP weg ist oder sein Tick steht.
* **Erledigt am 2026-10-04:** 19 (Admin-SSH-Keys je Person, DS3.3), 46 (`$cfmWifiScan` mit den eigenen
  Radios des CAPsMAN), 40 (`slaves-static` nur bei Bedarf), 23 (Warnung bei `wifi-qcom-ac`; die
  Unterstützung selbst bleibt offen), `$cfmStatus` blendet eine veraltete `bad`-Version aus. Im Labor
  gefunden: `/file/get` meldet gelöschte Dateien u.U. dauerhaft als Eintrag ohne Namen – die
  Existenzprüfungen verlangen jetzt einen Namen (DG4.2).
* **Erledigt am 2026-10-02/03:** 11 (feste Leases und DNS-Namen, DN1.1), 12 (`$cfmShow`/`$cfmDiff`,
  DU1.2), 41 (`$cfmWifiScan` über den CAPsMAN, auf Hardware gelaufen, DW3.3), 38 (Update bei 16 MB
  Flash über das eingebaute Update, Spiegel `tools/upgrade-mirror.py`, DV1.5); dazu schaltbare SSIDs
  für Home Assistant (DW4.1, neu auf Wunsch).
* **Erledigt am 2026-10-01:** 21 (Dateizugriff über den Namen, DG4.1), 36 (Labortest), 44 (Rest,
  DM3.2), „Manager-Ticks starten gleichzeitig“ (DM2.2); Labortest des Watchdog-Rollbacks (`e2e.sh`
  Schritt 14d) und Probe des Router-Umzugs mit drei VRRP-Routern (`e2e-vrrp.sh`). Am 2026-09-30:
  28, 29, 30, 31, 35, 37, 38 (Vorab-Prüfung).

## Erledigte Punkte

1. ~~**`manager.rsc` aufteilen**~~ – *erledigt (DM1.1):* `lib/mgr-core.rsc`, `mgr-enroll.rsc`,
   `mgr-onboard.rsc`, `mgr-auto.rsc` (je höchstens 21 KB statt 53 KB in einer Datei; RouterOS liest
   per `/file get` nur etwa 60 KB, `$cfmRelease` lehnt größere Dateien ab).
2. ~~**Benachrichtigungen**~~ – *erledigt (DU4.1):* `global.rsc` `notify` (HTTP-POST mit JSON, z.B. an
   einen Webhook von Home Assistant), je Zustandswechsel: Apply-Fehler/Rollback, stumm, WLAN lokal,
   Update fehlgeschlagen, Onboarding gescheitert, CHR-Lizenz; Labor: `e2e.sh` Schritt 14f. Der
   Backup-Manager meldet einen stummen Primary (SFTP weg oder Tick steht). – (E-Mail oder Push-Dienst wie
   ntfy/Telegram) bei Fehler/Rollback, stummen Geräten, gescheitertem Onboarding, CAPs im lokalen
   Fallback (DW1.6).
3. ~~**Archiv aufräumen**~~ – *erledigt (DG2.4):* nach jedem Release und auf dem Backup-Spiegel;
   behalten werden `archiveKeep` (10) plus alle von Ringen/Geräten genutzten Versionen.
4. ~~**Prüfskript für RouterOS-Fallen**~~ – *erledigt (DT1.2):* `tools/rsc-check.py` (Zeile beginnt
   mit `[`, `\"` in Argumenten, `:return` in `:onerror`, Slash-Syntax für geräteabhängige Menüs,
   Array-Klammern, `verbose=yes`, Klammern, Dateigröße, Dotfiles), Pre-Commit-Hook
   `tools/git-hooks/pre-commit`, GitHub Action `rsc-check`. Offen: `:parse` und `e2e.sh` in der CI
   (bisher bewusst lokal im Labor).
5. ~~**Inhaltliche Prüfung beim Release**~~ – *erledigt (DG2.4):* `$cfmCheck`, Fehler stoppen das
   Release (`force=yes` übergeht sie), fehlende Hostfiles sind Warnungen.
<!-- -->
7. ~~**RouterOS-Versionspflege – Rest: Pakete auf den Backup-Manager**~~ – *umgesetzt 2026-11-05 (Nachtrag DV1.2):*
   `$cfmMirror` holt `meta/upgrade.dat` und die Pakete offener Aufträge in die eigene Ablage (Pfad umgeschrieben),
   löscht Versionen ohne Auftrag. Labor: `e2e.sh` Schritt 13.
8. ~~**Identitätsprüfung vor dem Secret-Push**~~ – *erledigt (DS1.4):* Challenge-Response mit dem
   Geräteschlüssel; Erneuerung per `$cfmRekey`. ~~Offen: SFTP-Schlüssel (`cfmd-<name>`) rotieren
   (bisher nur per `$cfmEnroll … rekey=yes`).~~ – *erledigt (DS2.5):* `$cfmRekey … sftp=yes`, bei
   Managern zweiphasig (neuer Trust-Key erst auf allen Geräten, sonst Abbruch); der Backup-Manager legt
   die Geräte-User aus dem Spiegel selbst an. Labor: `e2e.sh` Schritt 14g.
9. ~~**Minimale Firewall auf allen Geräten**~~ – *erledigt (DR2.2):* Default-Drop auf Nicht-Routern,
   IPv6-input auf allen Geräten. Offen: IPv6-Forward auf Routern (mit Punkt 13).
10. ~~**Link-Bündel (Bonding/LACP) als Port-Profil** für Uplinks.~~ – *erledigt 2026-10-12:* Hostfile
    `bonds` (DP2.1), MLAG-Paare zentral in `mlag.rsc` (DP2.2). Labor: `e2e-mlag.sh` (fünf VMs, e1000). Offen:
    Test auf Hardware (CRS3xx mit Marvell-Chip: MLAG im Switch-Chip), Verhalten beim Umbau eines
    Uplinks, über den der Weg zum Manager läuft.
11. ~~**Feste DHCP-Leases und DNS-Namen aus zentralen Daten**~~ – *erledigt (DN1.1):* `leases.rsc` je
    VLAN, die Rolle `router` legt Leases und DNS-Namen `<name>.<domain>` (Leases und aufgenommene
    Geräte) an; Standard-Domain `internal`. Labor: `e2e.sh` Schritt 9.
12. ~~**Effektive Config und Diff anzeigen**~~ – *erledigt (DU1.2):* `$cfmShow host=<n> [ver=] [objects=yes]`
    (Daten bzw. Soll-Objekte per Probelauf), `$cfmDiff [ver=A] [to=B]` (Dateien, betroffene Geräte,
    Zeilen der Datendateien). Labor: `e2e.sh` Schritt 9.
<!-- -->
17. ~~**Verkabelung prüfen per LLDP**~~ – *erledigt (DU1.1):* `$cfmLinks` mit Baseline und
    Hostfile-Angaben, `netzplan.md` (Mermaid + Tabelle), `export=yes` für Graphviz/CSV.
<!-- -->
19. ~~**Individuelle `authorized_keys` je Admin-Benutzer**~~ – *erledigt (DS3.3):* `work/authorized_keys.<user>`
    je Person, Abgleich über den Fingerprint, Users ohne Datei unangetastet, die gemeinsame Datei gilt
    nicht mehr. Labor: `e2e.sh` Schritt 14e. Hardware 2026-10-04: neun Geräte von der gemeinsamen Datei
    umgestellt, die drei vorhandenen Keys blieben ohne Änderung stehen (gleiche Fingerprints). – Aktuell (DS3.2) gilt eine einzige
    `authorized_keys`-Datei für ALLE User aus `global.rsc` `users`; bei mehreren Admins sollte
    jeder Benutzer nur seine eigenen Keys bekommen (z.B. `authorized_keys.<user>` oder Zuordnung
    innerhalb der Datei), inkl. Revocation pro Person statt nur global.
<!-- -->
24. ~~**Eigene Radios des Managers**~~ – *erledigt (DW1.7):* Hostfile `capsmanRadios="yes"` auf dem
    CAPsMAN provisioniert dessen eigene Radios über den eigenen CAPsMAN
    (`/interface/wifi/radio/provision [find where local]`, dieselben Regeln wie für die CAPs). Auf
    Hardware seit 2026-10-03 an (hAP be³). Client-Test und FT zu den CAPs bestanden (an einem
    Standort, 2026-10-22, CRS418: Bridge-Port/VLAN korrekt, Roaming cm1-5g ↔ ap1-5g beidseitig); dabei auch das
    Verhalten bei einem Neustart des Geräts geklärt: RouterOS provisioniert die eigenen Radios dabei
    selbst neu, ohne den cfm-Agent (Einzelheiten DW1.7).
<!-- -->
26. ~~**Fremder CAPsMAN im MGMT-VLAN**~~ – Hardware-Befund: Läuft im MGMT-VLAN noch ein anderer
    wifi-CAPsMAN (z.B. auf dem bisherigen Core-Switch), meldet sich ein frisch aufgenommener CAP per
    Discovery dort an, obwohl `caps-man-addresses` auf die cfm-Manager zeigt, und übernimmt dessen
    CA und Zertifikat. Danach scheitert die Verbindung zum cfm-Manager an
    `ssl: no trusted CA certificate found` bzw. `missing key`. Abhilfe von Hand: `caps-man-names`
    auf die Identities der Manager setzen, die fremden Zertifikate löschen und `certificate` einmal
    auf `none` und zurück auf `request` setzen. *Behoben mit DW1.5:* Die Rolle `ap` setzt
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
28. ~~**`$cfmPush` an nicht aufgenommene Geräte**~~ – *erledigt (DO2.2):* Nur Geräte mit Geräteschlüssel
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
31. ~~**Onboarding an einem nicht verwalteten Switch**~~ – *erledigt (DO1.7):* `$cfmOnboard manual=yes
    [name=] [sw= port=]`, Labortest `e2e-onboard.sh manual`. – `$cfmOnboard sw= port=` setzt voraus, dass
    der Switch aufgenommen ist, sonst lässt sich der Port nicht schalten. Beim ersten Gerät hinter
    einem noch nicht übernommenen Core-Switch (Hardware-Befund) musste der Port von Hand in das
    Onboarding-VLAN (PVID) und die Sitzung von Hand in `meta/onboard.dat` angelegt werden; der
    Manager versuchte dabei in jedem Tick, sich am Switch anzumelden. Vorschlag: `$cfmOnboard
    port=manual` (bzw. `sw=-`): kein Umschalten, kein Fail-safe, am Ende kein Push – der Admin
    schaltet den Port selbst hin und zurück.
32. ~~**6 GHz und Wi-Fi 7 (MLO)**~~ – *umgesetzt (DW2.3):* MLO standardmäßig aus, 6 GHz mit Security je
    Band; offen nur noch lokales MLO bzw. MLO mit mehreren SSIDs, falls es je gebraucht wird.
    Hardware-Befund mit einem Tri-Band-AP (`wifi-qcom-be`): Das
    dritte Radio (6 GHz, `6ghz-ax`/`6ghz-be`) bleibt deaktiviert, weil `wifi.rsc` nur die Bänder
    2 und 5 kennt; der CAPsMAN legt außerdem dynamisch ein MLO-Interface (`mld*`) an. Offen:
    Kanal-Pool für Band `6` in `channels`, Provisioning-Regel dafür, 6 GHz verlangt WPA3-SAE mit
    PMF (kein WPA2-Übergang), Umgang mit MLO. `vlan-id` aus dem Datapath funktioniert mit
    `wifi-qcom-be` (`max-vlans=4095`).
    MLO-Befund: Der CAPsMAN fasst die Radios eines Wi-Fi-7-CAP bei gleicher SSID zu einem
    MLD-Interface zusammen; dafür kommen Bridge und `vlan-id` ebenfalls nicht vom CAPsMAN (wie DW1.3).
    Behoben in der Rolle `ap` per `/interface/wifi/cap mld-datapath` mit eigenem Datapath im VLAN der
    Master-SSID. Offen: Da es nur ein `mld-datapath` je CAP gibt, bräuchten weitere SSIDs mit MLO
    eigene Lösungen (MLO für Slave-SSIDs abschalten oder `mld-static` + eigene Datapaths).
33. ~~**Bestandsgeräte, die noch selbst routen**~~ (Hardware-Befund, Core-Switch mit L3 im Switch-Chip):
    Neu in der Rolle `base`: Hostfile-Schlüssel
    `cpuVlans` (Bridge bleibt in VLANs mit eigenen VLAN-Interfaces getaggt), `gw`/`dns`/`ntp` (statt
    MGMT-Gateway bzw. globaler Werte – sonst zeigt ein Gerät, das selbst das MGMT-Gateway ist, auf
    sich selbst), `bridgeFrames` (Bridge nimmt weiter ungetaggte Frames an, z.B. eine Adresse in VLAN 1);
    der Agent-Scheduler wird immer eingeschaltet; `$cfmEnroll … noapply=yes` nimmt ein Gerät ohne
    ersten Apply auf, damit vorher `$cfmPlan` läuft. *Erledigt (DO2.1):* Admin-Guide 7.3 (Ablauf ohne
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
<!-- -->
38. ~~**RouterOS-Update auf Geräten mit 16 MB Flash**~~ (hEX RB750Gr3, CRS328 u.ä.) – *erledigt
    (DV1.5):* `$cfmUpgrade … via=internet|via=mirror mirror=<IP>` nutzt das eingebaute Update des
    Geräts, der Spiegel ist `tools/upgrade-mirror.py`; Labor: `e2e.sh` Schritt 13e. tmpfs geht nicht
    (Laborversuch 2026-10-03). Auf Hardware: hEX mit 2,4 MB frei über den Spiegel aktualisiert. – *Vorab-Prüfung
    erledigt (DV1.3):* Agent meldet den freien Platz (`fs`), `$cfmUpgrade` erteilt zu vollen Geräten
    keinen Auftrag, der Agent prüft vor dem Download erneut. Offen bleibt das Update selbst (tmpfs
    oder eingebautes Update, nur mit Hardware testbar). – `$cfmUpgrade` lädt
    die Pakete per SFTP in den Flash des Geräts; dort sind oft nur 2–3 MB frei, `routeros` braucht
    ~12 MB. Das eingebaute Update (`/system/package/update`) kommt damit zurecht, braucht aber Internet
    am Gerät. Optionen: Pakete in eine tmpfs-Disk (`/disk add type=tmpfs`) laden und von dort
    installieren, falls RouterOS das zulässt; oder für solche Geräte das eingebaute Update über einen
    Proxy/Update-Pfad des Managers. `$cfmUpgrade` sollte vorab den freien Platz prüfen und klar abbrechen.
39. **Mindestsignal für Clients** – *vorbereitet (DW2.4):* `wifi.rsc` `steer` je Band (802.11v-Vorschläge
    an Clients unter der Schwelle, optional Trennen nach `kick`) und `minSignal` für die Anmeldung,
    standardmäßig aus. Vor Ort: Abdeckung prüfen, Schwellen je Band ermitteln, dann einschalten. – Hardware-Befund Roaming-Test mit FT: Die
    Wechsel selbst dauern meist unter 1 s, aber Clients bleiben lange an einem schwachen AP hängen
    (z.B. −79 dBm auf 2,4 GHz, viele kurze Aussetzer), obwohl ein stärkerer AP in Reichweite ist; ein
    Client verlor sogar erst die Verbindung, bevor er wechselte. FT beschleunigt nur den Wechsel, nicht
    die Entscheidung dazu. Idee: `/interface/wifi/access-list` mit `signal-range` aus `wifi.rsc`
    rendern (z.B. Clients unter −75 dBm abweisen bzw. trennen), optional je Band oder AP; dazu prüfen,
    ob die Steering-Einstellungen (`rrm`/`wnm`, BSS Transition) aktiv zum Wechsel auffordern.
    Risiko: In Randbereichen ohne besseren AP verliert ein Client dann ganz die Verbindung – vorher
    die Abdeckung prüfen (Löcher zwischen APs). Steering trennt Clients mit FT nicht → 61 (DW2.5, Trennschwelle).
    *Abgeschlossen 2026-11-03:* Steering (DW2.4) und Trennschwelle (DW2.5) laufen seit 2026-10-17 bzw. -24 an
    einem Standort ([TESTSTAND.md](TESTSTAND.md#bestanden)); ob Clients auf 802.11v-Vorschläge wechseln: 62.
<!-- -->
41. ~~**Kanalplan per Scan**~~ (entschieden 2026-09-27: fester Plan, gelegentlich neu optimieren) –
    *erledigt (DW3.2, DW3.3):* `$cfmWifiScan` scannt über den CAPsMAN (der CAP selbst lehnt den Scan ab,
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
44. ~~**Agent auf einem Backup-Manager fragt sich selbst**~~ – *Rest erledigt (DM3.2):* auch der Abruf des
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
    *Abgeschlossen 2026-11-03:* alle Geräte beider Standorte laufen mit 7.25 ([TESTSTAND.md](TESTSTAND.md)).
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
47. **Erstes Release nach dem Update auf DG4.3 (einmalig je bestehender Installation)** – *an beiden Standorten
    erledigt (2026-10-11/14); gilt nur noch für Installationen von vor DG4.3.* Das erste Release nach
    dem Hochladen baut noch der installierte Manager-Code. Der kennt `lib/lib-wifi.rsc` nicht, die
    Manifeste der WLAN-Geräte (Rollen `ap`, `capsman`, `manager`) nennen die Datei dann nicht. Geräte,
    die seit ihrem letzten Apply neu gestartet sind, haben die WLAN-Funktionen nicht mehr im Speicher
    und brechen mit „lib/lib-wifi.rsc fehlt im Manifest (DG4.3)“ ab: Rollback mit Neustart, die
    Version gilt als `bad`. Die übrigen laufen mit den Funktionen aus dem Speicher durch. Vorgehen:
    1. Framework wie gewohnt hochladen.
    2. Am Manager vor dem Release den neuen Manifest-Bau aus `work/` laden:
       `/system script run cfm-mgr; /import cfm/work/lib/mgr-core.rsc verbose=no`
    3. Gleich danach in derselben Sitzung `$cfmRelease msg="…"` (ringweise oder `all=yes`); der
       Manager-Tick lädt sonst wieder den installierten Code. **Korrektur 2026-10-11:** Schritt 2 gilt
       vor **jedem** Befehl, der Manifeste baut (`$cfmRelease`, `$cfmPromote`, `$cfmEnroll`,
       `$cfmUpgrade`), bis der Manager die neue Version selbst angewendet hat (`$cfmStatus`). Ein
       `$cfmPromote ring=1` aus einer neuen Sitzung baute sonst mit dem alten Code alle Manifeste neu,
       ohne `lib-wifi` auch für Ring 0. Ab DG2.5 (Regeln je Version aus dem Archiv) entfällt der Handgriff
       bei künftigen Updates; für den ersten Sprung auf DG2.5 bleibt er nötig. Achtung `ringSoak`: Nach
       dessen erstem Wert befördert der Manager-Tick den nächsten Ring selbst, mit dem installierten
       Code. Ring 1 und 2 deshalb vorher von Hand befördern (je mit dem Import) oder gleich `all=yes`.
    4. Prüfen: `$cfmStatus` ohne Fehler; das Manifest eines AP nennt den WLAN-Teil, z.B.
       `:put [:find [/file/get cfm/live/m/<Seriennummer>.mf contents] "lib-wifi"]` (Zahl, nicht leer).
    Falls Schritt 2 vergessen wurde: Sobald der Manager die Version angewendet hat, `$cfmManifests`,
    dann je zurückgerolltem Gerät `$cfmPush host=<name> force=yes`. Im Labor (2026-10-11) mit dem
    Stand von v19 durchgespielt: alle drei Geräte ok, nur der Manager bekam den WLAN-Teil.
<!-- -->
50. ~~**Broadcasts füllen das Log der Nicht-Router**~~ – *erledigt 2026-10-13 (DR2.5):* MNDP mit Quelle
    `0.0.0.0` verwirft der input-Block `fwb` still, vor dem Log. Zuerst an der Quelle (`7635c5e`: VMs mit
    `stp="none"` ohne MNDP), am selben Tag zurückgenommen: Die VM fehlte dann in Winbox, und gezielt nur
    für die Karte geht es nicht (Labor, DR2.5); das Gerät mit
    eigener Adresse im Client-VLAN verwirft dort per `local-input` still (Site-Regel, an dem Standort
    ausgerollt: kein `cfm-drop` mehr aus dem VLAN). Befund 2026-10-12: Die minimale Firewall (DR2.2)
    loggt jedes verworfene Paket an das Gerät selbst (Chain `input`), auch Broadcasts. Weitergeleitet
    wird davon alles normal: Der Filter sieht nur, was an das Gerät geht, nicht den Verkehr der Clients
    untereinander. Zwei Quellen an einem Standort, jeweils über 80 % der 1000 Zeilen des RAM-Logs (es
    reichte nur etwa 7 h zurück, WLAN-Ereignisse (DU2.2) und Fehler fallen früh heraus, über Syslog
    entsteht dieselbe Menge):
    * **MNDP des Managers in einer VM:** Die Nachbarsuche läuft auf allen Bridge-Ports (DU1.1). Über seine
      Karte im MGMT-VLAN (DP1.2, ohne eigene Adresse an der Karte) sendet er MNDP (UDP 5678) mit Quelle
      `0.0.0.0` an 255.255.255.255, alle 30 s. Jedes Gerät im MGMT-VLAN verwirft das (Quelle nicht in
      `cfm-mgmt`) und loggt es; die MNDP-Pakete mit seiner MGMT-Adresse kommen durch.
    * **Gerät mit eigener Adresse in einem Client-VLAN** (z.B. ein AP mit NAT-Käfig per `post.rsc`):
      bekommt jeden Broadcast dieses VLANs zugestellt (Discovery von Medienservern UDP 32412/32414,
      SSDP, NetBIOS, MNDP anderer Geräte).
    Verworfen: Broadcast/Multicast allgemein ohne Log verwerfen bzw. das Log enger begrenzen
    (behandelt nur die Wirkung, der Nutzer wollte die Ursachen beheben); für MNDP mit Quelle `0.0.0.0`
    blieb nur der Empfänger, und die Regel trifft genau diese Pakete.
<!-- -->
52. ~~**Lesezeichen ohne Hantieren**~~ (Wunsch des Nutzers, 2026-10-15) – *erledigt 2026-10-22 (DT3.2): festes
    Lade-Lesezeichen „cfm“, das die Fassung vom Gerät startet (`cfm/work/web/`, mit dem Release zu Manager und
    CAPsMAN); entschieden aus den Wegen unten, im Labor geprüft (Verteilung je Rolle, Laden per REST mit nachgebildetem
    Browser). Im echten Browser geprüft 2026-10-26 (Firefox 153 ESR, WebFig 7.25, an einem Standort): Formular,
    401 bei falschem Passwort, Start des Monitors auf dem CAPsMAN (einzige Datei), Menü und Editor auf dem
    Manager, gemerkte Anmeldung. Die Fehler `attrs is undefined` in der Konsole kommen von WebFig selbst (auch
    ohne Lesezeichen). Dabei behoben: Der Editor führte `web/` unter „Site-Daten“ (bearbeitbar), jetzt wie `lib/`
    und `roles/` nur lesen. Offen: am zweiten Standort nach dessen Framework-Update anlegen und die alten
    Lesezeichen löschen.* –
    Die Lesezeichen von DT3.1/DU2.2 müssen
    aus `install.html` in die Leiste gezogen und nach jeder neuen Fassung ersetzt werden. Auf dem Gerät
    selbst lässt sich nichts installieren: Wegen fehlender CORS-Header muss der Code unter derselben Adresse
    laufen wie `/rest`, `www` liefert keine eigenen Dateien aus, Skins sind nur JSON, Hotspot-Seiten liegen
    unter einer anderen Adresse (Befunde in ROUTEROS-EIGENHEITEN.md). Bekannte, vorerst verworfene Wege:
    * **Festes Lade-Lesezeichen, Code auf dem Gerät:** ein winziges Lesezeichen „cfm“, einmal angelegt;
      es liest `cfm-editor.js`/`cfm-monitor.js` über die bestehende WebFig-Sitzung (`fetchFile` über
      `/jsproxy`, im Labor geprüft) vom Gerät und startet sie. Updates kommen mit `upload-seed.sh`.
      Dagegen: undokumentierte WebFig-Interna (Rückfall: Laden per REST nach der Anmeldung); der CAPsMAN
      braucht die Dateien auch, wenn er nicht der Manager ist.
    * **Userscript** (Violentmonkey/Tampermonkey): einmal `cfm.user.js` installieren, es blendet in jeder
      WebFig-Seite Knöpfe für Editor und WLAN ein, Updates per `@updateURL` aus dem öffentlichen Repo.
      Dagegen: Browser-Erweiterung nötig (DT3.1), Code aus dem Netz.
    * **Container auf dem Gerät** (RouterOS-Container bzw. „Apps“), der die Seite ausliefert und `/rest`
      durchreicht; im Browser nichts. Dagegen: Container-Paket und Speicher nötig (ein CRS328 im Einsatz hat 1,6 MB frei,
      hAPs knapp).
53. ~~**Gerätesuche `$cfmFind` und Lesezeichen „cfm-Monitor“**~~ (Wunsch des Nutzers, entschieden 2026-10-16) –
    *erledigt 2026-10-16 (DU1.4, Admin-Guide 8.10/8.11): `$cfmFind`, der bisherige interne Helfer heißt
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
      dem Manager startet (wie der cfm-Editor). Das Lesezeichen „cfm-WLAN“ (DU2.2) heißt dann
      **„cfm-Monitor“** (`tools/editor/`, `install.html`, `build.py`, tools/README, Admin-Guide 8.10).
    * Grenzen: In Netzen mit fremdem DHCP (z.B. Fritz!Box) kennt cfm IPs nur aus der ARP-Tabelle eines
      eigenen Routers mit Adresse im VLAN, Namen nur aus `leases.rsc`. Rolle `ap` läuft im Labor nicht
      (CHR ohne Radios) – WLAN-Teil nur mit Hardware testbar.
<!-- -->
56. ~~**Vorhandene VLAN-Interfaces an Bridge und VLAN-ID übernehmen**~~ (entschieden 2026-10-17) – *erledigt
    2026-10-20 (DP1.3):* `$cfmVlanKey` sucht zuerst `vlan<VID>`, sonst ein VLAN-Interface auf der Bridge mit
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
<!-- -->
59. ~~**NTP der Router**~~ (Code-Review 2026-10-20) – *erledigt am selben Tag (DN2.1):* `wan.ntp` (Text oder
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
61. ~~**Trennschwelle per access-list, auch mit FT**~~ (Wunsch des Nutzers, 2026-10-22; Anlass: Steering trennt
    FT-Clients nicht, 39/DW2.4) – *umgesetzt 2026-10-23 (DW2.5):* `steer` je Band mit `drop`/`join`/`hold`, zwei
    Regeln je Band für die Liste `cfm-wifi-<Band>g`, die RouterOS über einen datapath je Band füllt; isolierte
    VLANs ausgenommen. Labor `e2e.sh` (Objekte, Reihenfolge, Entfernen, Prüfungen); das Trennen von Hand an
    einem Standort erprobt (Liste, Hysterese, FT). Dort am 2026-10-24 mit dem Framework
    eingeschaltet (6 GHz −74/−68/60 s), Handregeln entfernt; **offen:** Wirkung über einige Tage auswerten. – Befund an einem Standort (18./19.10.): `steer` mit `kick` trennte einen
    Client ohne FT zuverlässig nach `after` + `kick`, ein Handy mit `ft-wpa3-psk` nie (18 min bei −88…−93 dBm);
    `minSignal` (access-list `reject`) griff bei einem Wechsel per FT nicht (Wechsel mit −83 bei Schwelle −80).
    Laut RouterOS-Doku prüft die access-list nur Verbindungen **laufend**, die eine Regel **angenommen** hat
    (`signal-range`, `time`), und trennt sie, wenn das Signal länger als `allow-signal-out-of-range` außerhalb
    liegt (Standard `0s`, `always` = nur bei der Anmeldung). Die Regel `wacl:min` lehnt nur ab – eine
    angenommene Verbindung unter der Schwelle trennt sie also nie. `interface` nimmt auch eine Interface-Liste.
    Idee: je Band (oder AP) eine `accept`-Regel mit `signal-range=<Schwelle>..0` und
    `allow-signal-out-of-range=<Zeit>` vor `wacl:min`, dazu `reject` darunter; `interface` = eine Liste der
    WLAN-Interfaces des Bands. Seit DW4.2 sind die Interfaces fest – der Grund aus DW2.4 („Interfaces der CAPs
    entstehen dynamisch“) fällt weg, solange alle Interfaces fest sind. **Offen, vor dem Bauen von Hand an
    der Hardware prüfen:** (1) ~~Wird eine per FT übernommene Verbindung überhaupt einer Regel zugeordnet und
    laufend geprüft?~~ *Ja (Test von Hand 2026-10-22, 7.24.5, CAPsMAN mit CAP auf 7.25beta5): nach FT-Wechsel
    viermal „disconnected, signal too weak“ ~20 s nach Unterschreiten der Schwelle, 0–4 s bis zur neuen
    Verbindung.* Weitere Befunde dabei: Die Regel verweist per ID auf das Interface – nach dem Provisionieren
    (auch der eigenen Radios) zeigt sie ins Leere (`*90`), der Apply muss sie also jedes Mal nachführen; jede
    Änderung an der access-list prüft alle Verbindungen neu und trennt Clients, die dann unter eine
    `reject`-Regel fallen („access-list changed“). Ob 802.11v-Vorschläge des Steerings (`period`/`count`) vor
    der Trennung einen Wechsel bewirken, wird an dem Standort gemessen (selbst gewechselt vs. getrennt).
    (2) Wirkt eine Regel mit `interface=<Liste>` am CAPsMAN auf die Interfaces der CAPs (`wacl:min` am
    CAPsMAN wirkt dort)? *Mit einzelnem Interface ja (getestet an einem CAP-Interface), mit Liste ungeprüft.* (3) Trennt sie hart – ohne vorherige 802.11v-Vorschläge, auch wenn kein besserer AP
    da ist (Randbereiche, siehe 39). Vorab-Test ohne Framework am CAPsMAN, z.B.
    `/interface/wifi/access-list add interface=<AP>-6g signal-range=-72..0 allow-signal-out-of-range=20s
    action=accept comment=test place-before=0`, Client mit FT dorthin wechseln lassen und entfernen. Im Labor
    nicht prüfbar (CHR ohne Radios).
<!-- -->
64. ~~**„Erledigt“-Meldung für RouterOS-Versionen – Rest**~~ – *umgesetzt 2026-11-05 (Nachtrag DU4.2):* Ist keine
    Meldung offen, aber ein Gerät älter als die zuletzt gesehene Version, öffnet der nächste Tick sie wieder. Labor:
    `e2e.sh` Schritt 14f.
66. ~~**Bandbreitenlimit je Zone/VLAN (Gast-WLAN)**~~ (Wunsch des Nutzers, 2026-10-28) – *umgesetzt am selben Tag
    (DR2.7):* `vlans.rsc` → `"limit"="50M/10M"` (ganzes Netz, PCQ teilt gleich auf) und/oder `"limitClient"` (je
    Client, eigene PCQ-Typen); Fasttrack-Ausnahme je Netz (`src-`/`dst-address` vor der Fasttrack-Regel); gilt für
    allen gerouteten Verkehr des Netzes. `/queue/type` kennt kein `comment` → `cfmByName` (Schlüssel = Name
    `cfm-…`). Labor siehe DR2.7; auf Hardware am 2026-10-28/29 bestätigt (Gast-WLAN, DR2.7), Rest unter „Noch nicht
    mit echter Hardware getestet“. – *Anlass:*
    An einem Standort kommt ein Gast-WLAN (eigenes VLAN, Zone `guest`, Policy `"guest"="*wan"`, isoliert) dazu,
    das nur Internet bekommt und in der Bandbreite begrenzt sein soll. Bis das umgesetzt ist, läuft es ohne Limit.
    Das Framework kennt bisher keine Queues.
    * **Hindernis Fasttrack:** Die Rolle `router` setzt im `forward`-Block `fasttrack-connection` für alle
      `established,related` (`roles/router.rsc`, nach der `cfm-mgmt`-Regel). Fasttrack-Verbindungen umgehen
      Simple Queues und Queue Trees – eine begrenzte Zone muss davon ausgenommen sein, z.B. eine
      `accept`-Regel `established,related` mit `in-interface-list`/`out-interface-list` `Z-<zone>` vor dem
      Fasttrack (die Listen gibt es schon), oder Fasttrack nur für `connection-mark=!cfm-limit`. Die
      L3-Hardware-Offload ist auf Routern ohnehin aus (DR1.2) – die Last trägt die CPU; auf einer CRS418
      (Router + CAPsMAN) messen.
    * **Datenmodell (in der Session entscheiden, ≥ 2 Varianten vorlegen):** Feld an der VLAN-Zeile in
      `vlans.rsc`, z.B. `"limit"="20M/5M"` (Download/Upload aus Sicht der Clients). Offen: Limit **je Client**
      (PCQ, `pcq-rate` mit Klassifizierung `dst-address`/`src-address`, optional Gesamtgrenze `max-limit`) oder
      **gesamt für das Netz** (eine Simple Queue `target=<Netz>`) – oder beides (`"limit"` gesamt,
      `"limitClient"` je Client). Ggf. `burst`. Gilt nur für Zonen mit Router-Interface (nicht `l3=no`).
    * **Umsetzung:** Rolle `router` rendert `/queue/type` (PCQ je Richtung) und `/queue/simple` mit cfm-Tag
      (`$cfmEnsure`, Reconciler räumt ab, wenn `limit` wegfällt); bei VRRP auf jedem Router (nur der Master
      leitet weiter, schadet nicht). Reihenfolge der Simple Queues beachten (erste passende gewinnt; fremde
      Queues des Standorts nicht verdrängen). `$cfmCheck`: Syntax von `limit`, Warnung bei Zone ohne
      Router-Interface. Gilt das Limit auch für Verkehr zwischen Zonen (z.B. Gast → nichts, IoT → Broker)? Für
      Gast egal (nur `wan`), allgemein entscheiden.
    * **Labor:** `e2e.sh` – Queues/Typen und Fasttrack-Ausnahme vorhanden, nach Entfernen von `limit`
      aufgeräumt; Durchsatz messen (z.B. `/tool/bandwidth-test` oder `fetch` einer großen Datei zwischen zwei
      CHR durch den Router, mit und ohne Limit) – Messweg im Labor gibt es noch nicht. Gegenprobe: andere Zonen
      bleiben im Fasttrack.
    * **Doku:** DECISIONS (neue Nummer), Admin-Guide (`vlans.rsc`-Tabelle, Aufgabenliste „Gast-WLAN
      begrenzen“), danach am Standort im VLAN des Gast-WLANs einschalten (Site-Daten, Release).
<!-- -->
70. ~~**Umlaute im Syslog**~~ – *umgesetzt 2026-11-01 (DU3.4):* Log-Meldungen (`:log`, `$cfmLog`, `$cfmWarn`,
    `:error` des Agenten, Bootstrap) in ASCII, `rsc-check` Regel `log-ascii`; Labor-Greps angepasst; `e2e.sh` 405 grün. –
    Befund 2026-11-01 – RouterOS 7.25 ersetzt beim Remote-Logging jedes Nicht-ASCII-Byte
    durch `?` („Pr??fung ??? Ende“, Mitschnitt; ROUTEROS-EIGENHEITEN.md, Hardware). cfm-Meldungen enthalten Umlaute und
    Gedankenstriche („Apply vN fehlgeschlagen“ ist lesbar, „übersprungen“ nicht). Idee: Log-Texte des Agenten und
    der Rollen auf ASCII umstellen (ue/ae/oe, `-`), zumindest die Meldungen ab Schwere warning. Entschieden: ASCII für alle
    Log-Meldungen.
71. ~~**Dateiinhalte im Syslog**~~ – *umgesetzt 2026-11-01 (DU3.4):* `$cfmRelease`/`$cfmRollback` kopieren per
    `/file/copy` (wird nicht protokolliert), `$cfmRekey` eines Managers exportiert den Host-Key je User neu statt ihn
    per `/file/add` zu schreiben; `e2e.sh` 14g/14h prüft beides im RAM-Log von cm1/cm2; `e2e.sh` 405 grün. – Befund
    2026-11-01: Nicht Skript-Quelltext, sondern `/file/add contents=` des Release-Archivs (64 Dateien) – ein Release
    erzeugte auf dem Manager ~1070 Zeilen/~750 KB in einer Minute (Graylog). Geheime Felder schwärzt RouterOS
    (Test: User, PPP-Secret, SNMP-Community, WLAN-Security, WireGuard), Dateiinhalte nicht – beim Manager-Rekey
    wäre der private SSH-Schlüssel im Syslog gelandet (an diesem Standort lief seit dem Syslog keiner).

76. ~~**Umschaltbaren Port aus Home Assistant schalten, Zustand anzeigen**~~ – *umgesetzt 2026-11-06 (DP1.4.1),
    Labor `e2e.sh` 456 von 456, am Standort bestanden 2026-11-07 (v102):* Der Reset-Taster des hAP be³ Media löst
    unzuverlässig aus (normaler Druck 0 von 5, kräftiger 6 von 8) und meldet nichts zurück. Geräte mit `portSwitch`
    öffnen die API für `capsmanApi.from` wie der CAPsMAN, HA schaltet mit `tools/home-assistant/cfm_port.py` und
    liest den Zustand aus `<cfm>/port-<name>.txt`; jeder Wechsel geht als `ev` `port` an den Webhook
    ([home-assistant.md](home-assistant.md), Abschnitt 8). Am Standort: Schalten aus HA in beide Richtungen,
    Meldung am Webhook ([TESTSTAND.md](TESTSTAND.md#bestanden)).
77. ~~**Hostnamen am Manager ohne Groß-/Kleinschreibung**~~ – *umgesetzt 2026-11-08 (DM1.3), Labor `e2e.sh` 461
    von 461:* Befund am Standort 2026-11-07: `$cfmPlan host=hap-flur` → „unbekannter Host“, das Inventar kennt
    `hAP-Flur`. `$cfmHostName` (`mgr-core`) löst `host=` (auch `name=`, `sw=`, `ap=`) über `$cfmLower` zum Namen
    im Inventar auf; alle Befehle mit Hostnamen nutzen ihn, danach gilt nur der Inventarname (Pfade, Hostfile,
    Meldungen). `$cfmEnroll` und `$cfmRegister` nennen eine abweichende Schreibweise. `$cfmCheck` lehnt Namen ab, die
    sich nur in der Schreibweise unterscheiden. Labor: Plan/Show/Audit/Push mit `SW1`/`Sw1`, Kollision im Check.

## Frühere Fassungen

Stand 2026-11-03, bevor die Punkte in TODO.md auf ihren offenen Rest gekürzt wurden.

6. ~~**Plan-Modus**~~ – *erledigt (DG3.4):* `$cfmPlan host=<n>`, Probelauf gegen `work/` (ohne
   `*.post.rsc`). Offen: Grenze der Berichtsgröße bei sehr großen Plänen prüfen.
7. ~~**RouterOS-Versionspflege**~~ – *erledigt (DV1.2):* `$cfmUpgrade` (sofort oder einmaliges
   Wartungsfenster, auch Downgrade), Pakete vom Manager, automatisches Aufräumen. RouterBOOT-Firmware
   nach dem Update *erledigt*: `agent.rsc` erkennt `current-firmware != upgrade-firmware` (auf
   Hardware bestätigt: hAP AX² blieb nach einem RouterOS-Update sonst dauerhaft auf der alten
   Firmware stehen) und stößt selbst einen weiteren Neustart an. Zusatzpakete (`wifi-qcom-be`,
   `container`, `iot`, `ups` …) auf arm und arm64 auf Hardware gelaufen (2026-09-26). Offen: Pakete
   auf den Backup-Manager spiegeln. ~~Vorabversionen im Labortest~~ (TODO 36, erledigt).
<!-- -->
15. **WireGuard-Rolle** (Fernzugang, Standortkopplung; Schlüssel aus dem Vault).
16. ~~**WLAN-Ausbau**~~ – *erledigt (DW2.2):* PPSK per Multi-Passphrase-Gruppen, nächtliche
    Kanal-Neuwahl, Kanalbericht `$cfmChannels`. Offen: **WPA2/WPA3-Enterprise** (externer RADIUS
    oder User Manager); Kanalbericht und PPSK-VLANs mit echten APs testen (CHR hat keine Radios).
<!-- -->
20. **IoT-Isolation ausbauen** – *bis auf den Proxy erledigt 2026-10-12 (DP3.1):* `isolate="yes"` am VLAN
    mit Ausnahmen `isolateAllow`, Filter am Eingang der Client-Ports (Access-Ports mit `hw=no`,
    WLAN über die Liste `cfm-iso`), Freigaben mit Ports je Eintrag (`"ziel:tcp/443"`). Labor:
    `e2e-mlag.sh` Schritt 10, `e2e.sh` Schritt 9. Offen: Test an echten APs und Switches (siehe
    [TESTSTAND.md](TESTSTAND.md#offen-auf-hardware)), Proxy als Ziel. – (nach DR2.3/DR2.4): gerätespezifische Freigaben über kleinere Zonen
    erproben (eigenes VLAN/PPSK-Gruppe je Gerätegruppe); Freigaben nur für bestimmte Ports;
    Proxy als Ziel (transparent, Filter nach Domain) für Geräte, deren Cloud-Adressen häufig
    wechseln. WLAN-Client-Isolation trennt laut MikroTik nur Clients am selben AP – für
    isolierte Zonen über mehrere APs zusätzlich einen Bridge-Filter auf den APs (nur zum Gateway).
    – **Freigaben je Client** (Wunsch 2026-10-13): eine Freigabeliste nur für einzelne Clients einer
    Zone gelten lassen (Quelle = Namen aus `leases.rsc` oder IPs), statt für die ganze Zone und ohne
    eigenes VLAN. Anlass: Ein einzelnes Gerät braucht seine Cloud (z.B. ein PV-Wechselrichter),
    `iot="*allow:<Liste>"` erlaubt diese Ziele aber jedem Gerät der Zone. Bis dahin gilt sie zonenweit.
21. ~~**Weniger `/file/find` im Manager-Tick**~~ – *erledigt (DG4.1):* Zugriffe auf bekannte Dateinamen per
    `/file/get <Name>` statt Suche (CHR, 600 Dateien: 0,05 statt 8 ms), `cfmMB` je Sitzung gemerkt,
    `archiveKeep` standardmäßig 5, `$cfmRelease` lädt den Prüfer aus `work/`. Nachtrag 2026-10-11:
    auch die Geräte prüfen bekannte Namen per `get`; schneller wird das Apply erst durch DG4.4. Offen: auf Geräten mit
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
<!-- -->
37. ~~**Mindestgröße in `$cfmPkgFetch`**~~ – *erledigt (DV1.4):* NPK-Kennung (`1e f1 d0 ba`) statt
    Mindestgröße, `$cfmUpgrade … check=yes` listet fehlende Pakete samt Ablageort, der Auftrag nennt
    alle auf einmal. Offen: Prüfsummen von MikroTik (falls es eine Liste gibt). – Pakete unter 100 KB galten als kaputter Download und wurden
    gelöscht; echte Zusatzpakete sind kleiner (`ups` für `arm` ~45 KB). Grenze auf 20 KB gesenkt
    (Admin-Guide 8.6: Pakete für einen Manager ohne Internet von Hand ablegen).
    Besser: echte Prüfung (NPK-Kennung am Dateianfang oder Größe aus einer Prüfsummenliste von
    MikroTik). Außerdem: Ohne Internet am Manager müssen alle installierten Pakete eines Geräts vorab
    in `<pkgPath>/<ver>/` liegen – `$cfmUpgrade` könnte die fehlenden vor dem Auftrag auflisten.
<!-- -->
40. **Lokaler Fallback der APs (DW1.6), offene Punkte** (a vorbereitet, b/c/d/e erledigt) – *40a vorbereitet
    (DW1.8):* `fallback="yes"` an einer SSID schaltet `slaves-static` ein und hängt den virtuellen APs
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
    gelöst, DW1.6); lokales MLO wäre ein eigener Ausbau. ~~(d) Anzeige, wenn ein AP im
    Fallback läuft~~ – erledigt: Der Agent meldet `wfb` (CAP an, aber kein CAPsMAN verbunden) und
    schreibt eine Warnung ins Log, `$cfmStatus` zeigt „WLAN lokal“; eine Benachrichtigung hängt an 2. (e) ~~Dynamisches MLD~~ – ein
    CAPsMAN auf einem hAP be³ legte das MLD eines Wi-Fi-7-CAP beim ersten Kontakt abgeschaltet an
    (siehe ROUTEROS-EIGENHEITEN.md, Hardware); 2026-09-27 geprüft: von Hand eingeschaltet, blieb es nach einem
    Neustart des CAPsMAN an, und nach einer Neuprovisionierung (neue Namen, DU2.1) legte er es aktiv
    an. Nur beim allerersten Kontakt eines CAP prüfen.
<!-- -->
48. **RouterOS 7.25 (Labor mit 7.25rc1, 2026-10-11)** – Changelog-Punkte und Laborbefunde, die cfm
    berühren:
    * ~~SSH-Client prüft Host-Keys~~ – *erledigt (DS1.5).* Ein frisches oder zurückgesetztes 7.25 brach den
      Bootstrap ab („host key not trusted“), nach einem Update bleibt die Prüfung aus.
    * ~~Version ohne Kanal~~ – *erledigt:* Der Agent meldet `7.25.1 (stable)`; ohne Kanal machte
      `:deserialize` beim Manager eine IP-Adresse daraus (DV1.6).
    * **PoE-Firmware:** 7.25 aktualisiert die PoE-Firmware der 802.3at/bt-Geräte, laut Changelog mit
      kurzer Unterbrechung an allen PoE-Ports. Betrifft Switches, die APs per PoE versorgen: Update im
      Wartungsfenster, die APs starten mit.
    * **FT für MLD-Geräte** („wifi - add fast transition support for MLD devices“): DW2.3 hat MLO
      abgeschaltet, weil der hAP be³ als MLD kein FT anbot. Nach dem Update auf 7.25 mit einem Client
      prüfen, ob MLO mit FT jetzt geht (`wifi.rsc` `mlo`).
    * ~~**Globals über die API**~~ – *geprüft 2026-10-12 (7.25rc1 gegen 7.24.5):* Ein über die API
      gestartetes Skript setzt jetzt `:global`-Variablen in der gemeinsamen Umgebung (7.24.5: nicht).
      Lesen kann `/system/script/environment` weiterhin nur ein User mit `write` und `policy` (getestet
      mit read+api+rest-api+test, +policy, +write, +sensitive: „not enough permissions“). Für den
      Gast-Schalter (DW4.1) ändert sich nichts: HA liest den Zustand weiter per API (bis DW4.2 aus den Regeln,
      seitdem an den Interfaces); `cfmSsid<key>`
      auf der Konsole stimmt ab 7.25 auch nach dem Schalten aus HA.
    * **WebFig** zeigt Dateiinhalte weiter nicht an (DT3.1, Lesezeichen-Editor).
    * **Laborläufe mit 7.25rc1, 7.25rc2 und 7.25 sowie das Update der Standorte auf 7.25:** siehe
      [TESTSTAND.md](TESTSTAND.md).
    * **Changelog-Durchsicht:** 7.25rc2 (2026-10-17, für einen Standort) – nichts, was ein Update vor einem
      Router-Umbau nötig macht; das PoE-Firmware-Update (kurze Unterbrechung aller PoE-Ports) gehört in ein eigenes
      Wartungsfenster; unter rc1 meldete ein Nutzer hAP-ax³-CAPs mit fehlenden SSIDs (zu rc2 noch keine Meldungen).
      7.25 stable – Punkte für die Hardware: „ethernet - fix occasional packet loss on hAP be3 Media“ (Kabel-Ports an
      einem Standort aus, bis 7.25 läuft), „wifi - add more steering debug logs“ (802.11v-Vorschläge bisher nicht im
      Log), „wifi-qcom - fix disconnects during fast transition roaming“, FT für MLD (DW2.3), PoE-Firmware 802.3at/bt
      (siehe oben, Wartungsfenster).
<!-- -->
51. ~~**Kanalplanung mit den anderen Funknetzen im 2,4-GHz-Band**~~ (Idee des Nutzers, 2026-10-13) –
    *erledigt 2026-10-16 (DW3.5):* `wifi.rsc` → `others`, Kosten mit Nähe-Gewicht (auch Bluetooth und
    Milight), Kanalvorschlag für Zigbee/Thread mit `auto`, Kanalsatz 1/5/9, Warnung in `$cfmCheck`.
    Offen: Energie-Messungen der Koordinatoren einbeziehen. Befund und Herleitung:
    `$cfmWifiScan`/`$cfmChannels` (DW3.2) sehen nur WLAN. Im selben Haus funken oft auch Zigbee, Thread,
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

    Folgerungen für die Kanalsätze von DW3.2 (umgesetzt in DW3.5):
    * **1/5/9/13** deckt 2402–2482 MHz lückenlos ab, jeder 802.15.4-Kanal liegt in einem WLAN-Kanal.
      Frei wird einer nur, wenn ein WLAN-Kanal im ganzen Haus frei bleibt. Ohne 13 (also **1/5/9**)
      sind 24–26 frei, 23 liegt nur 2 MHz über WLAN 9. Den Satz 1/5/9 probiert `$cfmWifiScan` seit DW3.5
      mit; Sätze aus allen Kombinationen abzuleiten wurde nicht gewählt (Rechenzeit auf dem Manager, DW3.5).
    * **1/6/11:** 15 und 20 liegen in den Lücken, 25 und 26 über 11 (11 endet 2 MHz vor 25). Daher
      stammt die übliche Zigbee-Empfehlung 15/20/25. Auch BLE 38 und 39 liegen außerhalb.
    * Milight RGBW: unter 1/5/9/13 liegen alle drei Kanäle in WLAN-Kanälen, unter 1/5/9 ist 2473 MHz frei.
    * Ein AP direkt neben einem Koordinator kann dessen Empfänger auch auf einem freien Kanal
      übersteuern: 1–2 m Abstand.

    Entschieden 2026-10-16 (DW3.5): Kosten mit Nähe-Gewicht, Daten in `wifi.rsc`, Bluetooth und Milight
    als Kosten. Noch offen: ob Messungen der Koordinatoren einfließen (Energie-Scan je 802.15.4-Kanal aus
    den ZHA-Diagnosedaten bzw. `commissioner energy` in OpenThread; die MikroTik-Radios sehen nur WLAN).
    Quellen: [Zigbee2MQTT, Zigbee-Netz](https://www.zigbee2mqtt.io/guide/configuration/zigbee-network.html),
    [OpenThread Channel Manager](https://docs.silabs.com/openthread/2.5.0/openthread-api/api-channel-manager),
    [TI SWRA475A, BLE-Koexistenz mit WLAN](https://www.ti.com/document-viewer/lit/html/SWRA475A/coexistence-swra4755506),
    [Argenox, BLE Advertising](https://argenox.com/library/bluetooth-low-energy/ble-advertising-primer),
    [esp8266_milight_hub, Funkparameter](https://github.com/sidoh/esp8266_milight_hub/blob/master/lib/Radio/MiLightRadioConfig.cpp),
    [Milight-Funkprotokoll (Hackaday)](https://hackaday.io/project/5888-reverse-engineering-the-milight-on-air-protocol/log/18456-in-the-radio-domain).
<!-- -->
54. **LibreNMS anbinden: SNMPv3 und Syslog** (entschieden 2026-10-16) – *umgesetzt 2026-10-29 (DU4.3):* `global.rsc` →
    `snmp` (Community authPriv nur von `from`, `public` aus, Passwörter `snmp.auth`/`snmp.priv` im Vault),
    `syslogFormat` (Standard `syslog`), Hostfile `location`; Admin-Guide 8.12. *SNMP an einem Standort bestanden
    2026-10-30* (Befunde: hAP be³ meldet nur CPU-Temperatur und -Takt, keine Spannung/Leistung – die liefert der
    PoE-Switch je Port als Sensor; der CAPsMAN (wifi-Paket, 7.25) zeigt unter `…14988.1.1.1` nur drei Zähler des alten
    `wireless`-Pakets mit 0, keine Clients – Signal/SSID bleiben bei `$cfmFind`/cfm-Monitor; direkt am CAP noch
    ungeprüft). ~~**Offen:** Syslog~~ (*2026-11-01 über Graylog, LibreNMS liest mit, 8.15*); **Offen:** Geräte per LibreNMS-API aus dem Inventar anlegen (Nutzer: später; von Hand geht
    `lnms device:add --v3` mit den v3-Daten aus den Einstellungen, Admin-Guide 8.12). – LibreNMS übernimmt Verlauf und
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
<!-- -->
58. **Schaltbare SSID ohne Unterbrechung der übrigen** (entschieden 2026-10-17) – *(a) umgesetzt 2026-10-20
    (DW4.2), seit 2026-10-21 an einem Standort ausgerollt, Test beim ersten Schalten offen:* Provisioning mit
    `create-enabled`, die Skripte schalten nur die
    Interfaces der SSID; Umstieg und Rückweg im Admin-Guide 6.8. Auf Hardware klären: Startet das Abschalten
    eines virtuellen AP das Radio neu? ~~Was macht erneutes Provisionieren bei vorhandenen festen Interfaces
    (neue SSID in `wifi.rsc`, geänderter Pin)?~~ *Geklärt 2026-10-26 (DW4.3):* RouterOS legt sie neu an,
    eingeschaltet; der Apply warnt bei veralteten CAP-Radios, `cfm-reprov` provisioniert nacheinander. Aufräumen der festen Interfaces eines abgebauten AP (bisher von
    Hand, Admin-Guide 7.4); bleiben beim Abschalten von `capsmanRadios` feste Interfaces der eigenen Radios
    stehen? Zusammenspiel mit `slaves-static` (DW1.8). (b) bleibt der Rückfall. – Ausgangslage: `cfm-ssid-<key>-on/-off`
    (DW4.1) ändern die Provisioning-Regeln und provisionieren alle Radios neu; das baut je Radio Master und
    alle virtuellen APs neu auf, alle SSIDs aller APs sind gleichzeitig ~3 s weg. Zwei Ansätze, in dieser
    Reihenfolge: (a) **statische Interfaces** – Provisioning mit `action=create-enabled` statt
    `create-dynamic-enabled`; feste Interfaces auf dem CAPsMAN lassen sich einzeln ab-/anschalten
    (dynamische nicht: „can not change dynamic interface“). Auf Hardware prüfen (CHR hat keine Radios):
    Betrifft das Abschalten nur den virtuellen AP, oder startet RouterOS das Radio trotzdem neu? Dazu
    klären: Aufräumen fester Interfaces, wenn ein AP verschwindet; Namen (`name-format`) und die Zuordnung in
    Home Assistant; Zusammenspiel mit `slaves-static` (DW1.8). (b) Falls (a) nichts bringt: **nacheinander
    provisionieren** – je AP `/interface/wifi/radio/provision` mit einigen Sekunden Abstand, damit nie alle
    APs gleichzeitig dunkel sind und Clients zu einem Nachbarn wechseln können; die Unterbrechung je AP bleibt.
<!-- -->
63. ~~**NTP-Umleitung je VLAN**~~ (Wunsch des Nutzers, 2026-10-23) – *umgesetzt 2026-10-23 (DN2.2):* OpenBeken-Lampen
    haben einen fest eingebauten NTP-Server und bekommen in der IoT-Zone ohne Internet keine Zeit. `vlans.rsc`
    `"ntp"="redirect"` leitet `udp/123` aus dem VLAN an jedes Ziel außer dem Router auf dessen NTP-Server um.
    Am 2026-10-24 an einem Standort ausgerollt (Regel zählte sofort). Offen: Zeit an einer Lampe prüfen.
64. ~~**„Erledigt“-Meldung für neue RouterOS-Versionen (`ros`)**~~ – *umgesetzt 2026-10-27 (DU4.2):* `ros` als Zustand
    (`roso`), `off` sobald alle aktuell bzw. „überholt“, Felder `key`/`ver`; offene Frage entschieden: keine
    Ausnahmeliste, ausgelassene Geräte beim Empfänger abhaken. Empfänger in HA: HA-Session. – (Wunsch des Nutzers, 2026-10-26, aus der
    HA-Session) – *Anlass:* Home Assistant macht aus jeder `action`-Meldung einen Eintrag in einer
    To-do-Liste, der täglich im Bericht steht, bis man ihn abhakt. `ros` kommt nur einmal (`"state":"once"`),
    ein „wieder ok“ gibt es nicht. Folge an einem Standort: Der Eintrag zu 7.24.5 (11.10.) stand nach dem
    Update weiter als erster Punkt im Bericht, die neue 7.25 (24.10.) darunter wurde übersehen. *Ziel:* Sobald
    kein aufgenommenes Gerät mehr älter ist als die gemeldete Version, meldet cfm das einmal, der Empfänger
    schließt die Aufgabe. Vorschlag (Details entscheidet die Umsetzung):
    * **`ros` als Zustand statt einmalig:** beim Melden `st="on"` statt `once` und die offene Version in
      `meta/notify.dat` merken (z.B. `roso`, mit Präfix `v` wie `rosv`, wegen `:deserialize`).
    * **Prüfung „alle aktuell“ in jedem `$cfmNotifyTick`**, nicht nur beim täglichen Abruf: dieselbe Schleife
      wie beim Melden (`status.dat` `ros`, `$cfmVerGe`), braucht kein `upgrade.mikrotik.com`. Damit kommt die
      Meldung kurz nach dem letzten `$cfmUpgrade`. Ist kein Gerät mehr älter als `roso`: `$cfmNotify ev="ros"
      host="" st="off" msg="RouterOS <ver> auf allen Geräten"` und `roso` leeren. Scheitert die Zustellung,
      bleibt `roso` stehen und der nächste Tick versucht es erneut (wie bei den übrigen Zuständen).
    * **Neuere Version, während eine ältere offen ist** (z.B. 7.25.1 vor dem Update auf 7.25): erst `off` für
      die alte („überholt durch 7.25.1“), dann `on` für die neue. Dann bleibt beim Empfänger nie mehr als
      eine RouterOS-Aufgabe offen.
    * **Schlüssel im JSON:** neues Feld `key`, damit der Empfänger `off` und `on` ohne Textvergleich
      zuordnet: `"<ev>:<host>"` wie in `meta/notify.dat`, bei `ros` `"ros:<ver>"`. Zusätzlich bei `ros` das
      Feld `ver`. Bestehende Empfänger, die nur `level`/`device`/`message` lesen, laufen unverändert weiter.
    * **Bewusst ausgelassene Version:** Der Nutzer hakt die Aufgabe beim Empfänger ab. cfm meldet dieselbe
      Version nicht erneut (bleibt wie heute über `rosv`). Kommt später doch das `off`, findet der Empfänger
      keine offene Aufgabe mehr, das ist harmlos.
    * **Offene Frage:** Geräte, die absichtlich auf einer älteren Version bleiben (z.B. 16-MB-Geräte, siehe
      38), verhindern das `off` dauerhaft. Reicht Abhaken von Hand, oder braucht es eine Ausnahmeliste
      (z.B. `rosHold` in `global.rsc`)? Ebenso offen: Ein später aufgenommenes älteres Gerät öffnet heute
      keine neue Meldung.
    * **Doku:** Admin-Guide (Tabelle der Meldungsarten, `ros`, Felder) und `docs/home-assistant.md`
      Abschnitt 7 (Felder `state`, `key`, `ver`, Hinweis: `off` schließt die Aufgabe; Beispiel für
      `todo.update_item … status: completed`). Labor: `on` beim Melden, `off` genau einmal nach dem Update
      aller Geräte, überholte Version während `on`, Zustellfehler mit Wiederholung.
    * **Empfänger an einem Standort (macht die HA-Session):** `automation.mikrotik_meldung_empfangen` legt
      `key` in die Beschreibung der Aufgabe und hakt bei `state=off` die offene Aufgabe mit diesem Schlüssel
      ab. Das gilt dann auch für `update` und `lizenz`, die schon heute ein `off` schicken, deren Aufgabe
      in HA aber bisher offen bleibt. Bitte der HA-Session über den Nutzer melden, wenn Feldnamen und
      Release stehen.
65. **Fremdgerät mit der Haupt-SSID bzw. am gemeinsamen Dock ins Gäste-VLAN** (Wunsch des Nutzers, 2026-10-26)
    – *Anlass:* Ein Firmen-Laptop soll nicht ins Hauptnetz, ist aber kein richtiger Gast (kennt die
    Haupt-SSID). Er hängt zeitweise an derselben Dockingstation wie der Admin-Laptop, der dort über
    NetworkManager das ungetaggte Haupt-VLAN und getaggt alle übrigen VLANs nutzt (auch MGMT). Zwei Teile:
    * ~~**(a) WLAN: VLAN je MAC über die Access-List**~~ – *umgesetzt 2026-10-27 (DW2.6):* `"wifi"="yes"` an der
      Lease, Einträge je MAC vorn im Block `wcut`; auf Hardware offen: Weitergabe von `vlan-id` an die CAPs,
      FT-Roaming. – *Vorschlag war:* `/interface/wifi/access-list`
      mit `mac-address` und `vlan-id` (am CAPsMAN angenommen, Probe 2026-10-26). Geht auch mit WPA3 und FT;
      PPSK scheidet für die Haupt-SSID aus, Multi-Passphrase verlangt WPA2 (DW2.2). Vorschlag: aus den Leases
      ableiten. Eine Lease mit MAC in einem VLAN, das nicht das VLAN der SSID ist, ergibt einen Eintrag vor
      den Signal-Grenzen (`wcut`/`wacl`, DW2.5), mit denselben Grenzen; oder ausdrücklich in `wifi.rsc`
      (`"clients"={"<mac>"={"vlan"=175}}`). Auf Hardware klären: Gibt der CAPsMAN `vlan-id` aus der
      Access-List an die CAPs weiter (wie bei PPSK)? Roaming/FT zwischen APs; Clients mit zufälliger MAC je
      SSID (Windows: stabil je Netz) – `$cfmCheck` könnte auf lokal verwaltete MACs hinweisen. Labor: Regeln
      und Reihenfolge (CHR ohne Radios).
    * **(b) Kabel am gemeinsamen Dock** – *wartet auf 802.1X* (WPA-Enterprise/RADIUS, TODO 16): Port mit
      dot1x und MAC-Auth, VLAN vom RADIUS. Die einfachen Wege tragen nicht: Eine Switch-Regel je MAC
      (`src-mac-address` + `new-vlan-id`; das Menü gibt es auf dem QCA-8386 eines hAP be³, Wirkung
      ungetestet) scheitert, wenn das Dock für beide Laptops mit seiner eigenen MAC sendet (ohne
      MAC-Passthrough). Den Port ungetaggt ins Gäste-VLAN zu legen (`hybrid:<gast>`, Admin-Laptop dann
      mit getaggtem Haupt-VLAN) wäre ohne Code möglich, schickt aber jedes Gerät ohne NM-Profil ins
      Gastnetz. **Rückfall, wenn 802.1X zu lange dauert oder zu aufwändig wird:** das Port-Profil des
      Dock-Ports umschalten – von Hand oder automatisiert über Home Assistant, z.B. nach dem Muster der
      Schalt-Skripte (DW4.1/DW4.2: Skript `cfm-port-<name>-<profil>` mit `dont-require-permissions`, Zustand
      in einer Datei, die jeder Apply übernimmt, damit ein Release nicht zurückschaltet).
<!-- -->
67. **VIP als Gateway, obwohl der Internet-Router im selben Netz steht** (Befund an einem Standort und Wunsch des
    Nutzers, 2026-10-31) – *umgesetzt 2026-10-31 (DR3.2):* `vlans.rsc` → `"asymRouting"="internet"` am WAN-VLAN
    (Standard aus): `raw`-Regel `notrack` für Verkehr aus dem Netz ins Internet, Hinweg über die Router, Antwort
    direkt vom Internet-Router; Admin-Guide 8.13. **Offen:** Hardware-Test (Server mit Gateway VIP: TCP ins
    Internet, Ausfall des Internet-Routers – interne Wege bleiben, VRRP-Wechsel), Portfreigabe auf einen Host mit
    Gateway VIP. **Ziel danach:** Transfernetz für den Internet-Router (dann VIP für alle, zweiter Anschluss als
    Backup möglich), der Schalter entfällt.
68. **DNS der Router: Upstream, Adblock, Ausnahmen, Weiterleitung je Domain, Abfrage-Log** (Wunsch des Nutzers,
    2026-10-31) – *umgesetzt 2026-10-31 (DN3.1):* optionale `dns.rsc` (Admin-Guide Kapitel 4). ~~**Offen:**
    Abfrage-Log über Syslog~~ – *erledigt 2026-11-01:* `log.syslog=yes` an Graylog, eigener Stream per Regex auf
    `query from`/`done query:`/`local query:`/`[adlist]`, Index-Set eine Woche (Admin-Guide 8.15; ein Router mit vielen
    Clients ~4,6 Zeilen/s, ~270 MB Index am Tag). Hardware: Adlisten laden und RAM auf vier Routern ok, 2026-10-31. **Offen:** die
    Resolver-Container eines Standorts nach Parallelbetrieb abbauen; Selbstbedienung für Clients siehe 69;
    Namensschema der Standorte für `forward` (später, mit einem Standort-VPN der Router); DoH als Option.
69. **DNS-Selbstbedienung für Clients: eigene Abfragen sehen, gesperrte Domain freischalten** (Wunsch des Nutzers,
    2026-10-31, DN3.2) – *umgesetzt am selben Tag:* `dns.rsc` `self` (Admin-Guide Kapitel 4), Lesezeichen cfm-DNS
    (`tools/editor/cfm-dns.js`), Skript `cfm-dnsreq` der Rolle `router`, Labor `e2e.sh` Schritt 14l. *Hardware
    bestanden 2026-10-31* (hAP ax³ als VRRP-Master, 7.25: Freischaltung nach 3 s, dauerhaft/löschen ok, 20 000
    Log-Zeilen in 2,3 s gelesen). Befund: Nach `$cfmSecret` verteilt erst der nächste Tick das Passwort – sofort
    mit `$cfmSecretPush host=` (Admin-Guide 8.14). **Offen:** `www-ssl` für die Anmeldung; befristete Freischaltung auch auf den anderen Routern (VRRP-Wechsel);
    `mgr-check.rsc` nähert sich der 60-KB-Grenze (55 KB) – beim nächsten Prüfblock aufteilen.
<!-- -->
73. **Feature-Module (DG4.6)** (Wunsch des Nutzers, 2026-11-02) – *umgesetzt am selben Tag, Labor grün, Hardware teils:*
    `lib/<Rolle>.<Feature>.rsc`, geladen per `$cfmFeat` nur bei Nutzung: `router.dns` (+ Skript-Rumpf
    `router.dnsreq`), `router.wg`, `router.limit`, `base.sshkeys`, `base.snmp`, `base.iso`, `base.bond`; Skript-Rümpfe
    des CAPsMAN `capsman.ssid`, `capsman.ssidcheck`, `capsman.reprov` (`$cfmBody`).
    `roles/router.rsc` 41,6 → 27,3 KB, `roles/base.rsc` 38,8 → 27,6 KB. `tools/upload-seed.sh` lädt nur die
    Module hoch, die die Site nutzt (`tools/feature-module.py`), und entfernt die übrigen auf dem Manager;
    `$cfmCheck` stoppt ein Release, dem ein genutztes Modul fehlt. Grün: `rsc-check` (Regel `feature-modul`),
    `feature-module-test.py`, `upload-seed-test.py` (nachgebauter SFTP-Server). Das CHR-Labor lief in der
    Cloud-Sitzung nicht (kein KVM, `download.mikrotik.com` gesperrt).
    * *Labor 7.25 (2026-11-02, erledigt):* `e2e.sh` 410, `e2e-vrrp.sh` 137, `e2e-mlag.sh` 72, `e2e-onboard.sh` 14 –
      alle ohne Fehler (Labor-Skripte mit `--all-features`). Übergangsprobe alter Stand (vor DW1.11) → DG4.6 ohne
      `--all-features` (Modulauswahl aus den Seed-Daten): Release ringweise und zweites Release ok.
    * *Hardware, Standort ohne DNS-Selbstbedienung (2026-11-02, erledigt):* `upload-seed.sh` ließ genau die sieben
      ungenutzten Module weg (bond, iso, snmp, ssid, ssidcheck, dns, dnsreq), `$cfmCheck` ohne Fehler, Release
      ringweise inkl. Router ohne Rollback, zweites Release mit neuem Manager-Code ok; kein `cfm-dnsreq`, WireGuard,
      Queues, SSH-Schlüssel und `cfm-reprov` unverändert.
    **Offen:**
    * Hardware an einem Router mit `dns.rsc`: `/system/script/get cfm-dnsreq source` prüfen
      (Kopf `:local dur …`/`:local deny …` für cfm-DNS, Rumpf als Funktion `$dnsreq`), cfm-DNS-Freischaltung einmal
      durchspielen; dort auch die Listen „nicht hochgeladen“/„entfernt“ von `upload-seed.sh`.
    * Nachtrag: Die WLAN-Skripte des CAPsMAN kommen ebenfalls aus Rümpfen (`capsman.ssid`, `capsman.ssidcheck`,
      `capsman.reprov`, `$cfmBody`); Labor `e2e.sh` Schritt 14 (schaltbare SSID, Auto-Aus, `cfm-reprov`) prüft sie.
    * Weitere Kandidaten: `mgr-check.rsc` (57 KB) aufteilen, bevor die
      60-KB-Grenze greift (`$cfmRelease` lädt den Prüfer aus `work/` – dann beide Dateien). Nicht empfohlen:
      RouterOS-Update/Firmware aus dem Agent (DG4.3: heikelster Pfad).

## Behobene Fehler

* ~~**`cfm-drop` für DHCP-Discover beim Umschalten eines Ports**~~ – *behoben 2026-11-08 (DR2.5.1):* Der input-Block
  `fwb` verwirft `udp 68->67` mit Quelle `0.0.0.0` still. (Befund 2026-11-06 an einem Standort, hAP be³ Media 7.25:
  bei jedem Umschalten einmal `cfm-drop input: in:ether5 … 0.0.0.0:68->255.255.255.255:67`.)

* ~~**Manager-Funktionen fehlen nach einem Neustart bis zum ersten Tick**~~ – *behoben 2026-11-08 (DM2.1.1):*
  Scheduler `cfm-mgr-boot`. (Befund beim Ausfalltest an einem Standort, 2026-11-08.)

* ~~**`upload-seed.sh --site` lädt Labor-Hostfiles der Vorlage auf den Manager**~~ – *behoben 2026-11-08 (Nachtrag
  DT2.2):* Mit `--site` und Overlay kommen die Hostfiles nur noch aus dem Overlay; Dateien direkt in `work/`, die die
  Vorlage ergänzt, nennt das Skript (Test in `upload-seed-test.py`). (Befund an einem Standort, v104: `hosts/ap1.rsc`,
  `cm1.rsc` … standen auf dem Manager und in jedem Release; dort gelöscht.)

* ~~**Taster startet das Umschalt-Skript nicht**~~ – *im Code behoben 2026-11-06 (Nachtrag DP1.4), Release offen:*
  Die Rolle setzt `on-event="/system script run cfm-port-<name>-toggle"` zusammen mit `hold-time=0s..1m`. (Befund
  hAP be³ Media, 7.25: Mit `on-event=<Skriptname>`, wie die MikroTik-Doku es beschreibt, startete kein Druck etwas,
  `run-count` blieb 0, kein Log; auch von Hand gesetzter Code wirkte erst nach einem `set hold-time=…`.)

* ~~**Benachrichtigung doppelt, wenn `$cfmNotifyTick` zweimal zugleich läuft**~~ – *behoben 2026-11-06 (Nachtrag
  DU4.1):* Sperre `cfmNotBusy`, ein zweiter Aufruf wartet bis 60 s, eine Sperre älter als 5 min verfällt. (Befund
  Labor 7.25.1, `e2e.sh` „kein zweites Mal“: Ein Aufruf von Hand neben dem Scheduler-Tick las dasselbe
  `notify.dat`, jede Meldung ging gut eine Sekunde versetzt zweimal hinaus.)

* ~~**Apply scheitert am Manager-Modul: „no such item (/file/get)“ in `roles/manager.rsc`**~~ – *behoben 2026-10-29:*
  `$cfmGetFiles` überschreibt geänderte Dateien per `/tool/fetch`, gelöscht werden nur Dateien, die das Manifest
  nicht mehr nennt (DG4.5); im CHR nicht nachstellbar, beim nächsten Framework-Update
  eines Standorts beobachten. (Befund 2026-10-28,
  Hardware: CRS418 als Router + Manager, 7.25, Framework-Update mit geänderten `mgr-check`/`mgr-show`):
  `failed roles/manager.rsc: Script Error: no such item (/file/get; line 26)` → Rollback per Backup-Load, Neustart.
  Nach dem Neustart lagen alle Dateien in `cfm/dl` mit dem neuen Stand und ließen sich über den Namen lesen.
  Vermutung: `$cfmGetFiles` löscht eine geänderte Datei und lädt sie unter demselben Namen neu; RouterOS hält die
  gelöschte noch als Eintrag ohne Inhalt (Eigenheit, siehe ROUTEROS-EIGENHEITEN.md), `/file/get <Name>` trifft ihn.
  Beheben: geänderte Dateien nicht vorher löschen (`/tool/fetch` überschreibt), nur Dateien entfernen, die nicht
  mehr im Manifest stehen; ggf. `/file get` der Rolle `manager` bei „no such item“ nach kurzer Pause wiederholen.
  Labor: im CHR bisher nicht aufgetreten (e2e lädt Manager-Module bei jedem Framework-Update).
* ~~**Neue SSID: CAPsMAN bis zum nächsten Manager-Tick aus, eigene Radios ohne virtuelle SSIDs**~~ – *behoben
  2026-10-29 (DW1.11):* `$cfmPush` fasst bei CAPsMAN-Geräten alle 30 s nach (`cfm-mgr-follow`) und pusht die Secrets,
  sobald einer SV 0 meldet; schaltet der Push den CAPsMAN ein und hat er eigene Radios, folgt dort ein erzwungener
  Apply. Labor: `e2e.sh` Schritt 14 (6-GHz-Profil); die eigenen Radios nur auf Hardware. (Befund 2026-10-28,
  Release mit drei neuen SSIDs, Passphrasen vorher im Vault): Erst der Apply legt die Security-Profile `cfm-<ssid>` an,
  ein Secret-Push davor geht für sie ins Leere. Der Apply auf dem CAPsMAN schaltet ihn deshalb aus (`$cfmPskMissing`)
  und fordert den Push an (SV 0); der kommt erst mit dem nächsten Manager-Tick (bis 10 min, so lange kein WLAN aus
  dem CAPsMAN). Außerdem überspringt die Rolle bei ausgeschaltetem CAPsMAN die eigenen Radios (`capsmanRadios`), der
  Push schaltet ihn zwar ein, provisioniert sie aber nicht – sie behalten bis zum nächsten Apply (Reapply 1 d) nur den
  Master. Abhilfe von Hand: `$cfmSecretPush`, `$cfmPush host=<cm> force=yes`, `cfm-reprov`. Beheben: Manager pusht
  sofort, wenn ein Gerät nach dem Apply SV 0 meldet (`$cfmCollect`/Tick des Release-Ablaufs), und der Secret-Push
  provisioniert die eigenen Radios, wenn er den CAPsMAN einschaltet (oder fordert einen Apply an).
* ~~**Erzwungener Apply einer `bad`-Version lässt `bad` stehen**~~ – *behoben 2026-10-29:* Der Agent löscht `bad`
  nach einem erfolgreichen Apply derselben Version; Labor: `e2e.sh` Schritt 7. (Befund 2026-10-28, gleiche Gelegenheit):
  `$cfmPush host=<g> force=yes` wendete v31 an (`res=ok`), `bad` blieb v31 – `$cfmStatus` zeigt „bad v31 ok“, die
  Benachrichtigung `apply:<g>` bleibt offen, der tägliche Reapply wird als „fehlerhaft markiert“ übersprungen. Erledigt
  sich mit dem nächsten Release (ältere `bad` blendet der Manager aus). Beheben: im Agent nach erfolgreichem Apply
  `bad` löschen, wenn es die angewendete Version ist; Labor: `e2e.sh` Schritt 7 (force nach bad) um den Status ergänzen.
* ~~**Labor: Die MNDP-Prüfung in `e2e.sh` Schritt 14 schlägt vereinzelt fehl**~~ – *behoben 2026-10-27:* wartet bis
  70 s auf das erste Paket. (2026-10-20, ein Lauf von vier,
  drei Labore parallel): In den 40 s mit `pvid=10` an cm1:ether3 kam kein MNDP-Paket von cm2 an (Zähler der
  Regel 0, kein Log), obwohl `discover-interval` 30 s ist; derselbe Code bestand im Parallellauf. Wieder
  2026-10-25 (7.25, zwei Labore parallel; von Hand nachgestellt bestanden). Beheben:
  statt fest 40 s auf das erste Paket warten (bis etwa 70 s).
* ~~**Labor: `Rekey SFTP cm2` in `e2e.sh` Schritt 14g schlägt vereinzelt fehl**~~ – *behoben 2026-10-27:* wartet,
  bis auf cm2 kein Agent läuft, und wiederholt bei „gerade nicht möglich“ einmal. (2026-10-23, ein Lauf von zwei
  mit demselben Code): `$cfmRekey host=cm2 sftp=yes` meldete `busy` – auf cm2 lief gerade der Agent (bzw. stand
  `cfm-watchdog`), dann lehnt der Rekey bewusst ab (`mgr-vault.rsc`); die Folgeprüfung „cfmd-cm2 unverändert“
  scheitert mit. Beheben: im Test vorher warten, bis auf cm2 kein Agent läuft, oder `$cfmRekey` wiederholt
  nach kurzer Pause.
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
* ~~**Steering `count`="unlimited" ist nie idempotent**~~ (Befund 2026-10-22 an einem Standort):
  RouterOS liest `transition-request-count=unlimited` als Zahl 4294967295 zurück, `$cfmSame` verglich sie
  mit `[:tonum "unlimited"]` – jeder Plan des CAPsMAN meldet `geändert: … wst:<n>: transition-request-count`
  (set=1, harmlos, die eigenen Radios werden dabei nicht neu provisioniert). – *behoben am selben Tag:*
  `$cfmSame` nimmt „unlimited“ bei Zahlen als 4294967295; Labor `e2e.sh` (Einzeltest neben dem für Dauern).
* ~~**Nach dem Schalten einer SSID (DW4.1) baut der nächste Apply das Provisioning neu**~~ (Befund 2026-10-19,
  7.24.5): Die Skripte `cfm-ssid-<key>-on/-off` ändern `slave-configurations` direkt, die Signatur des
  Regelblocks `wprov` (`sig=` im Kommentar) und `<cfm>/wifi-local.txt` stammen aber vom letzten Apply. Der
  nächste Apply meldet `Regelblock /interface/wifi/provisioning wprov neu aufgebaut` mit gleichem Inhalt und
  provisioniert die eigenen Radios des CAPsMAN neu (`capsmanRadios`, ~3 s ohne WLAN). Beheben: die Skripte
  auch Signatur und Merker nachführen lassen, oder Signatur und Merker ohne die schaltbaren SSIDs bilden
  und deren Zustand getrennt vergleichen. – *behoben 2026-10-20 (DW4.1):* Die Skripte führen beides nach
  (Tabelle je Kombination der Schaltzustände aus dem Apply); passen Regeln und Zustand nicht zusammen,
  startet der Apply das Schalt-Skript. Labor: `e2e.sh` Schritt 14. *Seit DW4.2 gegenstandslos:* Schalten
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
* ~~**`$cfmAudit op=purge` meldet FEHLER für dynamische Folgeobjekte**~~ – *behoben 2026-10-27:* `get` auf ein
  eben verschwundenes Objekt liefert ohne Fehler nur `.id`, das Audit prüft jetzt, ob es das Objekt noch gibt;
  zugleich verschoben solche Zeilen die Nummern (`sel=A2` konnte ein anderes Objekt treffen als im Bericht). Labor: `e2e.sh`
  Schritt 5. – (Befund 2026-10-17: ein
  VLAN-Interface samt Adresse entfernt, zwei FEHLER-Zeilen für Objekte, die RouterOS dazu dynamisch
  angelegt hatte): Sie verschwinden mit dem entfernten Objekt, das Löschen danach scheitert.
  Harmlos, aber verwirrend; dynamische Einträge beim Purge überspringen.
* ~~**`$cfmStatus` zeigt bis zum nächsten Manager-Tick den alten Stand:**~~ – *behoben 2026-10-20 (DU1.5):*
  `$cfmStatus` holt den Status von Geräten mit Ist ≠ Soll oder ausstehendem Apply vorher selbst ab. Labor:
  `e2e.sh` Schritt 11. – Nach einem Release stand ein
  Gerät noch mit der alten Version da, obwohl es längst angewendet hatte; erst `$cfmCollect` holte den
  Status. Vorschlag: `$cfmStatus` holt veraltete Status selbst ab (oder weist auf `$cfmCollect` hin).
* ~~**Labor 2026-10-11: cm1 nimmt keine Anmeldung mehr an.**~~ – *geklärt und behoben 2026-10-12:* Wettlauf
  zwischen dem Apply des Managers und `$cfmLoadData` (DM2.3, Sperre
  `cfmApplyBusy`); nachgestellt in Labor B (Push an cm1 plus paralleles `$cfmLoadData` → `adminUser`
  aus `global.rsc` statt aus dem Hostfile), mit der Sperre nicht mehr, `e2e.sh` Schritt 14i. Der
  Fehler bestand schon vorher; unter Last (zwei Labore parallel) wurde das Fenster groß genug.
  Ursprünglicher Befund: Im ersten `e2e.sh`-Lauf mit DG2.5/DS1.5
  (7.24.5, parallel zu einem zweiten Labor) scheiterte ab Schritt 14 jede Anmeldung an cm1: admin
  (leeres Passwort) und netadmin per SSH und an der seriellen Konsole, `cfmd-sw1` per SFTP-Key von sw1,
  `/system/ssh-exec` von cm2 als `cfm`.
  Der Manager-Tick von cm1 lief weiter, er meldete sich alle 10 min per Key an cm2 und sw1 an. Mit demselben
  Code und Diagnose alle 5 s (freier Speicher 40 MB, Platz 68 MB) lief Schritt 14 danach fehlerfrei. Die
  VM-Disks gingen mit dem nächsten `fresh` verloren. Tritt es wieder auf: VM nicht neu aufsetzen, Disk
  sichern (`qemu-img convert`), dann zuerst prüfen, ob cm1 neu gestartet ist (Uptime im Status) und ob
  ein Rollback lief (Log von cm2/sw1 und `cfm/state/cm1/status.dat` im Spiegel von cm2).
* ~~**Manager-Ticks starten gleichzeitig:**~~ – *erledigt (DM2.2):* Der allgemeine Tick wartet bis zu
  60 s auf einen laufenden Onboarding-Tick und setzt während seiner Arbeit `cfmTickBusy`, der
  Onboarding-Tick wartet bis zu 30 s darauf und lässt dann seine Minute aus. – `cfm-mgr-tick` (alle `mgrTick`) und `cfm-mgr-onb-tick` (jede
  Minute) haben beide `start-time=startup` und laufen deshalb zur selben Sekunde los, im Labor mit
  `mgrTick=1m` jede Minute. Bisher nur als Zeitversatz beobachtet (Onboarding-Test: Status von ob1
  und Rückstellung des Onboarding-Ports einige Sekunden später, einmal ein leerer Status beim Lesen).
  Vorschlag damals: Start des Onboarding-Ticks versetzen oder beide Ticks gegenseitig ausschließen.
  Vor DM2.2 (DM2.1) übersprang sich nur jeder Tick selbst, solange sein eigener Vorlauf noch lief.
* ~~**WireGuard-Fernzugang: Rückweg zu cm1 selbst startet nicht zuverlässig ohne Anstoß.**~~ –
  *erledigt, am 2026-09-24 auf Hardware bestätigt:* Nach frischem `nmcli connection up` läuft der
  Verkehr zum MGMT-Netz sofort durch den Tunnel (Quelle ist die Tunnel-Adresse), SSH zu cm1 klappt
  auf Anhieb. Ursache war das früher überlappende
  Peer-Subnetz im MGMT-Netz (RouterOS legt dafür keine Route an, dazu Proxy-ARP); seit dem eigenen
  WireGuard-Subnetz (`wireguard.rsc` → `net`) ist das behoben.
