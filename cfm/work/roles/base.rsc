# ============================================================
# Rolle base – gilt für ALLE Geräte, wird immer zuerst angewendet
#  Identität, Bridge + VLAN-Filtering, Port-Profile, MGMT-Zugang,
#  Dienste-Härtung, Zeit/Logging, Admin-Benutzer, cfm-Agent.
# ============================================================
:global cfmG; :global cfmVlans; :global cfmHost; :global cfmMf; :global cfmDl; :global cfmWg
:global cfmEnsure; :global cfmSet; :global cfmProfile; :global cfmNet; :global cfmKeys
:global cfmHas; :global cfmLog; :global cfmBlock; :global cfmDry
:global cfmIds; :global cfmRun; :global cfmIndex; :global cfmIdx; :global cfmVids; :global cfmMlagOf
:global cfmLeases; :global cfmMacUp

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
# MLAG-Paar dieses Geräts (mlag.rsc, D75): beide Knoten brauchen dieselbe STP-Priorität, stpPrio des
# Paars gilt deshalb vor der aus dem Hostfile
:local ml [$cfmMlagOf ($cfmMf->"name")]
:local stp [:tostr ($cfmHost->"stpPrio")]
:if ([:len [:tostr ($ml->"stp")]] > 0) do={ :set stp ($ml->"stp") }
:if ([:len $stp] = 0) do={ :set stp "0x8000" }
:local proto "rstp"
:if ([:tostr ($cfmHost->"stp")] = "none") do={ :set proto "none" }
# Ohne RSTP liefert RouterOS keine priority (nil) – sie zu setzen, erschiene bei jedem Apply als
# Änderung (TODO 27); die Priorität zählt dann ohnehin nicht
:local brp ({"name"=$br;"protocol-mode"=$proto;"priority"=$stp})
:if ($proto = "none") do={ :set brp ({"name"=$br;"protocol-mode"=$proto}) }
$cfmEnsure m="/interface/bridge" k="br" n=({"name"=$br}) p=$brp a=({"vlan-filtering"="no"})

