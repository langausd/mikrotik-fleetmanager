# ============================================================
# cfm – MLAG-Paare (D75): zwei Switches, an denen Geräte per LACP-Bond über beide hängen
#  "<Paar>"={
#    "nodes"="sw1,sw2"         die beiden Knoten (Namen aus dem Inventar, gleicher Ring)
#    "primary"="sw1"           bekommt mlag-priority 50 (der andere 128)
#    "peer"="sfp-sfpplus3,sfp-sfpplus4"   Ports der direkten Verbindung beider Knoten -> Bond
#                              peer-<Paar> (LACP), trägt alle VLANs getaggt
#    "stpPrio"="0x4000"        optional, gilt auf beiden Knoten statt stpPrio aus dem Hostfile
#    "lacpFallback"="yes"      optional, ab RouterOS 7.25 (mlag-lacp-fallback), sonst Werkseinstellung
#    "initDelay"="1m"          optional, ab RouterOS 7.25 (mlag-init-delay)
#    "bonds"={"<Bond>"={"id"=11;"ports"="ether1";"profile"="trunk"}}
#                              je doppelt angebundenem Gerät ein Bond mit derselben mlag-id auf beiden
#                              Knoten, Profil wie unter ports im Hostfile
#  }
#  Ports: Text = auf beiden Knoten gleich, sonst je Knoten: "ports"={"sw1"="ether1";"sw2"="ether3"}
# Die Ports gehören dann nicht mehr ins Hostfile (ports/portDefault gelten für sie nicht). Einfache
# Bonds auf einem Gerät stehen im Hostfile unter bonds (D74). Voraussetzung: RouterOS 7.22 oder neuer,
# kein L3-Hardware-Offloading (schaltet base ab). Beispiel:
#  :global cfmMlag {
#    "core"={"nodes"="sw1,sw2";"primary"="sw1";"peer"="sfp-sfpplus3,sfp-sfpplus4";
#      "bonds"={"pve1"={"id"=11;"ports"="ether1";"profile"="trunk"}}}
#  }
# Leer bleibt es bei ({}) - ein leeres {} liest RouterOS als Codeblock (Syntaxfehler beim /import).
# ============================================================
:global cfmMlag ({})
