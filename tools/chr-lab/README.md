# CHR-Testlabor (`tools/chr-lab/`)

Das Labor startet RouterOS als **CHR** (Cloud Hosted Router) in virtuellen Maschinen (QEMU/KVM) auf
deinem Linux-Rechner und spielt damit ganze Abläufe von cfm durch: Aufnahme, Release, Probelauf,
Rollback, Backup-Manager, Onboarding, VRRP, MLAG und mehr. Ein Lauf meldet jede Prüfung mit ✔ oder ✘.
Funkteile gibt es auf CHR nicht. WLAN prüft das Labor nur auf Darstellung und Konfiguration.
Hintergrund: D20 in [DECISIONS](../../docs/DECISIONS.md), Admin-Guide Abschnitt 12.

## 1. Voraussetzungen

* Linux mit KVM: `/dev/kvm` muss existieren, und dein User muss es benutzen dürfen (meist Gruppe
  `kvm`: `sudo usermod -aG kvm $USER`, danach neu anmelden).
* Pakete (Debian/Ubuntu): `qemu-system-x86 qemu-utils openssh-client python3 netcat-openbsd`.
* Arbeitsspeicher: 256 MB je VM (`MEM`), je nach Test 3 bis 5 VMs. Platz: unter 1 GB in `~/.cache`.
* Internet: Der Gesamttest lädt in einem Schritt ein RouterOS-Paket (rund 20 MB) von MikroTik.

## 2. CHR-Image holen

Das Labor nimmt das neueste `chr-*.img` im Labor-Verzeichnis (Standard `~/.cache/cfm-chr-lab`):

```bash
mkdir -p ~/.cache/cfm-chr-lab && cd ~/.cache/cfm-chr-lab
wget https://download.mikrotik.com/routeros/7.24.5/chr-7.24.5.img.zip   # "Raw disk image" der Download-Seite
unzip chr-7.24.5.img.zip
```

Die VMs schreiben nur in eigene Overlay-Disks (`vm<n>.qcow2`), das Image selbst bleibt unverändert.
Weitere Versionen (rc, beta) legst du besser außerhalb ab, z.B. in `~/.cache/cfm-chr-img/`, und wählst sie
mit `CHR_IMG`: Im Labor-Verzeichnis würde sonst die höchste Version zum Standard.
Absichtlich liegt alles in `~/.cache`, nicht im (vielleicht synchronisierten) Projektverzeichnis.

## 3. Erste Schritte

```bash
cd tools/chr-lab
./lab.sh start 3      # drei VMs starten (vm1 zuerst, sie ist der zentrale "Switch")
./lab.sh status       # vm1 up (port 2210) …
./lab.sh ssh 1        # RouterOS-Terminal von vm1, beenden mit "quit"
./lab.sh ssh 2 '/system/identity/print'   # einzelner Befehl
./lab.sh stop         # alle VMs stoppen
```

Netz: Jede VM hat `ether1` am QEMU-Netz des Rechners (SSH-Weiterleitung auf Port 2200 + 10·n). vm1
ist mit `ether2`, `ether3` … sternförmig mit den anderen VMs verbunden. Die Testskripte starten und
stoppen die VMs selbst, `lab.sh` brauchst du nur zum Nachsehen.

## 4. Die Testläufe

| Aufruf | VMs | Dauer | Was geprüft wird |
|---|---|---|---|
| `./e2e.sh fresh` | 3 | ~80 min | Gesamttest: Aufnahme, Firewall, Probelauf, Prüfung, Rollback, Backup-Manager, Router, Leases, Bandbreitenlimit, Archiv, Schlüsselwechsel, RouterOS-Update (auch vom Spiegel), Netzplan, Gerätesuche, PPSK, WLAN-Daten, Bestandsgeräte, CAPsMAN-Umzug, Watchdog, Admin-Keys, Benachrichtigungen … |
| `./e2e-onboard.sh fresh` | 3 | ~10 min | automatisches Onboarding eines „Werksgeräts“ (192.168.88.1) |
| `./e2e-onboard.sh fresh dhcp` | 3 | ~10 min | dasselbe im CAPs-Modus (DHCP-Client, wie ein hAP an PoE) |
| `./e2e-onboard.sh fresh manual` | 3 | ~10 min | Switch, den cfm nicht verwaltet (`$cfmOnboard manual=yes`) |
| `./e2e-vrrp.sh` | 5 | ~15 min | drei VRRP-Router hinter einem Internet-Router, dazu ein Switch mit eigenem Ausgang: Failover, kurzer Master-Ausflug, Zonen, NAT, DHCP/DNS im LAN = WAN, WireGuard |
| `./e2e-mlag.sh` | 5 | ~15 min | LACP-Bonds, MLAG-Paar, Ausfall eines Links, isolierte VLANs |

`fresh` setzt die VM-Disks neu aus dem Image auf. Ohne `fresh` laufen die VMs mit dem Stand des
letzten Laufs weiter, das ist nur zum Nachstellen gedacht. `e2e-vrrp.sh` und `e2e-mlag.sh` setzen
immer neu auf.

