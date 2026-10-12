# LAB sw2 (vm3), Phase MLAG: ether2/ether3 (Peer) und ether4 (srv1) stehen in mlag.rsc
:global cfmHost {"ports"={"ether5"="access:30"};"stpPrio"="0x4000"}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
