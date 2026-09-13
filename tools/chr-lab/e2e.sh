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
expect 1 '[:len [/system/script/find where name~"^cfm-mgr-" and comment~"^cfm:sys:mgr-"]] = 7' "cm1: 7 Manager-Module als Skripte (von der Rolle übernommen)"
expect 1 '[:len [/ip/firewall/filter/find where comment~"^cfm:fwb" and dst-port="67"]] = 1' "cm1: minimale Firewall erlaubt DHCP im Onboarding-VLAN"
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
expect 2 '[:len [/ip/firewall/filter/find where comment~"^cfm:fwb"]] = 8 and [/ip/firewall/filter/get [find where comment="cfm:fwb:07"] action] = "drop"' "sw1: minimale Firewall IPv4 (8 Regeln, zuletzt drop)"
expect 2 '[:len [/ipv6/firewall/filter/find where comment~"^cfm:fw6"]] = 8' "sw1: minimale Firewall IPv6 (8 Regeln)"
expect 2 '[/ip/neighbor/discovery-settings/get discover-interface-list] = "DISC" and [:len [/interface/list/member/find where list="DISC" and interface="ether2"]] = 1' "sw1: Nachbarsuche auf den Bridge-Ports (Liste DISC)"

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

step "6. Probelauf (\$cfmPlan): zeigt Änderungen, wendet nichts an"
mgr ':global e2eV [/file/get [/file/find name="cfm/work/vlans.rsc"] contents]; /file/set [/file/find name="cfm/work/vlans.rsc"] contents=($e2eV . ":set (\$cfmVlans->\"99\") {\"name\"=\"PLAN\";\"zone\"=\"lan\"}\n")' >/dev/null
v0=$(stat sw1 v)
out=$(mgr '$cfmPlan host=sw1')
echo "$out" | grep -q "bv:99" && ok "Plan zeigt das neue Bridge-VLAN 99" || { bad "Plan ohne bv:99"; echo "$out" | tail -5; }
echo "$out" | grep -q "# Plan sw1" && ok "Plan-Zusammenfassung vom Gerät" || bad "keine Plan-Zusammenfassung"
expect 2 '[:len [/interface/bridge/vlan/find where comment="cfm:bv:99"]] = 0' "sw1: Probelauf hat nichts angewendet"
[ "$(stat sw1 v)" = "$v0" ] && ok "sw1: Version unverändert (v$v0)" || bad "sw1: Version nach dem Probelauf geändert"
mgr ':global e2eV; /file/set [/file/find name="cfm/work/vlans.rsc"] contents=$e2eV' >/dev/null

step "7. Kaputte Version -> Prüfung stoppt, mit force: Rollback + bad"
out=$(mgr ':local f [/file/find name="cfm/work/hosts/sw1.rsc"]; /file/set $f contents=":global cfmHost {\"ports\"={\"ether2\"=\"gibtsnicht\"}}"; :global cfmRelease; $cfmRelease msg=" kaputt"')
echo "$out" | grep -q "unbekanntes Port-Profil gibtsnicht" && ok "inhaltliche Prüfung stoppt das Release" || { bad "Prüfung hat nicht gestoppt"; echo "$out" | tail -3; }
mgr '$cfmRelease msg=" kaputt" force=yes' >/dev/null
for _ in $(seq 1 60); do [ "$(stat sw1 bad)" = 3 ] && break; sleep 4; done
if [ "$(stat sw1 bad)" = 3 ]; then ok "v3 als bad gemeldet ($(stat sw1 res | cut -c1-60))"; else bad "Rollback/bad: $(stat sw1 res)"; diag step7; fi
waitssh 2; sleep 20
expect 2 '[:len [/ip/address/find where address="192.168.10.21/24"]] = 1' "sw1 nach Rollback erreichbar konfiguriert"
mgr '$cfmRollback ver=2 all=yes' >/dev/null

