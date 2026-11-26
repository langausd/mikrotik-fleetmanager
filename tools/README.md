# Werkzeuge (`tools/`)

Die Werkzeuge laufen auf deinem Admin-Rechner, nicht auf den MikroTik-Geräten. Ausnahmen:
`cfm-git-sync` läuft auf einem Linux-Server, die Lesezeichen in `editor/` im Browser. Rufe alles aus
dem Wurzelverzeichnis des Repos auf (`tools/…`). Hilfe zu den Optionen steht jeweils im Kopf der Datei.

**Du brauchst:** bash, OpenSSH (`ssh`, `sftp`), Python 3 (nur Standardbibliothek) und Git. Für Upload
und Pull einen **SSH-Key** am Manager: Beide nutzen Batch-SFTP, und das kann kein Passwort abfragen.
Einen anderen Key als den Standard gibst du mit `SFTP_OPTS="-i ~/.ssh/<key>"` vor dem Aufruf an.

| Werkzeug | Wofür |
|---|---|
| [`upload-seed.sh`](#upload-seedsh) | Framework-Code (und beim ersten Mal die Site-Daten) auf den Manager laden |
| [`pull-site.sh`](#pull-sitesh) | Site-Daten vom Manager als Sicherung ins lokale Overlay holen |
| [`new-site.py`](#new-sitepy) | eine neue Site (Overlay) aus den Beispieldaten anlegen |
| [`rsc-check.py`](#rsc-checkpy) | RouterOS-Fallen in `.rsc`-Dateien finden, ohne Gerät |
| [`feature-module.py`](#feature-modulepy) | welche Feature-Module eine Site braucht (nutzt `upload-seed.sh`) |
| [`git-hooks/pre-commit`](#git-hookspre-commit) | `rsc-check.py` vor jedem Commit |
| [`editor/`](#editor) | cfm-Editor, cfm-Monitor und cfm-DNS als Lesezeichen für WebFig |
| [`upgrade-mirror.py`](#upgrade-mirrorpy) | RouterOS-Update für Geräte ohne Internet |
| [`pcap-ziele.py`](#pcap-zielepy) | Internet-Ziele eines Geräts aus einem Mitschnitt, Vorschlag für `allow` |
| [`wlan-btm.py`](#wlan-btmpy) | WLAN-Mitschnitt: kann ein Client Wechselvorschläge (802.11v), bekommt er welche? |
| [`wifi-sign.py`](#wifi-signpy) | WLAN-Schild als A4-PDF: QR-Code, SSID, Passphrase (de/en) |
| [`netbox-abgleich.py`](#netbox-abgleichpy) | Planung in NetBox mit cfm (Soll) und den Geräten (Ist) abgleichen |
| [`netbox-import.py`](#netbox-importpy) | Einmaliger Start-Import cfm → NetBox |
| [`netbox/`](netbox/README.md) | NetBox Custom Script „cfm-Abgleich“: Abgleich aus NetBox heraus (eigene Anleitung) |
| [`wg-client-setup.sh`](#wg-client-setupsh) | WireGuard-Zugang am Linux-Laptop einrichten |
| [`git-host/cfm-git-sync`](#git-hostcfm-git-sync) | Sicherung des Managers in ein Git-Repo |
| [`home-assistant/cfm_ssid.py`](#home-assistantcfm_ssidpy) | Gast-SSID aus Home Assistant schalten |
| [`home-assistant/cfm_port.py`](#home-assistantcfm_portpy) | Umschaltbaren Port (Dockingstation) aus Home Assistant schalten |
| [`cert-signer/`](cert-signer/README.md) | Signer für Gerätezertifikate (Let's Encrypt per acme-dns, DS3.6): CSRs vom Manager lesen, signieren, Manager anstoßen |
| [`chr-lab/`](chr-lab/README.md) | Testlabor mit RouterOS-CHR in QEMU (eigene Anleitung); `fake-ddns.py` = dyndns2-Attrappe für den DynDNS-Test |
| [`branding/`](branding/README.md) | Prototyp für das cfm-Branding-Paket: Stub, CAPs-Mode-Skript, cfm auf der WebFig-Login-Seite (Plan: docs/NETINSTALL.md, noch nicht gebaut) |

**Typischer Ablauf:** `new-site.py` → Daten anpassen, `rsc-check.py site/` → `upload-seed.sh … --seed-inventory
--bootstrap` (erstes Aufsetzen, Admin-Guide 6.2). Später bei einem neuen Framework-Stand: `git pull`,
`upload-seed.sh … --overlay site`, auf dem Manager `$cfmDiff` und `$cfmRelease`. Zwischendurch
`pull-site.sh`, damit deine lokale Kopie der Site-Daten aktuell bleibt.

---

## `upload-seed.sh`

Lädt die Vorlage aus `cfm/` (plus dein Overlay) per SFTP auf den Primary-Manager. Seit DT2.2 führt
der Manager die Site-Daten selbst. Ein normaler Upload bringt deshalb nur neuen Framework-Code
(`lib/`, `roles/`) und lässt deine Daten auf dem Manager unangetastet.

```bash
tools/upload-seed.sh admin@192.168.10.2 --overlay site            # Framework-Update (der Normalfall)
tools/upload-seed.sh admin@192.168.10.2 --overlay site --site     # zusätzlich die Site-Daten ersetzen
tools/upload-seed.sh admin@192.168.10.2 --overlay site --seed-inventory --bootstrap   # erstes Aufsetzen
```

* `--site` nennt vorher, welche Dateien auf dem Manager anders sind. Hast du dort etwas geändert
  (z.B. im cfm-Editor), hol es vorher mit `pull-site.sh`, sonst ist es weg. Hostfiles kommen dabei nur aus
  dem Overlay; fehlt dem Overlay eine Datei direkt in `work/` (z.B. `mlag.rsc`), nimmt das Skript die
  Vorlage und nennt sie. Ebenso nennt es Port-Profile der Vorlage, die in der `profiles.rsc` des Overlays fehlen
  (nur ein Hinweis, TODO 100).
* `--seed-inventory` lädt auch `meta/inventory.rsc`. Das ist nur beim allerersten Mal sinnvoll und
  bricht ab, sobald auf dem Manager echte Seriennummern stehen (`--force` überschreibt trotzdem).
* `--bootstrap [datei]` legt die Bootstrap-Datei ins Wurzelverzeichnis des Geräts (ohne Angabe:
  `bootstrap-manager.rsc` aus dem Overlay). Weitere Optionen: `--port`, `--base flash/cfm`.
* Feature-Module (`lib/<rolle>.<feature>.rsc`, DG4.6) gehen nur hinüber, wenn die Site das Feature nutzt
  (SNMP, isolierte VLANs, Admin-SSH-Keys, Bonds/MLAG, DNS aus `dns.rsc`, DNS-Selbstbedienung,
  Bandbreitenlimit, WireGuard, schaltbare SSIDs); nicht gebrauchte entfernt das Skript auf dem Manager und
  nennt sie.
  Maßgeblich sind die Site-Daten auf dem Manager, mit `--site` die hochgeladenen. Schaltest du ein
  Feature später ein (z.B. im cfm-Editor), stoppt `$cfmCheck` das Release mit „lib/… fehlt“ – dann
  das Skript erneut aufrufen. `--all-features` lädt alle hoch (Testlabor).
* Vor dem Upload prüft `rsc-check.py` alles, was hinübergeht (auch die Bootstrap-Datei). Bei einem Fehler,
  z.B. einem Kommentar in einem Array-Literal, bricht das Skript ab, ohne etwas hochzuladen;
  `--no-check` überspringt die Prüfung.
* Notizen (`STAND.md`, `BEFUNDE.md`, CSV-Listen) bleiben lokal. Jede Datei geht einzeln mit bis zu
  drei Versuchen hinüber. Am Ende steht `Seed hochgeladen nach … (N Dateien)`.
* Danach auf dem Manager: `/system script run cfm-mgr`, dann `$cfmDiff` (was ist neu?) und
  `$cfmRelease msg="…"`. Läuft auf dem Manager noch Code von vor DG2.5 (vor 2026-10-11), gilt bis
  zu seinem eigenen Update der Handgriff aus [TODO 47](../docs/ERLEDIGT.md#erledigte-punkte).

## `feature-module.py`

Sagt, welche Feature-Module (`cfm/work/lib/<rolle>.<feature>.rsc`, DG4.6) eine Site braucht, aus ihren
Site-Daten (`global.rsc`, `vlans.rsc`, `wifi.rsc`, `wireguard.rsc`, `dns.rsc`, `mlag.rsc`, `hosts/`,
`authorized_keys.<user>`). `upload-seed.sh` ruft es auf; von Hand zum Nachsehen:

```bash
tools/feature-module.py site cfm/work/lib --alle    # je Modul ja/nein und der Grund
```

Die Daten werden nicht ausgeführt, nur nach den Schlüsseln durchsucht. Im Zweifel (Wert per `:set`
gesetzt, unbekanntes Modul) gilt ein Modul als gebraucht. Tests: `tools/feature-module-test.py`,
`tools/upload-seed-test.py` (gegen einen nachgebauten SFTP-Server, beide in der GitHub Action).

## `pull-site.sh`

Holt die Site-Daten (`global.rsc`, `vlans.rsc`, …, `hosts/`, `authorized_keys.<user>`) und
`meta/inventory.rsc` vom Manager in dein Overlay. `lib/` und `roles/` bleiben unberührt.

```bash
tools/pull-site.sh admin@192.168.10.2 --overlay site --dry-run    # nur zeigen, was anders ist
tools/pull-site.sh admin@192.168.10.2 --overlay site              # holen
```

* Eine lokale Datei, die anders war, bleibt als `datei~` liegen. `upload-seed.sh` lädt solche
  Dateien nie hoch, du kannst sie vergleichen und dann löschen.
* Dateien, die es nur im Overlay gibt, nennt das Skript, löscht sie aber nicht.
* `--port` (SSH) und `--base flash/cfm` wie bei `upload-seed.sh`.
* Wann: nach Änderungen am Manager, vor einem Upload mit `--site` und regelmäßig als Sicherung.
  `site/` und `site-*/` sind von Git ausgenommen. Sichere sie selbst, z.B. in einem privaten Repo.

## `new-site.py`

Legt ein neues Overlay aus den Beispieldaten an (ein fiktives Netz, MGMT-VLAN 10 mit 192.168.10.0/24) und
setzt Manager-Name, Uplink, Admin-User und deinen Management-Zugang ein.

```bash
tools/new-site.py site --name cm1 --uplink ether1 --user <dein-user> --mgmt-extra <admin-pc>/32
```

* Ergebnis: das Verzeichnis `site/` mit allen Datendateien, eine `STAND.md` mit den nächsten
  Schritten (was du vor dem Einsatz anpassen musst) und ein `bootstrap-manager.rsc` mit ausgefülltem Kopf.
* `--mgmt-extra` darf mehrfach vorkommen. `--force` schreibt auch in ein nicht leeres Verzeichnis.
* Weiter geht es mit der `STAND.md` und dem Admin-Guide, Abschnitt 6.1.

## `rsc-check.py`

Findet bekannte RouterOS-Fallen in Skripten, ohne Gerät: `[` am Zeilenanfang, Escapes in
Funktionsargumenten, `:return` in `:onerror`, leere Arrays nach `:global`, Werte, die
`:deserialize` umdeutet, Dateien über 60 KB, Log-Meldungen mit Umlauten (kommen im Syslog als `?` an)
und mehr.

```bash
tools/rsc-check.py              # alle .rsc-Dateien im Repo
tools/rsc-check.py site/        # dein Overlay
tools/rsc-check.py --regeln     # alle Regeln mit Erklärung
python3 tools/rsc-check-test.py # Tests des Prüfskripts
```

* Ausgabe je Fund: `datei:zeile: FEHLER [regel] Erklärung`, am Anfang eine Zusammenfassung. Bei
  Fehlern ist der Rückgabewert 1.
* Ist ein Fund gewollt, schreib `# rsc-check: erlaubt <regel>` in die Zeile darüber.
* In einem Overlay gilt die 60-KB-Grenze nur für Dateien, die `upload-seed.sh` hochlädt (oberste Ebene,
  `hosts/`, `roles/`, `lib/`, `meta/`); Exporte als Notiz, z.B. unter `ist/`, prüft es nur auf die übrigen Regeln.
* Das Skript ersetzt weder `:parse` noch das Labor: Ob ein Befehl auf dem Gerät existiert, sieht es nicht.

## `git-hooks/pre-commit`

Prüft vor jedem Commit die gestagten `.rsc`-Dateien mit `rsc-check.py --staged` und blockiert den
Commit bei Fehlern.

```bash
git config core.hooksPath tools/git-hooks    # einmal je Klon
git commit --no-verify                       # im Ausnahmefall ohne Prüfung
```

Auf GitHub prüft zusätzlich die Action `rsc-check` (`.github/workflows/rsc-check.yml`) jeden Push – neben
`rsc-check.py` auch die Tests der übrigen Werkzeuge (`wifi-sign.py`, QR-Encoder, `upload-seed.sh`, `wlan-btm.py`, `new-site.py`).
Ein Fehler bricht die Schritte danach ab; im Log der Action den ersten roten Schritt ansehen.

## `editor/`

Drei Werkzeuge für WebFig, die über die REST-API derselben Adresse arbeiten. Gestartet werden sie über ein
festes Lesezeichen „cfm“ (DT3.2), das ihren Code vom Gerät lädt. Aus dem Netz wird nichts geladen.

* **cfm-Editor** (DT3.1): Site-Daten auf dem Manager bearbeiten, prüfen, Diff zum Release, Probelauf,
  Release an Ring 0 (ohne Notiz nur nach Rückfrage), Promote, Status, WLAN-Schild drucken (DT3.4.1, Passphrase aus dem Vault),
  Kanäle und Sendeleistung der APs, WLAN-Scan mit „Vorschlag übernehmen“ in `wifi.rsc` (DT3.5). Anmelden mit einem User der Gruppe `full`.
* **cfm-Monitor** (DU2.2, DU1.4; früher cfm-WLAN): Reiter WLAN mit den Clients je AP live und Roaming als
  Zeitleiste (in WebFig des CAPsMAN, Leserecht genügt); Reiter Suche findet Geräte nach MAC, IP, Name,
  Port, AP oder SSID (`$cfmFind`, in WebFig des Managers, Gruppe `full`).
* **cfm-DNS** (DN3.2): DNS-Selbstbedienung in WebFig eines Routers mit `self` in `dns.rsc` – gesperrte Namen
  der letzten Minuten, häufigste Abfragen, „Freischalten anfragen“. Der User `dns` sieht nur das eigene
  Gerät, ein Admin alle und macht Freischaltungen dauerhaft. Für die Clients: `install.html` weitergeben,
  „cfm“ ziehen, WebFig des eigenen Gateways öffnen.

So richtest du sie ein:

1. `tools/editor/install.html` im Browser öffnen (als lokale Datei) und den Knopf „cfm“ einmal in die
   Lesezeichen-Leiste ziehen.
2. WebFig öffnen (`http://<IP>/webfig/` des Managers bzw. des CAPsMAN), „cfm“ anklicken und anmelden
   (der Passwort-Manager trägt die WebFig-Daten ein). Auf dem Manager wählst du Editor oder Monitor, auf
   dem CAPsMAN startet gleich der Monitor, auf einem Router cfm-DNS. Der Browser merkt sich die Anmeldung bis zum Schließen.
   Voraussetzung: Dienst `www` (oder `www-ssl`) in `services`.

Den Code legt `tools/editor/build.py` nach `cfm/work/web/` (und baut `install.html`). Nach einer Änderung an
`cfm-editor.js`, `cfm-qr.js` (QR-Encoder des WLAN-Schilds, Test: `tools/editor/cfm-qr-test.py` mit gjs und libzbar),
`cfm-radios.js` (Kanalvorschlag in `wifi.rsc` übernehmen, Test: `tools/editor/cfm-radios-test.py` mit node),
`cfm-monitor.js` oder `cfm-dns.js`: `build.py`, mit `upload-seed.sh` hochladen, releasen – das
Lesezeichen bleibt. Für Geräte mit einem Framework-Stand ohne `web/` stehen in `install.html` weiter die
vollständigen Lesezeichen (Code im Lesezeichen, nach jeder Fassung neu ziehen). Alte Lesezeichen
„cfm-Editor“, „cfm-Monitor“ und „cfm-WLAN“ kannst du danach löschen. Mehr im Admin-Guide, 8.1, 8.10, 8.11.

## `upgrade-mirror.py`

Ein Spiegel für das eingebaute RouterOS-Update (DV1.5). Damit aktualisieren sich Geräte, die selbst
kein Internet haben (z.B. im MGMT-VLAN), von deinem Rechner aus.

```bash
sudo tools/upgrade-mirror.py 7.24.5     # lauscht auf Port 80, holt Dateien bei Bedarf von MikroTik
```

Auf dem Manager dann `$cfmUpgrade ver=7.24.5 host=<gerät> via=mirror mirror=<IP deines Rechners>`.
Ist das Update durch, beendest du den Spiegel mit Strg+C.

* `--prefetch arm64:routeros,wifi-qcom mmips:routeros` lädt vorab (z.B. solange du noch Internet
  hast), `--offline` nimmt dann nur den Zwischenspeicher (`--dir`, Standard `~/.cache/cfm-upgrade-mirror`).
* Port 80 schon belegt (z.B. Apache)? `--export /var/www/html` schreibt die Dateien statisch hinein.
  Danach `routeros/` dort wieder löschen.
* Ohne root: `--port 8080` und eine Weiterleitung von Port 80 dorthin; `--bind <IP>` lauscht nur auf einer Adresse.
* Die Geräte müssen deinen Rechner auf Port 80 erreichen (Firewall des Rechners). Die Pakete sind
  von MikroTik signiert, RouterOS prüft das beim Installieren.

## `pcap-ziele.py`

Ein Gerät soll in eine Zone ohne Internet (z.B. IoT), braucht aber seine Cloud. Freigeben kannst du
sie mit einer `allow`-Liste in `global.rsc` (Admin-Guide, `policy`/`allow`) – vorher musst du wissen,
welche Namen und Ports das Gerät anspricht. Das Skript liest dazu einen Mitschnitt.

1. Mitschnitt aufnehmen, während das Gerät arbeitet (App bedienen, Programm starten), am besten
   einige Stunden: an einer Fritz!Box unter `http://fritz.box/html/capture.html` die Schnittstelle,
   an der das Gerät hängt (WLAN oder LAN) – der Mitschnitt ist ein Download im Browser und reißt ab, sobald der
   Rechner das Netz wechselt. Besser am cfm-Router: `$cfmSniff host=<router> lease=<name> dauer=12h` auf dem
   Manager (Admin-Guide, DU2.3) schneidet nur dieses Gerät mit, der Manager legt die Datei unter `sniff/` ab
   (`scp <user>@<manager>:cfm/sniff/<datei>.pcap .`).
2. Auswerten:

```bash
tools/pcap-ziele.py mitschnitt.eth --leases site/leases.rsc        # welche Geräte sind drin?
tools/pcap-ziele.py mitschnitt.eth --mac 02:00:00:00:00:AA --liste waschmaschine
```

Je Gerät siehst du die DNS-Anfragen, die Verbindungen ins Internet (Port, Adresse, Name aus DNS,
TLS oder HTTP) und im LAN, am Ende einen Vorschlag wie `"waschmaschine"={"api.example.com:tcp/443"}`.
Prüfe ihn: Einträge mit einer IP statt eines Namens können sich ändern. Liest pcap (auch das „modifizierte“ der Fritz!Box) und pcapng, auch abgebrochene `.part`-Dateien, ohne
Fremdpakete. Verschlüsseltes QUIC (`udp/443`) zeigt nur die Adresse, den Namen dann aus den DNS-Anfragen.

## `wlan-btm.py`

Ein Client bleibt an einem schwachen AP hängen, obwohl `steer` (DW2.4) ihn wechseln lassen soll. Vorschläge zum
Wechsel (BSS Transition, 802.11v) schickt der AP nur Clients, die das in ihrer Anmeldung melden. Das Skript liest einen
Mitschnitt vom Funk und zeigt es je Client – dazu 802.11k, FT, die AKMs und den Ablauf (Anmeldung, Trennung mit Grund,
Wechselvorschläge mit Antwort).

1. Mitschnitt auf einem freien Radio im Kanal des APs (es sendet währenddessen nicht als AP):
   `/interface/wifi/sniffer wifi1 pcap-file=btm pcap-size-limit=20000000 duration=4m filter="type == 0 && subtype != 8"`
   (nur Management-Frames ohne Beacons), Datei per `scp` holen. Oder als Strom: `stream-address=<Rechner>` und am
   Rechner `tcpdump -i <if> -w btm.pcap udp port 37008`. An einem Radio, das der CAPsMAN verwaltet, lehnt RouterOS den
   Sniffer ab (`failure: not allowed`, 7.25.1); vorher `/interface/wifi/cap/set enabled=no` – das Radio hört dann im
   Monitor-Modus auch fremde Frames auf seinem Kanal, aber nur in Funkreichweite: Gerät nahe an den Client stellen.
2. Während der Aufnahme am Client WLAN aus und wieder an – erst der Association Request zeigt die Fähigkeiten.
3. Auswerten:

```bash
tools/wlan-btm.py btm.pcap --mac 02:00:00:00:00:AA     # ein Client
tools/wlan-btm.py btm.pcap                              # alle, die sich im Mitschnitt anmelden
```

Die Zusammenfassung zeigt jede Fassung der Fähigkeiten getrennt – je Quelle (Association Request, gezielter Probe
Request, Wildcard-Probe) und SSID, mit Anzahl und Zeit. Handys schicken je nach Probe verschiedene Extended
Capabilities (ein Android-Handy: gezielte Probes ohne BTM-Bit, Wildcard-Probes mit); das Urteil („→ …“) stützt sich
deshalb nur auf den (Re)Association Request je SSID. FT und AKM nennt das Skript nur dort – Probe Requests tragen keine
Mobility Domain. Fehlt der Association Request, sagt die letzte Zeile das. Steht dort „meldet KEIN BSS Transition“,
hilft bei diesem Client nur eine Trennschwelle (`drop`/`join`/`hold`).
`--alle` zeigt jeden Management-Frame der Clients (sonst Probe Requests nur zusammengefasst), `--probe` die Fähigkeiten
aus Probe Requests auch ohne `--mac` (zufällige MACs der Handys erscheinen dann einzeln).
Mit PMF (WPA3) sind die Wechselvorschläge selbst verschlüsselt – das Skript zeigt dann nur Zeit, Richtung und Länge.
Liest pcap/pcapng mit 802.11, Radiotap (mit Signal) oder TZSP; nur Standardbibliothek.

## `wifi-sign.py`

Ein Schild zum Aushängen, z.B. fürs Gäste-WLAN: A4-PDF mit Überschrift (Deutsch und Englisch), QR-Code (rund
12 cm, das übliche Format `WIFI:T:…;S:…;P:…;;` – iOS und Android verbinden sich direkt aus der Kamera), darunter SSID
und Passphrase zum Abtippen (Monospace, `0/O` und `l/1` unterscheidbar). Die SSID kommt aus `wifi.rsc` des Overlays,
die Passphrase aus dem Vault des Managers (`cfm:psk.<Schlüssel>`, per SSH) oder verdeckt von der Tastatur:

```bash
tools/wifi-sign.py --overlay site --ssid guest --manager <user>@<manager> -o ~/gast-wlan.pdf
tools/wifi-sign.py --overlay site --ssid guest                    # Passphrase abfragen
tools/wifi-sign.py --name Cafe --sec none                         # offenes Netz, ohne Passphrase
```

Optionen: `--title "Gäste-WLAN|Guest Wi-Fi"` (zwei Zeilen), `--hint "…"` (Zeile am unteren Rand), `--hidden` (SSID
nicht ausgestrahlt), `--passphrase-stdin` (Passphrase aus einer Pipe), `--port` (SSH-Port des Managers). Typ im QR-Code: `WPA` für WPA2 und gemischt WPA2/WPA3, `SAE` nur bei reinem WPA3. Das PDF enthält
die Passphrase und entsteht mit Rechten `0600` – nicht ins Repo legen, nach einem Passwortwechsel neu erzeugen. Braucht
`python3-segno` und `python3-cairo` (Debian/Ubuntu). Tests: `tools/wifi-sign-test.py`.
Dasselbe Schild ohne Python: Knopf „WLAN-Schild“ im cfm-Editor (DT3.4.1).

## `netbox-abgleich.py`

Vergleicht die Planung in NetBox mit cfm und den Geräten (TODO 55, DT2.3, Admin-Guide 8.21). NetBox ist der
Planungsstand, cfm bleibt führend: Das Tool ändert nichts, weder in NetBox noch in den Site-Daten, es berichtet nur.

```bash
NETBOX_TOKEN=… tools/netbox-abgleich.py --netbox https://netbox.example --site <slug> --manager admin@192.168.10.2
tools/netbox-abgleich.py --netbox … --site … --token-file ~/.netbox-token --state <verz>   # state/ liegt lokal
tools/netbox-abgleich.py --plan plan.json --state <verz>                                  # ohne NetBox
```

* Mit `--manager` startet das Tool am Manager `$cfmNetbox` (wertet die Site-Daten aus, Standard: letztes Release,
  `--ver 0` = `work/`) und holt per SFTP `state/netbox.json` und je Gerät `state/<name>/netbox.json`, `status.dat`
  und `export.rsc`. Dafür brauchst du wie bei `pull-site.sh` einen SSH-Key am Manager.
* Verglichen werden Geräte (Seriennummer, Modell, `cfm_role`, MGMT-IP), Ports (vorhanden, Profil `cfm_port` bzw.
  `cfm_port_default`, 802.1Q-Modus, Bond), Kabel (NetBox ↔ `links` im Hostfile ↔ LLDP/MNDP), VLANs, Prefixe,
  IP-Adressen (MGMT, Gateways/VIPs, feste Leases, WireGuard und alle Adressen auf den Geräten) und Tunnel der
  Standortkopplung.
* Ausgabe je Bereich: `✘` Abweichung, `!` Hinweis, mit `--alle` auch `·` Info (z.B. Adressen, die nur in NetBox
  stehen). `--json` gibt die Befunde als JSON aus, `--plan-speichern <datei>` legt den gelesenen Plan ab. Exit-Code
  0 ohne Abweichung, 1 mit, 2 bei einem Fehler.
* `--port` (SSH) und `--base flash/cfm` wie bei `upload-seed.sh`.
* `--plan-speichern <datei>` ohne `--state`/`--manager`: nur NetBox lesen und den Plan speichern (Test von Token und
  Zugriff, auch bevor `$cfmNetbox` auf dem Manager ist).
* `--lesend [--key <datei>] [--known-hosts <datei>]`: Soll und Ist als User `cfm-netbox` holen (nur Lesen, `global.rsc` `netbox`; das Skript
  `cfm-netbox-run` gibt die Dateien aus, kein SFTP; immer das letzte Release, die Ablage kennt der Manager). So ruft es das Custom Script in `tools/netbox/` auf.
* Token anlegen (nur lesend) und ablegen: Admin-Guide 8.21. `--ca <pem>` für eine NetBox mit eigenem Zertifikat,
  `--unsicher` prüft das Zertifikat nicht.
* `--vlan-group <slug>`: VLANs aus einer VLAN-Gruppe statt der Site. Token mit `nbt_` (NetBox 4.5) geht als Bearer,
  ältere als `Token`. Nur Standardbibliothek; Tests: `tools/netbox-abgleich-test.py`.

## `netbox-import.py`

Einmaliger Start-Import cfm → NetBox (TODO 55 Baustein 2, DT2.3, Admin-Guide 8.21): legt in NetBox an, was dort fehlt,
damit danach dort geplant und mit `netbox-abgleich.py` verglichen werden kann.

```bash
tools/netbox-import.py --site <slug> --manager admin@192.168.10.2 --plan-speichern plan.json   # nur der Plan
tools/netbox-import.py --site <slug> --state <verz> --netbox https://netbox.example --token-file <rw-token>   # Probelauf
tools/netbox-import.py … --schreiben                                                          # anlegen
```

* Quellen wie beim Abgleich (`--manager` startet `$cfmNetbox`, oder `--state`; `--ver`, `--port`, `--base`).
* Ohne `--netbox`: nur der Plan aus cfm (Zusammenfassung, Hinweise auf Übersprungenes, mit `--plan-speichern` als
  Datei im Format des Abgleichs). Mit `--netbox` ohne `--schreiben`: Probelauf, NetBox wird nur gelesen, `+` =
  würde angelegt, `~` = würde ergänzt. `--schreiben` braucht ein Token mit Schreibrecht.
* Vorhandenes bleibt, nur leere Felder werden gefüllt; ein zweiter Lauf legt nichts an. Die Site wird angelegt, wenn
  sie fehlt. NetBox 3.7 bis 4.6 (`device_role`/`role`, `content_types`/`object_types`, Prefix-`site`/`scope` ab 4.2,
  Tunnel mit Kapselung WireGuard ab 4.0, davor `ip-ip`).
* `--vlan-group`, `--ca`, `--unsicher` wie beim Abgleich. Tests: `tools/netbox-import-test.py` (NetBox im Speicher,
  Rundlauf Import → Abgleich ohne Abweichung).

* Fehlt in NetBox ein Gerätetyp, legt der Import ihn mit Interface-Vorlagen aus den Ports des ersten Geräts an.
  `--typ-yaml <verzeichnis>` schreibt je neuem Typ einen Entwurf für die Device-Type-Library (auch im Probelauf).

## `wg-client-setup.sh`

Legt die WireGuard-Verbindung zum Admin-Netz als NetworkManager-Verbindung an (Linux, braucht
`nmcli`; den Schlüssel erzeugt `genkey` mit `wg` aus `wireguard-tools`, ohne das Paket mit OpenSSL). Das
geht in zwei Schritten, weil jede Seite den Public Key der anderen braucht:

```bash
tools/wg-client-setup.sh genkey      # 1. Schlüssel erzeugen, Public Key nach wireguard.rsc (peers)
                                     #    dann $cfmRelease; den Key des Routers zeigt /interface/wireguard/print
tools/wg-client-setup.sh connect --name cfm-mgmt --endpoint <öffentliche-IP>:13231 \
  --server-pubkey <KEY-DES-ROUTERS> --address 192.168.250.2/32 \
  --allowed-ips 192.168.250.0/24,192.168.10.0/24     # 2. Verbindung anlegen
nmcli connection up cfm-mgmt                         # verbinden
```

Den Schlüssel legt `genkey` unter `~/.config/wireguard/<name>.key` ab (`--keyfile` ändert das, bei `connect`
ebenso); `--keepalive 25` hält die Verbindung hinter NAT offen. Die Adresse passt zu `peers.<name>.addr` in `wireguard.rsc`. Mit VRRP ist der Endpoint die VIP des
WAN-VLANs, der Key ist auf allen Routern derselbe. Mehr dazu im Admin-Guide, Abschnitt 8.8.

## `git-host/cfm-git-sync`

Externe Sicherung (DS2.4): Nach Release, Rollback, Promote, Audit, Onboarding, Vault-Backup und neuen
Geräte-Exporten ruft der Manager per SSH dieses Skript auf einem Linux-Server auf. Es holt den
Stand per SFTP und committet ihn in ein Git-Repo, auf Wunsch mit `git push`.

* Einrichtung einmalig, Schritt für Schritt im Kopf des Skripts: User `cfm` auf dem Server, Key des
  Managers als Forced Command in `~cfm/.ssh/authorized_keys`, ein SFTP-User `cfm-git` auf den
  Managern, `/etc/cfm-git-sync.conf`, in `global.rsc` `"hook"={"host"=…;"user"="cfm"}`.
* Von Hand auf dem Server: `cfm-git-sync manual`. Admin-Guide, Abschnitt 6.5.

## `home-assistant/cfm_ssid.py`

Schaltet eine schaltbare SSID (DW4.1, DW4.2, z.B. das Gast-WLAN) aus Home Assistant und fragt ihren
Zustand (an den WLAN-Interfaces) und die eingebuchten Clients ab. Es spricht direkt die RouterOS-API
des CAPsMAN an.

```bash
cfm_ssid.py guest on | off | state | until | clients
```

Die Zugangsdaten stehen in `cfm_ssid.json` neben dem Skript. Einbau in Home Assistant, Test und
Fehlersuche: [docs/home-assistant.md](../docs/home-assistant.md).

## `home-assistant/cfm_port.py`

Schaltet einen umschaltbaren Port (`portSwitch` im Hostfile, DP1.4.1, z.B. die Dockingstation) aus Home Assistant
zwischen `normal` und `alt` und fragt den Zustand ab. Es spricht die RouterOS-API des Geräts mit dem Port an, mit
demselben User wie `cfm_ssid.py`.

```bash
cfm_port.py 192.168.10.30 dock normal | alt | state
```

Liegt neben `cfm_ssid.py` (nutzt dessen API-Client und `cfm_ssid.json`). Einbau in Home Assistant:
[docs/home-assistant.md](../docs/home-assistant.md), Abschnitt 8.

## `chr-lab/`

Das Testlabor startet RouterOS als virtuelle Maschinen und spielt ganze Abläufe durch (Aufnahme,
Release, Rollback, Onboarding, VRRP, MLAG …). Anleitung: [chr-lab/README.md](chr-lab/README.md).
