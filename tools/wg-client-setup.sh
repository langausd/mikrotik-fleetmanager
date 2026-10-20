#!/usr/bin/env bash
# wg-client-setup.sh – WireGuard-Verbindung fürs cfm-Admin-Netz per NetworkManager anlegen
# (nmcli statt GNOME-Panel). Zwei Schritte, weil Client- und Server-Schlüssel sich gegenseitig
# brauchen:
#
#   1) Einmalig ein Schlüsselpaar erzeugen und den Public Key ausgeben – der kommt in
#      site/wireguard.rsc unter peers.<name>.pubkey (danach $cfmRelease + $cfmPromote):
#        tools/wg-client-setup.sh genkey [--keyfile ~/.config/wireguard/cfm-mgmt.key]
#
#   2) Sobald der Router (cm1) die Rolle angewendet hat, dessen Public Key holen
#      (auf cm1: /interface/wireguard/print) und die NetworkManager-Verbindung anlegen:
#        tools/wg-client-setup.sh connect --name cfm-mgmt \
#          --endpoint 203.0.113.10:13231 --server-pubkey <PUBKEY-CM1> \
#          --address 192.168.250.2/32 --allowed-ips 192.168.250.0/24,192.168.10.0/24 \
#          [--keyfile ~/.config/wireguard/cfm-mgmt.key] [--keepalive 25]
#
# Adresse passend zu peers.<name>.addr in wireguard.rsc wählen (Host-Anteil im eigenen
# WireGuard-Subnetz "net", z.B. addr=2 -> 192.168.250.2/32); allowed-ips = dieses Subnetz plus die
# Netze, die über den Router erreichbar sein sollen (z.B. das MGMT-VLAN). Die Verbindung wird per
# `nmcli connection import type wireguard file ...` angelegt (Standard-wg-quick-Format), nicht
# aktiv geschaltet (autoconnect no) – aktivieren mit `nmcli connection up <name>`.
set -euo pipefail

cmd=${1:?Aufruf: wg-client-setup.sh genkey|connect [Optionen]}; shift

default_keyfile() { echo "$HOME/.config/wireguard/$1.key"; }

case $cmd in
  genkey)
    keyfile=""
    while [ $# -gt 0 ]; do case $1 in
      --keyfile) keyfile=$2; shift 2;;
      *) echo "unbekannt: $1"; exit 1;; esac; done
    [ -n "$keyfile" ] || keyfile=$(default_keyfile cfm-mgmt)
    # Schlüssel mit wg aus wireguard-tools, sonst mit OpenSSL (TODO 57: ohne root lässt sich das Paket
    # oft nicht nachinstallieren). Beides ist X25519: privat = die letzten 32 Byte des PKCS#8-DER von
    # OpenSSL; öffentlich = privaten Schlüssel mit festem PKCS#8-Kopf einlesen, die letzten 32 Byte des
    # öffentlichen Teils. connect braucht nur nmcli.
    if command -v wg >/dev/null; then
      gen() { wg genkey; }
      pub() { wg pubkey; }
    elif command -v openssl >/dev/null; then
      gen() { openssl genpkey -algorithm X25519 -outform DER | tail -c 32 | base64; }
      pub() { { printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x6e\x04\x22\x04\x20'; base64 -d; } \
                | openssl pkey -inform DER -pubout -outform DER | tail -c 32 | base64; }
    else
      echo "wg-client-setup.sh: weder 'wg' (Paket wireguard-tools) noch 'openssl' gefunden" >&2; exit 1
    fi
    mkdir -p "$(dirname "$keyfile")"
    if [ -f "$keyfile" ]; then
      echo "Schlüssel existiert schon, wird nicht überschrieben: $keyfile" >&2
    else
      (umask 077 && gen > "$keyfile")
      echo "Neuer privater Schlüssel gespeichert: $keyfile" >&2
    fi
    echo "Public Key (für wireguard.rsc, peers.<name>.pubkey):"
    pub < "$keyfile"
    ;;
  connect)
    command -v nmcli >/dev/null || { echo "wg-client-setup.sh: 'nmcli' (NetworkManager) fehlt" >&2; exit 1; }
    name=""; endpoint=""; server_pubkey=""; address=""; allowed_ips=""; keyfile=""; keepalive=25
    while [ $# -gt 0 ]; do case $1 in
      --name) name=$2; shift 2;;
      --endpoint) endpoint=$2; shift 2;;
      --server-pubkey) server_pubkey=$2; shift 2;;
      --address) address=$2; shift 2;;
      --allowed-ips) allowed_ips=$2; shift 2;;
      --keyfile) keyfile=$2; shift 2;;
      --keepalive) keepalive=$2; shift 2;;
      *) echo "unbekannt: $1"; exit 1;; esac; done
    : "${name:?--name fehlt}"; : "${endpoint:?--endpoint fehlt}"
    : "${server_pubkey:?--server-pubkey fehlt}"; : "${address:?--address fehlt}"
    : "${allowed_ips:?--allowed-ips fehlt}"
    [ -n "$keyfile" ] || keyfile=$(default_keyfile "$name")
    [ -f "$keyfile" ] || { echo "kein Schlüssel unter $keyfile – erst 'genkey --keyfile $keyfile' ausführen" >&2; exit 1; }

    tmpdir=$(mktemp -d); trap 'rm -rf "$tmpdir"' EXIT
    conf="$tmpdir/$name.conf"
    {
      echo "[Interface]"
      echo "PrivateKey = $(cat "$keyfile")"
      echo "Address = $address"
      echo
      echo "[Peer]"
      echo "PublicKey = $server_pubkey"
      echo "Endpoint = $endpoint"
      echo "AllowedIPs = $allowed_ips"
      echo "PersistentKeepalive = $keepalive"
    } > "$conf"

    if nmcli -t -f NAME connection show | grep -qx "$name"; then
      nmcli connection delete "$name" >/dev/null
      echo "vorhandene Verbindung \"$name\" ersetzt" >&2
    fi
    nmcli connection import type wireguard file "$conf" >/dev/null
    nmcli connection modify "$name" connection.autoconnect no
    echo "Verbindung \"$name\" angelegt (autoconnect aus). Aktivieren mit: nmcli connection up $name"
    ;;
  *) echo "unbekannt: $cmd (genkey|connect)"; exit 1;;
esac
