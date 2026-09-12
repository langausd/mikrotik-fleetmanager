# ============================================================
# Rolle base – gilt für ALLE Geräte, wird immer zuerst angewendet
#  Identität, Bridge + VLAN-Filtering, Port-Profile, MGMT-Zugang,
#  Dienste-Härtung, Zeit/Logging, Admin-Benutzer, cfm-Agent.
# ============================================================
:global cfmG; :global cfmVlans; :global cfmHost; :global cfmMf; :global cfmDl
:global cfmEnsure; :global cfmSet; :global cfmProfile; :global cfmNet; :global cfmKeys
:global cfmHas; :global cfmLog

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
:foreach p,spec in=$ports do={
  :local pr [$cfmProfile $spec]
  :if ($pr->"bridge") do={
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
        /interface/bridge/port/remove $bid
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
$cfmSet m="/ip/neighbor/discovery-settings" p=({"discover-interface-list"="MGMT"})
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
