#!/usr/bin/env bash
# ------------------------------------------------------------------
# LACP-Bonds (D74) und MLAG (D75) im CHR-Labor, fünf VMs mit e1000-Karten (virtio meldet keine
# Geschwindigkeit, LACP bündelt damit nur einen Port – DECISIONS, Labor-Eigenheiten):
#   vm1 = cm1   Primary-Manager           ether2 -> sw1
#   vm2 = sw1   MLAG-Knoten (primary)     ether2 cm1, ether3/4 Peer zu sw2, ether5 srv1, ether6/7 Clients
#   vm3 = sw2   MLAG-Knoten               ether2/3 Peer zu sw1, ether4 srv1, ether5 Client
#   vm4 = srv1  LACP-Bond über beide      ether2 sw1, ether3 sw2
#   vm5 = cl    nicht verwaltet: Clients im IoT-VLAN (VRF a, b an sw1; c an sw2)
# Geprüft: Aufnahme ohne Bonds, Prüfungen von $cfmCheck, Umbau auf MLAG per Release (alle Geräte
# gleichzeitig), Zustand (MLAG verbunden, LACP auf allen Ports), Ausfall eines Links, Idempotenz,
# Rückbau; danach isolierte VLANs (D76) mit cm1 als Router. Daten: seed-mlag/ (Overlay),
# seed-mlag-phase/ (Umbau auf MLAG), seed-mlag-iso/ (Isolation).
#   ./e2e-mlag.sh          (setzt die VMs immer neu auf)
# ------------------------------------------------------------------
set -uo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
export LAB=${LAB:-${XDG_CACHE_HOME:-$HOME/.cache}/cfm-chr-lab}
export LABPORT=${LABPORT:-2200} LABSOCK=${LABSOCK:-12000}
export LABNIC=e1000 LABLINKS="1-2 2-3 2-3 2-4 3-4 2-5 2-5 3-5"
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
agentwait() { for _ in $(seq 1 "${4:-45}"); do mgr ':global cfmJson; :put [:tostr ([$cfmJson "cfm/state/'"$3"'/status.dat"]->"v")]' | grep -qx "$2" && return 0; sleep 4; done; return 1; }
pings() { r "$1" ":put [/ping $2 count=5 interval=200ms]" | tail -1 | tr -dc 0-9; }
# LACP je Slave (monitor-slaves läuft nur interaktiv weiter: im Hintergrund in eine Datei)
# -> "ether2:S ether3:S" (S = synchron und aktiv, - = nicht)
lacp() { r "$1" ':local j [:execute script="/interface/bonding/monitor-slaves bond='"$2"'" file=cfm-ms.txt]; :delay 2500ms; :onerror e in={ /system/script/job/remove $j } do={}; :delay 500ms; :local c [/file/get cfm-ms.txt contents]; /file/remove cfm-ms.txt; :local o ""; :local p 0; :while ([:typeof [:find $c "port=" $p]] = "num") do={ :local a ([:find $c "port=" $p] + 5); :local e [:find $c " " $a]; :local f [:find $c "flags=\"" $e]; :local fl [:pick $c ($f + 7) ($f + 15)]; :local s "-"; :if ([:pick $fl 3 4] = "S") do={ :set s "S" }; :local n ([:pick $c $a $e] . ":" . $s); :if ([:typeof [:find $o $n]] = "nil") do={ :set o ($o . " " . $n) }; :set p $e }; :put ("L=" . $o)' | grep -o 'L=.*' | cut -c3- | xargs; }
mstate() { r "$1" '/interface/bridge/monitor bridge once' | grep -o 'mlag-state: [a-z]*' | awk '{print $2}'; }
pushwait() { # pushwait <name> <vm>: Apply anstoßen und das Ende abwarten (Status t ändert sich)
  local t0; t0=$(stat "$1" t)
  for _ in $(seq 1 40); do r "$2" ':put [:len [/system/script/job/find where script="cfm-agent"]]' | tail -1 | grep -qx 0 && break; sleep 3; done
  mgr "\$cfmPush host=$1 force=yes" >/dev/null
  for _ in $(seq 1 60); do [ "$(stat "$1" t)" != "$t0" ] && break; sleep 4; done; }

