# cfm – Config-Framework für MikroTik-Flotten (RouterOS 7)

Minimalistisches, **auf MikroTiks selbst gehostetes** Config-Management für 5–20 Geräte.
Ein Template-Satz (Rollen) wird auf allen Geräten aktuell gehalten. Gerätespezifika und
lokale Ausnahmen bleiben möglich. Kein Ansible, kein Container, keine externe Abhängigkeit.

* **Source of Truth ist der Config-Manager** (ein MikroTik, z.B. RB5009/hAP ax³). Editiert wird dort
  in `cfm/work/`. `$cfmRelease` friert eine Version ein.
* **Pull + Push-Trigger:** Jedes Gerät holt per SFTP (Geräte-Key, kein Passwort) sein Manifest und
  bei Bedarf die Dateien. Der Manager stößt per `ssh-exec` sofort an.
* **Reconciler statt Befehlslisten:** Verwaltete Objekte tragen `comment="cfm:<key>"`. Was nicht mehr
  in den Daten steht, wird entfernt (VLAN löschen = Zeile löschen). Von Hand angelegte Objekte bleiben
  unangetastet und lassen sich per Audit anzeigen, als `cfm-override` markieren oder entfernen.
* **Sicherheitsnetz:** Rollout in Canary-Ringen 0 → 1 → 2. Vor jedem Apply wird ein Backup gezogen,
  ein Watchdog rollt zurück, wenn der Manager danach nicht mehr erreichbar ist. Fehlerhafte Versionen
  werden pro Gerät als `bad` gemerkt.
* **Secrets verlassen den Manager nie als Datei:** Der Vault liegt als deaktivierte `/ppp secret`
  (im Export ausgeblendet, im verschlüsselten Backup enthalten). Verteilt wird per SSH direkt in die
  Geräte-Config.
* **Rückkanal:** Der Manager holt von jedem Gerät Status (JSON) und aktive Config (`/export`, ohne
  Secrets) nach `state/<name>/`. Geräte haben am Manager nur Lesezugriff. Ein Hook stößt eine
  externe Git-Sicherung an.
* **WLAN:** Der wifi-CAPsMAN auf dem Config-Manager rendert alle SSIDs (lokales Forwarding mit VLAN,
  WPA2/WPA3, 802.11r/k/v). Ein Backup-CAPsMAN übernimmt per Netwatch.

Alle Design-Entscheidungen samt verworfener Alternativen stehen in [docs/DECISIONS.md](docs/DECISIONS.md).
**Für den Einsatz in der eigenen Flotte:** [docs/admin-guide.md](docs/admin-guide.md) (Planung,
Inbetriebnahme, tägliche Arbeit, Notfälle, eigene Templates, Befehlsreferenz).

## Architektur

```
                 ┌──────────────── cm1 (Primary-Manager, CAPsMAN aktiv) ─────────────────┐
  Admin ──SSH──▶ │ cfm/work/  ──$cfmRelease──▶ archive/v<N>/  +  live/m/<serial>.mf (MAC)│
                 │ meta/ (Inventar, Ringe, Keys)   state/<gerät>/ (Status, Export, Audit)│
                 │ Vault = /ppp secret cfm:*   Scheduler cfm-mgr-tick (Promote, Secrets) │
                 └───────▲──────────────┬──────────────────────┬─────────────┬───────────┘
         SFTP pull (Key) │   ssh-exec   │ Push-Trigger/Secrets │ Mirror      │ ssh-exec Hook
                         │              ▼                      ▼             ▼
     ┌──────────┐  ┌──────────┐  ┌──────────┐        ┌──────────────┐  ┌────────────┐
     │ rtr1     │  │ sw1      │  │ ap1..n   │  ...   │ cm2 (Backup) │  │ Git-Host   │
     │ router   │  │ switch   │  │ ap (CAP) │        │ read-only,   │  │ cfm-git-   │
     │ cfm-agent│  │ cfm-agent│  │ cfm-agent│        │ CAPsMAN pass.│  │ sync       │
     └──────────┘  └──────────┘  └──────────┘        └──────────────┘  └────────────┘
```

