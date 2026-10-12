# ============================================================
# Rolle switch – Ports/VLANs erledigt bereits base.
# Hier nur Switch-Spezifika (bewusst schlank).
#  Hostfile-Parameter: igmp="yes"   IGMP-Snooping
#                      dhcpSnoop="yes"  DHCP-Snooping; Trunks (tagged, ohne PVID) = trusted
# ============================================================
:global cfmHost; :global cfmSet; :global cfmProfile

:local igmp [:tostr ($cfmHost->"igmp")]
:if ([:len $igmp] = 0) do={ :set igmp "no" }
:local snoop [:tostr ($cfmHost->"dhcpSnoop")]
:if ([:len $snoop] = 0) do={ :set snoop "no" }
$cfmSet m="/interface/bridge" n=({"name"="bridge"}) p=({"igmp-snooping"=$igmp;"dhcp-snooping"=$snoop})

# Ports samt Bonds und MLAG-Peer aus der Rolle base (cfmPortMap, D74/D75)
:global cfmPortMap
:if ($snoop = "yes" and [:typeof $cfmPortMap] = "array") do={
  :foreach p,spec in=$cfmPortMap do={
    :local pr ({"bridge"=true;"untag"=""})
    :if ($spec != "*mlag-peer") do={ :set pr [$cfmProfile $spec] }
    :if ($pr->"bridge") do={
      :local tr "no"
      :if ([:len ($pr->"untag")] = 0) do={ :set tr "yes" }
      $cfmSet m="/interface/bridge/port" n=({"interface"=$p}) p=({"trusted"=$tr})
    }
  }
}
