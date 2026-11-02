# ============================================================
# cfm lib/base.iso.rsc – Feature-Modul der Rolle base (D104): Filter der isolierten VLANs (D76, isolate="yes"
# in vlans.rsc). base lädt es per $cfmFeat nur mit einem isolierten VLAN und nur, wo Client-Ports sein können
# (reine Access-Ports eines solchen VLANs, Rollen ap, capsman, manager); ohne es bleibt der Block leer.
# Clients erreichen nur das Gateway (Router im VLAN, alles außerhalb des eigenen Netzes), Broadcast und die
# Ausnahmen aus isolateAllow. Von der Rolle: cfmCtx->"iso" = {VID=1} der isolierten VLANs
# ============================================================
:global cfmVlans; :global cfmLeases; :global cfmMf; :global cfmCtx
:global cfmNet; :global cfmMacUp; :global cfmLog; :global cfmBlock
:local iso ($cfmCtx->"iso")
:local fl ({})
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
$cfmBlock m="/interface/bridge/filter" k="iso" l=$fl
