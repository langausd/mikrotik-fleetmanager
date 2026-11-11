# Netinstall-Station und Branding-Paket – Plan (DO1.8, DT3.3, TODO 79)

Stand 2026-11-11, entschieden vom Nutzer in der Fragerunde zur Nacht auf den 11.11. Noch nicht umgesetzt; Prototypen
liegen in [`tools/branding/`](../tools/branding/README.md). Hintergrund: [TODO.md](TODO.md) „Onboarding: weitere Wege“,
[DECISIONS.md](DECISIONS.md) DO1.1 (Push in die Werks-Config), DO1.8, DT3.3.

## 1. Ziel

1. **Reset-fest ins Onboarding:** Ein zurückgesetztes Gerät (Reset-Taster, `reset-configuration`, Neuinstallation)
   landet von selbst wieder in einem Zustand, in dem der Manager es ohne Aufkleber-Passwort übernimmt.
2. **Zero-Touch-Neuinstallation:** Ein neues oder verkorkstes Gerät wird am Onboarding-Port per Netinstall in einer
   festen RouterOS-Version samt Paketen und Branding neu installiert – ohne PC.
3. **cfm in der GUI:** Editor, Monitor und DNS-Selbstbedienung sind auf jedem Gerät über die WebFig-Login-Seite
   erreichbar, ohne Lesezeichen (DT3.3).

## 2. Bausteine

### 2.1 Branding-Paket (`.dpk`, ein Paket für alle Standorte)

Gebaut im mikrotik.com-Konto („Branding maker“); laut MikroTik-Doku für jede RouterOS-Version und Architektur
installierbar (prüfen: ein Paket je Architektur ist **nicht** nötig – offene Frage O1). Inhalt:

| Teil | Datei im Prototyp | Zweck |
|---|---|---|
| Router name `cfm` | – | Plattformname/Identity bis zum Onboarding (`cfm-new` setzt der Stub) |
| Default configuration | `cfm-stub.rsc` | der **cfm-Stub**: läuft nach jedem Reset (Abschnitt 2.2) |
| CAPs mode script | `caps-mode.rsc` | derselbe Stub, wenn der Reset-Taster das Gerät in den CAP-Modus setzt (PoE-Geräte, DO1.6) |
| WebFig login page | `webfig/index2.html`, `webfig/cfm.js`, `webfig/cfm.css` | Login plus Knopf „cfm“ (Abschnitt 2.4) |
| Skin | `skins/cfm-dns.json` | WebFig-Skin für die Gruppe `cfm-dns` (nur Logout und die REST-Anmeldung nötig) |
| Logo, ASCII-Logo, Manual URL | `logo/` | `mikrotik_logo.png` → cfm-Logo, Konsolen-Banner, Link auf den Admin-Guide |
| Optionen | – | „Hide Default configuration prompt“, „Hide default caps-mode-script“ (7.15+), „Do not run script on install“ **aus** (der Stub soll gleich laufen) |

Nutzungsbedingungen des Branding Makers vor dem ersten Bau lesen (O2).

### 2.2 Der cfm-Stub (Default-Config nach jedem Reset)

Minimal und in unter 2 Minuten (Grenze von RouterOS):

* Identity `cfm-new`, alle Ethernet-Ports in einer Bridge (wie die Werks-Config), **DHCP-Client** auf der Bridge
  (Onboarding-VLAN 88 vergibt `.100–.199`, DO1.4) und zusätzlich die feste Werksadresse `192.168.88.1/24`, damit der
  Manager das Gerät auf beiden Wegen findet (DO1.6).
* **Onboarding-Schlüsselpaar:** öffentlicher Schlüssel für `admin` per `/user/ssh-keys/import`; das Werks-Passwort
  (`$defconfPassword`) bleibt, wird aber nicht mehr gebraucht. Kein festes Passwort im Paket.
