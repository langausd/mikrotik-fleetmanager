# LAB sw1 (vm5): Adresse im LAN-VLAN für den eigenen Ausgang (gw im Hostfile)
:global cfmEnsure
$cfmEnsure m="/interface/vlan" k="sw1:vlan20" n=({"name"="vlan20"}) p=({"name"="vlan20";"interface"="bridge";"vlan-id"=20})
$cfmEnsure m="/ip/address" k="sw1:ip20" n=({"interface"="vlan20"}) p=({"address"="192.168.20.240/24";"interface"="vlan20"})