## 5. Ergebnis lesen

```
== 9. Rolle router auf sw1 (über den echten Agent-Pfad)
  ✔ sw1 als switch,router angewendet
  ✔ sw1: Zonen-Firewall-Block
  ✘ sw1: VRRP je VLAN
…
Ergebnis: 297 ok, 1 fehlgeschlagen
```

* `==` leitet einen Schritt ein, jede Zeile darunter ist eine Prüfung. Die letzte Zeile zählt alles
  zusammen. Der Rückgabewert ist 0 nur ohne Fehlschlag.
* Ausgabe sichern und Fehlschläge suchen: `./e2e.sh fresh 2>&1 | tee ~/e2e.log`, danach `grep ✘ ~/e2e.log`.
* Ein einzelnes ✘ kann am Timing liegen, z.B. wenn der Rechner gleichzeitig ein zweites Labor
  rechnet. Erst wiederholen, dann nachforschen.
* Nach dem Lauf laufen die VMs weiter, damit du nachsehen kannst (`./lab.sh ssh 2 '/log/print'`).
  Danach `./lab.sh stop`.

## 6. Andere RouterOS-Version, zwei Labore

```bash
CHR_IMG=~/.cache/cfm-chr-img/chr-7.25rc2.img ./e2e.sh fresh        # bestimmtes Image
LAB=~/.cache/cfm-chr-lab-b LABPORT=2300 LABSOCK=13000 CHR_IMG=~/.cache/cfm-chr-lab/chr-7.24.5.img ./e2e.sh fresh
```

Ein zweites Labor gleichzeitig braucht ein eigenes Verzeichnis (`LAB`) und eigene Port-Basen
(`LABPORT` für SSH, Standard 2200; `LABSOCK` für die Verbindungen der VMs, Standard 12000). Das
Image darf es mit dem ersten teilen. `./lab.sh stop` und `status` brauchen dieselben Variablen.

## 7. Wichtig

* **Ein laufendes `e2e*.sh` nie bearbeiten:** bash liest das Skript stückweise, eine Änderung
  mitten im Lauf führt zu sinnlosen Fehlern. Für lange Läufe aus einer Kopie starten, z.B. mit dem
  letzten Commit: `mkdir -p /tmp/cfm-lauf && git archive HEAD | tar -x -C /tmp/cfm-lauf`, dann
  `cd /tmp/cfm-lauf/tools/chr-lab && ./e2e.sh fresh` (mit nicht committeten Änderungen: `cp -a` des Repos).
* Getestet wird der Stand des Verzeichnisses, aus dem du startest, samt nicht committeter Änderungen.
* Auch nach einem Abbruch (Strg+C) laufen die VMs weiter: `./lab.sh stop`.
* Die Labor-Daten liegen in `seed/` (Gesamttest und Onboarding), `seed-vrrp/` und `seed-mlag*/`.
  Sie werden wie ein Site-Overlay über `cfm/work/` gelegt. Die Hostfiles setzen `adminUser="keep"`,
  weil sich `lab.sh` als `admin` anmeldet (Schlüssel `$LAB/lab_key`).

## 8. Weitere Stellschrauben

| Variable | Wirkung |
|---|---|
| `MEM` | Arbeitsspeicher je VM in MB (Standard 256) |
| `LABNIC` | Netzwerkkarte der VM-Verbindungen (Standard `virtio-net-pci`; `e2e-mlag.sh` setzt `e1000`, weil LACP mit virtio nur einen Port bündelt) |
| `LABLINKS` | eigene Verkabelung statt Stern, z.B. `"1-2 2-3 2-3"` (ein Paar VM-Nummern je Kabel, kleinere zuerst) |

`notify-sink.py` ist ein kleiner Empfänger für Benachrichtigungen (D66), auch zum Ausprobieren:
`./notify-sink.py 8099 /tmp/meldungen.jsonl` schreibt jede Meldung als JSON-Zeile in die Datei. Die
VMs erreichen deinen Rechner als `10.0.2.2`, also `notify.url` = `http://10.0.2.2:8099/`.

## 9. Fehlersuche

| Meldung | Ursache und Abhilfe |
|---|---|
| `CHR-Image fehlt` | kein `chr-*.img` in `$LAB` und kein `CHR_IMG` gesetzt (Abschnitt 2) |
| `Could not access KVM kernel module` / `Permission denied` auf `/dev/kvm` | KVM fehlt oder der User ist nicht in der Gruppe `kvm` |
| VM startet nicht, Port belegt | ein anderes Labor läuft noch: `./lab.sh status`, `./lab.sh stop`, oder eigene `LABPORT`/`LABSOCK` |
| Update-Schritt scheitert | kein Internet auf dem Rechner (die VMs laden über ihn) |
| Schritt mit dem Spiegel scheitert | `nc` fehlt (die VMs erreichen den Spiegel über eine Weiterleitung mit `nc`) |
