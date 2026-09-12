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

* Onboarding-Push gegen echte Werks-Configs: Router (ether1 = WAN mit Firewall), CRS-Switches,
  APs im CAPs-Modus, Geräte mit Aufkleber-Passwort und `flash/`-Verzeichnis
* echte Funkteile (CAPs), VRRP mit zwei Routern, CAPsMAN-Übernahme durch den Backup-Manager
* Hook Manager → Git-Host per `ssh-exec` (die Pull-Seite `cfm-git-sync` ist getestet)

## Verbesserungsplan (Stand 2026-09-12)

Reihenfolge: 0 → 1 → 2, 3, 4 → 6, 7 → Rest nach Bedarf.

**0. Pilotbetrieb mit echter Hardware** – ein Gerät je Typ (Router, Switch, AP, Manager); deckt
die oben genannten ungetesteten Punkte ab. Größter Risikominderer vor jedem neuen Feature.

### Kurzfristig (großer Nutzen, wenig Aufwand)

1. **`manager.rsc` aufteilen** (Kern, Onboarding, Automatik …) – *in Arbeit.* Die Datei hat
   53 KB; RouterOS liest per `/file get` nur etwa 60 KB, und `$cfmRelease` lehnt größere Dateien ab.
2. **Benachrichtigungen** (E-Mail oder Push-Dienst wie ntfy/Telegram) bei Fehler/Rollback, stummen
   Geräten, gescheitertem Onboarding, CAPsMAN-Übernahme durch den Backup-Manager.
3. **Archiv aufräumen:** z.B. die letzten 10 Versionen plus alle von Ringen genutzten behalten,
   damit der Flash des Managers nicht vollläuft (jede Version ≈ 150 KB).
4. **Prüfskript für RouterOS-Fallen** (Zeile beginnt mit `[`, `\"` in Argumenten, `:return` in
   `:onerror`, Slash-Syntax für geräteabhängige Menüs) als Git-Pre-Commit-Hook und in einer
   CI-Pipeline; dort zusätzlich `:parse` und, wo KVM verfügbar ist, `e2e.sh`.
5. **Inhaltliche Prüfung beim Release:** VLANs aus Profilen/`wifi.rsc` vorhanden, Zonen aus
   `policy` vorhanden, keine doppelten MGMT-IPs, Hostfile zu jedem Inventar-Eintrag.

### Mittelfristig

6. **Plan-Modus `$cfmPlan host=<n>`:** Gerät zeigt, was ein Apply ändern würde, ohne es auszuführen.
7. **RouterOS-Versionspflege in Ringen:** Zielversion in `global.rsc`, Rollout über die Canary-Ringe.
8. **Identitätsprüfung vor dem Secret-Push** (Gerät beweist Kenntnis seines Geräteschlüssels,
   da Host-Schlüssel nicht geprüft werden) und regelmäßige Erneuerung der Schlüssel.
9. **Minimale Firewall auf allen Geräten** (Switches/APs haben bisher nur die Dienst-Adressfilter).
10. **Link-Bündel (Bonding/LACP) als Port-Profil** für Uplinks.
11. **Feste DHCP-Leases und DNS-Namen aus zentralen Daten** (z.B. `leases.rsc`).
12. **Effektive Config und Diff anzeigen:** `$cfmShow host=<n>`, `$cfmDiff ver=A ver=B`.

### Größere Ausbauten

13. **IPv6** (Präfixe je VLAN, Router Advertisements, IPv6-Firewall).
14. **Zentrale Admin-Anmeldung per RADIUS** (User Manager auf dem Manager).
15. **WireGuard-Rolle** (Fernzugang, Standortkopplung; Schlüssel aus dem Vault).
16. **WLAN-Ausbau:** WPA-Enterprise, mehrere PSKs mit eigenem VLAN, automatische Kanalplanung.
17. **Verkabelung prüfen per LLDP:** Nachbarn gegen Hostfiles abgleichen, Netzplan erzeugen.
18. **Optional Git als Arbeitsort** mit Review vor dem Release – bewusste Alternative zu D4,
    z.B. bei mehreren Admins.