Ablauf pro Gerät (`cfm-agent`, beim Boot, alle 15 min, per Push):
Manifest holen (Fallback cm1 → cm2) → MAC prüfen → Dateien laden, SHA-512 prüfen → `backup save`
→ Watchdog scharf → `lib` + Daten + Hostfile + Rollen importieren → verwaiste Objekte entfernen
→ Erreichbarkeit bestätigen → Status/Export nach `cfm/out/` (der Manager holt sie jede Minute ab).

## Verzeichnisse

| Pfad (Projekt) | Zweck |
|---|---|
| `cfm/work/global.rsc` | globale Parameter, Zonen-Policy, Admin-User, Hook |
| `cfm/work/vlans.rsc` | VLAN-Tabelle (Zone, Subnetz, Gateway, DHCP) |
| `cfm/work/profiles.rsc` | Port-Profile (`trunk`, `trunk-ap`, `access:<vid>`, …) |
| `cfm/work/wifi.rsc` | SSIDs, Security-Defaults, Kanal-Pools, AP-Pinning |
| `cfm/work/roles/*.rsc` | Rollen `base`, `switch`, `ap`, `router`, `manager`, `manager-backup` |
| `cfm/work/hosts/<name>.rsc` | Gerätespezifika (+ optional `<name>.post.rsc`) |
| `cfm/work/lib/` | Reconciler (`lib.rsc`), Agent, Manager-Funktionen (Module `mgr-*.rsc`), Bootstrap-Rumpf |
| `cfm/meta/inventory.rsc` | Name → Seriennummer, Rolle(n), Ring, MGMT-IP |
| `site/` (privat, von Git ignoriert) | eigene Standortdaten als Overlay für `tools/upload-seed.sh --overlay site` |
| `bootstrap/bootstrap-manager.rsc` | Ersteinrichtung des Primary-Managers |
| `tools/upload-seed.sh` | Vorlage einmalig auf den Manager laden |
| `tools/rsc-check.py` | RouterOS-Fallen in `.rsc`-Dateien statisch finden; Pre-Commit-Hook `tools/git-hooks/`, GitHub Action `rsc-check` |
| `tools/git-host/cfm-git-sync` | externe Git-Sicherung (Forced Command auf einem Linux-Host) |
| `tools/chr-lab/` | Testlabor mit RouterOS-CHR in QEMU: `lab.sh`, Gesamttest `e2e.sh`, Onboarding-Test `e2e-onboard.sh`, Lab-Overlay `seed/` |

Auf dem Manager (`cfm/` bzw. `flash/cfm/`): `work/`, `meta/`, `archive/v<N>/`, `live/m/`, `state/<name>/`, `vault/`.

## Rollen

| Rolle | Inhalt |
|---|---|
| `base` (immer) | Identity, Bridge + VLAN-Filtering, Port-Profile, Bridge-VLAN-Tabelle, MGMT-VLAN/IP/Route, IP-Services nur aus MGMT, SSH-Härtung, Zeitzone/NTP/Syslog, Admin-User, Agent |
| `switch` | IGMP-Snooping, DHCP-Snooping (Trunks = trusted). Bewusst schlank. |
| `ap` | CAP des wifi-CAPsMAN (beide Manager als Adressen), Radios → `configuration.manager=capsman` |
| `router` | VLAN-Interfaces, Adressen (VRRP optional: `.250+routerId`, VIP `.gw`), DHCP (bei VRRP nur Master), Zonen-Listen, Firewall-Block mit Hook-Chains `local-input`/`local-forward`, NAT, DNS, NTP-Server |
| `manager` | Manager-Funktionen, SFTP-Gruppe, CAPsMAN aus `wifi.rsc` (Security, Datapath, Steering, Kanäle, Provisioning) |
| `manager-backup` | wie `manager`, CAPsMAN passiv (Netwatch übernimmt nach ~3 min), spiegelt den Primary, read-only |

