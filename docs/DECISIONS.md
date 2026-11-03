# Design-Entscheidungen

Alle Entscheidungen des Frameworks, nach Themen geordnet. Die RouterOS-Eigenheiten, die die Umsetzung geprägt haben,
stehen in [ROUTEROS-EIGENHEITEN.md](ROUTEROS-EIGENHEITEN.md).

## Aufbau

* **Nummern:** `D` + Buchstabe des Themas + Nummer des Abschnitts + laufende Nummer, z.B. `DW1.5` (WLAN, Abschnitt 1,
  fünfte Entscheidung). Eine Unterentscheidung, die nachträglich zu einer bestehenden kommt, hängt eine Stufe an
  (`DG4.6.1`). Nummern werden nie umgehängt oder neu vergeben: Eine neue Entscheidung bekommt im passenden Abschnitt
  die nächste freie Nummer, ein neuer Abschnitt die nächste freie Abschnittsnummer.
* **Eintrag:** Überschrift mit Nummer und Titel, darunter Datum und Herkunft. Ohne Vermerk hat der Nutzer entschieden
  (Optionen zur Wahl gestellt); *technisch, nicht abgefragt* heißt technisch begründet umgesetzt. Felder: Frage,
  Entscheidung, Verworfen (bzw. Optionen mit der gewählten fett), Begründung oder Umsetzung.
