# ============================================================
# cfm – VLAN-Tabelle (Key = VLAN-ID als String)
#  name   Anzeigename (Kommentar); Interfaces heißen vlan<VID> / vrrp<VID>
#  zone   Firewall-Zone (mgmt|lan|iot|guest|… siehe policy in global.rsc)
#  net    Subnetz; Default 192.168.<VID>.0/24 (nur VID <= 255)
#  gw     Host-Anteil des Gateways/VRRP-VIP (Default 1)
#  dhcp   "a-b" Host-Bereich des DHCP-Pools oder "no" (Default "no")
#  dns    DNS-Server für DHCP-Clients (Default = Gateway)
#  lease  DHCP-Lease-Zeit (Default 30m)
#  l3     "no" = Router legt kein Interface/IP an (reines L2-VLAN)
# VLAN entfernen = Zeile löschen -> Reconciler räumt überall auf.
# ============================================================
:global cfmVlans {
  "10"={"name"="MGMT";"zone"="mgmt"};
  "30"={"name"="IOT";"zone"="iot";"dhcp"="50-200";"lease"="45m"};
  "40"={"name"="GAST";"zone"="guest";"dhcp"="100-200"};
  "20"={"name"="LAN";"zone"="lan";"gw"=66;"dns"="192.168.20.1"};
  "88"={"name"="ONBOARD";"zone"="onboard";"gw"=250;"dhcp"="100-199";"lease"="10m";"onboard"="yes"}
}
# VLAN 88 = Onboarding-Netz (siehe README "Onboarding"): passt zur Werks-IP 192.168.88.1
# neuer Geräte, Gateway .250 (Router, nur MikroTik-Update-Server erreichbar), DHCP vom
# Primary-Manager. Nie dauerhaft untagged an einem Port – nur per $cfmOnboard.
# Bereiche lassen sich per Schleife anlegen (Zone ggf. anpassen):
:for i from=101 to=119 do={
  :set ($cfmVlans->[:tostr $i]) {"name"=("V" . $i);"zone"="lan"}
}
