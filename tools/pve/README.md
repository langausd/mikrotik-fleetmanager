# Proxmox → cfm: Gäste als feste Lease (`tools/pve/`)

`cfm-lease-pve.py` trägt Gäste eines Proxmox-Hosts als feste DHCP-Lease in cfm ein (TODO 102, DN1.3, Admin-Guide
8.22). Es läuft auf dem PVE-Host als root und ruft am Primary-Manager das Skript `cfm-lease` auf (User `cfm-lease`,
nur per Key, nur von der Adresse des PVE-Hosts). Der Manager wählt die Adresse, schreibt `leases.rsc` und gibt ein
Release heraus.

* **Welche Gäste:** nur mit PVE-Tag `cfm` (`TAG`). Name = VM-Name bzw. Hostname des Containers, als DNS-Label
  (`web_01` → `web-01`). MAC und VLAN aus `net0` (`tag=`); ohne Tag aus `VLAN_MAP` (`vmbr1=40`) oder `DEFAULT_VLAN`.
  Container mit fester Adresse in `net0` werden übersprungen.
* **Wann:** systemd-Timer alle 2 Minuten (`sweep`). Was eingetragen ist, merkt sich das Tool in `STATE`; ein Gast wird
  erst wieder gefragt, wenn sich Name, MAC oder VLAN ändern (`--force` fragt alle).
* **Community Scripts:** Proxmox selbst kennt keinen Hook beim Anlegen eines Gasts. Die Proxmox Community Scripts
  rufen nach dem Anlegen eines Containers `var_post_install` auf dem Host auf (Umgebung `CTID`, `HN`, …);
  `cfm-lease-hook.sh` setzt dann den Tag und trägt den Container sofort ein. Für VMs gibt es diesen Hook nicht – sie
  erfasst der Timer, sobald sie den Tag haben.

## Einrichten

Am Manager (`global.rsc`): `"lease"={"from"={"<IP des PVE-Hosts>"}}`, dann den Schlüssel als
`work/authorized_keys.cfm-lease` ablegen und `$cfmRelease`.

Auf dem PVE-Host:

```bash
install -d -m 700 /etc/cfm-lease-pve
ssh-keygen -t ed25519 -N "" -C cfm-lease-pve -f /etc/cfm-lease-pve/id_ed25519   # .pub -> authorized_keys.cfm-lease
install -m 755 cfm-lease-pve.py cfm-lease-hook.sh /usr/local/sbin/
install -m 600 cfm-lease-pve.conf.example /etc/cfm-lease-pve.conf               # MANAGER, PORT, VLAN_MAP anpassen
install -m 644 cfm-lease-pve.service cfm-lease-pve.timer /etc/systemd/system/
systemctl daemon-reload

cfm-lease-pve.py sweep --probe      # zeigt, was es eintragen würde (ruft den Manager nicht auf)
cfm-lease-pve.py add <vmid>         # ein Gast zum Ausprobieren
systemctl enable --now cfm-lease-pve.timer

# Community Scripts (optional):
echo 'var_post_install=/usr/local/sbin/cfm-lease-hook.sh' >> /usr/local/community-scripts/default.vars
```

Die erste Verbindung nimmt den Host-Key des Managers in `/etc/cfm-lease-pve/known_hosts` auf (`accept-new`).
Ausgabe je Gast: `<vmid>: LEASE ok … ip=…`, `<vmid>: RELEASE v<N>`; Fehler (`ERGEBNIS fehler: …`, z.B. Name schon
vergeben) im Journal (`journalctl -u cfm-lease-pve`), der Timer fragt dann beim nächsten Lauf wieder.

**Grenzen:** Die erste DHCP-Anfrage des neuen Gasts kann noch eine Pool-Adresse bekommen (Release und Apply brauchen
etwa eine Minute) – dann im Gast die Lease erneuern. Ein gelöschter Gast bleibt in `leases.rsc`. Nur `net0` zählt.

Tests: `python3 tools/pve/cfm-lease-pve-test.py`.
