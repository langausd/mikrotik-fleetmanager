# ============================================================
# Rolle base – gilt für ALLE Geräte, wird immer zuerst angewendet
#  Identität, Bridge + VLAN-Filtering, Port-Profile, MGMT-Zugang,
#  Dienste-Härtung, Zeit/Logging, Admin-Benutzer, cfm-Agent.
# ============================================================
:global cfmG; :global cfmVlans; :global cfmHost; :global cfmMf; :global cfmDl
:global cfmEnsure; :global cfmSet; :global cfmProfile; :global cfmNet; :global cfmKeys
:global cfmHas; :global cfmLog; :global cfmBlock; :global cfmDry

:local br "bridge"
:local mv [:tostr ($cfmG->"mgmtVlan")]
:local mif ("vlan" . $mv)
:local isRouter [$cfmHas "router"]
:local isMgr ([$cfmHas "manager"] or [$cfmHas "manager-backup"])

# --- Identität ---
$cfmSet m="/system/identity" p=({"name"=($cfmMf->"name")})

# --- Bridge (VLAN-Filtering wird erst am Ende aktiviert) ---
:local stp [:tostr ($cfmHost->"stpPrio")]
:if ([:len $stp] = 0) do={ :set stp "0x8000" }
$cfmEnsure m="/interface/bridge" k="br" n=({"name"=$br}) p=({"name"=$br;"protocol-mode"="rstp";"priority"=$stp}) a=({"vlan-filtering"="no"})

# --- Ports nach Profil (portDefault gilt für alle nicht genannten Ethernet-Ports) ---
:local ports ({})
:local def [:tostr ($cfmHost->"portDefault")]
:if ([:len $def] > 0) do={
  :foreach i in=[/interface/ethernet/find] do={ :set ($ports->[/interface/ethernet/get $i name]) $def }
}
:if ([:typeof ($cfmHost->"ports")] = "array") do={
  :foreach p,spec in=($cfmHost->"ports") do={ :set ($ports->$p) $spec }
}
:local tagged ({}); :local untagged ({})
# Nachbarsuche (LLDP/MNDP/CDP) auf allen Bridge-Ports + MGMT-VLAN: Grundlage für $cfmLinks (D33)
$cfmEnsure m="/interface/list" k="il:DISC" n=({"name"="DISC"}) p=({"name"="DISC"})
:foreach p,spec in=$ports do={
  :local pr [$cfmProfile $spec]
  :if ($pr->"bridge") do={
    $cfmEnsure m="/interface/list/member" k=("ilm:DISC:" . $p) n=({"list"="DISC";"interface"=$p}) p=({"list"="DISC";"interface"=$p})
    :local pv 1
    :if ([:len ($pr->"untag")] > 0) do={ :set pv [:tonum ($pr->"untag")] }
    :local bpdu "no"
    :if (($pr->"edge") = "yes") do={ :set bpdu "yes" }
    $cfmEnsure m="/interface/bridge/port" k=("bp:" . $p) n=({"interface"=$p}) p=({"bridge"=$br;"interface"=$p;"pvid"=$pv;"frame-types"=($pr->"frame");"ingress-filtering"="yes";"edge"=($pr->"edge");"bpdu-guard"=$bpdu})
    :foreach vid,m in=($pr->"tag") do={
      :if ($m = 1) do={
        :if ([:typeof ($tagged->$vid)] != "array") do={ :set ($tagged->$vid) ({}) }
        :set ($tagged->$vid->$p) 1
      }
    }
    :local u ($pr->"untag")
    :if ([:len $u] > 0) do={
      :if ([:typeof ($untagged->$u)] != "array") do={ :set ($untagged->$u) ({}) }
      :set ($untagged->$u->$p) 1
    }
  } else={
    # Port ausdrücklich NICHT in der Bridge (wan/off): fremde Einträge entfernen
    :foreach bid in=[/interface/bridge/port/find where interface=$p and !dynamic] do={
      :if (!([:tostr [/interface/bridge/port/get $bid comment]] ~ "^cfm")) do={
        :if ($cfmDry != true) do={ /interface/bridge/port/remove $bid }
        $cfmLog ("Port " . $p . " aus Bridge genommen (Profil " . $spec . ")")
      }
    }
  }
  :if ([:len [/interface/ethernet/find where name=$p]] > 0) do={
    :local dis "no"
    :if ($pr->"disabled") do={ :set dis "yes" }
    $cfmSet m="/interface/ethernet" n=({"name"=$p}) p=({"disabled"=$dis})
  }
}

