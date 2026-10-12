# LAB cm1 (vm1): Primary-Manager, ether2 = Trunk zu sw1. Später auch Router (Gateway .1 der VLANs).
:global cfmHost {"ports"={"ether2"="trunk"}}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
# Labor: Manager-Tick jede Minute
:set ($cfmG->"mgrTick") "1m"