step "VMs neu aufsetzen (5, e1000)"
./lab.sh stop >/dev/null; rm -f "$LAB"/vm*.qcow2; ./lab.sh start 5
for i in 1 2 3 4 5; do waitssh $i || { echo "vm$i nicht erreichbar"; exit 1; }; done

step "1. Clients cl (vm5, von Hand): VRF a/b an sw1, c an sw2, IoT-VLAN ungetaggt"
r 5 '/ip/vrf/add name=a interfaces=ether2; /ip/vrf/add name=b interfaces=ether3; /ip/vrf/add name=c interfaces=ether4; /ip/address/add address=192.168.30.71/24 interface=ether2; /ip/address/add address=192.168.30.72/24 interface=ether3; /ip/address/add address=192.168.30.73/24 interface=ether4; /system/identity/set name=cl' >/dev/null
expect 5 '[:len [/ip/address/find where address~"^192.168.30.7"]] = 3' "cl: drei Clients .71 (a), .72 (b), .73 (c)"

step "2. Seed auf cm1 + Manager-Bootstrap"
SFTP_OPTS="-i $LAB/lab_key ${O[*]}" SSH_ASKPASS="$LAB/askpass" SSH_ASKPASS_REQUIRE=force \
  "$ROOT/tools/upload-seed.sh" admin@127.0.0.1 --port $((LABPORT+10)) --overlay "$PWD/seed-mlag" --seed-inventory >/dev/null && ok "Seed hochgeladen" || bad "Seed hochladen fehlgeschlagen"
sed -e 's/^:local uplink "ether1"/:local uplink "ether2"/' \
    -e 's|^:local post ""|:local post ":if ([:len [/ip/dhcp-client/find where interface=ether1]] = 0) do={ /ip/dhcp-client/add interface=ether1 disabled=no add-default-route=no }"|' \
    "$ROOT/bootstrap/bootstrap-manager.rsc" > "$LAB/bm-mlag.rsc"
echo "put $LAB/bm-mlag.rsc bootstrap-manager.rsc" | put 1
timeout 90 ./lab.sh ssh 1 '/import bootstrap-manager.rsc verbose=no' >/dev/null 2>&1
sleep 15; waitssh 1
for _ in $(seq 1 60); do r 1 ':put [:len [/log/find where message="cfm: Primary-Manager bereit"]]' | tail -1 | grep -qx 1 && break; sleep 5; done
r 1 ':put [:len [/log/find where message="cfm: Primary-Manager bereit"]]' | tail -1 | grep -qx 1 && ok "Manager-Bootstrap" || bad "Manager-Bootstrap"
agentwait 1 1 cm1 && ok "cm1 hat v1 angewendet" || bad "cm1 Apply v1"

step "3. sw1, sw2, srv1: Bootstrap + Enroll (Ring 0, noch ohne Bonds)"
mgr '$cfmBootstrap' >/dev/null
get 1 cfm/cfm-bootstrap.rsc "$LAB/bs-mlag.rsc"
for i in 2 3 4; do
  case $i in 2) n=sw1;; 3) n=sw2;; 4) n=srv1;; esac
  ip=192.168.10.$((19+i))
  sed -e 's|^:local ip ".*"|:local ip "'"$ip"'/24"|' -e 's/^:local uplink "ether1"/:local uplink "ether2"/' "$LAB/bs-mlag.rsc" > "$LAB/bs-$n.rsc"
  echo "put $LAB/bs-$n.rsc cfm-bootstrap.rsc" | put $i
  r $i '/import cfm-bootstrap.rsc verbose=no' | grep -q "Bootstrap fertig" && ok "Bootstrap $n" || bad "Bootstrap $n"
  mgr "\$cfmEnroll name=$n ip=$ip role=switch ring=0" | grep -q "Enrolled" && ok "Enroll $n" || bad "Enroll $n"
  agentwait $i 1 $n && ok "$n hat v1 angewendet" || bad "$n Apply v1"
