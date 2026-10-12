# LAB sw1 (vm2): ether2 = cm1, ether3/ether4 = zu sw2 (vor MLAG zwei Trunks, RSTP sperrt einen),
# ether5 = srv1, ether6/ether7 = Clients im IoT-VLAN (vm5, VRF a und b)
:global cfmHost {"ports"={"ether2"="trunk";"ether3"="trunk";"ether4"="trunk";"ether5"="trunk";"ether6"="access:30";"ether7"="access:30"};"stpPrio"="0x4000"}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