# --- Bonds (D74) und MLAG (D75) ---
#     Hostfile bonds={"bond1"={"slaves"="sfp1,sfp2";"mode"="802.3ad"|"active-backup";"hash"=…;"primary"=…}},
#     das Profil steht wie bei jedem Port unter ports ("bond1"="trunk"). Ist das Gerät Knoten eines Paars
#     in mlag.rsc, kommen der Peer-Bond peer-<Paar> (alle VLANs getaggt) und die MLAG-Bonds (mlag-id,
#     Profil aus mlag.rsc) dazu. Bonds, die es nicht mehr geben soll, werden schon hier entfernt und
#     die Slaves verlassen die Bridge: Unten bei den Ports wären sie sonst noch belegt.
:local brc ({})
:onerror e in={ :set brc [/interface/bridge/get [find where name=$br and !dynamic]] } do={}
:local hasMl ([:typeof ($brc->"mlag-peer-port")] != "nothing")
:if ([:len $ml] > 0 and !$hasMl) do={ :error "MLAG (mlag.rsc) braucht RouterOS 7.22 oder neuer" }
:if ($hasMl and [:len $ml] = 0 and [:tostr ($brc->"mlag-peer-port")] != "none") do={ $cfmSet m="/interface/bridge" n=({"name"=$br}) p=({"mlag-peer-port"="none"}) }
:local bonds ({})
:local bspec ({})
:foreach bn,b in=($cfmHost->"bonds") do={
  :local md [:tostr ($b->"mode")]
  :if ([:len $md] = 0) do={ :set md "802.3ad" }
  :local hs [:tostr ($b->"hash")]
  :if ([:len $hs] = 0) do={ :set hs "layer-2-and-3" }
  :local bp ({"name"=$bn;"slaves"=[:toarray ($b->"slaves")];"mode"=$md;"lacp-rate"="1sec";"transmit-hash-policy"=$hs})
  :if ([:len [:tostr ($b->"primary")]] > 0) do={ :set ($bp->"primary") [:tostr ($b->"primary")] }
  :set ($bonds->$bn) $bp
}
:if ([:len $ml] > 0) do={
  :set ($bonds->($ml->"peer")) ({"name"=($ml->"peer");"slaves"=[:toarray ($ml->"peerSlaves")];"mode"="802.3ad";"lacp-rate"="1sec";"transmit-hash-policy"="layer-2-and-3"})
  :set ($bspec->($ml->"peer")) "*mlag-peer"
  :foreach bn,b in=($ml->"bonds") do={
    :set ($bonds->$bn) ({"name"=$bn;"slaves"=[:toarray ($b->"slaves")];"mode"="802.3ad";"lacp-rate"="1sec";"transmit-hash-policy"="layer-2-and-3";"mlag-id"=($b->"id")})
    :set ($bspec->$bn) ($b->"profile")
  }
}
:local slv ({})
:foreach bn,b in=$bonds do={ :foreach x in=($b->"slaves") do={ :set ($slv->[:tostr $x]) $bn } }
$cfmIndex "/interface/bonding"
$cfmIndex "/interface/bridge/port"
:foreach k,id in=($cfmIdx->"/interface/bonding") do={
  :local bn [:pick $k 5 [:len $k]]
  :if ([:pick $k 0 5] = "bond:" and [:typeof ($bonds->$bn)] = "nothing") do={
    :local bpid ($cfmIdx->"/interface/bridge/port"->("bp:" . $bn))
    :if ($cfmDry != true) do={
      :if ([:typeof $bpid] != "nothing") do={ /interface/bridge/port/remove $bpid }
      /interface/bonding/remove $id
    }
    :set ($cfmIdx->"/interface/bridge/port"->("bp:" . $bn))
    :set ($cfmIdx->"/interface/bonding"->$k)
    $cfmLog ("Bond " . $bn . " entfernt, seine Ports bekommen wieder ihr eigenes Profil")
  }
}
:foreach x,bn in=$slv do={
  :foreach pid in=[/interface/bridge/port/find where interface=$x and !dynamic] do={
    :if ($cfmDry != true) do={ /interface/bridge/port/remove $pid }
    $cfmLog ("Port " . $x . " aus der Bridge genommen (Slave von " . $bn . ")")
  }
  :set ($cfmIdx->"/interface/bridge/port"->("bp:" . $x))
  :if ([:len [/interface/ethernet/find where name=$x]] > 0) do={ $cfmSet m="/interface/ethernet" n=({"name"=$x}) p=({"disabled"="no"}) }
}
:foreach bn,b in=$bonds do={ $cfmEnsure m="/interface/bonding" k=("bond:" . $bn) n=({"name"=$bn}) p=$b }
# MLAG verträgt kein L3-Hardware-Offloading (MikroTik-Doku): wie bei der Rolle router (D37) aus
:if ([:len $ml] > 0) do={
  :local sws ({})
  :onerror e in={ :set sws [$cfmIds "/interface/ethernet/switch" N=({})] } do={ :set sws ({}) }
  :foreach sw in=$sws do={
    :local sc [$cfmRun "/interface/ethernet/switch/get" I=$sw]
    :if ([:typeof ($sc->"l3-hw-offloading")] != "nothing") do={ $cfmSet m="/interface/ethernet/switch" n=({"name"=($sc->"name")}) p=({"l3-hw-offloading"="no"}) }
  }
}

# --- Ports nach Profil (portDefault gilt für alle nicht genannten Ethernet-Ports, nicht für Slaves) ---
:local ports ({})
:local def [:tostr ($cfmHost->"portDefault")]
:if ([:len $def] > 0) do={
  :foreach i in=[/interface/ethernet/find] do={
    :local en [/interface/ethernet/get $i name]
    :if ([:typeof ($slv->$en)] = "nothing") do={ :set ($ports->$en) $def }
  }
}
:if ([:typeof ($cfmHost->"ports")] = "array") do={
  :foreach p,spec in=($cfmHost->"ports") do={
    :if ([:typeof ($slv->$p)] = "nothing") do={ :set ($ports->$p) $spec } else={ $cfmLog ("Port " . $p . " ist Slave von " . ($slv->$p) . ": Profil " . $spec . " gilt nicht") }
  }
}
:foreach bn,sp in=$bspec do={ :set ($ports->$bn) $sp }
# für spätere Rollen (switch: DHCP-Snooping vertraut den Trunks)
:global cfmPortMap; :set cfmPortMap $ports

