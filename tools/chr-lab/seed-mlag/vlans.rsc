# ============================================================
# LAB (MLAG und Isolation, e2e-mlag.sh): MGMT, LAN, IoT (später isoliert), Gast, Onboarding
# ============================================================
:global cfmVlans {
  "10"={"name"="MGMT";"zone"="mgmt"};
  "20"={"name"="LAN";"zone"="lan"};
  "30"={"name"="IOT";"zone"="iot";"dhcp"="50-200"};
  "40"={"name"="GAST";"zone"="guest";"dhcp"="100-200"};
  "88"={"name"="ONBOARD";"zone"="onboard";"gw"=250;"dhcp"="100-199";"lease"="10m";"onboard"="yes"}
}
