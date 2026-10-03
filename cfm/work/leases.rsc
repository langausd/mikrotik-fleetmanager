# ============================================================
# cfm – feste DHCP-Leases je VLAN (D62)
#  "<VID>"={"<name>"={"mac"="AA:BB:CC:DD:EE:FF";"ip"=<Host-Teil>}}
#  ip    Host-Anteil im Netz des VLANs (wie gw/dhcp in vlans.rsc), z.B. 50 -> .50
#  name  Kommentar der Lease und DNS-Name <name>.<domain> auf den Routern (Buchstaben, Ziffern, "-")
# Wirkt auf Geräten mit Rolle router in VLANs mit "dhcp" (bei VRRP auf allen Routern, der DHCP-Server
# läuft nur auf dem Master). Die Router führen außerdem DNS-Namen für alle aufgenommenen Geräte
# (<name>.<domain> -> MGMT-Adresse). Beispiel:
#  :global cfmLeases {
#    "30"={"drucker"={"mac"="02:00:00:00:00:30";"ip"=20}}
#  }
# Leer bleibt es bei ({}) - ein leeres {} liest RouterOS als Codeblock (Syntaxfehler beim /import).
# ============================================================
:global cfmLeases ({})