step "8. Backup-Manager cm2"
echo "put $LAB/bs.rsc cfm-bootstrap.rsc" | put 3
sed -e 's|^:local ip ".*"|:local ip "192.168.10.3/24"|' -e 's/^:local uplink "ether1"/:local uplink "ether2"/' "$LAB/bs.rsc" > "$LAB/bs-cm2.rsc"
echo "put $LAB/bs-cm2.rsc cfm-bootstrap.rsc" | put 3
r 3 '/import cfm-bootstrap.rsc verbose=no' >/dev/null
mgr '$cfmEnroll name=cm2 ip=192.168.10.3 role=manager-backup ring=0' | grep -q Enrolled && ok "Enroll cm2" || bad "Enroll cm2"
agentwait 3 4 cm2 && ok "cm2 hat v4 angewendet" || bad "cm2 Apply"
expect 3 '[:tostr [/interface/wifi/capsman/get enabled]] ~ "no|false"' "cm2: CAPsMAN passiv"
expect 1 '[:tostr [/interface/wifi/capsman/get enabled]] ~ "yes|true"' "cm1: CAPsMAN aktiv"
expect 1 '[:len [/interface/wifi/provisioning/find where comment~"^cfm:wprov"]] >= 2' "cm1: Provisioning-Regeln gerendert"

step "9. Rolle router auf sw1 (über den echten Agent-Pfad)"
mgr ':local f [/file/find name="cfm/meta/inventory.rsc"]; :local c [/file/get $f contents]; :local p [:find $c "\"role\"=\"switch\""]; /file/set $f contents=([:pick $c 0 $p] . "\"role\"=\"switch,router\"" . [:pick $c ($p + 15) [:len $c]]); :global cfmManifests; $cfmManifests' >/dev/null
mgr '$cfmPush host=sw1' >/dev/null
for _ in $(seq 1 60); do [ "$(stat sw1 role)" = "switch,router" ] && [ "$(stat sw1 res)" = ok ] && break; sleep 4; done
[ "$(stat sw1 role)" = "switch,router" ] && [ "$(stat sw1 res)" = ok ] && ok "sw1 als switch,router angewendet" || bad "Router-Apply: $(stat sw1 role) $(stat sw1 res)"
expect 2 '[:len [/ip/firewall/filter/find where comment~"^cfm:fw"]] > 15' "sw1: Zonen-Firewall-Block"
expect 2 '[:len [/interface/vrrp/find where comment~"^cfm:vrrp"]] >= 4' "sw1: VRRP je VLAN"
expect 2 '[:len [/ip/dhcp-server/find where comment~"^cfm:dhcp"]] = 2' "sw1: DHCP für IoT + Gast"
expect 2 '[:len [/ip/firewall/filter/find where comment~"^cfm:fwb"]] = 0' "sw1: minimale Firewall durch Router-Firewall ersetzt"
t0=$(stat sw1 t); mgr '$cfmPush host=sw1 force=yes' >/dev/null
for _ in $(seq 1 60); do [ "$(stat sw1 t)" != "$t0" ] && break; sleep 4; done
stat sw1 stats | grep -q "add=0;rem=0;set=0;skip=0" && ok "Router-Rolle idempotent" || bad "Router idempotent: $(stat sw1 stats)"

step "10. Backup-Spiegel & Vault-Backup"
for _ in $(seq 1 50); do r 3 ':put ([:len [/file/find where name="cfm/meta/rings.dat"]] + [:len [/file/find where name="cfm/archive/v4/index.dat"]])' | grep -qx 2 && break; sleep 8; done
expect 3 '[:len [/file/find where name="cfm/archive/v4/lib/agent.rsc"]] = 1' "cm2: Archiv v4 gespiegelt"
expect 3 '[:len [/file/find where name="cfm/meta/rings.dat"]] = 1' "cm2: Ringe gespiegelt"
expect 1 '[:len [/file/find where name~"^cfm/vault/.*-vault.bak"]] = 1' "cm1: verschlüsseltes Vault-Backup (.bak)"

