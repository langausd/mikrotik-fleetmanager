#!/usr/bin/env bash
# ------------------------------------------------------------------
# Probe des Router-Umzugs (Variante C) im CHR-Labor: drei Router mit VRRP hinter einem Internet-Router,
# der wie im Zielbild im LAN-VLAN steht (LAN-Gateway der Router = VIP .2, der Internet-Router behält .1).
#   vm1 = cm1   Primary-Manager, zentraler Switch der Stern-Topologie und dritter Router (routerId 3)
#   vm2 = r1    routerId 1 (VRRP-Master)        vm3 = r2   routerId 2
#   vm4 = inet  nicht verwaltet: Internet-Router 192.168.20.1 an cm1/ether4 (LAN ungetaggt), dazu je
#               eine VRF als Client in IoT (192.168.30.77) und Gast (192.168.40.77). "Internet" ist
#               198.51.100.1 auf inet (TEST-NET-2, also nicht in cfm-private).
# Geprüft: VIPs und DHCP nur auf dem Master, Zonen-Policy (LAN -> IoT/Gast ja, IoT -> LAN/Internet nein,
# Gast -> Internet mit fester NAT-Adresse, Gast -> LAN nein), Ausfall und Rückkehr des Masters
# (Preemption: VIP danach erreichbar?), Neustart des Masters, Ausfall von zwei Routern.
# Daten: seed-vrrp/ (Overlay über cfm/work).
#   ./e2e-vrrp.sh [fresh]      fresh = VM-Disks neu aus dem CHR-Image (Standard: immer neu)
# ------------------------------------------------------------------
set -uo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
export LAB=${LAB:-${XDG_CACHE_HOME:-$HOME/.cache}/cfm-chr-lab}
export LABPORT=${LABPORT:-2200} LABSOCK=${LABSOCK:-12000}
O=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
pass=0; fail=0
ok()   { echo "  ✔ $*"; pass=$((pass+1)); }
bad()  { echo "  ✘ $*"; fail=$((fail+1)); }
step() { echo; echo "== $*"; }
r()    { ./lab.sh ssh "$@" 2>&1 | tr -d '\r'; }
put()  { printf '#!/bin/sh\necho ""\n' > "$LAB/askpass"
         SSH_ASKPASS="$LAB/askpass" SSH_ASKPASS_REQUIRE=force sftp -q -b - -P $((LABPORT+$1*10)) "${O[@]}" -i "$LAB/lab_key" admin@127.0.0.1 >/dev/null; }
