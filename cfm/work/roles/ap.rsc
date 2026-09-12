# ============================================================
# Rolle ap – WLAN-Access-Point als CAP des (wifi-)CAPsMAN
#  SSIDs/Kanäle/Security rendert der CAPsMAN (Rolle manager).
#  Lokales Forwarding: SSIDs landen per datapath vlan-id im VLAN,
#  der Uplink braucht daher das Profil "trunk-ap".
# ============================================================
:global cfmG; :global cfmSet; :global cfmLog

:local mv [:tostr ($cfmG->"mgmtVlan")]
$cfmSet m="/interface/wifi/cap" p=({"enabled"="yes";"caps-man-addresses"=($cfmG->"managers");"discovery-interfaces"=("vlan" . $mv);"lock-to-caps-man"="no";"certificate"="request"})

# Lokale Radios dem CAPsMAN übergeben
:foreach i in=[/interface/wifi/find where default-name~"^wifi"] do={
  :if ([:tostr [/interface/wifi/get $i configuration.manager]] != "capsman") do={
    /interface/wifi/set $i configuration.manager=capsman
    $cfmLog ("Radio " . [/interface/wifi/get $i name] . " -> CAPsMAN")
  }
}
