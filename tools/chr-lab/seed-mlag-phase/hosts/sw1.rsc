# LAB sw1 (vm2), Phase MLAG: ether3/ether4 (Peer) und ether5 (srv1) stehen in mlag.rsc
:global cfmHost {"ports"={"ether2"="trunk";"ether6"="access:30";"ether7"="access:30"};"stpPrio"="0x4000"}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
