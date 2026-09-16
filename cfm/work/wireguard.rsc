# ============================================================
# cfm – WireGuard-Fernzugang für Admins (Peers zählen als Zone "mgmt",
#  volle Rechte wie ein Gerät im MGMT-VLAN, aber eigenes Subnetz - siehe "net")
#  listenPort  UDP-Port, auf dem der Router lauscht (auf dem WAN-Interface offen)
#  net         eigenes, nicht mit vlans.rsc überlappendes Subnetz für Router (Host .1)
#              und Peers - keine Proxy-ARP-Tricks, RouterOS legt die Routen automatisch an
#  peers       Key = Name/Kommentar; pubkey = Public Key des Peers (Base64);
#              addr = zugewiesene Tunnel-IP, Host-Anteil in "net" (z.B. 2)
# Der private Schlüssel des Routers wird beim ersten Anlegen der Schnittstelle
# automatisch erzeugt und bleibt auf dem Gerät (kein Vault-Eintrag, wie bei den
# SSH-Host-Keys). Öffentlichen Schlüssel abrufen: /interface/wireguard/print
# leer lassen (peers={}) = WireGuard-Interface bleibt aus.
# ============================================================
:global cfmWg {
  "listenPort"=13231;
  "net"="192.168.250.0/24";
  "peers"={
  }
}
