# Design-Entscheidungen (ADR-Log)

Alle wesentlichen Entscheidungen wurden interaktiv getroffen (2026-09-11). Pro Entscheidung:
die zur Wahl gestellten Optionen, die Wahl (**fett**) und die Konsequenzen für die Umsetzung.

## Architektur des Frameworks

| # | Thema | Optionen | Entscheidung / Konsequenz |
|---|-------|----------|---------------------------|
| D1 | Verteilung | **Pull + Push-Trigger** · reiner Push per SSH · HTTPS-Pull aus Container | Geräte holen per SFTP (Scheduler + Boot), der Manager stößt per `/system ssh-exec` sofort an. **Ergänzung:** Die aktive Config jedes Geräts (Export) liegt zentral in `state/<name>/`. *Umsetzung angepasst:* Der Manager holt Status und Export ab (Tick, 1/min), weil ein Upload durch die Geräte die Policy `write` erfordern würde und damit SSH-Konfigurationsrechte am Manager. |
| D2 | Apply-Engine | **Daten + Reconciler mit Tags** · idempotente Befehlsskripte · Full-Rebuild per Reset | Jedes verwaltete Objekt trägt `comment="cfm:<typ>:<key> …"`. Getaggte Objekte ohne Datensatz werden entfernt (VLAN löschen = Zeile löschen). Ungetaggte Objekte werden nie angefasst. |
| D3 | Datenformat | **RouterOS-Arrays (.rsc)** · JSON + `:deserialize` | Native Arrays, per `/import` geladen, keine Parser-Abhängigkeit. |
| D4 | Source of Truth | Git lokal + Deploy · **nur auf dem Manager** · Git-Server im Container | Editiert wird in `cfm/work/` auf dem Manager. Historie über Archiv-Snapshots + externen Git-Hook (D13). Dieses Projektverzeichnis ist Seed/Referenz. |
| D5 | Release | **explizites Release** · automatisch nach Ruhezeit | `$cfmRelease` prüft Syntax, friert `work/` als `archive/<ver>/` ein, erzeugt Manifeste, triggert Push. Halbfertige Edits kommen nie an. |
| D6 | Geräte-Spezifika | **Schichten + lokaler Hook** · nur Parameter im Hostfile | global → Rolle → `hosts/<name>.rsc` → optional `hosts/<name>.post.rsc`. **Ergänzung:** Audit-Lauf zeigt von Hand angelegte Objekte an und kann sie gezielt als `cfm-override` markieren oder entfernen. |
| D7 | Manager-Redundanz | **Fallback-Liste** · VRRP-VIP | Geräte probieren Manager der Reihe nach. Backup spiegelt Primary (Pull) und ist read-only bis zur Beförderung. |
| D8 | Schutz vor kaputter Config | Backup + Watchdog · nur Pre-Apply-Export · **Canary-Ringe + Backup/Watchdog** | Ring 0 → 1 → 2. Promotion automatisch nach Erfolg + Soak-Zeit oder manuell (`$cfmPromote`). Pro Gerät: Backup vor Apply, Watchdog-Rollback per `/system backup load`, Version wird als `bad` gemerkt. |

## Identität, Secrets, Backups

| # | Thema | Optionen | Entscheidung / Konsequenz |
|---|-------|----------|---------------------------|
| D9 | Zuordnung Gerät ↔ Hostfile | Seriennummer · System-Identity · **eigene Variante** | Gerät matcht über Seriennummer, Dateien liegen nach Identity (`hosts/sw1.rsc`). Zuordnung Seriennummer → Name in `meta/inventory.rsc` (Manager-Metadaten, nicht versioniert). Gerätetausch = Seriennummer in einer Zeile ändern + Onboarding wiederholen. |
| D10 | Rück-Export | Export + verschl. Backup · Export mit Secrets · **nur Export ohne Secrets** | `/export terse` (ohne `show-sensitive`). DR: zentrale Secrets liegen verschlüsselt im Vault (D12); individuelle Secrets (Geräte-Key, MAC-Schlüssel) entstehen beim Onboarding und werden im DR-Fall per erneutem Onboarding neu erzeugt. |
| D11 | Secrets-Transport | secrets.rsc nur auf Managern · Secrets nur lokal → **Secret-Push per SSH** | Nachträglich geändert: RouterOS-SFTP kennt keine Verzeichnisrechte, also könnte jedes Gerät jede Datei lesen. Deshalb schreibt der Manager Secrets per `ssh-exec` direkt in die Geräte-Config. Es gibt nie eine Secret-Datei. Benutzer werden bis zum ersten Push `disabled` angelegt. |
| D12 | Vault | **verschl. Manager-Backup** · Vault-Datei mit Skript-Crypto | Vault-Einträge sind deaktivierte `/ppp secret` namens `cfm:<key>`. Das Passwortfeld ist *sensitive*: Es fehlt im Export, ist aber im AES-verschlüsselten `/system backup` enthalten (zentrales Passwort). `$cfmVaultBackup` legt es in `vault/` ab, der Git-Hook spiegelt es. |
| D13 | Externe Sicherung | **SSH-Exec → Git-Host** · HTTP-Webhook · Log/Mail | Hook-Events: `release`, `rollback`, `promote`, `state` (neue Geräte-Exporte, entprellt), `audit`, `vault`. Der Git-Host holt per SFTP und committet (`tools/git-host/cfm-git-sync`). |

