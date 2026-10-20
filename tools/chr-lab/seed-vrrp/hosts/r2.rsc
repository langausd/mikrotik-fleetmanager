# LAB r2 (vm3): erster Ersatz (routerId 2)
# WAN = LAN-VLAN mit dem Internet-Router als Gateway (wie im Zielbild); eigene NTP-Server als Liste (TODO 59).
:global cfmHost {"ports"={"ether2"="trunk"};"routerId"=2;"wan"={"if"="vlan20";"gw"="192.168.20.1";"dns"="192.168.20.1";"ntp"={"192.168.20.1";"198.51.100.1"}}}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24";"192.168.20.10/32"})
# Policy wie im Zielbild: LAN -> IoT/Gast/Internet ohne NAT, IoT ohne Internet, Gäste mit fester NAT-Adresse
:set ($cfmG->"policy") ({"mgmt"="*";"lan"="iot,guest,wan";"iot"="";"guest"="wan@192.168.20.199";"onboard"="*mtupdate"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