Rollen sind kombinierbar (`"switch,manager"`, `"router,manager"`).

## Schnellstart

1. **Eigene Daten anlegen:** als privates Overlay `site/` (von Git ignoriert, gleiche Struktur wie
   `cfm/work` plus `meta/`): `global.rsc` (Manager-IPs, MGMT-VLAN, User), `vlans.rsc`, `wifi.rsc`,
   `hosts/` und `meta/inventory.rsc`. Vorlage sind die Dateien in `cfm/work/` und `cfm/meta/`; die
   Beispiele dort sind ein fiktives Netz (VLAN 10/20/30/40, 101–119, SSIDs Demo, Demo-Gast,
   Demo-Event, Demo-IoT).
2. **Primary-Manager:** `tools/upload-seed.sh admin@<cm1> --overlay site`, dann `bootstrap/bootstrap-manager.rsc`
   anpassen, hochladen, `/import bootstrap-manager.rsc`. Das Gerät setzt sich dabei zuerst auf eine
   leere Config zurück (`clean`), erzeugt danach Release v1 und enrollt cm1 selbst.
3. **Secrets:**
   `$cfmSecret key=user.netadmin value=…`, `$cfmSecret key=psk.main value=…` (je SSID-Key), `$cfmSecret key=vaultpw value=…`
4. **Weitere Geräte:** `$cfmBootstrap` erzeugt `cfm/cfm-bootstrap.rsc`. Datei aufs neue Gerät
   (Winbox → Files), IP/Uplink oben anpassen, `/import cfm-bootstrap.rsc`. Dann am Manager:
   `$cfmEnroll name=sw1 ip=192.168.10.21 role=switch ring=1`.
5. **Backup-Manager:** wie ein Gerät, mit `role=switch,manager-backup` enrollen.
6. **Git-Sicherung (optional):** siehe Kopf von `tools/git-host/cfm-git-sync`, dann `hook` in `global.rsc` setzen.

## Tägliche Arbeit (im Terminal des Managers, nach `/system script run cfm-mgr`)

| Aufgabe | Vorgehen |
|---|---|
| VLAN hinzufügen/ändern/löschen | `cfm/work/vlans.rsc` editieren → `$cfmRelease msg="VLAN 180"` |
| Vorher sehen, was sich ändert | `$cfmPlan host=sw1`: Probelauf gegen `work/`, das Gerät ändert nichts |
| Daten prüfen | `$cfmCheck` (läuft bei jedem `$cfmRelease`; Fehler stoppen das Release, `force=yes` übergeht sie) |
| SSID/PSK ändern | `wifi.rsc` → `$cfmRelease`; PSK: `$cfmSecret key=psk.<ssid> value=…` |
| Status der Flotte | `$cfmStatus` |
| Ring vorziehen | `$cfmPromote` (bzw. automatisch nach `ringSoak`) |
| Zurück auf alten Stand | `$cfmRollback ver=12 all=yes` |
| Sofort anwenden | `$cfmPush` / `$cfmPush host=sw1 force=yes` |
| Rückmeldungen sofort abholen | `$cfmCollect host=sw1` (sonst automatisch jede Minute) |
| Manager-Schlüssel neu verteilen | `$cfmTrust` (läuft beim Enroll automatisch) |
| Hand-Objekte finden | `$cfmAudit host=sw1` → `$cfmAudit host=sw1 op=mark sel=A2` / `op=purge sel=A5` |
| Gerät tauschen | Ersatz bootstrappen → `$cfmEnroll name=sw1 ip=…` (neue Seriennummer wird übernommen) |
| Manager-Ausfall | Geräte ziehen automatisch von cm2. Dauerhaft: `$cfmPromoteManager` auf cm2 |
| RouterOS aktualisieren | `$cfmUpgrade ver=7.25 ring=0` (sofort) bzw. `host=sw1 at="2026-10-01 02:00"` (einmaliges Wartungsfenster). Der Manager lädt vorher alle Pakete; ältere Zielversion = Downgrade. Übersicht: `$cfmUpgrade`, zurückziehen: `cancel=yes` |
| Geräteschlüssel erneuern | `$cfmRekey host=sw1` bzw. `all=yes` |
| Archiv verkleinern | automatisch nach jedem Release (`archiveKeep`), von Hand `$cfmArchivePrune keep=5` |
| Verkabelung prüfen, Netzplan | `$cfmLinks` (Soll einfrieren: `accept=yes`; Graphviz/CSV: `export=yes`) → `cfm/state/netzplan.md` |
| Zweite Passphrase mit eigenem VLAN (PPSK) | `wifi.rsc` → `ppsk`, Release, dann `$cfmSecret key=ppsk.<ssid>.<name> value=…` |
| WLAN-Kanäle der APs | `$cfmChannels` (Warnung bei gleichem Kanal an einem Switch) |