# --- Bridge-VLAN-Tabelle: aus Profilen abgeleitet ---
:foreach vid,v in=$cfmVlans do={
  :local tg ({})
  :if ([:typeof ($tagged->$vid)] = "array") do={ :set tg ($tagged->$vid) }
  :if ($vid = $mv or ($isRouter and [:tostr ($v->"l3")] != "no") or ($isMgr and [:tostr ($v->"onboard")] = "yes")) do={ :set ($tg->$br) 1 }
  :local ut ({})
  :if ([:typeof ($untagged->$vid)] = "array") do={ :set ut ($untagged->$vid) }
  :if (([:len $tg] + [:len $ut]) > 0) do={
    $cfmEnsure m="/interface/bridge/vlan" k=("bv:" . $vid) n=({"bridge"=$br;"vlan-ids"=[:tonum $vid]}) p=({"bridge"=$br;"vlan-ids"=[:tonum $vid];"tagged"=[$cfmKeys $tg];"untagged"=[$cfmKeys $ut]})
  }
}

# --- Management: VLAN-Interface, IP, Route, DNS ---
:local mn [$cfmNet $mv]
$cfmEnsure m="/interface/vlan" k=("vlan:" . $mv) n=({"name"=$mif}) p=({"name"=$mif;"interface"=$br;"vlan-id"=[:tonum $mv]}) x=($cfmVlans->$mv->"name")
$cfmEnsure m="/ip/address" k="ip:mgmt" n=({"interface"=$mif}) p=({"address"=(($cfmMf->"ip") . "/" . ($mn->"pfx"));"interface"=$mif})
:if (!$isRouter) do={
  $cfmEnsure m="/ip/route" k="rt:default" n=({"dst-address"="0.0.0.0/0";"gateway"=[:tostr ($mn->"gw")]}) p=({"dst-address"="0.0.0.0/0";"gateway"=[:tostr ($mn->"gw")]})
  $cfmSet m="/ip/dns" p=({"servers"=($cfmG->"dns")})
  $cfmSet m="/system/ntp/client" p=({"enabled"="yes";"servers"=($cfmG->"ntp")})
}
$cfmEnsure m="/interface/list" k="il:MGMT" n=({"name"="MGMT"}) p=({"name"="MGMT"})
$cfmEnsure m="/interface/list/member" k="ilm:MGMT" n=({"list"="MGMT";"interface"=$mif}) p=({"list"="MGMT";"interface"=$mif})
$cfmEnsure m="/interface/list/member" k="ilm:DISC:mgmt" n=({"list"="DISC";"interface"=$mif}) p=({"list"="DISC";"interface"=$mif})
$cfmSet m="/ip/neighbor/discovery-settings" p=({"discover-interface-list"="DISC"})
$cfmSet m="/tool/mac-server" p=({"allowed-interface-list"="none"})
$cfmSet m="/tool/mac-server/mac-winbox" p=({"allowed-interface-list"="MGMT"})

# --- IP-Services: nur die in global.rsc genannten, nur aus Management-Netzen ---
:local an ({})
:foreach vid,v in=$cfmVlans do={
  :if ((("," . ($cfmG->"mgmtAccess") . ",") ~ ("," . ($v->"zone") . ","))) do={
    :local nn [$cfmNet $vid]
    :if ([:len ($nn->"net")] > 0) do={ :set ($an->($nn->"net")) 1 }
  }
}
:foreach x in=($cfmG->"mgmtExtra") do={ :set ($an->$x) 1 }
:foreach s in={"telnet";"ftp";"www";"www-ssl";"api";"api-ssl";"ssh";"winbox"} do={
  :local port ($cfmG->"services"->$s)
  :if ([:len $port] > 0) do={
    $cfmSet m="/ip/service" n=({"name"=$s;"dynamic"=false}) p=({"disabled"="no";"port"=$port;"address"=[$cfmKeys $an]})
  } else={
    $cfmSet m="/ip/service" n=({"name"=$s;"dynamic"=false}) p=({"disabled"="yes"})
  }
}
$cfmSet m="/ip/ssh" p=({"strong-crypto"="yes";"host-key-type"="ed25519"})

