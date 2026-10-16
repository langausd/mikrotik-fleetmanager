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
export LABPORT=${LABPORT:-2200} LABSOCK=${LABSOCK:-12000}
O=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
pass=0; fail=0
ok()   { echo "  ✔ $*"; pass=$((pass+1)); }
bad()  { echo "  ✘ $*"; fail=$((fail+1)); }
step() { echo; echo "== $*"; }
r()    { ./lab.sh ssh "$@" 2>&1 | tr -d '\r'; }        # r <vm> '<ros cmd>'
put()  { printf '#!/bin/sh\necho ""\n' > "$LAB/askpass"
         SSH_ASKPASS="$LAB/askpass" SSH_ASKPASS_REQUIRE=force sftp -q -b - -P $((LABPORT+$1*10)) "${O[@]}" -i "$LAB/lab_key" admin@127.0.0.1 >/dev/null; }
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
agentwait() { # warten bis Agent auf vm $1 v$2 gemeldet hat; $4 = Anzahl Versuche à 4 s (Standard 45 = 3 min)
  for _ in $(seq 1 "${4:-45}"); do mgr ':global cfmJson; :put [:tostr ([$cfmJson "cfm/state/'"$3"'/status.dat"]->"v")]' | grep -qx "$2" && return 0; sleep 4; done; return 1; }

if [ "${1:-}" = fresh ]; then
  step "VMs neu aufsetzen"
  ./lab.sh stop >/dev/null; rm -f "$LAB"/vm*.qcow2; ./lab.sh start 3
fi
for i in 1 2 3; do waitssh $i || { echo "vm$i nicht erreichbar"; exit 1; }; done

step "1. Seed auf cm1 + Manager-Bootstrap"
SFTP_OPTS="-i $LAB/lab_key ${O[*]}" SSH_ASKPASS="$LAB/askpass" SSH_ASKPASS_REQUIRE=force \
  "$ROOT/tools/upload-seed.sh" admin@127.0.0.1 --port $((LABPORT+10)) --overlay "$PWD/seed" --seed-inventory >/dev/null && ok "Seed hochgeladen" || bad "Seed hochladen fehlgeschlagen"
# clean="yes" (Standard): Reset auf leere Config, danach läuft der Bootstrap selbst weiter.
# post sichert den Host-Zugang über ether1 per DHCP-Client (CHR legt ihn nach dem Reset meist
# selbst wieder an, deshalb nur, wenn er fehlt).
sed -e 's/^:local uplink "ether1"/:local uplink "ether2"/' \
    -e 's|^:local post ""|:local post ":if ([:len [/ip/dhcp-client/find where interface=ether1]] = 0) do={ /ip/dhcp-client/add interface=ether1 disabled=no }"|' \
    "$ROOT/bootstrap/bootstrap-manager.rsc" > "$LAB/bm.rsc"
echo "put $LAB/bm.rsc bootstrap-manager.rsc" | put 1
out=$(timeout 90 ./lab.sh ssh 1 '/import bootstrap-manager.rsc verbose=no' 2>&1 | tr -d '\r')   # Sitzung endet mit dem Reset
echo "$out" | grep -q "Reset auf leere Config" && ok "Manager-Bootstrap Stufe 1: Reset auf leere Config" || { bad "Manager-Bootstrap Stufe 1"; echo "$out" | tail -5; }
sleep 15; waitssh 1
for _ in $(seq 1 60); do r 1 ':put [:len [/log/find where message="cfm: Primary-Manager bereit"]]' | tail -1 | grep -qx 1 && break; sleep 5; done
if r 1 ':put [:len [/log/find where message="cfm: Primary-Manager bereit"]]' | tail -1 | grep -qx 1; then ok "Manager-Bootstrap Stufe 2 nach dem Reset"; else bad "Manager-Bootstrap Stufe 2"; r 1 '/log/print where message~"cfm: "' | tail -5; fi
expect 1 '[:len [/interface/bridge/find]] = 1 and [:len [/ip/dhcp-client/find where interface=ether1]] = 1 and [:len [/file/find where name~"bootstrap-(stufe|uebergabe)|cfm-uebergabe"]] = 0 and [:len [/system/scheduler/find where name~"^cfm-bootstrap"]] = 0 and [:len [/log/find where message="cfm: Bootstrap - post erledigt"]] = 1' "cm1: leere Config mit Bootstrap (eine Bridge, DHCP-Client, post erledigt, keine Markierungen und Übergabe-Scheduler mehr)"
expect 1 '[:len [/log/find where message="cfm: Bootstrap Stufe 3 als cfm"]] = 1' "cm1: Bootstrap nach dem Reset an cfm übergeben (Stufe 3 als cfm)"
agentwait 1 1 cm1 && ok "cm1 hat v1 angewendet" || bad "cm1 Apply v1"
expect 1 '[:len [/system/script/find where name~"^cfm-mgr-" and comment~"^cfm:sys:mgr-"]] = 10' "cm1: 10 Manager-Module als Skripte (von der Rolle übernommen)"
expect 1 '[/system/scheduler/get [find name="cfm-mgr-tick"] on-event] ~ "cfm-mgr-onb-tick" and [/system/scheduler/get [find name="cfm-mgr-onb-tick"] on-event] ~ "cfmTickBusy"' "cm1: die beiden Manager-Ticks sperren sich gegenseitig"
expect 1 '[:len [/ip/firewall/filter/find where comment~"^cfm:fwb" and dst-port="67"]] = 1' "cm1: minimale Firewall erlaubt DHCP im Onboarding-VLAN"
expect 1 '(([/ip/ssh/get]->"known-hosts-validation") != true)' "cm1: SSH-Client ohne Host-Key-Prüfung (ab 7.25 nach dem Reset an, D71)"
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
expect 2 '[:len [/ip/firewall/filter/find where comment~"^cfm:fwb"]] = 9 and [/ip/firewall/filter/get [find where comment="cfm:fwb:08"] action] = "drop"' "sw1: minimale Firewall IPv4 (9 Regeln, zuletzt drop)"
expect 2 '[:len [/ipv6/firewall/filter/find where comment~"^cfm:fw6"]] = 8' "sw1: minimale Firewall IPv6 (8 Regeln)"
expect 2 '[/ip/neighbor/discovery-settings/get discover-interface-list] = "DISC" and [:len [/interface/list/member/find where list="DISC" and interface="ether2"]] = 1' "sw1: Nachbarsuche auf den Bridge-Ports (Liste DISC)"
expect 2 '[/ip/service/get [:pick [find where name="reverse-proxy" and !dynamic] 0] disabled]' "sw1: Dienst reverse-proxy aus (ab Werk offen auf 443, TODO 30)"
r 2 '/system/script/add name=cfm-e2e-x source=":put 1"; /system/script/remove cfm-e2e-x; :log info "cfm-e2e-b"' >/dev/null
expect 2 '[:tostr [/system/logging/get [find where action="memory" and default and topics~"info"] topics]] = "info;!system" and [:len [/log/find where message="cfm-e2e-b"]] = 1 and [:len [/log/find where topics~"system" and message~"cfm-e2e-x"]] = 0' "sw1: RAM-Log ohne system,info, script,info kommt an (D79)"
expect 2 '(([/ip/ssh/get]->"known-hosts-validation") != true)' "sw1: SSH-Client ohne Host-Key-Prüfung (D71)"
case "$(stat sw1 ros)" in *" ("*) ok "sw1: RouterOS-Version mit Kanal gemeldet (bleibt beim Manager Text, 7.25)";; *) bad "sw1: ros=$(stat sw1 ros)";; esac

step "3. Secrets-Push & Idempotenz"
sleep 70
expect 2 '[/user/get [find name=netadmin] disabled] = false' "sw1: User netadmin per Secret-Push aktiviert"
t0=$(stat sw1 t); mgr '$cfmPush host=sw1 force=yes' >/dev/null
for _ in $(seq 1 40); do [ "$(stat sw1 t)" != "$t0" ] && break; sleep 3; done
stat sw1 stats | grep -q "add=0;rem=0;set=0;skip=0" && ok "zweiter Apply ohne Änderungen (idempotent)" || bad "Idempotenz: $(stat sw1 stats)"
# Platzhalter im Inventar (wie noch nicht aufgenommene Geräte eines Standorts, TODO 28): bleibt bis
# nach Schritt 13 stehen, damit Release, Trust, Spiegel, Secret-Push und Upgrade ihn überspringen müssen
mgr '$cfmRegister name=ph1 serial=SERIAL-PH1 ip=192.168.10.98 role=switch ring=0' >/dev/null
out=$(mgr '$cfmPush')
echo "$out" | grep -q "kein Push (nicht aufgenommen): ph1" && ! echo "$out" | grep -q "Push -> ph1" && echo "$out" | grep -q "Push -> sw1" && ok "Push lässt den Platzhalter aus (TODO 28)" || { bad "Push an Platzhalter"; echo "$out" | tail -3; }
mgr '$cfmStatus' | grep "^ph1" | grep -q "nicht aufgenommen" && ok "\$cfmStatus: ph1 nicht aufgenommen" || bad "\$cfmStatus ohne Hinweis auf ph1"
mgr ':put ("SP=" . [$cfmSecretPush])' >/dev/null
expect 1 '[:len [/log/find where message~"Secret-Push ph1"]] = 0' "Secret-Push ohne Warnung zum Platzhalter"
# Agent von Hand aus einer Admin-Sitzung (TODO 35): klare Meldung statt nur "kein Manager erreichbar"
for _ in 1 2 3; do out=$(r 2 '/system script run cfm-agent'); echo "$out" | grep -q "läuft bereits" || break; sleep 35; done
echo "$out" | grep -q "der Agent läuft als admin" && ok "Agent aus einer Admin-Sitzung: klare Meldung" || { bad "Agent als admin: $(echo "$out" | tail -1)"; }

step "4. VLAN entfernen -> Reconciler räumt auf"
mgr ':local f [/file/find name="cfm/work/vlans.rsc"]; /file/set $f contents=[:pick [/file/get $f contents] 0 [:find [/file/get $f contents] ":for i from=101"]]; :global cfmRelease; $cfmRelease msg=" ohne 101-119"' >/dev/null
agentwait 2 2 sw1 && ok "sw1 hat v2 angewendet" || bad "sw1 Apply v2"
expect 2 '[:len [/interface/bridge/vlan/find where comment~"^cfm:bv:1[01][0-9]\$"]] = 0' "sw1: VLANs 101-119 entfernt"

step "5. Audit: Hand-Objekt anzeigen und markieren"
r 2 '/ip/dns/static/add name=hand.lan address=192.168.10.99' >/dev/null
mgr '$cfmAudit host=sw1' | grep -q "hand.lan" && ok "Audit zeigt hand.lan" || bad "Audit report"
# $cfmLoadData importiert lib/lib.rsc: der Manager-Befehl $cfmAudit muss das überstehen
r 1 '/system script run cfm-mgr; :global cfmLoadData; $cfmLoadData; :global cfmAudit; $cfmAudit host=sw1' | grep -q "hand.lan" && ok "Audit nach \$cfmLoadData (kein Namenskonflikt mit lib.rsc)" || bad "Audit nach \$cfmLoadData liefert nichts"
mgr '$cfmAudit host=sw1' | grep -qE "/user name=admin|action=cfmremote" && bad "Audit meldet von base verwaltete Objekte (admin, Syslog)" || ok "Audit ohne Fehlalarme (admin, Syslog)"
ref=$(mgr '$cfmAudit host=sw1' | grep "hand.lan" | awk '{print $1}')
mgr "\$cfmAudit host=sw1 op=mark sel=$ref" >/dev/null
expect 2 '[/ip/dns/static/get [find name=hand.lan] comment] ~ "^cfm-override"' "Audit mark -> cfm-override"

step "6. Probelauf (\$cfmPlan): zeigt Änderungen, wendet nichts an"
mgr ':global e2eV [/file/get [/file/find name="cfm/work/vlans.rsc"] contents]; /file/set [/file/find name="cfm/work/vlans.rsc"] contents=($e2eV . ":set (\$cfmVlans->\"99\") {\"name\"=\"PLAN\";\"zone\"=\"lan\"}\n")' >/dev/null
v0=$(stat sw1 v)
out=$(mgr '$cfmPlan host=sw1')
echo "$out" | grep -q "bv:99" && ok "Plan zeigt das neue Bridge-VLAN 99" || { bad "Plan ohne bv:99"; echo "$out" | tail -5; }
echo "$out" | grep -q "# Plan sw1" && ok "Plan-Zusammenfassung vom Gerät" || bad "keine Plan-Zusammenfassung"
expect 2 '[:len [/interface/bridge/vlan/find where comment="cfm:bv:99"]] = 0' "sw1: Probelauf hat nichts angewendet"
[ "$(stat sw1 v)" = "$v0" ] && ok "sw1: Version unverändert (v$v0)" || bad "sw1: Version nach dem Probelauf geändert"
# zweiter Probelauf direkt danach: plan/ wird geleert und neu geschrieben ("no such item" auf Hardware)
out=$(mgr '$cfmPlan host=sw1; $cfmPlan host=sw1')
[ "$(echo "$out" | grep -c '# Plan sw1')" = 2 ] && ! echo "$out" | grep -q "no such item" && ok "zwei Probeläufe direkt hintereinander" || { bad "zwei Probeläufe hintereinander"; echo "$out" | grep -E "no such|Plan sw1" | head -3; }
mgr ':global e2eV; /file/set [/file/find name="cfm/work/vlans.rsc"] contents=$e2eV' >/dev/null
# Probe eines Umbaus (from=, role=): Stand aus cfm/umzug/, Rolle router nur für diesen Probelauf
mgr ':global cfmWrite; :foreach f in=[/file/find where name~"^cfm/work/" and type!="directory"] do={ :local n [/file/get $f name]; $cfmWrite ("cfm/umzug/" . [:pick $n 9 [:len $n]]) [/file/get $f contents] }; :global e2eV [/file/get [/file/find name="cfm/umzug/vlans.rsc"] contents]; /file/set [/file/find name="cfm/umzug/vlans.rsc"] contents=($e2eV . ":set (\$cfmVlans->\"98\") {\"name\"=\"UMZUG\";\"zone\"=\"lan\";\"dhcp\"=\"100-199\"}\n")' >/dev/null
out=$(mgr '$cfmPlan host=sw1 from=umzug role=switch,router')
# VLAN 98 mit DHCP: VRRP-Interface und DHCP-Server gibt es im Probelauf noch nicht (router.rsc fragte
# den VRRP-Zustand ab und brach ab, gefunden beim Probelauf des Router-Umzugs 2026-10-11)
echo "$out" | grep -q "Probelauf aus cfm/umzug/, Rollen switch,router" && echo "$out" | grep -q "bv:98" && echo "$out" | grep -q "il:Z-" && echo "$out" | grep -q "vrrp:98" && echo "$out" | grep -q "dhcp:98" && ! echo "$out" | grep -q "FEHLER" && ok "Probelauf aus cfm/umzug/ mit Rolle router (VLAN 98 mit VRRP und DHCP, Zonen-Listen, ohne Fehler)" || { bad "Probelauf from=/role="; echo "$out" | tail -6; }
expect 1 '[:typeof [:find [/file/get [/file/find name="cfm/work/vlans.rsc"] contents] "UMZUG"]] = "nil"' "work/ bleibt beim Probelauf aus cfm/umzug/ unverändert"
[ "$(stat sw1 v)" = "$v0" ] && expect 2 '[:len [/interface/list/find where comment~"^cfm:il:Z-"]] = 0' "sw1: Probelauf mit role=router hat nichts angewendet" || bad "sw1: Version nach dem Probelauf geändert"
out=$(mgr ':onerror e in={ $cfmPlan host=sw1 from=work } do={ :put ("ERR " . $e) }')
echo "$out" | grep -q "ERR from=work" && ok "from=work abgelehnt (nur eigene Verzeichnisse)" || { bad "from=work nicht abgelehnt"; echo "$out" | tail -2; }
mgr ':foreach f in=[/file/find where name~"^cfm/umzug"] do={ :onerror e in={ /file/remove $f } do={} }' >/dev/null

step "7. Kaputte Version -> Prüfung stoppt, mit force: Rollback + bad"
# unbekannter Dienstname und doppelter Port (www-ssl und reverse-proxy auf 443) sind Fehler (TODO 30)
out=$(mgr ':global e2eG [/file/get [/file/find name="cfm/work/global.rsc"] contents]; /file/set [/file/find name="cfm/work/global.rsc"] contents=($e2eG . ":set (\$cfmG->\"services\"->\"http\") 80\n:set (\$cfmG->\"services\"->\"www-ssl\") 443\n:set (\$cfmG->\"services\"->\"reverse-proxy\") 443\n"); :global cfmCheck; :local ck [$cfmCheck]; :foreach e in=($ck->"err") do={ :put ("ERR " . $e) }; /file/set [/file/find name="cfm/work/global.rsc"] contents=$e2eG')
echo "$out" | grep -q "ERR global.rsc: services nennt unbekannten Dienst http" && echo "$out" | grep -q "ERR global.rsc: services: Port 443 doppelt" && ok "\$cfmCheck: unbekannter Dienst und doppelter Port" || { bad "\$cfmCheck services"; echo "$out" | tail -3; }
out=$(mgr ':local f [/file/find name="cfm/work/hosts/sw1.rsc"]; /file/set $f contents=":global cfmHost {\"ports\"={\"ether2\"=\"gibtsnicht\"}}"; :global cfmRelease; $cfmRelease msg=" kaputt"')
echo "$out" | grep -q "unbekanntes Port-Profil gibtsnicht" && ok "inhaltliche Prüfung stoppt das Release" || { bad "Prüfung hat nicht gestoppt"; echo "$out" | tail -3; }
mgr '$cfmRelease msg=" kaputt" force=yes' >/dev/null
for _ in $(seq 1 60); do [ "$(stat sw1 bad)" = 3 ] && break; sleep 4; done
if [ "$(stat sw1 bad)" = 3 ]; then ok "v3 als bad gemeldet ($(stat sw1 res | cut -c1-60))"; else bad "Rollback/bad: $(stat sw1 res)"; diag step7; fi
waitssh 2; sleep 20
expect 2 '[:len [/ip/address/find where address="192.168.10.21/24"]] = 1' "sw1 nach Rollback erreichbar konfiguriert"
mgr '$cfmStatus' | grep "^sw1" | grep -q "bad v3" && ok "\$cfmStatus zeigt bad v3 (neuer als IST)" || bad "\$cfmStatus ohne bad v3"
mgr '$cfmRollback ver=2 all=yes' >/dev/null