## Automatisches Onboarding (Push in die Werks-Config)

1. **Registrieren** (einmal pro Gerät, Seriennummer und Passwort vom Aufkleber), dazu
   `cfm/work/hosts/ap3.rsc` anlegen und `$cfmRelease`:
   `$cfmRegister name=ap3 serial=HG1234567 role=ap ring=1 ip=192.168.10.33 pw="<Aufkleber-Passwort>"`
2. **Port am Zielort freischalten:** `$cfmOnboard sw=sw1 port=ether5` (optional `name=ap3`).
   Der Port bekommt vorübergehend das Onboarding-VLAN 88 untagged, die normalen VLANs bleiben tagged.
3. **Gerät im Werkszustand** (oder nach einem Reset) dort einstecken bzw. einschalten.

Danach läuft alles im Manager-Tick (jede Minute):
Probe per `*.auto.rsc` mit dem Aufkleber-Passwort → Seriennummer prüfen → RouterOS-Update aus dem
Internet (das Onboarding-VLAN erreicht nur die MikroTik-Update-Server) → gerätespezifischer Bootstrap
per `reset-configuration no-defaults run-after-reset` → `$cfmEnroll` → erster Apply → der Port fällt
auf sein normales Profil zurück. Stand: `$cfmOnboardStatus`, Abbruch: `$cfmOnboardAbort`.

* Es läuft immer nur eine Sitzung gleichzeitig (alle Werksgeräte haben `192.168.88.1`).
* Ein Fail-safe-Timer auf dem Switch setzt den Port spätestens nach `onboard.timeout` + 10 min zurück.
* Unbekannte Seriennummern landen in `$cfmPending` und werden per `$cfmApprove` freigegeben.
* Router mit Werks-Config über einen LAN-Port anschließen (ether1 ist dort WAN mit Firewall).
  APs funktionieren im CAPs-Modus (DHCP-Client) oder mit `192.168.88.1`.
* Geräte mit PoE-Eingang nur an ether1 (hAP): im **CAPs-Modus** starten (Reset-Taster beim Einstecken
  des PoE-Kabels halten, bis die LED nach ~10 s dauerhaft leuchtet). Dann ist ether1 ohne Firewall
  per DHCP erreichbar, und das Onboarding läuft über den PoE-Port.
* Mit echter Hardware noch nicht getestet, siehe [docs/TODO.md](docs/TODO.md).

## Sicherheitsmodell (Kurzfassung)

* Geräte authentifizieren sich am Manager per **ed25519-Host-Key** (Onboarding exportiert ihn; der
  Manager importiert nur den Public Key für den User `cfmd-<name>`, Gruppe `ssh,ftp,read`).
* Der Manager steuert Geräte über den User `cfm` mit **seinem** Key (Push, Secrets, Audit, Enroll).
* Geräte haben am Manager **nur Lesezugriff** (Schreiben würde `write` erfordern und damit
  SSH-Konfigurationsrechte). Status und Export holt der Manager selbst ab.