done
for i in 1 2 3 4; do r $i '/ip/dhcp-client/set [find where interface=ether1] add-default-route=no' >/dev/null; done

step "4. \$cfmCheck: Fehler in mlag.rsc und Bonds werden erkannt"
for f in mlag.rsc hosts/sw1.rsc hosts/sw2.rsc hosts/srv1.rsc; do echo "put $PWD/seed-mlag-phase/$f cfm/work/$f" | put 1; done
ck() { mgr ':global cfmCheck; :local c [$cfmCheck]; :foreach e in=($c->"err") do={ :put ("ERR " . $e) }; :foreach w in=($c->"warn") do={ :put ("WARN " . $w) }'; }
out=$(ck); echo "$out" | grep -q '^ERR' && bad "Umbau-Daten mit Fehlern: $(echo "$out" | grep '^ERR' | head -3)" || ok "Umbau-Daten ohne Fehler"
# gezielt kaputt machen: Port doppelt (Hostfile und mlag.rsc), Bond-Modus falsch, Knoten in anderem Ring
mgr ':local f [/file/find name="cfm/work/hosts/sw2.rsc"]; :local c [/file/get $f contents]; :local p [:find $c "\"ether5\"="]; /file/set $f contents=([:pick $c 0 $p] . "\"ether4\"=\"trunk\";" . [:pick $c $p [:len $c]])' >/dev/null
mgr ':local f [/file/find name="cfm/work/hosts/srv1.rsc"]; :local c [/file/get $f contents]; :local p [:find $c "\"slaves\""]; /file/set $f contents=([:pick $c 0 $p] . "\"mode\"=\"balance-rr\";" . [:pick $c $p [:len $c]])' >/dev/null
mgr ':global cfmInvLoad; :global cfmInvSave; :local i [$cfmInvLoad]; :set ($i->"sw2"->"ring") 1; $cfmInvSave $i' >/dev/null
out=$(ck)
echo "$out" | grep -q 'ERR mlag.rsc: core: sw2: Port ether4 (srv1) steht auch im Hostfile' && ok "Prüfung: Port in mlag.rsc und Hostfile" || bad "Port doppelt nicht erkannt: $(echo "$out" | grep ERR | head -3)"
echo "$out" | grep -q 'ERR hosts/srv1.rsc: bonds bond1: mode balance-rr' && ok "Prüfung: unbekannter Bond-Modus" || bad "Bond-Modus nicht erkannt"
echo "$out" | grep -q 'ERR mlag.rsc: core: .*denselben Ring' && ok "Prüfung: MLAG-Knoten in verschiedenen Ringen" || bad "Ring-Unterschied nicht erkannt"
for f in hosts/sw2.rsc hosts/srv1.rsc; do echo "put $PWD/seed-mlag-phase/$f cfm/work/$f" | put 1; done
mgr ':global cfmInvLoad; :global cfmInvSave; :local i [$cfmInvLoad]; :set ($i->"sw2"->"ring") 0; $cfmInvSave $i' >/dev/null
out=$(ck); echo "$out" | grep -q '^ERR' && bad "nach dem Zurücksetzen noch Fehler: $(echo "$out" | grep '^ERR' | head -2)" || ok "zurückgesetzt: keine Fehler"
a=$(mgr '$cfmShow host=sw1'); echo "$a" | grep -q 'peer-core *MLAG-Peer zu sw2 (primary), Slaves ether3,ether4' && echo "$a" | grep -q 'srv1 *MLAG-Bond, mlag-id 10' && ok "\$cfmShow sw1: Peer-Bond und MLAG-Bond" || bad "\$cfmShow sw1: $(echo "$a" | grep -A3 Bonds | tr '\n' '|')"
# mlag.rsc ist eine gemeinsame Datendatei: alle Geräte betroffen, Zeilen sichtbar (nicht nur die Hostfiles)
a=$(mgr '$cfmDiff'); echo "$a" | grep -qE '(geändert|neu): mlag.rsc' && echo "$a" | grep -q 'betroffen: alle Geräte' && echo "$a" | grep -q '^mlag.rsc:' && ok "\$cfmDiff: mlag.rsc betrifft alle Geräte, Zeilen sichtbar" || bad "\$cfmDiff mlag.rsc: $(echo "$a" | head -8 | tr '\n' '|')"

