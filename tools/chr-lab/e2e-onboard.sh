#!/usr/bin/env bash
# ------------------------------------------------------------------
# Test des automatischen Onboardings (Push in die Werks-Config) im CHR-Labor.
#   vm1 = cm1 (Primary-Manager, zugleich "Switch" mit dem Onboarding-Port ether3)
#   vm3 = neues Gerät "ob1" an cm1/ether3 (Stern-Topologie aus lab.sh)
# Der Werkszustand wird auf dem frischen CHR simuliert: 192.168.88.1 auf ether2,
# admin ohne Passwort (echte Geräte: Aufkleber-Passwort per $cfmRegister pw=...).
#   ./e2e-onboard.sh [fresh] [dhcp]
#   dhcp = Werksgerät im CAPs-Modus: DHCP-Client auf dem Uplink statt 192.168.88.1, wie ein hAP,
#          der per PoE an ether1 hängt (dessen normale Werks-Config dort eine WAN-Firewall hat)
# ------------------------------------------------------------------
set -uo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
export LAB=${LAB:-${XDG_CACHE_HOME:-$HOME/.cache}/cfm-chr-lab}
O=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
pass=0; fail=0
ok()   { echo "  ✔ $*"; pass=$((pass+1)); }
bad()  { echo "  ✘ $*"; fail=$((fail+1)); }
step() { echo; echo "== $*"; }
r()    { ./lab.sh ssh "$@" 2>&1 | tr -d '\r'; }
put()  { printf '#!/bin/sh\necho ""\n' > "$LAB/askpass"
         SSH_ASKPASS="$LAB/askpass" SSH_ASKPASS_REQUIRE=force sftp -q -b - -P $((2200+$1*10)) "${O[@]}" -i "$LAB/lab_key" admin@127.0.0.1 >/dev/null; }
mgr()  { r 1 "/system script run cfm-mgr; $1"; }
waitssh() { for _ in $(seq 1 60); do r "$1" ':put up' | grep -q up && return 0; sleep 2; done; return 1; }
expect() { if r "$1" ":put ($2)" | grep -q true; then ok "$3"; else bad "$3"; fi; }
stat() { mgr ':global cfmJson; :put [:tostr ([$cfmJson "cfm/state/'"$1"'/status.dat"]->"'"$2"'")]' | tail -1; }

fresh=0; mode=static
for a in "$@"; do case $a in fresh) fresh=1;; dhcp) mode=dhcp;; esac; done
if [ $fresh = 1 ]; then
  step "VMs neu aufsetzen"
  ./lab.sh stop >/dev/null; rm -f "$LAB"/vm*.qcow2; ./lab.sh start 3
fi
for i in 1 3; do waitssh $i || { echo "vm$i nicht erreichbar"; exit 1; }; done

step "1. Primary-Manager cm1"
SFTP_OPTS="-i $LAB/lab_key ${O[*]}" SSH_ASKPASS="$LAB/askpass" SSH_ASKPASS_REQUIRE=force \
  "$ROOT/tools/upload-seed.sh" admin@127.0.0.1 --port 2210 --overlay "$PWD/seed" --seed-inventory >/dev/null && ok "Seed hochgeladen" || bad "Seed hochladen fehlgeschlagen"
# hier der Weg ohne Reset (clean="no"), den Reset testet e2e.sh
sed -e 's/^:local uplink "ether1"/:local uplink "ether2"/' -e 's/^:local clean "yes"/:local clean "no" /' \
    "$ROOT/bootstrap/bootstrap-manager.rsc" > "$LAB/bm.rsc"
echo "put $LAB/bm.rsc bootstrap-manager.rsc" | put 1
r 1 '/import bootstrap-manager.rsc verbose=no' | grep -q "Primary-Manager bereit" && ok "Manager-Bootstrap" || bad "Manager-Bootstrap"
for _ in $(seq 1 45); do [ "$(stat cm1 v)" = 1 ] && break; sleep 4; done
[ "$(stat cm1 v)" = 1 ] && ok "cm1 hat v1 angewendet" || bad "cm1 Apply v1"
expect 1 '[:len [/ip/dhcp-server/find where name=dhcp88]] = 1' "cm1: DHCP im Onboarding-VLAN 88"

