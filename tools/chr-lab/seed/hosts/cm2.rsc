# LAB cm2 (vm3): Backup-Manager. stp="none" prüft die Option aus D40 (nur ein Uplink, keine Schleife).
:global cfmHost {"ports"={"ether2"="trunk"};"stp"="none"}
:global cfmG; :set ($cfmG->"mgmtExtra") ({"10.0.2.0/24"})
# Labor: admin bleibt aktiv (SSH-Zugang vom Host über lab.sh)
:set ($cfmG->"adminUser") "keep"
# Labor: Manager-Tick jede Minute (Standard 10m), sonst warten die Tests minutenlang auf Rückmeldungen
:set ($cfmG->"mgrTick") "1m"