* **Revision:** Eine Entscheidung, die eine andere ganz ersetzt, nennt sie unter **Löst ab** mit Grund; die alte wandert
  mit ihrer Nummer ins [Archiv](#archiv), im Thema bleibt ein Verweis. Ändert sie nur einen Teil, bleibt die alte im
  Thema und bekommt einen **Status** mit Datum, Nummer und dem, was sich geändert hat.
* **Alte Nummern:** Bis 2026-11-03 waren die Entscheidungen durchgezählt (D1–D104) und nach Runden geordnet. Commits
  und ältere Notizen nutzen diese Zählung; die [Zuordnung](#alte-nummern) und die [Chronik](#chronik) stehen am Ende.

## Inhalt

* [DG · Grundarchitektur](#dg) – Verteilung, Release, Apply-Engine, Code-Umfang
  [DG1 Daten und Quelle](#dg1) · [DG2 Release und Verteilung](#dg2) · [DG3 Apply-Engine](#dg3) · [DG4 Code-Umfang und Laufzeit](#dg4)
* [DM · Manager](#dm) – Module, Ticks, Nebenläufigkeit, Redundanz
  [DM1 Aufbau](#dm1) · [DM2 Nebenläufigkeit](#dm2) · [DM3 Redundanz](#dm3)
* [DS · Sicherheit](#ds) – Identität, Secrets, Benutzer und Dienste
  [DS1 Identität und Integrität](#ds1) · [DS2 Secrets und Sicherung](#ds2) · [DS3 Benutzer und Dienste](#ds3)
* [DO · Onboarding](#do) – Werksgeräte, Bestandsgeräte, Manager aufsetzen
  [DO1 Werksgeräte aufnehmen](#do1) · [DO2 Bestandsgeräte und Inventar](#do2) · [DO3 Manager aufsetzen](#do3)
* [DV · RouterOS-Versionen](#dv) – Updates, Pakete, Versionsangaben
  [DV1 Updates und Versionen](#dv1)
* [DP · Ports und VLANs](#dp) – Port-Profile, Bonds, MLAG, Isolation
  [DP1 Ports und VLANs](#dp1) · [DP2 Bonds und MLAG](#dp2) · [DP3 Isolation](#dp3)
* [DR · Routing und Firewall](#dr) – Gateway, VRRP, Firewall, NAT, Fernzugang
  [DR1 Gateway und VRRP](#dr1) · [DR2 Firewall, NAT, Queues](#dr2) · [DR3 Internet-Router im LAN](#dr3) · [DR4 Fernzugang](#dr4)
* [DN · Netzdienste](#dn) – DHCP, DNS, NTP
  [DN1 DHCP und Namen](#dn1) · [DN2 Zeit](#dn2) · [DN3 DNS-Resolver](#dn3)
* [DW · WLAN](#dw) – CAPsMAN, Sicherheit, Kanäle, SSID-Schalter
  [DW1 CAPsMAN, Datapath, Fallback](#dw1) · [DW2 Sicherheit und Clients](#dw2) · [DW3 Kanäle](#dw3) · [DW4 SSID-Schalter und Provisioning](#dw4)
* [DU · Überwachung](#du) – Anzeige, Clients, Logs, Meldungen
  [DU1 Anzeige am Manager](#du1) · [DU2 Clients und WLAN](#du2) · [DU3 Logs](#du3) · [DU4 Meldungen und Monitoring](#du4)
* [DT · Tools und Test](#dt) – Labor, Prüfskript, Site-Daten, Browser-Werkzeuge
  [DT1 Test und Prüfung](#dt1) · [DT2 Site-Daten](#dt2) · [DT3 Browser-Werkzeuge](#dt3)
* [Archiv](#archiv) · [Alte Nummern](#alte-nummern) · [Chronik](#chronik)

## <a id="dg"></a>DG · Grundarchitektur

### <a id="dg1"></a>DG1 · Daten und Quelle

#### <a id="dg1.1"></a>DG1.1 · Datenformat: RouterOS-Arrays

*2026-09-11 · alt D3*

**Entscheidung:** RouterOS-Arrays (.rsc)

**Verworfen:** JSON + `:deserialize`

**Umsetzung:** Native Arrays, per `/import` geladen, keine Parser-Abhängigkeit.

#### <a id="dg1.2"></a>DG1.2 · Source of Truth auf dem Manager

*2026-09-11 · alt D4*

**Entscheidung:** nur auf dem Manager

**Verworfen:** Git lokal + Deploy · Git-Server im Container

**Umsetzung:** Editiert wird in `cfm/work/` auf dem Manager. Historie über Archiv-Snapshots + externen Git-Hook (DS2.4). Dieses Projektverzeichnis ist Seed/Referenz.

#### <a id="dg1.3"></a>DG1.3 · Schichten und lokaler Hook

*2026-09-11 · alt D6*

**Thema:** Geräte-Spezifika

**Entscheidung:** Schichten + lokaler Hook

**Verworfen:** nur Parameter im Hostfile

**Umsetzung:** global → Rolle → `hosts/<name>.rsc` → optional `hosts/<name>.post.rsc`. **Ergänzung:** Audit-Lauf zeigt von Hand angelegte Objekte an und kann sie gezielt als `cfm-override` markieren oder entfernen.

#### <a id="dg1.4"></a>DG1.4 · Inventar ist Metadatum

*2026-09-12 · technisch, nicht abgefragt*

`meta/inventory.rsc` (Name, Seriennummer, Rolle, Ring, MGMT-IP) wirkt ohne Release; Inhalte (`work/`) nur per Release.

### <a id="dg2"></a>DG2 · Release und Verteilung

#### <a id="dg2.1"></a>DG2.1 · Verteilung: Pull mit Push-Trigger

*2026-09-11 · alt D1*

**Entscheidung:** Pull + Push-Trigger

**Verworfen:** reiner Push per SSH · HTTPS-Pull aus Container

**Umsetzung:** Geräte holen per SFTP (Scheduler + Boot), der Manager stößt per `/system ssh-exec` sofort an. **Ergänzung:** Die aktive Config jedes Geräts (Export) liegt zentral in `state/<name>/`. *Umsetzung angepasst:* Der Manager holt Status und Export ab (Manager-Tick, `mgrTick`, Standard 10 min), weil ein Upload durch die Geräte die Policy `write` erfordern würde und damit SSH-Konfigurationsrechte am Manager.

#### <a id="dg2.2"></a>DG2.2 · Explizites Release

*2026-09-11 · alt D5*

**Entscheidung:** explizites Release

**Verworfen:** automatisch nach Ruhezeit

**Umsetzung:** `$cfmRelease` prüft Syntax, friert `work/` als `archive/<ver>/` ein, erzeugt Manifeste, triggert Push. Halbfertige Edits kommen nie an.

#### <a id="dg2.3"></a>DG2.3 · Schutz vor kaputter Config: Canary-Ringe, Backup, Watchdog

*2026-09-11 · alt D8*

**Entscheidung:** Canary-Ringe + Backup/Watchdog

**Verworfen:** Backup + Watchdog · nur Pre-Apply-Export

**Umsetzung:** Ring 0 → 1 → 2. Promotion automatisch nach Erfolg + Soak-Zeit oder manuell (`$cfmPromote`). Pro Gerät: Backup vor Apply, Watchdog-Rollback per `/system backup load`, Version wird als `bad` gemerkt.

#### <a id="dg2.4"></a>DG2.4 · Archiv und Release-Prüfung

*2026-09-12 · technisch, nicht abgefragt · alt D27*

**Status:** teilweise geändert durch DG4.1 (2026-10-01): `archiveKeep` standardmäßig 5.

**Umsetzung:** Nach jedem Release (und auf dem Backup-Spiegel) bleiben die letzten `archiveKeep` Versionen (10, seit DG4.1 Standard 5) plus alle, die ein Ring nutzt oder ein Gerät meldet (angewendet, ausstehend, als fehlerhaft markiert). `$cfmCheck` prüft `work/` inhaltlich: VLANs/Zonen aus Profilen, WLAN, `policy`, `mgmtAccess` und Hostfiles; unbekannte Port-Profile; doppelte MGMT-IPs; Rollen ohne Datei. Fehler stoppen das Release, `force=yes` übergeht sie (`$cfmRollback` setzt es selbst); fehlende Hostfiles sind Warnungen.

#### <a id="dg2.5"></a>DG2.5 · Manifest-Bau mit den Regeln der jeweiligen Version

*2026-10-11 · alt D70*

**Frage:** Woher der Manifest-Bau seine Regeln nimmt

**Entscheidung:** Je Version aus dem Archiv: `lib/mgr-mf.rsc` (`$cfmMfWant`), `$cfmManifests` lädt das Modul der Version, die ein Gerät bekommt (`archive/vN`, beim Probelauf `plan/`)

**Verworfen:** nur das Modul der neuesten Version für alle Ringe · nur `$cfmRelease` lädt aus `work/` (wie der Prüfer, DG4.1)

**Begründung:** Neue Dateien, die eine Rolle braucht, wirken genau ab der Version, die sie mitbringt, auch wenn der installierte Manager-Code älter ist. Das Canary-Prinzip gilt damit auch für den Manifest-Bau: Ein Fehler im Modul trifft nur die Ringe auf dieser Version. Je Aufruf höchstens drei kleine Imports. Versionen ohne das Modul baut die installierte Fassung (Skript `cfm-mgr-mf`), fehlt auch die (Übergang), die der neuesten Version. Die Regeln bleiben abwärtskompatibel (Dateien, die ältere Versionen nicht haben, sind optional). Scheitert das Modul, bleiben die Manifeste dieser Version unverändert (Warnung im Log). Übergang von älterem Manager-Code: TODO 47, Handgriff jetzt vor **jedem** Release und Promote, bis der Manager die Version selbst hat

#### <a id="dg2.6"></a>DG2.6 · Erzwungener Apply löscht `bad`

*2026-10-28 · technisch, nicht abgefragt*

`$cfmPush host=<g> force=yes` wandte eine als fehlerhaft markierte Version an, `bad` blieb stehen – `$cfmStatus` zeigte „bad vN ok“, die Meldung `apply:<g>` blieb offen und der tägliche Reapply übersprang die Version. Der Agent löscht `bad` jetzt nach einem erfolgreichen Apply derselben Version. Labor: `e2e.sh` Schritt 7.

### <a id="dg3"></a>DG3 · Apply-Engine

#### <a id="dg3.1"></a>DG3.1 · Daten und Reconciler mit Tags

*2026-09-11 · alt D2*

**Thema:** Apply-Engine

**Entscheidung:** Daten + Reconciler mit Tags

**Verworfen:** idempotente Befehlsskripte · Full-Rebuild per Reset

**Umsetzung:** Jedes verwaltete Objekt trägt `comment="cfm:<typ>:<key> …"`. Getaggte Objekte ohne Datensatz werden entfernt (VLAN löschen = Zeile löschen). Ungetaggte Objekte werden nie angefasst.

#### <a id="dg3.2"></a>DG3.2 · Reihenfolge-sensitive Listen als Block

*2026-09-12 · technisch, nicht abgefragt*

Reihenfolge-sensitive Listen (Firewall/NAT) werden als Block verwaltet. Bei geänderter Signatur wird der neue Block zuerst eingefügt und dann der alte entfernt (kein Moment ohne Regeln).

#### <a id="dg3.3"></a>DG3.3 · Werte nie in Code-Strings

*2026-09-12 · technisch, nicht abgefragt*

Der Reconciler erzeugt Kommandos per `:parse`, übergibt aber alle Werte als Variablen (`name=($P->"name")`). Dadurch gibt es kein Quoting/Escaping und keine Injection über Daten (SSIDs mit Leerzeichen/Anführungszeichen).

#### <a id="dg3.4"></a>DG3.4 · Probelauf gegen `work/`

*2026-09-13 · alt D29*

**Entscheidung:** Probelauf gegen work/

**Verworfen:** gegen freigegebene Version · nur Datei-Diff

**Umsetzung:** `$cfmPlan host=…` legt einen Schnappschuss `plan/` samt signiertem Plan-Manifest an. Das Gerät führt die Rollen mit `cfmDry=true` aus: `cfmRun` überspringt add/set/remove, die Meldungen des Reconcilers (mit Werten) sind der Plan. `*.post.rsc` wird übersprungen, direkte Befehle in Rollen sind mit `$cfmDry` abgesichert. Damit die cfm-Objekte der `*.post.rsc` nicht als verwaist erscheinen, merkt sich der echte Apply ihre Schlüssel (`cfm/post.json`, nur die Schlüssel, die erst diese Datei gesehen hat); der Probelauf derselben Datei behält genau diese. Start per `:execute`, Ergebnis per SFTP (ssh-exec bricht lange Befehle ab).

### <a id="dg4"></a>DG4 · Code-Umfang und Laufzeit

#### <a id="dg4.1"></a>DG4.1 · Dateizugriff über den Namen

*2026-10-01 · technisch, nicht abgefragt · alt D59*

**Frage:** Dateizugriffe im Manager-Tick und beim Apply (TODO 21)

**Entscheidung:** Bekannte Dateinamen per `/file/get <Name>` statt `/file/find`; `cfmMB` merkt sich die Ablage je Sitzung; `archiveKeep` standardmäßig 5; `$cfmRelease` lädt den Prüfer aus `work/`

**Verworfen:** weiter suchen und nur das Archiv verkleinern

**Begründung:** `/file/find` wertet jede Datei in `/file` aus (Hardware ~0,2 ms je Datei; CHR mit 600 Dateien 8 ms je Suche), `/file/get <Name>` braucht 0,05 ms. `cfmRead`/`cfmWrite`/`cfmFileEx` und alle Prüfungen auf einen bekannten Namen greifen deshalb direkt zu; `cfmMB` merkt sich die Ablage je Sitzung (`cfmMBv`). Suchen per Regex bleiben, wo mehrere Dateien gemeint sind (Release, Archiv, Spiegel). `archiveKeep` ist jetzt standardmäßig 5. `$cfmRelease` lädt den Prüfer (`lib/mgr-check.rsc`) aus `work/`, bevor er prüft: Nach einem Framework-Update kannte der installierte die neuen Kennzeichen nicht und hielt das erste Release auf (`force=yes` nötig). Der Prüfer nutzt deshalb nur Helfer, die es auch in älteren Manager-Modulen gibt. Nachtrag 2026-10-11: Auf den Geräten greifen jetzt auch `base` (Prüfung auf `authorized_keys.<user>`) und der Agent (Flash-Ablage) über den Namen zu. Beim Apply war die Dateisuche aber nicht der Zeitfresser, sondern die SFTP-Abrufe mit je mindestens 1 s: Der Agent lädt nur noch geänderte Dateien (DG4.4).

#### <a id="dg4.2"></a>DG4.2 · Datei-Existenz nur mit nicht leerem Namen

*2026-10-04 · technisch, nicht abgefragt*

Im Labor gefunden und behoben (2026-10-04): Eine gelöschte Datei liefert `/file/get` u.U. dauerhaft als Eintrag ohne Namen weiter. Existenzprüfungen verlangen deshalb einen nicht leeren `name` (`$cfmFileEx`, `fex` im Prüfer, `cfmWrite` des Agents; Eigenheit in [ROUTEROS-EIGENHEITEN.md](ROUTEROS-EIGENHEITEN.md#auf-hardware-verifizierte-routeros-eigenheiten)).

#### <a id="dg4.3"></a>DG4.3 · Größe der Gerätebibliothek: WLAN-Teil auslagern

*2026-10-11 · alt D68*

**Entscheidung:** WLAN-Teil (`$cfmSsidState`, `$cfmWifiRender`, `$cfmPskMissing`, `$cfmCapsmanOn`) in `lib/lib-wifi.rsc`, nur im Manifest der Rollen `ap`, `capsman`, `manager`; dazu kleine Bereinigung im Agent

**Verworfen:** nur WLAN auslagern · nur als TODO festhalten. Nicht gewählt: RouterOS-Auftrag und Firmware aus dem Agent auslagern (heikelster Pfad, Gewinn nur Parse-Zeit); Kommentare beim Release entfernen (die Grenze gilt schon für die Quelle auf dem Manager, Zeilennummern in Fehlermeldungen passten nicht mehr)

**Begründung:** `lib.rsc` 46 → 23 KB, Switches und Router laden den WLAN-Code nicht mehr. `$cfmIsCapsman` bleibt in `lib.rsc`, `base` braucht es. Die Datei ist im Manifest optional, damit Ringe auf Versionen vor DG4.3 gültig bleiben (dort steht alles noch in `lib.rsc`). Fehlt sie trotzdem, bricht die Rolle mit Fehler ab (Rollback), statt dass der Abgleich die WLAN-Objekte als verwaist entfernt

#### <a id="dg4.4"></a>DG4.4 · Apply lädt nur geänderte Dateien

*2026-10-11 · alt D69*

**Frage:** Apply-Dauer

**Entscheidung:** `$cfmGetFiles` lädt nur Dateien, die in `dl/` (bzw. `pl/`) noch nicht mit dem Hash aus dem Manifest liegen; Dateien, die das Manifest nicht nennt, löscht es

**Verworfen:** Dateien parallel per `:execute` laden · ein Bündel je Version (scheitert an der 60-KB-Grenze)

**Begründung:** Ein Apply holt nur noch, was das Release geändert hat. Der tägliche Reapply holt gar nichts mehr. Der lokale Hash kostet je Datei rund 1 ms (CHR). Das Löschen der übrigen Dateien bleibt nötig: `base` erkennt eine entzogene `authorized_keys.<user>` nur daran, dass die Datei fehlt. Vom Nutzer als weitere Performance-Optimierung freigegeben

#### <a id="dg4.5"></a>DG4.5 · Geänderte Dateien überschreiben statt löschen

*2026-10-28 · technisch, nicht abgefragt*

`$cfmGetFiles` löschte eine Datei mit falschem Hash und lud sie gleich unter demselben Namen neu. Auf einem CRS418 (7.25, Framework-Update mit geänderten `mgr-check`/`mgr-show`) bestand die neue Datei noch die Hash-Prüfung, im Apply fand `/file get` sie in `roles/manager.rsc` aber nicht mehr („no such item“) – Rollback mit Neustart, danach war sie lesbar. Vermutlich wirkt das Löschen im Datei-Index von RouterOS verzögert (vgl. die gelöschte Datei als Eintrag ohne Namen, [Eigenheiten](ROUTEROS-EIGENHEITEN.md)). Jetzt überschreibt `/tool/fetch` geänderte Dateien an Ort und Stelle; gelöscht werden nur noch Dateien, die das Manifest nicht nennt (`base` erkennt eine entzogene `authorized_keys.<user>` am Fehlen, DG4.4). Im CHR nicht nachstellbar; jedes Release in `e2e.sh` lädt geänderte Dateien.

#### <a id="dg4.6"></a>DG4.6 · Feature-Module

*2026-11-02 · alt D104*

**Anlass:** Wunsch des Nutzers, den RouterOS-Code zu straffen und Features, die nur manche Sites nutzen, in eigene Skripte auszulagern, die nur bei Nutzung geladen werden. Stand vorher: `roles/router.rsc` 41,6 KB, davon ~10 KB DNS (DN3.1/DN3.2, das Skript `cfm-dnsreq` Zeile für Zeile als String mit dreifachem Escape); `roles/base.rsc` 38,8 KB, davon ~5,5 KB Admin-SSH-Keys (DS3.3), ~3 KB Filter isolierter VLANs (DP3.1) und ~2 KB SNMP (DU4.3) – Rollen parst jedes Gerät bei jedem Apply.

**Frage:** Code einzelner Features nur auf Geräten laden, die sie nutzen

**Entscheidung:** Feature-Module `lib/<Rolle>.<Feature>.rsc`: Das Manifest liefert die Module einer Rolle jedem Gerät mit dieser Rolle (base: allen) ohne Import (`$cfmMfWant`, eine allgemeine Regel statt einer je Datei); die Rolle importiert eins per `$cfmFeat "<Rolle>.<Feature>"` nur, wenn das Gerät das Feature nutzt oder Reste davon aufzuräumen sind, die die GC nicht kennt. Werte der Rolle gehen über `:global cfmCtx` hinein. Ausnahme beim Download: `base.sshkeys` nur, wenn die Version eine `authorized_keys.<user>` enthält (aus dem Dateiindex der Version ablesbar)

**Verworfen:** Entscheidung auf dem Manager: Datei nur ins Manifest, wenn die Site-Daten das Feature nutzen · alles in den Rollen lassen

**Begründung:** Über die Nutzung entscheidet das Gerät, weil nur dort Daten **und** Hostfile der Version vorliegen, die es anwendet: Der Manifest-Bau kennt nur die Daten des neuesten Release (`$cfmLoadData`) und keine Hostfiles (`bonds`, `wan`, `routerId`). Ein Ring auf einer älteren Version bekäme sonst ein Modul nicht, das seine Rolle braucht (Apply-Fehler, Rollback) – das Canary-Prinzip (DG2.5) bliebe nicht gewahrt. Der Download kostet einmal je Änderung (DG4.4, unveränderte Dateien lädt der Agent nicht neu), geparst wird nur bei Nutzung. Fehlt ein Modul, bricht `$cfmFeat` ab (Rollback), statt dass der Abgleich die Objekte des Features als verwaist entfernt (wie DG4.3). Erste Module: `router.dns` (Adlisten, Ausnahmen, Weiterleitungen, Abfrage-Log, Selbstbedienung; geladen mit `dns.rsc` oder solange es die Aktion `cfmdns`, eine Log-Regel `dns,!packet` oder Einträge `dnsui:` gibt), `router.dnsreq` (Rumpf des Skripts `cfm-dnsreq` als echter Code statt Escape-Strings, als Funktion, damit die Datei allein `:parse` besteht; davor setzt `router.dns` die Locals `dur`/`deny`/`nu`/`site`, die `cfm-dns.js` liest), `router.wg` (WireGuard-Fernzugang, nur mit Peers), `base.sshkeys` (nur mit einer `authorized_keys.<user>` eines Users aus `users`), `base.snmp` (nur mit `snmp.from`), `base.iso` (Filter isolierter VLANs, nur mit `isolate` und Client-Ports), `base.bond` (Bonds und MLAG, nur mit `bonds` im Hostfile oder als Knoten in `mlag.rsc`), `router.limit` (Bandbreitenlimit, nur mit `limit`/`limitClient`). `roles/router.rsc` 41,6 → 27,3 KB, `roles/base.rsc` 38,8 → 27,6 KB. Nebenbei: zwei Log-Texte von `cfm-dnsreq` mit Umlaut („für“, „gültiger“) jetzt in ASCII (DU3.4) – als String im String fand `rsc-check` sie nicht. `tools/rsc-check.py` prüft `$cfmFeat`-Aufrufe (Regel `feature-modul`: Name, Rolle base oder die eigene, Datei vorhanden), `$cfmDiff` ordnet die Module den Rollen zu. Weitere Kandidaten: TODO 73.

##### <a id="dg4.6.1"></a>DG4.6.1 · Nur genutzte Feature-Module hochladen

*2026-11-02 · alt D104, Nachtrag 1*

**Entscheidung:** `tools/upload-seed.sh` lädt nur die Module auf den Manager, deren Feature die Site-Daten nutzen, und entfernt die übrigen dort (`tools/feature-module.py`: liest die Site-Daten des Managers, mit `--site` darüber die hochgeladenen; im Zweifel – Wert per `:set`, Modul ohne Regel, keine Site-Daten – hochladen; `--all-features` für das Labor). Damit landen sie auch nicht im Release und auf den Geräten.

**Verworfen:** Module immer hochladen und nur bei der Verteilung filtern (Manifest-Bau kennt die Hostfiles nicht, siehe DG4.6).

**Folgen:** (1) Was die GC nicht kennt, baut die Rolle selbst ab, nicht das Modul – sonst bräuchte ein Gerät das Modul noch, wenn die Site das Feature längst nicht mehr nutzt (DNS: Log-Regeln ohne comment, `dnsui:tmp:`, der Forwarder `cfm-upstream` für `dnsui:`; Bonds: nicht mehr gewollte Bonds samt Bridge-Port vor den Ports; MLAG: `mlag-peer-port`). (2) Schaltet die Site ein Feature später ein (cfm-Editor), fehlt sein Modul in `work/`: `$cfmCheck` meldet das als Fehler (Bedingungen wie in den Rollen, Router-Module nur mit einem Gerät der Rolle `router`), das Release stoppt, statt dass die Geräte zurückrollen.

##### <a id="dg4.6.2"></a>DG4.6.2 · WLAN-Skripte des CAPsMAN als Rümpfe

*2026-11-02 · alt D104, Nachtrag 2*

**Entscheidung:** Auch die WLAN-Skripte des CAPsMAN werden Rümpfe: `capsman.ssid` (`cfm-ssid-<key>-on/-off`), `capsman.ssidcheck` (`cfm-ssid-check`, die SSIDs als Liste `ssids` statt je SSID eigener Code mit `cfmSsid<key>`-Variablen), `capsman.reprov` (`cfm-reprov`); gelesen per `$cfmBody` (lib.rsc, auch für `router.dnsreq`). Werte gehen als Locals davor, ein Rumpf ist eine Funktion (`:parse` der Datei allein); Name und Datei einer SSID kommen jetzt escaped in den Skripttext (vorher roh – ein `"` im SSID-Namen hätte das Skript zerbrochen). `capsman.*` geht auch an die Rolle `manager`, weil ohne Gerät mit Rolle `capsman` der Primary-Manager CAPsMAN ist (DW1.5). `cfm-reprov` braucht jeder CAPsMAN, die Schalt-Rümpfe nur Sites mit `switch` an einer SSID (`feature-module.py`, `$cfmCheck`).

## <a id="dm"></a>DM · Manager

### <a id="dm1"></a>DM1 · Aufbau

#### <a id="dm1.1"></a>DM1.1 · Manager-Funktionen als Module mit Lader

*2026-09-12 · alt D26*

**Entscheidung:** Module + Lader

**Verworfen:** eine Datei

**Umsetzung:** `/file get` liest nur etwa 60 KB. Die Funktionen liegen daher in `lib/mgr-*.rsc`: `core`, `check` (Prüfung, Probelauf), `enroll`, `onboard`, `ros` (RouterOS-Updates), `auto`; später dazu `net` (Verkabelung und WLAN-Kanäle, DW2.2/DU1.1), `show` (DU1.2), `notify` (DU4.1) und `mf` (Manifest-Regeln, DG2.5); 2026-10-20 aus `core` `vault` (Vault, Secrets, Identitätsprüfung, Rekey) und aus `net` `scan` (`$cfmWifiScan`) ausgelagert, damit jedes Modul deutlich unter der Grenze bleibt (vorher 47 KB). Die Rolle `manager` installiert jedes Modul aus dem Manifest als Skript `cfm-mgr-<modul>`, das Skript `cfm-mgr` lädt alle (Befehl im Terminal unverändert). Fehlen die Module im Manifest, bricht der Apply ab.

#### <a id="dm1.2"></a>DM1.2 · Manager-Tick einstellbar

*2026-09-17 · technisch, nicht abgefragt*

`mgrTick` in `global.rsc` (Standard 10 min) steuert Status-Abholung, Ring-Aufstieg, Secret-Sync, Updates, Netzplan, Hook und Vault-Backup. Das Onboarding läuft auf einem eigenen Scheduler jede Minute, damit eine laufende Sitzung nicht langsamer wird.

### <a id="dm2"></a>DM2 · Nebenläufigkeit

#### <a id="dm2.1"></a>DM2.1 · Überlappende Manager-Ticks: Job-Sperre

*2026-09-22 · technisch, nicht abgefragt · alt D42*

**Entscheidung:** Job-Sperre je Scheduler, Onboarding-Tick lädt im Leerlauf nichts, Schrittmarken im Log

**Verworfen:** nur die Startzeiten der beiden Scheduler versetzen · einen gemeinsamen Scheduler für beide Aufgaben

**Umsetzung:** Befund (CRS418, 2026-09-21/22): Bei vollem Archiv und einer Supout-Datei dauerte jede `/file/find`-Suche so lange, dass ein Tick Minuten brauchte; `cfm-mgr-tick` und der minütliche `cfm-mgr-onb-tick` stapelten sich dann auf, bis zu `action timed out`. Beide Scheduler starten jetzt nur, wenn nicht schon ein Lauf desselben Schedulers in `/system/script/job` steht (wie beim Agenten), sonst eine Warnung „… übersprungen (Vorlauf hängt)“. Der Onboarding-Tick lädt die Manager-Module nur, wenn `meta/onboard.dat` Aufträge enthält. `$cfmTick` schreibt vor jedem Schritt `cfm: tick collect/promote/secrets/upgrade/net/hook/ende` ins Log, damit ein Hänger zu lokalisieren ist. Die langsamen Dateisuchen selbst behob DG4.1 (Dateizugriff über den Namen, 2026-10-01). Nummer nachgetragen: Sie stand zuerst nur im Commit `bd39385`.

#### <a id="dm2.2"></a>DM2.2 · Gleichzeitige Manager-Ticks: kurz warten

*2026-10-01 · alt D57*

**Entscheidung:** Der allgemeine Tick wartet bis zu 60 s auf einen laufenden Onboarding-Tick (danach läuft er mit Warnung trotzdem) und setzt während seiner Arbeit `cfmTickBusy`; der Onboarding-Tick wartet bis zu 30 s auf einen arbeitenden allgemeinen Tick und lässt danach seine Minute aus

**Verworfen:** Onboarding-Tick überspringt sofort · beide überspringen

**Begründung:** Beide Scheduler starten zur selben Sekunde (`start-time=startup`). Mit sofortigem Überspringen käme das Onboarding bei `mgrTick=1m` (Labor) kaum dran, weil der allgemeine Tick die Sekunde jedes Mal gewinnen kann. Der Onboarding-Tick wartet nie auf einen allgemeinen Tick, der selbst noch wartet – so blockieren sie sich nicht gegenseitig. Der Onboarding-Tick prüft seine Aufträge jetzt über den Dateinamen statt per Suche über alle Dateien (DG4.1).

#### <a id="dm2.3"></a>DM2.3 · Sperre `cfmApplyBusy`

*2026-10-12 · technisch, nicht abgefragt*

Auf dem Manager teilen sich der Agent und die Manager-Funktionen dieselben globalen Variablen (`$cfmG`, Bibliothek). `$cfmLoadData` (fast jeder Manager-Befehl, der Tick) importierte `global.rsc` neu – fiel das in einen Apply des Managers selbst, lief `base` ohne die Werte aus seinem Hostfile (`adminUser`, `mgmtExtra`, Ports): Im Labor sperrte cm1 so admin und den Zugang vom Host, nachgestellt mit Push plus parallelem `$cfmLoadData`. `$cfmImportAll` setzt die Sperre für die Dauer des Apply (auch im Probelauf), `$cfmLoadData` wartet, solange sie gesetzt ist und ein Job `cfm-agent` läuft (höchstens 120 s, dann Warnung). Keine Rolle ruft Manager-Funktionen auf, eine Selbstblockade gibt es nicht. Labor: `e2e.sh` Schritt 14i.

#### <a id="dm2.4"></a>DM2.4 · Gegenrichtung: Zeitstempel `cfmMgrData`

*2026-10-12 · technisch, nicht abgefragt*

`cfmApplyBusy` schützte nur einen Apply, der schon lief, wenn ein Manager-Befehl begann. Startet der Apply erst während `$cfmCheck` oder `$cfmShow`, importieren diese weiter die Hostfiles anderer Geräte in `cfmHost`, den der Apply gerade liest (cm1 bekäme z.B. die Ports von sw1). `$cfmLoadData` setzt deshalb einen Zeitstempel und gibt ihn am Ende frei; mit `hold=yes` hält ihn der Aufrufer, und `$cfmCheck` frischt ihn vor jedem Hostfile auf. `$cfmImportAll` wartet, solange er jünger als 30 s ist (höchstens 120 s), und erst danach setzt es `cfmApplyBusy` – andersherum warteten beide aufeinander. Ein Zeitstempel statt eines Flags, damit ein abgebrochener Befehl nichts dauerhaft sperrt. Labor: `e2e.sh` Schritt 14j.

### <a id="dm3"></a>DM3 · Redundanz

#### <a id="dm3.1"></a>DM3.1 · Manager-Redundanz: Fallback-Liste

*2026-09-11 · alt D7*

**Entscheidung:** Fallback-Liste

**Verworfen:** VRRP-VIP

**Umsetzung:** Geräte probieren Manager der Reihe nach. Backup spiegelt Primary (Pull) und ist read-only bis zur Beförderung.

#### <a id="dm3.2"></a>DM3.2 · SFTP blockiert während des Spiegels: wiederholen

*2026-10-01 · alt D58*

**Frage:** SFTP des Primary blockiert, solange der Backup-Manager spiegelt (Rest von TODO 44)

**Entscheidung:** Wiederholen mit exponentieller Pause 8/16/32/64 s (zusammen 2 min) – beim Abruf des Manifests (auch im Watchdog-Lauf) wie bei den Dateien; ein Agent, der aus einer Admin-Sitzung läuft, bricht weiter sofort ab

**Verworfen:** Wiederholungen + kürzerer Spiegel · Wiederholungen + der Primary steuert den Spiegel

**Begründung:** Der Watchdog-Lauf rollte bisher zurück (mit Neustart), wenn er den Manager während eines Spiegel-Syncs nicht erreichte. Exponentielle Pausen fangen kurze Störungen schnell ab und überbrücken den ~1 min langen Sync, ohne den Manager mit Versuchen zu überhäufen.

## <a id="ds"></a>DS · Sicherheit

### <a id="ds1"></a>DS1 · Identität und Integrität

#### <a id="ds1.1"></a>DS1.1 · Zuordnung Gerät ↔ Hostfile

*2026-09-11 · alt D9*

**Entscheidung:** eigene Variante

**Verworfen:** Seriennummer · System-Identity

**Umsetzung:** Gerät matcht über Seriennummer, Dateien liegen nach Identity (`hosts/sw1.rsc`). Zuordnung Seriennummer → Name in `meta/inventory.rsc` (Manager-Metadaten, nicht versioniert). Gerätetausch = Seriennummer in einer Zeile ändern + Onboarding wiederholen.

#### <a id="ds1.2"></a>DS1.2 · Integritätsschutz: Manifest mit MAC je Gerät

*2026-09-12 · technisch, nicht abgefragt*

Jedes Gerät bekommt ein eigenes Manifest `live/m/<serial>.mf` mit Version, Rolle, Dateiliste + SHA-512 und einem MAC (`sha512(key . sha512(body))`) mit dem beim Onboarding ausgetauschten Geräteschlüssel. Geräte haben am Manager nur Lesezugriff. Der MAC schützt zusätzlich gegen manipulierte Spiegel oder Transportwege: Ein Gerät verwirft jedes Manifest, das nicht mit seinem Schlüssel gesichert ist.

#### <a id="ds1.3"></a>DS1.3 · Geräte-Rückmeldungen nur als Daten

*2026-09-12 · technisch, nicht abgefragt*

Status als JSON (`:deserialize`), Audit als Text. Der Manager führt nie etwas aus, das von einem Gerät stammt.

#### <a id="ds1.4"></a>DS1.4 · Identitätsprüfung und Geräteschlüssel

*2026-09-13 · alt D28*

**Thema:** Identität & Geräteschlüssel

**Entscheidung:** Rotation nur per Befehl

**Verworfen:** Rotation automatisch und per Befehl · automatisch inkl. SFTP-Key

**Umsetzung:** Vor jedem Secret-Push beweist das Gerät per Challenge-Response (`sha512(Schlüssel . Zufallswert)`), dass es seinen Geräteschlüssel kennt – ssh-exec prüft keine Host-Schlüssel. `$cfmRekey host=…|all=yes` erneuert den Schlüssel, nicht während eines Applys (dessen Rollback-Sicherung ist mit dem alten Schlüssel verschlüsselt), signiert die Manifeste neu und erhöht die Vault-Version (Backup-Manager und Vault-Backup ziehen nach).

#### <a id="ds1.5"></a>DS1.5 · RouterOS 7.25: Host-Key-Prüfung des SSH-Clients aus

*2026-10-11 · alt D71*

**Frage:** RouterOS 7.25: SSH-Client prüft Host-Keys

**Entscheidung:** Prüfung aus: Bootstrap (Manager und Geräte) und Rolle `base` setzen `known-hosts-validation=no` (nur, wo es die Property gibt)

**Verworfen:** Prüfung an, cfm-Wege per `known-hosts-trusted-subnets` frei · cfm pflegt `known-hosts` selbst (Keys der Manager im Manifest, Geräte-Keys beim Enroll)

**Begründung:** Nach einem Update steht die Prüfung auf `no`, nach Reset oder Neuinstallation auf `yes`. Dann scheitern die Übergabe des Manager-Bootstraps an sich selbst, der erste Pull eines Geräts und das Onboarding („host key not trusted“). Die Echtheit sichert cfm schon selbst ab: Manifeste sind signiert, der Secret-Push prüft die Identität (DS1.4). Ein vergessener Weg in einer Liste vertrauter Netze hätte ein Gerät abgeschnitten, auch beim Router-Umzug mit neuen Adressen

### <a id="ds2"></a>DS2 · Secrets und Sicherung

#### <a id="ds2.1"></a>DS2.1 · Rück-Export ohne Secrets

*2026-09-11 · alt D10*

**Entscheidung:** nur Export ohne Secrets

**Verworfen:** Export + verschl. Backup · Export mit Secrets

**Umsetzung:** `/export terse` (ohne `show-sensitive`). DR: zentrale Secrets liegen verschlüsselt im Vault (DS2.3); individuelle Secrets (Geräte-Key, MAC-Schlüssel) entstehen beim Onboarding und werden im DR-Fall per erneutem Onboarding neu erzeugt.

#### <a id="ds2.2"></a>DS2.2 · Secrets per Secret-Push

*2026-09-11 · alt D11*

**Thema:** Secrets-Transport

**Entscheidung:** Secret-Push per SSH

**Verworfen:** secrets.rsc nur auf Managern · Secrets nur lokal

**Umsetzung:** Nachträglich geändert: RouterOS-SFTP kennt keine Verzeichnisrechte, also könnte jedes Gerät jede Datei lesen. Deshalb schreibt der Manager Secrets per `ssh-exec` direkt in die Geräte-Config. Es gibt nie eine Secret-Datei. Benutzer werden bis zum ersten Push `disabled` angelegt.

#### <a id="ds2.3"></a>DS2.3 · Vault im verschlüsselten Manager-Backup

*2026-09-11 · alt D12*

**Entscheidung:** verschl. Manager-Backup

**Verworfen:** Vault-Datei mit Skript-Crypto

**Umsetzung:** Vault-Einträge sind deaktivierte `/ppp secret` namens `cfm:<key>`. Das Passwortfeld ist *sensitive*: Es fehlt im Export, ist aber im AES-verschlüsselten `/system backup` enthalten (zentrales Passwort). `$cfmVaultBackup` legt es in `vault/` ab, der Git-Hook spiegelt es.

#### <a id="ds2.4"></a>DS2.4 · Externe Sicherung über einen Git-Host

*2026-09-11 · alt D13*

**Entscheidung:** SSH-Exec → Git-Host

**Verworfen:** HTTP-Webhook · Log/Mail

**Umsetzung:** Hook-Events: `release`, `rollback`, `promote`, `state` (neue Geräte-Exporte, entprellt), `audit`, `vault`, `onboard`. Der Git-Host holt per SFTP und committet (`tools/git-host/cfm-git-sync`).

#### <a id="ds2.5"></a>DS2.5 · SFTP-Schlüssel rotieren, Geräte-User auf dem Backup

*2026-10-08 · alt D67*

**Frage:** SFTP-Schlüssel rotieren (Rest von TODO 8) und Geräte-User auf dem Backup

**Optionen (gewählt fett):** Umfang: **beides zusammen** – der Spiegel überträgt `meta/keys/<name>.pem`, der Backup legt `cfmd-<name>` selbst an; `$cfmRekey … sftp=yes` · nur die Backup-Lücke · nur die Rotation; Manager-Geräte: **zweiphasig gleich mitbauen** · Manager erst ausnehmen; ab wann Geräte vom Backup ziehen: **erst nach der Beförderung – die User liegen gesperrt bereit, `$cfmPromoteManager` schaltet sie frei** · Agent fragt immer zuerst den Primary, Backup nur als Notfall · zusätzlich Schutz vor älteren Manifesten (Ringwechsel bringen legitim kleinere Versionen)

**Begründung:** Der SFTP-Schlüssel eines Geräts ist sein exportierter ed25519-Host-Key (DS1.4) – eine Rotation ändert deshalb den Host-Key mit (SSH-Clients melden das einmal). Ablauf ohne Lücke: neuer Host-Key auf dem Gerät → neuer Schlüssel *zusätzlich* bei `cfmd-<name>` → Gerät importiert den privaten Schlüssel → alter Schlüssel weg. Ein Manager-Schlüssel ist zugleich der Trust-Key im User `cfm` aller Geräte: Er kommt erst auf **alle** aufgenommenen Geräte; fehlt eines, bricht die Rotation ab und `$cfmTrust` stellt den alten Stand her (sonst sperrte sich der Manager bei einem Gerät aus, das gerade offline ist). Erst dann ersetzt der Manager die privaten Schlüssel **aller** User mit Schlüssel (alles Kopien des Host-Keys: `cfm`, Admin-User aus `users`), danach entfernt `$cfmTrust` den alten überall, die Bootstrap-Datei wird neu geschrieben. Der private Teil eines Manager-Schlüssels liegt nur Sekunden als Datei auf dem Gerät (dessen Geräte-User dürfen per SFTP lesen) und sonst nur im Speicher der Funktion. `$cfmDevUser` merkt einen Hash des Schlüssels im Kommentar und lässt einen User mit passendem Hash und genau einem Schlüssel stehen – so kostet der Abgleich auf dem Backup bei jedem Spiegel fast nichts. Nach einer Rotation hat der Backup bis zu seinem nächsten Spiegel (≥ 5 min) noch den alten Schlüssel. Ein Git-Host (`hook`) kennt den alten Manager-Schlüssel weiter – `$cfmRekey` weist darauf hin. Ohne Beförderung hat der Backup nie einen neueren Stand als der Primary – auszuliefern brächte nichts, konnte aber ältere Stände verteilen; die Geräte laufen im Ernstfall bis zur Beförderung mit ihrem Stand weiter. Den User für sich selbst legt der Backup nicht an (sein Agent zöge sonst aus dem eigenen Spiegel, Labor: v12 statt der neuen Version; er überspringt sich weiter, solange der User fehlt, TODO 44); `$cfmPromoteManager` legt ihn an (`$cfmDevUsersOn`). Weil die Schlüssel schon abgeglichen sind, greift die Beförderung sofort.

### <a id="ds3"></a>DS3 · Benutzer und Dienste

#### <a id="ds3.1"></a>DS3.1 · Werks-User `admin` automatisch abschalten

*2026-09-12 · alt D25*

**Entscheidung:** automatisch abschalten

**Verworfen:** behalten

**Umsetzung:** `adminUser="disable"` (Standard): Die Rolle `base` schaltet `admin` ab, sobald auf dem Gerät ein User aus `users` aktiv ist, nie vorher. Das Gerät meldet den effektiven Wert (inkl. Hostfile-Ausnahme) im Status; steht dort `disable`, schaltet der Manager `admin` beim Secret-Push gleich mit ab (kein zusätzlicher Apply, der mit anderen Läufen kollidieren könnte). Die Rolle `manager` hinterlegt den Manager-Schlüssel auch für diese User, damit die `$cfm…`-Befehle ohne `admin` funktionieren. Ausnahme pro Gerät per Hostfile (`"keep"`).

*DS3.2 · Admin-SSH-Keys in einer gemeinsamen Datei – abgelöst durch DS3.3, siehe [Archiv](#ds3.2).*

#### <a id="ds3.3"></a>DS3.3 · Admin-SSH-Keys je Person

*2026-10-04 · alt D65*

**Löst ab:** DS3.2: Eine gemeinsame Datei für alle Admin-User erlaubte keinen Entzug je Person.

**Optionen (gewählt fett):** Ablage: **eine Datei je User `work/authorized_keys.<user>` (OpenSSH-Format)** · Präfix `<user>:` je Zeile in einer Datei · Zuordnung über den Key-Kommentar (`user@host`); Verhältnis zur gemeinsamen Datei: **nur noch je User – `authorized_keys` gilt nicht mehr, `$cfmCheck` lehnt sie ab** · Vereinigung (gemeinsame Keys für alle plus je User) · Datei je User ersetzt die gemeinsame; Abgleich: **gezielt über den Fingerprint (fehlende anlegen, übrige entfernen)** · alles neu schreiben, nur wenn sich die Datei ändert · wie bisher bei jedem Apply alles neu; User ohne Datei: **unangetastet** · entfernen, sobald irgendeine Key-Datei existiert

**Begründung:** Entzug pro Person ohne Nebenwirkung auf andere; das OpenSSH-Format bleibt, die Datei lässt sich direkt aus `~/.ssh/*.pub` zusammenstellen. RouterOS 7.24 nimmt den Key per `/user/ssh-keys/add user= key=` direkt an und liefert die ID; der `fingerprint` ist lesbar, ein `comment`/`set` gibt es nicht, und `:convert` kennt kein SHA-256 – den Fingerprint eines Soll-Keys erfährt `base` deshalb nur, indem es ihn anlegt; hat der User ihn schon, entfernt es den neuen Eintrag gleich wieder. So gibt es nie einen Moment ohne Key, und Log und Zähler nennen nur echte Änderungen (Apply idempotent). Scheitert ein Key, entfernt `base` für diesen User nichts (ein halber Sollzustand sperrt niemanden aus). Im Probelauf ist kein `add` möglich – dort Abgleich näherungsweise über den Kommentar (`info`). Folge von „unangetastet“: Eine gelöschte Datei entzieht nichts; alle Keys einer Person entzieht eine geleerte Datei. Umstellung der Sites: Keys nach `authorized_keys.<user>`, alte Datei auf dem Manager löschen – die vorhandenen Keys bleiben stehen (gleicher Fingerprint).

#### <a id="ds3.4"></a>DS3.4 · Dienst `reverse-proxy` aus

*2026-09-30 · technisch, nicht abgefragt*

Der Dienst `reverse-proxy` (TODO 30) steht in der Dienstliste der Rolle `base` wie `www-ssl`, ist also aus, sofern `services` ihn nicht nennt. RouterOS 7.2x schaltet ihn ab Werk auf Port 443 ohne Adressbeschränkung ein; ältere Versionen kennen ihn nicht (`$cfmSet` findet dann nichts). `$cfmCheck` meldet unbekannte Dienstnamen (z.B. `http`) und doppelte Ports in `services` als Fehler.

#### <a id="ds3.5"></a>DS3.5 · WebFig per HTTPS zurückgestellt

*2026-10-01 · technisch, nicht abgefragt*

WebFig per HTTPS (TODO 25) ist zurückgestellt, bis Let's Encrypt über acme-dns mit einer öffentlichen Domain steht.

## <a id="do"></a>DO · Onboarding

### <a id="do1"></a>DO1 · Werksgeräte aufnehmen

#### <a id="do1.1"></a>DO1.1 · Erstzugriff: Push in die Werks-Config

*2026-09-12 · alt D21*

**Thema:** Erstzugriff auf Werksgeräte

**Entscheidung:** Push in die Werks-Config

**Verworfen:** Netinstall-Station · Push + Branding-Paket

**Umsetzung:** Der Manager meldet sich mit `admin` + Aufkleber-Passwort (aus der Vorab-Registrierung) an und lädt Skripte per SFTP als `*.auto.rsc` hoch (werden sofort ausgeführt). Netinstall und Branding stehen in [TODO.md](TODO.md).

#### <a id="do1.2"></a>DO1.2 · Anschlussort: temporärer Onboarding-Port

*2026-09-12 · alt D22*

**Entscheidung:** am Zielort, temporärer Onboarding-Port

**Verworfen:** am Zielort (Onboarding-VLAN dauerhaft) · Werkbank-Port

**Umsetzung:** `$cfmOnboard sw=<switch> port=<port>` schaltet genau einen Port vorübergehend ins Onboarding-VLAN (untagged, die normalen tagged VLANs bleiben). Nach erfolgreichem Onboarding stellt ein erzwungener Apply des Switches das Port-Profil aus dem Hostfile wieder her. Ein Fail-safe-Timer auf dem Switch tut das spätestens nach Ablauf der Zeit.

#### <a id="do1.3"></a>DO1.3 · Freigabe per Vorab-Registrierung

*2026-09-12 · alt D23*

**Entscheidung:** Vorab-Registrierung

**Verworfen:** immer manuell · vollautomatisch

**Umsetzung:** `$cfmRegister` (Seriennummer, Name, Rolle, Ring, MGMT-IP, Aufkleber-Passwort → Vault). Nur passende Seriennummern werden aufgenommen; unbekannte landen in `$cfmPending` und werden per `$cfmApprove` freigegeben.

#### <a id="do1.4"></a>DO1.4 · Onboarding-VLAN 88

*2026-09-12 · technisch, nicht abgefragt*

**Onboarding-VLAN 88 = `192.168.88.0/24`**, bewusst passend zur Werks-IP `192.168.88.1` neuer Geräte. Gateway `.250` (Router), DHCP `.100–.199` vom Primary-Manager (für Geräte mit DHCP-Client in der Werks-Config, z.B. APs im CAPs-Modus). Die Manager erreichen die Geräte direkt auf Layer 2 und haben dort die Host-Adresse ihrer MGMT-IP.

#### <a id="do1.5"></a>DO1.5 · Zweistufiger Push: Probe, dann Reset mit Bootstrap

*2026-09-12 · technisch, nicht abgefragt*

Stufe 1 (Probe) liest Seriennummer/Modell/Version und stößt ggf. das Update an. Stufe 2 lädt den gerätespezifischen Bootstrap hoch und setzt das Gerät per `reset-configuration no-defaults=yes run-after-reset=` auf eine leere Config mit genau diesem Bootstrap zurück (keine Werks-Firewall/-DHCP-Reste). Danach läuft das normale `$cfmEnroll`.

#### <a id="do1.6"></a>DO1.6 · Eine Sitzung gleichzeitig, Werksgeräte finden

*2026-09-12 · technisch, nicht abgefragt*

**Immer nur eine Onboarding-Sitzung gleichzeitig** (alle Werksgeräte haben `192.168.88.1`).

**Werksgeräte findet der Manager unter `192.168.88.1` oder über ihre DHCP-Lease** im Onboarding-VLAN. Geräte mit PoE-Eingang nur an ether1 (hAP) starten dafür im CAPs-Modus (Reset-Taster ~10 s): Dort ist ether1 ein Management-Port mit DHCP-Client ohne Firewall, statt WAN-Port mit Firewall.

#### <a id="do1.7"></a>DO1.7 · Onboarding hinter einem unverwalteten Switch

*2026-09-30 · alt D50*

**Frage:** Onboarding hinter einem Switch, den cfm nicht verwaltet

**Entscheidung:** `$cfmOnboard manual=yes [name=] [sw= port=]`: Der Admin schaltet den Port selbst ins Onboarding-VLAN und zurück; kein Fail-safe, kein Push an den Switch, `sw`/`port` nur als Notiz; am Ende eine Warnung im Log, den Port zurückzustellen

**Verworfen:** `sw=-` · `port=manual`

**Begründung:** Hardware-Befund (TODO 31): Beim ersten Gerät hinter dem noch nicht übernommenen Core-Switch musste die Sitzung von Hand in `meta/onboard.dat` angelegt werden, und der Manager versuchte in jedem Tick, sich am Switch anzumelden. Ein eigener Schalter ist selbsterklärender als ein Sonderwert.

### <a id="do2"></a>DO2 · Bestandsgeräte und Inventar

#### <a id="do2.1"></a>DO2.1 · Bestandsgerät übernehmen, das noch selbst routet

*2026-09-23 · technisch, nicht abgefragt · alt D43*

**Entscheidung:** Rolle `switch` plus Hostfile-Schlüssel `cpuVlans`, `gw`/`dns`/`ntp`, `bridgeFrames`, Freigaben in `local-input` per `post.rsc`; Aufnahme ohne Reset mit `$cfmEnroll noapply=yes` und `$cfmPlan` vor dem ersten Apply

**Verworfen:** erst nach dem Router-Umzug übernehmen · Rolle `router` sofort (kollidiert mit den laufenden Gateway-Adressen)

**Umsetzung:** Hardware-Befund (Core-Switch mit L3 im Switch-Chip): Der erste Apply der Rolle `base` hätte die Bridge aus den VLANs der eigenen VLAN-Interfaces genommen (Routing weg), Default-Route, DNS und NTP auf das Gerät selbst gesetzt (es ist das MGMT-Gateway) und mit dem input-Block DHCP-, NTP- und SNMP-Server abgeschnitten – still, ohne dass der Watchdog etwas merkt. Die Schlüssel greifen nur, wo das Hostfile sie setzt, und nur ohne Rolle `router`. `noapply` installiert Agent und Schlüssel mit ausgeschaltetem Scheduler, damit `$cfmPlan` jede Änderung zeigt, bevor etwas passiert; der erste Apply schaltet den Scheduler ein. Ohne Reset bleiben Objekte ohne cfm-Tag stehen (Skripte, Dienste); die Bootstrap-Route trägt den Tag `cfm:rt:default`, damit `gw=` sie übernimmt statt eine zweite Default-Route anzulegen.

#### <a id="do2.2"></a>DO2.2 · Nur aufgenommene Geräte ansprechen

*2026-09-30 · alt D49*

**Frage:** Welche Inventar-Einträge spricht der Manager an?

**Entscheidung:** Nur aufgenommene Geräte = Geräteschlüssel `mac.<Seriennr.>` im Vault (dasselbe Kriterium wie bei den Manifesten, `$cfmEnrolled`). Push, Secret-Push, Trust, Rekey (`all=yes`), Collect, Auto-Promote und `$cfmUpgrade` lassen die übrigen aus; `$cfmPush` nennt sie in einer Sammelzeile, `$cfmStatus` zeigt „nicht aufgenommen“

**Verworfen:** nur Platzhalter-Seriennummern (`SERIAL-…`, leer) ausschließen

**Begründung:** Befund an einem Standort (TODO 28): Drei noch nicht aufgenommene Geräte erzeugten bei jedem Release eine Fehlerzeile und beim Secret-Push eine Warnung; ein fremdes Gerät unter der geplanten Adresse wäre mit angestoßen worden. Auch ein per `$cfmRegister` eingetragenes Gerät ist bis zum Enroll nicht erreichbar. Nebenbei hielten solche Einträge den automatischen Ring-Aufstieg und `$cfmUpgrade ring=/all=yes` auf (Status ohne Architektur).

### <a id="do3"></a>DO3 · Manager aufsetzen

#### <a id="do3.1"></a>DO3.1 · Manager-Bootstrap auf leerer Config

*2026-09-13 · technisch, nicht abgefragt*

`bootstrap-manager.rsc` setzt das Gerät mit `clean="yes"` zuerst per `reset-configuration no-defaults=yes keep-users=yes run-after-reset=` zurück und läuft danach selbst weiter; `keep-users` erhält User, Passwörter und SSH-Schlüssel. Das run-after-reset-Skript läuft als Systemnutzer `*sys` ohne SSH-Schlüssel, und die Dienste starten erst nach ihm (siehe [Eigenheiten](ROUTEROS-EIGENHEITEN.md)). Deshalb richtet es nur `post`, den MGMT-Zugang und den User cfm mit einem Einmal-Passwort ein. Ein Scheduler lädt nach dem Hochfahren per SFTP mit diesem Passwort eine `.auto.rsc` an 127.0.0.1 hoch, die RouterOS als cfm ausführt; sie legt einen Scheduler an, der cfm gehört und den eigentlichen Bootstrap samt Selbst-Enroll ausführt. Danach bekommt cfm ein neues Zufallspasswort. Die Stufen erkennt die Datei an Markierungsdateien, Fortschritt und Fehler stehen im Log. So bleiben keine Reste einer Werks- oder CAPs-Config; auf einem bestehenden Manager wird der Reset verweigert. Verworfen: ein zweiter Import von Hand nach dem Reset (einfacher, aber nicht automatisch).

## <a id="dv"></a>DV · RouterOS-Versionen

### <a id="dv1"></a>DV1 · Updates und Versionen

#### <a id="dv1.1"></a>DV1.1 · Update aus dem Internet beim Onboarding

*2026-09-12 · alt D24*

**Thema:** RouterOS-Version

**Entscheidung:** Update aus dem Internet

**Verworfen:** Zielversion vom Manager · nur Mindestversion

**Umsetzung:** Das Probe-Skript prüft den Kanal (`rosChannel`) und installiert Updates. Das Onboarding-VLAN darf über den Router nur die MikroTik-Update-Server erreichen (FQDN-Adressliste). `rosMin` ist Abbruchkriterium, falls kein Update möglich ist.

#### <a id="dv1.2"></a>DV1.2 · Pakete vom Manager, Neustart nur per Befehl

*2026-09-13 · alt D30*

**Thema:** RouterOS-Versionen

**Optionen (gewählt fett):** Pakete: exakte Version aus dem Internet · **Manager hält Pakete** · nur Kanal; Neustart: Wartungsfenster · sofort · **nur per Befehl (sofort oder einmaliges Fenster)**

**Umsetzung:** `$cfmUpgrade ver=… host=|ring=|all=yes [at=…]`. Der Manager lädt vor dem Rollout alle Pakete (routeros + Zusatzpakete) für alle betroffenen Architekturen nach `pkgPath/<ver>/`; fehlt eins, startet nichts. Der Auftrag steht im signierten Manifest (Feld `ros`, zählt nicht zum Manifest-Hash). Der Agent lädt per SFTP, prüft die Größe (Hashes gehen nicht: `/file get` liest nur ~60 KB; die Signatur prüft RouterOS beim Installieren) und startet sofort oder per Scheduler neu. Ältere Zielversion = `/system/package/downgrade`. Ein erfolgloser Neustart wird nicht wiederholt (`fehlgeschlagen`). Versionen, die kein Gerät installiert hat und kein Auftrag nennt, löscht der Manager. Platzprüfung: DV1.3, Probe ohne Auftrag: DV1.4, Geräte mit wenig Flash: eingebautes Update (DV1.5).

#### <a id="dv1.3"></a>DV1.3 · Platz für Pakete auf kleinen Geräten

*2026-09-30 · alt D51*

**Frage:** Platz für RouterOS-Pakete auf kleinen Geräten

**Entscheidung:** Doppelt prüfen: Der Agent meldet `free-hdd-space` im Status (`fs`, nicht bei Geräten mit `flash/`-Verzeichnis, deren Wurzel im RAM liegt); `$cfmUpgrade` erteilt Geräten, bei denen Pakete + 1 MB Reserve nicht passen, keinen Auftrag. Der Agent prüft vor dem Download erneut, lädt dann nichts und meldet „Platz fehlt“ (kein neuer Versuch)

**Verworfen:** nur Agent · nur Manager

**Begründung:** Hardware-Befund hEX RB750Gr3 (16 MB Flash, 2,4 MB frei, `routeros` ~12 MB, TODO 38): Ein halb voller Flash lässt auch Config und Log scheitern. Der Platz kann sich zwischen Auftrag und Download ändern. Für solche Geräte gibt es seit DV1.5 das eingebaute Update (der Weg über eine RAM-Disk geht nicht, Labor).

#### <a id="dv1.4"></a>DV1.4 · Fehlende Pakete am Manager ohne Internet

*2026-09-30 · alt D52*

**Entscheidung:** `$cfmUpgrade … check=yes`: Probe ohne Download und ohne Auftrag – je Gerät Version, Architektur, Bedarf, freier Platz, Urteil, dazu alle fehlenden Dateien mit Ablageort und Download-URL. Der echte Auftrag nennt ebenfalls alle fehlenden Pakete auf einmal. Pakete gelten nur mit NPK-Kennung (`1e f1 d0 ba`, per `/file/read`) als gültig statt über eine Mindestgröße

**Verworfen:** nur die volle Liste beim Auftrag

**Begründung:** Befund an einem Standort: Das MGMT-VLAN hat kein Internet, Pakete kommen von Hand nach `cfm/pkg/<ver>/`. Bisher brach der Auftrag beim ersten fehlenden Paket ab. Die Mindestgröße (erst 100, dann 20 KB) war ein Notbehelf (TODO 37).

#### <a id="dv1.5"></a>DV1.5 · Eingebautes Update für Geräte mit 16 MB Flash

*2026-10-03 · alt D63*

**Frage:** RouterOS-Update auf Geräten mit 16 MB Flash (TODO 38)

**Entscheidung:** `$cfmUpgrade … via=internet` bzw. `via=mirror mirror=<IP>`: das eingebaute Update des Geräts (`/system/package/update/install`); für den Spiegel setzt der Agent befristet einen statischen DNS-Eintrag `upgrade.mikrotik.com` → Spiegel und `mode=http`, danach zurück. Spiegel: `tools/upgrade-mirror.py <ver>` (hält die Version fest, holt den Rest bei Bedarf von MikroTik)

**Verworfen:** nur `via=internet` · nur Spiegel · nur Anleitung

**Begründung:** Laborversuch (CHR 7.24.2 → 7.24.5): Pakete in einer RAM-Disk (tmpfs) installiert RouterOS beim Neustart nicht; das eingebaute Update ließ sich dagegen per DNS-Umleitung und `mode=http` auf einen lokalen Spiegel lenken. Es braucht dort nur `NEWESTa7.<Kanal>`, `<ver>/CHANGELOG` und die Pakete (`packages.csv` der installierten Version fragt es an, kommt aber ohne aus). Mit wenig Flash kommt das eingebaute Update zurecht (Hardware: ein CRS328 mit 1,7 MB frei hat sich so aktualisiert). Es installiert nur die angebotene Version und kein Downgrade – der Agent vergleicht `latest-version` mit dem Auftrag. Die Pakete sind von MikroTik signiert; HTTP gilt nur für die Dauer des Updates. Kanal der Zielversion: RCs in `testing`, Betas in `development` (upgrade.mikrotik.com 2026-10-20: `NEWESTa7.testing` 7.25rc2, `NEWESTa7.development` 7.26beta3) – bis zum Code-Review vom 2026-10-20 nahmen Agent und Spiegel für Betas `testing`, eine Beta per `via=internet` scheiterte damit.

#### <a id="dv1.6"></a>DV1.6 · Versionsangaben: Präfix `v` und Kanal

*2026-10-11 · technisch, nicht abgefragt*

Versionsangaben überstehen den JSON-Umlauf nur geschützt (`:deserialize` macht aus `7.24.5` die IP-Adresse `7.24.0.5`). Befund 2026-10-11: Der Agent merkte sich die geflashte RouterBOARD-Firmware als `"7.24.5"` in `state.json`, der Schutz „je Firmware-Version höchstens ein Neustart“ (2026-09-23) griff deshalb nie – wird eine geflashte Firmware nicht aktiv, hätte der Agent bei jedem Lauf neu geflasht und neu gestartet. Jetzt trägt der Wert das Präfix `v` (wie die Werte im Manifest). Befund im Labor auf 7.25rc1: RouterOS meldet die Version ohne Kanal („7.25.1“ statt „7.24.5 (stable)“), beim Manager wurde daraus eine IP-Adresse (`7.25.0.1`, `7.25` → `7.0.0.25`), `$cfmUpgrade` hätte ein Update nie als erledigt erkannt. Jetzt hängt der Agent den Kanal an. `tools/rsc-check.py` meldet solche ungeschützten Werte (Regel `json-typ`); die Regel fand im alten Stand auch den Fehler der Firmware-Sperre.

## <a id="dp"></a>DP · Ports und VLANs

### <a id="dp1"></a>DP1 · Ports und VLANs

#### <a id="dp1.1"></a>DP1.1 · Port-Profile

*2026-09-11 · alt D14*

**Thema:** VLAN ↔ Port

**Entscheidung:** Port-Profile

**Verworfen:** explizite Listen je Port

**Umsetzung:** Profile `trunk`, `trunk-ap`, `access:<vid>`, `hybrid:<vid>`, `wan`, `off` (später `vport:<vid>`, DP1.2). Neue VLANs erscheinen automatisch auf passenden Trunks. Bonds bekommen ihr Profil wie jeder Port (DP2.1).

#### <a id="dp1.2"></a>DP1.2 · Router/Manager als VM mit einer Karte je VLAN

*2026-09-17 · alt D40*

**Thema:** Router/Manager in einer VM mit einer Karte je VLAN und Spanning Tree

**Entscheidung:** RSTP auf der VM-Bridge abschalten (`stp="none"` im Hostfile)

**Verworfen:** eine Trunk-Karte statt einer Karte je VLAN (kostet Durchsatz, weil CHR-Lizenzen je Interface begrenzen) · lassen und nur den BPDU-Guard weglassen

**Umsetzung:** Die Karten der VM führen über die Bridge des Virtualisierungshosts alle ins selbe Netz. Für RSTP sieht das wie eine Schleife aus (es blockierte Ports und schnitte damit ganze VLANs ab), und die VM streut ihre BPDUs ungetaggt in jede dieser Karten, die der Host dann je VLAN taggt. Die Trennung leistet dort das VLAN-Filtering. Als Sicherheitsnetz warnt `$cfmCheck` bei `stp="none"`, wenn zwei Ports untagged im selben VLAN liegen oder mehrere Ports getaggte VLANs führen – dann wäre die Schleife echt. Auf Switches bleibt RSTP unverändert an; Ports zu Hypervisoren nehmen das Profil `vport` (kein BPDU-Guard, weil die Host-Bridge BPDUs durchreicht).

#### <a id="dp1.3"></a>DP1.3 · Vorhandene VLAN-Interfaces unter fremdem Namen

*2026-10-17 · alt D87*

**Entscheidung:** Natürlicher Schlüssel `$cfmVlanKey`: zuerst das Interface `vlan<VID>`, sonst eines auf der Bridge mit dieser VLAN-ID; `$cfmEnsure` übernimmt es und benennt es in `vlan<VID>` um (Rollen `base`, `router`, `manager`) (Nutzer, 2026-10-17)

**Verworfen:** weiter nur über den Namen · nur über Bridge und VLAN-ID

**Begründung:** Verweise auf das Interface (Adressen, DHCP-Server, Listen, Firewall) gehen in RouterOS über die ID und bleiben am umbenannten Interface. Der Name bleibt der erste Schlüssel, damit nichts anderes als bisher übernommen wird. Im Probelauf unterbleibt das Umbenennen: Objekte am Interface erscheinen dort noch als „neu“, der Apply übernimmt sie. Labor: `e2e.sh` Schritt 9 (Interface `GAST` mit VID 40 und Router-Adresse).

### <a id="dp2"></a>DP2 · Bonds und MLAG

#### <a id="dp2.1"></a>DP2.1 · Bonds im Hostfile

*2026-10-12 · alt D74*

**Entscheidung:** Abschnitt `bonds` (`{"bond1"={"slaves"="sfp1,sfp2";"mode";"hash";"primary"}}`), das Profil steht wie bei jedem Port unter `ports` (`"bond1"="trunk"`)

**Verworfen:** Gruppe am Port-Profil (`"sfp1"="trunk@bond1"`)

**Begründung:** Der Bond ist ein Interface wie jedes andere, Profile, VLAN-Tabelle und `$cfmShow` behandeln ihn ohne Sonderfall. Standard: `802.3ad`, `lacp-rate=1sec`, `transmit-hash-policy=layer-2-and-3`; zweiter Modus `active-backup` (mit `primary`). `base` entfernt Bonds, die es nicht mehr geben soll, und nimmt Slaves vor dem Anlegen aus der Bridge – beides vor den Ports, sonst wären die Slaves dort noch belegt. Slaves gelten nicht mehr für `portDefault`/`ports` (`$cfmCheck` warnt). Labor: Ein 802.3ad-Port ohne LACP-Gegenstelle leitet weiter; ein einseitig umgestellter Uplink reißt also nicht sofort ab

#### <a id="dp2.2"></a>DP2.2 · MLAG-Paare

*2026-10-12 · alt D75*

**Entscheidung:** Zentrale Datei `mlag.rsc`: je Paar `nodes`, `primary`, `peer` (Ports der Verbindung beider Knoten), optional `stpPrio`, `lacpFallback`, `initDelay`, und `bonds` mit `id`, `ports`, `profile` (Ports als Text = auf beiden Knoten gleich, sonst je Knoten)

**Verworfen:** im Hostfile je Peer mit `partner`

**Begründung:** Beide Seiten an einem Ort, dadurch zwangsläufig konsistent (gleiche mlag-id, gleiches Profil). `base` legt den Peer-Bond `peer-<Paar>` an (LACP, alle VLANs getaggt, nur getaggte Frames), die MLAG-Bonds mit `mlag-id`, setzt nach dem VLAN-Filtering `mlag-peer-port` und `mlag-priority` (Primary 50, sonst 128) und schaltet L3-Hardware-Offloading ab (MikroTik: verträgt sich nicht mit MLAG). `stpPrio` des Paars gilt auf beiden Knoten. `$cfmCheck`: zwei Knoten aus dem Inventar im **selben Ring** (sonst liefe ein Knoten tagelang mit, der andere ohne MLAG), Primary einer davon, mlag-id eindeutig, Ports nicht zugleich im Hostfile, gleiche STP-Priorität, kein `stp="none"`. Voraussetzung RouterOS 7.22 (Bridge-Menü, sonst bricht `base` ab). `lacpFallback`/`initDelay` gibt es ab 7.25 (Werkseinstellung dort: `mlag-lacp-fallback=yes`, `mlag-init-delay=1m`). Labor: `e2e-mlag.sh`

### <a id="dp3"></a>DP3 · Isolation

#### <a id="dp3.1"></a>DP3.1 · IoT-Isolation über APs und Switches hinweg

*2026-10-12 · alt D76*

**Optionen (gewählt fett):** Einschalten: **VLAN-Attribut `isolate="yes"` in `vlans.rsc` mit Ausnahmen `isolateAllow` (Namen aus `leases.rsc` oder MAC-Adressen)** · ohne Ausnahmen · an der SSID/PPSK-Gruppe. Umfang: **über APs hinweg, Kabel-Ports, Freigaben mit Ports**; Proxy als Ziel später. WLAN: **Datapath der isolierten SSIDs mit `interface-list=cfm-iso`, Rolle `ap` trägt die Interfaces sonst selbst ein** · zentral über den CAPsMAN (`traffic-processing=on-capsman`). Kabel-Ports mit Hardware-Offload: **`hw=no` für isolierte Access-Ports, derselbe Bridge-Filter** · Regeln im Switch-Chip (modellabhängig, im Labor nicht prüfbar). Multicast zwischen Clients: **gesperrt** · erlaubt

**Begründung:** Client-Isolation am WLAN trennt nur Clients am selben AP. Der Filter sitzt am Eingang jedes Client-Ports (Liste `cfm-iso`): Erlaubt sind Broadcast (ARP, DHCP), die Ausnahmen (Quell- oder Ziel-MAC), Frames an die VRRP-MAC (`00:00:5E:00:01:xx`) und an die Bridge-MACs der Router, IP aus dem eigenen Netz nach außerhalb und zu den Adressen der Router im VLAN (`.gw`, `.251`–`.254`, DR1.1) sowie ARP zu ihnen; Multicast wird vorher verworfen, alles andere am Ende. Ein Frame von Client zu Client endet so schon am Gerät des Absenders, auch wenn beide am selben Switch hängen. *Korrektur bei der Umsetzung:* Zuerst kam der Filter ohne Router-MACs aus (nur IP-Matcher). Mit e1000-Karten sah der Bridge-Filter die ungetaggt angekommenen Frames aber als `vlan`, die IP-Regeln griffen nicht, und die Clients erreichten das Gateway nicht ([Eigenheiten](ROUTEROS-EIGENHEITEN.md)). Seitdem meldet der Agent die MAC seiner Bridge im Status (VLAN-Interfaces haben keine eigene), der Manager schreibt die MACs aller Geräte mit Rolle `router` ins Manifest (`rmac`, nur wenn ein VLAN isoliert ist), und MAC-Matcher greifen unabhängig von dieser Sicht; die IP-Regeln bleiben als Ergänzung. Nach einem Router-Tausch braucht es deshalb ein Release. Am Trunk-Eingang zu filtern ging nicht: Getaggte Frames erlauben keine IP-Matcher. Client-Ports sind reine Access-Ports eines isolierten VLANs (Hybrid-Ports: Warnung) und die WLAN-Interfaces isolierter SSIDs (Client-Isolation wird dort mit eingeschaltet). Ob der CAPsMAN `interface-list` an die CAPs weitergibt, ist auf Hardware offen; im lokalen Fallback (DW1.8) gilt der lokale Datapath ohnehin. IPv6 geht in isolierten VLANs nicht (cfm routet noch kein IPv6, TODO 13). Labor: `e2e-mlag.sh` Schritt 10

## <a id="dr"></a>DR · Routing und Firewall

### <a id="dr1"></a>DR1 · Gateway und VRRP

#### <a id="dr1.1"></a>DR1.1 · Gateway: VRRP, optional

*2026-09-11 · alt D15*

**Entscheidung:** VRRP (wie ein vorhandenes Skript), optional

**Verworfen:** Einzelrouter mit freien Subnetzen

**Umsetzung:** `192.168.<VID>.0/24`, VIP `.gw` (Default 1), reale IP `.250+routerId`; ohne `routerId` bekommt der Router direkt `.gw`. DHCP läuft nur auf dem VRRP-Master.

#### <a id="dr1.2"></a>DR1.2 · Routing in der CPU statt im Switch-Chip

*2026-09-17 · alt D37*

**Thema:** Routing auf CRS-Switches mit L3-Hardware-Offloading

**Entscheidung:** alle VLANs über VRRP-Router in der CPU

**Verworfen:** Routing im Switch-Chip ohne VRRP, Filter nur zustandslos per Switch-Regeln, Gäste/IoT per Regel zur CPU · Hybrid: vertrauenswürdige VLANs im Switch-Chip, Gäste/IoT auf einem CPU-Router

**Umsetzung:** Laut MikroTik-Doku gibt es mit L3-Hardware-Offloading kein VRRP (dafür muss `l3-hw-offloading` am Switch ganz aus sein), die Chips kleinerer CRS3xx (z.B. 98DX3236, 98DX226S) können außerdem weder NAT noch Fasttrack im Chip, und die CPU-Firewall sieht im Switch-Chip gerouteten Verkehr nicht. Die Rolle `router` schaltet deshalb `l3-hw-offloading` am Switch ab (Geräte ohne die Eigenschaft bleiben unberührt; nach Entfernen der Rolle bleibt es aus). Ein Core-Switch kann trotzdem als VRRP-Reserve mitlaufen: mit der höchsten `routerId` (niedrigste Priorität) routet er nur im Ausfall, dann langsamer in der CPU.

#### <a id="dr1.3"></a>DR1.3 · VRRP-Interfaces in den Zonen-Listen

*2026-10-01 · technisch, nicht abgefragt*

Verkehr an die VIP kommt über `vrrp<VID>` herein, nicht über `vlan<VID>` – die Zonen-Firewall verwarf deshalb allen gerouteten Verkehr der Clients (sie nutzen die VIP als Gateway). Die VRRP-Interfaces stehen jetzt in derselben Zonen-Liste wie ihr VLAN, das des WAN-VLANs auch in `WAN`. Die reale Adresse (.250 + routerId) sucht die Rolle über Interface **und** Adresse – auf einem Router, der zugleich Primary-Manager ist, übernahm sie sonst dessen Onboarding-Adresse, und beide Rollen setzten sie bei jedem Apply hin und her. Im Onboarding-VLAN schalten die VRRP-Skripte keinen DHCP-Server mehr (dort vergibt der Primary-Manager; `on-backup` schaltete ihn ab).

#### <a id="dr1.4"></a>DR1.4 · Probelauf der Rolle `router` vor dem ersten VRRP

*2026-10-11 · technisch, nicht abgefragt*

Die Rolle fragte für den DHCP-Server den Zustand des VRRP-Interface ab; im Probelauf ist es noch nicht angelegt, der Lauf brach ab. Fehlt es, gilt das Gerät jetzt als „nicht Master“ (DHCP aus), wie beim ersten echten Apply bis zur VRRP-Wahl. Labor: `e2e.sh` Schritt 6 (VLAN mit DHCP, kein Fehler).

#### <a id="dr1.5"></a>DR1.5 · Startender VRRP-Backup: Dienste erst nach 5 s

*2026-10-18 · alt D85*

**Frage:** Ein startender VRRP-Backup ist kurz selbst Master (Befund bei Ausfalltests an einem Standort 2026-10-18, 7.24.5: Neustart eines Backups auf CHR – etwa 8 s nach dem Start hörte er die Werbung des Masters noch nicht, wurde per „master down timer“ für 2 s Master und schaltete dabei DHCP und `wg-admin` an; dasselbe Muster beim Start des Masters auf einem hAP be³)

**Entscheidung:** `on-master` wartet 5 s und schaltet DHCP, `wg-admin` und `rt:wg` nur, wenn das VRRP-Interface dann noch Master ist; `on-backup` schaltet weiter sofort (Nutzer)

**Verworfen:** nur dokumentieren (kostete im Test einen verlorenen Ping) · VRRP beim Start verzögert einschalten (Scheduler beim Boot; RouterOS kennt keine Startverzögerung, der Wettlauf mit dem Boot bliebe)

**Begründung:** Die VIP selbst wandert weiter ohne Verzögerung, nur die Dienste dahinter folgen 5 s später. Bei einem echten Ausfall fällt das nicht auf: DHCP-Clients wiederholen ihre Anfrage, ein WireGuard-Client braucht nach dem Wechsel ohnehin etwa 15 s für den neuen Handshake. Kein STP im Spiel (Bridge des CHR ohne Protokoll). Wechselt der Zustand in den 5 s mehrmals, prüft jeder Lauf erneut. Beim Update: Eine Änderung an `on-master`/`on-backup` startet das VRRP-Interface neu – der Master geht kurz auf Backup, ein Backup übernimmt für etwa 9 s (Labor 7.24.5), danach preemptet der Master wieder; das erste Release mit DR1.5 verursacht also je VLAN einen kurzen Wechsel (WireGuard-Clients etwa 15–30 s ohne Tunnel). Labor: `e2e-vrrp.sh` Schritt 7b (r2 verwirft die VRRP-Werbung 3 s lang per `raw`, wird Master, DHCP bleibt aus; nach der Rückkehr kein DHCP und kein Tunnel auf r2), Wartezeiten nach dem Umschalten in den Schritten 6, 8 und 9 von 6–8 auf 10 s; Gegenprobe ohne Wartezeit: r2 schaltet DHCP während des Ausflugs ein

### <a id="dr2"></a>DR2 · Firewall, NAT, Queues

#### <a id="dr2.1"></a>DR2.1 · Firewall-Zonen über Interface-Listen

*2026-09-11 · alt D16*

**Entscheidung:** Zonen via Interface-Listen

**Verworfen:** Basis zentral, Rest lokal

**Umsetzung:** Zone je VLAN, Policy-Matrix in `global.rsc`. Lokale Regeln gehören in die Chains `local-input`/`local-forward` (Hook-Punkte vor dem finalen Drop).

#### <a id="dr2.2"></a>DR2.2 · Minimale Firewall für Nicht-Router

*2026-09-13 · alt D31*

**Optionen (gewählt fett):** Regelwerk: **Default-Drop** · nur Dienste sperren; IPv6: **IPv6-Firewall** · abschalten · nicht anfassen; Log: **begrenzt** · nein

**Umsetzung:** Nicht-Router (Switch, AP, Manager) bekommen den input-Block `fwb`: Antworten, ICMP, Adressliste `cfm-mgmt` (MGMT-Netz, `mgmtAccess`, `mgmtExtra`), auf Managern DHCP im Onboarding-VLAN, Sprung in `local-input`, MNDP mit Quelle `0.0.0.0` still (DR2.5), Log `cfm-drop` (10/min), Drop. IPv6-input `fw6` auf allen Geräten: Antworten, ICMPv6, Link-Local aus dem MGMT-VLAN. Bekommt ein Gerät die Rolle `router`, ersetzt dessen Zonen-Firewall den Block.

#### <a id="dr2.3"></a>DR2.3 · NAT je Zone

*2026-09-17 · alt D38*

**Entscheidung:** Kennzeichen am Policy-Ziel

**Verworfen:** Liste der Zonen mit NAT in `global.rsc` · am Uplink im Router-Hostfile

**Umsetzung:** Der Zonenname bleibt unverändert, das Ziel trägt das Kennzeichen: `*wan` = masquerade, `wan@<Adresse>` = `src-nat` auf eine feste Adresse (liegt bei VRRP als /32 auf `vrrp<VID>` des WAN-VLANs und wandert mit dem Master, sonst am WAN-Interface), `wan` = geroutet ohne NAT. Gilt auch für `mtupdate` und `allow:…`. Quelle der NAT-Regeln ist die Adressliste `cfm-z-<zone>` (Netze der Zone, bei `mgmt` samt WireGuard-Netz). **Bruch mit dem bisherigen Verhalten:** Bis DR2.3 wurde jeder Internet-Verkehr maskiert; bestehende Daten auf `*wan`/`*mtupdate` (und `"*,*wan"` statt `"*"`) umstellen, sonst fehlt NAT. `$cfmCheck` prüft Kennzeichen und Adresse.

#### <a id="dr2.4"></a>DR2.4 · Internet-Freigaben für einzelne Zonen

*2026-09-17 · alt D39*

**Entscheidung:** benannte Freigabelisten als Policy-Ziel

**Verworfen:** Listen je Gerätegruppe über feste Adressen · nur über einen Proxy

**Umsetzung:** `global.rsc` `allow`: Hostnamen (RouterOS löst sie selbst auf), IPs, Netze → Adressliste `cfm-allow-<name>`; Ziel `allow:<name>` erlaubt diese Adressen in jede Richtung (Internet oder z.B. ein Proxy in einer anderen Zone). Freigaben gelten je Zone; gerätespezifische Freigaben entstehen über kleinere Zonen (eigenes VLAN je Gerätegruppe). Zonen ohne `*` oder `wan` bekommen eine DNS-Umleitung (dstnat Port 53 an externe Ziele → Router), damit Geräte mit fest eingebautem DNS dieselben Antworten bekommen, die die Freigabelisten auflösen. Proxy bleibt als späterer Ausbau (Ziel `allow:` auf den Proxy). Freigaben je Client statt je Zone: Idee in TODO 20.

#### <a id="dr2.5"></a>DR2.5 · MNDP ohne Adresse still verwerfen

*2026-10-13 · alt D78*

**Frage:** Broadcasts an das Gerät selbst, die die minimale Firewall (DR2.2) loggt

**Entscheidung:** MNDP über Bridge-Ports ohne Adresse (Quelle `0.0.0.0`, UDP 5678) verwirft der input-Block `fwb` still, nach `local-input` und vor dem Log; ein Gerät mit eigener Adresse in einem Client-VLAN verwirft dort per `local-input` still (Site-Regel in der `post.rsc`) (Nutzer, am selben Tag revidiert)

**Verworfen:** VMs mit `stp="none"` ohne MNDP (zuerst gewählt, `7635c5e`: die VM fehlte dann in der Nachbarliste von Winbox) · VMs suchen nur über das MGMT-Interface · VM-Karten auf dem Host getaggt (Site, Umbau an der Manager-VM) · Broadcast/Multicast im input-Block ohne Log verwerfen · Log enger begrenzen

**Begründung:** Die Nachbarsuche läuft auf allen Bridge-Ports (DU1.1). Über einen Bridge-Port ohne eigene Adresse geht MNDP mit Quelle `0.0.0.0` an 255.255.255.255. An einem physischen Port landet es ungetaggt im Trunk-VLAN 1 und damit nirgends; hinter einer VM-Karte stellt die Bridge des Hosts es als Access-VLAN im ganzen VLAN zu, und jedes Gerät mit Adresse darin verwarf und loggte es alle 30 s. An der Quelle ließ es sich nicht ohne Verlust abstellen (Labor): `protocol` gilt für das ganze Gerät, die Liste `DISC` für alle drei Protokolle; eine output-Regel der IP-Firewall oder des Bridge-Filters auf der VM sieht die Pakete nicht (Zähler 0); ohne die Karte in `DISC` endet auch LLDP auf ihr, über das die VM den Host und dessen Interface meldet (Netzplan, z.B. `tap108i1`). Winbox findet Geräte nur per MNDP, das MNDP der MGMT-Adresse kommt weiter durch. Die Regel trifft genau diese Pakete (Gegenstück in `fw6`: MNDP aus anderen VLANs still); der Router-Block loggt ohnehin nicht. Labor: `e2e.sh` Schritt 14 stellt den Access-Port mit `pvid=10` an cm1:ether3 nach (Regel zählt, kein `cfm-drop`)

#### <a id="dr2.6"></a>DR2.6 · Admin-PCs außerhalb des MGMT-VLANs hinter cfm-Routern

*2026-10-17 · alt D83*

**Entscheidung:** Rolle `router`: Forward-Regel `cfm-mgmt` → Zone des MGMT-VLANs im Regelblock `fw`, ganz vorn (vor Fasttrack und `drop invalid`) (Nutzer)

**Verworfen:** Policy-Eintrag `lan → mgmt` (öffnete das MGMT-VLAN für das ganze LAN) · Regel je Standort in `local-forward` per `post.rsc` (dort als Übergang genutzt)

**Begründung:** `mgmtExtra` heißt damit auf Routern wie auf allen Geräten „Management-Zugriff“: Dienste (input) und geroutet bis ins MGMT-VLAN. Andere Zonen bleiben außen vor. Vor `drop invalid`, weil Geräte mit eigener Adresse im Netz des Admin-PCs (Backup-Router, ein noch selbst routender Core, ein AP mit Käfig-Adresse) direkt antworten: Der Master sieht nur eine Richtung und hielte die Folgepakete für invalid – Ping ging, ssh hing im Banner (erste Fassung hinter `drop invalid`, am Standort aufgefallen). Labor: `e2e-vrrp.sh` Schritt 5 (Admin-PC .20.10 in `mgmtExtra` erreicht r2 im MGMT-VLAN über den Master; TCP zu r2, der über seine LAN-Adresse antwortet, ohne invalid-Drop beim Master; LAN .20.1 nicht)

#### <a id="dr2.7"></a>DR2.7 · Bandbreitenlimit je VLAN

*2026-10-28 · alt D97*

**Optionen (gewählt fett):** Datenmodell: **`vlans.rsc` → `"limit"="50M/10M"` für das ganze Netz (Download/Upload aus Sicht der Clients), die Clients teilen es per PCQ gleich auf; optional `"limitClient"="10M/2M"` als Obergrenze je Client (mit oder ohne `limit`)** (Nutzer) · nur je Client (viele Gäste füllen zusammen die Leitung) · nur gesamt als FIFO (ein Client belegt alles); Fasttrack-Ausnahme: **je Netz des VLANs – vor der Fasttrack-Regel `accept` für `established,related` mit `src-address` bzw. `dst-address` = Netz** (Nutzer) · je Zone über `Z-<zone>` (nähme auch VLANs ohne Limit derselben Zone aus); Geltung: **aller gerouteter Verkehr des Netzes** (Nutzer, Queue nur mit `target`) · nur Richtung Internet (`dst` = WAN-Interface, bei WAN im LAN-VLAN und VRRP mehr Logik)

**Begründung:** Je VLAN eine Simple Queue `vlan<VID>` (`cfm:q:<VID>`, `target` = Netz, `max-limit` Upload/Download in der Schreibweise, die RouterOS zurückliest: größte Einheit, die glatt teilt, `1500k`), Queue-Typ `pcq-upload-default/pcq-download-default` (Rate 0 = gleiche Teile), mit `limitClient` eigene PCQ-Typen `cfm-pcq<VID>-down/-up` (`pcq-rate`, Klassifizierung `dst-address`/`src-address`). `/queue/type` hat kein `comment` (7.25: „bad parameter comment“) – neue Liste `cfmByName` in `lib.rsc`: In diesen Menüs sind der Name der Schlüssel und die Objekte „cfm-…“ die eigenen, Reconciler und Audit behandeln sie so. Aufräumen in der Reihenfolge von `cfmMenus` (Queue vor Typ): RouterOS löscht einen benutzten Typ ohne Fehler, die Queue zeigte dann `*7` (Labor). Bei VRRP auf jedem Router (nur der Master leitet weiter). Neue Simple Queues hängt `$cfmEnsure` hinten an, fremde Queues eines Standorts davor greifen zuerst. Eine schon per Fasttrack markierte Verbindung bleibt es bis zu ihrem Ende. `$cfmCheck`: Syntax (Fehler), Warnung ohne Router-Interface oder Subnetz. Labor 7.25 (drei CHRs: Client → Router → Server, `bandwidth-test` TCP, unter der 1-Mbit/s-Grenze der CHR-Lizenz): Limit 400k/200k → 371k/175k, je Client 100k/50k → 89k/37k; die Umgehung durch Fasttrack zeigt CHR nicht (Fast Path aus, `ipv4-fasttrack-packets` 0) – auf Hardware prüfen. `e2e.sh` Schritt 9 (Objekte, Ausnahme vor Fasttrack, idempotent, Abbau im Probelauf, Prüfung): 359, grün. Hardware (2026-10-28/29, CRS418 als Router und CAPsMAN, 7.25, Gast-VLAN `50M/10M`, je Client `20M/5M`): Speedtest eines Clients 19,8 Mbit/s Download, die Queue zählte über den Test ≈ 20M down/5M up und verwarf in beiden Richtungen, `pcq-queues=1/1`, keine Gast-Verbindung mit Fasttrack-Markierung. Gegenprobe ohne Ausnahme und CPU-Last unter Volllast offen

### <a id="dr3"></a>DR3 · Internet-Router im LAN

#### <a id="dr3.1"></a>DR3.1 · WAN-VLAN zugleich Client-Netz

*2026-10-18 · alt D86*

**Frage:** Internet-Router im LAN: Das WAN-VLAN der Router ist zugleich ein Client-Netz (Befund an einem Standort 2026-10-18 vor dem Umzug des LAN-DHCP auf die Router: Die Router-Firewall nahm DNS/DHCP/NTP nur über `in-interface-list=!WAN` an, `vlan<VID>` und `vrrp<VID>` des LANs stehen aber in `WAN` – DNS-Anfragen aus dem LAN an die VIP liefen ins Leere; mit `dhcp` und `dhcpGw` (DN1.2) hätten alle LAN-Clients die VIP als DNS bekommen)

**Entscheidung:** Ist das WAN ein cfm-VLAN (`wan.if` = `vlan<VID>`), nehmen die Router DNS, DHCP und NTP auch aus dessen Netz an (`in-interface-list=WAN` mit `src-address` = Netz des VLANs) (Nutzer)

**Verworfen:** DNS der LAN-Clients bleibt der Internet-Router (`dns` in `vlans.rsc`; dann keine Namen `<name>.<domain>` im LAN)

**Begründung:** Gilt auch für Einzelrouter mit WAN in einem cfm-VLAN. Aus dem Internet trifft die Regel nichts: Der Absender muss im LAN-Netz liegen, davor NATet der Internet-Router. DHCP lief in der Gegenprobe auch ohne Regel (der DHCP-Server von RouterOS bekommt die Anfragen an der Firewall vorbei); `67` steht trotzdem wie bei den übrigen Zonen in der Regel. Labor: `e2e-vrrp.sh` – VLAN 20 mit `dhcp`/`dhcpGw`/`lease` wie am Standort, DHCP-Client auf inet (macvlan `mv20` in eigener VRF, feste Lease `labpc` .20.42); bei jedem Master (r1, r2, cm1) Lease vom Master (Server .250+routerId, Gateway .1, DNS VIP .2) und DNS-Antwort der VIP auf eine Anfrage aus dem LAN. Gegenprobe ohne Fix: alle fünf DNS-Prüfungen schlagen fehl, DHCP geht

#### <a id="dr3.2"></a>DR3.2 · VIP als Gateway trotz Internet-Router im Netz

*2026-10-31 · alt D100*

**Anlass:** Befund an einem Standort: Ein Server mit der VIP als Gateway erreichte das Internet per Ping, aber nicht per TCP (Internet-Router im selben Netz, DN1.2/DR3.1; Antwort direkt, `drop invalid` am Master). Ziel des Nutzers: Der Internet-Router soll nicht länger Single Point of Failure für die internen Netze sein; langfristig ein Transfernetz (auch für einen zweiten Anschluss), bis dahin eine schlanke Übergangslösung.

**Frage:** VIP als Gateway, obwohl der Internet-Router im selben Netz steht

**Entscheidung:** Asymmetrisch: `vlans.rsc` → `"asymRouting"="internet"` am WAN-VLAN, Standard aus. Die Rolle `router` setzt eine `raw`-Regel `prerouting` `notrack` (herein über `WAN`, Quelle = Netz des VLANs, Ziel `!cfm-private`); der forward-Block nimmt `untracked` schon an (Nutzer, 2026-10-31; Name statt „asyncRouting“: asymmetrisch, nicht asynchron)

**Verworfen:** Masquerade auf die VIP für Hosts mit Gateway VIP (Internet-Router sähe nur noch eine Adresse, Portfreigaben gingen nicht, Abriss beim VRRP-Wechsel) · Split-Routing per DHCP-Option 121 (Android wertet sie nicht aus) · Transfernetz für den Internet-Router (sauber, aber Mesh-Repeater, WLAN und IP-Telefon am Internet-Router müssten mit – eigenes Wartungsfenster) · Clients per ICMP-Redirect auf den Internet-Router umleiten (nur je Ziel, erstes Paket immer über den Router, Hosts ignorieren Redirects oft; am Standort mit `send-redirects=yes` ging TCP trotzdem nicht)

**Begründung:** Ohne conntrack gibt es kein `invalid`; der Internet-Router sieht weiter die echten Adressen (Kindersicherung, Freigaben), ein Wechsel des VRRP-Masters reißt nichts ab, nur der Upload geht durch den Router. Auf die Zone beschränkt, die ins Internet darf, ist der Verlust der Firewall-Prüfung für diesen Verkehr gering; Verkehr zwischen VLANs bleibt verfolgt. Eigener Schalter, weil es nur für die Migration bestehender Netze Sinn hat (Nutzer). `in-interface-list=WAN`, weil Verkehr an die VIP über `vrrp<VID>` hereinkommt (DR3.1 trägt es ins WAN ein). NAT der Zone ins Internet ginge mit `notrack` verloren: Die Router setzen die Regel dann nicht und warnen; `$cfmCheck` warnt nur (Hostfiles können die policy überschreiben), Fehler bei einem anderen Wert als `internet`, Warnungen bei `l3=no`, `ntp=redirect` und `limit`. Neues Menü `/ip/firewall/raw` in `cfmMenus` (GC räumt die Regel nach dem Abschalten weg). Labor: `e2e-vrrp.sh` Schritte 5c (Ausgangslage verworfen, mit Schalter TCP über die VIP, kein invalid-Drop, Gast-NAT und LAN → IoT unverändert), 6–9 (TCP nach jedem Masterwechsel) und 11 (Abschalten), `e2e.sh` (Prüfung); RouterOS 7.25: `e2e-vrrp.sh` 137, `e2e.sh` 374, grün

### <a id="dr4"></a>DR4 · Fernzugang

#### <a id="dr4.1"></a>DR4.1 · WireGuard-Fernzugang für Admins

*2026-09-17 · alt D36*

**Status:** teilweise geändert durch DR4.2 (2026-10-17): Der private Schlüssel ist jetzt allen Routern gemeinsam und liegt im Vault.

**Optionen (gewählt fett):** Adressen: **eigenes Subnetz (`wireguard.rsc` → `net`)** · Adressen aus dem MGMT-Subnetz mit Proxy-ARP (erste Version, im Pilot beim ersten Verbindungsaufbau unzuverlässig); privater Schlüssel des Routers: **lokal erzeugt, bleibt auf dem Gerät** · im Vault (seit DR4.2: gemeinsamer Schlüssel aller Router im Vault)

**Umsetzung:** Nur mit Rolle `router` und nur, wenn `peers` nicht leer ist. Der Router bekommt Host `.1` im WireGuard-Subnetz; daraus entsteht die verbundene Route automatisch, ohne Proxy-ARP und ohne Route je Peer. Die Peers stehen in der Interface-Liste `Z-mgmt` (volle mgmt-Rechte beim Routing), das Subnetz zusätzlich in `cfm-mgmt` (Dienste des Routers) und bei allen Geräten in den erlaubten Adressen der IP-Dienste (`base`; die wirken unabhängig von der Firewall). Der `listenPort` ist aus allen Richtungen offen, die Sicherheit kommt aus den Schlüsseln. `$cfmCheck` prüft: `net` gesetzt, sobald es Peers gibt, keine Überschneidung mit `vlans.rsc`, Pubkey und eindeutige Adresse je Peer. Client unter Linux: `tools/wg-client-setup.sh` (NetworkManager). Der Rückweg zum Router direkt nach dem Verbindungsaufbau klappt seit dem Umbau (Hardware, 2026-09-24).

#### <a id="dr4.2"></a>DR4.2 · WireGuard mit mehreren Routern (VRRP)

*2026-10-17 · alt D84*

**Frage:** WireGuard-Fernzugang mit mehreren Routern (VRRP) (Befund beim Router-Umzug eines Standorts 2026-10-17: jeder Router erzeugte seinen eigenen Schlüssel, ein Peer konnte nur einen Router als Gegenstelle haben; die Backups hatten das WG-Netz als eigenes verbundenes Netz und schickten ihre Antworten in den eigenen Tunnel, ohne Peer – über einen Tunnel zum Master war z.B. der Manager als Backup nicht erreichbar)

**Entscheidung:** Gemeinsamer privater Schlüssel aller Router im Vault (`wg.admin`, Secret-Push), Endpoint = VIP des WAN-VLANs, `wg-admin` nur auf dessen Master an (on-master/on-backup wie DHCP), Backups routen das WG-Netz über die MGMT-VIP zum Master (`rt:wg`) (Nutzer)

**Verworfen:** WG nur auf einem festen Router (bei dessen Ausfall kein Fernzugang) · Admin-PC mit Karte im MGMT-VLAN statt Tunnel

**Begründung:** Der Manager übernimmt beim ersten Release mit Peers den Schlüssel eines Routers, der `wg-admin` schon hat (Einzelrouter mit bestehenden Clients: nichts ändert sich), sonst erzeugt er einen (Hilfs-Interface, gleich wieder gelöscht); der öffentliche Schlüssel steht in `meta/vault.dat` und im Manifest der Router (`wgpub`). Weicht `wg-admin` davon ab (neu angelegt, von Hand geändert), fordert die Rolle beim Apply einen Secret-Push an (sv=0, wie bei fehlenden WLAN-Passphrasen). Erzeugt wird nur beim echten Release, nicht im Probelauf. `$cfmSecret key=wg.admin` setzt einen eigenen Schlüssel samt `wgpub`. Ohne VRRP oder mit `wan.if` außerhalb eines VLANs bleibt `wg-admin` an und ohne `rt:wg` (wie bisher). Laborbefund (7.24.5): RouterOS beantwortet ein Paket an die VIP von seiner eigenen Adresse im WAN-VLAN; der Client übernahm sie als Endpoint (Roaming) und hing nach dem Wechsel des Masters am alten Router. Deshalb `dst-nat` VIP:`listenPort` → eigene Adresse: Die Antwort gehört dann zur Verbindung und geht von der VIP zurück, auch hinter einer Portfreigabe des Internet-Routers. Geräte ohne Rolle `router` mit eigenem Ausgang (Hostfile `gw`, z.B. ein NAT-Käfig direkt über den Internet-Router) schickten ihre Antworten an Peers zu diesem Gateway, das das WG-Netz nicht kennt (Befund am Standort): Sie bekommen bei vorhandenen Peers ebenfalls `rt:wg` über das MGMT-Gateway. Beim Update gilt: `$cfmRelease` läuft mit der Manager-Bibliothek, die der Manager zuletzt selbst angewendet hat – das erste Release bringt die neue mit, erst das zweite übernimmt bzw. erzeugt den Schlüssel, danach `$cfmSecretPush`. Nebenbei behoben: Der Secret-Push schaltete den CAPsMAN auch ohne Passphrase der Master-SSID im Vault ein, die Rolle beim nächsten Apply wieder aus (fiel auf, weil im VRRP-Labor erstmals ein Secret-Push lief). Labor: `e2e-vrrp.sh` Schritt 5b (vorhandener Schlüssel auf r1 übernommen, gleicher Schlüssel auf allen, Tunnel nur am Master, Client über die VIP erreicht Master, Backup und Manager, Endpoint bleibt die VIP, Selbstheilung nach geändertem Schlüssel; Switch sw1 mit eigenem Ausgang erreichbar, keine Antwort über den Internet-Router), Schritte 6/7 (Tunnel nach Umschalten und Preemption)

## <a id="dn"></a>DN · Netzdienste

### <a id="dn1"></a>DN1 · DHCP und Namen

#### <a id="dn1.1"></a>DN1.1 · Feste DHCP-Leases und DNS-Namen aus zentralen Daten

*2026-10-03 · alt D62*

**Entscheidung:** Neue Datendatei `leases.rsc` je VLAN (`"<VID>"={"<name>"={"mac"=…;"ip"=<Host-Teil>}}`); die Rolle `router` legt die Leases am DHCP-Server des VLANs an und führt statische DNS-Einträge `<name>.<domain>` für Leases und alle aufgenommenen Geräte (MGMT-Adresse, Liste im Manifest der Router). Standard-Domain `internal`

**Verworfen:** Leases in `vlans.rsc` · flache Liste mit voller IP · nur Lease-Namen bzw. keine DNS-Namen · Domain `home.arpa` (RFC 8375) oder `.local`

**Begründung:** Je VLAN mit Host-Teil wie bei `gw`/`dhcp`. `.local` gehört mDNS (RFC 6762) und stört Bonjour/Avahi; `internal` hat ICANN 2024 für private Netze reserviert (Nutzerwahl). `leases.rsc` ist im Manifest optional (ältere Releases bleiben für Ringe gültig), der Agent leert `$cfmLeases` vor dem Import. Die MAC schreibt die Rolle groß (`$cfmMacUp`), sonst erschiene sie bei jedem Apply als Änderung. `/ip/dhcp-server/lease`, `/ip/firewall/mangle` und `/routing/table` stehen jetzt in `cfmMenus`, damit verwaiste Objekte auch verschwinden, wenn das Menü im Lauf gar nicht mehr vorkommt.

#### <a id="dn1.2"></a>DN1.2 · DHCP der cfm-Router neben einem fremden Internet-Router

*2026-10-17 · alt D82*

**Frage:** DHCP der cfm-Router in einem Netz, dessen Internet-Router ein anderes Gerät bleibt (Standort mit Fritz!Box: Namen und IPs des LANs für `$cfmFind`)

**Entscheidung:** `vlans.rsc` → `dhcpGw` (Host-Anteil): Gateway, das die DHCP-Clients bekommen; DNS bleibt Standard der Router (Gateway), `gw` bleibt die Adresse der Router für die übrigen VLANs (Nutzer)

**Verworfen:** Clients bekommen die VRRP-VIP als Gateway (Internet dann Router → Internet-Router im selben VLAN: Haarnadel, Rückweg direkt vom Internet-Router zum Client, die Router sehen nur eine Richtung, ICMP-Redirects) · Reverse-DNS bzw. TR-064-Abfrage der Fritz!Box statt eigenem DHCP

**Begründung:** Der Internet-Router bleibt Default-Gateway der Clients, die anderen VLANs erreichen sie über dessen statische Routen zur VIP (wie bisher). DNS über die Router löst die Namen aus `leases.rsc` als `<name>.<domain>` auf und fragt sonst weiter. `$cfmCheck`: dhcpGw nur mit `dhcp` (sonst Warnung), nicht im DHCP-Bereich, keine feste Lease auf dieser Adresse, Hinweis wenn gleich `gw`. `$cfmShow` nennt das Gateway der Clients. `$cfmFind` nimmt die festen Adressen aus `leases.rsc` als IP dazu. Labor: `e2e.sh` Schritt 9 (dhcpGw 5 in VLAN 30: Gateway .5, DNS .1; Prüfung im Pool bzw. ohne dhcp)

### <a id="dn2"></a>DN2 · Zeit

#### <a id="dn2.1"></a>DN2.1 · Zeitquelle der Router

*2026-10-20 · alt D88*

**Frage:** Woher die Router ihre eigene Zeit holen (TODO 59)

**Entscheidung:** `ntp` im Hostfile-Eintrag `wan` (Text oder Liste), sonst der DNS-Server aus `wan`, sonst `0.pool.ntp.org,1.pool.ntp.org`; mit `wan.dhcp` zusätzlich der NTP-Server der DHCP-Antwort (`use-peer-ntp`) (Nutzer)

**Verworfen:** Schlüssel in `global.rsc` für alle Router · nur dokumentieren

**Begründung:** Bisher fest der DNS-Server aus `wan` bzw. `0/1.de.pool.ntp.org`: Das setzte NTP beim DNS-Server voraus (ein öffentlicher DNS wie 1.1.1.1 hat keins) und band den Rückfall an Deutschland. Der Server aus DHCP erscheint als dynamischer Eintrag unter `/system/ntp/client/servers`, `get servers` liefert nur die festen – der Abgleich bleibt idempotent (Labor 7.24.5). Labor: `e2e.sh` Schritt 9 (WAN per DHCP), `e2e-vrrp.sh` Schritt 4 (Liste bzw. `wan.dns`).

#### <a id="dn2.2"></a>DN2.2 · NTP-Umleitung je VLAN

*2026-10-23 · alt D93*

**Entscheidung:** `vlans.rsc` → `"ntp"="redirect"`: Die Rolle router legt je VLAN eine dstnat-Regel an (`udp/123`, Quellnetz des VLANs, jedes Ziel außer dem Router selbst `dst-address-type=!local` → `redirect` auf Port 123); der NTP-Server der Router läuft schon (TODO 59), `input` nimmt udp/123 aus allen Nicht-WAN-Zonen an (Nutzer, 2026-10-23)

**Verworfen:** automatisch je Zone wie die DNS-Umleitung (DR2.4) · Regel in `post.rsc` je Router · nur externe Ziele (`!cfm-private`) wie bei DNS

**Begründung:** Eigener Schalter statt automatisch: Nicht jedes VLAN ohne Internet soll seine NTP-Ziele verlieren. Auch private Ziele, weil Geräte oft den Internet-Router im LAN als NTP-Server fest eingetragen haben; ein anderer NTP-Server im Haus ist aus dem VLAN dann nicht mehr erreichbar. Quellnetz statt `in-interface`, weil Verkehr an die VIP über `vrrp<VID>` hereinkommt (Laborprobe des Router-Umzugs, 2026-10-01). Die Antwort kommt von der Adresse, an die das Gerät gefragt hat (Verbindungsverfolgung). `$cfmCheck`: nur `redirect`, Hinweis bei `l3=no`. `$cfmShow` nennt es je VLAN. Labor: `e2e.sh` Schritt 9 (Regel nur für VLAN 30, idempotent, Prüfung).

### <a id="dn3"></a>DN3 · DNS-Resolver

#### <a id="dn3.1"></a>DN3.1 · DNS der Router: Upstream, Adblock, Ausnahmen, Abfrage-Log

*2026-10-31 · alt D101*

**Anlass:** Ausgangslage an einem Standort: Clients fragen die VIP, die Router fragen den Internet-Router, der wiederum zwei Resolver-Container (Cache, Adblock) – der Internet-Router steckt in jeder externen Abfrage. Ziel des Nutzers: kein Single Point of Failure, weniger Komponenten (Wartung, Angriffsfläche), Adblock mit Standardlisten und eigenen Ausnahmen, ein Abfrage-Log je Client zum Debuggen ohne dauerhafte Speicherung, später Namen über Standorte hinweg.

**Optionen (gewählt fett):** **Eigene Datei `dns.rsc` (`cfmDns`, optional, nur Rolle `router`): `servers` (Upstream statt `wan.dns`), `cache` (`cache-size`), `adlists` (`/ip/dns/adlist`, `ssl-verify` beim Standard `yes`), `allow` (statische `FWD`-Einträge mit `match-subdomain` an den Forwarder `cfm-upstream` mit allen Upstreams), `forward` (`FWD` je Domain an Adresse oder Liste), `log` mit `memory` (RAM-Puffer `cfmdns`) und `syslog` (zusätzlich an `cfmremote`), Topic `dns,!packet`. Ohne Einträge das bisherige Verhalten** (Nutzer, 2026-10-31: eigene Datei wegen langer Listen; beide Log-Wege als Option) · Schlüssel `resolver` in `global.rsc` · Ausnahmen in eigener Datei; Upstream: **Quad9, dahinter DNS4EU unfiltered** (Nutzer: Privacy-Fokus, kein Cloudflare) · Resolver-Container im Haus behalten (DNSSEC-Prüfung, Log und Regeln je Client, Oberfläche) · DoH (später möglich); standortübergreifend: **Weiterleitung je Domain** (Nutzer) · über den Internet-Router; Namensschema der Standorte: später

**Begründung:** RouterOS 7.25 kann alles Nötige (Labor): Adlisten im hosts-Format laden über HTTPS mit dem eingebauten Zertifikatsspeicher (`/certificate/settings builtin-trust-store`), gesperrte Namen → `0.0.0.0`; ein statischer `FWD`-Eintrag nimmt eine Domain samt Subdomains aus („To exempt certain domains from Adlist, you need to create a static DNS FWD entry“, MikroTik-Doku); `FWD` an einen bestimmten Server greift für Domain und Subdomains (Gegenprobe mit totem Server scheitert, andere Domains unberührt). Das Topic `dns` ohne `packet` nennt den Client (`query from <IP>: #n <Name> <Typ>`, `done query: #n … <Antwort>`), mit `packet` etwa zehnmal so lang. Die Adlisten liegen im DNS-Cache, etwa 70 Byte je Name (Hardware: 79 315 Namen ≈ 5,7 MB) – auch kleine Router (CRS310, 256 MB) haben Platz. Ausnahmen an einen Forwarder mit allen Upstreams statt an eine Adresse: Ein Ausfall des ersten Upstreams träfe sonst nur die Ausnahmen. `ssl-verify` setzt cfm nicht: RouterOS meldet nur `no` zurück, `yes` (Standard) fehlt im Readback – gesetzt erschiene es bei jedem Lauf als Änderung (Labor). Log-Regeln ohne `comment` wie in `base` (einige Builds lehnen es ab), vor der Aktion entfernt. Alle Objekte tragen `comment` und werden per GC entfernt (`/ip/dns/forwarders`, `/ip/dns/adlist` in `cfmMenus` vor `/ip/dns/static`, die GC läuft rückwärts). `cache` wird beim Wegfall nicht zurückgesetzt. Nicht dabei: DNSSEC-Prüfung (Upstream prüft), Regeln und Statistik je Client/Domain; Pflege der Ausnahmen aus Home Assistant später als eigener Schritt (eine von cfm nicht verwaltete Liste, wie der SSID-Schalter DW4.2). `$cfmCheck` prüft Adressen, Größe, URL, Domainnamen, Log-Schalter und warnt bei unbekannten Schlüsseln. Labor: `e2e.sh` Schritt 14l

#### <a id="dn3.2"></a>DN3.2 · DNS-Selbstbedienung

*2026-10-31 · alt D102*

**Entscheidung:** Ohne eigenen Dienst: Lesezeichen cfm-DNS (`web/cfm-dns.js`, DT3.2, Rolle `router`) in WebFig des Gateways, Daten per REST aus dem RAM-Puffer `cfmdns`; `dns.rsc` `self` = `zones` (WebFig/REST nur aus diesen Zonen: Dienst `www` – ohne Eintrag in `services` Port 80 –, Firewall `input` je Zone), `deny`, `hours` (Standard 2), `user` (Standard `dns`); gemeinsamer User der Gruppe `cfm-dns` (`read,api,rest-api`, Passwort aus dem Vault per Secret-Push), Ansicht nur der eigenen IP (Admin mit Schreibrecht: alle); Anfrage per Log-Eintrag `cfm-dnsreq: <Domain> <IP>` über `/execute` + Skript `cfm-dnsreq` (`dont-require-permissions`), das sofort für `hours` freischaltet (`FWD` an `cfm-upstream`, Kommentar `dnsui:tmp:<Ablauf> <IP>`), außer `deny`; Meldung `ev=dnsreq` an `notify.url`; Scheduler (1 min) räumt Abgelaufenes weg; Admin macht im Lesezeichen dauerhaft (`dnsui:perm`), jeder Apply warnt bis zur Übernahme nach `allow` (Nutzer, 2026-10-31)

**Verworfen:** eigener Dienst im Container (Syslog-Empfang oder Graylog-API, Freigabe per Webhook/HA) · Freigabe nur durch den Admin · je Person ein User · Begrenzung je Stunde · Blacklist als Adliste oder Regex

**Begründung:** Nutzer: lieber kein zusätzlicher Dienst, Muster wie der cfm-Editor. Labor 7.25: `GET /rest/log?buffer=cfmdns` liefert den Puffer, aber immer ganz (`.query` mit `.id>` oder `time>` filtert nicht; 20 000 Zeilen ≈ 2 s auf einem CHR – Standard alle 30 s, nur bei sichtbarem Tab); `/user/active` nennt Adresse und `via=rest-api` der laufenden Anfrage; REST braucht neben `rest-api` auch `api` (nur `read,rest-api,web` → 500), die Gruppe `read` hätte `password`; ein solcher User darf per REST ein Skript mit `dont-require-permissions=yes` starten, das schreibt; `:log info` per `/execute` geht, `:global` aus `/execute` kommt im Skript nicht an (Variablen gelten je User) – deshalb Übergabe und Erledigt-Vermerk (`req=<id>`) über das Log, nur Puffer `memory` (eine Zeile in zwei Puffern hätte zwei `.id`s). Ein neuer `FWD`-Eintrag wirkt sofort gegen die Adliste. Gesperrt erkennt das Lesezeichen an `done query: #n <Name>` mit genau dem gefragten Namen bei A/AAAA (PTR und NS stehen in derselben Form mit ihrer Antwort; Hardware). Der Forwarder `cfm-upstream` bleibt, solange `dnsui:`-Einträge auf ihn zeigen. Grenzen: Freischaltung gilt für alle Clients des Routers und nur auf diesem Router (bei VRRP-Wechsel ist eine befristete weg); die Sichtschranke wirkt nur im Browser; Browser mit DoH umgehen den Router; Anmeldung über `http` unverschlüsselt im VLAN (`www-ssl` später). Labor: `e2e.sh` Schritt 14l. Hardware 2026-10-31 (hAP ax³ als VRRP-Master, 7.25): Freischaltung aus dem Client-VLAN nach 3 s wirksam, dauerhaft machen und löschen als Admin ok, 20 000 Log-Zeilen in 2,3 s gelesen (`:time`, ohne REST). Das Passwort verteilt erst der nächste Manager-Tick nach der nächsten Statusmeldung, sofort per `$cfmSecretPush`. TODO 69

## <a id="dw"></a>DW · WLAN

### <a id="dw1"></a>DW1 · CAPsMAN, Datapath, Fallback

*DW1.1 · CAPsMAN auf dem Config-Manager mit Standby – abgelöst durch DW1.5 und DW1.6, siehe [Archiv](#dw1.1).*

#### <a id="dw1.2"></a>DW1.2 · Datapath lokal am CAP mit VLAN-Tag

*2026-09-11 · alt D18*

**Entscheidung:** lokal am CAP + VLAN-Tag

**Verworfen:** CAPsMAN-Forwarding

**Umsetzung:** `datapath vlan-id` je SSID. AP-Uplinks nutzen das Profil `trunk-ap`.

#### <a id="dw1.3"></a>DW1.3 · Bridge der WLAN-Radios am CAP

*2026-09-22 · technisch, nicht abgefragt · alt D41*

**Entscheidung:** lokaler Datapath `cfm-cap` mit `bridge=bridge`, Radios und `slaves-datapath` zeigen darauf (Weg der MikroTik-Doku)

**Verworfen:** `datapath.bridge` direkt an jedem Radio (ohne Wirkung auf virtuelle APs) · statische Bridge-Ports mit PVID (verlöre die VLANs je SSID vom CAPsMAN)

**Umsetzung:** Der CAPsMAN überträgt aus seinem Datapath `vlan-id` und `client-isolation`, aber nie `bridge` – die Bridge ist ein Interface des CAP. Ohne lokalen Datapath wurde kein Radio Bridge-Port: Clients authentifizierten sich, bekamen aber kein DHCP. Die Rolle `ap` legt `cfm-cap` ohne `vlan-id` an, das VLAN kommt weiter je SSID vom CAPsMAN; das Radio wird dynamischer Bridge-Port mit dieser PVID. Das `bridge` im Datapath des Managers gilt nur für dessen eigene Radios. `cap` ist als SSID-Schlüssel reserviert (`$cfmCheck`). Gilt für CAPs mit `wifi-qcom`; `wifi-qcom-ac` übernimmt laut Doku kein `vlan-id` vom CAPsMAN ([TODO.md](TODO.md) Punkt 23; die Rolle `ap` und `$cfmCheck` warnen seit 2026-10-04).

#### <a id="dw1.4"></a>DW1.4 · WLAN-Verkehr über das MLD-Interface (Wi-Fi 7)

*2026-09-23 · technisch, nicht abgefragt · alt D44*

**Entscheidung:** lokaler Datapath `cfm-mld` mit `bridge` und dem VLAN der `master`-SSID, per `/interface/wifi/cap mld-datapath`

**Verworfen:** MLO im CAPsMAN abschalten · `mld-static=yes` und eigene Bridge-Ports

**Umsetzung:** Hardware-Befund (hAP be³, `wifi-qcom-be`): Der CAPsMAN fasst die Radios eines Wi-Fi-7-CAP mit gleicher SSID zu einem MLD zusammen; der Verkehr läuft über das MLD, nicht über die Radios. Wie bei DW1.3 überträgt der CAPsMAN dafür weder Bridge noch `vlan-id`: Ohne `mld-datapath` war das MLD kein Bridge-Port (Clients ohne DHCP, Abbruch nach ~20 s), mit dem Datapath `cfm-cap` bekam es PVID 1. Ein `mld-datapath` gilt für alle MLDs des CAP – weitere SSIDs mit MLO bräuchten eine andere Lösung; seit DW2.3 ist MLO standardmäßig aus. Auf Geräten ohne Wi-Fi 7 ist die Einstellung wirkungslos (sie melden sich einmal neu am CAPsMAN an).

#### <a id="dw1.5"></a>DW1.5 · Ort des CAPsMAN: eigene Rolle `capsman`

*2026-09-27 · alt D45*

**Löst ab:** DW1.1 (zusammen mit DW1.6): Der CAPsMAN zieht auf ein Gerät ohne VM- und Host-Abhängigkeit, statt eines passiven Standbys senden die APs bei einem Ausfall lokal weiter.

**Frage:** Wo läuft der CAPsMAN?

**Entscheidung:** Eigene Rolle `capsman` auf genau einem Gerät (kein Standby); die APs erfahren Name und MGMT-IP über das Manifest-Feld `cm`; ohne Gerät mit dieser Rolle bleibt übergangsweise der Primary-Manager CAPsMAN

**Verworfen:** Rolle `manager` rendert weiter, Ort per Schalter in `wifi.rsc` · passiver Standby auf dem Backup-Manager mit Netwatch-Übernahme (bisher)

**Begründung:** Hardware-Befund: Der Manager lief als VM. Ein Link-Abriss der Netzwerkkarte des Hosts (14 s, Realtek mit `r8169`) trennte alle CAPs rund 2 min vom CAPsMAN; ohne CAPsMAN schalten CAPs ihre Radios ab, die SSID war komplett weg. Der CAPsMAN gehört deshalb auf ein Gerät ohne VM- und Host-Abhängigkeit, der Config-Manager darf in der VM bleiben. Der passive Standby hätte erst nach ~3 min übernommen und eine zweite CA ins Netz gebracht (ein CAP vertraut nur der CA, bei der er sein Zertifikat angefordert hat, TODO 26) – er entfällt zugunsten des lokalen Fallbacks (DW1.6); bei einem längeren Ausfall wird die Rolle verschoben (`$cfmEnroll … role=` bzw. Inventar). Folgen: Die Rolle `ap` setzt `caps-man-addresses`/`-names` aus `cm` und erneuert die CAPsMAN-Zertifikate, wenn sich `cm` seit dem letzten Apply geändert hat (gemerkt im Kommentar des Datapaths `cfm-cap`) oder der CAP an einem CAPsMAN außerhalb von `cm` hängt; `base` schaltet auf allen anderen Geräten den CAPsMAN-Dienst ab. Ein neuer CAPsMAN bleibt aus, bis der Secret-Push die PSK der `master`-SSID gesetzt hat (sonst verteilte er SSIDs, an denen sich niemand anmelden kann); der Push schaltet ihn danach ein, bis dahin senden die APs im Fallback. Die CAPsMAN-Logik steckt in der Gerätebibliothek (`$cfmCapsmanOn`, seit DG4.3 in `lib/lib-wifi.rsc`), weil ein Manager mit älterem Stand noch Manifeste ohne `cm` baut: Ein Gerät entscheidet selbst (`$cfmIsCapsman`), fehlt `cm`, gilt die alte Regel „Rolle `manager` = CAPsMAN“. `$cfmCheck` warnt ohne Rolle `capsman` und lehnt sie mehrfach ab.

#### <a id="dw1.6"></a>DW1.6 · Lokaler Fallback der APs

*2026-09-27 · alt D46*

**Frage:** Verhalten der APs, wenn der CAPsMAN weg ist

**Entscheidung:** Lokaler Fallback: Jedes Radio trägt eine lokale Kopie der `master`-SSID (`configuration.manager=capsman-or-local`, Master-Konfiguration `cfm-l<Band>`, Kanal = Pin aus `radios` oder Pool; Profile, PPSK und PSK wie beim CAPsMAN)

**Verworfen:** nur ein Standby-CAPsMAN · nur die Ursache des Abrisses beheben

**Begründung:** Hardware-Test (cAP ax, 7.24.4): Abriss per Bridge-Filter auf die MAC des CAPsMAN; nach 6 s „no connection to CAPsMAN, managed locally“, nach 8–9 s sendet der AP mit der lokalen Kopie weiter; Rückkehr ~20 s nach dem Ende, danach ~10 s Neuprovisionierung. Die MikroTik-Doku beschreibt `capsman-or-local` anders („wenn `/interface/wifi/cap` nicht aktiv ist“), verlässlich ist hier nur der Test. Im Fallback ruht FT zwischen den APs (jeder AP ist allein). Datapath des Radios = Datapath der `master`-SSID (Bridge + VLAN): dieselbe `vlan-id` schickt auch der CAPsMAN, sie gilt damit in beiden Betriebsarten. Radios ohne Band in `wifi.rsc` (6 GHz) bleiben reine CAPs. Wi-Fi 7 (hAP be³, 7.25beta5): Ab Werk hängen die Radios am statischen, abgeschalteten MLD `mld1`; im Fallback meldeten sie „mld-interface not enabled“ und blieben aus. Die Rolle löst sie davon (`mld-interface` leer, bei jedem Apply, sobald das Gerät ein statisches MLD hat) – lokal senden sie dann nach ~4–7 s als getrennte APs ohne MLO; im CAPsMAN-Betrieb baut der CAPsMAN sein MLD weiter dynamisch auf (geprüft). Fehlt die PSK in einem neu angelegten Profil, fordert die Rolle einen Secret-Push an (`sv=0` am Geräteschlüssel, der Agent meldet es gleich nach dem Apply). Weitere SSIDs im Fallback: DW1.8 (vorbereitet, standardmäßig aus). Offen bleibt der Client-Test im Fallback ([TODO.md](TODO.md) Punkt 40a).

#### <a id="dw1.7"></a>DW1.7 · Eigene Radios des CAPsMAN-Geräts

*2026-10-01 · alt D53*

**Entscheidung:** Über den eigenen CAPsMAN provisionieren (`/interface/wifi/radio/provision [find where local]`), Schalter `capsmanRadios="yes"` im Hostfile des CAPsMAN, Standard aus. Neu provisioniert wird nur, wenn sich WLAN-Daten oder Provisioning-Regeln geändert haben (Signatur in `<cfm>/wifi-local.txt`); Schalter aus: cfm-Regeln kurz abschalten, neu provisionieren (Radios unkonfiguriert), Regeln wieder an

**Verworfen:** lokale Profile per Rolle (Master-SSID + virtuelle APs direkt am Radio)

**Begründung:** Laut MikroTik-Doku kann ein CAPsMAN seine eigenen Interfaces nicht mit `configuration.manager=capsman` verwalten; dokumentiert sind „dieselben Profile von Hand setzen“ und „über `/interface/wifi/radio` provisionieren“. Der zweite Weg ergibt dieselben Regeln, Kanal-Pins, Namen und virtuellen APs wie bei den CAPs und braucht wenig Code; FT im selben CAPsMAN-Verbund ist so am wahrscheinlichsten. Der zentrale Datapath trägt `bridge=bridge` schon (die CAPs ignorieren ihn, DW1.3). Auf Hardware seit 2026-10-03 an (hAP be³, drei Radios, Interface-Namen `<Name>-<Band>g` wie bei den CAPs, Scan darüber, TODO 46). Client-Test und FT zu den CAPs bestanden (an einem Standort, 2026-10-22, CRS418 mit zwei eingebauten Radios): Bridge-Port `cm1-5g` mit PVID 200, Bridge-Host-Tabelle lernt die Client-MAC mit VID 200, DHCP-Lease unverändert über den Server des VLANs – derselbe Datapath wie bei den CAPs. Roaming per Log beidseitig bestätigt (`cm1-5g → ap1-5g`, `ap1-5g → cm1-5g`, je `ft-wpa3-psk`). *Nachtrag 2026-10-22:* Ein Neustart des CAPsMAN-Geräts selbst provisioniert seine eigenen Radios automatisch neu, ohne den cfm-Agent – RouterOS tut das von sich aus (`wireless,info provision local radio …` im Log, Sekunden nach dem Boot, vor der ersten SSH-Verbindung des Agents); die Signaturdatei `wifi-local.txt` bleibt dabei unverändert, der Apply war nicht beteiligt. Beim Neustart verhalten sich die eigenen Radios also wie echte CAPs (automatische Wiederherstellung ohne Zutun des Frameworks); der verbleibende Unterschied ist der fehlende laufende CAPsMAN-Kontrollkanal (kein `operated by CAP` in `/interface/wifi/print`) – eine **Konfigurationsänderung** provisioniert die eigenen Radios nur über den nächsten cfm-Apply neu (Signaturvergleich), nicht über einen Push vom CAPsMAN wie bei einem CAP.

##### <a id="dw1.7.1"></a>DW1.7.1 · Wi-Fi-7-CAPsMAN: eigene Radios von `mld1` lösen

*2026-10-03 · technisch, nicht abgefragt*

Ab Werk hängen die Radios des hAP be³ am statischen, abgeschalteten MLD `mld1`; ohne MLO blieben sie nach dem Provisionieren aus. Wie die Rolle `ap` (DW1.6) löst `$cfmCapsmanOn` sie davon, bevor sie die eigenen Radios provisioniert.

#### <a id="dw1.8"></a>DW1.8 · Gast/IoT im lokalen Fallback

*2026-10-01 · alt D54*

**Entscheidung:** `fallback="yes"` an einer weiteren SSID in `wifi.rsc` schaltet auf den APs `slaves-static=yes` ein; die Rolle `ap` hängt den statischen virtuellen APs, die der CAPsMAN angelegt hat, eine lokale Kopie ihrer SSID an (`capsman-or-local`, Konfiguration `cfm-<SSID>` bzw. `cfm-<SSID>-<Band>g`, Datapath der SSID mit Bridge + VLAN). Die SSID eines virtuellen AP liest sie aus seiner Konfiguration bzw. dem Monitor

**Verworfen:** eigene statische virtuelle APs, die nur im Fallback laufen (Umschalten per Netwatch)

**Begründung:** Wie bei der Master-SSID (DW1.6), wenig Code. Ob RouterOS statische virtuelle APs im Fallback weitersenden lässt, zeigt nur der Test vor Ort. Bei ausgeschaltetem Schalter bleiben schon angelegte statische virtuelle APs stehen (der CAPsMAN legt sie beim Verbinden ohnehin neu an).

#### <a id="dw1.9"></a>DW1.9 · `slaves-static` nur bei Bedarf setzen

*2026-10-04 · technisch, nicht abgefragt*

`slaves-static` setzt die Rolle `ap` nur noch, wenn ein `fallback` es verlangt (DW1.8) oder der Wert schon an ist (TODO 40): Jedes Setzen unter `/interface/wifi/cap` trennt den CAP kurz vom CAPsMAN.

#### <a id="dw1.10"></a>DW1.10 · Warnung bei `wifi-qcom-ac`

*2026-10-04 · technisch, nicht abgefragt*

Die Rolle `ap` und `$cfmCheck` warnen bei CAPs mit `wifi-qcom-ac`: Das Paket übernimmt laut Doku kein `vlan-id` vom CAPsMAN (TODO 23, DW1.3).

#### <a id="dw1.11"></a>DW1.11 · Neue Master-SSID: Secret-Push nachfassen

*2026-10-29 · alt D98*

**Frage:** Neue Master-SSID: CAPsMAN bis zum Secret-Push aus (Befund 2026-10-28: drei neue SSIDs, Passphrasen vorher im Vault; erst der Apply legt die Profile an, `$cfmPskMissing` schaltet den CAPsMAN aus und meldet SV 0, der Push kam erst mit dem nächsten Manager-Tick – bis 10 min ohne WLAN; danach fehlten den eigenen Radios die übrigen SSIDs bis zum nächsten Apply)

**Entscheidung:** Nachfassen nach dem Push: `$cfmPush` trägt angestoßene CAPsMAN-Geräte in `meta/follow.dat` ein, der Scheduler `cfm-mgr-follow` holt alle 30 s ihren Status ab (höchstens 10 min); meldet einer einen Lauf seit dem Push mit veraltetem SV, folgt der Secret-Push sofort. Schaltet der Push den CAPsMAN von aus auf an und hat er eigene Radios, stößt er dort einen erzwungenen Apply an (Nutzer)

**Verworfen:** Profile vorab anlegen: der Secret-Push legt fehlende Security-Profile samt Passphrase vor dem Anstoßen an (kein Ausfall, aber die Profile je Band müsste der Manager selbst herleiten) · beides

**Begründung:** Der Ausfall schrumpft auf die Dauer des Applys plus höchstens 30 s. Nur CAPsMAN-Geräte: Nur dort führt eine fehlende Passphrase zum Ausfall (die APs brauchen sie nur für den lokalen Fallback), und je Gerät kostet das Abholen gut 1 s. `seen` im Status (Start des Laufs, der ihn schrieb) muss nach dem Push liegen – sonst zählte ein alter Status; bei falsch gehender Uhr des Geräts übernimmt nach 10 min wieder der allgemeine Tick. Der Scheduler läuft nicht, während der allgemeine Tick arbeitet (`cfmTickBusy`), und entfernt sich, sobald nichts mehr offen ist (`cfm-sys:follow`, kein GC). Der erzwungene Apply startet erst nach dem neuen SV im Gerät, sonst meldete er noch den alten. Labor: `e2e.sh` Schritt 14 (neues 6-GHz-Profil ohne Passphrase, der Tick per `cfmSpTry` gesperrt); die eigenen Radios gibt es im CHR nicht

### <a id="dw2"></a>DW2 · Sicherheit und Clients

#### <a id="dw2.1"></a>DW2.1 · WPA2/WPA3 mit FT und 802.11k/v

*2026-09-11 · alt D19*

**Thema:** WLAN-Sicherheit

**Entscheidung:** WPA2/WPA3 + FT + k/v

**Verworfen:** WPA3-only · WPA2-only

**Umsetzung:** `wpa2-psk,wpa3-psk`, `ft=yes ft-over-ds=yes`, Steering `rrm=yes wnm=yes`. IoT-Override: WPA2, FT aus.

#### <a id="dw2.2"></a>DW2.2 · WLAN-Ausbau: PPSK, Kanalwahl, vorerst kein Enterprise

*2026-09-13 · alt D32*

**Optionen (gewählt fett):** Enterprise: externer RADIUS · User Manager auf dem Manager · **vorerst kein Enterprise**; PPSK: **Multi-Passphrase-Gruppen** · Access-List je MAC; Kanäle: **RouterOS-Auswahl + Bericht** · zentrale Planung in cfm · nur RouterOS-Auswahl

**Umsetzung:** `wifi.rsc` → `ppsk`: je SSID Einträge mit `vlan` (optional `isolation`, `expires`). Die Rolle `manager` legt `/interface/wifi/security/multi-passphrase`-Einträge (Gruppe = Security-Profil) mit Zufallswert an, die echte Passphrase kommt per Secret-Push aus dem Vault (`ppsk.<ssid>.<name>`) und steht nie in Daten, Log oder Probelauf. `$cfmCheck` verlangt WPA2-PSK (RouterOS: kein Multi-Passphrase mit WPA3) und warnt, wenn das VLAN nicht auf den AP-Uplinks (`trunk-ap`) liegt. Kanäle: `reselect` (nächtliche Neuwahl) und je Band `skipDfs`; APs melden ihre Kanäle, `$cfmChannels` warnt bei gleichem Kanal an einem Switch (Näherung für „benachbart“). Kanalplan per Scan: DW3.2/DW3.3; andere Funknetze im 2,4-GHz-Band: DW3.5. Enterprise steht in [TODO.md](TODO.md) Punkt 16.

#### <a id="dw2.3"></a>DW2.3 · Wi-Fi 7 (MLO) und 6 GHz

*2026-09-27 · alt D48*

**Entscheidung:** MLO standardmäßig aus (`mlo` in `wifi.rsc` → `multi-link-mode` jeder Provisioning-Regel, nur gesetzt, wenn RouterOS den Parameter kennt); 6 GHz mit derselben SSID, Security je Band im Kanal-Eintrag (`sec`/`ft`/`ftOverDs`/`pmf`, eigenes Profil `cfm-<SSID>-<Band>g`, gleiche Passphrase per Secret-Push); `$cfmCheck` verlangt auf 6 GHz WPA3 mit PMF `required`

**Verworfen:** MLO an und FT aus · MLO nur in einer eigenen Wi-Fi-7-SSID · eigene SSID für 6 GHz · 6 GHz aus

**Begründung:** Hardware-Befund (hAP be³, RouterOS 7.24.4/7.25beta5): Als MLD bietet der AP kein FT an (RouterOS: „MLO does not support Fast Transition“). Ein Handy im FT-Verbund der übrigen APs meldete sich einen Tag lang nie am be³ an, auch direkt daneben; ein zweites Gerät flog nach 9 s wieder raus. Dazu gibt es nur ein `mld-datapath` je CAP (VLAN der `master`-SSID): Weitere SSIDs wie Gast/IoT landeten per MLO dort, also im falschen VLAN. Ohne MLO verhält sich der be³ wie die ax-APs. 6 GHz erlaubt keinen WPA2-Übergang; dieselbe SSID mit WPA3 auf 6 GHz hält die Clients in einem Netz (übliche Praxis bei Heimroutern), ältere Geräte bleiben auf 2,4/5 GHz. Die Master-SSID sendet auf allen Bändern aus `channels`, weitere SSIDs laut `bands`.

#### <a id="dw2.4"></a>DW2.4 · Steering für Clients an schwachen APs

*2026-10-01 · alt D55*

**Status:** teilweise geändert durch DW2.5 (2026-10-23): Der Kick trennt Clients mit FT nicht, die access-list kennt über Interface-Listen doch ein Band – Trennschwelle je Band im steer-Eintrag (`drop`/`join`/`hold`).

**Frage:** Clients, die an einem schwachen AP kleben (TODO 39)

**Entscheidung:** Steering je Band in `wifi.rsc` (`steer`={Band={threshold;after;kick;count;period}}) → Profil `cfm-steer-<Band>g`: Liegt ein Client länger als `after` unter `threshold`, schickt der AP unaufgefordert BSS-Transition-Requests (802.11v, ab RouterOS 7.21) mit den Nachbar-APs; `kick` trennt ihn danach (leer = nie). Dazu optional `minSignal` (dBm, alle Bänder) als access-list für die Anmeldung. Alles standardmäßig aus, Schwellen vor Ort ermitteln

**Verworfen:** nur access-list (`signal-range` + `allow-signal-out-of-range`)

**Begründung:** Der Client bekommt erst Nachbarn vorgeschlagen und wird nur getrennt, wenn er bleibt – näher an „nur trennen, wenn ein besserer AP da ist“. Ob ein anderer AP den Client besser hört, prüft RouterOS nicht (die APs tauschen keine Client-Pegel aus). Eine Anmeldeschwelle je Band geht nicht: Die access-list kennt kein Band, nur Interfaces, und die der CAPs entstehen dynamisch. Für weitere SSIDs legt die Rolle bei Steering je Band eigene Konfigurationen `cfm-<SSID>-<Band>g` an (Security bleibt `cfm-<SSID>`, sofern das Band keine eigene hat).

#### <a id="dw2.5"></a>DW2.5 · Trennschwelle je Band, auch für Clients mit FT

*2026-10-23 · alt D92*

**Entscheidung:** Im `steer`-Eintrag des Bands `drop` (dBm), optional `join` (Standard = drop) und `hold` (Standard 0 s). Je Band zwei access-list-Regeln (Regelblock `wcut`, Reihenfolge fest): Anmeldung unter `join` abweisen, sonst annehmen bis `drop` mit `allow-signal-out-of-range=hold`. Die Regeln zeigen auf die Interface-Liste `cfm-wifi-<Band>g`; in sie trägt RouterOS die Interfaces über einen eigenen datapath je Band und SSID (`cfm-<SSID>-<Band>g`, sonst wie `cfm-<SSID>`, dazu `interface-list`) selbst ein. SSIDs in isolierten VLANs (DP3.1) sind ausgenommen, `$cfmCheck` weist darauf hin (Nutzer, 2026-10-23)

**Verworfen:** Schwellen als `minSignal` je Band · Regel je Interface, vom Apply und einem Skript am CAPsMAN nachgeführt · verschachtelte Listen (`include`) für isolierte VLANs · FT auf dem Band aus (dann wirkt der Kick) · Band ganz aus

**Begründung:** Befunde an einem Standort (7.24.5, CAP auf 7.25beta5): Der Steering-Kick trennte einen Client mit `ft-wpa3-psk` nie (7 h 20 min unter −72, Vorschlag alle 5 s), einen ohne FT zuverlässig. Die access-list prüft laufend nur Verbindungen, die eine Regel **angenommen** hat, und trennt sie nach `allow-signal-out-of-range` – auch nach einem Wechsel per FT („disconnected, signal too weak“, danach 0–4 s ohne Verbindung); eine `reject`-Regel wies auch Wechselversuche per FT ab. Eine Anmeldung unterhalb der accept-Regel passt zu keiner Regel und wird nie geprüft (Handy 7 h an einem AP bei −87 im Mittel) – deshalb die reject-Regel davor. Mit gleicher Schwelle pendelte ein Client am Rand (getrennt, 3 s später wieder angemeldet); `join` über `drop` gibt Abstand. Ein Verweis der access-list auf ein Interface (auch eine Interface-Liste mit statischem Mitglied) zeigt nach dem Neu-Provisionieren ins Leere (`*90`); ein dynamisches Mitglied über `datapath interface-list` war danach sofort wieder da. Jede Änderung an der access-list prüft alle Verbindungen neu und kann auch Verbindungen trennen, die keine geänderte Regel angenommen hatte („access-list changed“, bis 31 s ohne WLAN) – neue Schwellen also gebündelt und nicht mitten am Tag ausrollen. Ein datapath trägt nur in eine Liste ein, isolierte VLANs brauchen schon `cfm-iso`. Labor: `e2e.sh` (Objekte, Reihenfolge, kein Probelauf-Unterschied, Entfernen, Prüfungen); das Trennen selbst nur an Hardware (von Hand nachgebaut 2026-10-22/23).

#### <a id="dw2.6"></a>DW2.6 · Fremdgerät per MAC in ein anderes VLAN

*2026-10-26 · alt D95*

**Entscheidung:** `leases.rsc` → `"wifi"="yes"` an der Lease: Die Access-List schickt diese MAC an jeder SSID in das VLAN der Lease (`vlan-id`). Die Einträge stehen vorn im Block `wcut`, bilden je MAC die Grenzen nach (je Band `join`/`drop`/`hold`, `minSignal`) und enden mit „annehmen mit VLAN“ (Nutzer, 2026-10-26)

**Verworfen:** eigener Eintrag `"clients"` in `wifi.rsc` · nur für angegebene SSIDs · PPSK auf der Haupt-SSID

**Begründung:** Lease statt `wifi.rsc`: Die MAC steht nur einmal, das Gerät bekommt zugleich feste IP und DNS-Namen, `$cfmFind` kennt es. PPSK scheidet für eine Haupt-SSID mit WPA3 aus (Multi-Passphrase nur mit WPA2, DW2.2); die Access-List hängt nur an der MAC und geht mit WPA3 und FT. Die Access-List nimmt den ersten passenden Eintrag: Ein einzelner MAC-Eintrag mit Signal-Grenze ließe das Gerät bei schwachem Signal zu den allgemeinen Regeln durchfallen, die ohne `vlan-id` annehmen – es landete doch im VLAN der SSID. Deshalb je MAC die vollständige Kette mit eigenem Abschluss. Im selben Block wie die Trennschwelle (DW2.5), nicht in einem eigenen: Ein später neu entstehender Block `wcut` käme sonst vor die MAC-Einträge (`$cfmBlock` setzt einen neuen Block an den Anfang). Ohne solche Leases bleibt der Block unverändert (gleiche Signatur). Gilt auch im lokalen Fallback der APs (DW1.6), dort baut dieselbe Funktion die Access-List. `$cfmCheck`: `wifi` nur `yes`/`no`; Fehler, wenn dieselbe MAC in zwei VLANs `wifi` hat; Hinweis bei lokal verwalteter (zufälliger) MAC und wenn das VLAN nicht auf den AP-Uplinks (`trunk-ap`) liegt. Auf Hardware offen: Gibt der CAPsMAN `vlan-id` aus der Access-List an die CAPs weiter (wie bei PPSK)? Roaming mit FT. Kabel am gemeinsamen Dock bleibt offen (TODO 65b, wartet auf 802.1X). Labor: `e2e.sh` Schritt 14 (Reihenfolge, Probelauf ohne Scheinänderung, Prüfungen).

### <a id="dw3"></a>DW3 · Kanäle

#### <a id="dw3.1"></a>DW3.1 · Kanal-Pools und Pins zentral in `wifi.rsc`

*2026-09-12 · technisch, nicht abgefragt*

Kanal-Pools zentral in `wifi.rsc`, optionales Pinning pro AP ebenfalls in `wifi.rsc → radios`, weil der CAPsMAN (nicht der AP) die Radio-Config rendert. Vorschlag für die Pins per Scan: DW3.2/DW3.3.

#### <a id="dw3.2"></a>DW3.2 · Kanalplan per Scan

*2026-10-01 · alt D56*

**Entscheidung:** `$cfmWifiScan [host=] [band=2] [duration=10s] [data=yes]`: Alle APs scannen nacheinander per ssh-exec (`/interface/wifi/scan … as-value`, Clients wechseln kurz zum Nachbarn); die BSSIDs der eigenen APs liefert der CAPsMAN (Interface-Namen `<AP>-<Band>g`, DU2.1). Ergebnis in `state/wifiscan.json`; für 2,4 GHz Vorschlag für 1/6/11 und 1/5/9/13 samt Kosten des aktuellen Stands und der Zeile für `radios`. `wifi.rsc` bleibt unverändert

**Verworfen:** nur Radios ohne Clients scannen (`force=yes` für die übrigen)

**Begründung:** Vollständige Daten in einem Durchgang; die kurze Unterbrechung ist vertretbar. Kosten je AP = Summe über gehörte Netze: (Signal + 95 dB) × Überlappung (gleicher Kanal 4/4, ein Kanal daneben 3/4 … ab 4 Kanälen Abstand 0); eigene APs, die sich hören, zählen doppelt. Bis 6 APs alle Kombinationen (Labor: 4096 in 2 s), darüber schrittweise. Die Feldnamen der Scan-Ergebnisse liest der Befehl tolerant (Hardware 2026-10-03: `address`, `channel` „2437/ax“, `signal`, `ssid`). Seit 2026-10-04 zählt der mitfunkende CAPsMAN mit (TODO 46). Formel und Beispiel: Admin-Guide 8.7. Andere Funknetze im 2,4-GHz-Band (Zigbee, Thread, Bluetooth, Milight) und der Kanalsatz 1/5/9: DW3.5.

#### <a id="dw3.3"></a>DW3.3 · Scan über den CAPsMAN

*2026-10-03 · alt D60*

**Frage:** Scan, solange der CAPsMAN die Radios steuert (TODO 41)

**Entscheidung:** Auf dem CAPsMAN am Interface `<AP>-<Band>g` scannen (Mindestdauer 10 s), Radios ohne CAPsMAN direkt am AP

**Verworfen:** Radio für den Scan kurz auf `configuration.manager=local` und zurück · beides (CAPsMAN, sonst lösen)

**Begründung:** Der CAP lehnt den Scan ab („not allowed“), der CAPsMAN liefert ihn – unter 10 s allerdings leer. Der Weg über den CAPsMAN lässt das Radio am CAPsMAN; das Lösen (gebaut und auf Hardware geprüft, ~20 s ohne Gast/IoT auf dem Radio) entfiel, als sich der CAPsMAN-Scan mit 10 s doch als brauchbar erwies. Der Fernbefehl gibt nur vier Felder zurück (Adresse, Kanal, Signal, SSID), damit die Ausgabe von `ssh-exec` klein bleibt. Eine Messung ganz ohne Netze überschreibt `state/wifiscan.json` nicht und ergibt keinen Vorschlag.

#### <a id="dw3.4"></a>DW3.4 · Scan und Kanalbericht mit den eigenen Radios des CAPsMAN

*2026-10-04 · technisch, nicht abgefragt*

`$cfmWifiScan` und `$cfmChannels` beziehen die eigenen Radios des CAPsMAN mit ein (TODO 46) – nur über sein Interface `<Name>-<Band>g`, also nur, wenn sie senden. Der Agent eines CAPsMAN meldet nur seine eigenen Radios; `host=` ersetzt nur diesen AP in der letzten Messung.

#### <a id="dw3.5"></a>DW3.5 · Andere Funknetze im 2,4-GHz-Band

*2026-10-13 · alt D80*

**Entscheidung:** Kosten mit Nähe-Gewicht: `wifi.rsc` → `others` nennt je Netz `type` (zigbee, thread, milight-rgbw/-cct/-rgbcct, ble, bt), bei Zigbee/Thread `ch` (11–26 oder `auto`), optional `near` (APs neben dem Sender) und `w`; `$cfmWifiScan` rechnet sie wie ein fremdes WLAN in die Kosten ein (an `near`-APs volles Gewicht, sonst ein Drittel), schlägt für `auto` je Kanalsatz einen 802.15.4-Kanal vor und probiert zusätzlich den Satz 1/5/9; `$cfmCheck` warnt, wenn ein Pin einen festen Zigbee-/Thread-Kanal überdeckt. Bluetooth (classic und LE) und Milight zählen ebenfalls als Kosten (Nutzer)

**Verworfen:** harter Ausschluss der überdeckenden WLAN-Kanäle im ganzen Haus · Ausschluss nur am `near`-AP · Bluetooth/Milight nur als Hinweis · eigene Datei `radio.rsc` · Kanalsätze aus allen Kombinationen ableiten

**Begründung:** Ein harter Ausschluss ließe unter 1/5/9/13 keinen Kanal übrig (das Raster deckt 2402–2482 MHz lückenlos ab); die Kosten wägen so ab, wie es bei einer Kanalwahl von Hand an einem Standort geschah: Zigbee 25 neben dem Koordinator schwer, an entfernten APs leicht. Gewichte: Zigbee/Thread 60 (wie ein WLAN mit −35 dBm), Milight 30 und BLE-Advertising 20 je Frequenz, Bluetooth classic 2 je 1-MHz-Kanal (fast gleich auf allen WLAN-Kanälen). Überlappung eines schmalen Senders: bis 9 MHz neben der Kanalmitte 4, bis 13 MHz 1 (Seitenband, z.B. Zigbee 25 über WLAN 11), sonst 0. Beim Kanalvorschlag kostet ein belegter 802.15.4-Kanal 100, ein Nachbar 2, Kanal 26 verliert jeden Gleichstand. `$cfmCheck` rechnet ohne die Helfer aus `mgr-net` (heute `mgr-scan`; beim ersten Release mit DW3.5 laufen noch die alten Manager-Module). Energie-Messungen der Koordinatoren (ZHA, OpenThread `commissioner energy`) fließen noch nicht ein. Labor: `e2e.sh` Schritt 14 (erfundene Messung, Zigbee bei einem AP, Thread `auto`, Prüfung)

### <a id="dw4"></a>DW4 · SSID-Schalter und Provisioning

#### <a id="dw4.1"></a>DW4.1 · Gast-SSID per Home Assistant schalten

*2026-10-03 · alt D64*

**Status:** teilweise geändert durch DW4.2 (2026-10-20): Provisioning mit festen Interfaces, die Skripte schalten nur noch die Interfaces der SSID; Signatur-Tabelle, Merker-Nachführung und der Start des Schalt-Skripts durch den Apply sind entfallen, HA liest den Zustand an den Interfaces.

**Frage:** Gast-SSID bei Bedarf per Home Assistant schalten (Airtime sparen)

**Entscheidung:** `"switch"="off"|"on"` (Grundzustand) und optional `"autoOff"` an der SSID; die Rolle `capsman` legt `cfm-ssid-<key>-on/-off` an (ändern nur die betroffenen Provisioning-Regeln, dann `radio/provision` der CAP-Radios), Zustand in `<cfm>/ssid-<key>.txt`, den jeder Apply übernimmt; `cfm-ssid-check` alle 10 min für Auto-Aus. HA liest den Zustand per API aus den Provisioning-Regeln, den Ablauf aus der Datei (`tools/home-assistant/cfm_ssid.py`, [home-assistant.md](home-assistant.md)). Im ersten Einsatz: Grundzustand aus, Auto-Aus nach 50 h

**Verworfen:** Schalten über den Manager (`$cfmSsid` → Daten + Release, Minuten, HA bräuchte Zugang zum Manager) · Zeitplan statt Schalter

**Begründung:** Dynamische Interfaces des CAPsMAN lassen sich nicht abschalten („can not change dynamic interface“, Hardware 2026-10-03) – es bleibt nur das Provisioning, also ein Neuprovisionieren (~3 s für alle SSIDs eines APs). `dont-require-permissions` lässt den API-User mit `read,api,test` die Skripte starten, ohne selbst schreiben zu dürfen (Labor: direktes Schreiben „not enough permissions“, das Skript schreibt). Schaltbare SSIDs kommen in `slave-configurations` immer hinter die festen (Apply wie Skript hängen sie an), sonst rutschten beim Schalten die Nummern der übrigen virtuellen Interfaces und Home Assistant verlor die Zuordnung (Hardware, 2026-10-14; vorher sortierte der Apply nach Schlüssel, `guest` vor `iot`). Die Skripte schreibt jeder Apply neu (Namen der Konfigurationen je Regel stehen darin); sie ändern die Regeln direkt und setzen Signatur des Blocks `wprov` und Merker der eigenen Radios (`wifi-local.txt`) auf die neue Kombination der Schaltzustände – beides rechnet der Apply für jede Kombination vor (bis 4 schaltbare SSIDs). Sonst baute der nächste Apply den Block mit gleichem Inhalt neu und provisionierte die eigenen Radios des CAPsMAN neu (~3 s; Hardware 2026-10-19 nach dem Auto-Aus). Passen Regeln und Zustand nicht zusammen, startet der Apply das Schalt-Skript (Nutzer 2026-10-20; nicht gewählt: Signatur über den Grundzustand und getrennte Zustandsprüfung; nur die Regeln still korrigieren). Zustand als Textdatei (`on <Ablauf>`/`off`), nicht JSON: `:deserialize` machte aus Wörtern Bools. Funkt der CAPsMAN selbst mit (`capsmanRadios`, DW1.7), provisionieren die Skripte auch seine Radios neu. Zuerst war `:global cfmSsid<key>` als Zustand für HA gedacht (Sensor „Environment“ der Integration). Das geht nicht: Die API zeigt globale Variablen nur Usern mit `write` und `policy`, und ein über die API gestartetes Skript ändert sie nicht (Labor 2026-10-03, siehe [Eigenheiten](ROUTEROS-EIGENHEITEN.md); ab 7.25 setzt ein solches Skript sie zwar, lesen dürfen sie aber weiter nur User mit `write` und `policy`). Die Variable bleibt für die Konsole; HA fragt mit einem `command_line`-Schalter und Hilfsskript (nur Standardbibliothek) ab. Verworfen: Taster der Integration ohne Zustand, mehr Rechte für den HA-User, REST-API (`www`) zusätzlich öffnen.

#### <a id="dw4.2"></a>DW4.2 · Gast-Schalter ohne Unterbrechung der übrigen SSIDs

*2026-10-20 · alt D90*

**Entscheidung:** Provisioning mit festen Interfaces (`action=create-enabled`); schaltbare SSIDs stehen immer in `slave-configurations` (hinter den festen), die Skripte `cfm-ssid-<key>-on/-off` schalten nur noch deren Interfaces ab bzw. an. Ohne Schalter zum alten Verfahren, der Rückweg ist der vorige Framework-Stand (Admin-Guide 6.8) (Nutzer, 2026-10-20)

**Verworfen:** (b) aus TODO 58: APs nacheinander neu provisionieren (die Unterbrechung je AP bliebe) · beide Verfahren per Schalter in `wifi.rsc`

**Begründung:** Dynamische Interfaces lassen sich nicht abschalten („can not change dynamic interface“, Hardware 2026-10-03), feste schon. Der Zustand bleibt in `<cfm>/ssid-<key>.txt`; Apply und `cfm-ssid-check` (alle 10 min) setzen ihn an den Interfaces durch – an denen eines neu aufgenommenen AP, die eingeschaltet entstehen, also spätestens nach 10 min, an den eigenen Radios des CAPsMAN gleich nach deren Neuprovisionierung. Die Regeln ändern sich beim Schalten nicht mehr: Signatur-Tabelle und Merker-Nachführung aus DW4.1 und der Start des Schalt-Skripts durch den Apply entfallen. Fällt `switch` weg, schaltet der Apply die Interfaces der SSID ein und löscht die Zustandsdatei. Übergang: Das erste Release provisioniert die eigenen Radios des CAPsMAN neu (`capsmanRadios`, ihr Merker ändert sich); die APs behalten ihre dynamischen Interfaces, bis das erste Schalten sie einmal neu provisioniert (etwa 3 s, wie vorher bei jedem Schalten) – das Skript erkennt das an noch vorhandenen dynamischen cfm-Interfaces. `tools/home-assistant/cfm_ssid.py` liest den Zustand jetzt an den Interfaces (ein eingeschaltetes Interface mit der Konfiguration der SSID); das gilt auch für den Stand vor DW4.2, das alte Hilfsskript meldete mit DW4.2 immer `on`. Auf Hardware offen (TODO 58): ob das Abschalten eines virtuellen AP das Radio neu startet; was erneutes Provisionieren mit vorhandenen festen Interfaces macht (geklärt 2026-10-26: neu angelegt, eingeschaltet – DW4.3); Aufräumen der festen Interfaces eines abgebauten AP. Labor (CHR ohne Radios: Regeln, Skripte, Zustand, Auto-Aus, Apply): `e2e.sh` Schritt 14.

#### <a id="dw4.3"></a>DW4.3 · Veraltete Interfaces der CAPs nach einer Regeländerung

*2026-10-26 · alt D94*

**Entscheidung:** Der Apply vergleicht je CAP-Radio die erste passende Regel (Identity, Band) mit den Konfigurationen von Master und Slaves, warnt bei Abweichung oder dynamischen Interfaces (Log, im Probelauf `WARNUNG`) und schreibt das Skript `cfm-reprov` mit den betroffenen APs; es provisioniert sie nacheinander (30 s Abstand) und startet danach `cfm-ssid-check`. Wann die ~3 s je AP passen, entscheidet der Mensch (Nutzer, 2026-10-26)

**Verworfen:** Apply provisioniert die veralteten APs selbst nacheinander · nur Doku

**Begründung:** Neuprovisionieren bei vorhandenen festen Interfaces (offene Frage aus DW4.2/TODO 58, Hardware 2026-10-26): RouterOS löscht sie und legt sie neu an – gleiche Namen, neue Nummern, keine Reste, Konfigurationen nach den aktuellen Regeln. Sie entstehen eingeschaltet, eine ausgeschaltete SSID sendet also bis zum nächsten `cfm-ssid-check` (bis zu 10 min); deshalb startet das Skript ihn gleich. Slaves werden nach Namen verglichen, also in der Folge aus `slave-configurations` (bis 9 Slaves je Radio). Die Liste im Skript stammt vom letzten Apply; ein zweiter Lauf provisioniert dieselben APs noch einmal. Labor (CHR ohne Radios): `e2e.sh` Schritt 14 (Skript mit leerer Liste); Erkennung auf Hardware mit echten und verfälschten Regeln geprüft.

## <a id="du"></a>DU · Überwachung

### <a id="du1"></a>DU1 · Anzeige am Manager

#### <a id="du1.1"></a>DU1.1 · Verkabelung per LLDP und Netzplan

*2026-09-13 · alt D33*

**Optionen (gewählt fett):** Ports: nur Infrastruktur · **alle Bridge-Ports**; Soll: **Baseline + optionale Angaben** · nur Hostfile · nur Baseline; Netzplan: **Mermaid + Tabelle, auf Anforderung zusätzlich Graphviz und CSV** · Graphviz · nur Tabelle

**Umsetzung:** Nachbarsuche (LLDP/MNDP/CDP) auf der Interface-Liste `DISC` (alle Bridge-Ports + MGMT-VLAN). Der Agent meldet die Nachbarn je physischem Port. `$cfmLinks` baut daraus die Links, vergleicht mit der Baseline (`accept=yes`, `meta/links.dat`) und den Angaben `"links"={"ether1"="rtr1:ether2"}` in `work/hosts/<name>.rsc` und schreibt `state/netzplan.md` (Mermaid + Tabelle), mit `export=yes` zusätzlich `netzplan.dot` und `netzplan.csv`. Der Manager-Tick prüft alle 15 min und loggt neue Abweichungen; der Netzplan wird nur bei Änderungen neu geschrieben (Git-Sicherung). MNDP über Bridge-Ports ohne Adresse hat die Quelle `0.0.0.0`; die Empfänger verwerfen es still (DR2.5).

#### <a id="du1.2"></a>DU1.2 · Effektive Konfiguration und Unterschiede anzeigen

*2026-10-03 · alt D61*

**Entscheidung:** `$cfmShow host=` zeigt die zusammengeführten Daten (Manager allein: Rollen, Ring, Hostfile, Ports mit aufgelöstem Profil, VLANs auf dem Gerät, WLAN, Leases; `ver=N` aus einem Release); `objects=yes` lässt das Gerät im Probelauf alle Soll-Objekte ausgeben. `$cfmDiff [ver=A] [to=B]` (Standard: letztes Release → `work/`) zeigt geänderte Dateien, betroffene Geräte und für Datendateien die geänderten Zeilen

**Verworfen:** nur Daten bzw. nur Soll-Objekte · `$cfmDiff` nur auf Dateiebene · Diff-Werkzeug am PC

**Begründung:** Die Daten gehen auch für Geräte, die offline sind; die Soll-Objekte zeigen, was cfm wirklich erzwingt. `objects=yes` nutzt den Probelauf (`$cfmPlan … show=yes`): `$cfmEnsure`/`$cfmBlock`/`$cfmSet` schreiben dann jedes Objekt mit gekürzten Werten in `cfmShowOut` (unter 50 000 Zeichen, `/file/get` liest nur ~60 KB). Zeilenvergleich auf dem Manager: gemeinsamer Anfang und gemeinsames Ende fallen weg, dazwischen LCS bis 40 000 Zellen (Datendateien bleiben weit darunter), sonst ein Block alt/neu; `lib/` und `roles/` nur als Datei.

#### <a id="du1.3"></a>DU1.3 · `$cfmStatus`: `bad vN` nur, solange es zählt

*2026-10-04 · technisch, nicht abgefragt*

`$cfmStatus` zeigt `bad vN` nur, solange N nicht älter ist als IST oder gleich SOLL – vorn in der Spalte, weil sie nach 25 Zeichen endet. Dasselbe Kriterium nutzen die Benachrichtigungen (DU4.1).

#### <a id="du1.4"></a>DU1.4 · Geräte schnell finden: `$cfmFind`

*2026-10-16 · alt D81*

**Frage:** Geräte schnell finden (TODO 53)

**Entscheidung:** Live-Suche am Manager `$cfmFind <text>` mit Filtern `host=`, `port=`, `ap=`, `ssid=`, `vlan=`, `signal=`: der Manager fragt jedes aufgenommene Gerät per ssh-exec ab (Bridge-Hosts, ARP, DHCP-Leases, auf CAPsMAN und APs die WLAN-Registrierung) und verknüpft über die MAC; der bisherige interne Helfer `$cfmFind` heißt jetzt `$cfmIds` (Nutzer)

**Verworfen:** Schnappschuss je Tick mit Index und Verlauf auf dem Manager · Python-Tool am Admin-Rechner · nur LibreNMS; Namen `$cfmWhere`/`$cfmLocate`/`$cfmSearch` statt der Umbenennung; nur benannte Felder bzw. nur Freitext

**Begründung:** Kein Verlauf, keine Last im Tick, nichts auf dem Flash; Verlauf und Messwerte soll LibreNMS liefern (TODO 54). Endpunkt ist ein Port ohne verwalteten Nachbarn (LLDP/MNDP der abgefragten Geräte, Bonds über ihre Ports); unter mehreren gilt der mit den wenigsten MACs. Ohne diese Rangfolge landete an einem Standort fast das ganze LAN-VLAN an der VLAN-Karte des CHR (hinter der PVE-Bridge: 50 MACs, Nachbar der PVE-Host), richtig sind z.B. der Port zur Fritz!Box (3 MACs) und der zum Backbone-Switch (14). Eine MAC nur an Uplinks steht mit „über Uplink“ da. Eigene Geräte (Bridge-MAC aus dem Status) stehen dort, wo ein anderes Gerät sie per LLDP/MNDP an einem Bridge-Port sieht, im MGMT-VLAN – ihre MAC lernt sonst jeder Port mit MGMT-Verkehr (an einem Standort stand ein AP an der MGMT-Karte des CHR); ein zentraler Switch erscheint mit „N Links per LLDP“. Namen aus `leases.rsc` (gelesen per `:parse` mit lokaler Variable statt `/import`: kein Eingriff in den Apply des Agents auf dem Manager, keine Meldung je Datei im Terminal), aus den Leases der Geräte und für die eigenen Geräte aus dem Status (`mac`). Netze mit fremdem DHCP (Fritz!Box): IPs nur aus der ARP-Tabelle eigener Geräte. Gemessen an einem Standort: Antwort des Core 4,3 KB in 1,1 s (73 Bridge-Hosts), 9 Geräte zusammen 29 KB. Übergang: Die alte Gerätebibliothek definiert `$cfmFind` noch als Helfer; bis der Manager selbst die neue Version anwendet, kann ein Apply auf ihm den Namen überschreiben – dann zuerst `/system script run cfm-mgr`. Eigene Templates mit `$cfmFind` auf `$cfmIds` umstellen. Labor: `e2e.sh` Schritt 14 (live über drei VMs, Name aus `leases.rsc`, MAC-Schreibweisen; Auswertung mit erfundenen Antworten per `data=`); dazu die echten Antworten eines Standorts (nur lesend abgeholt) per `data=` ausgewertet

##### <a id="du1.4.1"></a>DU1.4.1 · Suche im Browser: Lesezeichen „cfm-Monitor“

*2026-10-16 · alt D81, Teil „Im Browser“*

**Entscheidung:** Das Lesezeichen „cfm-WLAN“ (DU2.2) heißt „cfm-Monitor“ und hat zwei Reiter, WLAN (live am CAPsMAN) und Suche (startet `$cfmFind … quiet=yes` per `:execute` auf dem Manager, Treffer als JSON in eine klickbare, sortierbare Tabelle) (Nutzer)

**Verworfen:** alles über den Manager (WLAN dann nur alle ~10 s, ohne die Log-Vorgeschichte des CAPsMAN) · Suche als Reiter im cfm-Editor; Textausgabe wie im Terminal.

**Begründung:** Ohne CORS spricht ein Lesezeichen nur das Gerät an, dessen WebFig offen ist; auf einem anderen Gerät nennt der Reiter Suche die Manager-Adresse aus `state.json` des Agents, der Reiter WLAN auf einem Gerät, das nicht CAPsMAN ist, den CAPsMAN aus dem Manifest (`cm`), beide mit Link zu dessen WebFig; ein Manager, der nicht CAPsMAN ist, startet im Reiter Suche.

#### <a id="du1.5"></a>DU1.5 · `$cfmStatus` holt veraltete Stände frisch ab

*2026-10-20 · alt D89*

**Frage:** `$cfmStatus` zeigt nach einem Release bis zum nächsten Manager-Tick alte Stände (Bekannter Fehler, 2026-10-17)

**Entscheidung:** `$cfmStatus` holt vorher den Status der Geräte ab, deren Ist-Version nicht dem Soll entspricht oder bei denen ein Apply aussteht – je Gerät höchstens einmal in der Minute; Zeile „frisch abgeholt: …“ (Nutzer)

**Verworfen:** `fresh=yes` auf Wunsch · nur ein Hinweis in der Kopfzeile

**Begründung:** Kostet je betroffenem Gerät 1–2 s (SFTP), ein nicht erreichbares nur den Ping; alle übrigen kommen aus dem letzten Tick. Labor: `e2e.sh` Schritt 11.

### <a id="du2"></a>DU2 · Clients und WLAN

#### <a id="du2.1"></a>DU2.1 · Clients je AP außerhalb von cfm: API am CAPsMAN

*2026-09-27 · alt D47*

**Frage:** Welcher Client hängt an welchem AP – Anzeige außerhalb von cfm

**Entscheidung:** Lese-Zugang per RouterOS-API nur auf dem CAPsMAN (`capsmanApi` in `global.rsc`: Adressen, User; Gruppe `cfm-api` mit `read,api,test`; unverschlüsselt auf 8728, nur für die genannten Adressen), dazu stabile Interface-Namen `%I-2g`/`%I-5g` im Provisioning; Anzeige in Home Assistant (HACS-Integration „Mikrotik Router“)

**Verworfen:** Manager-Befehl `$cfmClients` · API auf allen Geräten · `api-ssl` mit Zertifikat · nur WebFig/Winbox

**Begründung:** Die Registration-Tabelle des CAPsMAN enthält alle Clients aller APs; ein Zugang dort reicht. Er wandert mit der Rolle `capsman` (`base` öffnet den Dienst nur auf `$cfmIsCapsman`, die Rolle legt User, Gruppe und die Freigabe in `local-input` an, die GC räumt das alte Gerät auf); das Passwort kommt per Secret-Push (`user.<name>`). Unverschlüsselt auf Wunsch (Klartext-Passwort eines reinen Lese-Users im LAN). Ohne stabile Namen verschob sich `cap-wifiN` bei jeder Neuverbindung, eine Zuordnung Interface → AP war in einer Oberfläche nicht haltbar. Liegt der Monitoring-Host außerhalb des MGMT-VLANs, braucht der Router davor eine Forward-Freigabe auf den API-Port: Die Rolle `router` rendert sie in ihrem Firewall-Block (Quellen aus `capsmanApi.from`, Ziel der CAPsMAN aus dem Manifest, zieht also mit um); ein Bestandsrouter ohne Rolle `router` bekommt sie über seine `post.rsc` nach demselben Muster.

#### <a id="du2.2"></a>DU2.2 · Roaming nachvollziehen ohne Home Assistant

*2026-10-12 · alt D77*

**Frage:** Roaming nachvollziehen an einem Standort ohne Home Assistant

**Optionen (gewählt fett):** Ort: **Lesezeichen „cfm-WLAN“ (seit DU1.4 „cfm-Monitor“, Reiter WLAN) für WebFig des CAPsMAN (wie DT3.1, `tools/editor/`)** · Python-Skript auf dem Laptop mit eigener Seite · Mitschnitt per Scheduler auf dem CAPsMAN; Darstellung: **AP-Kacheln live und Zeitleiste je Client** · Grundriss mit AP-Positionen; Ablage: **allgemein in `tools/`** · nur im Site-Overlay

**Begründung:** Die Registrierungstabelle des CAPsMAN enthält alle Clients aller APs (DU2.1). Das Lesezeichen fragt sie per REST derselben Adresse ab (alle 5/10/30 s) und ändert nichts am Gerät. Den AP eines Interface liefert das Feld `cap` (`<Identity>@<MAC>%…`, Hardware), unabhängig vom Namen – auch `cap-wifiN` vor dem Provisionieren mit `name-format` (DU2.1). Die `uptime` der Verbindung gibt den Beginn eines Abschnitts, ein Wechsel des Interface ist ein Roaming. Die Zeit vor dem Öffnen kommt aus dem Log des Geräts (`<MAC>@<Interface> connected/disconnected`), das nur bis zum Ende seines RAM-Puffers reicht. Der Verlauf liegt 24 h im Browser (`localStorage`), Namen aus den DHCP-Leases des Geräts (cfm-Lease, sonst `host-name`) oder per Klick. Ein Mitschnitt auf dem Gerät hätte auch ohne offenen Browser aufgezeichnet, aber regelmäßig in den Flash geschrieben. Getestet gegen eine Attrappe der REST-API (Firefox headless) und die REST-Formate an einer CHR, mit echten Clients am 2026-10-13/14 (zwei Standorte, vier bzw. zwei APs). Dabei korrigiert: Roaming-Zeilen des CAPsMAN tragen die SSID am Interface (`<MAC>@ap1-5g(SSID) roamed to <MAC>@ap2-5g(SSID), signal strength …`); alle Abfragen mit `cache: 'no-store'` ([Eigenheiten](ROUTEROS-EIGENHEITEN.md): REST und `Cache-Control`). Die REST-Ausgabe von `/interface/wifi` enthält die Passphrasen – nie ablegen

### <a id="du3"></a>DU3 · Logs

#### <a id="du3.1"></a>DU3.1 · Disk-Logging zurückgestellt

*2026-10-01 · technisch, nicht abgefragt*

Disk-Logging für den Primary (TODO 22) ist zurückgestellt, weil ein externer Syslog-Server geplant ist (inzwischen DU4.3, DU3.4).

#### <a id="du3.2"></a>DU3.2 · Konfig-Änderungen nicht im RAM-Log

*2026-10-13 · alt D79*

**Frage:** Konfig-Änderungen füllen das RAM-Log

**Entscheidung:** Die Regel `info` → memory bekommt `info,!system` (Rolle `base`, alle Geräte; `logMemory` in `global.rsc`, `"info"` = RouterOS-Standard, z.B. sobald ein Syslog-Server mitschreibt) (Nutzer)

**Verworfen:** gar kein `info` im RAM-Puffer (zuerst erwogen: dann fehlen auch die cfm-Meldungen wie „angewendet“, `cfm-drop`, WLAN-Ereignisse für cfm-WLAN und Link up/down) · `info` raus mit Ausnahmen `script`/`wireless`/`interface` · eigener Puffer für `system` · zusätzlich die Ursache am Gerät abstellen (Manager mit eigener Adresse im LAN-VLAN, Site-Regel wie DR2.5; nicht gewollt, entfällt mit dem Router-Umzug)

**Begründung:** RouterOS loggt jede Konfig-Änderung als `system,info`, bei Skripten mit dem ganzen Quelltext, dazu jede Anmeldung (`system,info,account`). Nach dem Framework-Update eines Standorts (v39) waren 536 der 1000 Zeilen im Puffer des Managers Quelltext (fünf Skripte, ~135 KB), auf dem CAPsMAN 44. Die Regel ist eine RouterOS-Standardregel (bleibt `default`, das Audit meldet sie nicht); der Syslog (`cfmremote`) bekommt weiter alle `info`. Labor 7.24.5: mit `info,!system` keine Zeile für `script add/set`, Identity und Anmeldungen, `script,info` kommt an; mit `info` wieder alles (`e2e.sh` Schritt 2). Seit 2026-10-20 stellt schon der Manager-Bootstrap die Regel vor dem ersten Release um: Beim Schreiben des Archivs loggte RouterOS jede Datei samt Inhalt, und die frühen Bootstrap-Meldungen fielen aus dem Puffer (Labor, nach dem Aufteilen der Manager-Module)

#### <a id="du3.3"></a>DU3.3 · Leeres `syslog` räumt auf

*2026-10-29 · technisch, nicht abgefragt*

Beide Standorte schickten den Syslog an ihren Manager – RouterOS nimmt aber keinen Syslog entgegen (nur mit dem Paket The Dude), die Meldungen gingen ins Leere; Vorlage war das Labor-Muster `global.rsc` mit der Manager-Adresse. Ohne `syslog` entfernte bisher nur die GC die Aktion, die Einträge blieben ungültig stehen. Jetzt entfernt `base` die Einträge mit `action=cfmremote`, solange es die Aktion noch gibt; die Aktion selbst räumt die GC weg. `new-site.py` legt neue Sites mit leerem `syslog` an. Labor: `e2e.sh` Schritt 14k.

#### <a id="du3.4"></a>DU3.4 · Was über den Syslog geht

*2026-11-01 · alt D103*

**Optionen (gewählt fett):** Dateiinhalte: **im Code vermeiden** (Nutzer) · zusätzlicher Topic-Filter `syslogTopics` · nur im Syslog-Server verwerfen; Umlaute: **Log-Meldungen nur in ASCII** (Nutzer) · zur Laufzeit in `$cfmLog` umschreiben · lassen

**Begründung:** RouterOS protokolliert `/file/add|set contents=` mit vollständigem Inhalt (`system,info`, im RAM-Log seit DU3.2 ausgeblendet, an den Syslog geht alles), `/file/copy` gar nicht; geheime Felder (Passwort, Passphrase, SNMP-Passwörter, WireGuard-`private-key`) schwärzt es (Hardware 7.25). `$cfmRelease` und `$cfmRollback` kopieren das Archiv per `/file/copy` (ohne: wie bisher Lesen und Schreiben) – ein Release schickte vorher ~750 KB an den Syslog. `$cfmRekey` eines Managers exportiert den Host-Key je User neu (`/ip/ssh/export-host-key`, der Import verbraucht die Datei), statt den privaten Schlüssel per `/file/add` zurückzuschreiben – er stünde sonst im Syslog (UDP im Klartext übers MGMT-VLAN). Log-Texte (`:log`, `$cfmLog`, `$cfmWarn`, `:error` des Agenten, Bootstrap) mit ae/oe/ue/ss und `-`, weil RouterOS jedes Nicht-ASCII-Byte als `?` sendet; `tools/rsc-check.py` Regel `log-ascii` (Fehler unter `cfm/work/`, sonst Hinweis). Terminal-Ausgaben (`:put`) und Kommentare bleiben. Labor: `e2e.sh` 14g/14h prüfen, dass nach Rekey und Release weder `PRIVATE KEY` noch Archivinhalt im Log stehen (7.25: 405 grün). Hardware 2026-11-02: Das erste Release nach dem Update läuft noch mit dem installierten alten Code (`cfm-mgr` lädt `cfm-mgr-*`), ab dem nächsten schickt der Manager statt ~1250 nur ~100 Zeilen (zwei kleine `/file add`: `index.dat`, meta). Skript-Änderungen (`/system script set source=`) protokolliert RouterOS mit Quelltext – nur bei Code-Änderungen, ohne Geheimnisse

### <a id="du4"></a>DU4 · Meldungen und Monitoring

#### <a id="du4.1"></a>DU4.1 · Benachrichtigungen per HTTP-POST

*2026-10-08 · alt D66*

**Frage:** Benachrichtigungen (TODO 2)

**Optionen (gewählt fett):** Kanal: **HTTP-POST mit JSON-Body an `global.rsc` `notify.url`** (z.B. ein Webhook von Home Assistant, das aufs Handy weiterleitet) · ntfy-Format (Text-Body, Title/Priority-Header) · E-Mail über einen SMTP-Relay; Ereignisse: **Apply-Fehler/Rollback, Gerät stumm (`stale`, Default 30 min), AP im lokalen Fallback, RouterOS-Update fehlgeschlagen, Onboarding gescheitert, CHR-Lizenz des Managers (Erneuerung überfällig oder Ablauf in weniger als `licWarn`, Default 14 Tage)**; Entprellung: **nur Wechsel – einmal beim Eintreten, einmal „wieder ok“** · Wechsel plus Erinnerung alle N Stunden · Tageszusammenfassung

**Begründung:** Das MGMT-VLAN hat kein Internet, der Manager erreicht aber Dienste im LAN; ein allgemeiner POST deckt Home Assistant, ntfy und eigene Empfänger mit derselben Funktion ab. Neues Modul `lib/mgr-notify.rsc`: `$cfmNotifyTick` läuft am Ende des Manager-Ticks (nur Primary), bildet aus den gesammelten Status die Menge `<art>:<gerät>` und meldet die Unterschiede zu `meta/notify.dat`. Scheitert die Zustellung, bleibt der Zustand offen (nächster Tick versucht es erneut), und im selben Tick folgen keine weiteren Versuche (ein toter Empfänger bremst den Tick nicht vielfach). Das JSON baut die Funktion selbst (`$cfmJStr`), damit Umlaute als UTF-8 ankommen. „Stumm“ vergleicht wie `$cfmStatus` den Zeitstempel `seen` des Geräts; `bad vN` zählt nur, solange `$cfmStatus` sie zeigt. Die Lizenzdaten liest der Manager aus `/system/license` (nur CHR hat `next-renewal-at`/`deadline-at`); überfällig heißt mindestens einen Tag zurück. Onboarding meldet einmalig (`state=once`), ohne „wieder ok“. Probe: `$cfmNotify test=yes`.

##### <a id="du4.1.1"></a>DU4.1.1 · Felder `level`/`device`/`message`, neue RouterOS-Versionen

*2026-10-11 · alt D66, Nachtrag 1*

**Status:** teilweise geändert durch DU4.2 (2026-10-27): `ros` ist ein Zustand mit „off“ und `key`.

**Entscheidung:** Zusätzlich `level`/`device`/`message` – `error` für apply, onboard und stumm, `warning` für wlan und jedes „wieder ok“, `action` für update, lizenz und **neu `ros`** (neue RouterOS-Version: einmal am Tag `NEWESTa7.<rosChannel>` bei upgrade.mikrotik.com, je Version eine Meldung, solange ein aufgenommenes Gerät älter ist; seit DU4.2 als Zustand mit „off“ und `key`), `info` für die Probe; `device` = betroffenes Gerät, nicht der Absender. Die Version wird mit Präfix `v` gespeichert (`:deserialize` liest `7.24.5` sonst als IP-Adresse).

**Verworfen:** „wieder ok“ nur als info und stumm als warning.

##### <a id="du4.1.2"></a>DU4.1.2 · Backup-Manager überwacht den Primary

*2026-10-11 · alt D66, Nachtrag 2*

**Optionen (gewählt fett):** Erkennung: **SFTP-Abruf des Spiegels und Frische der gespiegelten Gerätestatus** (zwei Meldungen `primary`/`primary-tick`, level error) · nur SFTP · nur Ping; Schwelle: **wie `notify.stale`** · 15 min · eigener Wert.

**Begründung:** Der Primary holt die Status in jedem Tick ab; sind alle älter als `stale`, obwohl SFTP geht, hängt sein Tick. Bei SFTP-Ausfall meldet der Backup nur das (sonst doppelt). Eigene Zustandsdatei `meta/notify-b.dat`.

#### <a id="du4.2"></a>DU4.2 · „Erledigt“-Meldung für neue RouterOS-Versionen

*2026-10-27 · alt D96*

**Entscheidung:** `ros` als Zustand: `"on"` beim Melden, offen in `meta/notify.dat` `roso`; in jedem Tick `"off"` („auf allen Geräten“), sobald kein aufgenommenes Gerät älter ist; kommt vorher eine neuere Version, erst `"off"` für die alte („überholt durch …“), dann `"on"` für die neue. Jede Meldung trägt `key` (`<ev>:<host>`, bei `ros` `ros:<Version>`) und bei `ros` `ver`. Absichtlich ausgelassene Geräte halten die Meldung offen – abgehakt wird beim Empfänger, cfm kümmert sich nur um die Zustände der Geräte (Nutzer, 2026-10-27)

**Verworfen:** Ausnahmeliste `rosHold` in `global.rsc` · `"off"` nur beim täglichen Abruf

**Begründung:** Die Prüfung „alle aktuell“ braucht `upgrade.mikrotik.com` nicht (gesammelter Status `ros`, `$cfmVerGe`), deshalb in jedem Tick: Die Meldung kommt kurz nach dem letzten `$cfmUpgrade`. Scheitert die Zustellung, bleibt `roso` stehen, der nächste Tick versucht es erneut. Übergang: Fehlt `roso` in `notify.dat` (Stand vor DU4.2), gilt die zuletzt gemeldete Version (`rosv`) als offen – an einem Standort mit aktuellen Geräten kommt beim ersten Tick ihr `"off"`. Bestehende Empfänger, die nur `level`/`device`/`message` lesen, laufen unverändert. Labor: `e2e.sh` Schritt 14f.

#### <a id="du4.3"></a>DU4.3 · LibreNMS: SNMPv3 und Syslog

*2026-10-29 · alt D99*

**Frage:** LibreNMS anbinden (TODO 54): SNMPv3 und Syslog

**Optionen (gewählt fett):** Passwörter: **ein Satz für alle Geräte (Vault `snmp.auth`, `snmp.priv`, Secret-Push)** (Nutzer) · je Gerät; Syslog: **`remote-log-format=syslog` (Facility `daemon`, Schwere aus dem Topic), Schlüssel `syslogFormat` zum Zurückstellen** (Nutzer) · RouterOS-Format lassen; Geräte per LibreNMS-API anlegen: **später** (Nutzer) · gleich mit Tool; sysLocation: **`snmp.location` in `global.rsc`, Hostfile `location` überschreibt** (Nutzer) · nur global

**Begründung:** `global.rsc` → `snmp`: `from` (MGMT-Adresse des Servers – laut TODO 54 bekommt er eine zweite Schnittstelle im MGMT-VLAN, entschieden 2026-10-16), `user` (Standard `librenms`), `auth` (Standard SHA256), `contact`, `location`. Die Rolle `base` legt die Community `cfm:snmp:<user>` an (authPriv, AES, nur lesend, `addresses` = `from`, Hostadressen als `/32` wie RouterOS sie zurückliest), Passwörter beim Anlegen zufällig (`a=`) – dabei fordert sie den Secret-Push an (SV 0, wie bei WireGuard DR4.2), sonst blieben sie bis zur nächsten Vault-Änderung zufällig –, schaltet die Standard-Community `public` ab und SNMP ein. Ohne `snmp` bleibt `/snmp` unangetastet – ein Bestandsgerät kann es für anderes nutzen; nach dem Wegfall entfernt die GC die Community (`/snmp/community` in `cfmMenus`). Keine Firewall-Regel: Der input-Block der Nicht-Router und die Zonen-Firewall der Router nehmen das MGMT-Netz an (`cfm-mgmt`). RouterOS 7.25 (Labor): Auth MD5/SHA1/SHA256/SHA384/SHA512, Verschlüsselung nur AES (128) oder DES, `public` lässt sich nicht löschen („can not remove default community“), abgeschaltet antwortet v2c nicht mehr; `/tool/snmp-get` mit v3 (`security=private`, `authentication-protocol`/`-password`, `encryption-protocol`/`-password`) liefert mit richtigem Passwort, mit falschem oder von einer nicht freigegebenen Adresse nichts. `$cfmCheck`: `from` gültig, `auth` bekannt (ohne MD5), Passwörter vorhanden (Warnung) und mindestens 8 Zeichen (Fehler), `syslogFormat`. `remote-log-format` setzt `base` nur, wenn RouterOS es kennt. Was das `wifi`-Paket per SNMP liefert, bleibt am hAP zu prüfen. Labor: `e2e.sh` Schritt 14k

## <a id="dt"></a>DT · Tools und Test

### <a id="dt1"></a>DT1 · Test und Prüfung

#### <a id="dt1.1"></a>DT1.1 · Testlabor: CHR in QEMU

*2026-09-11 · alt D20*

**Entscheidung:** CHR in QEMU

**Verworfen:** nur statisch · Testgerät

**Umsetzung:** `tools/chr-lab/` startet Manager + Geräte als CHR-VMs; Testläufe `e2e.sh`, `e2e-onboard.sh`, `e2e-vrrp.sh`, `e2e-mlag.sh` ([tools/chr-lab/README.md](../tools/chr-lab/README.md)).

#### <a id="dt1.2"></a>DT1.2 · Prüfskript für RouterOS-Fallen

*2026-09-13 · alt D34*

**Optionen (gewählt fett):** Sprache: **Python 3** · Bash/awk; CI: Lint + `:parse`, e2e manuell · Lint + `:parse` + e2e bei Push · **nur Lint** · keine; Hook: **Fehler blockieren** · nur warnen

**Umsetzung:** `tools/rsc-check.py` zerlegt Skripte mit einem kleinen Tokenizer (Strings, Kommentare, Zeilenfortsetzung, Klammerebenen) und prüft die statisch erkennbaren [Eigenheiten](ROUTEROS-EIGENHEITEN.md): `[` am Zeilenanfang, `\"` in direkten Funktionsargumenten, `:return` in `:onerror … in={}` (außer in Funktionsrümpfen), geräteabhängige Menüs in Slash-Schreibweise (außerhalb von Strings), Array-Literal ohne runde Klammern, `/import … verbose=yes`, unausgeglichene Klammern, Dateien über 60 KB (Hinweis ab 50 KB) und Dotfiles unter `cfm/work/`. Ausnahme per `# rsc-check: erlaubt <regel>`. Der Hook `tools/git-hooks/pre-commit` prüft den Index-Stand der gestagten Dateien; die GitHub Action prüft jeden Push samt Tests des Skripts. `:parse` und `e2e.sh` bleiben im lokalen Labor (CHR-Download, Laufzeit).

### <a id="dt2"></a>DT2 · Site-Daten

#### <a id="dt2.1"></a>DT2.1 · Lokale Site anlegen und hochladen

*2026-09-14 · technisch, nicht abgefragt*

`tools/new-site.py` erzeugt ein Overlay aus den Beispieldaten samt `STAND.md` (aktueller Stand, Logbuch mit den neuesten Einträgen oben, nächste Schritte, offene Punkte; ausführliche Analysen in einer `BEFUNDE.md` daneben) und ausgefülltem Bootstrap-Kopf; das Manager-Hostfile enthält nur den Uplink, weil Ports, die es auf dem Gerät nicht gibt, den Apply scheitern ließen. `tools/upload-seed.sh` lädt aus einem Overlay nur `*.rsc` (außer `bootstrap*.rsc`, die per `--bootstrap` einzeln ins Wurzelverzeichnis geht), `authorized_keys.<user>` und `hosts/`, `roles/`, `lib/`, `meta/` – die Site-Daten (Dateien direkt in `work/` und `work/hosts/`) seit DT2.2 nur mit `--site`; Notizen (`STAND.md`, `BEFUNDE.md`) und CSV-Listen bleiben lokal (vorher landeten sie in `work/` und damit in jedem Release). `meta/inventory.rsc` geht nur mit `--seed-inventory` hinüber, weil das Inventar nach dem ersten Aufsetzen auf dem Manager lebt. Dateien werden einzeln mit bis zu drei Versuchen übertragen; ein `sftp`-Batch mit vielen `put` scheiterte im Pilot lautlos.

#### <a id="dt2.2"></a>DT2.2 · Site-Daten führt der Manager

*2026-10-12 · alt D72*

**Frage:** Browser-Bearbeitung und lokales Overlay

**Entscheidung:** Der Manager führt die Site-Daten (wie DG1.2 gedacht): `upload-seed.sh` lädt ohne `--site` nur Framework-Code (`lib/`, `roles/`); `--site` lädt die Site-Daten und nennt vorher, was auf dem Manager anders ist; `--seed-inventory` schließt `--site` ein; `tools/pull-site.sh` holt Site-Daten und Inventar als Sicherung ins Overlay (alte lokale Fassung als `datei~`)

**Verworfen:** Upload mit Prüfsummen-Schutz (Abbruch, wenn auf dem Manager seit dem letzten Upload geändert) · nur Anleitung

**Begründung:** Eine Änderung im Browser darf der nächste Framework-Upload nicht still überschreiben. Site-Daten sind die Dateien direkt in `work/` und `work/hosts/`

### <a id="dt3"></a>DT3 · Browser-Werkzeuge

#### <a id="dt3.1"></a>DT3.1 · Editor im Browser: Lesezeichen für WebFig

*2026-10-12 · alt D73*

**Status:** ergänzt durch DT3.2 (2026-10-22): Der Code liegt jetzt auf dem Gerät (`web/`, mit dem Release verteilt) und wird über ein festes Lade-Lesezeichen „cfm“ per REST geladen; die vollständigen Lesezeichen bleiben als Rückfall.

**Optionen (gewählt fett):** **Lesezeichen für WebFig (`tools/editor/`): läuft in der WebFig-Seite des Managers und spricht die REST-API derselben Adresse an** · Userscript (Browser-Erweiterung) · Container auf dem Manager · Python-Dienst im Netz · Home-Assistant-Panel; Verbindung: **REST, bis zu den Let's-Encrypt-Zertifikaten über HTTP, danach HTTPS** (das Lesezeichen nutzt die Adresse, unter der WebFig läuft); Umfang: **Bearbeiten und Speichern, Prüfen, Diff zum Release, Probelauf, Release (Ring 0)**

**Begründung:** RouterOS liefert über `www` keine eigenen Dateien aus, und die REST-API sendet keine CORS-Header (`OPTIONS` → 503). Eine Seite von anderswo darf sie im Browser also nicht aufrufen. „File Share“ (Back To Home) liegt unter `<seriennummer>.routingthecloud.net`, also unter einer anderen Adresse, ist öffentlich und fehlt auf CHR. Ein Skript in der WebFig-Seite läuft dagegen unter derselben Adresse wie `/rest`. Der ganze Editor steckt im Lesezeichen, auf dem Manager ändert sich nichts, und es lädt nichts aus dem Netz. Lesen per `POST /rest/file/get` (`value-name=contents`), Schreiben per `PATCH /rest/file/<id>`, Umlaute als UTF-8. Befehle laufen per `:execute … file=` im Hintergrund, der Editor liest die Ausgabe laufend aus der Datei (REST bricht lange Aufrufe ab). Vor dem Speichern prüft er, ob die Datei inzwischen geändert wurde; danach `:parse`. `lib/` und `roles/` zeigt er nur an (DT2.2), seit DT3.2 auch `web/`. Ein Lesezeichen trägt seinen Stand (build.py), eine neue Fassung ersetzt die alte in der offenen WebFig-Seite (vorher nur wieder eingeblendet – ein ersetztes Lesezeichen wirkte erst nach F5). Verworfen: Installation auf dem Gerät (Skins sind nur JSON, Hotspot-Seiten unter anderer Adresse).

##### <a id="dt3.1.1"></a>DT3.1.1 · Anmeldung der Lesezeichen

*2026-10-15 · alt D73, Teil „Anmeldung“*

**Entscheidung:** Für beide Lesezeichen (auch DU2.2): eigenes Formular (der Passwort-Manager füllt es aus dem WebFig-Eintrag derselben Adresse), geprüft per XHR mit User/Passwort; der Browser merkt sich die Daten und schickt sie bei REST-Aufrufen ohne `Authorization`-Kopf bis zum Schließen mit, auch für das andere Lesezeichen (Merker `cfmRestOk` in `sessionStorage`, ohne Passwort).

**Verworfen:** Passwort nur im Speicher der Seite (bis 2026-10-15, je Öffnen neu bestätigen); nur der Anmeldedialog des Browsers (eigener Passwort-Eintrag `http://<IP>`, nach einem Tippfehler keine neue Abfrage bis zum Löschen der Website-Daten; Hardware); die WebFig-Sitzung mitnutzen (Dateien über `/jsproxy`, Befehle über ein unsichtbares WebFig-Terminal – geht, aber undokumentierte Interna).

#### <a id="dt3.2"></a>DT3.2 · Lade-Lesezeichen „cfm“

*2026-10-22 · alt D91*

**Frage:** Lesezeichen ohne Hantieren (TODO 52): nach jeder neuen Fassung von cfm-Editor/cfm-Monitor musste das Lesezeichen aus `install.html` neu gezogen werden

**Entscheidung:** Ein festes Lade-Lesezeichen „cfm“, einmal angelegt: Anmeldung wie bisher (Formular, XHR, `cfmRestOk`), dann liest es `web/cfm-editor.js` bzw. `web/cfm-monitor.js` per `POST /rest/file/get` vom offenen Gerät und startet sie. `tools/editor/build.py` legt die Fassungen (ohne Kommentarzeilen und Einrückung, unter 60 KB) nach `cfm/work/web/`; sie kommen mit `upload-seed.sh` auf den Manager und mit dem Release zu den Geräten – der Editor zur Rolle `manager`, der Monitor zu `manager` und `capsman` (`cfm/dl/web/`, optional, ohne `/import`). Das Lesezeichen sucht zuerst `cfm/dl/web/` (freigegebener Stand), dann `cfm/work/web/` (hochgeladen, noch nicht freigegeben), jeweils auch unter `flash/`. Liegt nur eine Datei auf dem Gerät, startet es sie gleich. Die vollständigen Lesezeichen bleiben in `install.html` als Rückfall für Geräte ohne `web/` (Nutzer, 2026-10-22)

**Verworfen:** Lesezeichen wie heute mit Hinweis auf eine neue Fassung · Userscript (Violentmonkey/Tampermonkey, Updates aus dem öffentlichen Repo) · Container auf dem Gerät, der die Seite ausliefert und `/rest` durchreicht · Laden über die WebFig-Sitzung (`/jsproxy`)

**Begründung:** Nur dokumentierte REST-API, nichts aus dem Netz, keine Browser-Erweiterung; die Anmeldung braucht es ohnehin für die REST-Aufrufe der beiden Lesezeichen, `/jsproxy` brächte also nichts. Ohne CORS muss der Code auf dem Gerät liegen, dessen WebFig offen ist – deshalb verteilt der Release ihn auch an den CAPsMAN, wenn er nicht der Manager ist (zusammen etwa 50 KB Flash, Switches und APs bekommen nichts). Ein Update kommt so mit dem Framework-Update und geht ringweise wie der übrige Code. `/file get` liest nur etwa 60 KB (Release und Hash-Prüfung des Agents lesen so, die REST-API ebenso) – `build.py` bricht bei einer größeren Gerätefassung ab, `$cfmParseWork` würde sie ablehnen. `tools/pull-site.sh` überspringt `web/` wie `lib/` und `roles/`. Labor: `e2e.sh` Schritte 1, 2 und 14c (Dateien je Rolle); das Lade-Lesezeichen mit nachgebildetem Browser (Node) gegen die REST-API von cm1 (7.24.5): falsches Passwort, Auswahl, Start beider Dateien unverändert, gemerkte und abgelaufene Anmeldung (2026-10-22). Im echten Browser (Firefox 153 ESR, WebFig 7.25, 2026-10-26): Formular, falsches Passwort, Start des Monitors auf dem CAPsMAN, Menü und Editor auf dem Manager, gemerkte Anmeldung.

## <a id="archiv"></a>Archiv

Abgelöste Entscheidungen, mit ihrer Nummer und dem Text zum Zeitpunkt der Ablösung.

#### <a id="ds3.2"></a>DS3.2 · Admin-SSH-Keys in einer gemeinsamen Datei

*2026-09-17 · alt D35*

**Status:** abgelöst durch DS3.3 (2026-10-04): Keys je Person in einer Datei je User, damit sich ein Key entziehen lässt, ohne die anderen anzufassen.

**Thema:** Persönliche Admin-SSH-Keys

**Optionen (gewählt fett):** Format/Ablage: **`work/authorized_keys`, OpenSSH-Format, eine Zeile je Key** · eigene `.rsc`-Datenstruktur · Secret-Push wie Passwörter (bliebe dann geheim, unnötig für Public Keys); Geltung: **alle Admin-User aus `global.rsc` `users`** · ein Key fest an einen bestimmten User gebunden (bräuchte Datei-je-User oder Spaltenformat); nicht mehr gelistete Keys: **bei jedem Apply entfernen (voll deklarativ, wie VLANs/Profile)** · nur ergänzen, Reste bleiben stehen

**Umsetzung:** `work/authorized_keys` ist optional, kein RouterOS-Skript (kein `/import`), sondern nur Bestandteil des normalen Manifests (Rolle `base` liest die Rohdatei über `cfmDl`). Fehlt sie, bleiben `ssh-keys` unangetastet; ist sie da, gilt sie als vollständiger Sollzustand: `base` schreibt bei jedem Apply für jeden User aus `users` `/user/ssh-keys` komplett neu (kein `comment`-Feld für Teil-Reconciliation vorhanden, daher remove-all + reimport wie beim Manager-eigenen Schlüssel in `mgr-enroll.rsc`). Revocation = Zeile löschen + `$cfmRelease`. Passwort-Login (Secret-Push) bleibt davon unberührt und ist immer zusätzlich möglich, ein kaputter Key sperrt also nicht aus. `$cfmCheck` prüft grob das Zeilenformat, `tools/upload-seed.sh` lädt die Datei wie die übrigen Top-Level-`.rsc`-Dateien mit hoch. Bewusst nicht in `tools/new-site.py` aufgenommen: eine automatisch mitkopierte Datei ohne echten Key wäre bei jedem Apply ein leises "alle Keys entfernen" für jede neue Site.

#### <a id="dw1.1"></a>DW1.1 · CAPsMAN auf dem Config-Manager mit Standby

*2026-09-11 · alt D17*

**Status:** abgelöst durch DW1.5 und DW1.6 (2026-09-27): Der CAPsMAN gehört auf ein Gerät ohne VM- und Host-Abhängigkeit, und statt eines passiven Standbys senden die APs bei einem Ausfall lokal weiter.

**Entscheidung:** Config-Manager + Netwatch

**Verworfen:** folgt VRRP-Master · beide aktiv

**Umsetzung:** Primary-CM ist CAPsMAN. Der Backup-CM rendert dieselbe Config mit `enabled=no`, Netwatch schaltet ihn bei Ausfall des Primary ein. Ein Controller → ein FT-Verbund.

## <a id="alte-nummern"></a>Alte Nummern

Zuordnung der bis 2026-11-03 gültigen Nummern. Teile alter Einträge, die jetzt eigene Unterentscheidungen sind,
stehen mit dabei.

| Alt | Neu | Titel |
|---|---|---|
| D1 | DG2.1 | Verteilung: Pull mit Push-Trigger |
| D2 | DG3.1 | Daten und Reconciler mit Tags |
| D3 | DG1.1 | Datenformat: RouterOS-Arrays |
| D4 | DG1.2 | Source of Truth auf dem Manager |
| D5 | DG2.2 | Explizites Release |
| D6 | DG1.3 | Schichten und lokaler Hook |
| D7 | DM3.1 | Manager-Redundanz: Fallback-Liste |
| D8 | DG2.3 | Schutz vor kaputter Config: Canary-Ringe, Backup, Watchdog |
| D9 | DS1.1 | Zuordnung Gerät ↔ Hostfile |
| D10 | DS2.1 | Rück-Export ohne Secrets |
| D11 | DS2.2 | Secrets per Secret-Push |
| D12 | DS2.3 | Vault im verschlüsselten Manager-Backup |
| D13 | DS2.4 | Externe Sicherung über einen Git-Host |
| D14 | DP1.1 | Port-Profile |
| D15 | DR1.1 | Gateway: VRRP, optional |
| D16 | DR2.1 | Firewall-Zonen über Interface-Listen |
| D17 | DW1.1 | CAPsMAN auf dem Config-Manager mit Standby |
| D18 | DW1.2 | Datapath lokal am CAP mit VLAN-Tag |
| D19 | DW2.1 | WPA2/WPA3 mit FT und 802.11k/v |
| D20 | DT1.1 | Testlabor: CHR in QEMU |
| D21 | DO1.1 | Erstzugriff: Push in die Werks-Config |
| D22 | DO1.2 | Anschlussort: temporärer Onboarding-Port |
| D23 | DO1.3 | Freigabe per Vorab-Registrierung |
| D24 | DV1.1 | Update aus dem Internet beim Onboarding |
| D25 | DS3.1 | Werks-User `admin` automatisch abschalten |
| D26 | DM1.1 | Manager-Funktionen als Module mit Lader |
| D27 | DG2.4 | Archiv und Release-Prüfung |
| D28 | DS1.4 | Identitätsprüfung und Geräteschlüssel |
| D29 | DG3.4 | Probelauf gegen `work/` |
| D30 | DV1.2 | Pakete vom Manager, Neustart nur per Befehl |
| D31 | DR2.2 | Minimale Firewall für Nicht-Router |
| D32 | DW2.2 | WLAN-Ausbau: PPSK, Kanalwahl, vorerst kein Enterprise |
| D33 | DU1.1 | Verkabelung per LLDP und Netzplan |
| D34 | DT1.2 | Prüfskript für RouterOS-Fallen |
| D35 | DS3.2 | Admin-SSH-Keys in einer gemeinsamen Datei |
| D36 | DR4.1 | WireGuard-Fernzugang für Admins |
| D37 | DR1.2 | Routing in der CPU statt im Switch-Chip |
| D38 | DR2.3 | NAT je Zone |
| D39 | DR2.4 | Internet-Freigaben für einzelne Zonen |
| D40 | DP1.2 | Router/Manager als VM mit einer Karte je VLAN |
| D41 | DW1.3 | Bridge der WLAN-Radios am CAP |
| D42 | DM2.1 | Überlappende Manager-Ticks: Job-Sperre |
| D43 | DO2.1 | Bestandsgerät übernehmen, das noch selbst routet |
| D44 | DW1.4 | WLAN-Verkehr über das MLD-Interface (Wi-Fi 7) |
| D45 | DW1.5 | Ort des CAPsMAN: eigene Rolle `capsman` |
| D46 | DW1.6 | Lokaler Fallback der APs |
| D47 | DU2.1 | Clients je AP außerhalb von cfm: API am CAPsMAN |
| D48 | DW2.3 | Wi-Fi 7 (MLO) und 6 GHz |
| D49 | DO2.2 | Nur aufgenommene Geräte ansprechen |
| D50 | DO1.7 | Onboarding hinter einem unverwalteten Switch |
| D51 | DV1.3 | Platz für Pakete auf kleinen Geräten |
| D52 | DV1.4 | Fehlende Pakete am Manager ohne Internet |
| D53 | DW1.7 | Eigene Radios des CAPsMAN-Geräts |
| D54 | DW1.8 | Gast/IoT im lokalen Fallback |
| D55 | DW2.4 | Steering für Clients an schwachen APs |
| D56 | DW3.2 | Kanalplan per Scan |
| D57 | DM2.2 | Gleichzeitige Manager-Ticks: kurz warten |
| D58 | DM3.2 | SFTP blockiert während des Spiegels: wiederholen |
| D59 | DG4.1 | Dateizugriff über den Namen |
| D60 | DW3.3 | Scan über den CAPsMAN |
| D61 | DU1.2 | Effektive Konfiguration und Unterschiede anzeigen |
| D62 | DN1.1 | Feste DHCP-Leases und DNS-Namen aus zentralen Daten |
| D63 | DV1.5 | Eingebautes Update für Geräte mit 16 MB Flash |
| D64 | DW4.1 | Gast-SSID per Home Assistant schalten |
| D65 | DS3.3 | Admin-SSH-Keys je Person |
| D66 | DU4.1 | Benachrichtigungen per HTTP-POST |
| D66, Nachtrag (Felder, `ros`) | DU4.1.1 | Felder `level`/`device`/`message`, neue RouterOS-Versionen |
| D66, Nachtrag 2026-10-11 | DU4.1.2 | Backup-Manager überwacht den Primary |
| D67 | DS2.5 | SFTP-Schlüssel rotieren, Geräte-User auf dem Backup |
| D68 | DG4.3 | Größe der Gerätebibliothek: WLAN-Teil auslagern |
| D69 | DG4.4 | Apply lädt nur geänderte Dateien |
| D70 | DG2.5 | Manifest-Bau mit den Regeln der jeweiligen Version |
| D71 | DS1.5 | RouterOS 7.25: Host-Key-Prüfung des SSH-Clients aus |
| D72 | DT2.2 | Site-Daten führt der Manager |
| D73 | DT3.1 | Editor im Browser: Lesezeichen für WebFig |
| D73, Teil „Anmeldung“ | DT3.1.1 | Anmeldung der Lesezeichen |
| D74 | DP2.1 | Bonds im Hostfile |
| D75 | DP2.2 | MLAG-Paare |
| D76 | DP3.1 | IoT-Isolation über APs und Switches hinweg |
| D77 | DU2.2 | Roaming nachvollziehen ohne Home Assistant |
| D78 | DR2.5 | MNDP ohne Adresse still verwerfen |
| D79 | DU3.2 | Konfig-Änderungen nicht im RAM-Log |
| D80 | DW3.5 | Andere Funknetze im 2,4-GHz-Band |
| D81 | DU1.4 | Geräte schnell finden: `$cfmFind` |
| D81, Teil „Im Browser“ | DU1.4.1 | Suche im Browser: Lesezeichen „cfm-Monitor“ |
| D82 | DN1.2 | DHCP der cfm-Router neben einem fremden Internet-Router |
| D83 | DR2.6 | Admin-PCs außerhalb des MGMT-VLANs hinter cfm-Routern |
| D84 | DR4.2 | WireGuard mit mehreren Routern (VRRP) |
| D85 | DR1.5 | Startender VRRP-Backup: Dienste erst nach 5 s |
| D86 | DR3.1 | WAN-VLAN zugleich Client-Netz |
| D87 | DP1.3 | Vorhandene VLAN-Interfaces unter fremdem Namen |
| D88 | DN2.1 | Zeitquelle der Router |
| D89 | DU1.5 | `$cfmStatus` holt veraltete Stände frisch ab |
| D90 | DW4.2 | Gast-Schalter ohne Unterbrechung der übrigen SSIDs |
| D91 | DT3.2 | Lade-Lesezeichen „cfm“ |
| D92 | DW2.5 | Trennschwelle je Band, auch für Clients mit FT |
| D93 | DN2.2 | NTP-Umleitung je VLAN |
| D94 | DW4.3 | Veraltete Interfaces der CAPs nach einer Regeländerung |
| D95 | DW2.6 | Fremdgerät per MAC in ein anderes VLAN |
| D96 | DU4.2 | „Erledigt“-Meldung für neue RouterOS-Versionen |
| D97 | DR2.7 | Bandbreitenlimit je VLAN |
| D98 | DW1.11 | Neue Master-SSID: Secret-Push nachfassen |
| D99 | DU4.3 | LibreNMS: SNMPv3 und Syslog |
| D100 | DR3.2 | VIP als Gateway trotz Internet-Router im Netz |
| D101 | DN3.1 | DNS der Router: Upstream, Adblock, Ausnahmen, Abfrage-Log |
| D102 | DN3.2 | DNS-Selbstbedienung |
| D103 | DU3.4 | Was über den Syslog geht |
| D104 | DG4.6 | Feature-Module |
| D104, Nachtrag | DG4.6.1 | Nur genutzte Feature-Module hochladen |
| D104, Nachtrag 2 | DG4.6.2 | WLAN-Skripte des CAPsMAN als Rümpfe |

Bisher ohne Nummer (Umsetzungsentscheidungen, Umsetzungsdetails des Onboardings, Punkte „ohne eigene
Entscheidung“ aus den Einleitungen der Runden):

| Bisher | Neu |
|---|---|
| Umsetzungsentscheidungen: Inventar ist Metadatum | DG1.4 |
| Umsetzungsentscheidungen: Erzwungener Apply löscht `bad` | DG2.6 |
| Umsetzungsentscheidungen: Reihenfolge-sensitive Listen | DG3.2 |
| Umsetzungsentscheidungen: Werte nie in Code-Strings einsetzen | DG3.3 |
| Einleitung „Dritte Remote-Runde“: Datei-Existenz nur mit nicht leerem Namen | DG4.2 |
| Umsetzungsentscheidungen: Geänderte Dateien überschreiben statt löschen | DG4.5 |
| Umsetzungsentscheidungen: Manager-Tick einstellbar | DM1.2 |
| Umsetzungsentscheidungen: Sperre `cfmApplyBusy` | DM2.3 |
| Umsetzungsentscheidungen: Gegenrichtung: Zeitstempel `cfmMgrData` | DM2.4 |
| Umsetzungsentscheidungen: Integritätsschutz | DS1.2 |
| Umsetzungsentscheidungen: Geräte-Rückmeldungen nur als Daten | DS1.3 |
| Umsetzungsentscheidungen: Dienst `reverse-proxy` | DS3.4 |
| Umsetzungsentscheidungen, „Zurückgestellt“: WebFig per HTTPS zurückgestellt | DS3.5 |
| Umsetzungsdetails Onboarding: Onboarding-VLAN 88 | DO1.4 |
| Umsetzungsdetails Onboarding: Zweistufiger Push: Probe, dann Reset mit Bootstrap | DO1.5 |
| Umsetzungsdetails Onboarding: Eine Sitzung gleichzeitig, Werksgeräte finden | DO1.6 |
| Umsetzungsentscheidungen: Manager-Bootstrap auf leerer Config | DO3.1 |
| Einleitungen „Straffung und Laufzeit“, „Fünfte Remote-Runde“: Versionsangaben: Präfix `v` und Kanal | DV1.6 |
| Umsetzungsentscheidungen: Rolle `router` mit VRRP | DR1.3 |
| Umsetzungsentscheidungen: Probelauf der Rolle `router` vor dem ersten VRRP | DR1.4 |
| Umsetzungsentscheidungen: Eigene Radios eines Wi-Fi-7-CAPsMAN | DW1.7.1 |
| Einleitung „Dritte Remote-Runde“: `slaves-static` nur bei Bedarf setzen | DW1.9 |
| Einleitung „Dritte Remote-Runde“: Warnung bei `wifi-qcom-ac` | DW1.10 |
| Umsetzungsentscheidungen: Kanalplanung | DW3.1 |
| Einleitung „Dritte Remote-Runde“: Scan und Kanalbericht mit den eigenen Radios des CAPsMAN | DW3.4 |
| Einleitung „Dritte Remote-Runde“: `$cfmStatus`: `bad vN` nur, solange es zählt | DU1.3 |
| Umsetzungsentscheidungen, „Zurückgestellt“: Disk-Logging zurückgestellt | DU3.1 |
| Umsetzungsentscheidungen: `syslog` leer räumt auf | DU3.3 |
| Umsetzungsentscheidungen: Lokale Site anlegen | DT2.1 |
| Umsetzungsentscheidungen: Dateizugriff über den Namen | DG4.1 (in den Eintrag übernommen) |

## <a id="chronik"></a>Chronik

Die Entscheidungen fielen in Runden; hier die Runden mit ihren Einleitungen (Stand des jeweiligen Tages), in
Klammern die alte Nummer.

### Grundentwurf (2026-09-11)

Entscheidungen: DG2.1 (D1), DG3.1 (D2), DG1.1 (D3), DG1.2 (D4), DG2.2 (D5), DG1.3 (D6), DM3.1 (D7), DG2.3 (D8), DS1.1 (D9), DS2.1 (D10), DS2.2 (D11), DS2.3 (D12), DS2.4 (D13), DP1.1 (D14), DR1.1 (D15), DR2.1 (D16), DW1.1 (D17), DW1.2 (D18), DW2.1 (D19), DT1.1 (D20)

Die ersten 20 Entscheidungen fielen interaktiv an einem Tag (damals Abschnitte „Architektur des Frameworks“, „Identität, Secrets, Backups“, „Netzwerk & WLAN“).

### Automatisches Onboarding (Runde 2026-09-12)

Entscheidungen: DO1.1 (D21), DO1.2 (D22), DO1.3 (D23), DV1.1 (D24), DS3.1 (D25), DM1.1 (D26), DO1.4, DO1.5, DO1.6

### Verbesserungsplan, Punkte 3 und 5–9 (Runde 2026-09-12/13)

Entscheidungen: DG2.4 (D27), DS1.4 (D28), DG3.4 (D29), DV1.2 (D30), DR2.2 (D31)

### Verbesserungsplan, Punkte 16 und 17 (Runde 2026-09-13)

Entscheidungen: DW2.2 (D32), DU1.1 (D33)

### Verbesserungsplan, Punkt 4 (Runde 2026-09-13)

Entscheidungen: DT1.2 (D34)

### Hardware-Pilot (Runde 2026-09-17)

Entscheidungen: DS3.2 (D35), DR4.1 (D36)

Erster Einsatz auf echter Hardware: ein CRS418 (Rolle `router,manager`) und ein hAP ax² (Rolle `ap`).

### Planung eines größeren Heimnetzes (Runde 2026-09-17)

Entscheidungen: DR1.2 (D37), DR2.3 (D38), DR2.4 (D39), DP1.2 (D40)

### Hardware-Pilot, Fortsetzung (Runde 2026-09-21 bis 23)

Entscheidungen: DW1.3 (D41), DM2.1 (D42), DO2.1 (D43), DW1.4 (D44)

Befunde am CRS418 (`router,manager`) und an zwei hAP ax² (`ap`). Nicht separat abgefragt, weil technisch begründet; die Alternativen stehen trotzdem dabei.

### WLAN-Stabilität (Runde 2026-09-27)

Entscheidungen: DW1.5 (D45), DW1.6 (D46), DU2.1 (D47), DW2.3 (D48)

### Betrieb aus der Ferne (Runde 2026-09-30)

Entscheidungen: DO2.2 (D49), DO1.7 (D50), DV1.3 (D51), DV1.4 (D52)

### Vorbereitung aus der Ferne (Runde 2026-10-01)

Entscheidungen: DW1.7 (D53), DW1.8 (D54), DW2.4 (D55), DW3.2 (D56), DM2.2 (D57), DM3.2 (D58), DG4.1 (D59)

Die WLAN-Punkte DW1.7, DW1.8, DW2.4, DW3.2 sind gebaut und im Labor nur auf Darstellung und Prüfung getestet (CHR hat keine Radios); alle sind standardmäßig aus und werden vor Ort eingeschaltet und geprüft. Stand 2026-10-13: DW1.7 auf Hardware eingeschaltet (hAP be³, Client-Test offen), DW3.2 auf Hardware gelaufen (über den CAPsMAN, DW3.3; Pins danach zweimal neu gesetzt), DW1.8 weiter aus; DW2.4 seit 2026-10-17 auf Hardware eingeschaltet (5 und 6 GHz, mit `kick`), Auswertung offen.

### Zweite Remote-Runde (2026-10-02/03)

Entscheidungen: DW3.3 (D60), DU1.2 (D61), DN1.1 (D62), DV1.5 (D63), DW4.1 (D64)

Aus der Ferne gebaut. Labor: DU1.2/DN1.1 in `e2e.sh` Schritt 9, DV1.5 in Schritt 13e (Update vom Spiegel), DW4.1 in Schritt 14. Hardware (2026-10-03, neun Geräte, vier APs an einem hAP be³ als CAPsMAN): DW3.3 (Scan mit Pin-Vorschlag und Zeile „Aktuell“), DU1.2 (`$cfmShow`, `objects=yes` am Manager, `$cfmDiff`), DV1.5 (hEX über den Spiegel auf 7.24.5) und DW4.1 (Gast-SSID aus); DN1.1 wirkt nur auf Geräten mit Rolle `router`.

### Dritte Remote-Runde (2026-10-04)

Entscheidungen: DS3.3 (D65), DW1.9, DW1.10, DW3.4, DU1.3, DG4.2

Aus der Ferne gebaut, Labor: DS3.3 in `e2e.sh` Schritt 14e. Dazu technisch: DW1.9, DW1.10, DW3.4, DU1.3. Hardware (2026-10-04, neun Geräte): DS3.3 ohne Änderung an den vorhandenen Keys übernommen (gleiche Fingerprints), Scan und Kanalbericht mit den drei Radios eines hAP be³ als CAPsMAN. Im Labor gefunden und behoben: DG4.2.

### Vierte Remote-Runde (2026-10-08)

Entscheidungen: DU4.1 (D66), DS2.5 (D67)

Aus der Ferne gebaut, Labor: DU4.1 in `e2e.sh` Schritt 14f (Empfänger `tools/chr-lab/notify-sink.py`), DS2.5 in Schritt 14g. Beim Sichten gefunden: Der Backup-Manager hatte keine Geräte-User `cfmd-<name>` – nur `$cfmEnroll` legte sie an, und zwar auf dem Primary; der Spiegel übertrug weder `meta/keys/` noch die User. Die im Admin-Guide beschriebene Lage „Primary fällt aus → Geräte ziehen vom Backup“ scheiterte damit an der SFTP-Anmeldung (ungetestet; `e2e.sh` prüfte nur den Spiegel). Behoben mit DS2.5 – nach der Beförderung. Im Labor zeigte sich dabei, warum ein unbeförderter Backup gar nicht ausliefern darf: Mit freigeschalteten Usern holte sich ein Gerät, dessen Primary gerade blockiert war (Spiegel-Sync, DM3.2), das ältere, aber gültig signierte Manifest vom Backup (cm1 wandte v6 statt v12 an).

### Straffung und Laufzeit (2026-10-11)

Entscheidungen: DG4.3 (D68), DG4.4 (D69), DV1.6

Anlass: `lib/lib.rsc` lag mit 46 KB bei 77 % der 60-KB-Grenze von `/file get` (DM1.1). Gemessen im Labor (CHR 7.24.5, sw1 mit Rollen switch und router): Ein Apply ohne Änderung dauerte 17–19 s. Davon entfielen etwa 0,1 s auf Import und Abgleich aller Dateien, 3 ms auf `backup save` und 60 ms auf den Export. Der Rest ging in 12 SFTP-Abrufe zu je mindestens 1 s, plus 300 ms Pause je Datei. Ein normaler Lauf ohne Apply dauert 1 s, fast nur der Abruf des Manifests. Beim Sichten gefunden: Die Sperre „je Firmware-Version höchstens ein Neustart“ griff nie, weil die Version den JSON-Umlauf nicht überstand (DV1.6).

### Fünfte Remote-Runde (2026-10-11 bis 13)

Entscheidungen: DG2.5 (D70), DS1.5 (D71), DT2.2 (D72), DT3.1 (D73), DV1.6

Anlass: Vorbereitung des Updates auf RouterOS 7.25 und des Router-Umzugs, dazu der Wunsch, die Konfiguration im Browser zu bearbeiten. Beim Sichten gefunden: Der Handgriff aus TODO 47 lud den neuen Manifest-Bau nur für die Sitzung von `$cfmRelease`. Ein späteres `$cfmPromote` baute die Manifeste wieder mit dem installierten Code, und der kennt `lib/lib-wifi.rsc` nicht. Beim ringweisen Ausrollen hätte das die WLAN-Geräte in Ring 0 und 1 getroffen, solange der Manager (Ring 2) die Version noch nicht hat. Im Labor auf 7.25rc1 gefunden: Der SSH-Client prüft dort Host-Keys (DS1.5). Außerdem meldet 7.25 die Version ohne Kanal (DV1.6).

### Sechste Remote-Runde (2026-10-12)

Entscheidungen: DP2.1 (D74), DP2.2 (D75), DP3.1 (D76), DU2.2 (D77), DM2.4

Anlass: Link-Bündel und Redundanz über zwei Switches (TODO 10, MLAG von Anfang an mitgedacht) und die Trennung von IoT-Geräten über mehrere APs hinweg (TODO 20). Im Labor geklärt: Seit RouterOS 7.22 läuft MLAG an der Bridge und auf jedem Gerät, auch auf CHR (in Software). LACP bündelt im Labor nur mit e1000-Karten mehr als einen Port (virtio meldet keine Geschwindigkeit). Ein Bridge-Filter unterscheidet ungetaggt ankommende Frames nicht nach VLAN, in getaggten Frames erlaubt er keine IP-Matcher, und ob er einen ungetaggt angekommenen Frame als IP sieht, hängt von der Karte ab (Tabelle der [Eigenheiten](ROUTEROS-EIGENHEITEN.md), DP3.1). Bei der Durchsicht der Doku gefunden: `$cfmDiff` zählte `mlag.rsc` nicht zu den gemeinsamen Datendateien (betroffen: keine, keine Zeilen) – behoben, `e2e-mlag.sh` Schritt 4. Beim Review vor dem nächsten Framework-Update einer Site gefunden: Die Sperre `cfmApplyBusy` wirkte nur in eine Richtung (DM2.4).

### Nachbereitung (2026-10-13)

Entscheidungen: DR2.5 (D78), DU3.2 (D79), DW3.5 (D80), DU1.4 (D81), DN1.2 (D82), DR2.6 (D83), DR4.2 (D84), DR1.5 (D85), DR3.1 (D86)

Anlass: Das RAM-Log von APs und CAPsMAN eines Standorts bestand zu über 80 % aus `cfm-drop`-Einträgen und reichte nur etwa 7 h zurück (TODO 50). Verworfen wurde nur, was an das Gerät selbst ging (Chain `input`); den Verkehr der Clients untereinander betrifft die Firewall nicht.

### Code-Review und Folgearbeiten (2026-10-20)

Entscheidungen: DP1.3 (D87), DN2.1 (D88), DU1.5 (D89), DW4.2 (D90), DT3.2 (D91), DW2.5 (D92), DN2.2 (D93), DW4.3 (D94), DW2.6 (D95), DU4.2 (D96), DR2.7 (D97)

Nach dem Code-Review (Befunde und Bereinigung: [TODO.md](TODO.md), Übersicht) vom Nutzer entschieden.

### Befunde vom Hardware-Update und LibreNMS (2026-10-29)

Entscheidungen: DW1.11 (D98), DU4.3 (D99), DG4.5, DG2.6

Drei „Bekannte Fehler“ vom Update eines Standorts (2026-10-28, [TODO.md](TODO.md#bekannte-fehler)) und TODO 54, vom Nutzer entschieden. Technisch dazu: DG4.5, DG2.6.

### Internet-Router im LAN: VIP als Gateway (2026-10-31)

Entscheidungen: DR3.2 (D100)

Anlass: siehe DR3.2.

### DNS der Router (2026-10-31)

Entscheidungen: DN3.1 (D101), DN3.2 (D102), DU3.4 (D103)

Anlass: siehe DN3.1.

### Feature-Module (2026-11-02)

Entscheidungen: DG4.6 (D104)

Anlass: siehe DG4.6.
