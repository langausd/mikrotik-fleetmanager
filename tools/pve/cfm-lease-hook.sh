#!/usr/bin/env bash
# Hook für die Proxmox Community Scripts (var_post_install, läuft als root auf dem PVE-Host nach dem Anlegen eines
# Containers, Umgebung CTID, HN, …): Tag setzen und die Lease sofort eintragen (cfm-lease-pve.py hook).
# In /usr/local/community-scripts/default.vars:  var_post_install=/usr/local/sbin/cfm-lease-hook.sh
# Ein Fehler bricht nichts ab: Der Container bleibt, der Timer versucht es beim nächsten Lauf wieder.
/usr/local/sbin/cfm-lease-pve.py hook || echo "cfm-lease: Eintrag fehlgeschlagen - der Timer versucht es wieder"
exit 0
