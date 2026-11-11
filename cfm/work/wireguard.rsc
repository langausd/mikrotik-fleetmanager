# ============================================================
# cfm – WireGuard: Fernzugang für Admins (DR4.1/DR4.2), Standortkopplung (DR4.3), DynDNS (DR4.4)
#
# Fernzugang (Peers zählen als Zone "mgmt", volle Rechte wie ein Gerät im MGMT-VLAN, eigenes Subnetz "net"):
#  listenPort  UDP-Port, auf dem der Router lauscht (auf dem WAN-Interface offen)
#  net         eigenes, nicht mit vlans.rsc überlappendes Subnetz für Router (Host .1)
#              und Peers - keine Proxy-ARP-Tricks, RouterOS legt die Routen automatisch an
#  peers       Key = Name/Kommentar; pubkey = Public Key des Peers (Base64);
#              addr = zugewiesene Tunnel-IP, Host-Anteil in "net" (z.B. 2)
# Alle Router haben denselben privaten Schlüssel (DR4.2, Vault "wg.admin", per Secret-Push;
# beim ersten Release mit Peers übernimmt der Manager den eines vorhandenen wg-admin oder
# erzeugt einen). Öffentlichen Schlüssel abrufen: /interface/wireguard/print auf einem Router.
# Mit VRRP ist der Endpoint die VIP des WAN-VLANs; wg-admin läuft nur auf dessen Master.
# Geräte ohne Rolle router mit eigenem gw (Hostfile) routen das WG-Netz über das MGMT-Gateway.
# leer lassen (peers={}) = WireGuard-Interface bleibt aus.
#
# Standortkopplung (DR4.3, optional): je entferntem Standort ein Tunnel wg-site-<name>, der Standort ist eine
# Zone mit diesem Namen - in global.rsc policy wie jede andere: Zeile "<name>"="lan,iot" (was er hier erreicht)
# und als Ziel "lan"="…,<name>". Alle Router haben denselben Schlüssel (Vault "wg.site", entsteht beim ersten
# Release; öffentlich: $cfmShow bzw. meta/vault.dat "wgsitepub" - den trägt die Gegenstelle als pubkey ein).
#  "sites"={"<name>"={"pubkey"="<wgsitepub der Gegenstelle>";"endpoint"="<Name oder IP>:<Port>";"port"=13232;
#                     "nets"={"192.168.20.0/24";"192.168.30.0/24"};"domain"="standort2.example";"dns"="192.168.20.2"}}
#   name      Kleinbuchstaben/Ziffern/"-", keine vorhandene Zone
#   endpoint  öffentlicher Name (DynDNS) oder Adresse der Gegenstelle samt deren Port; ohne endpoint wartet dieser
#             Standort auf den Verbindungsaufbau der Gegenstelle. Namen löst der Router über den Upstream auf
#             (Skript cfm-wgsite alle 2 min), nicht über den eigenen DNS
#   port      eigener UDP-Port für diesen Tunnel (Standard 13232, je Standort eindeutig; am Internet-Router
#             auf die VIP des WAN-VLANs bzw. den Router weiterleiten)
#   nets      Netze des Standorts, die über den Tunnel erreichbar sind (allowed-address und Routen)
#   domain    DNS-Namen des Standorts (dessen global.rsc domain) samt Subdomains an dessen Resolver "dns"
#             (eine Adresse in nets, z.B. dessen LAN-Gateway/VIP) weiterleiten
# Bei VRRP hält der Master des WAN-VLANs den Tunnel; Backups routen über die MGMT-VIP (Distanz 10). Clients,
# die den Internet-Router als Gateway nutzen, brauchen dort Routen zu nets ($cfmShow nennt sie).
#
# DynDNS (DR4.4, optional, nur Router; bei VRRP nur der Master des WAN-VLANs):
#  "self"={"name"="<standort>";"ddns"={"type"="dyndns2";"url"="https://update.dedyn.io/nic/update";"name"="s1.example";
#          "ipUrl"="https://api.ipify.org";"interval"="5m"}}
#   type      "dyndns2" = Update-URL des Anbieters mit hostname/myip und HTTP-Basic (Zugang im Vault:
#             $cfmSecret key=ddns.auth value="user:passwort"); "cloud" = MikroTik-Cloud (/ip/cloud ddns-enabled,
#             Name <SN>.sn.mynetname.net je Gerät); "api" = vorgemerkt (Anbieter-API mit Token), noch ohne Wirkung
#   ipUrl     liefert die eigene öffentliche Adresse (Text), Standard https://api.ipify.org
#   interval  Prüfintervall (Standard 5m); gesendet wird nur bei neuer Adresse, sonst einmal täglich
# ============================================================
:global cfmWg {
  "listenPort"=13231;
  "net"="192.168.250.0/24";
  "peers"={
  }
}
