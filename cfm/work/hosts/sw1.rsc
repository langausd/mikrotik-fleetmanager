# sw1 – Access-Switch (Beispiel: CRS326-24G-2S+)
# Alle nicht genannten Ports: access im LAN-VLAN 20.
:global cfmHost {
  "portDefault"="access:20";
  "ports"={
    "sfp-sfpplus1"="trunk";
    "ether1"="trunk";
    "ether2"="trunk-ap";
    "ether3"="trunk-ap";
    "ether8"="access:30";
    "ether24"="access:10"
  };
  "stpPrio"="0x4000";
  "igmp"="yes"
}
