# ============================================================
# cfm – DNS der Router (D101, optional, nur Rolle router). Leer = wie ohne Datei: Die Router fragen
# wan.dns aus ihrem Hostfile und beantworten nur die eigenen Namen (<name>.<domain>, D62).
#  "servers"={"9.9.9.9";"149.112.112.112"}   Upstream statt wan.dns, Reihenfolge = Vorrang
#  "cache"="64M"            DNS-Cache (k/M/G oder Zahl in KiB, Standard RouterOS 2M); die Adlisten
#                           liegen darin - je 100 000 Namen gut 7 MB
#  "adlists"={"https://…/hosts"}   Sperrlisten im hosts-Format; gesperrte Namen -> 0.0.0.0, RouterOS lädt
#                           sie alle 4 h neu (Zertifikat geprüft, eingebauter Speicher)
#  "allow"={"beispiel.de"}  Ausnahmen von den Adlisten: Domain samt Subdomains geht an die Upstreams
#  "forward"={"standort2.example"="192.168.20.2"}   Domain samt Subdomains an einen anderen DNS-Server
#                           (Adresse oder Liste {"a";"b"}), z.B. die Namen eines anderen Standorts
#  "log"={"memory"=20000;"syslog"="yes"}   Abfrage-Log je Client (Topic dns): memory = Zeilen im
#                           RAM-Puffer cfmdns (0 = aus), syslog = zusätzlich an den Syslog-Server (global.rsc
#                           syslog). Aus beidem: kein Log
# Beispiel:
#  :global cfmDns {
#    "servers"={"9.9.9.9";"149.112.112.112";"86.54.11.100";"86.54.11.200"};
#    "cache"="64M";
#    "adlists"={"https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"};
#    "allow"={"beispiel.de"};
#    "forward"={"standort2.example"="192.168.20.2"};
#    "log"={"memory"=20000;"syslog"="no"}
#  }
# Leer bleibt es bei ({}) - ein leeres {} liest RouterOS als Codeblock (Syntaxfehler beim /import).
# ============================================================
:global cfmDns ({})