# --- Isolierte VLANs (D76): isolate="yes" in vlans.rsc ---
#     Clients eines isolierten VLANs erreichen nur das Gateway (Adressen der Router im VLAN und alles
#     außerhalb des eigenen Netzes), Broadcast (ARP, DHCP) und die Ausnahmen aus isolateAllow (Namen aus
#     leases.rsc oder MAC-Adressen); Multicast zwischen Clients nicht. Gefiltert wird am Eingang der
#     Client-Ports (Liste cfm-iso): reine Access-Ports des VLANs - mit hw=no, sonst sähe der Bridge-Filter
#     den Verkehr im Switch-Chip nicht - und WLAN-Interfaces isolierter SSIDs (Datapath interface-list,
#     Rolle ap). Ein Frame von Client zu Client endet damit schon am Gerät des Absenders.
:local iso ({})
:foreach vid,v in=$cfmVlans do={ :if ([:tostr ($v->"isolate")] = "yes") do={ :set ($iso->$vid) 1 } }
# Ports, die zuletzt isoliert waren (hw=no zurücknehmen, wenn sie es nicht mehr sind)
:local wasIso ({})
$cfmIndex "/interface/list/member"
:foreach k,id in=($cfmIdx->"/interface/list/member") do={ :if ([:pick $k 0 8] = "ilm:ISO:") do={ :set ($wasIso->[:pick $k 8 [:len $k]]) 1 } }
:if ([:len $iso] > 0) do={ $cfmEnsure m="/interface/list" k="il:ISO" n=({"name"="cfm-iso"}) p=({"name"="cfm-iso"}) }
:local hasHw false
:onerror e in={ :set hasHw ([:typeof ([/interface/bridge/port/get [:pick [/interface/bridge/port/find where !dynamic] 0]]->"hw")] != "nothing") } do={}
:local nIso 0
:local tagged ({}); :local untagged ({})
# Nachbarsuche (LLDP/MNDP/CDP) auf allen Bridge-Ports + MGMT-VLAN: Grundlage für $cfmLinks (D33)
$cfmEnsure m="/interface/list" k="il:DISC" n=({"name"="DISC"}) p=({"name"="DISC"})
:foreach p,spec in=$ports do={
  :local pr
  # Peer-Bond eines MLAG-Paars: alle VLANs getaggt, keine ungetaggten Frames (MikroTik-Doku)
  :if ($spec = "*mlag-peer") do={ :set pr ({"tag"=[$cfmVids "*"];"untag"="";"bridge"=true;"edge"="auto";"disabled"=false;"frame"="admit-only-vlan-tagged"}) } else={ :set pr [$cfmProfile $spec] }
  :if ($pr->"bridge") do={
    $cfmEnsure m="/interface/list/member" k=("ilm:DISC:" . $p) n=({"list"="DISC";"interface"=$p}) p=({"list"="DISC";"interface"=$p})
    :local pv 1
    :if ([:len ($pr->"untag")] > 0) do={ :set pv [:tonum ($pr->"untag")] }
    :local bpdu "no"
    :if (($pr->"edge") = "yes") do={ :set bpdu "yes" }
    :local bpp ({"bridge"=$br;"interface"=$p;"pvid"=$pv;"frame-types"=($pr->"frame");"ingress-filtering"="yes";"edge"=($pr->"edge");"bpdu-guard"=$bpdu})
    # reiner Access-Port eines isolierten VLANs (D76): Client-Port, Verkehr über die CPU (Bridge-Filter)
    :local isoP ([:len ($pr->"untag")] > 0 and [:typeof ($iso->[:tostr ($pr->"untag")])] != "nothing" and [:len [$cfmKeys ($pr->"tag")]] = 0)
    :if ($isoP) do={
      :set nIso ($nIso + 1)
      $cfmEnsure m="/interface/list/member" k=("ilm:ISO:" . $p) n=({"list"="cfm-iso";"interface"=$p}) p=({"list"="cfm-iso";"interface"=$p})
      :if ($hasHw) do={ :set ($bpp->"hw") "no" }
    } else={ :if ($hasHw and [:typeof ($wasIso->$p)] != "nothing") do={ :set ($bpp->"hw") "yes" } }
    $cfmEnsure m="/interface/bridge/port" k=("bp:" . $p) n=({"interface"=$p}) p=$bpp
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

# Filter der isolierten VLANs (D76), nur wo Client-Ports sein können (Access-Ports, WLAN)
:local fl ({})
:if ([:len $iso] > 0 and ($nIso > 0 or [$cfmHas "ap"] or [$cfmHas "capsman"] or [$cfmHas "manager"])) do={
  :local am ({})
  :local ipr ({})
  :foreach vid,x in=$iso do={
    :local nn [$cfmNet $vid]
    :local net [:tostr ($nn->"net")]
    :if ([:len $net] > 0) do={
      # Router im VLAN: VIP bzw. Gateway .gw und die realen Adressen .250+routerId (D15)
      :local rips ({})
      :set ($rips->[:tostr ($nn->"gw")]) 1
      :for r from=1 to=4 do={ :set ($rips->[:tostr (($nn->"addr") + 250 + $r)]) 1 }
      :set ($ipr->[:len $ipr]) ({"chain"="forward";"in-interface-list"="cfm-iso";"mac-protocol"="ip";"src-address"=$net;"dst-address"=("!" . $net);"action"="accept"})
      :foreach ip,y in=$rips do={
        :set ($ipr->[:len $ipr]) ({"chain"="forward";"in-interface-list"="cfm-iso";"mac-protocol"="ip";"src-address"=$net;"dst-address"=($ip . "/32");"action"="accept"})
        :set ($ipr->[:len $ipr]) ({"chain"="forward";"in-interface-list"="cfm-iso";"mac-protocol"="arp";"arp-src-address"=$net;"arp-dst-address"=($ip . "/32");"action"="accept"})
      }
    }
    :foreach a in=[:toarray ($cfmVlans->$vid->"isolateAllow")] do={
      :local mac [:tostr $a]
      :if (!([:len $mac] = 17 and $mac ~ "^[0-9A-Fa-f][0-9A-Fa-f](:[0-9A-Fa-f][0-9A-Fa-f])+\$")) do={ :set mac [:tostr ($cfmLeases->$vid->$a->"mac")] }
      :if ([:len $mac] > 0) do={ :set ($am->[$cfmMacUp $mac]) 1 } else={ $cfmLog ("isolateAllow " . $a . " (VLAN " . $vid . "): keine MAC in leases.rsc") }
    }
  }
  :set ($fl->[:len $fl]) ({"chain"="forward";"in-interface-list"="cfm-iso";"dst-mac-address"="FF:FF:FF:FF:FF:FF/FF:FF:FF:FF:FF:FF";"action"="accept"})
  :foreach mac,y in=$am do={
    :set ($fl->[:len $fl]) ({"chain"="forward";"in-interface-list"="cfm-iso";"dst-mac-address"=($mac . "/FF:FF:FF:FF:FF:FF");"action"="accept"})
    :set ($fl->[:len $fl]) ({"chain"="forward";"in-interface-list"="cfm-iso";"src-mac-address"=($mac . "/FF:FF:FF:FF:FF:FF");"action"="accept"})
  }
  # Multicast vor den IP-Regeln: eine Multicast-Adresse liegt außerhalb des eigenen Netzes
  :set ($fl->[:len $fl]) ({"chain"="forward";"in-interface-list"="cfm-iso";"dst-mac-address"="01:00:00:00:00:00/01:00:00:00:00:00";"action"="drop"})
  # Gateway: VRRP-MAC und die MACs der Router aus dem Manifest. Je nach Gerät sieht der Bridge-Filter
  # einen ungetaggt angekommenen Frame als ip oder als vlan (Labor: virtio ip, e1000 vlan) - IP-Matcher
  # greifen dann nicht, MAC-Matcher immer. Die IP-Regeln danach ergänzen nur.
  :set ($fl->[:len $fl]) ({"chain"="forward";"in-interface-list"="cfm-iso";"dst-mac-address"="00:00:5E:00:01:00/FF:FF:FF:FF:FF:00";"action"="accept"})
  :foreach mac in=($cfmMf->"rmac") do={ :set ($fl->[:len $fl]) ({"chain"="forward";"in-interface-list"="cfm-iso";"dst-mac-address"=([$cfmMacUp $mac] . "/FF:FF:FF:FF:FF:FF");"action"="accept"}) }
  :if ([:len ($cfmMf->"rmac")] = 0) do={ $cfmLog "isolierte VLANs: keine Router-MACs im Manifest - Clients erreichen das Gateway nur, wenn der Filter IP-Adressen sieht" }
  :foreach r in=$ipr do={ :set ($fl->[:len $fl]) $r }
  :set ($fl->[:len $fl]) ({"chain"="forward";"in-interface-list"="cfm-iso";"action"="drop"})
}
$cfmBlock m="/interface/bridge/filter" k="iso" l=$fl

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
  # Eigener Ausgang: Antworten an WireGuard-Peers (D36) gingen sonst an diesen Gateway, der das
  # WG-Netz nicht kennt -> WG-Netz über das MGMT-Gateway (bei VRRP die VIP, D84)
  :if ($gw != [:tostr ($mn->"gw")] and [:typeof $cfmWg] = "array" and [:len ($cfmWg->"peers")] > 0 and [:len [:tostr ($cfmWg->"net")]] > 0) do={
    $cfmEnsure m="/ip/route" k="rt:wg" p=({"dst-address"=[:tostr ($cfmWg->"net")];"gateway"=[:tostr ($mn->"gw")];"disabled"="no"})
  }
  $cfmSet m="/ip/dns" p=({"servers"=$dns})
  $cfmSet m="/system/ntp/client" p=({"enabled"="yes";"servers"=$ntp})
}
$cfmEnsure m="/interface/list" k="il:MGMT" n=({"name"="MGMT"}) p=({"name"="MGMT"})
$cfmEnsure m="/interface/list/member" k="ilm:MGMT" n=({"list"="MGMT";"interface"=$mif}) p=({"list"="MGMT";"interface"=$mif})
$cfmEnsure m="/interface/list/member" k="ilm:DISC:mgmt" n=({"list"="DISC";"interface"=$mif}) p=({"list"="DISC";"interface"=$mif})
# Alle drei Protokolle auf allen Geräten: Winbox findet Geräte nur per MNDP. MNDP über Bridge-Ports
# ohne Adresse (Quelle 0.0.0.0) verwirft der input-Block der Empfänger still (D78)
$cfmSet m="/ip/neighbor/discovery-settings" p=({"discover-interface-list"="DISC";"protocol"="cdp,lldp,mndp"})
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
# reverse-proxy (RouterOS 7.2x) ist ab Werk an, Port 443 ohne Adressbeschränkung (TODO 30); ältere
# Versionen kennen den Dienst nicht, $cfmSet findet dann nichts
:foreach s in={"telnet";"ftp";"www";"www-ssl";"reverse-proxy";"api";"api-ssl";"ssh";"winbox"} do={
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
# Host-Key-Prüfung des SSH-Clients (RouterOS 7.25, nach Reset an) aus wie nach einem Update: Pull und
# ssh-exec liefen sonst nur mit gepflegten known-hosts; Manifeste sind signiert, der Secret-Push prüft
# die Identität (D28, D71)
:if ([:typeof ([/ip/ssh/get]->"known-hosts-validation")] != "nothing") do={ $cfmSet m="/ip/ssh" p=({"known-hosts-validation"="no"}) }

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
  # MNDP über Bridge-Ports ohne Adresse (Quelle 0.0.0.0) still verwerfen, sonst füllt es das Log: Hinter
  # einem Access-Port (z.B. die Karten einer VM, D40) erreicht es jedes Gerät im VLAN (D78)
  :set ($r->[:len $r]) ({"chain"="input";"action"="drop";"protocol"="udp";"dst-port"="5678";"src-address"="0.0.0.0"})
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
# RAM-Log ohne system,info (D79): RouterOS loggt jede Konfig-Änderung (bei Skripten samt Quelltext) und
# jede Anmeldung als system,info - ein Framework-Update verdrängte so die Hälfte der 1000 Zeilen des
# Managers. logMemory = Topics der Regel info -> memory (RouterOS-Standard "info"); Syslog bekommt alles.
:global cfmStat
:local lm [:tostr ($cfmG->"logMemory")]
:if ([:len $lm] = 0) do={ :set lm "info,!system" }
:foreach id in=[/system/logging/find where action="memory"] do={
  :local t [/system/logging/get $id topics]
  :if ([:pick $t 0] = "info" and [:tostr $t] != [:tostr [:toarray $lm]]) do={
    $cfmRun "/system/logging/set" I=$id P=({"topics"=$lm})
    :set ($cfmStat->"set") (($cfmStat->"set") + 1)
    $cfmLog ("gesetzt: /system/logging: topics=" . $lm)
  }
}

# --- Admin-Benutzer (Passwort + Aktivierung kommen per Secret-Push) ---
:foreach u,grp in=($cfmG->"users") do={
  $cfmEnsure m="/user" k=("user:" . $u) n=({"name"=$u}) p=({"name"=$u;"group"=$grp}) a=({"password"=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"];"disabled"="yes"})
}

# --- Persönliche Admin-SSH-Keys je User (TODO 19, D65): work/authorized_keys.<user> im OpenSSH-Format,
#     eine Zeile je Key "<typ> <base64> [kommentar]" (ssh-ed25519, ssh-rsa, sk-ssh-ed25519@openssh.com;
#     keine OpenSSH-Optionen wie command=... davor; "#"-Zeilen und Leerzeilen zählen nicht).
#     Gibt es die Datei für einen User aus global.rsc users, ist sie SEIN vollständiger Sollzustand:
#     fehlende Keys legt base an, alle übrigen Keys dieses Users entfernt es (auch von Hand
#     hinzugefügte). Entzug = Zeile löschen + $cfmRelease; alle Keys einer Person entziehen = Datei
#     leeren (nur Kommentare) - eine gelöschte Datei lässt die Keys dagegen stehen: Ohne Datei bleiben
#     die Keys eines Users unangetastet. Abgleich über den Fingerprint: Jeder Key wird angelegt
#     (add key=, liefert fingerprint) und gleich wieder entfernt, wenn der User ihn schon hat - so gibt
#     es nie einen Moment ohne Key. Scheitert ein Key, entfernt base für diesen User nichts (ein
#     halber Sollzustand sperrt niemanden aus). Im Probelauf ist kein add möglich - Abgleich dort
#     näherungsweise über den Kommentar (info). Das Passwort (Secret-Push) bleibt gesetzt, gilt mit Key
#     aber nur noch für Winbox/WebFig: RouterOS lehnt SSH per Passwort ab, sobald der User einen Key
#     hat (always-allow-password-login=no, TODO 29). Kein Ersatz für die ssh-keys der Rolle manager
#     (cfm/cfmd-<name>) - die sind Maschinen-Identität, hier geht es um Menschen. ---
:global cfmWarn; :global cfmShowAll; :global cfmShowObj
:foreach u,grp in=($cfmG->"users") do={
  :local akf ($cfmDl . "/authorized_keys." . $u)
  # per Name statt /file/find (D59, auf dem Manager Hunderte Dateien); eine gelöschte Datei liefert
  # /file/get u.U. weiter als Eintrag ohne Namen
  :local akx false
  :onerror e in={ :set akx ([:len [/file/get $akf name]] > 0) } do={}
  :if ($akx and [:len [/user/find where name=$u]] > 0) do={
    :local lines ({})
    :local t ([/file/get $akf contents] . "\n")
    :while ([:len $t] > 0) do={
      :local p [:find $t "\n"]
      :local l [:pick $t 0 $p]
      :set t [:pick $t ($p + 1) [:len $t]]
      :if ([:len $l] > 0 and [:pick $l ([:len $l] - 1) [:len $l]] = "\r") do={ :set l [:pick $l 0 ([:len $l] - 1)] }
      :if ([:len $l] > 0 and [:pick $l 0 1] != "#") do={ :set ($lines->[:len $lines]) $l }
    }
    :if ($cfmShowAll = true) do={ $cfmShowObj m="/user/ssh-keys" k=("ak:" . $u) p=({"user"=$u;"keys"=[:len $lines]}) }
    :if ($cfmDry = true) do={
      # Kommentar = alles nach dem zweiten Feld; RouterOS legt ihn als info ab
      :local want ({})
      :foreach ln in=$lines do={
        :local c ""
        :local p1 [:find $ln " "]
        :if ([:typeof $p1] = "num") do={
          :local r [:pick $ln ($p1 + 1) [:len $ln]]
          :local p2 [:find $r " "]
          :if ([:typeof $p2] = "num") do={ :set c [:pick $r ($p2 + 1) [:len $r]] }
        }
        :set ($want->("i" . $c)) 1
      }
      :local have ({})
      :local nr 0
      :foreach id in=[/user/ssh-keys/find where user=$u] do={
        :local c ("i" . [:tostr [/user/ssh-keys/get $id info]])
        :set ($have->$c) 1
        :if ([:typeof ($want->$c)] = "nothing") do={ :set nr ($nr + 1) }
      }
      :local na 0
      :foreach c,x in=$want do={ :if ([:typeof ($have->$c)] = "nothing") do={ :set na ($na + 1) } }
      :if (($na + $nr) > 0) do={ $cfmLog ("Admin-SSH-Keys " . $u . ": " . $na . " neu, " . $nr . " entfernt (Abgleich im Probelauf über den Kommentar)") }
    } else={
      # vorhandene Keys nach Fingerprint; doppelte gleich entfernen
      :local have ({})
      :foreach id in=[/user/ssh-keys/find where user=$u] do={
        :local fp ("f" . [:tostr [/user/ssh-keys/get $id fingerprint]])
        :if ([:typeof ($have->$fp)] = "nothing") do={ :set ($have->$fp) $id } else={
          /user/ssh-keys/remove $id
          :set ($cfmStat->"rem") (($cfmStat->"rem") + 1)
          $cfmLog ("entfernt: /user/ssh-keys " . $u . " (doppelt)")
        }
      }
      :local keep ({})
      :local fail 0
      :local i 0
      :foreach ln in=$lines do={
        :set i ($i + 1)
        :onerror e in={
          :local nid [/user/ssh-keys/add user=$u key=$ln]
          :local fp ("f" . [:tostr [/user/ssh-keys/get $nid fingerprint]])
          :if ([:typeof ($have->$fp)] != "nothing" or [:typeof ($keep->$fp)] != "nothing") do={
            /user/ssh-keys/remove $nid
          } else={
            :set ($cfmStat->"add") (($cfmStat->"add") + 1)
            $cfmLog ("neu: /user/ssh-keys " . $u . " " . [:tostr [/user/ssh-keys/get $nid info]])
          }
          :set ($keep->$fp) 1
        } do={
          :set fail ($fail + 1)
          $cfmWarn ("authorized_keys." . $u . ": Key " . $i . " nicht angelegt: " . $e)
        }
      }
      :if ($fail > 0) do={
        $cfmWarn ("authorized_keys." . $u . ": " . $fail . " Key(s) fehlgeschlagen - vorhandene Keys bleiben stehen")
      } else={
        :foreach fp,id in=$have do={
          :if ([:typeof ($keep->$fp)] = "nothing") do={
            :local inf [:tostr [/user/ssh-keys/get $id info]]
            /user/ssh-keys/remove $id
            :set ($cfmStat->"rem") (($cfmStat->"rem") + 1)
            $cfmLog ("entfernt: /user/ssh-keys " . $u . " " . $inf)
          }
        }
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
# MLAG erst mit VLAN-Filtering (Peer-Port im Bridge-Menü seit 7.22); Primary = mlag-priority 50
:if ([:len $ml] > 0) do={
  :local mp ({"mlag-peer-port"=($ml->"peer");"mlag-priority"=128})
  :if ($ml->"primary") do={ :set ($mp->"mlag-priority") 50 }
  # ab 7.25: LACP-Fallback und Startverzögerung, nur wenn in mlag.rsc gesetzt
  :if ([:len ($ml->"fallback")] > 0 and [:typeof ($brc->"mlag-lacp-fallback")] != "nothing") do={ :set ($mp->"mlag-lacp-fallback") ($ml->"fallback") }
  :if ([:len ($ml->"initDelay")] > 0 and [:typeof ($brc->"mlag-init-delay")] != "nothing") do={ :set ($mp->"mlag-init-delay") ($ml->"initDelay") }
  $cfmSet m="/interface/bridge" n=({"name"=$br}) p=$mp
}
