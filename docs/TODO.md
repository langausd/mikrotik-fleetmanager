# TODO – geplante Verbesserungen

## Übersicht offener Punkte (Stand 2026-11-25)

Erledigtes steht in [ERLEDIGT.md](ERLEDIGT.md): der Verlauf, die erledigten Punkte mit ihren Nummern und die
behobenen Fehler. Ist von einem Punkt nur ein Rest offen, steht er hier gekürzt auf diesen Rest, der frühere
Text ebenfalls dort. Neue Punkte bekommen die nächste freie Nummer (ab 100). Was auf Hardware und im Labor
geprüft ist: [TESTSTAND.md](TESTSTAND.md). Offen, grob nach Nutzen:

* **Neu 2026-11-11, Labor grün (12.11.):** Standortkopplung (15, DR4.3) mit DynDNS (DR4.4) und Freigaben nach Domain
  bzw. je Client (20, DR2.8/DR2.9) sind umgesetzt und im Labor bestanden (`e2e-vrrp.sh` 164, `e2e.sh` 477). Nächster
  Schritt: Rollout an beiden Standorten (Site-Overlays vorbereitet, Reihenfolge Admin-Guide 8.17), Hardware-Test (80).
  Netinstall/Branding: Plan in [NETINSTALL.md](NETINSTALL.md), Umsetzung 79.
  *Nachtrag 2026-11-12:* Der LAN-LAN-Tunnel der Fritz!Boxen bleibt vorerst (DR3.2.1: `asymRouting` mit Netzen, damit
  Hosts mit Gateway VIP darüber erreichbar sind; DR4.3.1: Standort ohne `pubkey` nur vorbereitet). Reihenfolge des
  Nutzers: erst die offenen Tests an Standort B (74), dann cfm-Tunnel vorbereiten, A/B-Messung gegen den Fritz-Tunnel (81).
