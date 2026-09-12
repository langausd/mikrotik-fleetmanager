#!/usr/bin/env bash
# ------------------------------------------------------------------
# Ende-zu-Ende-Test des cfm-Frameworks im CHR-Labor.
#   vm1 = cm1 (Primary-Manager)   vm2 = sw1 (Testgerät)   vm3 = cm2 (Backup-Manager)
# Stern-Topologie (lab.sh): cm1 ether2/ether3 <-> sw1/cm2 ether2 (Trunks, MGMT-VLAN 10),
# ether1 ist der SSH-Zugang vom Host (QEMU-User-Net, 10.0.2.0/24 = mgmtExtra).
#
#   ./e2e.sh [fresh]      fresh = VM-Disks neu aus dem CHR-Image
# Voraussetzung: CHR-Image in $LAB (siehe lab.sh).
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
r()    { ./lab.sh ssh "$@" 2>&1 | tr -d '\r'; }        # r <vm> '<ros cmd>'
put()  { printf '#!/bin/sh\necho ""\n' > "$LAB/askpass"
         SSH_ASKPASS="$LAB/askpass" SSH_ASKPASS_REQUIRE=force sftp -q -b - -P $((2200+$1*10)) "${O[@]}" -i "$LAB/lab_key" admin@127.0.0.1 >/dev/null; }
get()  { echo "get $2 $3" | put "$1"; }
mgr()  { r 1 "/system script run cfm-mgr; $1"; }      # Manager-Funktion auf cm1
waitssh() { for _ in $(seq 1 60); do r "$1" ':put up' | grep -q up && return 0; sleep 2; done; return 1; }
expect() { # expect <vm> '<ros-ausdruck, der true liefert>' <beschreibung>
  if r "$1" ":put ($2)" | grep -q true; then ok "$3"; else bad "$3"; fi; }
stat() { mgr ':global cfmJson; :put [:tostr ([$cfmJson "cfm/state/'"$1"'/status.dat"]->"'"$2"'")]' | tail -1; }
diag() { # diag <name>: Zustand von cm1 und sw1 nach $LAB/diag-<name>.txt (über ether1, unabhängig vom MGMT-Netz)
  { echo "### cm1 -> sw1"; r 1 ':put ("ping: " . [/ping 192.168.10.21 count=3]); /ip/arp/print where address~"192.168.10."; /interface/bridge/port/print; /interface/bridge/host/print where vid=10; /log/print where !(topics~"debug")'
    echo; echo "### sw1"; r 2 ':put ("ping: " . [/ping 192.168.10.2 count=3]); /ip/address/print; /interface/bridge/print; /interface/bridge/port/print; /interface/bridge/vlan/print; /ip/service/print; /system/script/job/print; /system/scheduler/print; /user/print; /log/print'
  } > "$LAB/diag-$1.txt" 2>&1; echo "    (Diagnose: $LAB/diag-$1.txt)"; }
agentwait() { # warten bis Agent auf vm $1 v$2 gemeldet hat
  for _ in $(seq 1 45); do mgr ':global cfmJson; :put [:tostr ([$cfmJson "cfm/state/'"$3"'/status.dat"]->"v")]' | grep -qx "$2" && return 0; sleep 4; done; return 1; }

if [ "${1:-}" = fresh ]; then
  step "VMs neu aufsetzen"
  ./lab.sh stop >/dev/null; rm -f "$LAB"/vm*.qcow2; ./lab.sh start 3
fi
for i in 1 2 3; do waitssh $i || { echo "vm$i nicht erreichbar"; exit 1; }; done

step "1. Seed auf cm1 + Manager-Bootstrap"
SFTP_OPTS="-i $LAB/lab_key ${O[*]}" SSH_ASKPASS="$LAB/askpass" SSH_ASKPASS_REQUIRE=force \
  "$ROOT/tools/upload-seed.sh" admin@127.0.0.1 --port 2210 --overlay "$PWD/seed" >/dev/null && ok "Seed hochgeladen"