## Netzwerk & WLAN

| # | Thema | Optionen | Entscheidung / Konsequenz |
|---|-------|----------|---------------------------|
| D14 | VLAN ↔ Port | **Port-Profile** · explizite Listen je Port | Profile `trunk`, `trunk-ap`, `access:<vid>`, `hybrid:<vid>`, `wan`, `off`. Neue VLANs erscheinen automatisch auf passenden Trunks. |
| D15 | Gateway | **VRRP (wie ein vorhandenes Skript), optional** · Einzelrouter mit freien Subnetzen | `192.168.<VID>.0/24`, VIP `.gw` (Default 1), reale IP `.250+routerId`; ohne `routerId` bekommt der Router direkt `.gw`. DHCP läuft nur auf dem VRRP-Master. |
| D16 | Firewall | **Zonen via Interface-Listen** · Basis zentral, Rest lokal | Zone je VLAN, Policy-Matrix in `global.rsc`. Lokale Regeln gehören in die Chains `local-input`/`local-forward` (Hook-Punkte vor dem finalen Drop). |
| D17 | CAPsMAN | **Config-Manager + Netwatch** · folgt VRRP-Master · beide aktiv | Primary-CM ist CAPsMAN. Der Backup-CM rendert dieselbe Config mit `enabled=no`, Netwatch schaltet ihn bei Ausfall des Primary ein. Ein Controller → ein FT-Verbund. |
| D18 | Datapath | **lokal am CAP + VLAN-Tag** · CAPsMAN-Forwarding | `datapath vlan-id` je SSID. AP-Uplinks nutzen das Profil `trunk-ap`. |
| D19 | WLAN-Sicherheit | **WPA2/WPA3 + FT + k/v** · WPA3-only · WPA2-only | `wpa2-psk,wpa3-psk`, `ft=yes ft-over-ds=yes`, Steering `rrm=yes wnm=yes`. IoT-Override: WPA2, FT aus. |
| D20 | Test | **CHR in QEMU** · nur statisch · Testgerät | `tools/chr-lab/` startet Manager + Geräte als CHR-VMs. |

## Automatisches Onboarding (Runde 2026-09-12)