get()  { echo "get $2 $3" | put "$1"; }
mgr()  { r 1 "/system script run cfm-mgr; $1"; }
waitssh() { for _ in $(seq 1 60); do r "$1" ':put up' | grep -q up && return 0; sleep 2; done; return 1; }
expect() { if r "$1" ":put ($2)" | grep -q true; then ok "$3"; else bad "$3"; fi; }
stat() { mgr ':global cfmJson; :put [:tostr ([$cfmJson "cfm/state/'"$1"'/status.dat"]->"'"$2"'")]' | tail -1; }
agentwait() { for _ in $(seq 1 45); do mgr ':global cfmJson; :put [:tostr ([$cfmJson "cfm/state/'"$3"'/status.dat"]->"v")]' | grep -qx "$2" && return 0; sleep 4; done; return 1; }
# Antworten eines Pings (letzte Zeile = Anzahl): pings <vm> '<Ziel und Optionen>'
pings() { r "$1" ":put [/ping $2 count=5 interval=200ms]" | tail -1 | tr -dc 0-9; }
# VRRP-Master in allen vier VLANs? vrrp: running = Master
ismaster() { r "$1" ':local n 0; :foreach v in={"vrrp10";"vrrp20";"vrrp30";"vrrp40"} do={ :if ([/interface/vrrp/get [find name=$v] running]) do={ :set n ($n + 1) } }; :put ("M=" . $n)' | grep -o 'M=[0-9]' | tr -dc 0-9; }
dhcpon() { r "$1" ':put ("D=" . [:len [/ip/dhcp-server/find where comment~"^cfm:dhcp" and !disabled]])' | grep -o 'D=[0-9]' | tr -dc 0-9; }
natcnt() { r 4 ':put ("N=" . [/ip/firewall/filter/get [find comment=gastnat] packets])' | grep -o 'N=[0-9]*' | tr -dc 0-9; }
# Lage aus Sicht der Clients: VIPs, Policy, NAT. Erwartet: $1 = Name des Masters
policy() {
  local m=$1 n0 n1
  [ "$(pings 4 '192.168.20.2')" -ge 4 ] && ok "$m: VIP 192.168.20.2 aus dem LAN erreichbar" || bad "$m: VIP .20.2 nicht erreichbar"
  [ "$(pings 4 '192.168.30.1 vrf=iot')" -ge 4 ] && ok "$m: IoT-Client erreicht sein Gateway .30.1" || bad "$m: IoT-Gateway nicht erreichbar"
  [ "$(pings 4 '192.168.30.77 src-address=192.168.20.1')" -ge 4 ] && ok "$m: LAN -> IoT erlaubt" || bad "$m: LAN -> IoT gesperrt"
  [ "$(pings 4 '192.168.40.77 src-address=192.168.20.1')" -ge 4 ] && ok "$m: LAN -> Gast erlaubt" || bad "$m: LAN -> Gast gesperrt"
  [ "$(pings 4 '192.168.20.1 vrf=iot')" = 0 ] && ok "$m: IoT -> LAN gesperrt" || bad "$m: IoT -> LAN offen"
  [ "$(pings 4 '198.51.100.1 vrf=iot')" = 0 ] && ok "$m: IoT -> Internet gesperrt" || bad "$m: IoT -> Internet offen"
  [ "$(pings 4 '192.168.20.1 vrf=guest')" = 0 ] && ok "$m: Gast -> LAN gesperrt (privates Ziel über das WAN-VLAN)" || bad "$m: Gast -> LAN offen"
  n0=$(natcnt)
  [ "$(pings 4 '198.51.100.1 vrf=guest')" -ge 4 ] && ok "$m: Gast -> Internet" || bad "$m: Gast -> Internet geht nicht"
  n1=$(natcnt)
  [ "${n1:-0}" -gt "${n0:-0}" ] && ok "$m: Gäste kommen beim Internet-Router als 192.168.20.199 an" || bad "$m: feste NAT-Adresse nicht gesehen ($n0 -> $n1)"
}
state() { # state <master-vm> <name> [abgetrennte VMs]: genau dieser Router ist Master in allen VLANs und
  # vergibt DHCP; abgetrennte Router (Uplink aus) hören niemanden und zählen nicht mit
  local m=$1 nm=$2 i c=0 n=0; shift 2
  for i in 1 2 3; do
    [ "$i" = "$m" ] && continue; [[ " $* " == *" $i "* ]] && continue
    n=$((n+1)); [ "$(ismaster $i)" = 0 ] && [ "$(dhcpon $i)" = 0 ] && c=$((c+1))
  done
  [ "$(ismaster "$m")" = 4 ] && ok "$nm ist Master in allen 4 VLANs" || bad "$nm Master in $(ismaster "$m")/4 VLANs"
  [ "$(dhcpon "$m")" = 2 ] && [ $c = $n ] && ok "DHCP (IoT, Gast) nur auf $nm" || bad "DHCP: $nm $(dhcpon "$m"), übrige ohne DHCP: $c/$n"
}

step "VMs neu aufsetzen (4)"
./lab.sh stop >/dev/null; rm -f "$LAB"/vm*.qcow2; ./lab.sh start 4
for i in 1 2 3 4; do waitssh $i || { echo "vm$i nicht erreichbar"; exit 1; }; done

