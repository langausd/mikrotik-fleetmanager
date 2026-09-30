# ============================================================
# Rolle base – gilt für ALLE Geräte, wird immer zuerst angewendet
#  Identität, Bridge + VLAN-Filtering, Port-Profile, MGMT-Zugang,
#  Dienste-Härtung, Zeit/Logging, Admin-Benutzer, cfm-Agent.
# ============================================================
:global cfmG; :global cfmVlans; :global cfmHost; :global cfmMf; :global cfmDl; :global cfmWg
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
#     stp="none" (Hostfile) schaltet RSTP ab. Gedacht für Router/Manager in einer VM mit einer Karte
#     je VLAN: Deren Ports führen alle zum selben Netz, RSTP hielte das für eine Schleife und würde
#     Ports blockieren; die VM streute außerdem BPDUs in jedes dieser VLANs. Die Trennung leistet
#     dort das VLAN-Filtering. $cfmCheck warnt, wenn zwei Ports desselben Geräts im selben VLAN
#     liegen - dann wäre die Schleife echt (D40).
:local stp [:tostr ($cfmHost->"stpPrio")]
:if ([:len $stp] = 0) do={ :set stp "0x8000" }
:local proto "rstp"
:if ([:tostr ($cfmHost->"stp")] = "none") do={ :set proto "none" }
# Ohne RSTP liefert RouterOS keine priority (nil) – sie zu setzen, erschiene bei jedem Apply als
# Änderung (TODO 27); die Priorität zählt dann ohnehin nicht
:local brp ({"name"=$br;"protocol-mode"=$proto;"priority"=$stp})
:if ($proto = "none") do={ :set brp ({"name"=$br;"protocol-mode"=$proto}) }
$cfmEnsure m="/interface/bridge" k="br" n=({"name"=$br}) p=$brp a=({"vlan-filtering"="no"})

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
#     Hostfile cpuVlans={177;...}: die Bridge (CPU) bleibt in diesen VLANs getaggt, obwohl das Gerät
#     kein Router ist - für eigene VLAN-Interfaces aus der post.rsc oder von Hand (Bestandsgerät,
#     das heute noch routet). Ohne den Eintrag verlören diese Interfaces beim ersten Apply ihr VLAN.
:local cpuV ({})
:foreach x in=($cfmHost->"cpuVlans") do={ :set ($cpuV->[:tostr $x]) 1 }
:foreach vid,v in=$cfmVlans do={
  :local tg ({})
  :if ([:typeof ($tagged->$vid)] = "array") do={ :set tg ($tagged->$vid) }
  :if ($vid = $mv or ($isRouter and [:tostr ($v->"l3")] != "no") or ($isMgr and [:tostr ($v->"onboard")] = "yes") or [:typeof ($cpuV->$vid)] != "nothing") do={ :set ($tg->$br) 1 }
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
# Hostfile gw/dns/ntp ersetzen MGMT-Gateway bzw. globale Werte - für Geräte, die selbst das
# MGMT-Gateway sind (sonst Default-Route, DNS und NTP auf sich selbst) oder einen eigenen Ausgang
# brauchen (z.B. ein Käfig-Netz, das direkt über den Internet-Router ins Internet geht).
:if (!$isRouter) do={
  :local gw [:tostr ($mn->"gw")]
  :if ([:len [:tostr ($cfmHost->"gw")]] > 0) do={ :set gw [:tostr ($cfmHost->"gw")] }
  :local dns ($cfmG->"dns")
  :if ([:len [:tostr ($cfmHost->"dns")]] > 0) do={ :set dns ($cfmHost->"dns") }
  :local ntp ($cfmG->"ntp")
  :if ([:len [:tostr ($cfmHost->"ntp")]] > 0) do={ :set ntp ($cfmHost->"ntp") }
  $cfmEnsure m="/ip/route" k="rt:default" n=({"dst-address"="0.0.0.0/0";"gateway"=$gw}) p=({"dst-address"="0.0.0.0/0";"gateway"=$gw})
  $cfmSet m="/ip/dns" p=({"servers"=$dns})
  $cfmSet m="/system/ntp/client" p=({"enabled"="yes";"servers"=$ntp})
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
# WireGuard-Peers (D36) zählen überall als mgmt, nicht nur beim Forwarding über den Router -
# sonst lässt zwar die Firewall SSH/Winbox-Pakete durch, aber der Dienst selbst (eigene
# Adressliste, unabhängig von der Firewall) weist sie zurück.
:if ([:typeof $cfmWg] = "array" and [:len ($cfmWg->"peers")] > 0 and [:len [:tostr ($cfmWg->"net")]] > 0) do={
  :set ($an->[:tostr ($cfmWg->"net")]) 1
}
# Lese-Zugang per RouterOS-API nur auf dem CAPsMAN und nur für capsmanApi.from (D47, z.B. Home
# Assistant: welcher Client an welchem AP) - unabhängig von services und den Management-Netzen
:global cfmIsCapsman
:local capi ($cfmG->"capsmanApi")
:local capiOn false
:if ([:typeof $capi] = "array") do={ :if ([:len ($capi->"from")] > 0 and [$cfmIsCapsman]) do={ :set capiOn true } }
# Ab RouterOS 7.24 heißt das Feld available-from, address ist veraltet (Warnung beim Setzen, TODO 43);
# ältere Versionen kennen nur address -> Feldname aus dem Eigenschafts-Array (ssh gibt es auch dynamisch)
:local saf "address"
:onerror e in={
  :if ([:typeof ([/ip/service/get [:pick [find where name="ssh" and !dynamic] 0]]->"available-from")] != "nothing") do={ :set saf "available-from" }
} do={}
:foreach s in={"telnet";"ftp";"www";"www-ssl";"api";"api-ssl";"ssh";"winbox"} do={
  :local port ($cfmG->"services"->$s)
  :local addr [$cfmKeys $an]
  :if ($s = "api" and $capiOn and [:len $port] = 0) do={
    :set port ($capi->"port")
    :if ([:len [:tostr $port]] = 0) do={ :set port 8728 }
    :set addr ($capi->"from")
  }
  :if ([:len $port] > 0) do={
    :local sp ({"disabled"="no";"port"=$port})
    :set ($sp->$saf) $addr
    $cfmSet m="/ip/service" n=({"name"=$s;"dynamic"=false}) p=$sp
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
  # ohne $cfmEnsure (kein "comment"): manche RouterOS-Builds (beobachtet auf hAP AX²,
  # wifiwave2) lehnen /system/logging/add mit "comment" ab ("expected end of command"),
  # obwohl derselbe Aufruf auf anderer Hardware (z.B. CRS418) funktioniert.
  :foreach t in={"info";"warning";"error";"critical"} do={
    :local lid [/system/logging/find where action="cfmremote" and topics=$t]
    :if ([:len $lid] = 0 and $cfmDry != true) do={ /system/logging/add action="cfmremote" topics=$t }
  }
}

# --- Admin-Benutzer (Passwort + Aktivierung kommen per Secret-Push) ---
:foreach u,grp in=($cfmG->"users") do={
  $cfmEnsure m="/user" k=("user:" . $u) n=({"name"=$u}) p=({"name"=$u;"group"=$grp}) a=({"password"=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"];"disabled"="yes"})
}

# --- Persönliche Admin-SSH-Keys aus work/authorized_keys (OpenSSH-Format, eine Zeile je Key:
#     "<typ> <base64> [kommentar]", keine OpenSSH-Optionen wie command=... davor; "#"-Zeilen und
#     Leerzeilen werden ignoriert). Optional: Fehlt die Datei, bleiben ssh-keys unangetastet.
#     Ist sie da, ist sie der VOLLSTÄNDIGE Sollzustand für ALLE Admin-User aus global.rsc users:
#     Keys, die nicht (mehr) drinstehen, werden bei jedem Apply entfernt (auch von Hand
#     hinzugefügte) - Revocation = Zeile löschen + $cfmRelease. Passwort-Login (Secret-Push) bleibt
#     davon unberührt und funktioniert in jedem Fall zusätzlich. Kein Ersatz für die ssh-keys der
#     Rolle manager (cfm/cfmd-<name>) - die sind Maschinen-Identität, hier geht es um Menschen. ---
:local akf ($cfmDl . "/authorized_keys")
:if ([:len [/file/find where name=$akf]] > 0) do={
  :local lines ({})
  :local t ([/file/get $akf contents] . "\n")
  :while ([:len $t] > 0) do={
    :local p [:find $t "\n"]
    :local l [:pick $t 0 $p]
    :set t [:pick $t ($p + 1) [:len $t]]
    :if ([:len $l] > 0 and [:pick $l ([:len $l] - 1) [:len $l]] = "\r") do={ :set l [:pick $l 0 ([:len $l] - 1)] }
    :if ([:len $l] > 0 and [:pick $l 0 1] != "#") do={ :set ($lines->[:len $lines]) $l }
  }
  :local aku ({})
  :foreach u,grp in=($cfmG->"users") do={ :if ([:len [/user/find where name=$u]] > 0) do={ :set ($aku->[:len $aku]) $u } }
  :if ([:len $aku] > 0) do={
    :if ($cfmDry = true) do={
      $cfmLog ("Admin-SSH-Keys wuerden aktualisiert: " . [:len $lines] . " Key(s) fuer " . [:len $aku] . " User")
    } else={
      :foreach u in=$aku do={ /user/ssh-keys/remove [find where user=$u] }
      :local i 0
      :foreach ln in=$lines do={
        :local kf ("cfm-ak" . $i)
        /file/add name=$kf contents=$ln
        :delay 100ms
        :foreach u in=$aku do={
          :onerror e in={ /user/ssh-keys/import user=$u public-key-file=$kf } do={ $cfmLog ("Admin-Key " . ($i + 1) . " fuer " . $u . " fehlgeschlagen: " . $e) }
        }
        :onerror e in={ /file/remove [find where name=$kf] } do={}
        :set i ($i + 1)
      }
    }
  }
}

# --- cfm-Agent, Konfiguration und Scheduler aktuell halten ---
:local ms ""
:foreach a in=($cfmG->"managers") do={ :set ms ($ms . ";\"" . $a . "\"") }
:local conf (":global cfmConf {\"mgrs\"={" . [:pick $ms 1 [:len $ms]] . "};\"path\"=\"" . ($cfmG->"mgrPath") . "\";\"user\"=\"cfmd-" . ($cfmMf->"name") . "\"}")
$cfmEnsure m="/system/script" k="sys:conf" n=({"name"="cfm-conf"}) p=({"name"="cfm-conf";"source"=$conf;"policy"="read"})
$cfmEnsure m="/system/script" k="sys:agent" n=({"name"="cfm-agent"}) p=({"name"="cfm-agent";"source"=[/file get ($cfmDl . "/lib/agent.rsc") contents];"policy"="ftp,reboot,read,write,policy,test,password,sensitive"})
$cfmEnsure m="/system/scheduler" k="sys:agent" n=({"name"="cfm-agent"}) p=({"name"="cfm-agent";"start-time"="startup";"interval"=($cfmG->"interval");"on-event"="/system script run cfm-agent";"disabled"="no"})
# Mit Intervall läuft "startup" erst nach dem ersten Intervall (7.24). Eigener Boot-Scheduler,
# damit ein Gerät nach jedem Neustart (Update, Rollback, Stromausfall) gleich Status meldet.
# Der Boot-Lauf ist als "boot" gekennzeichnet: findet er keinen Manager, startet der Agent
# die Bridge-Ports neu (RouterOS-Eigenheit nach einem Neustart, siehe agent.rsc)
:local bev ":delay 20s; :global cfmArg \"boot\"; /system script run cfm-agent"
$cfmEnsure m="/system/scheduler" k="sys:agent-boot" n=({"name"="cfm-agent-boot"}) p=({"name"="cfm-agent-boot";"start-time"="startup";"interval"="0s";"on-event"=$bev})

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

# --- Nur der cfm-CAPsMAN darf im MGMT-VLAN antworten (D45, TODO 26): Ein zweiter CAPsMAN lockt
#     frische CAPs per Discovery an und verteilt eine fremde CA. Auf Geräten, die nicht CAPsMAN sind
#     (Manifest-Feld cm), den Dienst abschalten – auch nach einem Umzug der Rolle capsman ---
:global cfmIsCapsman
:if (![$cfmIsCapsman]) do={
  :onerror e in={ $cfmSet m="/interface/wifi/capsman" p=({"enabled"="no"}) } do={}
}

# --- RouterBOOT-Firmware nach RouterOS-Updates automatisch nachziehen (fehlt auf CHR/x86) ---
:onerror e in={ $cfmSet m="/system/routerboard/settings" p=({"auto-upgrade"="yes"}) } do={}

# --- zuletzt: VLAN-Filtering scharf schalten ---
#     Hostfile bridgeFrames="admit-all": die Bridge (CPU) nimmt weiter ungetaggte Frames an - nur für
#     Bestandsgeräte mit einer Adresse direkt auf der Bridge (VLAN 1), die erhalten bleiben soll.
:local bfr "admit-only-vlan-tagged"
:if ([:len [:tostr ($cfmHost->"bridgeFrames")]] > 0) do={ :set bfr [:tostr ($cfmHost->"bridgeFrames")] }
$cfmSet m="/interface/bridge" n=({"name"=$br}) p=({"vlan-filtering"="yes";"frame-types"=$bfr})
