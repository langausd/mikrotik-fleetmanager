# ============================================================
# LAB (e2e-mlag.sh, Isolation): IoT-VLAN isoliert (D76), Ausnahme cl-c aus leases.rsc
# ============================================================
:global cfmVlans {
  "10"={"name"="MGMT";"zone"="mgmt"};
  "20"={"name"="LAN";"zone"="lan"};
  "30"={"name"="IOT";"zone"="iot";"dhcp"="50-200";"isolate"="yes";"isolateAllow"="cl-c"};
  "40"={"name"="GAST";"zone"="guest";"dhcp"="100-200"};
  "88"={"name"="ONBOARD";"zone"="onboard";"gw"=250;"dhcp"="100-199";"lease"="10m";"onboard"="yes"}
}
