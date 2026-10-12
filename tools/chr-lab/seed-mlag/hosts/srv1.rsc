# LAB srv1 (vm4): Server an beiden Switches, ether2 = sw1, ether3 = sw2 (vor dem Bond zwei Trunks)
:global cfmHost {"ports"={"ether2"="trunk";"ether3"="trunk"}}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
