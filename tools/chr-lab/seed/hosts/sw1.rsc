# LAB sw1 (vm2): Switch/Router-Testgerät
:global cfmHost {"ports"={"ether2"="trunk"};"igmp"="yes";"routerId"=1;"wan"={"if"="ether1";"dhcp"="yes"}}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Labor: feste NAT-Adresse (D38) am WAN ether1 prüfen (Beispieldaten nutzen *wan)
:set ($cfmG->"policy"->"guest") "wan@10.0.2.99"
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
