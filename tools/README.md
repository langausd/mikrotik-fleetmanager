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
| [`git-hooks/pre-commit`](#git-hookspre-commit) | `rsc-check.py` vor jedem Commit |
| [`editor/`](#editor) | cfm-Editor und cfm-Monitor als Lesezeichen für WebFig |
| [`upgrade-mirror.py`](#upgrade-mirrorpy) | RouterOS-Update für Geräte ohne Internet |
| [`pcap-ziele.py`](#pcap-zielepy) | Internet-Ziele eines Geräts aus einem Mitschnitt, Vorschlag für `allow` |
| [`wg-client-setup.sh`](#wg-client-setupsh) | WireGuard-Zugang am Linux-Laptop einrichten |
| [`git-host/cfm-git-sync`](#git-hostcfm-git-sync) | Sicherung des Managers in ein Git-Repo |
| [`home-assistant/cfm_ssid.py`](#home-assistantcfm_ssidpy) | Gast-SSID aus Home Assistant schalten |
| [`chr-lab/`](chr-lab/README.md) | Testlabor mit RouterOS-CHR in QEMU (eigene Anleitung) |

**Typischer Ablauf:** `new-site.py` → Daten anpassen, `rsc-check.py site/` → `upload-seed.sh … --seed-inventory
--bootstrap` (erstes Aufsetzen, Admin-Guide 6.2). Später bei einem neuen Framework-Stand: `git pull`,
`upload-seed.sh … --overlay site`, auf dem Manager `$cfmDiff` und `$cfmRelease`. Zwischendurch
`pull-site.sh`, damit deine lokale Kopie der Site-Daten aktuell bleibt.

---

## `upload-seed.sh`

Lädt die Vorlage aus `cfm/` (plus dein Overlay) per SFTP auf den Primary-Manager. Seit D72 führt
der Manager die Site-Daten selbst. Ein normaler Upload bringt deshalb nur neuen Framework-Code
(`lib/`, `roles/`) und lässt deine Daten auf dem Manager unangetastet.

```bash
tools/upload-seed.sh admin@192.168.10.2 --overlay site            # Framework-Update (der Normalfall)
tools/upload-seed.sh admin@192.168.10.2 --overlay site --site     # zusätzlich die Site-Daten ersetzen
tools/upload-seed.sh admin@192.168.10.2 --overlay site --seed-inventory --bootstrap   # erstes Aufsetzen
```

* `--site` nennt vorher, welche Dateien auf dem Manager anders sind. Hast du dort etwas geändert
  (z.B. im cfm-Editor), hol es vorher mit `pull-site.sh`, sonst ist es weg.
* `--seed-inventory` lädt auch `meta/inventory.rsc`. Das ist nur beim allerersten Mal sinnvoll und
  bricht ab, sobald auf dem Manager echte Seriennummern stehen (`--force` überschreibt trotzdem).
* `--bootstrap [datei]` legt die Bootstrap-Datei ins Wurzelverzeichnis des Geräts (ohne Angabe:
  `bootstrap-manager.rsc` aus dem Overlay). Weitere Optionen: `--port`, `--base flash/cfm`.
* Notizen (`STAND.md`, `BEFUNDE.md`, CSV-Listen) bleiben lokal. Jede Datei geht einzeln mit bis zu
  drei Versuchen hinüber. Am Ende steht `Seed hochgeladen nach … (N Dateien)`.
* Danach auf dem Manager: `/system script run cfm-mgr`, dann `$cfmDiff` (was ist neu?) und
  `$cfmRelease msg="…"`. Läuft auf dem Manager noch Code von vor D70 (vor 2026-10-11), gilt bis
  zu seinem eigenen Update der Handgriff aus [TODO 47](../docs/TODO.md).

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
`:deserialize` umdeutet, Dateien über 60 KB und mehr.

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

Auf GitHub prüft zusätzlich die Action `rsc-check` (`.github/workflows/rsc-check.yml`) jeden Push.

## `editor/`

Zwei Werkzeuge für WebFig, die über die REST-API derselben Adresse arbeiten. Gestartet werden sie über ein
festes Lesezeichen „cfm“ (D91), das ihren Code vom Gerät lädt. Aus dem Netz wird nichts geladen.

* **cfm-Editor** (D73): Site-Daten auf dem Manager bearbeiten, prüfen, Diff zum Release, Probelauf,
  Release an Ring 0. Anmelden mit einem User der Gruppe `full`.
* **cfm-Monitor** (D77, D81; früher cfm-WLAN): Reiter WLAN mit den Clients je AP live und Roaming als
  Zeitleiste (in WebFig des CAPsMAN, Leserecht genügt); Reiter Suche findet Geräte nach MAC, IP, Name,
  Port, AP oder SSID (`$cfmFind`, in WebFig des Managers, Gruppe `full`).

So richtest du sie ein:

1. `tools/editor/install.html` im Browser öffnen (als lokale Datei) und den Knopf „cfm“ einmal in die
   Lesezeichen-Leiste ziehen.
2. WebFig öffnen (`http://<IP>/webfig/` des Managers bzw. des CAPsMAN), „cfm“ anklicken und anmelden
   (der Passwort-Manager trägt die WebFig-Daten ein). Auf dem Manager wählst du Editor oder Monitor, auf
   dem CAPsMAN startet gleich der Monitor. Der Browser merkt sich die Anmeldung bis zum Schließen.
   Voraussetzung: Dienst `www` (oder `www-ssl`) in `services`.

Den Code legt `tools/editor/build.py` nach `cfm/work/web/` (und baut `install.html`). Nach einer Änderung an
`cfm-editor.js` oder `cfm-monitor.js`: `build.py`, mit `upload-seed.sh` hochladen, releasen – das
Lesezeichen bleibt. Für Geräte mit einem Framework-Stand ohne `web/` stehen in `install.html` weiter die
vollständigen Lesezeichen (Code im Lesezeichen, nach jeder Fassung neu ziehen). Alte Lesezeichen
„cfm-Editor“, „cfm-Monitor“ und „cfm-WLAN“ kannst du danach löschen. Mehr im Admin-Guide, 8.1, 8.10, 8.11.

## `upgrade-mirror.py`

Ein Spiegel für das eingebaute RouterOS-Update (D63). Damit aktualisieren sich Geräte, die selbst
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
* Die Geräte müssen deinen Rechner auf Port 80 erreichen (Firewall des Rechners). Die Pakete sind
  von MikroTik signiert, RouterOS prüft das beim Installieren.

## `pcap-ziele.py`

Ein Gerät soll in eine Zone ohne Internet (z.B. IoT), braucht aber seine Cloud. Freigeben kannst du
sie mit einer `allow`-Liste in `global.rsc` (Admin-Guide, `policy`/`allow`) – vorher musst du wissen,
welche Namen und Ports das Gerät anspricht. Das Skript liest dazu einen Mitschnitt.

1. Mitschnitt aufnehmen, während das Gerät arbeitet (App bedienen, Programm starten), am besten
   einige Stunden: an einer Fritz!Box unter `http://fritz.box/html/capture.html` die Schnittstelle,
   an der das Gerät hängt (WLAN oder LAN); an einem MikroTik `/tool/sniffer` mit `file-name`.
2. Auswerten:

```bash
tools/pcap-ziele.py mitschnitt.eth --leases site/leases.rsc        # welche Geräte sind drin?
tools/pcap-ziele.py mitschnitt.eth --mac 02:00:00:00:00:AA --liste waschmaschine
```

Je Gerät siehst du die DNS-Anfragen, die Verbindungen ins Internet (Port, Adresse, Name aus DNS,
TLS oder HTTP) und im LAN, am Ende einen Vorschlag wie `"waschmaschine"={"api.example.com:tcp/443"}`.
Prüfe ihn: Einträge mit einer IP statt eines Namens können sich ändern. Liest pcap und pcapng, ohne
Fremdpakete. Verschlüsseltes QUIC (`udp/443`) zeigt nur die Adresse, den Namen dann aus den DNS-Anfragen.

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

Die Adresse passt zu `peers.<name>.addr` in `wireguard.rsc`. Mit VRRP ist der Endpoint die VIP des
WAN-VLANs, der Key ist auf allen Routern derselbe. Mehr dazu im Admin-Guide, Abschnitt 8.8.

## `git-host/cfm-git-sync`

Externe Sicherung (D13): Nach Release, Rollback, Promote, Audit, Onboarding, Vault-Backup und neuen
Geräte-Exporten ruft der Manager per SSH dieses Skript auf einem Linux-Server auf. Es holt den
Stand per SFTP und committet ihn in ein Git-Repo, auf Wunsch mit `git push`.

* Einrichtung einmalig, Schritt für Schritt im Kopf des Skripts: User `cfm` auf dem Server, Key des
  Managers als Forced Command in `~cfm/.ssh/authorized_keys`, ein SFTP-User `cfm-git` auf den
  Managern, `/etc/cfm-git-sync.conf`, in `global.rsc` `"hook"={"host"=…;"user"="cfm"}`.
* Von Hand auf dem Server: `cfm-git-sync manual`. Admin-Guide, Abschnitt 6.5.

## `home-assistant/cfm_ssid.py`

Schaltet eine schaltbare SSID (D64, D90, z.B. das Gast-WLAN) aus Home Assistant und fragt ihren
Zustand ab (an den WLAN-Interfaces). Es spricht direkt die RouterOS-API des CAPsMAN an.

```bash
cfm_ssid.py guest on | off | state | until
```

Die Zugangsdaten stehen in `cfm_ssid.json` neben dem Skript. Einbau in Home Assistant, Test und
Fehlersuche: [docs/home-assistant.md](../docs/home-assistant.md).

## `chr-lab/`

Das Testlabor startet RouterOS als virtuelle Maschinen und spielt ganze Abläufe durch (Aufnahme,
Release, Rollback, Onboarding, VRRP, MLAG …). Anleitung: [chr-lab/README.md](chr-lab/README.md).
