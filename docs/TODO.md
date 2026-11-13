# TODO – geplante Verbesserungen

## Übersicht offener Punkte (Stand 2026-11-11)

Erledigtes steht in [ERLEDIGT.md](ERLEDIGT.md): der Verlauf, die erledigten Punkte mit ihren Nummern und die
behobenen Fehler. Ist von einem Punkt nur ein Rest offen, steht er hier gekürzt auf diesen Rest, der frühere
Text ebenfalls dort. Neue Punkte bekommen die nächste freie Nummer (ab 81). Was auf Hardware und im Labor
geprüft ist: [TESTSTAND.md](TESTSTAND.md). Offen, grob nach Nutzen:

* **Neu 2026-11-11, Labor grün (12.11.):** Standortkopplung (15, DR4.3) mit DynDNS (DR4.4) und Freigaben nach Domain
  bzw. je Client (20, DR2.8/DR2.9) sind umgesetzt und im Labor bestanden (`e2e-vrrp.sh` 164, `e2e.sh` 477). Nächster
  Schritt: Rollout an beiden Standorten (Site-Overlays vorbereitet, Reihenfolge Admin-Guide 8.17), Hardware-Test (80).
  Netinstall/Branding: Plan in [NETINSTALL.md](NETINSTALL.md), Umsetzung 79.
  *Nachtrag 2026-11-12:* Der LAN-LAN-Tunnel der Fritz!Boxen bleibt vorerst (DR3.2.1: `asymRouting` mit Netzen, damit
  Hosts mit Gateway VIP darüber erreichbar sind; DR4.3.1: Standort ohne `pubkey` nur vorbereitet). Reihenfolge des
  Nutzers: erst die offenen Tests an Standort B (74), dann cfm-Tunnel vorbereiten, A/B-Messung gegen den Fritz-Tunnel (81).
* **Zuerst: Test vor Ort (74)** der drei Fixes vom 2026-11-05 (unter „Bekannte Fehler“): Fallback-Kopie
  (DW1.8.1), normale Passphrase bei PPSK (DW2.2.1), `cfm-iso` nach `slaves-static` (DP3.1.1). Der Code läuft seit
  2026-11-06 an einem Standort (v99), die Tests dort stehen aus.