sed -e 's/^:local uplink "ether1"/:local uplink "ether2"/' "$ROOT/bootstrap/bootstrap-manager.rsc" > "$LAB/bm.rsc"
echo "put $LAB/bm.rsc bootstrap-manager.rsc" | put 1
out=$(r 1 '/import bootstrap-manager.rsc verbose=no')
echo "$out" | grep -q "Primary-Manager bereit" && ok "Manager-Bootstrap" || { bad "Manager-Bootstrap"; echo "$out" | tail -5; }
agentwait 1 1 cm1 && ok "cm1 hat v1 angewendet" || bad "cm1 Apply v1"
expect 1 '[:len [/system/script/find where name~"^cfm-mgr-" and comment~"^cfm:sys:mgr-"]] = 4' "cm1: 4 Manager-Module als Skripte (von der Rolle übernommen)"
mgr '$cfmSecret key=user.netadmin value="Lab-Passw0rd!"; $cfmSecret key=psk.main value="lab-psk-12345"; $cfmSecret key=vaultpw value="vault-lab-pw"' >/dev/null

step "2. Geräte-Bootstrap sw1 + Enroll"
mgr '$cfmBootstrap' >/dev/null
get 1 cfm/cfm-bootstrap.rsc "$LAB/bs.rsc"
sed -e 's|^:local ip ".*"|:local ip "192.168.10.21/24"|' -e 's/^:local uplink "ether1"/:local uplink "ether2"/' "$LAB/bs.rsc" > "$LAB/bs-sw1.rsc"
echo "put $LAB/bs-sw1.rsc cfm-bootstrap.rsc" | put 2
r 2 '/import cfm-bootstrap.rsc verbose=no' | grep -q "Bootstrap fertig" && ok "Bootstrap sw1" || bad "Bootstrap sw1"
mgr '$cfmEnroll name=sw1 ip=192.168.10.21 role=switch ring=0' | grep -q "Enrolled" && ok "Enroll sw1" || bad "Enroll sw1"
agentwait 2 1 sw1 && ok "sw1 hat v1 angewendet" || bad "sw1 Apply v1"
expect 2 '[/interface/bridge/get bridge vlan-filtering]' "sw1: VLAN-Filtering aktiv"
expect 2 '[:len [/interface/bridge/vlan/find where comment="cfm:bv:119"]] = 1' "sw1: Trunk trägt VLAN 119"
expect 2 '[:len [/ip/address/find where address="192.168.10.21/24"]] = 1' "sw1: MGMT-IP"

step "3. Secrets-Push & Idempotenz"
sleep 70
expect 2 '[/user/get [find name=netadmin] disabled] = false' "sw1: User netadmin per Secret-Push aktiviert"
t0=$(stat sw1 t); mgr '$cfmPush host=sw1 force=yes' >/dev/null
for _ in $(seq 1 40); do [ "$(stat sw1 t)" != "$t0" ] && break; sleep 3; done
stat sw1 stats | grep -q "add=0;rem=0;set=0;skip=0" && ok "zweiter Apply ohne Änderungen (idempotent)" || bad "Idempotenz: $(stat sw1 stats)"

step "4. VLAN entfernen -> Reconciler räumt auf"
mgr ':local f [/file/find name="cfm/work/vlans.rsc"]; /file/set $f contents=[:pick [/file/get $f contents] 0 [:find [/file/get $f contents] ":for i from=101"]]; :global cfmRelease; $cfmRelease msg=" ohne 101-119"' >/dev/null
agentwait 2 2 sw1 && ok "sw1 hat v2 angewendet" || bad "sw1 Apply v2"
expect 2 '[:len [/interface/bridge/vlan/find where comment~"^cfm:bv:1[01][0-9]\$"]] = 0' "sw1: VLANs 101-119 entfernt"

