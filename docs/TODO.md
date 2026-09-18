# TODO – geplante Verbesserungen

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
(`router,manager`) und ein hAP ax² als AP. Die gefundenen Fehler sind behoben
([DECISIONS.md](DECISIONS.md#auf-hardware-verifizierte-routeros-eigenheiten)). Offen bleiben:

* Onboarding-Push gegen echte Werks-Configs: Router (ether1 = WAN mit Firewall), CRS-Switches,
  APs im CAPs-Modus, Geräte mit Aufkleber-Passwort und `flash/`-Verzeichnis
* Onboarding eines hAP per PoE an ether1 im CAPs-Modus (Reset-Taster, LED-Verhalten je Modell)
* Manager-Bootstrap mit Reset (`clean="yes"`) auf Hardware, besonders die Übergabe an cfm per
  SFTP-`.auto.rsc` nach dem Hochfahren und Geräte mit `flash/`
* Bridge nach Neustart/Rollback: Auf CHR nimmt eine Bridge mit VLAN-Filtering nach dem Boot
  sporadisch keine getaggten Frames an (cfm startet die Ports dann neu). Betrifft das auch Geräte
  mit Switch-Chip? Auf Hardware prüfen, ob die Log-Meldung „Bridge-Ports werden neu gestartet“ auftritt.
* mehrere APs und PPSK-VLANs (im Pilot nur ein hAP ax² als AP), VRRP mit mehreren Routern,
  CAPsMAN-Übernahme durch den Backup-Manager
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
* ~~**WireGuard-Fernzugang: Rückweg zu cm1 selbst startet nicht zuverlässig ohne Anstoß.**~~ –
  *vermutlich behoben, noch nicht erneut getestet:* Ursache war wahrscheinlich, dass die
  WireGuard-Peers ursprünglich Adressen aus dem **bereits verbundenen** MGMT-Subnetz bekamen
  (RouterOS legt dafür keine automatische Route an, dazu Proxy-ARP nötig – beides zusammen offenbar
  fragil beim allerersten Verbindungsaufbau). Umgebaut auf ein eigenes, nicht überlappendes
  WireGuard-Subnetz (`wireguard.rsc` → `net`, Router bekommt Host `.1`); Proxy-ARP und die
  explizite Peer-Route sind damit entfallen, die verbundene Route fürs ganze Subnetz entsteht
  automatisch. Nach dem Umbau erneut testen, insbesondere den Rückweg zu cm1 selbst direkt nach
  einem frischen `nmcli connection up`, bevor `mgmtExtra` gehärtet wird (siehe CHECKLISTE) – falls
  es dann wieder hakt, war die Vorgeschichte mit `mgmtExtra` doch nicht die Erklärung und die
  eigentliche Ursache liegt woanders.

## Verbesserungsplan (Stand 2026-09-12)

Reihenfolge: 0 → 1 → 2, 3, 4 → 6, 7 → Rest nach Bedarf.

**0. Pilotbetrieb mit echter Hardware** – ein Gerät je Typ (Router, Switch, AP, Manager); deckt
die oben genannten ungetesteten Punkte ab. Größter Risikominderer vor jedem neuen Feature.
*Begonnen 2026-09-17* mit CRS418 (Router + Manager) und hAP ax² (AP), siehe oben; Switch- und
Backup-Manager-Rolle fehlen noch.

### Kurzfristig (großer Nutzen, wenig Aufwand)

1. ~~**`manager.rsc` aufteilen**~~ – *erledigt (D26):* `lib/mgr-core.rsc`, `mgr-enroll.rsc`,
   `mgr-onboard.rsc`, `mgr-auto.rsc` (je höchstens 21 KB statt 53 KB in einer Datei; RouterOS liest
   per `/file get` nur etwa 60 KB, `$cfmRelease` lehnt größere Dateien ab).
2. **Benachrichtigungen** (E-Mail oder Push-Dienst wie ntfy/Telegram) bei Fehler/Rollback, stummen
   Geräten, gescheitertem Onboarding, CAPsMAN-Übernahme durch den Backup-Manager.
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
   Firmware stehen) und stößt selbst einen weiteren Neustart an. Offen: Pakete auf den
   Backup-Manager spiegeln; Zusatzpakete (`wifi-qcom` …) und mehrere Architekturen auf echter
   Hardware testen.
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
