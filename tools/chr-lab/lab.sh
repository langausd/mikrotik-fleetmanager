#!/usr/bin/env bash
# CHR-Testlabor für das cfm-Framework.
#   ./lab.sh start [n]   startet n VMs (default 3: cm1, cm2, dev1)
#   ./lab.sh stop        stoppt alle VMs
#   ./lab.sh ssh <i> [cmd...]   SSH auf VM i (1..n), ohne cmd interaktiv
#   ./lab.sh put <i> <local> [remote]   Datei per SFTP hochladen
#   ./lab.sh status
#
# Netz: nic0 = QEMU-User-Net (ether1, DHCP 10.0.2.x, SSH-Forward auf 22<i>0),
#       Stern: vm1 ether2..etherN <-> vm2..vmN ether2 (Trunks, siehe topo()).
#       vm1 muss zuerst starten (lauscht), "start" startet in dieser Reihenfolge.
# Voraussetzung: CHR-Image (raw .img) in $CHR_IMG oder im Arbeitsverzeichnis $LAB.
set -euo pipefail
# VM-Disks bewusst NICHT im (evtl. synchronisierten) Projektverzeichnis
LAB=${LAB:-${XDG_CACHE_HOME:-$HOME/.cache}/cfm-chr-lab}
CHR_IMG=${CHR_IMG:-$(ls "$LAB"/chr-*.img 2>/dev/null | sort -V | tail -1 || true)}
KEY="$LAB/lab_key"
MEM=${MEM:-256}
mkdir -p "$LAB"

port() { echo $((2200 + $1 * 10)); }

# Stern-Topologie: vm1 (Manager) hat ether2..etherN je als Punkt-zu-Punkt-Link zu
# vm2..vmN (TCP-Socket). Kein Multicast-Hub: der spiegelt jeder VM ihre eigenen
# Frames zurück, RSTP sieht dann eine Schleife und blockiert den Port.
topo() { # topo <vm> <anzahl>
  local i=$1 n=$2 j a=""
  if [ "$i" = 1 ]; then
    for j in $(seq 2 "$n"); do
      a="$a -netdev socket,id=t$j,listen=127.0.0.1:$((12000 + j)) -device virtio-net-pci,netdev=t$j,mac=52:54:00:00:01:0$j"
    done
  else
    a="-netdev socket,id=t1,connect=127.0.0.1:$((12000 + i)) -device virtio-net-pci,netdev=t1,mac=52:54:00:00:0$i:02"
  fi
  echo "$a"
}

askpass() { # leeres Passwort fuer frische CHRs
  printf '#!/bin/sh\necho "%s"\n' "${LAB_PASS:-}" > "$LAB/askpass"; chmod +x "$LAB/askpass"
}

sshopts() {
  echo "-p $(port "$1") -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"
}

case "${1:-}" in
start)
  n=${2:-3}
  [ -f "$CHR_IMG" ] || { echo "CHR-Image fehlt (CHR_IMG=$CHR_IMG)"; exit 1; }
  [ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -f "$KEY"
  cd "$LAB"   # relative Socket-Pfade (Unix-Sockets max. 108 Zeichen)
  for i in $(seq 1 "$n"); do
    disk="$LAB/vm$i.qcow2"
    [ -f "$disk" ] || qemu-img create -q -f qcow2 -b "$CHR_IMG" -F raw "$disk"
    if [ -f "$LAB/vm$i.pid" ] && kill -0 "$(cat "$LAB/vm$i.pid")" 2>/dev/null; then echo "vm$i läuft bereits"; continue; fi
    qemu-system-x86_64 -enable-kvm -m "$MEM" -smp 1 -name "cfm-vm$i" \
      -drive file="$disk",format=qcow2,if=virtio \
      -netdev user,id=n0,hostfwd=tcp:127.0.0.1:"$(port "$i")"-:22 \
      -device virtio-net-pci,netdev=n0,mac=52:54:00:00:0$i:01 \
      $(topo "$i" "$n") \
      -serial unix:"vm$i.serial",server,nowait -monitor none \
      -display none -daemonize -pidfile "vm$i.pid"
    echo "vm$i gestartet (ssh-Port $(port "$i"))"
  done ;;
stop)
  for p in "$LAB"/vm*.pid; do [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null; rm -f "$p"; done; echo gestoppt ;;
status)
  for p in "$LAB"/vm*.pid; do [ -f "$p" ] || continue; i=${p##*/vm}; i=${i%.pid}
    kill -0 "$(cat "$p")" 2>/dev/null && echo "vm$i up (port $(port "$i"))" || echo "vm$i down"; done ;;
ssh)
  i=$2; shift 2; askpass
  # Key-Login bevorzugt, sonst leeres Passwort per SSH_ASKPASS
  SSH_ASKPASS="$LAB/askpass" SSH_ASKPASS_REQUIRE=force \
    ssh $(sshopts "$i") -i "$KEY" admin@127.0.0.1 "$@" ;;
put)
  i=$2; src=$3; dst=${4:-$(basename "$3")}; askpass
  SSH_ASKPASS="$LAB/askpass" SSH_ASKPASS_REQUIRE=force \
    sftp -q -P "$(port "$i")" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    -i "$KEY" admin@127.0.0.1 <<< "put $src $dst" ;;
*) sed -n '2,12p' "$0"; exit 1 ;;
esac
