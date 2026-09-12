# LAB cm2 (vm3): Backup-Manager
:global cfmHost {"ports"={"ether2"="trunk"}}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