step "11. Archiv aufräumen"
out=$(mgr ':global cfmArchivePrune; :put ("AP=" . [$cfmArchivePrune keep=1])')
echo "$out" | grep -q "AP=2" && ok "2 alte Versionen gelöscht" || bad "Archiv: $(echo "$out" | tail -1)"
expect 1 '[:len [/file/find where name~"^cfm/archive/v[12](/|\$)"]] = 0' "v1 und v2 samt Verzeichnis entfernt"
expect 1 '[:len [/file/find where name="cfm/archive/v3/index.dat"]] = 1' "v3 bleibt (sw1 meldet sie als bad)"
expect 1 '[:len [/file/find where name="cfm/archive/v4/index.dat"]] = 1' "v4 bleibt (von den Ringen genutzt)"

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
# (a) sw1: Wartungsfenster in einer Stunde -> Paket wird sofort geladen, Neustart geplant
now=$(r 1 ':put ([/system/clock/get date] . " " . [/system/clock/get time])' | head -1)
at=$(date -d "@$(( $(date -d "$now" +%s) + 3600 ))" '+%Y-%m-%d %H:%M')
out=$(mgr '$cfmUpgrade ver=7.24.1 host=sw1 at="'"$at"'"')
echo "$out" | grep -q "Auftrag sw1: downgrade auf 7.24.1 (am $at)" && ok "Auftrag sw1 für das Wartungsfenster $at" || { bad "Auftrag sw1"; echo "$out" | tail -3; }
expect 1 '[/file/get [find where name="cfm/pkg/7.24.1/routeros-7.24.1.npk"] size] > 1000000' "cm1: Paket 7.24.1 (x86) vor dem Rollout geladen"
# SFTP zwischen CHRs ist langsam (~100 KB/s): das 20-MB-Paket braucht einige Minuten
for _ in $(seq 1 100); do r 2 ':put [:len [/system/scheduler/find where name="cfm-upgrade"]]' | grep -qx 1 && break; sleep 6; done
expect 2 '[:tostr [/system/scheduler/get [find where name="cfm-upgrade"] start-time]] = "'"${at#* }"':00" and [/file/get [find where name="routeros-7.24.1.npk"] size] > 1000000' "sw1: Paket geladen, Neustart für $at geplant"
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
r 1 '/file/add name="cfm/pkg/7.0.0/routeros-7.0.0.npk" contents="x"' >/dev/null
mgr '$cfmPkgPrune' >/dev/null
expect 1 '[:len [/file/find where name~"^cfm/pkg/7.0.0"]] = 0 and [:len [/file/find where name="cfm/pkg/7.24.1/routeros-7.24.1.npk"]] = 1' "Paketversion ohne Einsatz gelöscht, 7.24.1 bleibt"