# --- Minimale Firewall (D31). Nicht-Router bekommen einen input-Block, Router haben die
#     Zonen-Firewall der Rolle router. Erlaubt: Antworten, ICMP, Management-Netze (MGMT-Netz,
#     mgmtAccess-Zonen, mgmtExtra), auf Managern DHCP im Onboarding-VLAN. Eigene Regeln gehören
#     in die Chain local-input; der Rest wird begrenzt geloggt (cfm-drop) und verworfen. ---
:if (!$isRouter) do={
  :local fa $an
  :set ($fa->($mn->"net")) 1
  :foreach n,x in=$fa do={ $cfmEnsure m="/ip/firewall/address-list" k=("al:mgmt:" . $n) p=({"list"="cfm-mgmt";"address"=$n}) }
  :local r ({})
  :set ($r->[:len $r]) ({"chain"="input";"action"="accept";"connection-state"="established,related,untracked"})
  :set ($r->[:len $r]) ({"chain"="input";"action"="drop";"connection-state"="invalid"})
  :set ($r->[:len $r]) ({"chain"="input";"action"="accept";"protocol"="icmp"})
  :set ($r->[:len $r]) ({"chain"="input";"action"="accept";"src-address-list"="cfm-mgmt"})
  # Manager: DHCP-Anfragen der Werksgeräte (Broadcast). Ohne Interface-Bindung, weil das
  # Onboarding-VLAN-Interface erst die Rolle manager anlegt; der DHCP-Server läuft nur dort.
  :if ($isMgr) do={
    :local ob false
    :foreach vid,v in=$cfmVlans do={ :if ([:tostr ($v->"onboard")] = "yes") do={ :set ob true } }
    :if ($ob) do={ :set ($r->[:len $r]) ({"chain"="input";"action"="accept";"protocol"="udp";"dst-port"="67"}) }
  }
  :set ($r->[:len $r]) ({"chain"="input";"action"="accept";"dst-address"="127.0.0.1"})
  :set ($r->[:len $r]) ({"chain"="input";"action"="jump";"jump-target"="local-input"})
  :set ($r->[:len $r]) ({"chain"="input";"action"="log";"log-prefix"="cfm-drop";"limit"="10/1m,5:packet"})
  :set ($r->[:len $r]) ({"chain"="input";"action"="drop"})
  $cfmBlock m="/ip/firewall/filter" k="fwb" l=$r
}
# IPv6 auf allen Geräten (bis zum IPv6-Konzept): Antworten, ICMPv6, Link-Local aus dem MGMT-VLAN
:local r6 ({})
:set ($r6->[:len $r6]) ({"chain"="input";"action"="accept";"connection-state"="established,related,untracked"})
:set ($r6->[:len $r6]) ({"chain"="input";"action"="drop";"connection-state"="invalid"})
:set ($r6->[:len $r6]) ({"chain"="input";"action"="accept";"protocol"="icmpv6"})
:set ($r6->[:len $r6]) ({"chain"="input";"action"="accept";"src-address"="fe80::/10";"in-interface-list"="MGMT"})
:set ($r6->[:len $r6]) ({"chain"="input";"action"="jump";"jump-target"="local-input"})
# MNDP-Nachbarsuche (UDP 5678 an ff02::1) aus anderen VLANs still verwerfen, sonst füllt sie das Log
:set ($r6->[:len $r6]) ({"chain"="input";"action"="drop";"protocol"="udp";"dst-port"="5678"})
:set ($r6->[:len $r6]) ({"chain"="input";"action"="log";"log-prefix"="cfm-drop6";"limit"="10/1m,5:packet"})
:set ($r6->[:len $r6]) ({"chain"="input";"action"="drop"})
$cfmBlock m="/ipv6/firewall/filter" k="fw6" l=$r6