step "5. Umbau auf MLAG: Release an alle (sw1, sw2, srv1 gleichzeitig)"
rv=$(mgr '$cfmRelease msg=" MLAG" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
for n in sw1 sw2 srv1; do
  case $n in sw1) i=2;; sw2) i=3;; srv1) i=4;; esac
  agentwait $i "$rv" $n 75 && [ "$(stat $n res)" = ok ] && ok "$n hat v$rv angewendet" || bad "$n Apply v$rv: $(stat $n res)"
done
sleep 20
for i in 2 3; do [ "$(mstate $i)" = connected ] && ok "vm$i: MLAG verbunden" || bad "vm$i: MLAG $(mstate $i)"; done
expect 2 '[/interface/bridge/get [find name=bridge] mlag-peer-port] = "peer-core" and [/interface/bridge/get [find name=bridge] mlag-priority] = 50' "sw1: Peer-Port peer-core, mlag-priority 50 (primary)"
expect 3 '[/interface/bonding/get [find name=srv1] mlag-id] = 10 and [:len [/interface/bridge/port/find where interface=srv1]] = 1' "sw2: Bond srv1 mit mlag-id 10 in der Bridge"
expect 2 '[:typeof [:find [/interface/bridge/vlan/get [find where vlan-ids=30] tagged] "peer-core"]] = "num" and [/interface/bridge/port/get [find interface=peer-core] frame-types] = "admit-only-vlan-tagged"' "sw1: Peer-Bond trägt VLAN 30 getaggt, nur getaggte Frames"
[ "$(lacp 2 peer-core)" = "ether3:S ether4:S" ] && ok "Peer-Bond: beide Links per LACP aktiv" || bad "Peer-Bond LACP: $(lacp 2 peer-core)"
[ "$(lacp 4 bond1)" = "ether2:S ether3:S" ] && ok "srv1: Bond über sw1 und sw2, beide Links aktiv" || bad "srv1 LACP: $(lacp 4 bond1)"
[ "$(pings 4 '192.168.10.2')" -ge 4 ] && ok "srv1 erreicht cm1 über den Bond" || bad "srv1 -> cm1"
[ "$(pings 1 '192.168.10.22')" -ge 4 ] && ok "cm1 erreicht sw2 über sw1 und den Peer-Bond" || bad "cm1 -> sw2"

step "6. Ausfall: Link sw1-srv1 weg (an beiden Enden abgeschaltet, Socket-Links melden keinen Ausfall)"
r 2 '/interface/ethernet/disable ether5' >/dev/null; r 4 '/interface/ethernet/disable ether2' >/dev/null; sleep 5
[ "$(pings 4 '192.168.10.2')" -ge 4 ] && ok "srv1 erreicht cm1 über sw2 und den Peer-Bond" || bad "srv1 -> cm1 ohne Link zu sw1"
r 2 '/interface/ethernet/enable ether5' >/dev/null; r 4 '/interface/ethernet/enable ether2' >/dev/null; sleep 8
[ "$(lacp 4 bond1)" = "ether2:S ether3:S" ] && ok "srv1: nach der Rückkehr wieder beide Links aktiv" || bad "srv1 LACP nach Rückkehr: $(lacp 4 bond1)"

step "7. Idempotenz"
for n in sw1 sw2 srv1; do
  case $n in sw1) i=2;; sw2) i=3;; srv1) i=4;; esac
  pushwait $n $i
  stat $n stats | grep -q "add=0;rem=0;set=0;skip=0" && ok "$n: zweiter Apply ohne Änderungen" || bad "$n idempotent: $(stat $n stats)"
done