* Jedes **Manifest ist per MAC** mit einem gerätespezifischen Schlüssel (`cfm:key` / Vault
  `mac.<serial>`) gesichert und nennt die SHA-512 aller Dateien. Manipulierte Dateien (z.B. auf
  einem Spiegel) werden verworfen.
* `$cfmTrust` verteilt die Schlüssel aller Manager an die Geräte (läuft automatisch beim Enroll),
  damit auch ein später hinzugekommener Backup-Manager im DR-Fall steuern kann.
* Status-Dateien der Geräte werden am Manager nur als JSON gelesen, nie ausgeführt.
* Der Werks-User `admin` wird abgeschaltet, sobald auf einem Gerät ein eigener Admin-User aktiv ist
  (`adminUser` in `global.rsc`, Ausnahmen pro Gerät im Hostfile).
* Vor jedem Secret-Push beweist das Gerät per **Challenge-Response**, dass es seinen Geräteschlüssel
  kennt. Ein Gerät, das sich nur unter der IP ausgibt, bekommt keine Secrets.
* **Minimale Firewall** auf Switches, APs und Managern: nur Antworten, ICMP und Management-Netze
  (MGMT, `mgmtAccess`, `mgmtExtra`), Rest wird begrenzt geloggt (`cfm-drop`) und verworfen. IPv6
  auf allen Geräten nur ICMPv6 und Link-Local aus dem MGMT-VLAN. Eigene Regeln: Chain `local-input`.
* RouterOS-Pakete lädt nur der Manager; Geräte holen sie per SFTP, RouterOS prüft die Signatur.
* Die Nachbarsuche (LLDP/MNDP/CDP) läuft auf allen Bridge-Ports, auch an Access-Ports: Endgeräte
  sehen Modell, Version und Identität des Switches (bewusste Entscheidung für den Netzplan, D33).

## Grenzen & Hinweise

* Einzelne Dateien < 60 KB (`/file get`-Grenze), das prüft `$cfmRelease`.
* **Bestandsgeräte:** Vor dem ersten Apply `$cfmAudit` laufen lassen. Alte Bridge-VLAN-Einträge mit
  mehreren VIDs kollidieren sonst mit den verwalteten Einträgen (per `op=purge` entfernen).
* RouterOS ≥ 7.21 empfohlen (getestet mit 7.24.2 CHR). Ab 7.24 brauchen Skripte, die aus Winbox
  gestartet `ssh-exec` nutzen, ggf. `dont-require-permissions=yes`.
* Das CHR-Labor testet alles außer echten Funkteilen (CAPsMAN-Config ja, Radios nein).
* `$cfmPlan` überspringt `hosts/*.post.rsc` (dort sind beliebige Befehle erlaubt). Direkte Befehle in
  eigenen Rollen nur mit `:if ($cfmDry != true) do={ … }`, sonst würde der Probelauf sie ausführen.
* RouterOS-Pakete brauchen ca. 20 MB pro Architektur und Version (`pkgPath` für USB/NVMe). Sie
  werden nicht auf den Backup-Manager gespiegelt; offene Aufträge brauchen den Primary.
* **Eigene Templates schreiben:** Objekte mit `$cfmEnsure m=<menü> k=<key> p=({…})` anlegen
  (verwaltet inkl. Aufräumen), Singletons/Built-ins mit `$cfmSet`. Funktionen als Anweisung **ohne**
  eckige Klammern aufrufen: Eine Zeile, die mit `[` beginnt, liest RouterOS u.U. als Fortsetzung
  der vorigen Anweisung. Außerdem kein `\"\"` in String-Argumenten (`:parse` akzeptiert es, `/import`
  nicht). `$cfmRelease` prüft nur mit `:parse`, im Zweifel im CHR-Labor testen. Details im Kopf von
  `cfm/work/lib/lib.rsc`.