serial=$(r 3 ':put [/system/license/get system-id]' | tail -1)
if [ $mode = dhcp ]; then
  step "2. Werkszustand auf vm3 simulieren: CAPs-Modus (DHCP-Client auf dem Uplink, keine 192.168.88.1)"
  # ohne Default-Route: im Labor gibt es den Onboarding-Router .250 nicht, das Update-Prüfen
  # läuft weiter über ether1 (QEMU-Netz); ein echtes Gerät nutzt den Router des Onboarding-VLANs
  r 3 '/ip/dhcp-client/add interface=ether2 add-default-route=no use-peer-dns=no disabled=no' >/dev/null
else
  step "2. Werkszustand auf vm3 simulieren: Werks-IP 192.168.88.1"
  r 3 '/ip/address/add address=192.168.88.1/24 interface=ether2' >/dev/null
fi
echo "   Seriennummer vm3: $serial"

step "3. Registrieren + Onboarding-Port cm1/ether3"
mgr "\$cfmRegister name=ob1 serial=\"$serial\" role=switch,router ring=0 ip=192.168.10.23" | grep -q "Registriert" && ok "ob1 registriert" || bad "Registrierung"
mgr '$cfmOnboard sw=cm1 port=ether3 name=ob1' | grep -q "ist aktiv" && ok "Onboarding-Port aktiv" || bad "cfmOnboard"
expect 1 '[/interface/bridge/port/get [find interface=ether3] pvid] = 88' "cm1/ether3: PVID = Onboarding-VLAN"

step "4. Automatischer Ablauf (Probe -> Update-Check -> Bootstrap/Reset -> Enroll -> Apply)"
last=""
for _ in $(seq 1 70); do
  st=$(mgr '$cfmOnboardStatus' | tail -1)
  [ "$st" != "$last" ] && echo "   $st" && last=$st
  echo "$st" | grep -q "keine Onboarding-Sitzung" && break
  sleep 15
done
mgr ':foreach l in=[/log/find where message~"Onboarding"] do={:put [/log/get $l message]}' | tail -3 | sed 's/^/   log: /'
mgr ':put [:len [/log/find where message~"beendet: erfolgreich: ob1"]]' | tail -1 | grep -qx 1 && ok "Onboarding erfolgreich beendet" || bad "Onboarding nicht erfolgreich"
# den Status holt der allgemeine Manager-Tick ab, der parallel zum Onboarding-Tick läuft: kurz warten
for _ in $(seq 1 24); do [ "$(stat ob1 res)" = ok ] && break; sleep 5; done
[ "$(stat ob1 res)" = ok ] && ok "ob1 meldet Apply ok (v$(stat ob1 v))" || bad "ob1 Status: $(stat ob1 res)"
[ $mode = dhcp ] && expect 1 '[:len [/ip/dhcp-server/lease/find where server=dhcp88 and mac-address="52:54:00:00:03:02"]] = 1' "cm1: ob1 hat seine Adresse per DHCP im Onboarding-VLAN bekommen (CAPs-Modus)"

step "5. Port zurück auf sein Profil, Gerät vollständig aufgenommen"
# die Rückstellung kommt mit dem angestoßenen Apply auf cm1 (im Labor ca. 25 s): bis 2 min warten
for _ in $(seq 1 24); do r 1 ':put [/interface/bridge/port/get [find interface=ether3] pvid]' | tail -1 | grep -qx 1 && break; sleep 5; done
expect 1 '[/interface/bridge/port/get [find interface=ether3] pvid] = 1' "cm1/ether3: PVID wieder 1"
expect 1 '[/interface/bridge/port/get [find interface=ether3] frame-types] = "admit-only-vlan-tagged"' "cm1/ether3: wieder reiner Trunk"
expect 1 '[:len [/system/scheduler/find where name=cfm-onboard-revert]] = 0' "cm1: Fail-safe-Timer entfernt"
waitssh 3 && expect 3 '[/system/identity/get name] = "ob1"' "ob1: Identity gesetzt, per SSH erreichbar" || bad "ob1 nicht per SSH erreichbar"
expect 3 '[/interface/bridge/get bridge vlan-filtering]' "ob1: VLAN-Filtering aktiv"

echo; echo "Ergebnis: $pass ok, $fail fehlgeschlagen"; [ $fail -eq 0 ]