step "8. Rückbau: mlag.rsc leer, Hostfiles wie vorher"
mgr ':local f [/file/find name="cfm/work/mlag.rsc"]; /file/set $f contents=":global cfmMlag ({})\n"' >/dev/null
for f in sw1 sw2 srv1; do echo "put $PWD/seed-mlag/hosts/$f.rsc cfm/work/hosts/$f.rsc" | put 1; done
rv=$(mgr '$cfmRelease msg=" ohne MLAG" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
for n in sw1 sw2 srv1; do
  case $n in sw1) i=2;; sw2) i=3;; srv1) i=4;; esac
  agentwait $i "$rv" $n 75 && [ "$(stat $n res)" = ok ] && ok "$n hat v$rv angewendet" || bad "$n Apply v$rv: $(stat $n res)"
done
expect 2 '[:len [/interface/bonding/find]] = 0 and [/interface/bridge/get [find name=bridge] mlag-peer-port] = "none" and [:len [/interface/bridge/port/find where interface~"^ether[345]\$"]] = 3' "sw1: Bonds weg, kein Peer-Port, ether3-5 wieder Bridge-Ports"
expect 4 '[:len [/interface/bonding/find]] = 0 and [:len [/interface/bridge/port/find where interface~"^ether[23]\$"]] = 2' "srv1: Bond weg, ether2/3 wieder Trunks"
sleep 5
[ "$(pings 1 '192.168.10.23')" -ge 4 ] && ok "cm1 erreicht srv1 nach dem Rückbau" || bad "cm1 -> srv1 nach Rückbau"

step "9. cm1 wird Router (Gateway .1), noch ohne Isolation: Clients erreichen sich gegenseitig"
cping() { r 5 ":put [/ping $2 vrf=$1 count=4 interval=200ms]" | tail -1 | tr -dc 0-9; }  # cping <vrf> <ziel>
mgr ':global cfmInvLoad; :global cfmInvSave; :local i [$cfmInvLoad]; :set ($i->"cm1"->"role") "switch,router,manager"; $cfmInvSave $i' >/dev/null
echo "put $PWD/seed-mlag-iso/leases.rsc cfm/work/leases.rsc" | put 1
rv=$(mgr '$cfmRelease msg=" Router" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
for n in cm1 sw1 sw2 srv1; do
  case $n in cm1) i=1;; sw1) i=2;; sw2) i=3;; srv1) i=4;; esac
  agentwait $i "$rv" $n 75 && [ "$(stat $n res)" = ok ] && ok "$n hat v$rv angewendet" || bad "$n Apply v$rv: $(stat $n res)"
done
sleep 5
[ "$(cping a 192.168.30.1)" -ge 3 ] && [ "$(cping c 192.168.30.1)" -ge 3 ] && ok "a und c erreichen das Gateway" || bad "Gateway: a $(cping a 192.168.30.1), c $(cping c 192.168.30.1)"
[ "$(cping a 192.168.30.72)" -ge 3 ] && ok "ohne Isolation: a -> b (gleicher Switch)" || bad "a -> b ohne Isolation"
[ "$(cping a 192.168.30.73)" -ge 3 ] && ok "ohne Isolation: a -> c (anderer Switch)" || bad "a -> c ohne Isolation"

step "10. IoT-VLAN isoliert (D76), Ausnahme cl-c"
echo "put $PWD/seed-mlag-iso/vlans.rsc cfm/work/vlans.rsc" | put 1
out=$(ck); echo "$out" | grep -q '^ERR' && bad "Isolation: Prüfung meldet Fehler: $(echo "$out" | grep '^ERR' | head -2)" || ok "Isolation: Prüfung ohne Fehler"
rv=$(mgr '$cfmRelease msg=" Isolation" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
for n in cm1 sw1 sw2 srv1; do
  case $n in cm1) i=1;; sw1) i=2;; sw2) i=3;; srv1) i=4;; esac
  agentwait $i "$rv" $n 75 && [ "$(stat $n res)" = ok ] && ok "$n hat v$rv angewendet" || bad "$n Apply v$rv: $(stat $n res)"
