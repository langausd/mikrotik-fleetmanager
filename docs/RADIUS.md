# 802.1X am Kabel-Port mit RADIUS – Konzept (TODO 65b, Grundlage für 14 und 16)

Stand 2026-11-22, Entwurf aus der Nachtschicht, **noch nicht entschieden und nicht umgesetzt**. Auftrag des Nutzers:
den User Manager von RouterOS und PacketFence in einem externen Container vergleichen, den User Manager genauer planen,
Ziel zuerst 802.1X am gemeinsamen Dock-Port (65b). Offene Fragen an den Nutzer: [Abschnitt 7](#7-offene-fragen).
Hintergrund: [TODO.md](TODO.md) 14, 16, 65; [DECISIONS.md](DECISIONS.md) DP1.4 (umschaltbarer Port als Rückfall).

## 1. Ziel und Ausgangslage

An einer Dockingstation hängen zeitweise zwei Laptops: der Admin-Laptop (ungetaggt Haupt-VLAN, getaggt die übrigen
VLANs, auch MGMT) und ein Firmen-Laptop, der nur ins Gäste-VLAN darf. Das Dock sendet ohne MAC-Passthrough für beide mit
**seiner eigenen MAC** – ein Unterschied nach MAC (Switch-Regel, `mac-auth`) trägt deshalb nicht. Heute schaltet der
Port per Skript, Taster oder Home Assistant um (DP1.4); das soll von selbst gehen.

Mit 802.1X meldet sich das Gerät mit einem Zugangsnamen (EAP) an, nicht mit seiner MAC: Der Admin-Laptop bekommt nach
der Anmeldung sein VLAN, alles andere landet im Gast- oder Reject-VLAN.

## 2. Vergleich: User Manager oder PacketFence

| | User Manager (RouterOS-Paket `user-manager`) | PacketFence (externer Dienst) |
|---|---|---|
| Betrieb | Zusatzpaket auf dem cfm-Manager (auch CHR), 0,4 MB; Daten in SQLite auf dem Flash | laut Hersteller eigene VM: 4 Kerne, **16 GB RAM**, 200 GB, Debian 12 oder RHEL 8 (AppArmor aus); nutzt intern Docker, aber kein einzelner Container zum Mitnehmen |
| Verwaltung aus cfm | per RouterOS-Befehlen wie alles andere (`$cfmEnsure` unter `/user-manager`); Secrets aus dem Vault | eigene Oberfläche/REST-API, eigene Datenbank – zweite Quelle der Wahrheit neben cfm |
| EAP | PEAP-MSCHAPv2, EAP-TTLS (PAP/CHAP/MSCHAP), EAP-TLS; MAC-Auth über PAP | alles, dazu Portal, Geräteerkennung (Fingerprinting), Quarantäne, Registrierung |
| VLAN je Anmeldung | Gruppen-Attribute `Tunnel-Type:13,Tunnel-Medium-Type:6,Tunnel-Private-Group-ID:<vid>` | ja, regelbasiert |
| Ausfall | läuft auf dem Manager; Backup-Manager kann einen zweiten User Manager führen | eigener Dienst, eigene Hochverfügbarkeit |
| Passt zu cfm | gut: gleiche Werkzeuge, gleiche Prüfung (`$cfmCheck`), Labor auf CHR möglich | schlecht: Größe und Betrieb übersteigen den Zweck (ein Dock-Port, später WPA-Enterprise) |

**Empfehlung: User Manager.** PacketFence lohnt erst mit Hunderten Ports, Gästeportal und Geräteerkennung.

## 3. Laborbefunde (CHR 7.25.1, 2026-11-22)

Aufbau: vm1 mit User Manager (Zertifikat aus eigener CA) und `/interface/dot1x/server` an `ether2` (Bridge mit
`vlan-filtering=yes`, RSTP, PVID 99, VLAN 30 statisch getaggt am Port), vm2 als Supplicant (`/interface/dot1x/client`).
Gruppen: `haupt` → VLAN 10 (PEAP/TTLS), `gast` → VLAN 20 (MAC-Auth); Reject-VLAN 40.

| Fall | Ergebnis |
|---|---|
| A Ohne Dot1X-Server | nur das getaggte VLAN 30 erreichbar (PVID 99 leer) |
| B Server an, noch keine Anmeldung | **alles gesperrt**, auch das getaggte VLAN 30 |
| B MAC unbekannt (kein Supplicant, Fallback nach 3 × `retrans-timeout`) | Access-Reject → Reject-VLAN 40 ungetaggt, **VLAN 30 getaggt wieder offen** |
| C MAC im User Manager (Gruppe `gast`) | `mac-auth`, VLAN 20 |
| D PEAP `admin1` (Supplicant vertraut der CA) | VLAN 10 ungetaggt, VLAN 30 getaggt |
| E PEAP mit falschem Passwort | Reject-VLAN 40, VLAN 30 offen |
| F Supplicant vertraut der CA nicht (z.B. Firmen-Laptop mit eigenem 802.1X-Profil) | TLS bricht ab, **kein** Access-Reject: Port bleibt ganz gesperrt – kein Reject-, Gast- oder MAC-Fallback, solange das Gerät auf EAPOL antwortet |
| G Angemeldeter Supplicant verschwindet, Link bleibt oben, `reauth-timeout=30s` | Re-Auth ohne Antwort → Fallback `mac-auth` (VLAN 20); beim nächsten Re-Auth zählte der User Manager die MAC als **zweite Sitzung** (`shared-users=1`) → Reject-VLAN |

Weitere Beobachtungen: Der RouterOS-Supplicant prüft das Server-Zertifikat (ohne importierte CA: `ssl: no trusted CA
certificate found`). Zu Beginn jeder EAP-Anmeldung lehnt der User Manager einmal „PAP auth not allowed“ ab, danach läuft
PEAP normal. Zum Trennen per CoA erreichte der User Manager den Authenticator nicht („NAS not responding“) – dafür
braucht das Gerät `/radius/incoming accept=yes`.

**Folgen für den Entwurf:**

1. **Am Dot1X-Port keine statisch getaggten VLANs**, sonst kommt jedes abgewiesene Gerät per Tag hinein (B, E). Der
   Admin-Laptop bekommt am Dock nur sein ungetaggtes VLAN vom RADIUS; MGMT erreicht er geroutet (Firewall-Regel für
   seine Adresse) oder über WLAN/Konsole wie heute im alt-Zustand von DP1.4. → Frage 1.
2. **Firmen-Laptop mit eigenem 802.1X-Profil** sperrt den Port (F). Hat er keins, greift der Fallback nach ~3 ×
   `retrans-timeout`. → Frage 2; sonst bleibt der Umschalter DP1.4 als Rückfall.
3. **Link bleibt beim Wechsel am Dock oben?** Dann gilt die alte Anmeldung weiter, bis `reauth-timeout` abläuft (G) –
   der Firmen-Laptop säße so lange im Haupt-VLAN. `reauth-timeout` kurz (60 s) oder Hardware-Test, ob das Dock den
   Link beim Abziehen trennt. → Frage 3.
4. MAC-Einträge im User Manager mit `shared-users` > 1 (oder unbegrenzt), sonst Reject beim Re-Auth (G).

## 4. Entwurf für cfm

### 4.1 Daten

* **`global.rsc`** (Entwurf):

```
"radius"={"server"="manager";"dot1x"={"dock"={"guest"="guest";"reject"="guest";"reauth"="60s";"macAuth"="no"}}};
```

  `server`: `"manager"` = User Manager auf dem Primary (Backup als zweiter Server, 4.4) oder eine Adresse.
  `dot1x.<Profil>`: VLANs als Zone oder VID wie in `ports`; `guest` = kein Supplicant, `reject` = abgewiesen,
  `macAuth` = MAC-Auth vor dem Gast-VLAN versuchen.
* **`profiles.rsc`**: neues Port-Profil `"dot1x"={"dot1x"="arg";"edge"="yes"}` – im Hostfile
  `ports={"ether5"="dot1x:dock"}`. Ohne `tag` (Folge 1); PVID unwichtig, der Port ist bis zur Anmeldung gesperrt.
* **`radius.rsc`** (neue Site-Datei, nur Manager): Benutzer und Gruppen.

```
:global cfmRadius {
  "groups"={"admin"={"vlan"="lan";"eap"="peap"};"gast"={"vlan"="guest";"mac"="yes"}};
  "users"={"admin-laptop"={"group"="admin"};"02:00:00:00:00:aa"={"group"="gast"}}
}
```

  Passwörter nur im Vault (`radius.<user>`, `$cfmSecret`), das gemeinsame RADIUS-Secret als `radius.secret`.

### 4.2 Rollen

* **Manager** (Feature-Modul, nur wenn `radius.rsc` Benutzer hat): Paket `user-manager` vorausgesetzt (`$cfmCheck`
  meldet es, `$cfmUpgrade` kennt Zusatzpakete), `/user-manager set enabled=yes certificate=cfm-radius`, je Gerät mit
  Dot1X-Port ein Eintrag unter `/user-manager/router` (Adresse aus dem Inventar, Secret aus dem Vault), Gruppen mit den
  VLAN-Attributen, Benutzer; MAC-Benutzer mit Passwort = MAC und `shared-users=unlimited`. Benutzer, die cfm nicht
  kennt, bleiben (Handeinträge wie sonst auch nur im Audit).
* **Switch/Router mit Dot1X-Port** (`base`, Feature-Modul): `/radius add service=dot1x address=<Manager> secret=…`
  (Kommentar `cfm:rad`), `/radius/incoming set accept=yes` (CoA), `/interface/dot1x/server` je Port mit
  `auth-types=dot1x` (plus `mac-auth` bei `macAuth`), `guest-vlan-id`, `reject-vlan-id`, `reauth-timeout`,
  `interim-update=5m`. Die VLANs müssen auf der Bridge existieren (statisch nur `tagged=<bridge>`/Uplinks, das
  ungetaggte Mitglied trägt RouterOS dynamisch ein).
* **Firewall**: UDP 1812/1813 von den Geräten zum Manager, 3799 vom Manager zu den Geräten (MGMT-Zone).
* **`$cfmCheck`**: Profil `dot1x:<x>` nur mit Eintrag in `radius.dot1x`; am selben Port keine `tag`; `guest`/`reject`
  sind bekannte VLANs; Benutzer mit unbekannter Gruppe; fehlendes Paket; Bridge ohne STP (laut MikroTik nötig, sonst
  kommen EAP-Frames nicht an – `stp=none`-Geräte ablehnen).

### 4.3 Zertifikate

Eigene CA auf dem Manager (`/certificate add … key-usage=key-cert-sign,crl-sign`, `sign`), daraus das
Server-Zertifikat `cfm-radius` (10 Jahre, `days-valid=3650`). Die CA als `.crt` zum Herunterladen
(`cfm/out/radius-ca.crt`) – der Laptop braucht sie (NetworkManager: „PEAP, MSCHAPv2, CA-Zertifikat“). Verlängerung: Warnung
in `$cfmCheck` 60 Tage vor Ablauf. Alternative EAP-TLS mit Client-Zertifikat (sicherer, kein Passwort, aber
Zertifikat je Laptop erzeugen und exportieren) → Frage 4.

### 4.4 Backup-Manager

Die User-Manager-Daten sind aus `radius.rsc` und dem Vault vollständig herstellbar; der Backup-Manager führt dieselbe
Rolle (eigene Kopie, gleiche CA aus dem Vault) und steht als zweiter `/radius`-Eintrag in den Geräten. Sitzungen und
Accounting bleiben je Manager getrennt (nur Statistik).

### 4.5 Hardware

Dynamische VLANs am Port setzt der Switch-Chip nur bei hardware-offloaded VLAN-Filtering um, sonst die CPU. Ob der
Dock-Port (hAP be³ Media) das im Chip kann, ist offen → Hardware-Test. Dot1X fehlt nur auf SMIPS-Geräten (hAP lite,
hAP mini).

## 5. Umsetzungsschritte (Vorschlag)

1. Entscheidungen (Abschnitt 7), dann DECISIONS-Eintrag.
2. Code: Manager-Modul `manager.radius`, Gerätemodul `base.dot1x`, Profil `dot1x`, `$cfmCheck`, Admin-Guide-Kapitel.
3. Labor: `e2e.sh` mit User Manager auf cm1 (Paket in `tools/chr-lab/` wie die übrigen Pakete), Dot1X-Port an sw1,
   Supplicant auf einer weiteren VM – Fälle A–G aus Abschnitt 3 als Prüfungen.
4. Hardware: Dock-Port an einem Standort, beide Laptops, Wechsel am Dock (Link oben?), Re-Auth; Umschalter DP1.4
   bleibt bis dahin.
5. Danach WPA-Enterprise (16) mit denselben Benutzern und Gruppen (`Mikrotik-Wireless-VLANID` bzw. Tunnel-Attribute am
   CAPsMAN) und Admin-Anmeldung per RADIUS (14).

## 6. Rückbau

Profil `dot1x` aus den Hostfiles, `radius` aus `global.rsc`, `radius.rsc` löschen, Release: Die Rollen entfernen
`/interface/dot1x/server`, `/radius` mit `cfm:`-Kommentar und die User-Manager-Einträge; das Paket bleibt installiert.

## 7. Offene Fragen

1. **MGMT für den Admin-Laptop am Dock:** Am Dot1X-Port gibt es keine getaggten VLANs (Folge 1). Reicht MGMT geroutet
   aus dem Haupt-VLAN (Firewall-Freigabe für die Adresse des Admin-Laptops), oder soll der Admin-Laptop sich in ein
   eigenes Admin-VLAN anmelden?
2. **Hat der Firmen-Laptop ein eigenes 802.1X-Profil für Kabel?** Dann sperrt er den Port (Fall F) – der Umschalter
   DP1.4 bliebe für ihn nötig. Prüfen: Windows-Dienst „Automatische Konfiguration (verkabelt)“ / `netsh lan show
   profiles`.
3. **Trennt das Dock den Link, wenn ein Laptop abgezogen wird?** Sonst gilt die alte Anmeldung bis zum Re-Auth
   (Vorschlag 60 s). Test vor Ort: `/interface/ethernet/monitor ether5` beim Abziehen.
4. **PEAP mit Passwort oder EAP-TLS mit Client-Zertifikat** für den Admin-Laptop?
5. **Gast-VLAN für Geräte ohne Supplicant** (`guest`) gleich dem Reject-VLAN, oder Geräte ohne 802.1X ganz sperren?