* Dienste: SSH an, alles andere aus; keine Firewall (das Onboarding-VLAN ist isoliert, DO1.4).
* Kein WLAN, kein CAPsMAN – der gerätespezifische Bootstrap (Stufe 2, DO1.5) räumt ohnehin alles ab
  (`reset-configuration no-defaults=yes` überspringt die Branding-Default-Config, `run-after-reset` führt den
  Bootstrap aus; ein späterer Reset-Taster-Druck führt wieder den Stub aus – genau der gewünschte Kreis).

**Wessen Schlüssel?** Der Manager spricht Werksgeräte heute per SFTP mit `admin` + Aufkleber-Passwort an
(`mgr-onboard.rsc`, `/tool/fetch sftp://…`). Mit Schlüssel geht nur `ssh-exec`, und das nutzt den privaten Schlüssel des
ausführenden Users (`cfm`) – je Manager ein eigener. Für **ein** generisches Paket müssen alle Manager denselben
Schlüssel haben. Zwei Wege (offene Frage O3):

* **A (empfohlen):** Ein gemeinsames Manager-Schlüsselpaar für `ssh-exec` an allen Standorten: `$cfmSecret
  key=onboard.key value=<privater Schlüssel>` im Vault, Bootstrap des Managers importiert ihn für `cfm` statt einen
  eigenen zu erzeugen (bestehende Manager: `$cfmTrust` verteilt den neuen öffentlichen Schlüssel an die Geräte, dann
  Import). Der öffentliche Teil steht im Stub. Ein Schlüssel für alle Standorte, dafür nur ein Paket.
* **B:** Das Paket enthält die öffentlichen Schlüssel **aller** Manager (Liste im Stub). Jeder neue Manager = neues
  Paket auf allen Geräten.

Manager-Seite (TODO 79): Stufe 1 des Pushs (`onboard-probe.rsc`) läuft per `ssh-exec` mit dem Schlüssel; nur wenn das
scheitert, wie bisher per SFTP mit dem Aufkleber-Passwort (Bestandsgeräte ohne Branding). `$cfmRegister` ohne `pw=`
wird damit der Normalfall.

### 2.3 Netinstall-Station: Container auf einem MikroTik

Gewählt: **Container auf dem Backup-Manager eines Standorts**, dort ist schon eine Speicherkarte eingebaut und ein
Container (Companion-Satellite) läuft – der darf nicht beeinträchtigt werden; später ggf. Umzug auf den VRRP-Master. Zweiter Standort: offen,
vorerst derselbe Container auf dem CRS418 (ARM64, braucht USB-Speicher) oder der Laptop.

Werkzeug: [tikoci/netinstall](https://github.com/tikoci/netinstall) (CC0): OCI-Image `ammo74/netinstall` (arm64,
arm, amd64), führt `netinstall-cli` per QEMU-Emulation aus, lädt Pakete selbst von MikroTik (`ARCH`, `PKGS`, `CHANNEL`
oder `VER`), `make service` = Dauerschleife, `tools/container-manager.sh` richtet VETH, Bridge-Port und Container per
REST ein (RouterOS ≥ 7.20).

Aufbau auf dem Backup-Manager:

* `container.npk`, `/system/device-mode` mit `container=yes` (Neustart mit Tasterdruck – vor Ort), Speicherort
  `disk1/netinstall` (Speicherkarte, **nicht** das Verzeichnis des Companion-Containers).
* Eigener VETH `veth-netinstall` **ohne IP** als Bridge-Port mit `pvid=88` (Onboarding-VLAN, untagged) – Netinstall
  arbeitet auf Layer 2 (BOOTP/TFTP). Der Container selbst setzt eine Link-Local-Adresse auf das Interface
  (`netinstall-cli -i`). cfm-Hostfile: Port-Profil `access:88` für den VETH? Der Bridge-Port des VETH ist ein Objekt
  ohne cfm-Tag (Audit) – entweder als `cfm-override` markieren oder ein Hostfile-Schlüssel `container`
  (TODO 79, O4). Der Companion-VETH bleibt, wie er ist.