step "5. Audit: Hand-Objekt anzeigen und markieren"
r 2 '/ip/dns/static/add name=hand.lan address=192.168.10.99' >/dev/null
mgr '$cfmAudit host=sw1' | grep -q "hand.lan" && ok "Audit zeigt hand.lan" || bad "Audit report"
ref=$(mgr '$cfmAudit host=sw1' | grep "hand.lan" | awk '{print $1}')
mgr "\$cfmAudit host=sw1 op=mark sel=$ref" >/dev/null
expect 2 '[/ip/dns/static/get [find name=hand.lan] comment] ~ "^cfm-override"' "Audit mark -> cfm-override"

step "6. Kaputte Version -> Rollback + bad"
mgr ':local f [/file/find name="cfm/work/hosts/sw1.rsc"]; /file/set $f contents=":global cfmHost {\"ports\"={\"ether2\"=\"gibtsnicht\"}}"; :global cfmRelease; $cfmRelease msg=" kaputt"' >/dev/null
for _ in $(seq 1 60); do [ "$(stat sw1 bad)" = 3 ] && break; sleep 4; done
if [ "$(stat sw1 bad)" = 3 ]; then ok "v3 als bad gemeldet ($(stat sw1 res | cut -c1-60))"; else bad "Rollback/bad: $(stat sw1 res)"; diag step6; fi
waitssh 2; sleep 20
expect 2 '[:len [/ip/address/find where address="192.168.10.21/24"]] = 1' "sw1 nach Rollback erreichbar konfiguriert"
mgr '$cfmRollback ver=2 all=yes' >/dev/null

step "7. Backup-Manager cm2"
echo "put $LAB/bs.rsc cfm-bootstrap.rsc" | put 3
sed -e 's|^:local ip ".*"|:local ip "192.168.10.3/24"|' -e 's/^:local uplink "ether1"/:local uplink "ether2"/' "$LAB/bs.rsc" > "$LAB/bs-cm2.rsc"
echo "put $LAB/bs-cm2.rsc cfm-bootstrap.rsc" | put 3
r 3 '/import cfm-bootstrap.rsc verbose=no' >/dev/null
mgr '$cfmEnroll name=cm2 ip=192.168.10.3 role=manager-backup ring=0' | grep -q Enrolled && ok "Enroll cm2" || bad "Enroll cm2"
agentwait 3 4 cm2 && ok "cm2 hat v4 angewendet" || bad "cm2 Apply"
expect 3 '[:tostr [/interface/wifi/capsman/get enabled]] ~ "no|false"' "cm2: CAPsMAN passiv"
expect 1 '[:tostr [/interface/wifi/capsman/get enabled]] ~ "yes|true"' "cm1: CAPsMAN aktiv"
expect 1 '[:len [/interface/wifi/provisioning/find where comment~"^cfm:wprov"]] >= 2' "cm1: Provisioning-Regeln gerendert"

step "8. Rolle router auf sw1 (über den echten Agent-Pfad)"
mgr ':local f [/file/find name="cfm/meta/inventory.rsc"]; :local c [/file/get $f contents]; :local p [:find $c "\"role\"=\"switch\""]; /file/set $f contents=([:pick $c 0 $p] . "\"role\"=\"switch,router\"" . [:pick $c ($p + 15) [:len $c]]); :global cfmManifests; $cfmManifests' >/dev/null
mgr '$cfmPush host=sw1' >/dev/null
for _ in $(seq 1 60); do [ "$(stat sw1 role)" = "switch,router" ] && [ "$(stat sw1 res)" = ok ] && break; sleep 4; done
[ "$(stat sw1 role)" = "switch,router" ] && [ "$(stat sw1 res)" = ok ] && ok "sw1 als switch,router angewendet" || bad "Router-Apply: $(stat sw1 role) $(stat sw1 res)"
expect 2 '[:len [/ip/firewall/filter/find where comment~"^cfm:fw"]] > 15' "sw1: Zonen-Firewall-Block"
expect 2 '[:len [/interface/vrrp/find where comment~"^cfm:vrrp"]] >= 4' "sw1: VRRP je VLAN"
expect 2 '[:len [/ip/dhcp-server/find where comment~"^cfm:dhcp"]] = 2' "sw1: DHCP für IoT + Gast"
t0=$(stat sw1 t); mgr '$cfmPush host=sw1 force=yes' >/dev/null
for _ in $(seq 1 60); do [ "$(stat sw1 t)" != "$t0" ] && break; sleep 4; done
stat sw1 stats | grep -q "add=0;rem=0;set=0;skip=0" && ok "Router-Rolle idempotent" || bad "Router idempotent: $(stat sw1 stats)"

