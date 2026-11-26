#!/usr/bin/env bash
# cfm-lease.sh – feste Lease von außen eintragen (TODO 102, DN1.3; global.rsc lease am Manager)
#   cfm-lease.sh [-r] [-k <key>] [-p <port>] <user@manager> add name=<n> vlan=<vid> [mac=..] [ip=..] [wifi=yes] [allow=a,b] [acme=yes] [release=no]
#   cfm-lease.sh … del name=<n> | list [vlan=<vid>]
#   -r   per REST (https://<manager>[:port]/rest/execute, Passwort aus CFM_LEASE_PW) statt SSH; -k = SSH-Schlüssel
#   -c <ca.pem>  CA für das Zertifikat des Managers (REST), -i = Zertifikat nicht prüfen
# Ausgabe: die Zeilen des Managers (LEASE …, RELEASE …, CNAME …, ERGEBNIS …). Exit-Code 0 bei "ERGEBNIS ok", sonst 1.
set -uo pipefail
rest=0; key=""; port=""; ca=""; ins=0
while getopts "rk:p:c:i" o; do case $o in r) rest=1;; k) key=$OPTARG;; p) port=$OPTARG;; c) ca=$OPTARG;; i) ins=1;; *) exit 2;; esac; done
shift $((OPTIND - 1))
[ $# -ge 2 ] || { sed -n '2,7p' "$0"; exit 2; }
dest=$1; shift
args="$*"
# nur Zeichen, die auch der Manager annimmt (er prüft selbst noch einmal)
[[ "$args" =~ ^[A-Za-z0-9:._@*,=\ -]+$ ]] || { echo "ERGEBNIS fehler: unzulässige Zeichen in den Argumenten"; exit 2; }
cmd=":global cfmLeaseArg \"$args\"; /system script run cfm-lease"
if [ $rest = 1 ]; then
  [ -n "${CFM_LEASE_PW:-}" ] || { echo "ERGEBNIS fehler: CFM_LEASE_PW fehlt (Passwort des Users)"; exit 2; }
  user=${dest%@*}; host=${dest#*@}; [ -n "$port" ] && host="$host:$port"
  opt=(-sS --max-time 120 -u "$user:$CFM_LEASE_PW" -H "content-type: application/json")
  [ -n "$ca" ] && opt+=(--cacert "$ca"); [ $ins = 1 ] && opt+=(-k)
  body=$(python3 -c 'import json,sys; print(json.dumps({"script": sys.argv[1], "as-string": ""}))' "$cmd")
  out=$(curl "${opt[@]}" -d "$body" "https://$host/rest/execute" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("ret", d.get("message", d)) if isinstance(d, dict) else d)')
else
  opt=(-o BatchMode=yes -o ConnectTimeout=10)
  [ -n "$key" ] && opt+=(-i "$key"); [ -n "$port" ] && opt+=(-p "$port")
  out=$(ssh "${opt[@]}" "$dest" "$cmd" 2>&1)
fi
out=$(printf '%s\n' "$out" | tr -d '\r')
printf '%s\n' "$out"
grep -q '^ERGEBNIS ok' <<<"$out"
