# LAB sw2 (vm3): ether2/ether3 = zu sw1, ether4 = srv1, ether5 = Client im IoT-VLAN (vm5, VRF c)
:global cfmHost {"ports"={"ether2"="trunk";"ether3"="trunk";"ether4"="trunk";"ether5"="access:30"};"stpPrio"="0x4000"}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