| # | Thema | Optionen | Entscheidung / Konsequenz |
|---|-------|----------|---------------------------|
| D21 | Erstzugriff auf Werksgeräte | Netinstall-Station · **Push in die Werks-Config** · Push + Branding-Paket | Der Manager meldet sich mit `admin` + Aufkleber-Passwort (aus der Vorab-Registrierung) an und lädt Skripte per SFTP als `*.auto.rsc` hoch (werden sofort ausgeführt). Netinstall und Branding stehen in [TODO.md](TODO.md). |
| D22 | Anschlussort | am Zielort (Onboarding-VLAN dauerhaft) · Werkbank-Port · **am Zielort, temporärer Onboarding-Port** | `$cfmOnboard sw=<switch> port=<port>` schaltet genau einen Port vorübergehend ins Onboarding-VLAN (untagged, die normalen tagged VLANs bleiben). Nach erfolgreichem Onboarding stellt ein erzwungener Apply des Switches das Port-Profil aus dem Hostfile wieder her. Ein Fail-safe-Timer auf dem Switch tut das spätestens nach Ablauf der Zeit. |
| D23 | Freigabe | **Vorab-Registrierung** · immer manuell · vollautomatisch | `$cfmRegister` (Seriennummer, Name, Rolle, Ring, MGMT-IP, Aufkleber-Passwort → Vault). Nur passende Seriennummern werden aufgenommen; unbekannte landen in `$cfmPending` und werden per `$cfmApprove` freigegeben. |
| D24 | RouterOS-Version | Zielversion vom Manager · **Update aus dem Internet** · nur Mindestversion | Das Probe-Skript prüft den Kanal (`rosChannel`) und installiert Updates. Das Onboarding-VLAN darf über den Router nur die MikroTik-Update-Server erreichen (FQDN-Adressliste). `rosMin` ist Abbruchkriterium, falls kein Update möglich ist. |
| D25 | Werks-User `admin` | **automatisch abschalten** · behalten | `adminUser="disable"` (Standard): Die Rolle `base` schaltet `admin` ab, sobald auf dem Gerät ein User aus `users` aktiv ist, nie vorher. Das Gerät meldet den effektiven Wert (inkl. Hostfile-Ausnahme) im Status; steht dort `disable`, schaltet der Manager `admin` beim Secret-Push gleich mit ab (kein zusätzlicher Apply, der mit anderen Läufen kollidieren könnte). Die Rolle `manager` hinterlegt den Manager-Schlüssel auch für diese User, damit die `$cfm…`-Befehle ohne `admin` funktionieren. Ausnahme pro Gerät per Hostfile (`"keep"`). |
| D26 | Manager-Funktionen | eine Datei · **Module + Lader** | `/file get` liest nur etwa 60 KB. Die Funktionen liegen daher in `lib/mgr-*.rsc`: `core`, `check` (Prüfung, Probelauf), `enroll`, `onboard`, `ros` (RouterOS-Updates), `auto`. Die Rolle `manager` installiert jedes Modul aus dem Manifest als Skript `cfm-mgr-<modul>`, das Skript `cfm-mgr` lädt alle (Befehl im Terminal unverändert). Fehlen die Module im Manifest, bricht der Apply ab. |

Umsetzungsdetails:
* **Onboarding-VLAN 88 = `192.168.88.0/24`**, bewusst passend zur Werks-IP `192.168.88.1` neuer Geräte. Gateway `.250` (Router), DHCP `.100–.199` vom Primary-Manager (für Geräte mit DHCP-Client in der Werks-Config, z.B. APs im CAPs-Modus). Die Manager erreichen die Geräte direkt auf Layer 2 und haben dort die Host-Adresse ihrer MGMT-IP.
* **Zweistufiger Push:** Stufe 1 (Probe) liest Seriennummer/Modell/Version und stößt ggf. das Update an. Stufe 2 lädt den gerätespezifischen Bootstrap hoch und setzt das Gerät per `reset-configuration no-defaults=yes run-after-reset=` auf eine leere Config mit genau diesem Bootstrap zurück (keine Werks-Firewall/-DHCP-Reste). Danach läuft das normale `$cfmEnroll`.
* **Immer nur eine Onboarding-Sitzung gleichzeitig** (alle Werksgeräte haben `192.168.88.1`).

## Verbesserungsplan, Punkte 3 und 5–9 (Runde 2026-09-12/13)