* **Vorbereitet, Test nur mit Hardware vor Ort** (Code fertig, standardmäßig aus, im Labor nur
  Darstellung und Prüfung): 40a (Gast/IoT im lokalen Fallback,
  DW1.8; erster Versuch 2026-11-04 scheiterte am Fehler unten). 39 (Steering je Band + Mindestsignal, DW2.4) läuft seit 2026-10-17 an einem Standort
  ([TESTSTAND.md](TESTSTAND.md#bestanden)).
* **Nur mit Hardware:** die Punkte unter „Offen auf Hardware“ in [TESTSTAND.md](TESTSTAND.md#offen-auf-hardware). Das eingebaute Update
  (38, DV1.5) lief über den Spiegel (hEX) und per `via=internet` (CRS, 7.25).
* **RouterOS 7.25:** stable seit 2026-10-22, beide Standorte seit 2026-10-26/28 darauf
  ([TESTSTAND.md](TESTSTAND.md)); offen aus 48: FT für MLD (DW2.3).
* **Zurückgestellt:** 25 (WebFig per HTTPS – bis Let's Encrypt über acme-dns steht), 22 (Disk-Logging
  – ein externer Syslog-Server ist geplant; *seit 2026-11-01 an einem Standort in Betrieb, Graylog 8.15*).
* **Vorbereitet, Test nur mit Hardware:** MLAG auf CRS3xx (Hardware-Offload, Ausfall eines Knotens,
  Umbau im laufenden Betrieb), isolierte VLANs an echten APs (seit 2026-11-04 im Betrieb an einem Standort; der
  CAPsMAN gibt `interface-list` **nicht** an die CAPs weiter. Offen: Wie sieht der Bridge-Filter WLAN-Frames? Zwei
  Gäste an verschiedenen APs) und an Switch-Ports mit `hw=no`.
* **Größere Ausbauten:** 13, 14, 16, 18 sowie 79 (Netinstall-Station und Branding-Paket, Plan in
  [NETINSTALL.md](NETINSTALL.md)).
* **Offen im Verbesserungsplan:** 6, 13, 14, 16, 18, 21–23, 25, 37, 40, 48, 49, 51, 54, 55, 58, 62, 63, 65, 67–69, 72–75,
  78–82.

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

Drei Fehler aus dem Hardware-Test vom 2026-11-04 (CRS418 als CAPsMAN, hAP ax² als CAPs, 7.25; Eigenheiten dazu in
[ROUTEROS-EIGENHEITEN.md](ROUTEROS-EIGENHEITEN.md#auf-hardware-verifizierte-routeros-eigenheiten)). *Im Code behoben
2026-11-05 (DW1.8.1, DW2.2.1, DP3.1.1), im Labor geprüft soweit ohne Funk möglich ([TESTSTAND.md](TESTSTAND.md)); der
Test vor Ort (74) steht aus – bis dahin bleiben sie hier.*

* **Zweiter Apply nach `slaves-static` stellt noch einmal um** (DW1.8.1, Labor 7.25.1, 2026-11-05): Nach dem
  Umstellen startet `cfm-apfollow` den zweiten Apply; der setzt `slaves-static` erneut („gesetzt: /interface/wifi/cap:
  slaves-static“) und legt `cfm-apfollow` noch einmal an – ein zusätzliches Neuverbinden des CAP, danach ist Ruhe.
  In zwei Läufen gesehen, in den Läufen auf 7.25 nicht. Von Hand nicht nachgestellt: Mit zwei VMs (CAPsMAN + CAP,
  7.25.1) bleibt der Wert nach dem Neuverbinden `true`. Ursache offen; bis dahin `fallback` an weiteren SSIDs nur zu
  ruhiger Zeit einschalten. Der e2e-Test traf das Zeitfenster nur manchmal (wackelt).
* **`fallback="yes"` hängt keine lokale Kopie an** (DW1.8, `roles/ap.rsc`): Die Rolle erkennt die SSID eines vom
  CAPsMAN angelegten virtuellen AP an `configuration.ssid` bzw. `monitor`→`ssid` – am CAP ist beides leer, die SSID
  steht nur in `monitor`→`about` („mode: AP, SSID: Gast“). Folge: Nur `slaves-static` wirkt, im Fallback fällt die
  SSID weiter aus. Fix: SSID ersatzweise aus `about` lesen (Text nach `SSID: ` bis `,`/`;` – wie schon der Kanal
  im Agent), im Probelauf melden, wenn ein virtueller AP ohne erkennbare SSID bleibt.
* **Mit PPSK geht die normale Passphrase der SSID nicht mehr** (DW2.2, `lib/lib-wifi.rsc`, Secret-Push): RouterOS
  ignoriert die `passphrase` eines Profils mit `multi-passphrase-group`. Fix: Für jede SSID mit `ppsk` einen
  Gruppeneintrag ohne `vlan-id` (Kommentar z.B. `cfm:mpp:<ssid>`) mit der Passphrase aus `psk.<ssid>` anlegen – auf
  dem CAPsMAN und im lokalen Fallback der APs; der Secret-Push setzt ihn wie die übrigen Einträge. Weil Ändern oder
  Entfernen eines Eintrags dessen Clients trennt: Secret-Push und Rolle setzen die Passphrase nur, wenn sie sich
  ändert (Vergleich vor dem `set`; ob ein `set` mit gleichem Wert trennt, ist offen), und legen Einträge nicht neu an.
  Admin-Guide (PPSK) und DW2.2 ergänzen. Bis dahin ist die betroffene SSID an einem Standort aus.
* **`cfm-iso` nach dem Umstellen auf `slaves-static` veraltet** (DP3.1/DW1.8, `roles/ap.rsc`): Der Apply, der
  `slaves-static` setzt, trennt den CAP vom CAPsMAN; der CAP legt die virtuellen APs danach mit neuen Namen an. Die
  Rolle trug im selben Lauf noch das alte Interface ein (`wifi3`), erst der zweite Apply die neuen – dazwischen
  (12 min) griff der Bridge-Filter für Gäste vermutlich nicht. Dieselbe Lücke hat die Fallback-Kopie (braucht ohnehin
  den zweiten Apply). Fix: Nach einer Änderung von `slaves-static` stößt der Agent selbst einen zweiten Apply an,
  sobald der CAP wieder verbunden ist (ähnlich dem Nachfassen in DW1.11), statt auf `$cfmPush … force=yes` zu bauen.
  Dazu die Frage, ob isolierte SSIDs ohne `slaves-static` sicher sind: Dynamische Interfaces entstehen bei jedem
  Neuverbinden des CAP neu, das statische Mitglied in `cfm-iso` zeigt dann bis zum nächsten Apply ins Leere
  (Eigenheit „Verweis auf ein Interface“). Vorschlag zur Entscheidung: `isolate` an einer SSID setzt `slaves-static`
  mit, oder der Agent prüft `cfm-iso` bei jedem Lauf.

* **Backup-Manager: Einspielen der Manager-Module scheitert** (`roles/manager.rsc`, hAP be³ Media 7.25.1,
  2026-11-08): zweimal `no such item (/file/get; line 26)` gleich nach dem Ersetzen eines anderen Modul-Skripts,
  Rollback mit Neustart; von Hand nicht nachgestellt. Abwehr seit DM1.1.1 (erst lesen, dann setzen, Wiederholung,
  Log-Zeile mit Dateiname). Bleibt hier, bis ein Framework-Update an einem Backup auf Flash durchläuft; tritt es
  wieder auf, steht die Datei im Log.

* **Tick des Backup-Managers bricht ab: `no such item (/file/get; line 237)`** (Labor 7.25.1, 2026-11-08, cm2): Im
  Zweig für den Backup ruft `$cfmTick` `$cfmIsPrimary` auf; ist `cfmG` nicht geladen, liest `$cfmLoadData`
  (`mgr-core.rsc`) `work/global.rsc` … ohne `:onerror` – der Backup spiegelt kein `work/`. Der Tick fällt dann aus
  (kein Spiegel bis zum nächsten). Fix: `$cfmIsPrimary` ohne `$cfmLoadData` (Managerliste aus `cfm-conf` bzw.
  `meta/`), oder `$cfmLoadData` tolerant gegen fehlende Dateien.

* **Labor-Wackler MNDP mit Quelle 0.0.0.0** (`e2e.sh` Abschnitt 14, DR2.5): Die Prüfung „cm1: MNDP mit Quelle
  0.0.0.0 still verworfen“ wartet auf einen Treffer im Zähler der Drop-Regel. Fehlschläge 2026-10-31, 2026-11-06 und
  2026-11-08 (7.25.1) – auch nach dem Anstoßen (MNDP an cm2 aus und wieder an, danach bis zu 120 s): Zähler 0, cm2
  sendet MNDP (`cdp;lldp;mndp`, 30 s). Das Verhalten stimmt jeweils (kein `cfm-drop` im Log). Offen: Sendet cm2 über
  den Bridge-Port ohne Adresse nur manchmal mit Quelle 0.0.0.0? Gegenprobe per Sniffer an cm1 `ether3`.

* **Labor-Wackler MLAG: sw2 im zweiten Apply nicht idempotent** (`e2e-mlag.sh` Schritt 7, 7.25.1, 2026-11-08): einmal
  `add=6;rem=3;set=6`, sw1 mit derselben Rolle sauber, die Wiederholung grün. Die VMs waren schon ersetzt, das
  Agent-Log von sw2 fehlt. Bei Wiederkehr vor dem Stoppen `/log/print where message~"gesetzt|entfernt|angelegt"`
  auf sw2 sichern.

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

6. **Plan-Modus – Rest** (umgesetzt: DG3.4): Grenze der Berichtsgröße bei sehr großen Plänen prüfen.

### Größere Ausbauten

13. **IPv6** (Präfixe je VLAN, Router Advertisements, IPv6-Firewall).
14. **Zentrale Admin-Anmeldung per RADIUS** (User Manager auf dem Manager).
16. **WPA2/WPA3-Enterprise** (externer RADIUS oder User Manager) – Rest von „WLAN-Ausbau“ (umgesetzt: DW2.2);
    Voraussetzung für 65b. PPSK-VLANs auf Hardware: [TESTSTAND.md](TESTSTAND.md#offen-auf-hardware).
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
25. **WebFig per HTTPS** – *zurückgestellt (2026-10-01), bis Let's Encrypt über acme-dns mit einer
    öffentlichen Domain steht (dann Zertifikat per DNS-Challenge statt selbstsigniert).* – `services` kennt `www-ssl`, die Rolle `base` setzt aber nur Port und
    Adressen; ohne Zertifikat lauscht RouterOS dort nicht. Bis dahin geht das Web-Interface nur
    per `www` (HTTP, Passwort unverschlüsselt, auf die Management-Netze begrenzt). Umsetzung:
    je Gerät ein selbstsigniertes Zertifikat (oder von einer CA auf dem Manager signiert) anlegen,
    an `www-ssl` hängen und bei Namens-/Adressänderung erneuern; danach `www` abschalten.
<!-- -->
37. **Paketprüfung – Rest** (umgesetzt: DV1.4, NPK-Kennung): Prüfsummen von MikroTik nutzen, falls es eine
    Liste gibt.
<!-- -->
40. **Lokaler Fallback der APs: weitere SSIDs** (DW1.6) – *vorbereitet (DW1.8):* `fallback="yes"` an einer
    SSID schaltet `slaves-static` ein und hängt den virtuellen APs eine lokale Kopie an. Offen ist der Test vor
    Ort (CAPsMAN-Dienst kurz aus): Lässt `/interface/wifi/cap slaves-static=yes` die vom CAPsMAN angelegten
    virtuellen APs im Fallback mit ihrer lokalen Konfiguration weiterlaufen? Erst mit einer zweiten aktiven
    SSID auf Hardware testbar; bis dahin fallen Gast/IoT im Fallback aus. *2026-11-04:* an einem Standort aktiv
    (`slaves-static` gesetzt, virtuelle APs statisch), die lokale Kopie fehlt wegen eines Fehlers („Bekannte Fehler“);
    Test nach dem Fix (74). Die erledigten Teile (b)–(e) stehen
    in [ERLEDIGT.md](ERLEDIGT.md#frühere-fassungen).
<!-- -->
48. **RouterOS 7.25 – Rest** (Befunde und Changelog-Durchsicht: [ERLEDIGT.md](ERLEDIGT.md#frühere-fassungen),
    Läufe: [TESTSTAND.md](TESTSTAND.md)): **FT für MLD-Geräte** („wifi - add fast transition support for MLD
    devices“): DW2.3 hat MLO abgeschaltet, weil der hAP be³ als MLD kein FT anbot. Mit einem Client prüfen, ob
    MLO mit FT jetzt geht (`wifi.rsc` `mlo`); danach ggf. MLO für weitere SSIDs oder lokal (32).
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
55. **Netbox** (Idee, 2026-10-16, vorerst nicht) – zwei Varianten merken:
    * **Einweg-Export cfm → Netbox:** Tool liest das Overlay (`pull-site.sh`), `inventory.rsc`,
      `vlans.rsc`, `leases.rsc` und `netzplan.csv` (`$cfmLinks`) und legt per API Site, Geräte
      (Modell, Seriennummer, Rolle, RouterOS-Version), Interfaces, MGMT-IPs, VLANs, Prefixe, feste IPs
      mit DNS-Namen und Kabel an. Nur Doku, für die Fehlersuche wenig Nutzen.
    * **Netbox als Quelle:** Netbox erzeugt `vlans.rsc`/`leases.rsc` u.a. Widerspricht DT2.2 (der Manager
      führt die Site-Daten, der cfm-Editor schreibt hinein) – bräuchte eine neue Entscheidung, wer gewinnt.
<!-- -->
58. **Schaltbare SSID – Rest** (umgesetzt: feste Interfaces DW4.2, Neuprovisionieren DW4.3; Umstieg und
    Rückweg im Admin-Guide 6.8; *Hardware 2026-11-04:* Grundzustand aus, Einschalten mit Ablauf nach 8 h, Aus/Ein
    startet das Radio nicht neu – andere SSIDs ohne Unterbrechung). Offen: Aufräumen der festen Interfaces eines abgebauten AP (bisher von Hand, Admin-Guide 7.4); bleiben beim
    Abschalten von `capsmanRadios` feste Interfaces der eigenen Radios stehen? Zusammenspiel mit
    `slaves-static` (DW1.8). Rückfall, falls feste Interfaces nicht tragen: nacheinander provisionieren (je AP
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
63. **NTP-Umleitung – Rest** (umgesetzt: DN2.2, seit 2026-10-24 an einem Standort): Uhrzeit in der
    Weboberfläche einer OpenBeken-Lampe prüfen.
65. **Fremdgerät mit der Haupt-SSID bzw. am gemeinsamen Dock ins Gäste-VLAN** (Wunsch des Nutzers, 2026-10-26)
    – *Anlass:* Ein Firmen-Laptop soll nicht ins Hauptnetz, ist aber kein richtiger Gast (kennt die
    Haupt-SSID). Er hängt zeitweise an derselben Dockingstation wie der Admin-Laptop, der dort über
    NetworkManager das ungetaggte Haupt-VLAN und getaggt alle übrigen VLANs nutzt (auch MGMT). Zwei Teile:
    * **(a) WLAN** ist umgesetzt (DW2.6), auf Hardware seit 2026-11-05 an einem Standort im Betrieb (an einem CAP:
      VLAN, Lease, Internet ja, LAN nein); offen: Roaming ([TESTSTAND.md](TESTSTAND.md#offen-auf-hardware)).
    * **(b) Kabel am gemeinsamen Dock** – *wartet auf 802.1X* (WPA-Enterprise/RADIUS, TODO 16): Port mit
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
72. **Band je AP abschalten, Antennengewinn je AP** (Idee eines Standorts, 2026-10-26; nur nötig, wenn dort eine
    Außenantenne kommt) – Anlass: Ein AP soll eine seiner beiden Antennen (je Kette beide Bänder) nach außen führen.
    In der EU ist 5150–5350 MHz nur in Innenräumen erlaubt; `wifi.rsc` kennt je AP heute nur das Pinning `radios`
    (fester Kanal je Band) – weder ein Band je AP abschalten noch `antenna-gain` (EIRP) noch Sendeleistung. Idee:
    `radios` → `{"<ap>"={"5"="off"}}` (keine Provisionierung dieses Bands, Radio aus) und `antennaGain` je AP und
    Band (Parameter in der RouterOS-wifi-Doku prüfen; hält er beim Provisionieren durch den CAPsMAN?). Alternative
    ohne Framework: eigener Außen-AP (dieselbe 5-GHz-Regel). Offen, Entscheidung des Nutzers.
73. **Feature-Module – Rest** (umgesetzt: DG4.6; Labor und Hardware an einem Standort:
    [TESTSTAND.md](TESTSTAND.md#bestanden)):
    * Hardware an einem Router mit `dns.rsc`: `/system/script/get cfm-dnsreq source` prüfen
      (Kopf `:local dur …`/`:local deny …` für cfm-DNS, Rumpf als Funktion `$dnsreq`), cfm-DNS-Freischaltung einmal
      durchspielen; dort auch die Listen „nicht hochgeladen“/„entfernt“ von `upload-seed.sh`.
    * *2026-11-04:* WLAN-Prüfung aus `mgr-check.rsc` nach `mgr-checkw.rsc` ausgelagert (DM1.1; 57,4 → 47,1 KB),
      Labor 7.25 ok (Gesamttest und Übergang, TESTSTAND), Hardware offen: erstes Release nach dem Update (der WLAN-Teil kommt aus `work/`). Nicht empfohlen:
      RouterOS-Update/Firmware aus dem Agent (DG4.3: heikelster Pfad).
74. **Hardware-Test WLAN nach den Fixes vom 2026-11-04** (an beiden Standorten: CRS418 bzw. hAP be³ als CAPsMAN,
    nächste Termine vor Ort): (a) Fallback einer Gast-SSID – CAPWAP zu einem AP sperren, sendet die SSID lokal weiter,
    Lease, Isolation, Rückkehr (40, DW1.8); (b) PPSK: normale Passphrase und PPSK nebeneinander, FT-Roaming zwischen
    den APs mit PPSK, gibt der CAPsMAN die Gruppe an die CAPs weiter (oder gelten die lokalen Einträge), trennt der
    Secret-Push laufende PPSK-Clients (DW2.2); (c) isoliertes Gast-VLAN mit zwei Gästen an verschiedenen APs, Zähler
    der Bridge-Filter am AP (sieht er WLAN-Frames als `ip` oder `vlan`?), Limit unverändert (DP3.1); (d) zweiter Apply
    nach `slaves-static` kommt von selbst. Danach [TESTSTAND.md](TESTSTAND.md) „Offen auf Hardware“ nachziehen.
    *2026-11-12 an einem Standort (v37):* (b) bestanden bis auf das Roaming zwischen zwei CAPs (Befund „falsches
    Passwort“ beim ersten PPSK-Versuch, Ursache offen – nicht WPA3, Korrektur 2026-11-13, siehe TESTSTAND), (c) bestanden an den Radios des CAPsMAN, die lokale Kopie aus (a) hängt an; offen: (a) Client-Test im
    Fallback, (c) an zwei APs mit Zählern, (d), der zweite Standort.
75. **`$cfmSniff` bei gebrücktem Verkehr – Rest** (umgesetzt 2026-11-05: `mirror=<Port>`, DU2.3.1): auf Hardware
    prüfen – Eigenschaftsnamen je Switch-Chip (CRS3xx/5xx je Port, ältere Chips am Switch), geht die CPU als Ziel,
    CPU-Last, sieht der Sniffer die gespiegelten Frames. Erster Test: CRS418 an dem Standort, der nur brückt.
79. **Netinstall-Station und Branding-Paket umsetzen** (Plan 2026-11-11: [NETINSTALL.md](NETINSTALL.md), DO1.8,
    DT3.3; Prototyp `tools/branding/`): Branding-Paket im Branding Maker bauen (Login-Seite mit cfm-Start, Stub,
    CAPs-Mode-Skript, Skin, Logo), Onboarding-Schlüsselpaar im Manager (`$cfmSecret key=onboard.key`, Stufe 1 per
    `ssh-exec` statt Aufkleber-Passwort), Netinstall-Container (tikoci/netinstall) auf dem Backup-Manager eines
    Standorts mit VETH im Onboarding-VLAN, Paketquelle aus dem Spiegel-Cache; Test mit einem Ersatzgerät (hAP ax²).
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
82. **WLAN-Schild im cfm-Editor** (DT3.4, Nutzer 2026-11-12): eine Seite „Schild drucken“ im cfm-Editor/-Monitor,
    die SSID und Passphrase vom Gerät liest und das Schild über den Druckdialog als A4-PDF ausgibt (wie
    `tools/wifi-sign.py`). Braucht einen eingebetteten QR-Encoder in JavaScript (kein CDN, der Editor lädt seinen Code
    vom Gerät) und eine Antwort, wie die Seite an die Passphrase kommt (Vault nur auf dem Manager).
78. **Manager-Bibliothek beim Release aus `work/` laden** (geplant 2026-11-09, nach der Auswertung des WLAN-Tests an
    einem Standort): `cfm-mgr` lädt die installierten Skripte `cfm-mgr-*`. Nach einem Framework-Update laufen
    `$cfmCheck`, `$cfmPlan` und das erste `$cfmRelease` deshalb mit der alten Bibliothek – heute muss man jede neue
    `lib/mgr-*.rsc` vorher von Hand importieren (Admin-Guide 8.1, mehrfach vergessen: v95, 6.11.). Wie der Prüfer
    (DG4.1) sollen die Befehle die Module aus `work/lib/` laden, wenn sie neuer sind als die installierten.
