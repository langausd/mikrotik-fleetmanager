# ============================================================
# LAB (Router-Probe, e2e-vrrp.sh): VLANs wie im Zielbild eines Standorts, dessen Internet-Router im
# LAN steht (Variante C): LAN-Gateway der Router ist die VIP .2, der Internet-Router behält .1 und
# bleibt Default-Gateway der LAN-Clients; IoT und Gast mit DHCP vom VRRP-Master.
# ============================================================
:global cfmVlans {
  "10"={"name"="MGMT";"zone"="mgmt"};
  "20"={"name"="LAN";"zone"="lan";"gw"=2;"dns"="192.168.20.1"};
  "30"={"name"="IOT";"zone"="iot";"dhcp"="50-200";"lease"="45m"};
  "40"={"name"="GAST";"zone"="guest";"dhcp"="100-200"};
  "88"={"name"="ONBOARD";"zone"="onboard";"gw"=250;"dhcp"="100-199";"lease"="10m";"onboard"="yes"}
}