done
expect 2 '[/interface/bridge/port/get [find interface=ether6] hw] = false and [:len [/interface/list/member/find where list=cfm-iso and interface~"^ether[67]\$"]] = 2' "sw1: ether6/7 in cfm-iso, hw=no"
expect 2 '[/interface/bridge/port/get [find interface=ether2] hw] = true' "sw1: Trunk ether2 bleibt im Switch-Chip (hw=yes)"
expect 4 '[:len [/interface/bridge/filter/find where comment~"^cfm:iso"]] = 0' "srv1 (keine Client-Ports, kein WLAN): keine Filterregeln"
# Gateway an der MAC des Routers (cm1, Bridge-MAC aus dessen Status, Manifest-Feld rmac)
cmac=$(r 1 ':put [/interface/bridge/get [find where name="bridge"] mac-address]' | tail -1)
expect 2 '[:len [/interface/bridge/filter/find where comment~"^cfm:iso" and dst-mac-address~"^'"$cmac"'/"]] = 1' "sw1: Filter erlaubt die MAC des Routers cm1 ($cmac)"
sleep 3
[ "$(cping a 192.168.30.1)" -ge 3 ] && ok "isoliert: a erreicht das Gateway" || bad "isoliert: a -> Gateway"
[ "$(cping b 192.168.30.1)" -ge 3 ] && ok "isoliert: b erreicht das Gateway" || bad "isoliert: b -> Gateway"
[ "$(cping c 192.168.30.1)" -ge 3 ] && ok "isoliert: c (an sw2) erreicht das Gateway" || bad "isoliert: c -> Gateway"
r 5 '/ip/arp/remove [find]' >/dev/null
[ "$(cping a 192.168.30.72)" = 0 ] && ok "isoliert: a -> b gesperrt (gleicher Switch)" || bad "isoliert: a -> b offen"
[ "$(cping b 192.168.30.71)" = 0 ] && ok "isoliert: b -> a gesperrt" || bad "isoliert: b -> a offen"
[ "$(cping a 192.168.30.73)" -ge 3 ] && ok "Ausnahme: a -> c (cl-c aus leases.rsc)" || bad "Ausnahme a -> c geht nicht"
[ "$(cping c 192.168.30.72)" -ge 3 ] && ok "Ausnahme: c -> b" || bad "Ausnahme c -> b geht nicht"
pushwait sw1 2
stat sw1 stats | grep -q "add=0;rem=0;set=0;skip=0" && ok "sw1: zweiter Apply mit Isolation ohne Änderungen" || bad "sw1 idempotent mit Isolation: $(stat sw1 stats)"
a=$(mgr '$cfmShow host=sw1'); echo "$a" | grep -qE '^ *30 .*isoliert' && ok "\$cfmShow: VLAN 30 isoliert" || bad "\$cfmShow ohne Hinweis auf Isolation"

step "11. Isolation wieder aus"
echo "put $PWD/seed-mlag/vlans.rsc cfm/work/vlans.rsc" | put 1
rv=$(mgr '$cfmRelease msg=" ohne Isolation" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
for n in sw1 sw2; do
  case $n in sw1) i=2;; sw2) i=3;; esac
  agentwait $i "$rv" $n 75 && [ "$(stat $n res)" = ok ] && ok "$n hat v$rv angewendet" || bad "$n Apply v$rv: $(stat $n res)"
done
expect 2 '[/interface/bridge/port/get [find interface=ether6] hw] = true and [:len [/interface/bridge/filter/find where comment~"^cfm:iso"]] = 0 and [:len [/interface/list/member/find where list=cfm-iso]] = 0' "sw1: hw wieder an, keine Filter, Liste leer"
[ "$(cping a 192.168.30.72)" -ge 3 ] && ok "ohne Isolation: a -> b wieder offen" || bad "a -> b nach dem Abschalten"

echo; echo "Ergebnis: $pass ok, $fail fehlgeschlagen"; [ $fail -eq 0 ]