* Umgebung (`/container/envs list=NETINSTALL`): `ARCH="arm64 arm"` (hAP ax², hAP be³, CRS418 = arm64; hAP ac² =
  arm), `PKGS="wifi-qcom wifi-qcom-ac"` (tikoci lädt je Architektur, was es gibt), `VER=7.25.1` (feste Version wie die
  Flotte, `rosMin`), `OPTS="-b -r"` → **`-r` ist falsch für uns:** wir wollen die Branding-Default-Config, also
  `OPTS="-r"` ohne `-b` (`-b` = Branding entfernen), und das `.dpk` liegt im Paketverzeichnis (Netinstall installiert
  alle Pakete dort; prüfen, ob tikoci Fremddateien im Download-Verzeichnis mitnimmt – O5).
  `MODESCRIPT` leer lassen (device-mode bleibt Standard; Container braucht nur der Manager).
* Pakete offline: Das Download-Verzeichnis des Containers aus dem Cache von `tools/upgrade-mirror.py`
  (`~/.cache/cfm-upgrade-mirror/routeros/<ver>/`) befüllen, dann braucht der Container kein Internet (das
  Onboarding-VLAN erreicht nur die MikroTik-Server, DO1.4 – das reicht auch für den Download durch den Container,
  wenn sein VETH eine Adresse hätte; ohne Adresse: vorher befüllen).
* Betrieb: Container nur bei Bedarf starten (`/container/start`), sonst gestoppt – ein laufender Netinstall-Server
  installiert **jedes** Gerät im Etherboot in VLAN 88 neu. Manager-Befehle (TODO 79): `$cfmNetinstall start|stop|status`
  (per `ssh-exec` auf den Container-Host), Meldung `ev=netinstall` an `notify.url`.
* Auslösen am Gerät: Reset-Taster beim Einschalten halten (Etherboot), oder bei einem laufenden cfm-Gerät
  `$cfmReinstall host=<n>` (TODO 79): `/system/routerboard/settings/set boot-device=try-ethernet-once-then-nand` und
  Neustart – das Gerät holt sich die Installation und bootet danach wieder von NAND. Mit `--mac`/`CLIENTIP` auf genau
  ein Gerät beschränken, wenn mehrere am VLAN hängen.

Ablauf danach: Netinstall installiert RouterOS + Pakete + `.dpk` → Neustart → Stub läuft (Default-Config) → DHCP in
VLAN 88 → Onboarding-Tick findet die Lease → Stufe 1 per Schlüssel → Stufe 2 (gerätespezifischer Bootstrap) →
`$cfmEnroll` → Apply. Für die Registrierung wie bisher Seriennummer + Name (`$cfmRegister` ohne `pw=`).

### 2.4 cfm auf der WebFig-Login-Seite (DT3.3)

Die Branding-Login-Seite ist der einzige Ort, an dem RouterOS eigenes JavaScript unter der Adresse des Geräts
ausliefert (`index2.html`, `assets/script.js` – Pflichtelemente `<form id="login">`, `<input id="name">`,
`<input id="password">`, `<div id="error">`; weitere JS/CSS-Dateien erlaubt, gleicher Pfad wie die Index-Datei).

Prototyp `tools/branding/webfig/`: MikroTiks `index2.html`/`script.js` bleiben (Login wie gewohnt), dazu `cfm.js`
und `cfm.css` mit einem Knopf „cfm“: Formulardaten per XHR an `/rest/system/identity` (wie das Lade-Lesezeichen,
DT3.1.1), Merker `cfmRestOk`, dann `web/cfm-*.js` aus `cfm/dl/web/` bzw. `cfm/work/web/` per `POST /rest/file/get`
laden und starten – dieselbe Logik wie `tools/editor/cfm-loader.js` (DT3.2), nur ohne Lesezeichen. Die Seite bleibt
die Login-Seite (kein WebFig dahinter); Editor, Monitor und DNS rendern ihre eigene Oberfläche darin. Für die
DNS-Selbstbedienung: Clients öffnen `http://<gateway>/`, klicken „cfm“, melden sich als `dns` an – fertig.

