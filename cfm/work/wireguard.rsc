# ============================================================
# cfm – WireGuard-Fernzugang für Admins (Peers zählen als Zone "mgmt",
#  volle Rechte wie ein Gerät im MGMT-VLAN, aber eigenes Subnetz - siehe "net")
#  listenPort  UDP-Port, auf dem der Router lauscht (auf dem WAN-Interface offen)
#  net         eigenes, nicht mit vlans.rsc überlappendes Subnetz für Router (Host .1)
#              und Peers - keine Proxy-ARP-Tricks, RouterOS legt die Routen automatisch an
#  peers       Key = Name/Kommentar; pubkey = Public Key des Peers (Base64);
#              addr = zugewiesene Tunnel-IP, Host-Anteil in "net" (z.B. 2)
# Alle Router haben denselben privaten Schlüssel (D84, Vault "wg.admin", per Secret-Push;
# beim ersten Release mit Peers übernimmt der Manager den eines vorhandenen wg-admin oder
# erzeugt einen). Öffentlichen Schlüssel abrufen: /interface/wireguard/print auf einem Router.
# Mit VRRP ist der Endpoint die VIP des WAN-VLANs; wg-admin läuft nur auf dessen Master.
# leer lassen (peers={}) = WireGuard-Interface bleibt aus.
# ============================================================
:global cfmWg {
  "listenPort"=13231;
  "net"="192.168.250.0/24";
  "peers"={
  }
}