step "8. Backup-Manager cm2"
echo "put $LAB/bs.rsc cfm-bootstrap.rsc" | put 3
sed -e 's|^:local ip ".*"|:local ip "192.168.10.3/24"|' -e 's/^:local uplink "ether1"/:local uplink "ether2"/' "$LAB/bs.rsc" > "$LAB/bs-cm2.rsc"
echo "put $LAB/bs-cm2.rsc cfm-bootstrap.rsc" | put 3
r 3 '/import cfm-bootstrap.rsc verbose=no' >/dev/null
mgr '$cfmEnroll name=cm2 ip=192.168.10.3 role=manager-backup ring=0' | grep -q Enrolled && ok "Enroll cm2" || bad "Enroll cm2"
agentwait 3 4 cm2 && ok "cm2 hat v4 angewendet" || bad "cm2 Apply"
expect 3 '[:tostr [/interface/wifi/capsman/get enabled]] ~ "no|false"' "cm2: kein CAPsMAN (Backup ohne CAPsMAN, D45)"
expect 3 '[:len [/tool/netwatch/find where comment~"^cfm:nw:primary"]] = 0' "cm2: keine Netwatch-Übernahme mehr (D45)"
expect 3 '[:tostr [/interface/bridge/get bridge protocol-mode]] = "none"' "cm2: Bridge ohne RSTP (stp=none)"
expect 2 '[:tostr [/interface/bridge/get bridge protocol-mode]] = "rstp"' "sw1: Bridge weiter mit RSTP"
expect 1 '[:tostr [/interface/wifi/capsman/get enabled]] ~ "yes|true"' "cm1: CAPsMAN aktiv"
expect 1 '[:len [/interface/wifi/provisioning/find where comment~"^cfm:wprov"]] >= 2' "cm1: Provisioning-Regeln gerendert"

