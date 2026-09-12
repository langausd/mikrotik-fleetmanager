# rtr1 – Core-Router (VRRP routerId 1 = Master), Uplink zum Internet-Router im VLAN 20
:global cfmHost {
  "routerId"=1;
  "ports"={"ether1"="trunk";"ether2"="trunk"};
  "wan"={"if"="vlan20";"gw"="192.168.20.1";"dns"="192.168.20.1"}
}
# Zweiter Router: Hostfile rtr2.rsc mit "routerId"=2, sonst identisch.
