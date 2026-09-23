# ============================================================
# Rolle ap – WLAN-Access-Point als CAP des (wifi-)CAPsMAN
#  SSIDs/Kanäle/Security rendert der CAPsMAN (Rolle manager).
#  Lokales Forwarding: SSIDs landen per datapath vlan-id im VLAN,
#  der Uplink braucht daher das Profil "trunk-ap".
# ============================================================
:global cfmG; :global cfmEnsure; :global cfmSet; :global cfmLog; :global cfmDry

:local mv [:tostr ($cfmG->"mgmtVlan")]

# Lokaler Datapath (D41): Die Bridge ist beim wifi-CAPsMAN eine Einstellung des CAP. Der CAPsMAN
# schickt vlan-id und client-isolation, aber nie "bridge" (er kennt die Interfaces des CAP nicht).
# Ohne diesen Datapath wird kein Radio Bridge-Port: Clients melden sich an, erreichen aber kein
# VLAN. Radios (Master) und virtuelle APs (slaves-datapath) zeigen darauf, vlan-id bleibt leer.
:local dp "cfm-cap"
$cfmEnsure m="/interface/wifi/datapath" k="wdp-cap" n=({"name"=$dp}) p=({"name"=$dp;"bridge"="bridge"})
$cfmSet m="/interface/wifi/cap" p=({"enabled"="yes";"caps-man-addresses"=($cfmG->"managers");"discovery-interfaces"=("vlan" . $mv);"lock-to-caps-man"="no";"certificate"="request";"slaves-datapath"=$dp})

# Lokale Radios dem CAPsMAN übergeben
:foreach i in=[/interface/wifi/find where default-name~"^wifi"] do={
  :local rn [/interface/wifi/get $i name]
  :if ([:tostr [/interface/wifi/get $i configuration.manager]] != "capsman") do={
    :if ($cfmDry != true) do={ /interface/wifi/set $i configuration.manager=capsman }
    $cfmLog ("Radio " . $rn . " -> CAPsMAN")
  }
  :if ([:tostr [/interface/wifi/get $i datapath]] != $dp) do={
    :if ($cfmDry != true) do={ /interface/wifi/set $i datapath=$dp }
    $cfmLog ("Radio " . $rn . " -> Datapath " . $dp)
  }
}
