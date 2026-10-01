# LAB cm1 (vm1): Primary-Manager, zentraler Switch der Stern-Topologie und dritter Router (routerId 3).
# ether2/ether3 = Trunks zu r1/r2, ether4 = Internet-Router (LAN ungetaggt, IoT/Gast getaggt für dessen VRF-Clients)
# WAN = LAN-VLAN mit dem Internet-Router als Gateway (wie im Zielbild).
:global cfmHost {"ports"={"ether2"="trunk";"ether3"="trunk";"ether4"="hybrid:20"};"routerId"=3;"wan"={"if"="vlan20";"gw"="192.168.20.1";"dns"="192.168.20.1"}}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Policy wie im Zielbild: LAN -> IoT/Gast/Internet ohne NAT, IoT ohne Internet, Gäste mit fester NAT-Adresse
:set ($cfmG->"policy") ({"mgmt"="*";"lan"="iot,guest,wan";"iot"="";"guest"="wan@192.168.20.199";"onboard"="*mtupdate"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh), Manager-Tick jede Minute
:set ($cfmG->"adminUser") "keep"
:set ($cfmG->"mgrTick") "1m"