Grenzen: Nach einem Framework-Update kommt der Code weiter per Release (`web/`), die Login-Seite ändert sich nicht.
Die Lesezeichen bleiben als Rückfall (Geräte ohne Branding). HTTPS erst mit TODO 25.

### 2.5 Skin für `cfm-dns`

WebFig-Skin (JSON aus WebFigs „Design Skin“), der dem User der DNS-Selbstbedienung nur Logout zeigt. Zuweisung durch
die Rolle `router`: `/user/group set cfm-dns skin=cfm-dns`, sobald `skins/cfm-dns.json` auf dem Gerät liegt
(Branding legt Skins unter `skins/` ab). Ohne Skin landet der User in einem fast leeren WebFig – nur Komfort.

## 3. Reihenfolge der Umsetzung (TODO 79)

1. **Schlüsselfrage O3 entscheiden**, dann Manager: `onboard.key` im Vault, Bootstrap/`$cfmTrust` angepasst, Stufe 1 per
   `ssh-exec` mit Rückfall auf SFTP. Labor: `e2e-onboard.sh` mit einem Werksgerät, das den Schlüssel schon hat (den
   Stub von Hand importiert), ohne `pw=`.
2. **Branding-Paket bauen** (Prototyp-Dateien, Logo), auf ein Ersatzgerät (hAP ax², `reset-configuration` → Stub läuft?,
   Reset-Taster → Stub läuft?, CAP-Modus → Stub?), Login-Seite im Browser prüfen (Firefox/Chrome, Passwort-Manager).
   Befunde nach ROUTEROS-EIGENHEITEN.md.
3. **Onboarding über den Stub** auf Hardware: Gerät mit Paket, Reset, `$cfmOnboard` – ohne Aufkleber-Passwort.
4. **Netinstall-Container** auf dem Backup-Manager: device-mode, VETH in VLAN 88, Pakete aus dem Spiegel-Cache, `.dpk` dazu,
   Testinstallation des Ersatzgeräts per Reset-Taster/Etherboot; dann `$cfmNetinstall`/`$cfmReinstall`.
5. **Rollout:** Paket auf die Bestandsgeräte (Upload + Neustart je Gerät, über `$cfmUpgrade`-ähnlichen Weg oder von
   Hand, O6), Skin-Zuweisung in der Rolle, Doku (Admin-Guide 7.1, README Onboarding, DO1.8/DT3.3 auf „umgesetzt“).

## 4. Offene Fragen

* **O1** Ein `.dpk` für alle Architekturen? (Doku: „can be installed in any RouterOS version“, Architektur nicht genannt.)
* **O2** Nutzungsbedingungen des Branding Makers (Konto, Weitergabe).
* **O3** Onboarding-Schlüssel: gemeinsames Manager-Schlüsselpaar (A) oder Liste der Manager-Schlüssel im Paket (B)?
* **O4** VETH des Netinstall-Containers im Hostfile abbilden (Schlüssel `container`?) oder als `cfm-override`.
* **O5** Nimmt tikoci/netinstall ein `.dpk` im Download-Verzeichnis mit, und wie läuft es ohne `-b`?
* **O6** Verteilung des Pakets an Bestandsgeräte: Upload + Neustart je Gerät im Wartungsfenster (Vorschlag: Erweiterung
  von `$cfmUpgrade` um `dpk=`).
* **O7** Läuft die Login-Seite mit `cfm.js` in allen Browsern, die die Site nutzt (Passwort-Manager füllen das
  Formular, der Knopf liest es aus)?
