# LAB cm1 (vm1): ether1 = QEMU-User-Net (SSH vom Host), ether2/ether3 = Trunks zu vm2/vm3 (Stern)
:global cfmHost {"ports"={"ether2"="trunk";"ether3"="trunk"}}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