step "9. Backup-Spiegel & Vault-Backup"
for _ in $(seq 1 50); do r 3 ':put ([:len [/file/find where name="cfm/meta/rings.dat"]] + [:len [/file/find where name="cfm/archive/v4/index.dat"]])' | grep -qx 2 && break; sleep 8; done
expect 3 '[:len [/file/find where name="cfm/archive/v4/lib/agent.rsc"]] = 1' "cm2: Archiv v4 gespiegelt"
expect 3 '[:len [/file/find where name="cfm/meta/rings.dat"]] = 1' "cm2: Ringe gespiegelt"
expect 1 '[:len [/file/find where name~"^cfm/vault/.*-vault.bak"]] = 1' "cm1: verschlüsseltes Vault-Backup (.bak)"

step "10. Werks-User admin abschalten (zuletzt: danach kein admin-SSH mehr auf sw1)"
# Antwort mit Markierung, weil die ssh-exec-Ausgabe mit Zeilenumbruch endet (tail -1 wäre leer)
chk() { mgr ':global cfmExec; :local r [$cfmExec ip=192.168.10.21 cmd="'"$1"'"]; :put ("RES=" . ($r->"output"))' | sed -n 's/^RES=//p' | head -1; }
v0=$(stat sw1 v)
mgr ':local f [/file/find name="cfm/work/hosts/sw1.rsc"]; :local c [/file/get $f contents]; :local p [:find $c "\"keep\""]; /file/set $f contents=([:pick $c 0 $p] . "\"disable\"" . [:pick $c ($p + 6) [:len $c]]); $cfmRelease msg=" admin aus auf sw1"' >/dev/null
for _ in $(seq 1 60); do [ "$(stat sw1 v)" != "$v0" ] && [ "$(stat sw1 res)" = ok ] && break; sleep 4; done
[ "$(stat sw1 res)" = ok ] && ok "sw1 hat v$(stat sw1 v) angewendet" || bad "sw1 Apply: $(stat sw1 res)"
a=$(chk ':put [/user/get [find name=admin] disabled]')
if [ "$a" = true ]; then ok "sw1: admin deaktiviert"; else bad "sw1: admin noch aktiv (Antwort: '$a')"; diag step10; fi
a=$(chk ':put [/user/get [find name=netadmin] disabled]')
[ "$a" = false ] && ok "sw1: eigener User netadmin aktiv" || bad "sw1: netadmin nicht aktiv (Antwort: '$a')"
printf '#!/bin/sh\necho "Lab-Passw0rd!"\n' > "$LAB/askpass-netadmin"; chmod +x "$LAB/askpass-netadmin"
out=$(SSH_ASKPASS="$LAB/askpass-netadmin" SSH_ASKPASS_REQUIRE=force ssh -p 2210 "${O[@]}" -o PubkeyAuthentication=no netadmin@127.0.0.1 '/system script run cfm-mgr; $cfmPush host=sw1' 2>&1 | tr -d '\r')
echo "$out" | grep -q "Push -> sw1" && ! echo "$out" | grep -q FEHLER && ok "cm1: Manager-Befehle unter eigenem User (netadmin)" || bad "netadmin: $(echo "$out" | tail -1)"

echo; echo "Ergebnis: $pass ok, $fail fehlgeschlagen"; [ $fail -eq 0 ]
