# LAB ob1 (vm3): Testgerät für den Onboarding-Push. ether2 = Trunk zu cm1/ether3,
# ether1 = QEMU-User-Net als WAN (Router-Rolle stellt nach dem no-defaults-Reset den DHCP-Client
# und damit den SSH-Zugang vom Host wieder her)
:global cfmHost {"ports"={"ether2"="trunk";"ether1"="wan"};"wan"={"if"="ether1";"dhcp"="yes"}}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