step "9. Rolle router auf sw1 (über den echten Agent-Pfad)"
# gezielt sw1 (der Platzhalter ph1 aus Schritt 3 steht alphabetisch davor und hat auch "switch")
mgr ':global cfmInvLoad; :global cfmInvSave; :local i [$cfmInvLoad]; :set ($i->"sw1"->"role") "switch,router"; $cfmInvSave $i; :global cfmManifests; $cfmManifests' >/dev/null
mgr '$cfmPush host=sw1' >/dev/null
for _ in $(seq 1 60); do [ "$(stat sw1 role)" = "switch,router" ] && [ "$(stat sw1 res)" = ok ] && break; sleep 4; done
[ "$(stat sw1 role)" = "switch,router" ] && [ "$(stat sw1 res)" = ok ] && ok "sw1 als switch,router angewendet" || bad "Router-Apply: $(stat sw1 role) $(stat sw1 res)"
expect 2 '[:len [/ip/firewall/filter/find where comment~"^cfm:fw"]] > 15' "sw1: Zonen-Firewall-Block"
expect 2 '[:len [/interface/vrrp/find where comment~"^cfm:vrrp"]] >= 4' "sw1: VRRP je VLAN"
expect 2 '[:len [/ip/dhcp-server/find where comment~"^cfm:dhcp"]] = 2' "sw1: DHCP für IoT + Gast"
expect 2 '[:len [/ip/firewall/filter/find where comment~"^cfm:fwb"]] = 0' "sw1: minimale Firewall durch Router-Firewall ersetzt"
# NAT je Policy-Ziel (D38): Beispiel-policy mgmt/lan/iot/onboard mit *, Gäste per Hostfile wan@10.0.2.99
# Die Freigabeliste iot-cloud hat zwei Adresslisten (mit und ohne Ports, D76) - je eine NAT-Regel
expect 2 '[:len [/ip/firewall/nat/find where comment~"^cfm:nat" and action="masquerade"]] = 5' "sw1: masquerade nur für gekennzeichnete Ziele (5)"
expect 2 '[:len [/ip/firewall/nat/find where comment~"^cfm:nat" and action="src-nat" and src-address-list="cfm-z-guest"]] = 1 and [:tostr [/ip/firewall/nat/get [find where comment~"^cfm:nat" and action="src-nat"] to-addresses]] = "10.0.2.99"' "sw1: feste NAT-Adresse für Gäste (wan@)"
expect 2 '[:len [/ip/address/find where address="10.0.2.99/32" and interface="ether1" and comment~"^cfm:"]] = 1' "sw1: NAT-Adresse am WAN"
expect 2 '[:len [/ip/firewall/address-list/find where list="cfm-z-guest" and address="192.168.40.0/24"]] = 1' "sw1: Quellnetz-Liste der NAT-Zone"
# Freigabeliste (D39) und DNS-Umleitung für Zonen ohne Internet (iot, onboard: je udp+tcp)
expect 2 '[:len [/ip/firewall/filter/find where comment~"^cfm:fw" and dst-address-list="cfm-allow-iot-cloud"]] = 1 and [:len [/ip/firewall/address-list/find where list="cfm-allow-iot-cloud" and comment~"^cfm:"]] = 2' "sw1: Freigabeliste als Policy-Ziel"
# Eintrag mit Ports (D76): eigene Liste, Regel nur für tcp 443 und 8883
expect 2 '[:len [/ip/firewall/address-list/find where list="cfm-allow-iot-cloud-tcp443_8883" and address=203.0.113.20]] = 1 and [:len [/ip/firewall/filter/find where comment~"^cfm:fw" and dst-address-list="cfm-allow-iot-cloud-tcp443_8883" and protocol="tcp" and dst-port="443,8883"]] = 1' "sw1: Freigabe mit Ports (eigene Liste, tcp 443,8883)"
expect 2 '[:len [/ip/firewall/nat/find where comment~"^cfm:nat" and action="redirect" and dst-port="53"]] = 4' "sw1: DNS-Umleitung für Zonen ohne Internet"
t0=$(stat sw1 t); mgr '$cfmPush host=sw1 force=yes' >/dev/null
for _ in $(seq 1 60); do [ "$(stat sw1 t)" != "$t0" ] && break; sleep 4; done
stat sw1 stats | grep -q "add=0;rem=0;set=0;skip=0" && ok "Router-Rolle idempotent" || bad "Router idempotent: $(stat sw1 stats)"
# Feste Leases und DNS-Namen (D62), $cfmDiff und $cfmShow (D61)
mgr ':global e2eL [/file/get [/file/find name="cfm/work/leases.rsc"] contents]; /file/set [/file/find name="cfm/work/leases.rsc"] contents=($e2eL . ":set (\$cfmLeases->\"30\") {\"drucker\"={\"mac\"=\"02:00:00:00:00:aa\";\"ip\"=20}}\n")' >/dev/null
# dhcpGw (D82): Clients in VLAN 30 bekommen .5 als Gateway, DNS bleibt der Router (.1)
mgr ':local f [/file/find name="cfm/work/vlans.rsc"]; /file/set $f contents=([/file/get $f contents] . ":set (\$cfmVlans->\"30\"->\"dhcpGw\") 5\n")' >/dev/null
out=$(mgr '$cfmDiff')
echo "$out" | grep -q "geändert: leases.rsc" && echo "$out" | grep -q "betroffen: alle Geräte" && echo "$out" | grep -qF '+ :set ($cfmLeases->"30")' && ok "\$cfmDiff: work/ gegen das letzte Release mit der neuen Zeile" || { bad "\$cfmDiff work/"; echo "$out" | tail -8; }
rv=$(mgr '$cfmRelease msg=" Lease" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 2 "$rv" sw1 && ok "sw1 hat v$rv (Lease) angewendet" || bad "sw1 Apply v$rv"
expect 2 '[:len [/ip/dhcp-server/lease/find where comment="cfm:lease:30:drucker" and mac-address="02:00:00:00:00:AA" and address="192.168.30.20" and server="dhcp30"]] = 1' "sw1: feste Lease (MAC in Großbuchstaben, Adresse aus dem Host-Anteil)"
expect 2 '[/ip/dhcp-server/network/get [find where comment="cfm:dn:30"] gateway] = "192.168.30.5" and [/ip/dhcp-server/network/get [find where comment="cfm:dn:30"] dns-server] = "192.168.30.1"' "sw1: dhcpGw - Clients in VLAN 30 mit Gateway .5, DNS weiter der Router (D82)"
expect 2 '[:len [/ip/dns/static/find where name="drucker.internal" and address="192.168.30.20"]] = 1 and [:len [/ip/dns/static/find where name="sw1.internal" and address="192.168.10.21"]] = 1 and [:len [/ip/dns/static/find where name="cm1.internal"]] = 1' "sw1: DNS-Namen für Lease und Geräte (.internal)"
mgr '$cfmDiff' | grep -q "keine Unterschiede" && ok "\$cfmDiff nach dem Release: keine Unterschiede" || bad "\$cfmDiff nach dem Release"
out=$(mgr "\$cfmDiff ver=$((rv-1)) to=$rv")
echo "$out" | grep -q "geändert: leases.rsc" && ok "\$cfmDiff zwischen zwei Releases" || { bad "\$cfmDiff ver/to"; echo "$out" | tail -5; }
t0=$(stat sw1 t); mgr '$cfmPush host=sw1 force=yes' >/dev/null
for _ in $(seq 1 60); do [ "$(stat sw1 t)" != "$t0" ] && break; sleep 4; done
stat sw1 stats | grep -q "add=0;rem=0;set=0;skip=0" && ok "Leases und DNS-Namen idempotent" || bad "Leases idempotent: $(stat sw1 stats)"
out=$(mgr '$cfmShow host=sw1')
echo "$out" | grep -q "^Ports" && echo "$out" | grep -q "ether2 .*trunk" && echo "$out" | grep -q "drucker" && echo "$out" | grep -q "DNS-Namen unter .internal" && echo "$out" | grep -q "DHCP 50-200, Gateway der Clients .5" && ok "\$cfmShow: Ports, VLANs, Leases, DNS-Namen, dhcpGw" || { bad "\$cfmShow"; echo "$out" | tail -12; }
out=$(mgr '$cfmShow host=sw1 objects=yes')
echo "$out" | grep -q "# Soll-Objekte sw1" && echo "$out" | grep -q "^/ip/dhcp-server/lease lease:30:drucker:" && echo "$out" | grep -q "^/interface/bridge br:" && ok "\$cfmShow objects=yes: Soll-Objekte vom Gerät" || { bad "\$cfmShow objects=yes"; echo "$out" | head -5; }
out=$(mgr ':global e2eL2 [/file/get [/file/find name="cfm/work/leases.rsc"] contents]; :global cfmCheck; /file/set [/file/find name="cfm/work/leases.rsc"] contents=($e2eL2 . ":set (\$cfmLeases->\"40\") {\"x1\"={\"mac\"=\"zz\";\"ip\"=5};\"cm1\"={\"mac\"=\"02:00:00:00:00:bb\";\"ip\"=1}}\n"); :foreach e in=([$cfmCheck]->"err") do={ :put $e }')
echo "$out" | grep -q "x1: MAC fehlt oder ungültig" && echo "$out" | grep -q "Name cm1 ist auch ein Gerät" && echo "$out" | grep -q "cm1: ip ist die Adresse des Gateways" && ok "Prüfung: Leases (MAC, Gerätename, Gateway)" || { bad "Prüfung Leases"; echo "$out" | tail -4; }
mgr ':global e2eL2; /file/set [/file/find name="cfm/work/leases.rsc"] contents=$e2eL2' >/dev/null
out=$(mgr ':global e2eV2 [/file/get [/file/find name="cfm/work/vlans.rsc"] contents]; :global cfmCheck; /file/set [/file/find name="cfm/work/vlans.rsc"] contents=($e2eV2 . ":set (\$cfmVlans->\"30\"->\"dhcpGw\") 60\n:set (\$cfmVlans->\"20\"->\"dhcpGw\") 1\n"); :local ck [$cfmCheck]; :foreach e in=($ck->"err") do={ :put ("ERR " . $e) }; :foreach e in=($ck->"warn") do={ :put ("W " . $e) }')
echo "$out" | grep -q "ERR vlans.rsc: VLAN 30: dhcpGw 60 liegt im DHCP-Bereich 50-200" && echo "$out" | grep -q "W vlans.rsc: VLAN 20: dhcpGw 1 wirkt nur mit dhcp" && ok "Prüfung: dhcpGw im Pool bzw. ohne dhcp" || { bad "Prüfung dhcpGw"; echo "$out" | grep -i dhcpgw; }
mgr ':global e2eV2; /file/set [/file/find name="cfm/work/vlans.rsc"] contents=$e2eV2' >/dev/null

step "10. Backup-Spiegel & Vault-Backup"
for _ in $(seq 1 50); do r 3 ':put ([:len [/file/find where name="cfm/meta/rings.dat"]] + [:len [/file/find where name="cfm/archive/v4/index.dat"]])' | grep -qx 2 && break; sleep 8; done
expect 3 '[:len [/file/find where name="cfm/archive/v4/lib/agent.rsc"]] = 1' "cm2: Archiv v4 gespiegelt"
expect 3 '[:len [/file/find where name="cfm/meta/rings.dat"]] = 1' "cm2: Ringe gespiegelt"
expect 1 '[:len [/file/find where name~"^cfm/vault/.*-vault.bak"]] = 1' "cm1: verschlüsseltes Vault-Backup (.bak)"

step "11. Archiv aufräumen"
out=$(mgr ':global cfmArchivePrune; :put ("AP=" . [$cfmArchivePrune keep=1])')
# v1-v5: v3 ist kaputt (Schritt 7), v5 das Lease-Release aus Schritt 9 auf allen Ringen
echo "$out" | grep -q "AP=3" && ok "3 alte Versionen gelöscht" || bad "Archiv: $(echo "$out" | tail -1)"
expect 1 '[:len [/file/find where name~"^cfm/archive/v[124](/|\$)"]] = 0' "v1, v2 und v4 samt Verzeichnis entfernt"
expect 1 '[:len [/file/find where name="cfm/archive/v3/index.dat"]] = 1' "v3 bleibt (sw1 meldet sie als bad)"
mgr '$cfmStatus' | grep "^sw1" | grep -q "bad v" && bad "\$cfmStatus zeigt die alte bad v3 nach neuerem ok" || ok "\$cfmStatus: alte bad v3 nach neuerem ok ausgeblendet"
expect 1 '[:len [/file/find where name="cfm/archive/v5/index.dat"]] = 1' "v5 bleibt (von den Ringen genutzt)"

step "12. Identitätsprüfung vor dem Secret-Push, Geräteschlüssel erneuern"
ser=$(stat sw1 serial)
out=$(mgr ':global cfmVaultGet; :global cfmVaultSet; :global e2eK [$cfmVaultGet "mac.'"$ser"'"]; $cfmVaultSet "mac.'"$ser"'" "falsch"; :put ("SP=" . [$cfmSecretPush host=sw1]); $cfmVaultSet "mac.'"$ser"'" $e2eK')
echo "$out" | grep -q "SP=0" && ok "Secret-Push ohne Identitätsnachweis verweigert" || bad "Secret-Push trotz falschem Schlüssel ($(echo "$out" | tail -1))"
mgr ':put ("SP=" . [$cfmSecretPush host=sw1])' | grep -q "SP=1" && ok "Secret-Push mit Identitätsnachweis" || bad "Secret-Push mit richtigem Schlüssel fehlgeschlagen"
k0=$(mgr ':global cfmVaultGet; :put [$cfmVaultGet "mac.'"$ser"'"]' | tail -1)
out=$(mgr '$cfmRekey host=sw1')
echo "$out" | grep -q "neuer Geräteschlüssel aktiv" && ok "Rekey sw1" || { bad "Rekey sw1"; echo "$out" | tail -3; }
k1=$(mgr ':global cfmVaultGet; :put [$cfmVaultGet "mac.'"$ser"'"]' | tail -1)
[ -n "$k1" ] && [ "$k0" != "$k1" ] && ok "Vault hat den neuen Schlüssel" || bad "Vault-Schlüssel unverändert"
t0=$(stat sw1 t); mgr '$cfmPush host=sw1 force=yes' >/dev/null
for _ in $(seq 1 40); do [ "$(stat sw1 t)" != "$t0" ] && break; sleep 3; done
[ "$(stat sw1 t)" != "$t0" ] && [ "$(stat sw1 res)" = ok ] && ok "sw1 akzeptiert das neu signierte Manifest" || bad "sw1 nach Rekey: $(stat sw1 res)"

step "13. RouterOS-Update per Befehl (Pakete vom Manager; im Labor: Downgrade auf 7.24.1)"
# Labor: cm1 hat zwei gleichwertige Default-Routen, die über das hier fehlende MGMT-Gateway führt
# ins Leere -> Internet für den Paket-Download über ether1 (Handobjekte, cfm fasst sie nicht an)
r 1 '/ip/route/add dst-address=0.0.0.0/1 gateway=10.0.2.2 comment=e2e; /ip/route/add dst-address=128.0.0.0/1 gateway=10.0.2.2 comment=e2e' >/dev/null
# Probe ohne Auftrag (TODO 37): nennt das fehlende Paket samt Ablageort, lädt nichts, überspringt ph1
out=$(mgr '$cfmUpgrade ver=7.24.1 all=yes check=yes')
echo "$out" | grep -q "ph1: nicht aufgenommen - übersprungen" && echo "$out" | grep -q "routeros-7.24.1.npk: fehlt" && echo "$out" | grep -q "nach cfm/pkg/7.24.1/ legen" && echo "$out" | grep -q "kein Auftrag erteilt" && ok "check=yes: fehlendes Paket gemeldet, Platzhalter übersprungen" || { bad "check=yes"; echo "$out" | tail -6; }
# upgrade.dat gibt es vor dem ersten Auftrag noch nicht: $cfmJson liefert dann ein leeres Array
mgr ':global cfmJson; :put ("C=" . [:len [/file/find where name="cfm/pkg/7.24.1/routeros-7.24.1.npk"]] . "/" . [:len [$cfmJson "cfm/meta/upgrade.dat"]])' | grep -q "C=0/0" && ok "check=yes: nichts geladen, kein Auftrag" || bad "check=yes hat geladen oder beauftragt"
echo "$out" | grep "^sw1 " | grep -q "frei [0-9]" && ok "sw1 meldet den freien Platz (fs)" || bad "sw1 ohne Angabe zum freien Platz: $(echo "$out" | grep '^sw1')"
# Vorabversionen (TODO 36): alpha < beta < rc < fertig, Zusätze wie " (stable)" zählen nicht
out=$(mgr ':global cfmVerGe; :local n 0; :foreach c in={{"7.25beta5";"7.24.4";true};{"7.24.4";"7.25beta5";false};{"7.25rc1";"7.25beta5";true};{"7.25";"7.25rc2";true};{"7.25rc2";"7.25";false};{"7.25.1";"7.25";true};{"7.25beta10";"7.25beta9";true};{"7.25alpha1";"7.25beta1";false};{"7.24.5 (stable)";"7.24.5";true};{"7.24";"7.24.0";true};{"7.9";"7.24.5";false};{"7.25beta5";"7.25beta5";true}} do={ :if ([$cfmVerGe ($c->0) ($c->1)] = ($c->2)) do={ :set n ($n + 1) } else={ :put ("FALSCH " . ($c->0) . " >= " . ($c->1)) } }; :put ("VG=" . $n)')
echo "$out" | grep -q "VG=12" && ok "\$cfmVerGe: 12 Fälle mit Vorabversionen" || { bad "\$cfmVerGe"; echo "$out" | grep FALSCH; }
# Beta der nächsten Unterversion des Images (7.24.x -> 7.25beta5, 7.25rc1 -> 7.26beta5)
mi=$(r 2 ':put [/system/resource/get version]' | head -1 | sed -E 's/^7\.([0-9]+).*/\1/')
nb="7.$((mi + 1))beta5"
out=$(mgr "\$cfmUpgrade ver=$nb host=sw1 check=yes")
echo "$out" | grep "^sw1 " | grep -q "upgrade" && ok "check=yes: Beta der nächsten Version ($nb) ist ein Upgrade, kein Downgrade" || { bad "Richtung bei $nb"; echo "$out" | grep "^sw1"; }
# (a) sw1: Wartungsfenster in einer Stunde -> Paket wird sofort geladen, Neustart geplant
now=$(r 1 ':put ([/system/clock/get date] . " " . [/system/clock/get time])' | head -1)
at=$(date -d "@$(( $(date -d "$now" +%s) + 3600 ))" '+%Y-%m-%d %H:%M')
out=$(mgr '$cfmUpgrade ver=7.24.1 host=sw1 at="'"$at"'"')
echo "$out" | grep -q "Auftrag sw1: downgrade auf 7.24.1 (am $at)" && ok "Auftrag sw1 für das Wartungsfenster $at" || { bad "Auftrag sw1"; echo "$out" | tail -3; }
expect 1 '[/file/get [find where name="cfm/pkg/7.24.1/routeros-7.24.1.npk"] size] > 1000000' "cm1: Paket 7.24.1 (x86) vor dem Rollout geladen"
# SFTP zwischen CHRs ist langsam (~100 KB/s): das 20-MB-Paket braucht einige Minuten
for _ in $(seq 1 100); do r 2 ':put [:len [/system/scheduler/find where name="cfm-upgrade"]]' | grep -qx 1 && break; sleep 6; done
expect 2 '[:tostr [/system/scheduler/get [find where name="cfm-upgrade"] start-time]] = "'"${at#* }"':00" and [/file/get [find where name="routeros-7.24.1.npk"] size] > 1000000' "sw1: Paket geladen, Neustart für $at geplant"
mgr '$cfmUpgrade ver=7.24.1 host=sw1 check=yes' | grep -q "alle Pakete liegen in cfm/pkg/7.24.1/" && ok "check=yes: Paket vorhanden" || bad "check=yes nach dem Download"
mgr ':global cfmPkgOk; :put ("NPK=" . [$cfmPkgOk "cfm/pkg/7.24.1/routeros-7.24.1.npk"])' | grep -q "NPK=true" && ok "NPK-Kennung des echten Pakets erkannt" || bad "NPK-Kennung nicht erkannt"
# zu wenig Platz (TODO 38): gemeldeten Wert von cm2 kurz auf 5 MB setzen -> kein Auftrag, Status zurück
out=$(mgr ':global cfmJson; :global cfmWrite; :global cfmRead; :local f "cfm/state/cm2/status.dat"; :local raw [$cfmRead $f]; :local s [$cfmJson $f]; :set ($s->"fs") 5000000; $cfmWrite $f [:serialize to=json $s]; :onerror e in={ $cfmUpgrade ver=7.24.1 host=cm2 check=yes; $cfmUpgrade ver=7.24.1 host=cm2 } do={ :put ("ERR " . $e) }; $cfmWrite $f $raw')
echo "$out" | grep "^cm2 " | grep -q "zu wenig Platz" && echo "$out" | grep -q "cm2: zu wenig Platz für die Pakete" && echo "$out" | grep -q "kein Gerät mit genug Platz" && ok "Manager: kein Auftrag bei zu wenig Platz" || { bad "Platzprüfung am Manager"; echo "$out" | tail -4; }
mgr ':global cfmJson; :put ("N=" . [:len [$cfmJson "cfm/meta/upgrade.dat"]])' | grep -q "N=1" && ok "nur der Auftrag für sw1 offen" || bad "Aufträge nach der Platzprüfung: $(mgr ':global cfmJson; :put [:tostr [$cfmJson "cfm/meta/upgrade.dat"]]' | tail -1 | cut -c1-80)"
# (b) cm2: sofort -> Download, Neustart, Downgrade, Rückmeldung
out=$(mgr '$cfmUpgrade ver=7.24.1 host=cm2')
echo "$out" | grep -q "Auftrag cm2: downgrade auf 7.24.1 (sofort)" && ok "Auftrag cm2 (sofort)" || { bad "Auftrag cm2"; echo "$out" | tail -3; }
for _ in $(seq 1 100); do [ "$(stat cm2 ros | cut -d' ' -f1)" = 7.24.1 ] && break; sleep 6; done
[ "$(stat cm2 ros | cut -d' ' -f1)" = 7.24.1 ] && ok "cm2 läuft mit 7.24.1 (Downgrade sofort)" || bad "cm2: $(stat cm2 ros) $(stat cm2 upg)"
# (c) sw1: Auftrag zurückziehen -> geplanter Neustart und Paket verschwinden
mgr '$cfmUpgrade cancel=yes host=sw1' >/dev/null
for _ in $(seq 1 30); do r 2 ':put [:len [/system/scheduler/find where name="cfm-upgrade"]]' | grep -qx 0 && break; sleep 3; done
expect 2 '[:len [/system/scheduler/find where name="cfm-upgrade"]] = 0 and [:len [/file/find where name="routeros-7.24.1.npk"]] = 0' "sw1: zurückgezogener Auftrag - Neustart und Paket entfernt"
for _ in $(seq 1 30); do mgr ':global cfmJson; :put ("N=" . [:len [$cfmJson "cfm/meta/upgrade.dat"]])' | grep -q "N=0" && break; sleep 4; done
mgr ':global cfmJson; :put ("N=" . [:len [$cfmJson "cfm/meta/upgrade.dat"]])' | grep -q "N=0" && ok "erledigte Aufträge ausgetragen" || bad "Aufträge noch offen"
# (d) der Agent prüft den Platz selbst (TODO 38): Auftrag mit übergroßer Paketangabe direkt in upgrade.dat
mgr ':global cfmJson; :global cfmWrite; :global cfmManifests; :global cfmNow; :local o [$cfmJson "cfm/meta/upgrade.dat"]; :set ($o->"sw1") ({"rv"="v7.24.1";"at"="";"id"=("i" . [$cfmNow]);"how"="downgrade";"path"="cfm/pkg/7.24.1";"files"={{"routeros-7.24.1.npk";900000000}}}); $cfmWrite "cfm/meta/upgrade.dat" [:serialize to=json $o]; $cfmManifests; $cfmPush host=sw1' >/dev/null
for _ in $(seq 1 30); do stat sw1 upg | grep -q "^Platz fehlt" && break; sleep 4; done
stat sw1 upg | grep -q "^Platz fehlt" && ok "sw1: Agent lädt nichts bei zu wenig Platz ($(stat sw1 upg))" || bad "sw1 Platzprüfung: '$(stat sw1 upg)'"
expect 2 '[:len [/file/find where name="routeros-7.24.1.npk"]] = 0 and [:len [/system/scheduler/find where name="cfm-upgrade"]] = 0' "sw1: kein Paket geladen, kein Neustart geplant"
mgr '$cfmUpgrade cancel=yes host=sw1' >/dev/null
for _ in $(seq 1 30); do [ -z "$(stat sw1 upg)" ] && break; sleep 3; done
[ -z "$(stat sw1 upg)" ] && ok "sw1: Auftrag zurückgezogen, Meldung weg" || bad "sw1 nach dem Zurückziehen: $(stat sw1 upg)"
r 1 '/file/add name="cfm/pkg/7.0.0/routeros-7.0.0.npk" contents="x"' >/dev/null
# keine NPK-Kennung: die Probe meldet das, ohne die Datei anzufassen (TODO 37)
mgr ':global cfmPkgFetch; :put ("E=" . ([$cfmPkgFetch ver=7.0.0 arch=x86_64 pkg=routeros dl=no]->"err"))' | grep -q "E=kein RouterOS-Paket" && ok "Datei ohne NPK-Kennung erkannt" || bad "NPK-Prüfung der Fälschung"
expect 1 '[:len [/file/find where name="cfm/pkg/7.0.0/routeros-7.0.0.npk"]] = 1' "Probe lässt die Datei liegen"
mgr '$cfmPkgPrune' >/dev/null
expect 1 '[:len [/file/find where name~"^cfm/pkg/7.0.0"]] = 0 and [:len [/file/find where name="cfm/pkg/7.24.1/routeros-7.24.1.npk"]] = 1' "Paketversion ohne Einsatz gelöscht, 7.24.1 bleibt"

# (e) eingebautes Update über einen Spiegel (TODO 38, D63): cm2 von 7.24.1 zurück auf die Version
#     des Images; tools/upgrade-mirror.py lauscht auf LABPORT+90, die VMs erreichen ihn als 10.0.2.100
tv=$(r 1 ':put [/system/resource/get version]' | head -1 | cut -d' ' -f1)
mkdir -p "$LAB/mirror"
python3 "$ROOT/tools/upgrade-mirror.py" "$tv" --port $((LABPORT + 90)) --bind 127.0.0.1 --dir "$LAB/mirror" > "$LAB/mirror.log" 2>&1 &
mpid=$!
sleep 3
out=$(mgr "\$cfmUpgrade ver=$tv host=cm2 via=mirror mirror=10.0.2.100 check=yes")
echo "$out" | grep "^cm2 " | grep -q "über Spiegel 10.0.2.100" && echo "$out" | grep -q "kein Auftrag erteilt" && ok "check=yes mit via=mirror" || { bad "check=yes via=mirror"; echo "$out" | tail -3; }
mgr '$cfmUpgrade ver=7.24.1 host=sw1 via=internet check=yes' | grep "^sw1 " | grep -q "nur Upgrades" && ok "via=internet: Downgrade abgelehnt" || bad "via=internet mit Downgrade"
out=$(mgr ':onerror e in={ $cfmUpgrade ver=7.24.9 host=cm2 via=mirror } do={ :put ("ERR " . $e) }')
echo "$out" | grep -q "ERR via=mirror braucht mirror=" && ok "via=mirror ohne Adresse abgelehnt" || { bad "via=mirror ohne Adresse"; echo "$out" | tail -3; }
out=$(mgr "\$cfmUpgrade ver=$tv host=cm2 via=mirror mirror=10.0.2.100")
echo "$out" | grep -q "Auftrag cm2: upgrade auf $tv über Spiegel 10.0.2.100 (sofort)" && ok "Auftrag cm2 über den Spiegel" || { bad "Auftrag cm2 via=mirror"; echo "$out" | tail -3; }
for _ in $(seq 1 100); do [ "$(stat cm2 ros | cut -d' ' -f1)" = "$tv" ] && break; sleep 6; done
[ "$(stat cm2 ros | cut -d' ' -f1)" = "$tv" ] && ok "cm2 läuft mit $tv (eingebautes Update vom Spiegel)" || { bad "cm2 via=mirror: $(stat cm2 ros) $(stat cm2 upg)"; tail -5 "$LAB/mirror.log"; }
grep -q "GET /routeros/$tv/routeros-$tv.npk" "$LAB/mirror.log" && ok "Paket kam vom Spiegel" || bad "kein Paketabruf am Spiegel"
for _ in $(seq 1 40); do r 3 ':put ("M=" . [:len [/ip/dns/static/find where comment="cfm-sys:upgrade-mirror"]] . [/system/package/update/get mode])' | grep -q "M=0https" && break; sleep 5; done
if r 3 ':put ([:len [/ip/dns/static/find where comment="cfm-sys:upgrade-mirror"]] = 0 and [/system/package/update/get mode] = "https")' | grep -q true; then ok "cm2: Spiegel-Eintrag entfernt, Update wieder über https"; else
  bad "cm2: Spiegel-Eintrag oder mode=http geblieben"; r 3 ':put ("DNS=" . [:len [/ip/dns/static/find where comment="cfm-sys:upgrade-mirror"]] . " mode=" . [/system/package/update/get mode] . " state=" . [/file/get cfm/state.json contents])' | tail -1; fi
kill $mpid 2>/dev/null

mgr ':global cfmInvLoad; :global cfmInvSave; :local i [$cfmInvLoad]; :set ($i->"ph1"); $cfmInvSave $i' >/dev/null

step "14. Verkabelung (LLDP, Netzplan) und WLAN (PPSK, Kanäle)"
# alle Geräte melden ihre Nachbarn mit dem nächsten Lauf
for h in sw1 cm2 cm1; do mgr "\$cfmPush host=$h force=yes" >/dev/null; done
for _ in $(seq 1 40); do [ -n "$(stat sw1 nb)" ] && [ -n "$(stat cm2 nb)" ] && [ -n "$(stat cm1 nb)" ] && break; sleep 5; done
out=$(mgr '$cfmLinks')
echo "$out" | grep -qE "^(cm1 +ether2 +sw1 +ether2|sw1 +ether2 +cm1 +ether2) +ok" && ok "Link cm1:ether2 - sw1:ether2 (beide Seiten melden)" || { bad "Link cm1-sw1 fehlt"; echo "$out" | tail -8; }
echo "$out" | grep -qE "^(cm1 +ether3 +cm2 +ether2|cm2 +ether2 +cm1 +ether3) +ok" && ok "Link cm1:ether3 - cm2:ether2 (beide Seiten melden)" || bad "Link cm1-cm2 fehlt"
# MNDP über einen Bridge-Port ohne Adresse hat die Quelle 0.0.0.0. Hinter einem Access-Port (PVE vor den
# Karten einer VM, D40) landet es im VLAN: nachgestellt mit pvid=10 an cm1:ether3. cm1 verwirft es still (D78)
expect 3 '[:typeof [:find [/ip/neighbor/discovery-settings/get protocol] "mndp"]] = "num"' "cm2 (stp=none): Nachbarsuche mit MNDP"
n0=$(r 1 ':put [:len [/log/find where message~"0.0.0.0:5678"]]' | tail -1 | tr -dc 0-9)
r 1 '/interface/bridge/port/set [find interface=ether3] pvid=10 frame-types=admit-all' >/dev/null
sleep 40
r 1 '/interface/bridge/port/set [find interface=ether3] pvid=1 frame-types=admit-only-vlan-tagged' >/dev/null
n1=$(r 1 ':put [:len [/log/find where message~"0.0.0.0:5678"]]' | tail -1 | tr -dc 0-9)
expect 1 '[/ip/firewall/filter/get [find comment~"cfm:fwb" and src-address="0.0.0.0" and dst-port="5678"] packets] > 0' "cm1: MNDP mit Quelle 0.0.0.0 still verworfen (D78)"
[ -n "$n0" ] && [ -n "$n1" ] && [ "$n1" -le "$n0" ] && ok "cm1: kein cfm-drop für MNDP mit Quelle 0.0.0.0" || bad "cm1: cfm-drop für 0.0.0.0:5678 im Log ($n0 -> $n1)"
expect 1 '[/file/get [find where name="cfm/state/netzplan.md"] contents] ~ "graph LR"' "netzplan.md mit Mermaid-Diagramm"
mgr '$cfmLinks accept=yes' | grep -q "Baseline gespeichert: 2 Links" && ok "Baseline mit 2 Links eingefroren" || bad "Baseline"
mgr ':global e2eH [/file/get [/file/find name="cfm/work/hosts/sw1.rsc"] contents]; /file/set [/file/find name="cfm/work/hosts/sw1.rsc"] contents=($e2eH . ":set (\$cfmHost->\"links\") {\"ether2\"=\"cm1:ether3\"}\n")' >/dev/null
out=$(mgr '$cfmLinks export=yes')
echo "$out" | grep -q "sw1 ether2: erwartet cm1:ether3, gefunden cm1:ether2" && ok "Hostfile-Angabe links wird geprüft" || { bad "Erwartung nicht geprüft"; echo "$out" | tail -4; }
expect 1 '[:len [/file/find where name="cfm/state/netzplan.dot"]] = 1 and [/file/get [find where name="cfm/state/netzplan.csv"] contents] ~ "geraet_a;port_a"' "Export: netzplan.dot und netzplan.csv"
mgr ':global e2eH; /file/set [/file/find name="cfm/work/hosts/sw1.rsc"] contents=$e2eH' >/dev/null
# Gerätesuche (TODO 53): live über die drei VMs; im Labor gibt es nur die Geräte selbst – ihren Ort liefert LLDP
mgr '$cfmFind' | grep -q "Aufruf: \$cfmFind" && ok "\$cfmFind ohne Angaben: Aufruf" || bad "\$cfmFind ohne Angaben"
swm=$(stat sw1 mac)
out=$(mgr '$cfmFind sw1')
echo "$out" | grep -qE "^$swm +192\.168\.10\.21\+? +sw1 +cm1 ether2 +10 +cfm-Gerät" && echo "$out" | grep -q "Geräte abgefragt" && ok "\$cfmFind sw1: eigenes Gerät dort, wo LLDP es sieht (cm1:ether2)" || { bad "\$cfmFind sw1"; echo "$out" | tail -4; }
swl=$(echo "$swm" | tr 'A-F' 'a-f' | tr -d ':')
mgr ':global e2eL [/file/get [/file/find name="cfm/work/leases.rsc"] contents]; /file/set [/file/find name="cfm/work/leases.rsc"] contents=($e2eL . ":set (\$cfmLeases->\"10\") {\"e2e-gast\"={\"mac\"=\"'"$(echo "$swm" | tr 'A-F' 'a-f')"'\";\"ip\"=99}}\n")' >/dev/null
mgr '$cfmFind E2E-GAST' | grep -q "^$swm " && mgr ':put [:serialize to=json [$cfmFind E2E-GAST quiet=yes]]' | grep -q '"192.168.10.99"' && ok "\$cfmFind: Name und feste IP aus leases.rsc, groß/klein egal" || bad "\$cfmFind: Name/IP aus leases.rsc"
mgr ':global e2eL; /file/set [/file/find name="cfm/work/leases.rsc"] contents=$e2eL' >/dev/null
mgr "\$cfmFind $swl" | grep -q "^$swm " && ok "\$cfmFind: MAC ohne Trenner in Kleinbuchstaben" || bad "\$cfmFind: MAC ohne Trenner"
# Auswertung mit erfundenen Antworten (data=): Endpunkt = Port mit den wenigsten MACs, WLAN vom CAPsMAN
mgr ':global cfmWrite; $cfmWrite "cfm/state/find-e2e.json" ("{\"swY\":{\"f\":[[\"02:00:00:00:0C:01\",\"ether7\",\"30\"],[\"02:00:00:00:0C:01\",\"ether9\",\"30\"],[\"02:00:00:00:0C:02\",\"ether9\",\"30\"],[\"02:00:00:00:0C:03\",\"ether9\",\"30\"],[\"02:00:00:00:0A:01\",\"ether1\",\"30\"]],\"n\":{\"ether9\":\",fremd-sw\",\"ether1\":\",apX\"},\"b\":[],\"a\":[[\"192.168.30.50\",\"02:00:00:00:0C:01\",\"vlan30\"]],\"l\":[[\"192.168.30.51\",\"02:00:00:00:0A:01\",\"handy-e2e\",\"bound\",\"\"]],\"w\":[]},\"apX\":{\"f\":[[\"02:00:00:00:0A:01\",\"wifi1\",\"30\"]],\"n\":{\"ether1\":\",swY\"},\"b\":[],\"a\":[],\"l\":[],\"w\":[[\"02:00:00:00:0A:01\",\"apX-5g\",\"E2E-SSID\",\"-80\",\"5ghz-ax\",\"00:12:00\",\"30\",\"433000000\"]]}}")' | grep -i "error"
mgr '$cfmFind 192.168.30.50 data=state/find-e2e.json' | grep -qE "^02:00:00:00:0C:01 +192\.168\.30\.50 +swY ether7 +30" && ok "\$cfmFind: Endpunkt ist der Port mit den wenigsten MACs" || { bad "\$cfmFind: Endpunkt"; mgr '$cfmFind 192.168.30.50 data=state/find-e2e.json' | tail -3; }
mgr '$cfmFind handy data=state/find-e2e.json' | grep -qE "^02:00:00:00:0A:01 +192\.168\.30\.51 +handy-e2e +apX 5g +30 +E2E-SSID -80 dBm 433 Mbit/s" && ok "\$cfmFind: WLAN-Client mit AP, Band, SSID und Signal" || { bad "\$cfmFind: WLAN-Client"; mgr '$cfmFind handy data=state/find-e2e.json' | tail -3; }
out=$(mgr '$cfmFind signal=-75 data=state/find-e2e.json')
echo "$out" | grep -q "^1 Treffer" && echo "$out" | grep -q "^02:00:00:00:0A:01 " && ok "\$cfmFind signal=-75: nur der schwache WLAN-Client" || { bad "\$cfmFind signal="; echo "$out" | tail -3; }
out=$(mgr '$cfmFind host=swY port=ether9 data=state/find-e2e.json')
echo "$out" | grep -q "^2 Treffer" && ! echo "$out" | grep -q "^02:00:00:00:0C:01 " && echo "$out" | grep -q "Nachbar fremd-sw, 3 MACs am Port" && ok "\$cfmFind host= port=: was an einem Port hängt" || { bad "\$cfmFind host= port="; echo "$out" | tail -4; }
r 1 '/file/remove [find where name="cfm/state/find-e2e.json"]' >/dev/null
mgr '$cfmChannels' | grep -q "keine Funkdaten" && ok "Kanalbericht (Labor ohne Radios)" || bad "Kanalbericht"
# Kanal-Scan (D56/D60): ohne APs kein Vorschlag und keine Messdatei; Auswertung mit erfundenen Daten
out=$(mgr '$cfmWifiScan')
echo "$out" | grep -q "keine Netze gemessen" && ! echo "$out" | grep -q "^Vorschlag" && ok "WLAN-Scan ohne Messdaten: kein Vorschlag" || { bad "WLAN-Scan ohne Messdaten"; echo "$out" | tail -3; }
expect 1 '[:len [/file/find where name="cfm/state/wifiscan.json"]] = 0' "WLAN-Scan ohne Netze schreibt keine Messdatei"
# JSON als Funktionsargument nur in runden Klammern (sonst Syntaxfehler, siehe lib.rsc)
mgr ':global cfmWrite; $cfmWrite "cfm/state/wifiscan.json" ("{\"band\":\"2\",\"t\":\"e2e\",\"own\":{},\"aps\":{\"apA\":[[\"m00:00:00:00:00:01\",\"X\",2412,-40]],\"apB\":[[\"m00:00:00:00:00:02\",\"Y\",2462,-45]]}}")' | grep -i "error" 
out=$(mgr '$cfmWifiScan data=yes')
l=$(echo "$out" | grep "^Vorschlag 1/6/11")
echo "$l" | grep -q "Kosten 0" && ! echo "$l" | grep -q "apA=2412" && ! echo "$l" | grep -q "apB=2462" && ok "WLAN-Scan data=yes: Vorschlag meidet die belegten Kanäle" || { bad "WLAN-Scan data=yes"; echo "$out" | tail -6; }
echo "$out" | grep -q "^Vorschlag 1/5/9 " && ok "WLAN-Scan: Kanalsatz 1/5/9 (TODO 51)" || bad "Kanalsatz 1/5/9 fehlt"
# Andere Funknetze (TODO 51, D80): Zigbee 18 (2440 MHz) bei apA verdrängt apA von Kanal 6, Thread
# "auto" bei apB bekommt Kanal 16 (2430 MHz: weit weg von apA auf 11 und apB auf 1, nicht neben 18)
mgr ':global e2eW [/file/get [/file/find name="cfm/work/wifi.rsc"] contents]; /file/set [/file/find name="cfm/work/wifi.rsc"] contents=($e2eW . ":set (\$cfmWifi->\"others\") {\"zb\"={\"type\"=\"zigbee\";\"ch\"=18;\"near\"=\"apA\"};\"ot\"={\"type\"=\"thread\";\"ch\"=\"auto\";\"near\"=\"apB\"};\"ml\"={\"type\"=\"milight-rgbw\"}}\n")' >/dev/null
out=$(mgr '$cfmWifiScan data=yes')
l=$(echo "$out" | grep "^Vorschlag 1/6/11")
echo "$out" | grep -q "anderes Netz zb: zigbee Kanal 18, 2440 MHz, bei apA" && echo "$out" | grep -q "anderes Netz ml: milight-rgbw, 2411,2442,2473 MHz" && ok "WLAN-Scan nennt die anderen Funknetze" || { bad "andere Funknetze fehlen in der Ausgabe"; echo "$out" | grep -i netz; }
echo "$l" | grep -q "apA=2462" && echo "$l" | grep -q "apB=2412" && ok "WLAN-Scan: Zigbee bei apA verschiebt dessen Kanal" || { bad "Zigbee nicht eingerechnet"; echo "$out" | tail -12; }
echo "$out" | grep -A3 "^Vorschlag 1/6/11" | grep -q "ot (thread): Kanal 16 (2430 MHz)" && ok "WLAN-Scan: Kanalvorschlag für Thread mit auto" || { bad "Kanalvorschlag Thread"; echo "$out" | tail -12; }
out=$(mgr ':global cfmCheck; /file/set [/file/find name="cfm/work/wifi.rsc"] contents=([/file/get [/file/find name="cfm/work/wifi.rsc"] contents] . ":set (\$cfmWifi->\"radios\") {\"cm1\"={\"2\"=\"2437\"}}\n:set (\$cfmWifi->\"others\"->\"zb\"->\"near\") \"cm1\"\n:set (\$cfmWifi->\"others\"->\"x\") {\"type\"=\"wlan\"}\n:set (\$cfmWifi->\"others\"->\"y\") {\"type\"=\"thread\";\"ch\"=27}\n"); :local ck [$cfmCheck]; :foreach e in=($ck->"err") do={ :put ("ERR " . $e) }; :foreach e in=($ck->"warn") do={ :put ("W " . $e) }')
echo "$out" | grep -q "W wifi.rsc: radios cm1 2=2437 überdeckt zb (zigbee Kanal 18, 2440 MHz)" && ok "\$cfmCheck: Pin überdeckt Zigbee-Kanal" || { bad "Warnung Pin/Zigbee fehlt"; echo "$out" | grep -i others; }
echo "$out" | grep -q "ERR wifi.rsc: others x: type wlan unbekannt" && echo "$out" | grep -q "ERR wifi.rsc: others y: ch 27 liegt nicht in 11-26" && ok "\$cfmCheck: others mit falschem Typ und Kanal" || { bad "Prüfung others"; echo "$out" | grep -i others; }
mgr ':global e2eW; /file/set [/file/find name="cfm/work/wifi.rsc"] contents=$e2eW' >/dev/null
mgr ':global cfmWrite; $cfmWrite "cfm/state/wifiscan.json" ("{\"band\":\"2\",\"t\":\"e2e\",\"own\":{},\"aps\":{\"apA\":[],\"apB\":[]}}")' | grep -i "error" 
mgr '$cfmWifiScan data=yes' | grep -q "keine Messung mit Netzen" && ok "WLAN-Scan data=yes ohne Netze: kein Vorschlag" || bad "WLAN-Scan data=yes ohne Netze"
r 1 '/file/remove [find where name="cfm/state/wifiscan.json"]' >/dev/null
expect 1 '[:tostr [/interface/wifi/channel/get [find name="cfm-5g"] reselect-time]] = "03:00:00" and [/interface/wifi/channel/get [find name="cfm-5g"] skip-dfs-channels] = "10min-cac"' "cm1: Kanalprofil 5 GHz mit nächtlicher Neuwahl, ohne DFS-Wartezeit"
# PPSK: zweite Passphrase auf der IoT-SSID landet in VLAN 40
mgr ':global e2eW [/file/get [/file/find name="cfm/work/wifi.rsc"] contents]; /file/set [/file/find name="cfm/work/wifi.rsc"] contents=($e2eW . ":set (\$cfmWifi->\"ppsk\") {\"iot\"={\"gast\"={\"vlan\"=40;\"isolation\"=\"yes\"}}}\n")' >/dev/null
rv=$(mgr '$cfmRelease msg=" PPSK" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 1 "$rv" cm1 && ok "cm1 hat v$rv (PPSK) angewendet" || { bad "cm1 Apply v$rv"; r 1 '/log/print where message~"^cfm: "' | tail -6; }
expect 1 '[:len [/interface/wifi/security/multi-passphrase/find where comment="cfm:mpp:iot.gast" and vlan-id=40]] = 1 and [/interface/wifi/security/get [find name="cfm-iot"] multi-passphrase-group] = "cfm-iot"' "cm1: Multi-Passphrase für VLAN 40 an der IoT-SSID"
mgr '$cfmSecret key=ppsk.iot.gast value="PPSK-Gast-2026"; :global cfmSecretPush; $cfmSecretPush host=cm1' >/dev/null
expect 1 '[/interface/wifi/security/multi-passphrase/get [find comment="cfm:mpp:iot.gast"] passphrase] = "PPSK-Gast-2026"' "PPSK-Passphrase per Secret-Push gesetzt"
# 6 GHz: Security je Band (nur WPA3, PMF required) für Master und Slave-SSID, MLO aus (TODO 32)
mgr '/file/set [/file/find name="cfm/work/wifi.rsc"] contents=([/file/get [/file/find name="cfm/work/wifi.rsc"] contents] . ":set (\$cfmWifi->\"channels\"->\"6\") {\"band\"=\"6ghz-ax\";\"freq\"=\"5955,5975\";\"width\"=\"20/40/80mhz\";\"sec\"=\"wpa3-psk\";\"pmf\"=\"required\"}\n:set (\$cfmWifi->\"ssids\"->\"guest\"->\"bands\") \"2,5,6\"\n")' >/dev/null
rv=$(mgr '$cfmRelease msg=" 6 GHz" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 1 "$rv" cm1 && ok "cm1 hat v$rv (6 GHz) angewendet" || { bad "cm1 Apply v$rv"; r 1 '/log/print where message~"^cfm: "' | tail -6; }
expect 1 '[:tostr [/interface/wifi/security/get [find name="cfm-main-6g"] authentication-types]] = "wpa3-psk" and [/interface/wifi/security/get [find name="cfm-main-6g"] management-protection] = "required" and [:tostr [/interface/wifi/security/get [find name="cfm-main"] authentication-types]] ~ "wpa2-psk"' "cm1: eigenes Security-Profil für 6 GHz (WPA3, PMF required), 2,4/5 GHz unverändert"
expect 1 '[/interface/wifi/configuration/get [find name="cfm-m6"] security] = "cfm-main-6g" and [/interface/wifi/configuration/get [find name="cfm-guest-6g"] security] = "cfm-guest-6g" and [:tostr [/interface/wifi/provisioning/get [find where supported-bands=6ghz-ax] slave-configurations]] ~ "cfm-guest-6g"' "cm1: Master- und Slave-Konfiguration auf 6 GHz mit dem Band-Profil"
expect 1 '[:len [/interface/wifi/provisioning/find where comment~"^cfm:wprov" and multi-link-mode=disabled]] = [:len [/interface/wifi/provisioning/find where comment~"^cfm:wprov"]]' "cm1: MLO in allen Provisioning-Regeln aus"
mgr ':global cfmSecretPush; $cfmSecretPush host=cm1' >/dev/null
expect 1 '[/interface/wifi/security/get [find name="cfm-main-6g"] passphrase] = [/interface/wifi/security/get [find name="cfm-main"] passphrase] and [:len [/interface/wifi/security/get [find name="cfm-main"] passphrase]] > 0' "cm1: Secret-Push setzt die Passphrase auch im 6-GHz-Profil"
# stpPrio in Großbuchstaben: RouterOS meldet "0xa000" - kein erneutes Setzen bei jedem Apply (TODO 27)
mgr ':global e2eP [/file/get [/file/find name="cfm/work/hosts/sw1.rsc"] contents]; /file/set [/file/find name="cfm/work/hosts/sw1.rsc"] contents=($e2eP . ":set (\$cfmHost->\"stpPrio\") \"0xA000\"\n")' >/dev/null
rv=$(mgr '$cfmRelease msg=" stpPrio" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 2 "$rv" sw1 && ok "sw1 hat v$rv (stpPrio 0xA000) angewendet" || bad "sw1 Apply v$rv"
expect 2 '[/interface/bridge/get [find comment~"^cfm:br( |\$)"] priority] = "0xa000"' "sw1: Bridge-Priorität 0xa000"
out=$(mgr '$cfmPlan host=sw1')
echo "$out" | grep -q "priority" && { bad "stpPrio 0xA000 erscheint im Probelauf als Änderung"; echo "$out" | grep priority; } || ok "stpPrio in Großbuchstaben ohne Scheinänderung"
mgr ':global e2eP; /file/set [/file/find name="cfm/work/hosts/sw1.rsc"] contents=$e2eP' >/dev/null
out=$(mgr ':global cfmCheck; /file/set [/file/find name="cfm/work/wifi.rsc"] contents=([/file/get [/file/find name="cfm/work/wifi.rsc"] contents] . ":set (\$cfmWifi->\"ppsk\"->\"main\") {\"x\"={\"vlan\"=20}}\n:set (\$cfmWifi->\"ssids\"->\"cap\") {\"ssid\"=\"x\";\"vlan\"=20}\n:set (\$cfmWifi->\"channels\"->\"6\") {\"band\"=\"6ghz-ax\";\"freq\"=\"5955\";\"width\"=\"20mhz\"}\n"); :foreach e in=([$cfmCheck]->"err") do={ :put $e }')
echo "$out" | grep -q "PPSK auf SSID main braucht sec=wpa2-psk" && ok "Prüfung: PPSK nur mit WPA2-PSK" || { bad "PPSK/WPA3 nicht erkannt"; echo "$out" | tail -3; }
echo "$out" | grep -q "cap ist reserviert" && ok "Prüfung: SSID-Schlüssel cap reserviert (D41)" || { bad "SSID-Schlüssel cap nicht erkannt"; echo "$out" | tail -3; }
echo "$out" | grep -q "(6 GHz) braucht" && ok "Prüfung: 6 GHz nur mit WPA3 und PMF required" || { bad "6 GHz mit WPA2 nicht erkannt"; echo "$out" | tail -3; }
mgr ':global e2eW; /file/set [/file/find name="cfm/work/wifi.rsc"] contents=$e2eW' >/dev/null
# Schaltbare SSIDs (D64): guest und event mit switch=off -> nicht in den Regeln; die Skripte schalten
# (5 GHz bleibt dabei ganz ohne weitere SSID: leere Liste), der Apply behält den Zustand, Auto-Aus
cnt=':local n 0; :foreach i in=[/interface/wifi/provisioning/find where comment~"^cfm:wprov"] do={ :if ([:tostr [/interface/wifi/provisioning/get $i slave-configurations]] ~ "cfm-guest") do={ :set n ($n + 1) } }; :put ("G=" . $n)'
mgr ':global e2eW; /file/set [/file/find name="cfm/work/wifi.rsc"] contents=($e2eW . ":set (\$cfmWifi->\"ssids\"->\"guest\"->\"switch\") \"off\"\n:set (\$cfmWifi->\"ssids\"->\"guest\"->\"autoOff\") \"50h\"\n:set (\$cfmWifi->\"ssids\"->\"event\"->\"switch\") \"off\"\n")' >/dev/null
rv=$(mgr '$cfmRelease msg=" SSID schaltbar" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 1 "$rv" cm1 && ok "cm1 hat v$rv (Gast schaltbar) angewendet" || { bad "cm1 Apply v$rv"; r 1 '/log/print where message~"^cfm: "' | tail -6; }
r 1 "$cnt" | grep -q "G=0" && ok "Gast-SSID im Grundzustand aus: in keiner Provisioning-Regel" || bad "Gast-SSID trotz switch=off in den Regeln: $(r 1 "$cnt" | tail -1)"
expect 1 '[/system/script/get [find name="cfm-ssid-guest-on"] dont-require-permissions] = true and [:len [/system/script/find where name~"^cfm-ssid-(guest|event)-(on|off)\$"]] = 4 and [:len [/system/scheduler/find where name="cfm-ssid-check" and interval=10m]] = 1' "cm1: Schalt-Skripte (dont-require-permissions) und Prüfung alle 10 min"
expect 1 '[:typeof [:find [:tostr [/system/script/get [find name="cfm-ssid-guest-on"] source]] "cfm-guest"]] = "num"' "Schalt-Skript kennt die Konfiguration der Gast-SSID"
r 1 ':global cfmSsidguest; :put ("S=" . $cfmSsidguest)' | grep -q "S=off" && ok "Zustand für Home Assistant: cfmSsidguest=off" || bad "cfmSsidguest: $(r 1 ':global cfmSsidguest; :put $cfmSsidguest' | tail -1)"
r 1 '/system/script/run cfm-ssid-guest-on' >/dev/null
r 1 "$cnt" | grep -q "G=0" && bad "Einschalten wirkt nicht" || ok "cfm-ssid-guest-on: Gast-SSID in den Regeln ($(r 1 "$cnt" | tail -1))"
expect 1 '[:pick [/file/get cfm/ssid-guest.txt contents] 0 3] = "on " and [:tonum [:pick [/file/get cfm/ssid-guest.txt contents] 3 99]] > ([:tonsec [:timestamp]] / 1000000000 + 170000)' "Zustand on mit Ablauf in 50 h"
t0=$(stat cm1 t); mgr '$cfmPush host=cm1 force=yes' >/dev/null
for _ in $(seq 1 60); do [ "$(stat cm1 t)" != "$t0" ] && break; sleep 4; done
r 1 "$cnt" | grep -q "G=0" && bad "Apply hat die eingeschaltete Gast-SSID wieder entfernt" || ok "Apply behält den Zustand on"
expect 1 '[:find [:tostr [/interface/wifi/provisioning/get [find where comment~"^cfm:wprov" and supported-bands=2ghz-ax] slave-configurations]] "cfm-iot"] < [:find [:tostr [/interface/wifi/provisioning/get [find where comment~"^cfm:wprov" and supported-bands=2ghz-ax] slave-configurations]] "cfm-guest"]' "Apply: schaltbare Gast-SSID hinter der festen IoT-SSID (wie das Skript)"
r 1 '/system/script/run cfm-ssid-guest-off' >/dev/null
r 1 "$cnt" | grep -q "G=0" && ok "cfm-ssid-guest-off: Gast-SSID aus den Regeln" || bad "Ausschalten wirkt nicht"
r 1 ':local n 0; :foreach i in=[/interface/wifi/provisioning/find where comment~"^cfm:wprov"] do={ :if ([:tostr [/interface/wifi/provisioning/get $i supported-bands]] ~ "5ghz" and [:len [/interface/wifi/provisioning/get $i slave-configurations]] = 0) do={ :set n ($n + 1) } }; :put ("E=" . $n)' | grep -q "E=[1-9]" && ok "5 GHz ganz ohne weitere SSID (leere Liste gesetzt)" || bad "leere Liste auf 5 GHz nicht gesetzt"
r 1 '/system/script/run cfm-ssid-guest-on; /file/set cfm/ssid-guest.txt contents="on 1000"; /system/script/run cfm-ssid-check' >/dev/null
r 1 "$cnt" | grep -q "G=0" && r 1 ':global cfmSsidguest; :put ("S=" . $cfmSsidguest)' | grep -q "S=off" && ok "Auto-Aus nach Ablauf (cfm-ssid-check)" || bad "Auto-Aus: $(r 1 "$cnt" | tail -1)"
mgr ':global e2eW; /file/set [/file/find name="cfm/work/wifi.rsc"] contents=$e2eW' >/dev/null

step "14b. Bestandsgeräte: Hostfile gw/dns/ntp/cpuVlans/bridgeFrames (cm2), Enroll ohne Apply (sw1)"
# cm2 ist kein Router und per Bootstrap aufgenommen: prüft zugleich, dass die Rolle base die
# Bootstrap-Route übernimmt (Tag cfm:rt:default) statt eine zweite Default-Route anzulegen
mgr ':global e2eC [/file/get [/file/find name="cfm/work/hosts/cm2.rsc"] contents]; /file/set [/file/find name="cfm/work/hosts/cm2.rsc"] contents=($e2eC . ":global cfmHost; :set (\$cfmHost->\"gw\") \"192.168.10.254\"; :set (\$cfmHost->\"dns\") \"192.168.10.253\"; :set (\$cfmHost->\"ntp\") {\"192.168.10.252\"}; :set (\$cfmHost->\"cpuVlans\") {20}; :set (\$cfmHost->\"bridgeFrames\") \"admit-all\"\n")' >/dev/null
rv=$(mgr '$cfmRelease msg=" Hostfile-Overrides" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
# cm2 ist Backup-Manager: Fällt sein Apply in den eigenen Spiegel-Sync, wartet sein Agent auf den SFTP des
# Primary (Wiederholungen bis 2 min, D58) - deshalb bis zu 6 min
agentwait 3 "$rv" cm2 90 && [ "$(stat cm2 res)" = ok ] && ok "cm2 hat v$rv (Hostfile-Overrides) angewendet" || bad "cm2 Apply v$rv: $(stat cm2 res)"
expect 3 '[:len [/ip/route/find where dst-address="0.0.0.0/0" and static]] = 1 and [:tostr [/ip/route/get [find where comment="cfm:rt:default"] gateway]] = "192.168.10.254"' "cm2: genau eine Default-Route, Gateway aus dem Hostfile (Bootstrap-Route übernommen)"
expect 3 '[:tostr [/ip/dns/get servers]] = "192.168.10.253" and [:tostr [/system/ntp/client/get servers]] ~ "192.168.10.252"' "cm2: DNS und NTP aus dem Hostfile"
expect 3 '[:tostr [/interface/bridge/vlan/get [find where comment="cfm:bv:20"] tagged]] ~ "bridge" and [/interface/bridge/get bridge frame-types] = "admit-all"' "cm2: cpuVlans (Bridge in VLAN 20 getaggt) und bridgeFrames"
mgr ':global e2eC; /file/set [/file/find name="cfm/work/hosts/cm2.rsc"] contents=$e2eC' >/dev/null
rv=$(mgr '$cfmRelease msg=" Overrides zurück" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 3 "$rv" cm2 90 && ok "cm2 hat v$rv (ohne Overrides) angewendet" || bad "cm2 Apply v$rv"
agentwait 2 "$rv" sw1 || true   # sw1 bekommt das Release auch (all=yes): erst abwarten, sonst fällt sein Lauf in die Messung unten
expect 3 '[:len [/ip/route/find where dst-address="0.0.0.0/0" and static]] = 1 and [:tostr [/ip/route/get [find where comment="cfm:rt:default"] gateway]] = "192.168.10.1" and [/interface/bridge/get bridge frame-types] = "admit-only-vlan-tagged" and !([:tostr [/interface/bridge/vlan/get [find where comment="cfm:bv:20"] tagged]] ~ "bridge")' "cm2: ohne Overrides wieder MGMT-Gateway, nur getaggt, VLAN 20 ohne Bridge"
# Enroll ohne ersten Apply: Scheduler aus, kein Agent-Lauf, Probelauf möglich; ein Apply schaltet ihn ein
t0=$(stat sw1 t)
mgr '$cfmEnroll name=sw1 ip=192.168.10.21 noapply=yes' | grep -q "Enrolled ohne Apply" && ok "sw1: Enroll mit noapply" || bad "sw1: Enroll mit noapply"
expect 2 '[/system/scheduler/get [find name="cfm-agent"] disabled]' "sw1: Agent-Scheduler nach noapply aus"
sleep 20
[ "$(stat sw1 t)" = "$t0" ] && ok "sw1: kein Agent-Lauf nach noapply" || bad "sw1: Agent lief trotz noapply"
mgr '$cfmPlan host=sw1' | grep -q "# Plan sw1" && ok "sw1: Probelauf nach noapply" || bad "sw1: Probelauf nach noapply"
t1=$(stat sw1 t); mgr '$cfmPush host=sw1 force=yes' >/dev/null
for _ in $(seq 1 40); do [ "$(stat sw1 t)" != "$t1" ] && break; sleep 3; done
expect 2 '![/system/scheduler/get [find name="cfm-agent"] disabled]' "sw1: Apply schaltet den Agent-Scheduler wieder ein"

step "14c. CAPsMAN als eigene Rolle (D45), AP mit lokalem Fallback ohne Radios (D46)"
invrole() { # invrole <alt> <neu>: Rolle im Inventar ersetzen (Wert muss eindeutig sein), Manifeste neu bauen
  local o="\\\"role\\\"=\\\"$1\\\"" n="\\\"role\\\"=\\\"$2\\\"" l=$(( ${#1} + 9 ))
  mgr ':local f [/file/find name="cfm/meta/inventory.rsc"]; :local c [/file/get $f contents]; :local p [:find $c "'"$o"'"]; /file/set $f contents=([:pick $c 0 $p] . "'"$n"'" . [:pick $c ($p + '"$l"') [:len $c]]); :global cfmManifests; $cfmManifests' >/dev/null; }
applied() { # applied <name>: Lauf erzwingen und abwarten, true bei res=ok. Vorher warten, bis kein
  # Agent-Lauf mehr läuft (sonst "Agent läuft bereits", der erzwungene Lauf kommt erst per Retry).
  # Bis zu 3 Versuche: Synchronisiert cm2 als Backup gerade seinen Spiegel, läuft der Abruf des
  # Agenten vom Primary gelegentlich in einen Timeout ("kein Manager erreichbar", kein Report).
  local vm t0 n; case $1 in cm1) vm=1;; sw1) vm=2;; cm2) vm=3;; esac
  for n in 1 2 3; do
    for _ in $(seq 1 40); do r "$vm" ':put [:len [/system/script/job/find where script="cfm-agent"]]' | tail -1 | grep -qx 0 && break; sleep 3; done
    t0=$(stat "$1" t); mgr "\$cfmPush host=$1 force=yes" >/dev/null
    for _ in $(seq 1 60); do [ "$(stat "$1" t)" != "$t0" ] && break; sleep 4; done
    [ "$(stat "$1" t)" != "$t0" ] && break
    echo "    ($1: kein Report nach dem Push, Versuch $n)"
  done
  [ "$(stat "$1" t)" != "$t0" ] && [ "$(stat "$1" res)" = ok ]; }
mgr ':global cfmCheck; :foreach e in=([$cfmCheck]->"warn") do={ :put $e }' | grep -q "kein Gerät mit Rolle capsman" && ok "Prüfung: Übergang ohne Rolle capsman gemeldet (cm1 bleibt CAPsMAN)" || bad "Übergangswarnung fehlt"
# API-Lesezugang auf dem CAPsMAN (D47): erst auf cm1 (Übergangsregel), wandert mit der Rolle capsman
mgr ':global e2eG [/file/get [/file/find name="cfm/work/global.rsc"] contents]; /file/set [/file/find name="cfm/work/global.rsc"] contents=($e2eG . ":set (\$cfmG->\"capsmanApi\") {\"from\"={\"10.0.2.2/32\"};\"user\"=\"hatest\"}\n")' >/dev/null
mgr '$cfmSecret key=user.hatest value="Api-Lab-2026"' >/dev/null
rv=$(mgr '$cfmRelease msg=" capsmanApi" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 1 "$rv" cm1 && ok "cm1 hat v$rv (capsmanApi) angewendet" || bad "cm1 Apply v$rv"
agentwait 2 "$rv" sw1 || true; agentwait 3 "$rv" cm2 || true
expect 1 '![/ip/service/get [find name=api] disabled] and [:tostr [/ip/service/get [find name=api] available-from]] ~ "10.0.2.2" and [/user/get [find name=hatest] group] = "cfm-api" and [:len [/ip/firewall/filter/find where comment~"^cfm:capi" and dst-port="8728" and src-address~"10.0.2.2"]] = 1' "cm1: API nur für capsmanApi.from, User hatest (cfm-api), Freigabe in local-input"
expect 2 '[/ip/service/get [find name=api] disabled]' "sw1: API aus (kein CAPsMAN)"
expect 2 '[:len [/ip/firewall/filter/find where comment~"^cfm:fw:" and chain=forward and dst-address~"^192.168.10.2(/32)?\$" and dst-port="8728" and src-address~"10.0.2.2"]] = 1' "sw1 (router): Forward-Freigabe zur API des CAPsMAN cm1"
expect 1 '[/interface/wifi/provisioning/get [find where comment~"^cfm:wprov:00"] name-format] = "%I-2g"' "cm1: Interface-Namen aus Identity und Band (name-format)"
# CAPsMAN auf sw1, cm2 zusätzlich AP (CHR ohne Radios: CAP-Einstellungen, Profile, Passphrasen)
invrole "switch,router" "switch,router,capsman"
invrole "manager-backup" "manager-backup,ap"
out=$(mgr ':global cfmCheck; /file/add name="cfm/meta/inv2.rsc" contents=[/file/get [/file/find name="cfm/meta/inventory.rsc"] contents]; :local f [/file/find name="cfm/meta/inventory.rsc"]; :local c [/file/get $f contents]; :local p [:find $c "\"role\"=\"manager\""]; /file/set $f contents=([:pick $c 0 $p] . "\"role\"=\"manager,capsman\"" . [:pick $c ($p + 16) [:len $c]]); :foreach e in=([$cfmCheck]->"err") do={ :put $e }; /file/set $f contents=[/file/get [/file/find name="cfm/meta/inv2.rsc"] contents]; /file/remove [/file/find name="cfm/meta/inv2.rsc"]')
echo "$out" | grep -q "Rolle capsman mehrfach vergeben" && ok "Prüfung: nur ein CAPsMAN (Rolle capsman doppelt = Fehler)" || { bad "doppelte Rolle capsman nicht erkannt"; echo "$out" | tail -3; }
applied sw1 && ok "sw1 als switch,router,capsman angewendet" || bad "sw1 capsman: $(stat sw1 res)"
expect 2 '[:len [/file/find where name="cfm/dl/lib/lib-wifi.rsc"]] = 1' "sw1 (capsman): WLAN-Teil lib/lib-wifi.rsc geladen (D68)"
# Kam der Secret-Sync des Manager-Ticks (1 min) schon dazwischen (langsames Labor), ist der CAPsMAN bereits mit PSK an
expect 2 '[:len [/interface/wifi/provisioning/find where comment~"^cfm:wprov"]] >= 2 and (([:tostr [/interface/wifi/capsman/get enabled]] ~ "no|false" and [/ppp/secret/get [find name="cfm:key"] comment] ~ "sv=0\$") or ([:tostr [/interface/wifi/capsman/get enabled]] ~ "yes|true" and [:len [/interface/wifi/security/get [find name="cfm-main"] passphrase]] > 0))' "sw1: CAPsMAN gerendert, bleibt aus bis zur PSK (Secret-Push angefordert)"
mgr '$cfmSecretPush host=sw1' >/dev/null
expect 2 '[:tostr [/interface/wifi/capsman/get enabled]] ~ "yes|true" and [/interface/wifi/security/get [find name="cfm-main"] passphrase] = "lab-psk-12345"' "sw1: Secret-Push setzt die PSK und schaltet den CAPsMAN ein"
applied cm1 && ok "cm1 nach dem Umzug angewendet" || bad "cm1: $(stat cm1 res)"
expect 1 '[:tostr [/interface/wifi/capsman/get enabled]] ~ "no|false" and [:len [/interface/wifi/provisioning/find where comment~"^cfm:wprov"]] = 0 and [:len [/interface/wifi/security/find where comment~"^cfm:wsec"]] = 0' "cm1: CAPsMAN aus, Profile abgeräumt"
expect 1 '[/ip/service/get [find name=api] disabled] and [:len [/user/find where name=hatest]] = 0 and [:len [/ip/firewall/filter/find where comment~"^cfm:capi"]] = 0' "cm1: API, User und Freigabe mit der Rolle capsman abgeräumt"
expect 2 '![/ip/service/get [find name=api] disabled] and [/user/get [find name=hatest] group] = "cfm-api" and ![/user/get [find name=hatest] disabled]' "sw1: API-Zugang umgezogen, User nach dem Secret-Push aktiv"
expect 2 '[:len [/ip/firewall/filter/find where comment~"^cfm:fw:" and dst-port="8728"]] = 0' "sw1: als CAPsMAN selbst keine Forward-Freigabe (local-input reicht)"
applied cm2 && ok "cm2 als manager-backup,ap angewendet" || bad "cm2 ap: $(stat cm2 res)"
expect 3 '[:tostr [/interface/wifi/cap/get caps-man-addresses]] = "192.168.10.21" and [:tostr [/interface/wifi/cap/get caps-man-names]] = "sw1" and [/interface/wifi/datapath/get [find name="cfm-cap"] comment] = "cfm:wdp-cap cm=sw1"' "cm2: CAP zeigt auf sw1 (Adresse und Name aus dem Manifest, im Datapath gemerkt)"
expect 3 '[:len [/interface/wifi/configuration/find where comment~"^cfm:wcf:l"]] = 2 and [/interface/wifi/datapath/get [find name="cfm-main"] vlan-id] = 20 and [:tostr [/interface/wifi/capsman/get enabled]] ~ "no|false"' "cm2: lokale Fallback-Konfiguration je Band, Datapath mit VLAN, kein CAPsMAN"
mgr '$cfmSecretPush host=cm2' >/dev/null
expect 3 '[/interface/wifi/security/get [find name="cfm-main"] passphrase] = "lab-psk-12345"' "cm2: PSK für den lokalen Fallback per Secret-Push"
# Fallback-Anzeige (TODO 40d): Status-Feld wfb passt zum CAP-Zustand (CHR ohne Radios: verbunden oder nicht)
conn=$(r 3 ':put [:len [:tostr [/interface/wifi/cap/get current-caps-man-identity]]]' | tail -1 | tr -dc 0-9)
t0=$(stat cm2 t); mgr '$cfmPush host=cm2 force=yes' >/dev/null
for _ in $(seq 1 40); do [ "$(stat cm2 t)" != "$t0" ] && break; sleep 3; done
w=$(stat cm2 wfb | tr -dc 0-9)
if [ "${conn:-0}" = 0 ]; then
  [ "$w" = 1 ] && mgr '$cfmStatus' | grep -q "WLAN lokal" && ok "cm2 ohne CAPsMAN-Verbindung: \$cfmStatus zeigt WLAN lokal" || bad "Fallback-Anzeige fehlt (wfb=$w)"
else
  [ -z "$w" ] && ok "cm2 mit CAPsMAN verbunden: keine Fallback-Anzeige" || bad "Fallback-Anzeige trotz Verbindung (wfb=$w)"
fi
applied cm2 || true
stat cm2 stats | grep -q "add=0;rem=0;set=0;skip=0" && ok "Rolle ap idempotent" || bad "ap idempotent: $(stat cm2 stats)"
expect 3 '[:len [/log/find where message~"slaves-static"]] = 0' "cm2: slaves-static ohne fallback nicht gesetzt (kein Abriss zum CAPsMAN, TODO 40)"
# AP mit wifi-qcom-ac (TODO 23): \$cfmCheck warnt anhand der gemeldeten Pakete (Status kurz verändert)
out=$(mgr ':local f [/file/find name="cfm/state/cm2/status.dat"]; :local c [/file/get $f contents]; :local j [:deserialize from=json $c]; :set ($j->"pkgs") ({"routeros";"wifi-qcom-ac"}); /file/set $f contents=[:serialize to=json $j]; :global cfmCheck; :foreach e in=([$cfmCheck]->"warn") do={ :put ("W " . $e) }; /file/set $f contents=$c')
echo "$out" | grep -q "W inventory: cm2 hat das Paket wifi-qcom-ac" && ok "\$cfmCheck warnt vor wifi-qcom-ac am AP (TODO 23)" || { bad "Warnung wifi-qcom-ac fehlt"; echo "$out" | tail -3; }
# CAPsMAN zurück auf cm1 (ohne Rolle capsman übernimmt der Primary): cm2 folgt, erneuert Zertifikate
nc=$(r 3 ':put [:len [/certificate/find where trust-store=capsman]]' | tail -1 | tr -dc 0-9)
invrole "switch,router,capsman" "switch,router"
applied sw1 && ok "sw1 ohne Rolle capsman angewendet" || bad "sw1: $(stat sw1 res)"
expect 2 '[:len [/file/find where name="cfm/dl/lib/lib-wifi.rsc"]] = 0 and [:len [/file/find where name="cfm/dl/lib/lib.rsc"]] = 1' "sw1 ohne WLAN-Rolle: lib-wifi.rsc nicht mehr im Manifest, aus dl/ entfernt (D68, D69)"
expect 2 '[:tostr [/interface/wifi/capsman/get enabled]] ~ "no|false" and [:len [/interface/wifi/provisioning/find where comment~"^cfm:wprov"]] = 0' "sw1: CAPsMAN aus und abgeräumt"
applied cm1 && ok "cm1 wieder CAPsMAN (Übergangsregel)" || bad "cm1: $(stat cm1 res)"
mgr '$cfmSecretPush host=cm1' >/dev/null
expect 1 '[:tostr [/interface/wifi/capsman/get enabled]] ~ "yes|true" and [:len [/interface/wifi/provisioning/find where comment~"^cfm:wprov"]] >= 2' "cm1: CAPsMAN nach dem Secret-Push wieder aktiv"
applied cm2 && ok "cm2 folgt dem CAPsMAN" || bad "cm2: $(stat cm2 res)"
expect 3 '[:tostr [/interface/wifi/cap/get caps-man-names]] = "cm1" and [/interface/wifi/datapath/get [find name="cfm-cap"] comment] = "cfm:wdp-cap cm=cm1"' "cm2: CAP zeigt auf cm1"
if [ "${nc:-0}" -gt 0 ]; then
  expect 3 '[:len [/log/find where message~"^cfm: CAPsMAN-Zertifikate erneuert"]] >= 1' "cm2: Zertifikate des alten CAPsMAN erneuert ($nc vorher)"
else echo "  - cm2 hatte keine CAPsMAN-Zertifikate (CAP ohne Radios), Erneuerung nicht prüfbar"; fi
invrole "manager-backup,ap" "manager-backup"
applied cm2 && ok "cm2 wieder nur manager-backup" || bad "cm2: $(stat cm2 res)"
mgr ':global e2eG; /file/set [/file/find name="cfm/work/global.rsc"] contents=$e2eG' >/dev/null
rv=$(mgr '$cfmRelease msg=" capsmanApi aus" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 1 "$rv" cm1 && ok "cm1 hat v$rv (ohne capsmanApi) angewendet" || bad "cm1 Apply v$rv"
agentwait 2 "$rv" sw1 || true; agentwait 3 "$rv" cm2 || true
expect 1 '[/ip/service/get [find name=api] disabled] and [:len [/user/find where name=hatest]] = 0' "cm1: ohne capsmanApi kein API-Zugang"
expect 2 '[:len [/ip/firewall/filter/find where comment~"^cfm:fw:" and dst-port="8728"]] = 0' "sw1 (router): ohne capsmanApi keine Forward-Freigabe"
expect 3 '[:len [/interface/wifi/configuration/find where comment~"^cfm:wcf"]] = 0 and [:len [/interface/wifi/security/find where comment~"^cfm:wsec"]] = 0' "cm2: WLAN-Profile ohne Rolle ap abgeräumt"
r 3 '/interface/wifi/cap/set enabled=no' >/dev/null

expect 3 '[:len [/log/find where message~"login failure for user cfmd-cm2 from 192.168.10.3"]] = 0' "cm2: Agent fragt nie sich selbst (TODO 44)"
expect 2 '[:len [/log/find where message~"deprecation warning"]] = 0' "sw1: keine Deprecation-Warnung (/ip/service available-from, TODO 43)"

step "14d. Watchdog: Apply kappt den Weg zum Manager -> Rollback nach Ablauf"
# sw1.post.rsc schaltet die MGMT-Adresse ab: Der Apply gelingt, die Bestätigung scheitert. Zurück
# rollt erst der Scheduler cfm-watchdog (watchdog=5m, angelegt ohne start-time - RouterOS 7.24 bis
# 7.24.4: "scheduler scripts with the default start date and time not being triggered"), dessen
# Lauf das Manifest noch 2 min lang wiederholt abzurufen versucht (TODO 44).
rv=$(mgr '/file/add name="cfm/work/hosts/sw1.post.rsc" contents=":global cfmDry; :if (\$cfmDry != true) do={ /ip/address/disable [find where address=\"192.168.10.21/24\"] }"; $cfmRelease msg=" Watchdog-Test"' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
for _ in $(seq 1 45); do r 2 ':put [:len [/ip/address/find where address="192.168.10.21/24" and disabled]]' | grep -qx 1 && break; sleep 4; done
expect 2 '[:len [/ip/address/find where address="192.168.10.21/24" and disabled]] = 1 and [:len [/system/scheduler/find where name="cfm-watchdog"]] = 1' "sw1: v$rv angewendet, MGMT-Adresse aus, Watchdog scharf"
r 2 '/system/scheduler/print detail where name="cfm-watchdog"' | grep -o 'start-date=[^ ]* start-time=[^ ]*' | head -1 | sed 's/^/    /'
# 5 min Watchdog + 2 min Wiederholungen + Neustart
for _ in $(seq 1 120); do r 2 ':put [:len [/ip/address/find where address="192.168.10.21/24" and !disabled]]' 2>/dev/null | grep -qx 1 && break; sleep 6; done
waitssh 2
for _ in $(seq 1 45); do [ "$(stat sw1 bad)" = "$rv" ] && break; sleep 4; done
[ "$(stat sw1 bad)" = "$rv" ] && [ "$(stat sw1 res)" = rollback-watchdog ] && ok "sw1: Watchdog hat zurückgerollt (res=rollback-watchdog, v$rv als bad)" || { bad "Watchdog: res=$(stat sw1 res) bad=$(stat sw1 bad)"; diag step14d; }
expect 2 '[:len [/ip/address/find where address="192.168.10.21/24" and !disabled]] = 1 and [:len [/system/scheduler/find where name="cfm-watchdog"]] = 0' "sw1: MGMT-Adresse wieder an, kein Watchdog mehr"
rv=$(mgr '/file/remove [find name="cfm/work/hosts/sw1.post.rsc"]; $cfmRelease msg=" Watchdog-Test zurück"' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 2 "$rv" sw1 && [ "$(stat sw1 res)" = ok ] && ok "sw1 hat v$rv ohne post.rsc angewendet" || bad "sw1 Apply v$rv: $(stat sw1 res)"

step "14e. Admin-SSH-Keys je User (D65)"
# gemeinsame Datei abgelehnt, Datei eines unbekannten Users gewarnt, kaputte Zeile ein Fehler
out=$(mgr '/file/add name="cfm/work/authorized_keys" contents="x"; /file/add name="cfm/work/authorized_keys.niemand" contents="ssh-ed25519 AAAA== x\nkaputt\n"; :delay 200ms; :global cfmCheck; :local ck [$cfmCheck]; :foreach e in=($ck->"err") do={ :put ("ERR " . $e) }; :foreach e in=($ck->"warn") do={ :put ("W " . $e) }; /file/remove [find name="cfm/work/authorized_keys"]; /file/remove [find name="cfm/work/authorized_keys.niemand"]')
echo "$out" | grep -q "ERR authorized_keys: die gemeinsame Datei gilt nicht mehr" && ok "\$cfmCheck: gemeinsame authorized_keys abgelehnt" || { bad "gemeinsame authorized_keys nicht abgelehnt"; echo "$out" | tail -3; }
echo "$out" | grep -q "W authorized_keys.niemand: niemand steht nicht in global.rsc users" && echo "$out" | grep -q "ERR authorized_keys.niemand: Zeile 2" && ! echo "$out" | grep -q "niemand: Zeile 1" && ok "\$cfmCheck: unbekannter User gewarnt, kaputte Zeile 2 ein Fehler" || { bad "Prüfung authorized_keys.<user>"; echo "$out" | grep niemand; }
# netadmin: Lab-Key + zweiter Key; ein Hand-Key auf sw1 wird entfernt, der Login per Key klappt
rm -f "$LAB/e2e_k2" "$LAB/e2e_k2.pub" "$LAB/e2e_k3" "$LAB/e2e_k3.pub"
ssh-keygen -q -t ed25519 -N "" -C "e2e@zwei" -f "$LAB/e2e_k2"; ssh-keygen -q -t ed25519 -N "" -C "e2e@hand" -f "$LAB/e2e_k3"
printf '# Testkeys\n%s\n\n%s\n' "$(cat "$LAB/lab_key.pub")" "$(cat "$LAB/e2e_k2.pub")" > "$LAB/ak.netadmin"
echo "put $LAB/ak.netadmin cfm/work/authorized_keys.netadmin" | put 1
r 2 "/user/ssh-keys/add user=netadmin key=\"$(cat "$LAB/e2e_k3.pub")\"" >/dev/null
v0=$(stat sw1 v)
out=$(mgr '$cfmPlan host=sw1')
echo "$out" | grep -q "Admin-SSH-Keys netadmin: 2 neu, 1 entfernt" && ok "Plan: 2 Keys neu, Hand-Key entfernt" || { bad "Plan Admin-SSH-Keys"; echo "$out" | grep -i "keys" | head -3; }
rv=$(mgr '$cfmRelease msg=" Admin-Keys" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 2 "$rv" sw1 && ok "sw1 hat v$rv (Admin-Keys) angewendet" || bad "sw1 Apply v$rv"
agentwait 1 "$rv" cm1 || true; agentwait 3 "$rv" cm2 || true
mgr "\$cfmDiff ver=$v0 to=$rv" | grep -q "betroffen: alle Geräte" && ok "\$cfmDiff: Key-Datei betrifft alle Geräte" || bad "\$cfmDiff ohne alle Geräte"
expect 2 '[:len [/user/ssh-keys/find where user=netadmin]] = 2 and [:len [/user/ssh-keys/find where user=netadmin and info="e2e@hand"]] = 0 and [:len [/user/ssh-keys/find where user=netadmin and info="e2e@zwei"]] = 1' "sw1: netadmin hat genau die zwei Keys der Datei, Hand-Key entfernt"
expect 2 '[:len [/user/ssh-keys/find where user!=netadmin and info~"e2e@"]] = 0' "sw1: andere User ohne Datei unangetastet"
out=$(ssh -p $((LABPORT+20)) "${O[@]}" -o BatchMode=yes -i "$LAB/e2e_k2" netadmin@127.0.0.1 ':put keyok' 2>&1 | tr -d '\r')
echo "$out" | grep -q keyok && ok "sw1: Login als netadmin mit dem zweiten Key" || bad "Key-Login netadmin: $(echo "$out" | tail -1)"
lm0=$(r 2 ':put [/file/get cfm/dl/roles/base.rsc last-modified]' | tail -1)
applied sw1 || true
stat sw1 stats | grep -q "add=0;rem=0;set=0;skip=0" && ok "Keys idempotent (zweiter Apply ohne Änderung)" || bad "Keys idempotent: $(stat sw1 stats)"
lm1=$(r 2 ':put [/file/get cfm/dl/roles/base.rsc last-modified]' | tail -1)
[ -n "$lm0" ] && [ "$lm0" = "$lm1" ] && ok "Reapply lädt unveränderte Dateien nicht neu (D69)" || bad "Reapply lud roles/base.rsc neu ($lm0 -> $lm1)"
expect 1 '[:len [/file/find where name="cfm/dl/lib/lib-wifi.rsc"]] = 1' "cm1 (manager): WLAN-Teil lib/lib-wifi.rsc im Manifest (D68)"
# alle Keys einer Person entziehen = Datei leeren; danach Datei weg (Schritt 15 meldet netadmin per Passwort an)
echo "# entzogen" > "$LAB/ak.netadmin"; echo "put $LAB/ak.netadmin cfm/work/authorized_keys.netadmin" | put 1
rv=$(mgr '$cfmRelease msg=" Admin-Keys entzogen" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 2 "$rv" sw1 || true; agentwait 1 "$rv" cm1 || true; agentwait 3 "$rv" cm2 || true
expect 2 '[:len [/user/ssh-keys/find where user=netadmin]] = 0' "sw1: leere Datei entzieht alle Keys von netadmin"
expect 1 '[:len [/user/ssh-keys/find where user=netadmin]] = 0' "cm1: leere Datei entzieht alle Keys von netadmin"
mgr '/file/remove [find name="cfm/work/authorized_keys.netadmin"]' >/dev/null

step "14f. Benachrichtigungen (D66)"
# Empfänger auf dem Host; die VMs erreichen ihn über das QEMU-User-Net als 10.0.2.2
NP=$((LABPORT + 91)); NL="$LAB/notify.log"; : > "$NL"
sink() { python3 "$ROOT/tools/chr-lab/notify-sink.py" "$NP" "$NL" & npid=$!; sleep 1; }
sink
nwait() { for _ in $(seq 1 15); do [ "$(grep -c "$1" "$NL")" -ge "${2:-1}" ] && return 0; sleep 2; done; return 1; }
out=$(mgr ':global cfmDays; :global cfmNotifyLic; :put ("D=" . [$cfmDays "1970-01-01"] . "," . [$cfmDays "2000-02-29"] . "," . [$cfmDays "2000-03-01"] . "," . [$cfmDays "2024-02-29 10:00:00"] . "," . [$cfmDays "2026-10-08"] . "," . [$cfmDays "oct/08/2026"]); :put ("L1=" . [$cfmNotifyLic now="2026-10-08" renew="2026-10-07 23:00:00" deadline="2026-11-18 00:00:00" warn=14]); :put ("L2=" . [$cfmNotifyLic now="2026-10-08" renew="2026-10-08 01:00:00" deadline="2026-11-18" warn=14]); :put ("L3=" . [$cfmNotifyLic now="2026-11-05" renew="2026-12-01" deadline="2026-11-18" warn=14]); :put ("L4=" . [$cfmNotifyLic now="2026-10-08" renew="" deadline="" warn=14])')
echo "$out" | grep -q "^D=0,11016,11017,19782,20734,-1$" && ok "\$cfmDays: Tage seit 1970 (Schaltjahre, Uhrzeit, unlesbar = -1)" || { bad "\$cfmDays"; echo "$out" | grep "^D="; }
echo "$out" | grep -q "^L1=CHR-Lizenz: Erneuerung überfällig seit 2026-10-07" && echo "$out" | grep -qx "L2=" && echo "$out" | grep -q "^L3=CHR-Lizenz läuft am 2026-11-18 ab (in 13 Tagen)" && echo "$out" | grep -qx "L4=" && ok "Lizenz: überfällig, rechtzeitig, Ablauf in 13 Tagen, ohne Angaben" || { bad "Lizenzprüfung"; echo "$out" | grep "^L"; }
out=$(mgr '$cfmNotify test=yes')
echo "$out" | grep -q "notify.url ist leer" && ok "ohne notify.url aus" || { bad "notify ohne URL"; echo "$out" | tail -2; }
mgr ':global e2eG [/file/get [/file/find name="cfm/work/global.rsc"] contents]; /file/set [/file/find name="cfm/work/global.rsc"] contents=($e2eG . ":set (\$cfmG->\"notify\"->\"url\") \"http://10.0.2.2:'"$NP"'/hook\"\n:set (\$cfmG->\"notify\"->\"site\") \"Labor\"\n")' >/dev/null
out=$(mgr ':global cfmCheck; :global e2eG; /file/set [/file/find name="cfm/work/global.rsc"] contents=($e2eG . ":set (\$cfmG->\"notify\") {\"url\"=\"ftp://x\";\"stale\"=\"bald\"}\n"); :foreach e in=([$cfmCheck]->"err") do={ :put ("ERR " . $e) }; /file/set [/file/find name="cfm/work/global.rsc"] contents=($e2eG . ":set (\$cfmG->\"notify\"->\"url\") \"http://10.0.2.2:'"$NP"'/hook\"\n:set (\$cfmG->\"notify\"->\"site\") \"Labor\"\n")')
echo "$out" | grep -q "ERR global.rsc: notify url ftp://x ist keine http(s)-URL" && echo "$out" | grep -q "ERR global.rsc: notify stale=bald ist keine Zeitangabe" && ok "\$cfmCheck: notify-URL und Zeitangabe geprüft" || { bad "\$cfmCheck notify"; echo "$out" | tail -3; }
rv=$(mgr '$cfmRelease msg=" notify" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 2 "$rv" sw1 || true; agentwait 1 "$rv" cm1 || true; agentwait 3 "$rv" cm2 || true
# 14e hat authorized_keys.netadmin aus work/ gelöscht: Die Datei darf nicht in dl/ liegen bleiben (D69)
expect 2 '[:len [/file/find where name="cfm/dl/authorized_keys.netadmin"]] = 0 and [:len [/file/find where name="cfm/dl/roles/base.rsc"]] = 1' "sw1: gelöschte authorized_keys.netadmin auch aus dl/ entfernt (D65, D69)"
out=$(mgr '$cfmNotify test=yes; $cfmNotify ev="e2e" host="sw1" st="once" msg=("Pr\C3\BCfung \C3\A4\C3\B6\C3\BC \"x\"")')
echo "$out" | grep -q "zugestellt an http://10.0.2.2:$NP/hook" && nwait '"ev": "test"' && ok "Probemeldung zugestellt" || { bad "Probemeldung"; echo "$out" | tail -2; }
nwait '"ev": "e2e"' && grep '"ev": "e2e"' "$NL" | grep -q '"site": "Labor", "host": "sw1", "ev": "e2e", "state": "once", "msg": "Prüfung äöü \\"x\\"", "text": "Labor: sw1 - Prüfung äöü \\"x\\""' && grep '"ev": "e2e"' "$NL" | grep -q '"_ct": "application/json"' && ok "JSON mit Umlauten und Anführungszeichen, Content-Type application/json" || { bad "JSON der Meldung"; tail -1 "$NL"; }
grep '"ev": "test"' "$NL" | grep -q '"level": "info", "device": "cm1", "message": "Labor: Probemeldung von cfm"' && grep '"ev": "e2e"' "$NL" | grep -q '"level": "warning", "device": "sw1"' && ok "level/device/message (Probe info, Gerät statt Absender)" || { bad "level/device/message"; grep '"ev": "test"' "$NL" | tail -1; }
# Umlaute oben als Bytes (\C3\BC): die Konsole verwirft Mehrbyte-Zeichen aus der ssh-Befehlszeile
# Zustände von sw1 im gesammelten Status vortäuschen: stumm, Apply-Fehler, WLAN lokal, Update fehlgeschlagen
setst() { mgr ':global cfmJson; :global cfmWrite; :global cfmRead; :global cfmNow; :global e2eS; :if ([:typeof $e2eS] != "str") do={ :set e2eS [$cfmRead "cfm/state/sw1/status.dat"] }; :local s [$cfmJson "cfm/state/sw1/status.dat"]; :set ($s->"seen") ([$cfmNow] - 3600); :set ($s->"res") "failed e2e"; :set ($s->"wfb") 1; :set ($s->"upg") "fehlgeschlagen 7.0.0"; $cfmWrite "cfm/state/sw1/status.dat" [:serialize to=json $s]; :global cfmNotifyTick; :put ("NT=" . [$cfmNotifyTick])'; }
rest() { mgr ':global cfmWrite; :global e2eS; $cfmWrite "cfm/state/sw1/status.dat" $e2eS; :set e2eS; :global cfmNotifyTick; :put ("NT=" . [$cfmNotifyTick])'; }
setst >/dev/null
nwait '"state": "on"' 4 && for e in stumm apply wlan update; do grep -q "\"host\": \"sw1\", \"ev\": \"$e\", \"state\": \"on\"" "$NL" || bad "keine Meldung $e"; done && ok "vier Meldungen beim Eintreten (stumm, apply, wlan, update)" || { bad "Meldungen beim Eintreten: $(grep -c '"state": "on"' "$NL")"; grep '"state": "on"' "$NL" | cut -c1-160; }
grep '"ev": "apply", "state": "on"' "$NL" | grep -q '"level": "error"' && grep '"ev": "stumm", "state": "on"' "$NL" | grep -q '"level": "error"' && grep '"ev": "wlan", "state": "on"' "$NL" | grep -q '"level": "warning"' && grep '"ev": "update", "state": "on"' "$NL" | grep -q '"level": "action"' && ok "level: apply/stumm error, wlan warning, update action" || bad "level beim Eintreten: $(grep '"state": "on"' "$NL" | grep -o '"ev": "[a-z]*".*"level": "[a-z]*"' | sed 's/"state.*"level"/ level/' | tr '\n' ' ')"
grep '"ev": "apply", "state": "on"' "$NL" | grep -q '"msg": "Apply-Fehler: failed e2e"' && grep '"ev": "stumm", "state": "on"' "$NL" | grep -q '"msg": "stumm: kein Status seit 6[0-9] min"' && ok "Texte: Apply-Fehler, stumm seit 60 min" || bad "Meldungstexte: $(grep '"state": "on"' "$NL" | cut -c1-200 | head -2)"
setst >/dev/null; sleep 2
[ "$(grep -c '"state": "on"' "$NL")" = 4 ] && ok "kein zweites Mal, solange der Zustand bleibt" || bad "Wiederholung: $(grep -c '"state": "on"' "$NL") Meldungen"
rest >/dev/null
nwait '"state": "off"' 4 && grep '"ev": "apply", "state": "off"' "$NL" | grep -q '"msg": "wieder ok (war: Apply-Fehler: failed e2e)"' && ok "vier Meldungen \"wieder ok\"" || { bad "Meldungen wieder ok: $(grep -c '"state": "off"' "$NL")"; }
[ "$(grep '"state": "off"' "$NL" | grep -c '"level": "warning"')" = 4 ] && ok "\"wieder ok\" mit level warning" || bad "level von wieder ok"
# neue RouterOS-Version (level action): echte Abfrage bei MikroTik (Internet über ether1 aus Schritt 13),
# dann mit vorgetäuschter Version; je Version nur einmal, auch wenn erneut gefragt wird
mgr ':global cfmRosLatest; :put ("RL=" . [$cfmRosLatest])' | grep -qE '^RL=7\.[0-9]+' && ok "neueste RouterOS-Version bei MikroTik abgefragt" || bad "NEWESTa7 nicht abrufbar: $(mgr ':global cfmRosLatest; :put ("RL=" . [$cfmRosLatest])' | tail -1)"
rost() { mgr ':global cfmJson; :global cfmWrite; :local j [$cfmJson "cfm/meta/notify.dat"]; :set ($j->"rost") 0; $cfmWrite "cfm/meta/notify.dat" [:serialize to=json $j]; :global cfmRosFake "7.99.1"; :global cfmNotifyTick; :put ("NT=" . [$cfmNotifyTick]); :set cfmRosFake'; }
rost >/dev/null
nwait 'RouterOS 7.99.1' && grep 'RouterOS 7.99.1' "$NL" | grep -q '"state": "once", "msg": "RouterOS 7.99.1 (stable) verfügbar, älter: .*sw1=7\.[0-9.]*.*"level": "action"' && ok "neue Version gemeldet (level action, ältere Geräte genannt)" || { bad "Meldung neue Version"; grep '"ev": "ros"' "$NL" | tail -1 | cut -c1-250; }
rost >/dev/null; sleep 2
[ "$(grep -c 'RouterOS 7.99.1' "$NL")" = 1 ] && ok "dieselbe Version kein zweites Mal" || bad "Version mehrfach gemeldet: $(grep -c 'RouterOS 7.99.1' "$NL")"
expect 1 '[:len ([:deserialize from=json [/file/get cfm/meta/notify.dat contents]]->"act")] = 0' "notify.dat: keine offenen Zustände"
# Empfänger weg: nichts gilt als gemeldet, der nächste Tick holt es nach
kill $npid 2>/dev/null; wait $npid 2>/dev/null; n0=$(grep -c . "$NL")
setst >/dev/null
expect 1 '[:len [/log/find where message~"^cfm: Meldung nicht zugestellt"]] >= 1 and [:len ([:deserialize from=json [/file/get cfm/meta/notify.dat contents]]->"act")] = 0' "Empfänger aus: Warnung im Log, nichts als gemeldet vermerkt"
sink; setst >/dev/null
nwait '"state": "on"' 8 && ok "Empfänger zurück: Meldungen nachgeholt" || bad "nicht nachgeholt: $(grep -c '"state": "on"' "$NL")"
rest >/dev/null; nwait '"state": "off"' 8 || bad "wieder ok nach dem Nachholen fehlt"
# Spiegel auf cm2 sofort anstoßen: als User cfm (dessen Schlüssel braucht der SFTP-Abruf) im Hintergrund,
# ssh-exec selbst liefe vorher in seine Zeitgrenze; Ergebnis in e2e-mir.txt auf cm2
mirror() { local f="e2e-mir-$RANDOM.txt"
  mgr ':global cfmExec; $cfmExec ip=192.168.10.3 cmd=(":execute script=\"/system script run cfm-mgr; :global cfmMirT; :set cfmMirT 0; :global cfmMirror; /file/add name='"$f"' contents=(\\\"MIR=\\\" . [\\\$cfmMirror])\"")' >/dev/null
  for _ in $(seq 1 60); do o=$(r 3 ':onerror e in={ :put ("F=" . [/file/get '"$f"' contents]) } do={ :put none }' | tail -1); [ "${o#F=}" != "$o" ] && { echo "${o#F=}"; r 3 "/file/remove $f" >/dev/null; return; }; sleep 4; done; echo MIR=timeout; }
# Backup überwacht den Primary (ev primary, level error): auf cm2 als User cfm, letzter Spiegel-Abruf bzw.
# Uhr künstlich versetzt; der echte Tick von cm2 kann dazwischen funken, deshalb nur auf Inhalte prüfen
bk() { mgr ':global cfmExec; :local r [$cfmExec ip=192.168.10.3 cmd=("/system script run cfm-mgr; :global cfmMirLast; :set cfmMirLast ([:tonsec [:timestamp]] / 1000000000 + '"$1"'); :global cfmNotifyBackupTick; :put (\"NB=\" . [\$cfmNotifyBackupTick skew='"$2"'])")]; :put ($r->"output")' | grep -o 'NB=[0-9]*'; }
mirror | grep -q MIR=true || bad "Spiegel auf cm2 vor der Primary-Überwachung"   # cm2 braucht das Release mit notify
bk -7200 0 >/dev/null
nwait '"ev": "primary", "state": "on"' && grep '"ev": "primary", "state": "on"' "$NL" | grep -q '"host": "cm1".*"msg": "Primary nicht erreichbar: Spiegel-Abruf per SFTP seit 120 min.*"level": "error", "device": "cm1"' && ok "Backup: Primary per SFTP nicht erreichbar gemeldet (error)" || { bad "Meldung Primary nicht erreichbar"; grep '"ev": "primary' "$NL" | tail -2 | cut -c1-220; }
bk 3600 3600 >/dev/null
nwait '"ev": "primary-tick", "state": "on"' && grep '"ev": "primary-tick", "state": "on"' "$NL" | grep -q '"msg": "Primary erreichbar, aber sein Tick steht: neuester Gerätestatus [0-9]* min alt' && grep -q '"ev": "primary", "state": "off"' "$NL" && ok "Backup: Tick des Primary steht (Status zu alt), SFTP wieder ok" || { bad "Meldung Tick steht"; grep '"ev": "primary' "$NL" | tail -3 | cut -c1-220; }
bk 0 0 >/dev/null
nwait '"ev": "primary-tick", "state": "off"' && expect 3 '[:len ([:deserialize from=json [/file/get cfm/meta/notify-b.dat contents]]->"act")] = 0' "Backup: Tick wieder ok, keine offenen Zustände" || bad "Backup: Entwarnung Tick fehlt"
expect 1 '[:len [/file/find where name="cfm/meta/notify-b.dat"]] = 0' "Primary: keine Zustandsdatei des Backups"
mgr ':global e2eG; /file/set [/file/find name="cfm/work/global.rsc"] contents=$e2eG' >/dev/null

step "14g. SFTP-User auf dem Backup, Ernstfall, Schlüssel erneuern (D67)"
fp() { r "$1" ":put [/user/ssh-keys/get [:pick [find where user=\"$2\"] 0] fingerprint]" | head -1; }
mirror | grep -q MIR=true && ok "Spiegel auf cm2 angestoßen" || bad "Spiegel auf cm2"
expect 3 '[:len [/user/find where name~"^cfmd-(cm1|sw1)\$" and group="cfm-dev" and comment~" k=" and disabled]] = 2 and [:len [/user/ssh-keys/find where user="cfmd-sw1"]] = 1 and [:len [/user/find where name="cfmd-cm2"]] = 0' "cm2: SFTP-User von cm1 und sw1 gesperrt, je ein Schlüssel, keiner für sich selbst"
[ "$(fp 3 cfmd-sw1)" = "$(fp 1 cfmd-sw1)" ] && ok "cm2: Schlüssel von sw1 wie auf dem Primary" || bad "cm2: Schlüssel von sw1 weicht ab"
# Ernstfall nach der Beförderung: $cfmDevUsersOn (Teil von $cfmPromoteManager) schaltet die User frei;
# sw1 erreicht cm1 per SFTP nicht mehr (eigene Verbindungen zu cm1:22 abgewiesen; der Push von cm1 und
# das Abholen des Status laufen als Verbindungen von cm1 weiter)
mgr ':global cfmExec; :local r [$cfmExec ip=192.168.10.3 cmd=("/system script run cfm-mgr; :global cfmDevUsersOn; :put [\$cfmDevUsersOn]")]; :put ($r->"output")' >/dev/null
expect 3 '[:len [/user/find where name~"^cfmd-(cm1|sw1|cm2)\$" and !disabled]] = 3' "cm2: \$cfmDevUsersOn schaltet die User frei und legt den eigenen an"
r 2 '/ip/firewall/filter/add chain=output protocol=tcp dst-address=192.168.10.2 dst-port=22 action=reject reject-with=tcp-reset comment=e2e-dr' >/dev/null
t0=$(stat sw1 t); mgr '$cfmPush host=sw1 force=yes' >/dev/null
for _ in $(seq 1 40); do [ "$(stat sw1 t)" != "$t0" ] && break; sleep 4; done
[ "$(stat sw1 mgr)" = 192.168.10.3 ] && [ "$(stat sw1 res)" = ok ] && ok "sw1 zieht vom Backup-Manager cm2 (res=ok)" || { bad "sw1 vom Backup: mgr=$(stat sw1 mgr) res=$(stat sw1 res)"; r 3 '/log/print where message~"login failure"' | tail -3; }
r 2 '/ip/firewall/filter/remove [find where comment=e2e-dr]' >/dev/null
expect 2 '[:len [/ip/firewall/filter/find where comment="e2e-dr"]] = 0' "sw1: Testregel entfernt"
# zurück zum unbeförderten Backup: eigenen User weg, der nächste Spiegel sperrt die übrigen wieder
r 3 '/user/remove [find where name="cfmd-cm2"]' >/dev/null
mirror >/dev/null
expect 3 '[:len [/user/find where name~"^cfmd-" and !disabled]] = 0 and [:len [/user/find where name="cfmd-cm2"]] = 0' "cm2: Spiegel sperrt die Geräte-User wieder"
# SFTP-Schlüssel eines Geräts erneuern
f0=$(fp 1 cfmd-sw1)
out=$(mgr '$cfmRekey host=sw1 sftp=yes')
echo "$out" | grep -q "Rekey SFTP sw1: neuer SFTP-/Host-Schlüssel aktiv" && ok "Rekey SFTP sw1" || { bad "Rekey SFTP sw1"; echo "$out" | tail -3; }
f1=$(fp 1 cfmd-sw1)
[ -n "$f1" ] && [ "$f0" != "$f1" ] && expect 1 '[:len [/user/ssh-keys/find where user="cfmd-sw1"]] = 1' "cm1: cfmd-sw1 hat genau den neuen Schlüssel" || bad "cfmd-sw1 unverändert"
expect 2 '[:len [/user/ssh-keys/private/find where user=cfm]] = 1 and [:len [/file/find where name~"^cfm-rk"]] = 0' "sw1: ein privater Schlüssel, keine Dateien übrig"
t0=$(stat sw1 t); mgr '$cfmPush host=sw1 force=yes' >/dev/null
for _ in $(seq 1 40); do [ "$(stat sw1 t)" != "$t0" ] && break; sleep 4; done
[ "$(stat sw1 t)" != "$t0" ] && [ "$(stat sw1 res)" = ok ] && [ "$(stat sw1 mgr)" = 192.168.10.2 ] && ok "sw1 zieht mit dem neuen Schlüssel vom Primary" || bad "sw1 nach Rekey SFTP: mgr=$(stat sw1 mgr) res=$(stat sw1 res)"
mirror >/dev/null
[ "$(fp 3 cfmd-sw1)" = "$f1" ] && expect 3 '[:len [/user/ssh-keys/find where user="cfmd-sw1"]] = 1' "cm2: neuer Schlüssel von sw1 nach dem Spiegel" || bad "cm2 hat den neuen Schlüssel von sw1 nicht"
# Manager-Schlüssel: ein aufgenommenes, aber unerreichbares Gerät bricht die Rotation ab
k2a=$(fp 2 cfm); n2a=$(r 2 ':put [:len [/user/ssh-keys/find where user=cfm]]' | head -1)
mgr ':global cfmVaultSet; $cfmVaultSet "mac.SERIAL-PH2" "x"; $cfmRegister name=ph2 serial=SERIAL-PH2 ip=192.168.10.97 role=switch ring=0' >/dev/null
out=$(mgr '$cfmRekey host=cm2 sftp=yes')
echo "$out" | grep -q "Rekey SFTP cm2: neuer Manager-Schlüssel nicht auf allen Geräten ( ph2 ) - abgebrochen" && ok "Rotation cm2 abgebrochen (ph2 unerreichbar)" || { bad "Abbruch der Rotation"; echo "$out" | tail -3; }
[ "$(r 2 ':put [:len [/user/ssh-keys/find where user=cfm]]' | head -1)" = "$n2a" ] && ok "sw1: Trust-Keys wie vorher ($n2a)" || bad "sw1: Trust-Keys nach dem Abbruch: $(r 2 ':put [:len [/user/ssh-keys/find where user=cfm]]' | head -1)"
mirror | grep -q MIR=true && ok "cm2 spiegelt nach dem Abbruch weiter (alter Schlüssel)" || bad "cm2 spiegelt nach dem Abbruch nicht"
mgr ':global cfmInvLoad; :global cfmInvSave; :local i [$cfmInvLoad]; :set ($i->"ph2"); $cfmInvSave $i; /ppp/secret/remove [find where name="cfm:mac.SERIAL-PH2"]' >/dev/null
# Backup-Manager cm2: zweiphasig
c0=$(fp 1 cfmd-cm2)
out=$(mgr '$cfmRekey host=cm2 sftp=yes')
echo "$out" | grep -q "Rekey SFTP cm2: Manager-Schlüssel auf 3 Geräten, alter entfernt" && echo "$out" | grep -q "Rekey SFTP cm2: neuer SFTP-/Host-Schlüssel aktiv" && ok "Rekey SFTP cm2 (Manager, zweiphasig)" || { bad "Rekey SFTP cm2"; echo "$out" | tail -4; }
c1=$(fp 1 cfmd-cm2)
[ -n "$c1" ] && [ "$c0" != "$c1" ] && ok "cm1: cfmd-cm2 mit neuem Schlüssel" || bad "cfmd-cm2 unverändert"
expect 2 '[:len [/user/ssh-keys/find where user=cfm]] = 2 and [:len [/user/ssh-keys/find where user=cfm and fingerprint="'"$c1"'"]] = 1' "sw1: Trust-Keys cm1 + neuer cm2, alter weg"
expect 3 '[:len [/user/ssh-keys/private/find where user=cfm]] = 1 and [:len [/file/find where name~"^cfm-rk"]] = 0' "cm2: ein privater Schlüssel für cfm, keine Schlüsseldateien"
mirror | grep -q MIR=true && ok "cm2 spiegelt mit dem neuen Schlüssel" || bad "cm2 spiegelt nach der Rotation nicht"
t0=$(stat cm2 t); mgr '$cfmPush host=cm2 force=yes' >/dev/null
# fällt der Lauf in den eigenen Spiegel-Sync, dauert er gut 3 min (D58)
for _ in $(seq 1 75); do [ "$(stat cm2 t)" != "$t0" ] && break; sleep 4; done
[ "$(stat cm2 t)" != "$t0" ] && [ "$(stat cm2 res)" = ok ] && ok "cm2: Agent zieht mit dem neuen Schlüssel" || bad "cm2 nach Rekey SFTP: $(stat cm2 res)"
# Primary cm1 selbst: danach muss jeder Push mit dem neuen Schlüssel gehen (Schritt 15: auch als netadmin)
p0=$(fp 1 cfmd-cm1)
out=$(mgr '$cfmBootstrap; $cfmRekey host=cm1 sftp=yes')
echo "$out" | grep -q "Rekey SFTP cm1: Manager-Schlüssel auf 3 Geräten, alter entfernt" && ok "Rekey SFTP cm1 (Primary)" || { bad "Rekey SFTP cm1"; echo "$out" | tail -4; }
p1=$(fp 1 cfmd-cm1)
[ -n "$p1" ] && [ "$p0" != "$p1" ] && expect 2 '[:len [/user/ssh-keys/find where user=cfm]] = 2 and [:len [/user/ssh-keys/find where user=cfm and fingerprint="'"$p1"'"]] = 1 and [:len [/user/ssh-keys/find where user=cfm and fingerprint="'"$p0"'"]] = 0' "sw1: neuer Schlüssel von cm1, alter weg" || bad "cfmd-cm1 unverändert"
expect 1 '[:len [/user/ssh-keys/private/find where user=netadmin]] = 1 and [:len [/user/ssh-keys/private/find where user=cfm]] = 1' "cm1: netadmin und cfm je ein privater Schlüssel"
expect 1 '[:typeof [:find [/file/get cfm/cfm-bootstrap.rsc contents] [:pick [/file/get cfm/meta/keys/cm1.pem contents] 27 70]]] = "num"' "cm1: Bootstrap-Datei mit dem neuen Schlüssel"
for h in sw1 cm1; do
  t0=$(stat $h t); mgr "\$cfmPush host=$h force=yes" >/dev/null
  for _ in $(seq 1 40); do [ "$(stat $h t)" != "$t0" ] && break; sleep 4; done
  [ "$(stat $h t)" != "$t0" ] && [ "$(stat $h res)" = ok ] && ok "$h: Push und Apply nach der Rotation von cm1" || bad "$h nach Rekey cm1: $(stat $h res)"
done
mirror | grep -q MIR=true && ok "cm2 spiegelt nach der Rotation von cm1" || bad "cm2 spiegelt nach der Rotation von cm1 nicht"
kill $npid 2>/dev/null

step "14h. Manifest-Regeln je Version (D70)"
# Eine Regel, die nur die neue Version kennt: Ring 0 bekommt sie mit dem Release, Ring 2 erst mit dem
# Aufstieg - auch wenn $cfmPromote in einer neuen Sitzung mit dem installierten (älteren) Code läuft
mfhas() { # mfhas <host> <text>: true/false, ob das Manifest des Hosts den Text enthält
  mgr ':local r "kein Manifest"; :foreach f in=[/file/find where name~"^cfm/live/m/.*\\.mf\$"] do={ :local c [/file/get $f contents]; :local j [:deserialize from=json [:pick $c 0 [:find $c "\n# mac="]]]; :if (($j->"name") = "'"$1"'") do={ :set r ([:typeof [:find $c "'"$2"'"]] = "num") } }; :put ("MF=" . $r)' | sed -n 's/^MF=//p' | head -1; }
sed 's|^  :return \$want$|  :set ($want->[:len $want]) ({"e2e-mark.txt";0;0})\n  :return $want|' "$ROOT/cfm/work/lib/mgr-mf.rsc" > "$LAB/mgr-mf-e2e.rsc"
echo "D70" > "$LAB/e2e-mark.txt"
printf 'put %s cfm/work/lib/mgr-mf.rsc\nput %s cfm/work/e2e-mark.txt\n' "$LAB/mgr-mf-e2e.rsc" "$LAB/e2e-mark.txt" | put 1
rv=$(mgr '$cfmRelease msg=" e2e D70"' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
[ -n "$rv" ] && ok "Release v$rv mit einer Regel nur in dieser Version" || bad "Release mit neuer Regel"
a=$(mfhas sw1 e2e-mark); [ "$a" = true ] && ok "sw1 (Ring 0): Manifest nach den Regeln von v$rv" || bad "sw1 (Ring 0): Regel der neuen Version fehlt ($a)"
a=$(mfhas cm1 e2e-mark); [ "$a" = false ] && ok "cm1 (Ring 2): Manifest nach den Regeln seiner Version" || bad "cm1 (Ring 2): Regel vor dem Aufstieg ($a)"
expect 1 '[:typeof [:find [/system/script/get cfm-mgr-mf source] "e2e-mark"]] = "nil"' "cm1: installierte Regeln noch ohne die neue"
mgr '$cfmPromote ring=1' >/dev/null; mgr '$cfmPromote ring=2' >/dev/null
a=$(mfhas cm1 e2e-mark); [ "$a" = true ] && ok "cm1 nach \$cfmPromote aus neuer Sitzung: Regel aus v$rv (nicht aus dem installierten Code)" || bad "cm1 nach \$cfmPromote: Regel fehlt ($a)"
a=$(mfhas sw1 e2e-mark); [ "$a" = true ] && ok "sw1: Regel bleibt beim Neubau durch \$cfmPromote" || bad "sw1 nach \$cfmPromote: Regel fehlt ($a)"
agentwait 2 "$rv" sw1 && expect 2 '[:len [/file/find where name="cfm/dl/e2e-mark.txt"]] = 1' "sw1: Datei der neuen Regel geladen" || bad "sw1 Apply v$rv: $(stat sw1 res)"
agentwait 1 "$rv" cm1 60 && expect 1 '[:typeof [:find [/system/script/get cfm-mgr-mf source] "e2e-mark"]] = "num"' "cm1: nach dem Apply die Regeln von v$rv installiert" || bad "cm1 Apply v$rv: $(stat cm1 res)"
echo "put $ROOT/cfm/work/lib/mgr-mf.rsc cfm/work/lib/mgr-mf.rsc" | put 1
rv=$(mgr '/file/remove cfm/work/e2e-mark.txt; $cfmRelease all=yes msg=" e2e D70 zurück"' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 2 "$rv" sw1 && expect 2 '[:len [/file/find where name="cfm/dl/e2e-mark.txt"]] = 0' "sw1: Datei nach dem Rückbau der Regel entfernt (D69)" || bad "sw1 Apply v$rv: $(stat sw1 res)"
agentwait 1 "$rv" cm1 60 && [ "$(stat cm1 res)" = ok ] && ok "cm1 wieder auf den Regeln aus dem Seed (v$rv)" || bad "cm1 Apply v$rv: $(stat cm1 res)"

step "14i. Apply auf dem Manager parallel zu Manager-Befehlen (Sperre cfmApplyBusy)"
# Ohne Sperre importierte $cfmLoadData (fast jeder Manager-Befehl, der Tick) mitten im Apply von cm1
# global.rsc neu: cm1 verlor die Werte seines Hostfiles (adminUser keep, mgmtExtra), Labor 2026-10-11
for round in 1 2; do
  mgr ':global cfmAU; :set cfmAU "x"; $cfmPush host=cm1 force=yes' >/dev/null
  for i in $(seq 1 12); do mgr ':global cfmLoadData; $cfmLoadData' >/dev/null; done
  a=""; for _ in $(seq 1 30); do a=$(mgr ':global cfmAU; :put ("AU=" . $cfmAU)' | grep -o 'AU=.*'); [ "$a" != "AU=x" ] && break; sleep 3; done
  [ "$a" = "AU=keep" ] && ok "cm1: Hostfile gilt im ganzen Apply trotz paralleler Manager-Befehle (Runde $round)" || { bad "cm1: Apply mit parallelem \$cfmLoadData: '$a'"; break; }
done

step "14j. Manager-Befehl läuft schon, dann startet der Apply auf dem Manager (Sperre cfmMgrData)"
# Gegenrichtung zu 14i: $cfmCheck und $cfmShow importieren die Hostfiles aller Geräte in cfmHost, den
# ein laufender Apply liest. Ohne Sperre bekäme cm1 z.B. die Ports von sw1 (ether3 zu cm2 fiele aus
# der Bridge) oder stp="none" von cm2
brz() { r 1 ':local b [/interface/bridge/find where name=bridge]; :put ("P=" . [:len [/interface/bridge/port/find where !dynamic]] . " M=" . [/interface/bridge/get $b protocol-mode] . " I=" . [/interface/bridge/get $b igmp-snooping])' | grep -o 'P=.*'; }
b0=$(brz)
r 1 ':global cfmT14j; :set cfmT14j "busy"; :execute script="/system script run cfm-mgr; :global cfmCheck; :global cfmShow; :global cfmT14j; :for i from=1 to=6 do={ :local x [\$cfmCheck]; \$cfmShow host=sw1; \$cfmShow host=cm2 }; :set cfmT14j \"fertig\""' >/dev/null
sleep 4
mgr ':global cfmAU; :set cfmAU "x"; $cfmPush host=cm1 force=yes' >/dev/null
a=""; for _ in $(seq 1 60); do a=$(mgr ':global cfmAU; :put ("AU=" . $cfmAU)' | grep -o 'AU=.*'); [ "$a" != "AU=x" ] && break; sleep 3; done
for _ in $(seq 1 60); do [ "$(r 1 ':put [:len [/system/script/job/find where script="cfm-agent"]]' | tail -1)" = 0 ] && break; sleep 2; done
for _ in $(seq 1 90); do r 1 ':global cfmT14j; :put $cfmT14j' | grep -q fertig && break; sleep 2; done
b1=$(brz)
[ -n "$b0" ] && [ "$b0" = "$b1" ] && [ "$a" = "AU=keep" ] && [ "$(stat cm1 res)" = ok ] \
  && ok "cm1: Apply während \$cfmCheck/\$cfmShow mit eigenem Hostfile ($b1)" \
  || { bad "cm1: Apply während \$cfmCheck/\$cfmShow: vorher '$b0', nachher '$b1', $a, res $(stat cm1 res)"; diag step14j; }
w=$(r 1 ':foreach i in=[/log/find where message~"^cfm: Apply wartete"] do={ :put [/log/get $i message] }' | tail -1)
[ -n "$w" ] && echo "    ($w)" || echo "    (Apply fiel in eine Lücke zwischen zwei Befehlen, dort ohne Wartezeit)"

step "15. Werks-User admin abschalten (zuletzt: danach kein admin-SSH mehr auf sw1)"
# Antwort mit Markierung, weil die ssh-exec-Ausgabe mit Zeilenumbruch endet (tail -1 wäre leer)
chk() { mgr ':global cfmExec; :local r [$cfmExec ip=192.168.10.21 cmd="'"$1"'"]; :put ("RES=" . ($r->"output"))' | sed -n 's/^RES=//p' | head -1; }
# auf genau diese Version warten (ein früheres Release mit all=yes kann sw1 kurz vorher erreichen)
rv=$(mgr ':local f [/file/find name="cfm/work/hosts/sw1.rsc"]; :local c [/file/get $f contents]; :local p [:find $c "\"keep\""]; /file/set $f contents=([:pick $c 0 $p] . "\"disable\"" . [:pick $c ($p + 6) [:len $c]]); $cfmRelease msg=" admin aus auf sw1"' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 2 "$rv" sw1 && [ "$(stat sw1 res)" = ok ] && ok "sw1 hat v$rv angewendet" || bad "sw1 Apply v$rv: $(stat sw1 res)"
a=$(chk ':put [/user/get [find name=admin] disabled]')
if [ "$a" = true ]; then ok "sw1: admin deaktiviert"; else bad "sw1: admin noch aktiv (Antwort: '$a')"; diag step15; fi
a=$(chk ':put [/user/get [find name=netadmin] disabled]')
[ "$a" = false ] && ok "sw1: eigener User netadmin aktiv" || bad "sw1: netadmin nicht aktiv (Antwort: '$a')"
printf '#!/bin/sh\necho "Lab-Passw0rd!"\n' > "$LAB/askpass-netadmin"; chmod +x "$LAB/askpass-netadmin"
out=$(SSH_ASKPASS="$LAB/askpass-netadmin" SSH_ASKPASS_REQUIRE=force ssh -p $((LABPORT+10)) "${O[@]}" -o PubkeyAuthentication=no netadmin@127.0.0.1 '/system script run cfm-mgr; $cfmPush host=sw1' 2>&1 | tr -d '\r')
echo "$out" | grep -q "Push -> sw1" && ! echo "$out" | grep -q FEHLER && ok "cm1: Manager-Befehle unter eigenem User (netadmin)" || bad "netadmin: $(echo "$out" | tail -1)"

echo; echo "Ergebnis: $pass ok, $fail fehlgeschlagen"; [ $fail -eq 0 ]