* **Neu 2026-11-16 (Hardware), abends umgesetzt (unbeaufsichtigt, Labor):** Fallback weiterer SSIDs über eigene lokale
  virtuelle APs und das Skript `cfm-fallback`, `slaves-static` entfällt samt Resten (84, 85 → DW1.12); `txPower`, Pool
  je AP und Band aus (72 → DW3.7); 5-GHz-Pool der Vorlage mit DFS (87 → DW3.6); Hinweis in `upload-seed.sh` (86).
  *Hardware 2026-11-18 (v40) bestanden* bis auf die Isolation nach dem Wiederverbinden (→ 94); offen aus DW3.7 der
  Pegeltest von `txPower` am CAP ([TESTSTAND.md](TESTSTAND.md#offen-auf-hardware)).
* **Neu 2026-11-24:** 55 (NetBox) entschieden als Variante C: in NetBox planen (Geräte, Kabel, Ports mit
  cfm-Profil als Custom Field, VLANs, Prefixe, alle IPs), Abgleich gegen Soll und Ist nur auf Wunsch, aus NetBox
  per Custom Script auslösbar, das im NetBox-Container läuft; Tunnel als NetBox-Objekte; einmaliger Start-Import;
  NetBox schreibt nicht in die Site-Daten (DT2.2). *Baustein 1 umgesetzt (DT2.3, Labor 562/563):* `$cfmNetbox` (Soll als JSON),
  Ethernet-Ports im Agent-Status, `tools/netbox-abgleich.py` (Admin-Guide 8.21). *Baustein 2 vorbereitet (25.11.):*
  `tools/netbox-import.py`. Offen: Baustein 3, beide Bausteine gegen die echte NetBox.
* **Neu 2026-11-25:** 99 (Flottenzustand als JSON für Home Assistant), Idee, erst bei konkreten Sensoren umsetzen.
* **Neu 2026-11-22 (Nachtschicht):** 6 erledigt (Plan-Bericht über 60 KB, ERLEDIGT); 62 vorbereitet (`tools/wlan-btm.py`,
  Hardware-Test mit 97); Konzept 802.1X/RADIUS für 65b in [RADIUS.md](RADIUS.md) (Fragen an den Nutzer offen).
* **Neu 2026-11-18 (Hardware, Rollout DW1.12):**
  * **94 – Gast-Isolation nach dem Wiederverbinden und im Fallback** (DW1.12.2): *erledigt, Hardware bestanden
    2026-11-23 (v42)*, siehe [ERLEDIGT.md](ERLEDIGT.md#erledigte-punkte).
  * **95 – Kanalvorschlag 5 GHz auf Hardware korrigiert** (*umgesetzt 19.11. nachts, DW3.9.1, Labor; nur
    Framework-Upload, kein Release*): `cfmScanBlk` versteht `5500/ax/Ceee/D` und `/I`; Kanal und Sendeleistung
    werden vor dem Scan gelesen; `$cfmCheck` warnt nicht mehr bei `radios`/`txPower` für den Manager als CAPsMAN
    (cm1). Hardware: nächster `$cfmWifiScan band=5` am Standort („Aktuell“ mit 80 MHz, keine Rollen-Warnung zu cm1);
    6 GHz erstmals an einem Standort mit 6-GHz-Radios. *Hardware 19.11. (5 CAPs, hAP be³ als CAPsMAN, 7.25.1):
    „Aktuell“ mit Breite und `/D`/`/I` richtig, keine Rollen-Warnung; Leistung nicht bestanden → 96.*
* **Neu 2026-11-19 (Hardware, zweiter Standort), in der Nacht umgesetzt (unbeaufsichtigt, Labor):**
  * **96 – `$cfmWifiScan`: Leistung, Suche, 6 GHz** (*umgesetzt 20.11., DW3.9.2, Labor; Hardware offen*):
    1. *Leistung als EIRP:* `monitor` meldet `tx-power` am Anschluss, RouterOS zieht `min-antenna-gain` ab (hAP ax³ 8 dBm
       auf 5745 = 14 EIRP). Der Scan liest den Gewinn mit (`g`), rechnet EIRP und sagt in „Leistung vor dem Scan“, was
       er annimmt; an der Grenze gemessen = „Reserve bis 30 angenommen“, zählt nur 1 je dB (schwächere Radios per `txPower`).
       `$cfmChannels` mit Spalte `DBM`.
    2. *Suche:* Start beim laufenden Plan, beste K je AP aus verschiedenen Blöcken, Paar-Tausch.
    3. *6 GHz/freies Spektrum:* Vorschlag auch ohne gemessene Netze, APs ohne Radio im Band übersprungen.
    4. *Radar beobachten:* erster DFS-Pin auf Hardware (5500/80, CAC ohne Logzeile) – beim ersten Treffer Meldung und
       Verhalten in ROUTEROS-EIGENHEITEN festhalten.
    5. *`minSignal`:* wirkt nur auf Bändern ohne `drop` – Admin-Guide, Vorlage und `$cfmCheck`-Hinweis.
    Dazu (Nutzer): **MLO je SSID** (DW2.3.1, Hardware-Test ohne/mit MLO → 48), **`wifiDebug`** statt Handeintrag
    (DU3.5), **Editor** „Kanäle“/„WLAN-Scan“ mit Übernehmen (DT3.5), Admin-Guide **8.19 WLAN-Kanäle planen**.
    Hardware: `$cfmWifiScan band=5` am Standort (Leistungszeile plausibel, „breit“ ≤ Aktuell), `band=6` mit Vorschlag,
    Editor-Knöpfe im Browser, `wifiDebug` am CAPsMAN, MLO-Test (48).
* **Neu 2026-11-21:**
  * **92 – DFS je AP** (*umgesetzt 21.11., DW3.10, Labor; Hardware offen*): `skipDfs` ersetzt durch `dfs` = höchste
    erlaubte CAC (`no-cac` | `1min-cac` | `10min-cac`), unter `channels` und je AP (`"dfs"={"ap1"="10min-cac"}`); die
    Kanal-Objekte je AP aus `radios` erben den Wert (bisher ohne `skip-dfs-channels`). **Breaking Change:** Vor dem
    nächsten Release mit diesem Stand an beiden Standorten `"skipDfs"="10min-cac"` → `"dfs"="1min-cac"` (sonst Fehler
    in `$cfmCheck`). Hardware: `cfm-5g-<AP>` mit `skip-dfs-channels=10min-cac` nach dem Release.
  * **97 – 5-GHz-Steering erreicht das Handy nicht** (*Befund 21.11. aus den Dauermessungen, Test offen*): Ein Samsung
    S24U (`ft-wpa3-psk`) lag am 20.11. 44 min am Stück unter `threshold` −74 (5-s-Proben −75 … −86) – im Debug-Puffer
    keine einzige Zeile `transition requests`, kein Kick. In allen Messungen seit 26.10. bekam es auf keinem Band
    Vorschläge (nur „0 transition requests sent“ als Kandidat auf 6 GHz), andere Clients schon (Laptop ohne FT:
    Vorschläge und Kick auf 5 GHz; ein OnePlus mit FT: Vorschläge auf 2,4 GHz). Vermutung: Das Handy meldet kein BSS
    Transition (802.11v) – RouterOS schickt dann nichts, und der Kick trennt FT-Clients ohnehin nicht (DW2.5). Test vor
    Ort: Handy und Laptop nebeneinander unter der Schwelle, Puffer live mitlesen, dazu ein Mitschnitt am Funk (62). Bestätigt sich das, hilft bei
    solchen Clients nur die Trennschwelle (`drop`/`join`/`hold`) auch auf 5 GHz.
* **Neu 2026-11-17 (Hardware, Entscheidungen des Nutzers), Umsetzung über Nacht:**
  * **88 – Index unter `/interface/wifi`** (DW1.12): RouterOS zeigt dort den Kommentar des Datapaths an jedem
    Interface ohne eigenen (`cfm:wdp…`); der Plan wollte Radios und Slaves entfernen. Fix im Arbeitsstand
    (`cfmIdxPat`, Reste-Aufräumen ignoriert `cfm:wdp…`), Labor grün (17.11. abends, 503/504, der eine Fehler ein
    Zeitproblem im DNS-Test); *Hardware bestanden 18.11.* (Probelauf ohne `entfernt: … wdp…`).
  * **89 – Kanalbreite je AP und Band** (Option 2, *umgesetzt 17./18.11. DW3.8, Labor; Hardware 18.11.: Warnung
    zur Blockgrenze wie erwartet, Kanalplan mit `/80` und `/40` läuft*): `radios` `"5"="5500/80"` – ohne `/` gilt die Breite aus
    `channels`. `$cfmCheck`: Block darf nicht über 5725 MHz (EU) reichen. Anlass: ap1 und ap2 im selben 80-MHz-Block
    132–144, der bis 5730 reicht; nur zwei zulässige 80-MHz-Blöcke für drei APs, die sich hören.
  * **90 – Vorlage DW3.6 korrigieren** (*umgesetzt, DW3.8: Pool 5180–5240, 5500–5560*): 5660–5700 im Pool nur bis 40 MHz (80 MHz → 5650–5730).
  * **91 – `$cfmChannels`/`$cfmWifiScan`** (*umgesetzt: live vom CAPsMAN mit `*`, ohne virtuelle APs, Switch-Spalte; Hardware 18.11.: zeigt den neuen Plan nach `cfm-reprov`*): Status und live (`monitor`) wichen ab, die Kanäle wechselten am Abend
    mehrfach (2,4 GHz: ap1 2437 → 2462, ap2 2412 → 2437 – löst der Scan selbst eine Neuwahl aus?); prüfen, woher
    der Status die Kanäle nimmt und wie alt sie sind. Virtuelle APs (wifi9–17) als leere Zeilen, Spalte SWITCH bei cm1
    „ap1“.
  * **93 – `$cfmWifiScan` mit Vorschlag für 5 GHz** (Nutzer; *umgesetzt in der Nacht 17./18.11., DW3.9, mit 6 GHz,
    Labor; erster Einsatz 18.11.: Plan „breit“ übernommen, Fehler → 95*): Kandidaten je AP = Primärkanal × Breite aus dem Pool,
    Nebenbedingungen (EU-Bandgrenzen, `skipDfs`, DFS/CAC im Fallback, Sendeleistung je Teilband), Überlappung der
    belegten Blöcke statt nur des Primärkanals, fremde Netze mit ihrer Breite aus dem Scan. Setzt 89 voraus. Erst
    Konzept mit Fragen an den Nutzer, dann Umsetzung. **Konzept (Entwurf 2026-11-17):**
    1. *Kandidaten* je AP: (Primärfrequenz, Breite) mit Primärkanal im Pool bzw. Pin-Liste des AP und vollständigem
       Block in einem zulässigen Teilband (5150–5250, 5250–5350, 5470–5725; 5725–5850 nur, wenn im Pool), ohne
       Wetterradar 5600–5650 (außer Erlaubnis je AP, 92). Breiten bis `width` aus `channels`. Drei APs ≈ 15 Kandidaten
       je AP → ~3400 Pläne, vollständig; ab 5 APs reihum wie bei 2,4 GHz.
    2. *Störung* = Überlappung der belegten Blöcke in MHz (statt Kanalabstand), gewichtet mit `w(Signal) = s + 95`;
       fremde Netze mit dem Block aus dem Scan (`5700/ax/eeCe` → 80 MHz 5650–5730), eigene Nachbarn doppelt. Nur ein
       Bruchteil der Überlappung zählt, wenn ein fremdes Netz nur seinen Nebenkanal bei uns hat? (Frage A)
    3. *Nutzen der Breite*: Bonus je AP proportional zur Breite (40 = 1, 80 = 2, 160 = 3?) mal einem Gewicht `bw`
       (Frage B: wie viel Störung ist eine Verdopplung der Breite wert?).
    4. *Sendeleistung*: Bonus, wenn das Teilband mehr EIRP erlaubt und das Radio sie ausschöpft (Landeslimit aus
       `monitor` → `tx-power` je Kanal ist bekannt, sobald der AP dort sendete; sonst Tabelle EU: 23/23/30 dBm)
       (Frage C: Tabelle fest oder gemessen?).
    5. *DFS*: Malus für DFS an APs mit Fallback (60 s CAC), höher bei Wetterradar (600 s); am CAPsMAN-Gerät selbst 0
       (Frage D: fester Malus oder Schalter „AP darf DFS“ je AP?).
    6. *Ausgabe*: zwei Pläne – „breit“ (bw hoch) und „robust“ (bw niedrig, keine Überlappung eigener APs) – je mit
       Zeile `radios` (Pins mit `/<Breite>`, 2,4-GHz-Pins der letzten Messung übernommen) und den Kosten-Anteilen.
    **Entscheidungen (Nutzer, 2026-11-17):** A – Überlappung mit unserem Primär-20-MHz voll, sonst ×0,5 × Anteil der MHz;
    B – zwei Pläne „breit“ (Bonus je Verdopplung ≈ fremdes Netz −75 dBm voll überlappend, w = 20) und „robust“ (kein
    Breitenbonus, eigene APs ohne Überlappung); C – Leistung gemessen (`tx-power` aus `monitor` je Radio und Teilband,
    soweit bekannt), sonst EU-Tabelle begrenzt auf das bekannte Maximum des Radios, Bonus je dB; D – DFS-Malus nur an
    APs mit Fallback (Rolle `ap`), Wetterradar höher, CAPsMAN-Gerät ohne Malus; E – **6 GHz gleich mit** (PSC-Raster,
    kein DFS; Test an einem Standort mit zwei 6-GHz-Radios). **Umgesetzt** wie entschieden; abweichend vom Entwurf
    oben: Kandidaten aus dem Pool, `all=yes` für alle EU-Kanäle (der Pool aus TODO 90 enthält 5660 nicht mehr);
    Suche über die je AP besten K Kandidaten statt aller ~3400 Pläne, danach zwei Runden reihum.
* **Rest von 74 am Wochenende 28./29.11. am zweiten Standort:** zwei Gäste an verschiedenen APs (kein Ping untereinander, Zähler
  `cfm:iso` am AP: `ip` oder `vlan`?) und die Tests von 74 am zweiten Standort. Am ersten Standort bestanden: Fallback weiterer
  SSIDs (18.11.), Isolation nach der Rückkehr (94, 23.11.), normale Passphrase und FT-Roaming mit PPSK (17.11.).
* **Vorbereitet, Test nur mit Hardware vor Ort** (Code fertig, standardmäßig aus): 39 (Steering je Band +
  Mindestsignal, DW2.4) läuft seit 2026-10-17 an einem Standort ([TESTSTAND.md](TESTSTAND.md#bestanden)).
* **Nur mit Hardware:** die Punkte unter „Offen auf Hardware“ in [TESTSTAND.md](TESTSTAND.md#offen-auf-hardware). Das eingebaute Update
  (38, DV1.5) lief über den Spiegel (hEX) und per `via=internet` (CRS, 7.25).
* **RouterOS 7.25:** stable seit 2026-10-22, beide Standorte seit 2026-10-26/28 darauf
  ([TESTSTAND.md](TESTSTAND.md)); offen aus 48: FT für MLD (DW2.3).
* **Im Einsatz an einem Standort:** 25 (Zertifikate für WebFig/API, DS3.6, seit 2026-11-23; Rest siehe 25).
* **Zurückgestellt:** 22 (Disk-Logging
  – ein externer Syslog-Server ist geplant; *seit 2026-11-01 an einem Standort in Betrieb, Graylog 8.15*).
* **Vorbereitet, Test nur mit Hardware:** MLAG auf CRS3xx (Hardware-Offload, Ausfall eines Knotens,
  Umbau im laufenden Betrieb), isolierte VLANs an echten APs (seit 2026-11-04 im Betrieb an einem Standort; der
  CAPsMAN gibt `interface-list` **nicht** an die CAPs weiter. Offen: Wie sieht der Bridge-Filter WLAN-Frames? Zwei
  Gäste an verschiedenen APs) und an Switch-Ports mit `hw=no`.
* **Größere Ausbauten:** 13, 14, 16, 18 sowie 79 (Netinstall-Station und Branding-Paket, Plan in
  [NETINSTALL.md](NETINSTALL.md)).
* **Offen im Verbesserungsplan:** 13, 14, 16, 18, 21–23, 25, 37, 48, 49, 51, 54, 55, 58, 62, 63, 65, 67–69, 73–75,
  79–81.

## Onboarding: weitere Wege in den Onboarding-Zustand

Umgesetzt ist der **Push in die Werks-Config** (siehe README, Abschnitt Onboarding). Zwei weitere
Methoden wurden geprüft und für später vorgemerkt – *seit 2026-11-11 als Plan ausgearbeitet in
[NETINSTALL.md](NETINSTALL.md) (DO1.8, DT3.3; Umsetzung: 79). Die Entscheidung dort: Branding-Paket mit cfm-Stub
(generisch, Onboarding-Schlüsselpaar) plus Netinstall-Container auf einem MikroTik des Standorts; die beiden
Abschnitte unten bleiben als ursprüngliche Bewertung.*

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

Steht seit 2026-11-03 in [TESTSTAND.md](TESTSTAND.md#offen-auf-hardware) („Offen auf Hardware“), zusammen mit dem,
was auf Hardware und im Labor schon bestanden hat.

## Bekannte Fehler

Eigenheiten von RouterOS stehen in [ROUTEROS-EIGENHEITEN.md](ROUTEROS-EIGENHEITEN.md#auf-hardware-verifizierte-routeros-eigenheiten).
Die drei WLAN-Fehler aus den Hardware-Tests vom 2026-11-04 und 2026-11-16 (Gast-Kopie im Fallback, normale Passphrase
bei PPSK, `cfm-iso` nach dem Neuverbinden) sind seit 2026-11-23 auf Hardware behoben:
[ERLEDIGT.md](ERLEDIGT.md#behobene-fehler).

* **Backup-Manager: Einspielen der Manager-Module scheitert** (`roles/manager.rsc`, hAP be³ Media 7.25.1,
  2026-11-08): zweimal `no such item (/file/get; line 26)` gleich nach dem Ersetzen eines anderen Modul-Skripts,
  Rollback mit Neustart; von Hand nicht nachgestellt. Abwehr seit DM1.1.1 (erst lesen, dann setzen, Wiederholung,
  Log-Zeile mit Dateiname). Bleibt hier, bis ein Framework-Update an einem Backup auf Flash durchläuft; tritt es
  wieder auf, steht die Datei im Log.

* **Labor-Wackler MNDP mit Quelle 0.0.0.0** (`e2e.sh` Abschnitt 14, DR2.5): Die Prüfung „cm1: MNDP mit Quelle
  0.0.0.0 still verworfen“ wartet auf einen Treffer im Zähler der Drop-Regel. Fehlschläge 2026-10-31, 2026-11-06 und
  2026-11-08 (7.25.1) – auch nach dem Anstoßen (MNDP an cm2 aus und wieder an, danach bis zu 120 s): Zähler 0, cm2
  sendet MNDP (`cdp;lldp;mndp`, 30 s). Das Verhalten stimmt jeweils (kein `cfm-drop` im Log). *2026-11-21:* Mit zwei
  VMs nachgestellt (Trunk-Port ohne Adresse, `protocol-mode=none`, Gegenseite `pvid=10`, derselbe Ablauf mit Anstoßen):
  11 von 11 Mal kam das erste Paket nach 3 s an, immer `connection-state=new` – kein Hinweis auf Connection-Tracking.
  Die Prüfung stößt jetzt nach 60 s ein zweites Mal an und zählt davor in `raw`/prerouting (Handregel): Kam nichts mit
  Quelle 0.0.0.0 an, gilt sie als übersprungen („cm2 sendet nicht“, kein Fehler von cm1); kam etwas an und die
  Drop-Regel zählt nicht, ist sie rot. Offen bleibt, warum cm2 im vollen Labor manchmal nicht sendet.

* **Labor-Wackler MLAG: sw2 im zweiten Apply nicht idempotent** (`e2e-mlag.sh` Schritt 7, 7.25.1, 2026-11-08): einmal
  `add=6;rem=3;set=6`, sw1 mit derselben Rolle sauber, die Wiederholung grün. Die VMs waren schon ersetzt, das
  Agent-Log von sw2 fehlt. Bei Wiederkehr vor dem Stoppen `/log/print where message~"gesetzt|entfernt|angelegt"`
  auf sw2 sichern.

* **98 – VLAN-ID über 255 mit VRRP ohne `vrid`** (Befund 2026-11-24 bei der Doku-Prüfung, nicht beobachtet):
  `roles/router.rsc` nimmt die VID als VRRP-ID, über 255 den VLAN-Schlüssel `vrid`. Fehlt er, legt die Rolle das
  VRRP-Interface ohne gültige `vrid` an (Apply-Fehler, Rollback). `$cfmCheck` sollte das vorher melden (VID > 255,
  `l3` nicht `no`, ein Router mit `routerId` → `vrid` 1–255 und eindeutig). Dokumentiert ist `vrid` seit 2026-11-24
  (Admin-Guide 4, Kopf von `vlans.rsc`); ebenso braucht ein solches VLAN `net` (`$cfmNet`).

* **hAP be³ Media meldet beim Start einen Fehler im Werks-Skript** (Befund 2026-10-18, 7.24.5):
  `error while running customized default configuration script: no such item (/interface/wifi/get; line 1)`,
  obwohl `/system/default-configuration` kein eigenes Skript hat. Vermutlich sucht das Werks-Skript ein
  WLAN-Interface unter dem Werksnamen (cfm benennt sie um). Ohne erkennbare Folge; Ursache offen.

## Verbesserungsplan (Stand 2026-09-12)

Reihenfolge: 0 → 1 → 2, 3, 4 → 6, 7 → Rest nach Bedarf.

**0. Pilotbetrieb mit echter Hardware** – ein Gerät je Typ (Router, Switch, AP, Manager); deckt
die oben genannten ungetesteten Punkte ab. Größter Risikominderer vor jedem neuen Feature.
*Begonnen 2026-09-17* mit CRS418 (Router + Manager) und hAP ax² (AP), seit 2026-09-26 ein
zweiter Standort mit Switches, eigenem CAPsMAN und Manager in einer VM (siehe oben). Auf Hardware
lief der Backup-Manager am 2026-11-08 an einem Standort (Ausfalltest bestanden); VRRP mit vier Routern läuft seit 2026-10-17 an einem Standort.

### Kurzfristig (großer Nutzen, wenig Aufwand)

Alle erledigt, siehe [ERLEDIGT.md](ERLEDIGT.md#erledigte-punkte).

### Mittelfristig

Alle erledigt (zuletzt 6 am 2026-11-22), siehe [ERLEDIGT.md](ERLEDIGT.md#erledigte-punkte).

### Größere Ausbauten

13. **IPv6** (Präfixe je VLAN, Router Advertisements, IPv6-Firewall).
14. **Zentrale Admin-Anmeldung per RADIUS** (User Manager auf dem Manager; Grundlage: [RADIUS.md](RADIUS.md), Schritt 5).
16. **WPA2/WPA3-Enterprise** (externer RADIUS oder User Manager) – Rest von „WLAN-Ausbau“ (umgesetzt: DW2.2);
    Für 65b reicht der RADIUS-Teil ([RADIUS.md](RADIUS.md), Schritt 5: danach WPA-Enterprise mit denselben
    Benutzern). PPSK-VLANs auf Hardware: [TESTSTAND.md](TESTSTAND.md#offen-auf-hardware).
<!-- -->
18. **Optional Git als Arbeitsort** mit Review vor dem Release – bewusste Alternative zu DG1.2,
    z.B. bei mehreren Admins.
<!-- -->
21. **Weniger `/file/find` – Rest** (umgesetzt: DG4.1): auf Geräten mit USB-Stick prüfen, ob er die
    Dateiliste bremst.
22. **Fehlgeschlagener Apply löst über den Watchdog einen Reboot aus (Design-Falle, kein Bug)** –
    *Disk-Logging zurückgestellt (2026-10-01): Ein externer Syslog-Server ist geplant; den Grund eines
    Rollbacks meldet der Agent schon vor dem Neustart (`res` in `$cfmStatus`).* *Bestätigt 2026-11-01:* Bei einem
    gescheiterten Apply (Objekt von Hand angelegt, `entry already exists`) stand „Apply vN fehlgeschlagen …“ als
    Fehler im Syslog (Graylog), bevor der Rollback das Gerät neu startete. –
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
    nicht vom CAPsMAN – der Datapath `cfm-cap` (DW1.3) reicht dort nicht. Die Rolle `ap` müsste je
    Radio bzw. virtuellem AP einen statischen Bridge-Port mit der PVID der SSID anlegen, und der
    CAPsMAN dürfte solchen CAPs keinen Datapath mit `vlan-id` schicken. Erst mit einem solchen
    Gerät umsetzen und testen. *Seit 2026-10-04 warnen die Rolle `ap` (Log, Probelauf) und `$cfmCheck`
    (aus den gemeldeten Paketen), wenn ein AP das Paket hat.*
<!-- -->
25. **WebFig per HTTPS – Rest** (umgesetzt 2026-11-23: DS3.6, Zertifikate einer öffentlichen CA für `www-ssl` und
    `api-ssl`, Schlüssel auf dem Gerät, Signer `tools/cert-signer/`; Labor `e2e.sh` 14n, Admin-Guide 8.20; Hardware
    2026-11-23 an einem Standort mit drei Geräten bestanden, TESTSTAND). **Offen:** zweiter Standort, danach `www` in den Management-Netzen
    abschalten (auf Routern bleibt es für die DNS-Selbstbedienung, DN3.2); `notify`-Meldung bei TLS-Fehlern bzw. kurz
    vor Ablauf (bisher nur `$cfmTlsStatus` und Log); Home-Assistant-Integration auf `api-ssl` umstellen (8.20, 6.7).
<!-- -->
37. **Paketprüfung – Rest** (umgesetzt: DV1.4, NPK-Kennung): Prüfsummen von MikroTik nutzen, falls es eine
    Liste gibt.
<!-- -->
48. **RouterOS 7.25 – Rest** (Befunde und Changelog-Durchsicht: [ERLEDIGT.md](ERLEDIGT.md#frühere-fassungen),
    Läufe: [TESTSTAND.md](TESTSTAND.md)): **FT für MLD-Geräte** („wifi - add fast transition support for MLD
    devices“): DW2.3 hat MLO abgeschaltet, weil der hAP be³ als MLD kein FT anbot. Mit einem Client prüfen, ob
    MLO mit FT jetzt geht – seit DW2.3.1 je SSID (`"mlo"="enabled"` nur an der Master-SSID); geplant: direkt
    hintereinander ohne und mit MLO, im Haus und an den Messpunkten am Rand (Dauermessung). Danach ggf. MLO für
    weitere SSIDs oder lokal (32).
49. **RouterOS 7.26beta1 (Kanal development, 2026-10-01)** – `e2e.sh` im Labor grün ([TESTSTAND.md](TESTSTAND.md)).
    Punkte aus dem Changelog, die cfm berühren können:
    * „l3hw - add VRRP hardware offloading support“: DR1.2 schaltet für VRRP das Routing im Switch-Chip
      ab. Mit 7.26 prüfen, ob ein CRS als VRRP-Router im Chip routen kann (Zonen-Firewall bleibt aber in
      der CPU – also nur für Netze ohne Filter interessant).
    * „switch - add interface-list support to port isolation“: Alternative für isolierte Kabel-Ports
      (DP3.1) im Switch-Chip statt `hw=no`.
    * „bridge - add a per-VLAN DHCP snooping option“ (Rolle `switch`, `dhcpSnoop`).
    * „cmr - add initial implementation of centralised platform for RouterOS devices, allowing updates,
      monitoring, alerts“: eine zentrale Verwaltung von MikroTik selbst – beobachten, wie weit sie reicht.
    * „wifi - add a default-country parameter in radio settings“, „ethernet - move the port bandwidth
      setting to the switch port menu“ (cfm setzt beides nicht).
<!-- -->
51. **Kanalplanung mit anderen Funknetzen – Rest** (umgesetzt: DW3.5): Energie-Messungen der Koordinatoren
    einbeziehen (Energie-Scan je 802.15.4-Kanal aus den ZHA-Diagnosedaten bzw. `commissioner energy` in
    OpenThread; die MikroTik-Radios sehen nur WLAN).
<!-- -->
54. **LibreNMS – Rest** (umgesetzt: DU4.3, Admin-Guide 8.12; SNMP und Syslog auf Hardware bestanden,
    [TESTSTAND.md](TESTSTAND.md#bestanden)): Geräte per LibreNMS-API aus dem Inventar anlegen (Nutzer: später;
    von Hand geht `lnms device:add --v3` mit den v3-Daten aus den Einstellungen, Admin-Guide 8.12). Ungeprüft:
    was das `wifi`-Paket direkt am CAP per SNMP liefert (der CAPsMAN zeigt keine Clients – Signal/SSID bleiben
    bei `$cfmFind`/cfm-Monitor). Standorte, die nur per WireGuard erreichbar sind: Peer für den
    LibreNMS-Server. Die Netzanbindung (zweite Schnittstelle im MGMT-VLAN, entschieden 2026-10-16) steht in
    [ERLEDIGT.md](ERLEDIGT.md#frühere-fassungen).
55. **NetBox: planen und abgleichen** (Idee 2026-10-16; *Variante C entschieden 2026-11-24, DT2.3*; Baustein 1
    umgesetzt 2026-11-24, siehe unten). Eine NetBox-Instanz gibt es bereits. Die beiden früheren Varianten bleiben verworfen bzw. zurückgestellt:
    * ~~**A – Einweg-Export cfm → NetBox**~~ (nur Doku, für die Fehlersuche wenig Nutzen).
    * ~~**B – NetBox als Quelle**~~ (NetBox erzeugt `vlans.rsc`/`leases.rsc`; widerspricht DT2.2).
    * **C – In NetBox planen, cfm abgleichen** (Wunsch des Nutzers): In NetBox werden Geräte, Verkabelung, Ports
      samt Portkonfiguration, VLANs, Prefixe und alle konfigurierten IPs geplant. Ein Abgleich vergleicht den Plan mit
      dem Soll in cfm (Site-Daten) und dem Ist (Inventar, Nachbarn, Adressen am Gerät) und berichtet die Abweichungen.
      NetBox schreibt **nicht** in die Site-Daten (DT2.2 bleibt). Wahlweise erzeugt der Abgleich einen Vorschlag
      (Diff) für die Hostdateien, `vlans.rsc` und `leases.rsc`, den man per cfm-Editor oder `upload-seed.sh --site` übernimmt.
      * **Gegenstücke:** Geräte (Modell, Seriennummer, Rolle, Standort) ↔ `meta/inventory.rsc`; Kabel ↔ `"links"`
        der Hostdateien (Soll) und `$cfmLinks`/`netzplan.csv` (Ist per LLDP/MNDP), also Plan, Soll und Ist
        nebeneinander; Portliste ↔ Interface-Vorlagen des Device-Type (NetBox Device-Type-Library) gegen die Ports
        am Gerät; VLANs ↔ `vlans.rsc`; Prefixe ↔ Netze in `vlans.rsc`; IPs ↔ feste Leases (mit DNS-Namen),
        statische DNS-Einträge, MGMT-Adressen, VIPs (VRRP), WireGuard-Adressen und die Adressen am Gerät.
      * **Portkonfiguration über Custom Fields**, die alles abbilden, was cfm kennt: am Interface `cfm_port` mit dem
        vollständigen Profil (`trunk`, `trunk-ap`, `access:<vid>`, `hybrid:<vid>`, `access-sw:<vid>`, `wan`, `off`,
        später `vport:<vid>`, außerdem Sonderwerte wie `cage`), am Gerät `cfm_port_default` (`portDefault`) und
        ggf. weitere Host-Schlüssel (`stpPrio`, `igmp`, `portSwitch` …). Der Abgleich prüft zusätzlich, ob der
        native 802.1Q-Modus (access/tagged, untagged/tagged VLANs) in NetBox zum Profil passt. Dann bleibt auch die
        normale NetBox-Ansicht aussagekräftig. Bonds gehören als LAG-Interfaces dazu.
      * **Nur auf Wunsch, aus NetBox auslösbar:** als NetBox Custom Script („cfm-Abgleich“ je Site, Ergebnis im
        Job-Log, Vorschlag als Datei). Die Logik steckt in einem eigenständigen `tools/netbox-abgleich.py`
        (CLI, im Labor testbar), das Custom Script ruft nur auf. Kein Lauf im Manager-Tick.
      * **Entschieden 2026-11-24:** (1) Der Abgleich läuft im NetBox-Container. Das Custom Script holt die Daten
        selbst per SSH vom Manager (eigener Nutzer nur zum Lesen, wie `cfm-cert`; `pull-site.sh`). (2) Standortkopplung
        und Tunnel (WireGuard, Fritz!Box) als eigene NetBox-Objekte (VPN → Tunnels mit Terminations, ab NetBox 3.7).
        (3) Auch die Adressen, die cfm aus den Rollen berechnet, werden in NetBox geplant. Der Abgleich meldet,
        wenn das Ergebnis abweicht. (4) Einmaliger Start-Import cfm → NetBox (Geräte, Ports mit `cfm_port`, Kabel,
        VLANs, Prefixe, IPs, Tunnel), danach wird in NetBox gepflegt. (5) SSH-Schlüssel (und ggf. Einstellungen)
        liegen im NetBox-Container, nicht im Repo. Das Custom Script arbeitet über das ORM und braucht kein API-Token.
      * NetBox-Version: mindestens 3.7 (Nutzer, 2026-11-24), Tunnels also vorhanden. Im Einsatz ist **4.6.4** im
        Container (Nutzer, 2026-11-25). Das Custom Script so schreiben, dass es unter 3.7 und 4.x läuft (Unterschiede
        u.a. bei `log_*` und beim Ablegen von Scripts); erster echter Abgleich gegen 4.6.4 steht aus. Der Container
        braucht für Baustein 3 SSH-Zugang zum Manager (Quelle in `mgmtExtra` oder über das MGMT-VLAN).
        *Geklärt:* Für das Ist der Adressen braucht es keinen neuen Bericht. Der Agent legt `/export terse` ab, der
        Manager holt es nach `state/<name>/export.rsc` (`$cfmCollect`). Daraus liest der Abgleich `/ip address`,
        VRRP, WireGuard, Bridge-Ports und VLANs je Gerät, zusammen mit `status.json` (Modell, Seriennummer,
        Version, Nachbarn).
      * **Bausteine:** (1) *umgesetzt 2026-11-24:* Abgleich-Tool samt Tests. Der Manager wertet die Site-Daten selbst
        aus (`$cfmNetbox`, `lib/mgr-netbox.rsc` → `state/netbox.json`, `state/<name>/netbox.json`), weil sie
        RouterOS-Skripte sind; das Ist kommt aus `status.dat` (neu: Ethernet-Ports `eth`) und `export.rsc`.
        `tools/netbox-abgleich.py` (REST oder gespeicherter Plan, `--manager` per SSH/SFTP als Admin) berichtet
        Geräte, Ports, Kabel, VLANs, Prefixe, IP-Adressen und Tunnel. Tests `tools/netbox-abgleich-test.py` (29), Labor
        `e2e.sh` Schritt 14 (2026-11-24: 562/563, der eine rote Punkt ein bekannter Zeitfehler, nachgestellt grün). Gegen
        eine echte NetBox noch nicht gelaufen. (2) *vorbereitet 2026-11-25:* `tools/netbox-import.py` legt an, was in
        NetBox fehlt (Custom Fields, Site, Typen, Rollen, VLANs, Prefixe, Geräte, Interfaces mit `cfm_port`, Kabel aus
        `links`/LLDP, Adressen samt primary IPv4, Tunnel), ändert nichts Vorhandenes, füllt nur Leeres; Probelauf ohne
        `--schreiben`. Tests 12 (NetBox im Speicher, Rundlauf Import → Abgleich ohne Abweichung, 3.7/4.2/4.6), mit
        dem Labor-Stand vom 24.11. ohne Abweichung; `e2e.sh` Schritt 14 prüft das künftig mit. Gegen die echte NetBox
        (4.6.4) noch nicht gelaufen (Token mit Schreibrecht nötig).
        (3) *offen:* NetBox Custom Script „cfm-Abgleich“ (3.7 und 4.x) samt Anleitung; am Manager ein eigener User
        nur `ssh,read` (wie `cfm-cert`) und ein Skript mit `dont-require-permissions`, das `$cfmNetbox` startet. Lesen
        dann ohne SFTP (`ftp` wäre Schreibrecht), z.B. per `/file/read` in Stücken: `export.rsc` eines Managers hat
        ~500 KB, `/file/get` liest nur ~60 KB. Dazu der Vorschlag für die Hostfiles (`ports`, `links`) als Datei.
<!-- -->
58. **Schaltbare SSID – Rest** (umgesetzt: feste Interfaces DW4.2, Neuprovisionieren DW4.3; Umstieg und
    Rückweg im Admin-Guide 6.8; *Hardware 2026-11-04:* Grundzustand aus, Einschalten mit Ablauf nach 8 h, Aus/Ein
    startet das Radio nicht neu – andere SSIDs ohne Unterbrechung). Offen: Aufräumen der festen Interfaces eines abgebauten AP (bisher von Hand, Admin-Guide 7.4); bleiben beim
    Abschalten von `capsmanRadios` feste Interfaces der eigenen Radios stehen? Rückfall, falls feste Interfaces nicht tragen: nacheinander provisionieren (je AP
    `/interface/wifi/radio/provision` mit einigen Sekunden Abstand; die Unterbrechung je AP bleibt).
<!-- -->
62. **Mitschnitt der Wechselvorschläge (802.11v) per Sniffer** (Wunsch des Nutzers, 2026-10-23; zu 61/DW2.5) –
    Ungeklärt ist, auf welcher Seite der Wechsel scheitert: Schickt RouterOS einem Client mit FT überhaupt
    BSS-Transition-Requests (das wireless-Debug-Log zeigt sie nicht), und wie antwortet der Client
    (BTM-Response mit accept/reject, oder gar nicht)? Befund an einem Standort: Ein Android-Handy mit FT blieb
    7 h unter der Schwelle trotz Vorschlag alle 5 s; ein anderes Handy mit FT wechselte bei −75 selbst. Weg:
    `/interface/wifi/sniffer` (vorhanden ab 7.24.5; Optionen, Ausgabe als Datei oder Strom an Wireshark noch
    prüfen) auf einem freien Radio im Kanal des betroffenen APs – das Radio fehlt so lange im Netz (z.B. einen
    AP kurz aus dem CAPsMAN nehmen oder ein Ersatzgerät). Filter auf die MAC des Clients, Action-Frames
    (WNM). Nutzen: Klarheit für eine Fehlermeldung an den Hersteller; wechselt der Client auf Vorschläge,
    ließen sich `drop`/`hold` der Trennschwelle großzügiger setzen – jede harte Trennung kostet ~3 s
    Verbindung, ein Wechsel per FT fast nichts.
    *Vorbereitet 2026-11-22 (Hardware-Test offen, mit 97):* Optionen laut MikroTik-Doku: `/interface/wifi/sniffer
    <Interface> pcap-file=… pcap-size-limit=… duration=… filter="…"` (libpcap-ähnlich: `addr1..3`, `type`/`subtype`,
    Flags) oder `stream-address=` (TZSP); er hört auf dem aktuellen Kanal des Interfaces. Auswertung
    `tools/wlan-btm.py` (tools/README): Fähigkeiten aus (Re)Association/Probe Request (BTM-Bit, 802.11k, FT, AKM),
    Ablauf, WNM-Frames. Mit PMF (WPA3) sind BTM-Request/-Response verschlüsselt – die Frage „kann der Client BTM“
    beantwortet dann der unverschlüsselte Association Request. Die Registration-Table zeigt keine Client-Fähigkeiten.
    *Hardware 2026-11-22 (hAP ax³ als Mitschneider, 7.25.1):* Am vom CAPsMAN verwalteten Radio lehnt RouterOS den
    Sniffer ab (`failure: not allowed`, auch mit Policy `sniff`); mit `/interface/wifi/cap/set enabled=no` geht er,
    das Radio läuft dabei lokal weiter und hört trotzdem fremde Frames auf seinem Kanal (Monitor-Modus) – aber nur in
    Funkreichweite: Ein Client am anderen Ende des Hauses fehlte ganz, direkt daneben 62 Probe Requests in 10 min.
    Befund Android-Handy (FT): gezielte Probes für die eigene SSID ohne BTM-Bit, Wildcard-Probes teils mit – passt dazu,
    dass es nie Vorschläge bekam; der Association Request fehlt noch. *2026-11-24:* `tools/wlan-btm.py` zeigt jede
    Fassung getrennt (Quelle und SSID), urteilt nur nach dem Association Request und leitet FT nicht mehr aus Probe
    Requests ab (vorher eine Fassung je Client, pauschal „BTM nein“). **Offen:** Mitschnitt mit Association Request
    (WLAN am Handy aus/an neben dem Mitschneider), zusammen mit 97.
63. **NTP-Umleitung – Rest** (umgesetzt: DN2.2, seit 2026-10-24 an einem Standort): Uhrzeit in der
    Weboberfläche einer OpenBeken-Lampe prüfen.
65. **Fremdgerät mit der Haupt-SSID bzw. am gemeinsamen Dock ins Gäste-VLAN** (Wunsch des Nutzers, 2026-10-26)
    – *Anlass:* Ein Firmen-Laptop soll nicht ins Hauptnetz, ist aber kein richtiger Gast (kennt die
    Haupt-SSID). Er hängt zeitweise an derselben Dockingstation wie der Admin-Laptop, der dort über
    NetworkManager das ungetaggte Haupt-VLAN und getaggt alle übrigen VLANs nutzt (auch MGMT). Zwei Teile:
    * **(a) WLAN** ist umgesetzt (DW2.6), auf Hardware seit 2026-11-05 an einem Standort im Betrieb (an einem CAP:
      VLAN, Lease, Internet ja, LAN nein); offen: Roaming ([TESTSTAND.md](TESTSTAND.md#offen-auf-hardware)).
    * **(b) Kabel am gemeinsamen Dock** – *wartet auf 802.1X* (WPA-Enterprise/RADIUS, TODO 16; *Konzept 2026-11-22 mit
      Laborbefunden: [RADIUS.md](RADIUS.md), User Manager statt PacketFence, Fragen an den Nutzer offen*): Port mit
      dot1x und MAC-Auth, VLAN vom RADIUS. Die einfachen Wege tragen nicht: Eine Switch-Regel je MAC
      (`src-mac-address` + `new-vlan-id`; das Menü gibt es auf dem QCA-8386 eines hAP be³, Wirkung
      ungetestet) scheitert, wenn das Dock für beide Laptops mit seiner eigenen MAC sendet (ohne
      MAC-Passthrough). Den Port ungetaggt ins Gäste-VLAN zu legen (`hybrid:<gast>`, Admin-Laptop dann
      mit getaggtem Haupt-VLAN) wäre ohne Code möglich, schickt aber jedes Gerät ohne NM-Profil ins
      Gastnetz. **Rückfall umgesetzt 2026-11-05 (DP1.4):** Hostfile `portSwitch`, Skripte
      `cfm-port-<name>-normal/-alt/-toggle`, optional am Reset- oder Mode-Taster; Zustand in einer Datei, die jeder
      Apply übernimmt. Seit 2026-11-06 an einem Standort im Betrieb (hAP be³ Media): per Skript bestanden (Firmen-Laptop
      am Dock: Pool-Adresse in 175, Internet ja, LAN nein); Reset-Taster nach dem Fix (Code + `hold-time`, von Hand
      gesetzt) startet Skripte. Offen: Release mit dem Fix, dann Umschalten per Taster in beide Richtungen. Ohne Umschalten bleibt (b) bei 802.1X.
<!-- -->
67. **VIP als Gateway – Rest** (umgesetzt: `asymRouting`, DR3.2, Admin-Guide 8.13; TCP ins Internet auf
    Hardware bestanden 2026-10-31; 2026-11-12 auch für Netze hinter dem Internet-Router, DR3.2.1): **Offen:** Ausfall
    des Internet-Routers – bleiben die internen Wege?; VRRP-Wechsel; Portfreigabe auf einen Host mit Gateway VIP
    (DR3.2.1 auf Hardware bestanden 2026-11-13, [TESTSTAND.md](TESTSTAND.md#bestanden)). **Ziel danach:** Transfernetz für den
    Internet-Router (dann VIP für alle, zweiter Anschluss als Backup möglich), der Schalter entfällt.
68. **DNS der Router – Rest** (umgesetzt: DN3.1, Abfrage-Log per Syslog an Graylog, Admin-Guide 8.15;
    Hardware: [TESTSTAND.md](TESTSTAND.md#bestanden)): die Resolver-Container eines Standorts nach dem
    Parallelbetrieb abbauen; Namensschema der Standorte für `forward` (später, mit einem Standort-VPN der
    Router); DoH als Option. Selbstbedienung: 69.
69. **DNS-Selbstbedienung – Rest** (umgesetzt: DN3.2, Admin-Guide 8.14; Hardware bestanden 2026-10-31):
    `www-ssl` für die Anmeldung; befristete Freischaltung auch auf den anderen Routern (VRRP-Wechsel).
<!-- -->
73. **Feature-Module – Rest** (umgesetzt: DG4.6; Labor und Hardware an einem Standort:
    [TESTSTAND.md](TESTSTAND.md#bestanden)):
    * Hardware an einem Router mit `dns.rsc`: `/system/script/get cfm-dnsreq source` prüfen
      (Kopf `:local dur …`/`:local deny …` für cfm-DNS, Rumpf als Funktion `$dnsreq`), cfm-DNS-Freischaltung einmal
      durchspielen; dort auch die Listen „nicht hochgeladen“/„entfernt“ von `upload-seed.sh`.
    * *2026-11-04:* WLAN-Prüfung aus `mgr-check.rsc` nach `mgr-checkw.rsc` ausgelagert (DM1.1; 57,4 → 47,1 KB),
      Labor 7.25 ok (Gesamttest und Übergang, TESTSTAND), Hardware offen: erstes Release nach dem Update (der WLAN-Teil kommt aus `work/`). Nicht empfohlen:
      RouterOS-Update/Firmware aus dem Agent (DG4.3: heikelster Pfad).
74. **Hardware-Test WLAN nach den Fixes vom 2026-11-04 – Rest** (bestanden am ersten Standort, siehe
    [ERLEDIGT.md](ERLEDIGT.md#frühere-fassungen) und [TESTSTAND.md](TESTSTAND.md#bestanden)): **(c)** zwei Gäste an
    *verschiedenen* APs – kein Ping untereinander, Gateway und Internet gehen, Zähler `cfm:iso` an beiden APs (sieht der
    Bridge-Filter WLAN-Frames als `ip` oder `vlan`?); bisher nur an den Radios des CAPsMAN geprüft (12.11.). **Zweiter
    Standort** (hAP be³ als CAPsMAN): Fallback weiterer SSIDs mit Rückkehr, PPSK mit normaler Passphrase und
    FT-Roaming zwischen zwei CAPs. Geplant: Wochenende 28./29.11. am zweiten Standort.
75. **`$cfmSniff` bei gebrücktem Verkehr – Rest** (umgesetzt 2026-11-05: `mirror=<Port>`, DU2.3.1): auf Hardware
    prüfen – Eigenschaftsnamen je Switch-Chip (CRS3xx/5xx je Port, ältere Chips am Switch), geht die CPU als Ziel,
    CPU-Last, sieht der Sniffer die gespiegelten Frames. Erster Test: CRS418 an dem Standort, der nur brückt.
79. **Netinstall-Station und Branding-Paket umsetzen** (Plan 2026-11-11: [NETINSTALL.md](NETINSTALL.md), DO1.8,
    DT3.3; Prototyp `tools/branding/`): Branding-Paket im Branding Maker bauen (Login-Seite mit cfm-Start, Stub,
    CAPs-Mode-Skript, Skin, Logo), Onboarding-Schlüsselpaar im Manager (`$cfmSecret key=onboard.key`, Stufe 1 per
    `ssh-exec` statt Aufkleber-Passwort), Netinstall-Container (tikoci/netinstall) auf dem Backup-Manager eines
    Standorts mit VETH im Onboarding-VLAN, Paketquelle aus dem Spiegel-Cache; Test mit einem Ersatzgerät (hAP ax²).
    Vor dem Rollout auf Bestandsgeräte klären, ob die Installation des Pakets die Default-Config ausführt
    („Do not run script on install“, NETINSTALL.md O8).
80. **DynDNS per Anbieter-API** (`wireguard.rsc` `self.ddns.type="api"`, DR4.4): Schalter und Prüfung sind da, der
    Anbieter (Cloudflare, deSEC, Hetzner …) ist noch offen – bis dahin `dyndns2` (die meisten Anbieter, auch deSEC)
    oder `cloud`. Dazu aus 15 offen: Hardware-Test der Standortkopplung an beiden Standorten (Admin-Guide 8.17),
    `mgmt`↔`mgmt` über den Tunnel (bewusst nicht freigegeben, 2026-11-11), Namen der Standorte: B wechselt die
    Domain auf eine Subdomain von A (`b.example.net`) (Let's Encrypt später).
81. **A/B-Messung Fritz-Tunnel gegen cfm-Standortkopplung** (Nutzer, 2026-11-12): Beide Standorte bekommen die
    Kopplung vorbereitet (`sites` ohne `pubkey`, DR4.3.1), A `asymRouting` mit dem Netz von B (DR3.2.1). **A:** über
    den LAN-LAN-Tunnel der Fritz!Boxen messen. **B:** Fritz-Tunnel an beiden Boxen aus, Fritz!Box-Routen setzen
    (B: Netze von A → Router von B; A: Netz von B → VIP), `pubkey` beidseitig eintragen, Release; dieselben Messungen. *Stand 2026-11-13:* Vorbereitung an beiden Standorten
    ausgerollt (ohne `pubkey`, DR3.2.1 bestanden); beide `wgsitepub` notiert (Site-Logbücher). Als Nächstes Messung A
    (Laptop am Kabel im LAN von B, vor Ort). Messgrößen:
    Durchsatz in beide Richtungen (iperf3, ein und vier Streams), Latenz und Jitter (Ping 100×), CPU der Router beider Standorte
    unter Last, je ein Host mit Gateway VIP und einer mit Fritz!Box-Gateway in A. Danach Entscheidung (Nutzer), welcher
    Tunnel bleibt; beim cfm-Tunnel den `asymRouting`-Eintrag entfernen, beim Fritz-Tunnel `pubkey` wieder leer.
99. **Flottenzustand als JSON für Home Assistant** (Idee des Nutzers, 2026-11-25, nach dem Muster von `$cfmNetbox`,
    DT2.3): HA bekommt heute nur Ereignisse per Webhook (`$cfmNotify`, DU4.1) und live über die RouterOS-API
    Clients, SSID und Port (6.7–6.9, `cfm_ssid.py`, `cfm_port.py`; die bleiben live, ein Export wäre zu alt). Ein
    dauerhafter Zustand fehlt. Vorschlag: Der Manager schreibt in `$cfmNotifyTick` (rechnet die Zustände ohnehin)
    zusätzlich `state/fleet.json` mit je Gerät: erreichbar/stumm (seit), Release und Ring (Soll/Ist, Apply
    ok/Fehler), RouterOS-Version und offenes Update, Lizenz, offene Meldungen aus `meta/notify.dat`; dazu Summen
    (z.B. „3 Geräte nicht aktuell“). Nur schreiben, wenn sich etwas ändert (Flash). HA liest die Datei mit dem
    vorhandenen Lese-User über die API (Client aus `cfm_ssid.py`, neues Hilfsskript `cfm_fleet.py`, Ausgabe für
    `command_line`-Sensoren mit `json_attributes`) oder per REST, falls `www-ssl` an ist. Zu klären vor dem Bau: welche
    Sensoren HA wirklich braucht, Zugriff auf Dateien über die API mit `read`-Gruppe (Größe, `contents`),
    Standby/Backup-Manager (Datei nur auf dem Primary; HA fragt die Manager-VIP oder beide). Ersetzt nichts
    Vorhandenes (`$cfmStatus`, `netzplan.*` bleiben für die Konsole). Kommt ein zweites Python-Tool dazu, das die
    Manager-JSONs liest, wandert das Einlesen (Zahlen aus `:serialize`, `[]`) aus `tools/netbox-abgleich.py` in ein
    gemeinsames `tools/cfm_state.py`.