| # | Thema | Optionen | Entscheidung / Konsequenz |
|---|-------|----------|---------------------------|
| D27 | Archiv & Release-Prüfung | (Standard, nicht abgefragt) | Nach jedem Release (und auf dem Backup-Spiegel) bleiben die letzten `archiveKeep` Versionen (10) plus alle, die ein Ring nutzt oder ein Gerät meldet (angewendet, ausstehend, als fehlerhaft markiert). `$cfmCheck` prüft `work/` inhaltlich: VLANs/Zonen aus Profilen, WLAN, `policy`, `mgmtAccess` und Hostfiles; unbekannte Port-Profile; doppelte MGMT-IPs; Rollen ohne Datei. Fehler stoppen das Release, `force=yes` übergeht sie (`$cfmRollback` setzt es selbst); fehlende Hostfiles sind Warnungen. |
| D28 | Identität & Geräteschlüssel | Rotation: automatisch + Befehl · **nur per Befehl** · automatisch inkl. SFTP-Key | Vor jedem Secret-Push beweist das Gerät per Challenge-Response (`sha512(Schlüssel . Zufallswert)`), dass es seinen Geräteschlüssel kennt – ssh-exec prüft keine Host-Schlüssel. `$cfmRekey host=…|all=yes` erneuert den Schlüssel, nicht während eines Applys (dessen Rollback-Sicherung ist mit dem alten Schlüssel verschlüsselt), signiert die Manifeste neu und erhöht die Vault-Version (Backup-Manager und Vault-Backup ziehen nach). |
| D29 | Probelauf | **Probelauf gegen work/** · gegen freigegebene Version · nur Datei-Diff | `$cfmPlan host=…` legt einen Schnappschuss `plan/` samt signiertem Plan-Manifest an. Das Gerät führt die Rollen mit `cfmDry=true` aus: `cfmRun` überspringt add/set/remove, die Meldungen des Reconcilers (mit Werten) sind der Plan. `*.post.rsc` wird übersprungen, direkte Befehle in Rollen sind mit `$cfmDry` abgesichert. Start per `:execute`, Ergebnis per SFTP (ssh-exec bricht lange Befehle ab). |
| D30 | RouterOS-Versionen | Pakete: exakte Version aus dem Internet · **Manager hält Pakete** · nur Kanal; Neustart: Wartungsfenster · sofort · **nur per Befehl (sofort oder einmaliges Fenster)** | `$cfmUpgrade ver=… host=|ring=|all=yes [at=…]`. Der Manager lädt vor dem Rollout alle Pakete (routeros + Zusatzpakete) für alle betroffenen Architekturen nach `pkgPath/<ver>/`; fehlt eins, startet nichts. Der Auftrag steht im signierten Manifest (Feld `ros`, zählt nicht zum Manifest-Hash). Der Agent lädt per SFTP, prüft die Größe (Hashes gehen nicht: `/file get` liest nur ~60 KB; die Signatur prüft RouterOS beim Installieren) und startet sofort oder per Scheduler neu. Ältere Zielversion = `/system/package/downgrade`. Ein erfolgloser Neustart wird nicht wiederholt (`fehlgeschlagen`). Versionen, die kein Gerät installiert hat und kein Auftrag nennt, löscht der Manager. |
| D31 | Minimale Firewall | Regelwerk: **Default-Drop** · nur Dienste sperren; IPv6: **IPv6-Firewall** · abschalten · nicht anfassen; Log: **begrenzt** · nein | Nicht-Router (Switch, AP, Manager) bekommen den input-Block `fwb`: Antworten, ICMP, Adressliste `cfm-mgmt` (MGMT-Netz, `mgmtAccess`, `mgmtExtra`), auf Managern DHCP im Onboarding-VLAN, Sprung in `local-input`, Log `cfm-drop` (10/min), Drop. IPv6-input `fw6` auf allen Geräten: Antworten, ICMPv6, Link-Local aus dem MGMT-VLAN. Bekommt ein Gerät die Rolle `router`, ersetzt dessen Zonen-Firewall den Block. |

## Verbesserungsplan, Punkte 16 und 17 (Runde 2026-09-13)

| # | Thema | Optionen | Entscheidung / Konsequenz |
|---|-------|----------|---------------------------|
| D32 | WLAN-Ausbau | Enterprise: externer RADIUS · User Manager auf dem Manager · **vorerst kein Enterprise**; PPSK: **Multi-Passphrase-Gruppen** · Access-List je MAC; Kanäle: **RouterOS-Auswahl + Bericht** · zentrale Planung in cfm · nur RouterOS-Auswahl | `wifi.rsc` → `ppsk`: je SSID Einträge mit `vlan` (optional `isolation`, `expires`). Die Rolle `manager` legt `/interface/wifi/security/multi-passphrase`-Einträge (Gruppe = Security-Profil) mit Zufallswert an, die echte Passphrase kommt per Secret-Push aus dem Vault (`ppsk.<ssid>.<name>`) und steht nie in Daten, Log oder Probelauf. `$cfmCheck` verlangt WPA2-PSK (RouterOS: kein Multi-Passphrase mit WPA3) und warnt, wenn das VLAN nicht auf den AP-Uplinks (`trunk-ap`) liegt. Kanäle: `reselect` (nächtliche Neuwahl) und je Band `skipDfs`; APs melden ihre Kanäle, `$cfmChannels` warnt bei gleichem Kanal an einem Switch (Näherung für „benachbart“). Enterprise steht in [TODO.md](TODO.md). |
| D33 | Verkabelung per LLDP | Ports: nur Infrastruktur · **alle Bridge-Ports**; Soll: **Baseline + optionale Angaben** · nur Hostfile · nur Baseline; Netzplan: **Mermaid + Tabelle, auf Anforderung zusätzlich Graphviz und CSV** · Graphviz · nur Tabelle | Nachbarsuche (LLDP/MNDP/CDP) auf der Interface-Liste `DISC` (alle Bridge-Ports + MGMT-VLAN). Der Agent meldet die Nachbarn je physischem Port. `$cfmLinks` baut daraus die Links, vergleicht mit der Baseline (`accept=yes`, `meta/links.dat`) und den Angaben `"links"={"ether1"="rtr1:ether2"}` in `work/hosts/<name>.rsc` und schreibt `state/netzplan.md` (Mermaid + Tabelle), mit `export=yes` zusätzlich `netzplan.dot` und `netzplan.csv`. Der Manager-Tick prüft alle 15 min und loggt neue Abweichungen; der Netzplan wird nur bei Änderungen neu geschrieben (Git-Sicherung). |

## Umsetzungsentscheidungen (technisch begründet, nicht separat abgefragt)

* **Integritätsschutz:** Jedes Gerät bekommt ein eigenes Manifest `live/m/<serial>.rsc` mit Version, Rolle, Dateiliste + SHA-512 und einem MAC (`sha512(key . sha512(body))`) mit dem beim Onboarding ausgetauschten Geräteschlüssel. Geräte haben am Manager nur Lesezugriff. Der MAC schützt zusätzlich gegen manipulierte Spiegel oder Transportwege: Ein Gerät verwirft jedes Manifest, das nicht mit seinem Schlüssel gesichert ist.
* **Kanalplanung:** Kanal-Pools zentral in `wifi.rsc`, optionales Pinning pro AP ebenfalls in `wifi.rsc → radios`, weil der CAPsMAN (nicht der AP) die Radio-Config rendert.
* **Inventar ist Metadatum:** `meta/inventory.rsc` (Name, Seriennummer, Rolle, Ring, MGMT-IP) wirkt ohne Release; Inhalte (`work/`) nur per Release.
* **Reihenfolge-sensitive Listen (Firewall/NAT):** werden als Block verwaltet. Bei geänderter Signatur wird der neue Block zuerst eingefügt und dann der alte entfernt (kein Moment ohne Regeln).
* **Werte nie in Code-Strings einsetzen:** Der Reconciler erzeugt Kommandos per `:parse`, übergibt aber alle Werte als Variablen (`name=($P->"name")`). Dadurch gibt es kein Quoting/Escaping und keine Injection über Daten (SSIDs mit Leerzeichen/Anführungszeichen).
* **Geräte-Rückmeldungen nur als Daten:** Status als JSON (`:deserialize`), Audit als Text. Der Manager führt nie etwas aus, das von einem Gerät stammt.

## Im CHR-Labor verifizierte RouterOS-Eigenheiten (7.24.2)

Diese Punkte haben die Umsetzung geprägt und gelten für eigene Templates:

| Eigenheit | Konsequenz |
|---|---|
| Eine Zeile, die mit `[` beginnt, kann als Fortsetzung der vorigen Anweisung gelesen werden | Funktionsaufrufe als Anweisung immer ohne Klammern: `$cfmEnsure …` |
| `\"` in einem String-Literal, das direkt als Funktionsargument dient, bricht `/import` (`:parse` akzeptiert es) | solche Strings vorher in eine Local legen |
| Nicht vorhandene Menüs in Slash-Schreibweise (`/system/routerboard/…` auf CHR) sind Syntaxfehler, die `:onerror` nicht fängt | geräteabhängige Menüs in Leerzeichen-Schreibweise (`/system routerboard get …`) oder per `:parse` |
| `/import … verbose=yes` führt Zeilen einzeln aus | Locals gehen verloren, nur `verbose=no` verwenden |
| `/user add` verlangt ein Passwort | Benutzer werden mit Zufallspasswort + `disabled=yes` angelegt, bis der Secret-Push kommt |
| SFTP-Zugriff braucht die Policies `ssh,ftp,read`; ein Upload zusätzlich `write` | Gruppe `cfm-dev` bleibt lesend, der Manager holt Rückmeldungen ab |
| Lesende SFTP-Nutzer bekommen auf `*.json` und `*.backup` „Permission denied“ (alle anderen Endungen gehen) | Manager-Dateien für Geräte/Spiegel/Git heißen `*.dat` (Inhalt JSON); das Vault-Backup wird nach dem Speichern in `*.bak` umbenannt |
| `:return` innerhalb von `:onerror … in={}` verlässt die Funktion nicht | Ergebnis über ein Flag setzen und am Ende zurückgeben |
| Dateien mit führendem Punkt tauchen in `/file` nicht auf | keine Dotfiles als Zwischendateien |
| `[:tonum nothing]` ist `nil`, Vergleiche damit sind weder wahr noch falsch; Strings lassen sich nicht mit `<`/`>` vergleichen | Versionen als String vergleichen, Änderungen per md5-Signatur erkennen |
| `capsman enabled` liefert `"yes"`/`"no"` (String, kein Bool) | Vergleich per `[:tostr …] ~ "yes\|true"` |
| QEMU-Multicast-Netz spiegelt Frames an den Sender zurück (RSTP blockiert) | CHR-Labor nutzt eine Stern-Topologie mit Punkt-zu-Punkt-Sockets |
| `/tool fetch mode=sftp` nutzt die unter `/user ssh-keys private` importierten Schlüssel | Pull ohne Passwort, Geräte-Identität = exportierter ed25519-Host-Key |
| per `place-before` eingefügte Regeln zeigen ohne explizites `disabled=no` das Flag `I` | `cfmBlock` setzt `disabled=no` |
| `/file get … contents` liest bis ca. 60 KB | `$cfmRelease` weist größere Dateien ab |
| `:deserialize from=json` wandelt Strings um, die wie andere Typen aussehen: `"7.24.1"` wird die IP-Adresse `7.24.0.1`, `"2026-09-13 01:21"` ein Zeitwert; `:serialize` schreibt Ziffern-Strings als Zahl | Werte, die einen JSON-Umlauf überstehen müssen, bekommen ein Präfix (`"rv"="v7.24.1"`, `"at"="@2026-…"`) und werden beim Lesen wieder abgeschnitten |
| Ein Scheduler mit `start-time=startup` **und** Intervall läuft nach einem Neustart erst nach dem ersten Intervall, nicht beim Start | zusätzlicher Scheduler `cfm-agent-boot` (`startup`, ohne Intervall): Der Agent meldet sich 20 s nach jedem Boot |
| `/ip/neighbor`: Nachbarn erscheinen nur, wenn die Nachbarsuche auf den physischen Bridge-Ports läuft; `interface` ist dann eine Liste (`ether2;bridge`), `interface-name` der Gegenseite z.B. `bridge/ether3` | Liste `DISC` mit allen Bridge-Ports; der Agent nimmt das erste Listenelement und den Teil nach `/` |
| `/interface/wifi/security … multi-passphrase-group=""` hinterlässt eine leere Zuweisung | Gruppe per `unset` lösen |
| Nach einem Neustart nimmt eine Bridge mit VLAN-Filtering auf CHR sporadisch keine getaggten Frames ihrer Ports mehr an: RSTP „forwarding“, Konfiguration korrekt, die Frames sind im Sniffer sichtbar, erreichen aber das VLAN-Interface nicht. Im Labor nach `/system backup load` 2 von 2, nach einfachem Neustart 1 von 4 Mal; Aus- und Einschalten des Ports behebt es | Der Boot-Lauf des Agents (`cfm-agent-boot`, Argument `boot`) startet die Ethernet-Ports der Bridge einmal neu, wenn er keinen Manager erreicht. Ob echte Hardware betroffen ist, ist offen ([TODO.md](TODO.md)) |
| `/system/ssh-exec` bricht lange Befehle mit „action timed out“ ab | Lange Aktionen auf dem Gerät per `:execute` starten, Ergebnis per SFTP abholen (`$cfmPlan`); Pakete lädt der Agent im eigenen Lauf |
| `/system/package/downgrade` startet im Skript sofort und ohne Rückfrage neu – auch ohne passende Pakete | Der Agent ruft es nur auf, wenn alle Pakete geladen und in der Größe geprüft sind |
| `/system/package` zeigt installierte Pakete mit `available=false`, `disabled=false`; `architecture-name` ist z.B. `x86_64` (Paketname ohne Suffix) oder `arm64` | Status meldet `arch` und `pkgs`, Paketname `<pkg>-<ver>[-<arch>].npk` |
