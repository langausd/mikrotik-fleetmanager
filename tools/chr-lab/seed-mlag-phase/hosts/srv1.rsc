# LAB srv1 (vm4), Phase MLAG: LACP-Bond über beide Switches (D74)
:global cfmHost {"bonds"={"bond1"={"slaves"="ether2,ether3"}};"ports"={"bond1"="trunk"}}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