# --- Zeit & Logging ---
$cfmSet m="/system/clock" p=({"time-zone-autodetect"="no";"time-zone-name"=($cfmG->"tz")})
:local sl [:tostr ($cfmG->"syslog")]
:if ([:len $sl] > 0) do={
  $cfmEnsure m="/system/logging/action" k="log:remote" n=({"name"="cfmremote"}) p=({"name"="cfmremote";"target"="remote";"remote"=$sl})
  :foreach t in={"info";"warning";"error";"critical"} do={
    $cfmEnsure m="/system/logging" k=("log:remote:" . $t) p=({"action"="cfmremote";"topics"=$t})
  }
}

# --- Admin-Benutzer (Passwort + Aktivierung kommen per Secret-Push) ---
:foreach u,grp in=($cfmG->"users") do={
  $cfmEnsure m="/user" k=("user:" . $u) n=({"name"=$u}) p=({"name"=$u;"group"=$grp}) a=({"password"=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"];"disabled"="yes"})
}

# --- cfm-Agent, Konfiguration und Scheduler aktuell halten ---
:local ms ""
:foreach a in=($cfmG->"managers") do={ :set ms ($ms . ";\"" . $a . "\"") }
:local conf (":global cfmConf {\"mgrs\"={" . [:pick $ms 1 [:len $ms]] . "};\"path\"=\"" . ($cfmG->"mgrPath") . "\";\"user\"=\"cfmd-" . ($cfmMf->"name") . "\"}")
$cfmEnsure m="/system/script" k="sys:conf" n=({"name"="cfm-conf"}) p=({"name"="cfm-conf";"source"=$conf;"policy"="read"})
$cfmEnsure m="/system/script" k="sys:agent" n=({"name"="cfm-agent"}) p=({"name"="cfm-agent";"source"=[/file get ($cfmDl . "/lib/agent.rsc") contents];"policy"="ftp,reboot,read,write,policy,test,password,sensitive"})
$cfmEnsure m="/system/scheduler" k="sys:agent" n=({"name"="cfm-agent"}) p=({"name"="cfm-agent";"start-time"="startup";"interval"=($cfmG->"interval");"on-event"="/system script run cfm-agent"})
# Mit Intervall läuft "startup" erst nach dem ersten Intervall (7.24). Eigener Boot-Scheduler,
# damit ein Gerät nach jedem Neustart (Update, Rollback, Stromausfall) gleich Status meldet.
$cfmEnsure m="/system/scheduler" k="sys:agent-boot" n=({"name"="cfm-agent-boot"}) p=({"name"="cfm-agent-boot";"start-time"="startup";"interval"="0s";"on-event"=":delay 20s; /system script run cfm-agent"})

# --- Werks-User admin abschalten (global adminUser="disable"), sobald hier mindestens ein
#     eigener Admin-User aus users aktiv ist – vorher nie, sonst droht Aussperren ---
:global cfmAU; :set cfmAU [:tostr ($cfmG->"adminUser")]
:if ([:tostr ($cfmG->"adminUser")] = "disable" and [:typeof ($cfmG->"users"->"admin")] = "nothing") do={
  :local act 0
  :foreach u,g in=($cfmG->"users") do={
    :if ([:len [/user/find where name=$u and !disabled]] > 0) do={ :set act ($act + 1) }
  }
  :if ($act > 0) do={ $cfmSet m="/user" n=({"name"="admin"}) p=({"disabled"="yes"}) }
}

# --- RouterBOOT-Firmware nach RouterOS-Updates automatisch nachziehen (fehlt auf CHR/x86) ---
:onerror e in={ $cfmSet m="/system/routerboard/settings" p=({"auto-upgrade"="yes"}) } do={}

# --- zuletzt: VLAN-Filtering scharf schalten ---
$cfmSet m="/interface/bridge" n=({"name"=$br}) p=({"vlan-filtering"="yes";"frame-types"="admit-only-vlan-tagged"})