step "1. Internet-Router inet (vm4, von Hand)"
# Die Routing-Tabelle einer neuen VRF steht erst kurz danach bereit: Routen in einem zweiten Aufruf
r 4 '/interface/vlan/add name=v30 vlan-id=30 interface=ether2; /interface/vlan/add name=v40 vlan-id=40 interface=ether2; /ip/vrf/add name=iot interfaces=v30; /ip/vrf/add name=guest interfaces=v40; /ip/address/add address=192.168.20.1/24 interface=ether2; /ip/address/add address=192.168.30.77/24 interface=v30; /ip/address/add address=192.168.40.77/24 interface=v40; /ip/address/add address=198.51.100.1/32 interface=lo' >/dev/null
sleep 3
r 4 '/ip/route/add dst-address=0.0.0.0/0 gateway=192.168.30.1@iot routing-table=iot; /ip/route/add dst-address=0.0.0.0/0 gateway=192.168.40.1@guest routing-table=guest; :foreach n in={"192.168.10.0/24";"192.168.30.0/24";"192.168.40.0/24"} do={ /ip/route/add dst-address=$n gateway=192.168.20.2 }; /ip/firewall/filter/add chain=input src-address=192.168.20.199 action=accept comment=gastnat; /system/identity/set name=inet' >/dev/null
expect 4 '[:len [/ip/route/find where dst-address="0.0.0.0/0" and routing-table="guest" and active]] = 1 and [:len [/ip/route/find where gateway="192.168.20.2"]] = 3 and [:len [/ip/address/find where address="198.51.100.1/32"]] = 1' "inet: LAN .1, VRF-Clients IoT/Gast, Internet-Adresse 198.51.100.1"

step "2. Seed auf cm1 + Manager-Bootstrap"
SFTP_OPTS="-i $LAB/lab_key ${O[*]}" SSH_ASKPASS="$LAB/askpass" SSH_ASKPASS_REQUIRE=force \
  "$ROOT/tools/upload-seed.sh" admin@127.0.0.1 --port $((LABPORT+10)) --overlay "$PWD/seed-vrrp" --seed-inventory >/dev/null && ok "Seed hochgeladen" || bad "Seed hochladen fehlgeschlagen"
sed -e 's/^:local uplink "ether1"/:local uplink "ether2"/' \
    -e 's|^:local post ""|:local post ":if ([:len [/ip/dhcp-client/find where interface=ether1]] = 0) do={ /ip/dhcp-client/add interface=ether1 disabled=no add-default-route=no }"|' \
    "$ROOT/bootstrap/bootstrap-manager.rsc" > "$LAB/bm-vrrp.rsc"
echo "put $LAB/bm-vrrp.rsc bootstrap-manager.rsc" | put 1
timeout 90 ./lab.sh ssh 1 '/import bootstrap-manager.rsc verbose=no' >/dev/null 2>&1
sleep 15; waitssh 1
for _ in $(seq 1 60); do r 1 ':put [:len [/log/find where message="cfm: Primary-Manager bereit"]]' | tail -1 | grep -qx 1 && break; sleep 5; done
r 1 ':put [:len [/log/find where message="cfm: Primary-Manager bereit"]]' | tail -1 | grep -qx 1 && ok "Manager-Bootstrap" || bad "Manager-Bootstrap"
agentwait 1 1 cm1 && ok "cm1 hat v1 angewendet" || bad "cm1 Apply v1"

step "3. r1, r2: Bootstrap + Enroll"
mgr '$cfmBootstrap' >/dev/null
get 1 cfm/cfm-bootstrap.rsc "$LAB/bs-vrrp.rsc"
for i in 2 3; do
  n=r$((i-1)); ip=192.168.10.$((19+i))
  sed -e 's|^:local ip ".*"|:local ip "'"$ip"'/24"|' -e 's/^:local uplink "ether1"/:local uplink "ether2"/' "$LAB/bs-vrrp.rsc" > "$LAB/bs-$n.rsc"
  echo "put $LAB/bs-$n.rsc cfm-bootstrap.rsc" | put $i
  r $i '/import cfm-bootstrap.rsc verbose=no' | grep -q "Bootstrap fertig" && ok "Bootstrap $n" || bad "Bootstrap $n"
  mgr "\$cfmEnroll name=$n ip=$ip role=switch ring=0" | grep -q "Enrolled" && ok "Enroll $n" || bad "Enroll $n"
done
agentwait 2 1 r1 && ok "r1 hat v1 angewendet" || bad "r1 Apply v1"
agentwait 3 1 r2 && ok "r2 hat v1 angewendet" || bad "r2 Apply v1"
# Labor: Default-Route über den Host-Zugang (ether1, QEMU) abschalten, sonst ECMP mit dem WAN-Weg
for i in 1 2 3; do r $i '/ip/dhcp-client/set [find where interface=ether1] add-default-route=no' >/dev/null; done

