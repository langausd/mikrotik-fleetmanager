# TODO – geplante Verbesserungen

## Übersicht offener Punkte (Stand 2026-09-30)

Erledigtes ist unten durchgestrichen und bleibt als Befund stehen. Offen, grob nach Nutzen:

* **Nur mit Hardware vor Ort testbar:** 40a (weitere SSIDs im lokalen Fallback), 39 (Mindestsignal,
  vorher die Abdeckung prüfen), 41 (`$cfmWifiScan`, ein Scan unterbricht die Radios), 24 (eigene
  Radios des Managers/CAPsMAN), 38 (RouterOS-Update bei 16 MB Flash) sowie die Punkte unter „Noch
  nicht mit echter Hardware getestet“.
* **Remote bzw. im Labor machbar:** 25 (WebFig per HTTPS), „Manager-Ticks starten gleichzeitig“
  (Bekannte Fehler), Rest von 44 (Spiegel-Sync und Agent gegeneinander sperren), 21 (weniger
  `/file/find` im Tick), 36 (Labortest für Vorabversionen). Erledigt am 2026-09-30: 28, 29, 30, 31,
  35, 37, 38 (Vorab-Prüfung).
* **Größere Ausbauten:** 2 (Benachrichtigungen), 10–15, 18–21 sowie Netinstall/Branding (Onboarding).

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
übernommen (routet noch selbst, D43), hAP be³ als CAPsMAN (D45) und AP (Wi-Fi 7, D44/D48), hAP ax³,
cAP ax, hEX und L009 als Switches; Onboarding im CAPs-Modus, CAPsMAN-Umzug, lokaler Fallback (D46)
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
* PPSK-VLANs, VRRP mit mehreren Routern. ~~Umzug der Rolle `capsman`~~ (D45) am 2026-09-27 von
  einer CHR auf einen hAP be³ gelaufen, vier APs folgten samt Zertifikatswechsel. Zwei APs
  (hAP ax²) mit CAPsMAN, SSID-VLAN über den lokalen Datapath (D41), WPA2/WPA3 + FT und Clients
  mit `ft-wpa3-psk` laufen seit 2026-09-24, Roaming zwischen den beiden APs klappt (2026-09-25)
* Hook Manager → Git-Host per `ssh-exec` (die Pull-Seite `cfm-git-sync` ist getestet)
* Rolle `router` auf einem CRS mit L3-Hardware-Offloading (D37): schaltet sie `l3-hw-offloading` ab,
  läuft VRRP danach, und gibt es beim Umschalten einen Aussetzer im gerouteten Verkehr?
* Feste NAT-Adresse (`wan@<Adresse>`, D38) bei VRRP: Wandert die Adresse mit dem Master, und
  übernimmt der neue Master den ausgehenden Verkehr ohne Hand-Eingriff (bestehende Verbindungen
  brechen ab, conntrack wird nicht abgeglichen)?

## Bekannte Fehler

* **Manager-Ticks starten gleichzeitig:** `cfm-mgr-tick` (alle `mgrTick`) und `cfm-mgr-onb-tick` (jede
  Minute) haben beide `start-time=startup` und laufen deshalb zur selben Sekunde los, im Labor mit
  `mgrTick=1m` jede Minute. Bisher nur als Zeitversatz beobachtet (Onboarding-Test: Status von ob1
  und Rückstellung des Onboarding-Ports einige Sekunden später, einmal ein leerer Status beim Lesen).
  Vorschlag: Start des Onboarding-Ticks versetzen oder beide Ticks gegenseitig ausschließen.
  *Teilweise erledigt (D42):* Jeder Tick überspringt sich, solange sein eigener Vorlauf noch läuft;
  gegeneinander sind die beiden Ticks weiterhin nicht gesperrt.
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
2. **Benachrichtigungen** (E-Mail oder Push-Dienst wie ntfy/Telegram) bei Fehler/Rollback, stummen
   Geräten, gescheitertem Onboarding, CAPs im lokalen Fallback (D46).
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
   auf den Backup-Manager spiegeln; Vorabversionen im Labortest (TODO 36).
8. ~~**Identitätsprüfung vor dem Secret-Push**~~ – *erledigt (D28):* Challenge-Response mit dem
   Geräteschlüssel; Erneuerung per `$cfmRekey`. Offen: SFTP-Schlüssel (`cfmd-<name>`) rotieren
   (bisher nur per `$cfmEnroll … rekey=yes`).
9. ~~**Minimale Firewall auf allen Geräten**~~ – *erledigt (D31):* Default-Drop auf Nicht-Routern,
   IPv6-input auf allen Geräten. Offen: IPv6-Forward auf Routern (mit Punkt 13).
