# LAB sw1 (vm5): Switch ohne Rolle router an cm1/ether5 mit eigenem Ausgang wie ein Käfig-Netz am
# Standort: Adresse im LAN-VLAN (sw1.post.rsc), Default-Route über den Internet-Router statt über die
# MGMT-VIP. Antworten an WireGuard-Peers müssen trotzdem über die MGMT-VIP gehen (rt:wg, D84).
:global cfmHost {"ports"={"ether2"="trunk"};"cpuVlans"={20};"gw"="192.168.20.1";"dns"="192.168.20.1"}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24";"192.168.20.10/32"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