step "4. Rollen router (r1, r2) und switch,router,manager (cm1)"
mgr ':global cfmInvLoad; :global cfmInvSave; :local i [$cfmInvLoad]; :set ($i->"r1"->"role") "switch,router"; :set ($i->"r2"->"role") "switch,router"; :set ($i->"cm1"->"role") "switch,router,manager"; $cfmInvSave $i; :global cfmManifests; $cfmManifests; $cfmPush' >/dev/null
for n in r1 r2 cm1; do
  for _ in $(seq 1 60); do [[ "$(stat $n role)" == *router* ]] && [ "$(stat $n res)" = ok ] && break; sleep 4; done
  [[ "$(stat $n role)" == *router* ]] && [ "$(stat $n res)" = ok ] && ok "$n als $(stat $n role) angewendet" || bad "$n: $(stat $n role) $(stat $n res)"
done
sleep 5
expect 2 '[:len [/ip/address/find where address="192.168.20.199/32" and comment~"^cfm:"]] = 1' "r1: feste NAT-Adresse liegt am VRRP-Interface des WAN"
expect 2 '[:len [/ip/firewall/nat/find where comment~"^cfm:nat" and action="masquerade" and src-address-list!="cfm-z-onboard"]] = 0' "r1: masquerade nur fürs Onboarding (LAN und MGMT werden geroutet)"
# Verkehr an die VIP kommt über vrrp<VID> herein (Laborbefund 2026-10-01): VRRP-Interfaces in den Zonen, WAN-VRRP im WAN
expect 2 '[:len [/interface/list/member/find where interface="vrrp40" and list="Z-guest"]] = 1 and [:len [/interface/list/member/find where interface="vrrp20" and list="Z-lan"]] = 1 and [:len [/interface/list/member/find where interface="vrrp20" and list="WAN"]] = 1' "r1: VRRP-Interfaces in den Zonen-Listen (vrrp20 auch im WAN)"

step "5. Normalbetrieb: r1 ist Master"
state 2 r1
policy r1

step "6. Ausfall: r1 verliert den Uplink -> r2 übernimmt"
r 2 '/interface/ethernet/disable ether2' >/dev/null; sleep 6
state 3 r2 2
policy r2

step "7. Rückkehr: r1 wieder am Netz -> Preemption, VIPs danach erreichbar"
r 2 '/interface/ethernet/enable ether2' >/dev/null; sleep 10
state 2 r1
# Forum-Befund (7.24.4, CCR2004): VIP nach Preemption nicht erreichbar - hier 10 Pings über 2 s
[ "$(r 4 ':put [/ping 192.168.20.2 count=10 interval=200ms]' | tail -1 | tr -dc 0-9)" = 10 ] && ok "VIP .20.2 nach Preemption ohne Verlust" || bad "VIP .20.2 nach Preemption mit Verlust"
policy r1

step "8. Neustart des Masters r1"
r 2 '/system/reboot' >/dev/null 2>&1; sleep 8
state 3 "r2 (während r1 startet)" 2
waitssh 2; sleep 20
state 2 "r1 (nach dem Start)"
policy r1

step "9. Zwei Router fallen aus -> cm1 (routerId 3) übernimmt"
r 2 '/interface/ethernet/disable ether2' >/dev/null; r 3 '/interface/ethernet/disable ether2' >/dev/null; sleep 6
state 1 cm1 2 3
policy cm1
r 2 '/interface/ethernet/enable ether2' >/dev/null; r 3 '/interface/ethernet/enable ether2' >/dev/null; sleep 10
state 2 "r1 (wieder)"

step "10. Idempotenz der Router"
for n in r1 r2 cm1; do
  case $n in r1) vm=2;; r2) vm=3;; cm1) vm=1;; esac
  for _ in $(seq 1 40); do r $vm ':put [:len [/system/script/job/find where script="cfm-agent"]]' | tail -1 | grep -qx 0 && break; sleep 3; done
  t0=$(stat $n t); mgr "\$cfmPush host=$n force=yes" >/dev/null
  for _ in $(seq 1 60); do [ "$(stat $n t)" != "$t0" ] && break; sleep 4; done
  stat $n stats | grep -q "add=0;rem=0;set=0;skip=0" && ok "$n: zweiter Apply ohne Änderungen" || bad "$n idempotent: $(stat $n stats)"
done

echo; echo "Ergebnis: $pass ok, $fail fehlgeschlagen"; [ $fail -eq 0 ]