10. **Link-Bündel (Bonding/LACP) als Port-Profil** für Uplinks.
11. **Feste DHCP-Leases und DNS-Namen aus zentralen Daten** (z.B. `leases.rsc`).
12. **Effektive Config und Diff anzeigen:** `$cfmShow host=<n>`, `$cfmDiff ver=A ver=B`.

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
19. **Individuelle `authorized_keys` je Admin-Benutzer** – aktuell (D35) gilt eine einzige
    `authorized_keys`-Datei für ALLE User aus `global.rsc` `users`; bei mehreren Admins sollte
    jeder Benutzer nur seine eigenen Keys bekommen (z.B. `authorized_keys.<user>` oder Zuordnung
    innerhalb der Datei), inkl. Revocation pro Person statt nur global.
20. **IoT-Isolation ausbauen** (nach D38/D39): gerätespezifische Freigaben über kleinere Zonen
    erproben (eigenes VLAN/PPSK-Gruppe je Gerätegruppe); Freigaben nur für bestimmte Ports;
    Proxy als Ziel (transparent, Filter nach Domain) für Geräte, deren Cloud-Adressen häufig
    wechseln. WLAN-Client-Isolation trennt laut MikroTik nur Clients am selben AP – für
    isolierte Zonen über mehrere APs zusätzlich einen Bridge-Filter auf den APs (nur zum Gateway).
21. **Weniger `/file/find` im Manager-Tick** – Hardware-Befund (CRS418, RouterOS 7.22.2): eine
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
    Gerät umsetzen und testen; bis dahin erkennt cfm das Paket nicht und warnt auch nicht.
24. **Eigene Radios des Managers** (z.B. CRS418-…-5axQ2axQ): Die Rolle `manager` rendert nur den
    CAPsMAN, die eingebauten Radios bleiben unkonfiguriert. *Entschieden 2026-09-25: Sie sollen
    mitfunken.* Offen ist das Wie, vor der Umsetzung als Designfrage vorlegen: Rolle `ap` zusätzlich
    auf dem Manager (lokaler CAP des eigenen CAPsMAN – in der MikroTik-Doku prüfen, wie ein CAP den
    CAPsMAN auf demselben Gerät findet) oder die Rolle `manager` stellt die lokalen Radios direkt
    auf `configuration.manager=capsman`. Beide müssen im selben FT-Verbund wie die übrigen APs
    landen. Test nur auf der Hardware des Pilots möglich.
25. **WebFig per HTTPS** – `services` kennt `www-ssl`, die Rolle `base` setzt aber nur Port und
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
36. **Vorabversionen in `$cfmUpgrade`** – `$cfmVerGe` las „7.25beta5“ als 7.0 (`[:tonum "25beta5"]`
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
38. **RouterOS-Update auf Geräten mit 16 MB Flash** (hEX RB750Gr3, CRS328 u.ä.) – *Vorab-Prüfung
    erledigt (D51):* Agent meldet den freien Platz (`fs`), `$cfmUpgrade` erteilt zu vollen Geräten
    keinen Auftrag, der Agent prüft vor dem Download erneut. Offen bleibt das Update selbst (tmpfs
    oder eingebautes Update, nur mit Hardware testbar). – `$cfmUpgrade` lädt
    die Pakete per SFTP in den Flash des Geräts; dort sind oft nur 2–3 MB frei, `routeros` braucht
    ~12 MB. Das eingebaute Update (`/system/package/update`) kommt damit zurecht, braucht aber Internet
    am Gerät. Optionen: Pakete in eine tmpfs-Disk (`/disk add type=tmpfs`) laden und von dort
    installieren, falls RouterOS das zulässt; oder für solche Geräte das eingebaute Update über einen
    Proxy/Update-Pfad des Managers. `$cfmUpgrade` sollte vorab den freien Platz prüfen und klar abbrechen.
39. **Mindestsignal für Clients** (Entscheidung offen) – Hardware-Befund Roaming-Test mit FT: Die
    Wechsel selbst dauern meist unter 1 s, aber Clients bleiben lange an einem schwachen AP hängen
    (z.B. −79 dBm auf 2,4 GHz, viele kurze Aussetzer), obwohl ein stärkerer AP in Reichweite ist; ein
    Client verlor sogar erst die Verbindung, bevor er wechselte. FT beschleunigt nur den Wechsel, nicht
    die Entscheidung dazu. Idee: `/interface/wifi/access-list` mit `signal-range` aus `wifi.rsc`
    rendern (z.B. Clients unter −75 dBm abweisen bzw. trennen), optional je Band oder AP; dazu prüfen,
    ob die Steering-Einstellungen (`rrm`/`wnm`, BSS Transition) aktiv zum Wechsel auffordern.
    Risiko: In Randbereichen ohne besseren AP verliert ein Client dann ganz die Verbindung – vorher
    die Abdeckung prüfen (Löcher zwischen APs).
40. **Lokaler Fallback der APs (D46), offene Punkte** (a offen, b/c/d/e erledigt) – Umgesetzt ist die `master`-SSID je Radio
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
41. **Kanalplan per Scan** (entschieden 2026-09-27: fester Plan, gelegentlich neu optimieren) –
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
44. ~~**Agent auf einem Backup-Manager fragt sich selbst**~~ – *behoben:* `$cfmFetch` überspringt die
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