step "14. Verkabelung (LLDP, Netzplan) und WLAN (PPSK, Kanäle)"
# alle Geräte melden ihre Nachbarn mit dem nächsten Lauf
for h in sw1 cm2 cm1; do mgr "\$cfmPush host=$h force=yes" >/dev/null; done
for _ in $(seq 1 40); do [ -n "$(stat sw1 nb)" ] && [ -n "$(stat cm2 nb)" ] && [ -n "$(stat cm1 nb)" ] && break; sleep 5; done
out=$(mgr '$cfmLinks')
echo "$out" | grep -qE "^(cm1 +ether2 +sw1 +ether2|sw1 +ether2 +cm1 +ether2) +ok" && ok "Link cm1:ether2 - sw1:ether2 (beide Seiten melden)" || { bad "Link cm1-sw1 fehlt"; echo "$out" | tail -8; }
echo "$out" | grep -qE "^(cm1 +ether3 +cm2 +ether2|cm2 +ether2 +cm1 +ether3) +ok" && ok "Link cm1:ether3 - cm2:ether2 (beide Seiten melden)" || bad "Link cm1-cm2 fehlt"
expect 1 '[/file/get [find where name="cfm/state/netzplan.md"] contents] ~ "graph LR"' "netzplan.md mit Mermaid-Diagramm"
mgr '$cfmLinks accept=yes' | grep -q "Baseline gespeichert: 2 Links" && ok "Baseline mit 2 Links eingefroren" || bad "Baseline"
mgr ':global e2eH [/file/get [/file/find name="cfm/work/hosts/sw1.rsc"] contents]; /file/set [/file/find name="cfm/work/hosts/sw1.rsc"] contents=($e2eH . ":set (\$cfmHost->\"links\") {\"ether2\"=\"cm1:ether3\"}\n")' >/dev/null
out=$(mgr '$cfmLinks export=yes')
echo "$out" | grep -q "sw1 ether2: erwartet cm1:ether3, gefunden cm1:ether2" && ok "Hostfile-Angabe links wird geprüft" || { bad "Erwartung nicht geprüft"; echo "$out" | tail -4; }
expect 1 '[:len [/file/find where name="cfm/state/netzplan.dot"]] = 1 and [/file/get [find where name="cfm/state/netzplan.csv"] contents] ~ "geraet_a;port_a"' "Export: netzplan.dot und netzplan.csv"
mgr ':global e2eH; /file/set [/file/find name="cfm/work/hosts/sw1.rsc"] contents=$e2eH' >/dev/null
mgr '$cfmChannels' | grep -q "keine Funkdaten" && ok "Kanalbericht (Labor ohne Radios)" || bad "Kanalbericht"
expect 1 '[:tostr [/interface/wifi/channel/get [find name="cfm-5g"] reselect-time]] = "03:00:00" and [/interface/wifi/channel/get [find name="cfm-5g"] skip-dfs-channels] = "10min-cac"' "cm1: Kanalprofil 5 GHz mit nächtlicher Neuwahl, ohne DFS-Wartezeit"
# PPSK: zweite Passphrase auf der IoT-SSID landet in VLAN 40
mgr ':global e2eW [/file/get [/file/find name="cfm/work/wifi.rsc"] contents]; /file/set [/file/find name="cfm/work/wifi.rsc"] contents=($e2eW . ":set (\$cfmWifi->\"ppsk\") {\"iot\"={\"gast\"={\"vlan\"=40;\"isolation\"=\"yes\"}}}\n")' >/dev/null
rv=$(mgr '$cfmRelease msg=" PPSK" all=yes' | grep -o 'Release v[0-9]*' | tr -dc 0-9)
agentwait 1 "$rv" cm1 && ok "cm1 hat v$rv (PPSK) angewendet" || { bad "cm1 Apply v$rv"; r 1 '/log/print where message~"^cfm: "' | tail -6; }
expect 1 '[:len [/interface/wifi/security/multi-passphrase/find where comment="cfm:mpp:iot.gast" and vlan-id=40]] = 1 and [/interface/wifi/security/get [find name="cfm-iot"] multi-passphrase-group] = "cfm-iot"' "cm1: Multi-Passphrase für VLAN 40 an der IoT-SSID"
mgr '$cfmSecret key=ppsk.iot.gast value="PPSK-Gast-2026"; :global cfmSecretPush; $cfmSecretPush host=cm1' >/dev/null
expect 1 '[/interface/wifi/security/multi-passphrase/get [find comment="cfm:mpp:iot.gast"] passphrase] = "PPSK-Gast-2026"' "PPSK-Passphrase per Secret-Push gesetzt"
out=$(mgr ':global cfmCheck; /file/set [/file/find name="cfm/work/wifi.rsc"] contents=([/file/get [/file/find name="cfm/work/wifi.rsc"] contents] . ":set (\$cfmWifi->\"ppsk\"->\"main\") {\"x\"={\"vlan\"=20}}\n"); :foreach e in=([$cfmCheck]->"err") do={ :put $e }')
echo "$out" | grep -q "PPSK auf SSID main braucht sec=wpa2-psk" && ok "Prüfung: PPSK nur mit WPA2-PSK" || { bad "PPSK/WPA3 nicht erkannt"; echo "$out" | tail -3; }
mgr ':global e2eW; /file/set [/file/find name="cfm/work/wifi.rsc"] contents=$e2eW' >/dev/null

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
out=$(SSH_ASKPASS="$LAB/askpass-netadmin" SSH_ASKPASS_REQUIRE=force ssh -p 2210 "${O[@]}" -o PubkeyAuthentication=no netadmin@127.0.0.1 '/system script run cfm-mgr; $cfmPush host=sw1' 2>&1 | tr -d '\r')
echo "$out" | grep -q "Push -> sw1" && ! echo "$out" | grep -q FEHLER && ok "cm1: Manager-Befehle unter eigenem User (netadmin)" || bad "netadmin: $(echo "$out" | tail -1)"

echo; echo "Ergebnis: $pass ok, $fail fehlgeschlagen"; [ $fail -eq 0 ]
