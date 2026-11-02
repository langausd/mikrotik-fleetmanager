# ============================================================
# cfm lib/router.wg.rsc – Feature-Modul der Rolle router (D104); router.rsc lädt es per $cfmFeat nur mit
# Peers in wireguard.rsc. Ohne Peers räumt die GC Interface, Peers, Adresse, Route und Listeneinträge weg.
# WireGuard-Fernzugang (D36): eigenes, nicht überlappendes Subnetz (wireguard.rsc "net") -
# RouterOS legt sonst keine Route für "allowed-address" an, wenn sie in einem bereits
# verbundenen Subnetz (z.B. MGMT) liegt, und ohne eigenes Subnetz bräuchte es zusätzlich
# Proxy-ARP (frühere Version, siehe docs/TODO.md "Bekannte Fehler" zur Vorgeschichte). Peers
# zählen trotzdem als Zone mgmt (volle mgmt-Rechte) über die Interface-Liste, unabhängig vom
# Subnetz. Privater Schlüssel: alle Router denselben aus dem Vault (D84, Secret-Push); beim Anlegen
# erzeugt RouterOS erst einen eigenen, weicht er vom Manifest ab ("wgpub"), fordert die Rolle den
# Secret-Push an. Öffentlichen Schlüssel abrufen: /interface/wireguard/print. Leere peers-Liste =
# Interface bleibt aus.
# Von der Rolle: cfmCtx->"wgV" = VLAN des WAN bei VRRP (leer = Einzelrouter), cfmCtx->"mv" = MGMT-VLAN
# ============================================================
:global cfmWg; :global cfmMf; :global cfmCtx; :global cfmDry
:global cfmEnsure; :global cfmNet; :global cfmLog
:local wgIf "wg-admin"
:local wgV [:tostr ($cfmCtx->"wgV")]
:local mv [:tostr ($cfmCtx->"mv")]
:local wnet [:tostr ($cfmWg->"net")]
:local wslash [:find $wnet "/"]
:local wbase [:toip [:pick $wnet 0 $wslash]]
:local wpfx [:pick $wnet ($wslash + 1) [:len $wnet]]
# bei VRRP nur auf dem Master des WAN-VLANs an (wie DHCP; danach schalten on-master/on-backup um)
:local wgDis "no"
:if ([:len $wgV] > 0) do={
  :set wgDis "yes"
  :local vi [/interface/vrrp/find where name=("vrrp" . $wgV)]
  :if ([:len $vi] > 0) do={ :if ([:tostr [/interface/vrrp/get [:pick $vi 0] running]] = "true") do={ :set wgDis "no" } }
}
$cfmEnsure m="/interface/wireguard" k="wg:admin" n=({"name"=$wgIf}) p=({"name"=$wgIf;"listen-port"=[:tonum ($cfmWg->"listenPort")];"disabled"=$wgDis})
:local wpub [:tostr ($cfmMf->"wgpub")]
:if ([:len $wpub] > 0) do={
  :local cur ""
  :onerror e in={ :set cur [:tostr [/interface/wireguard/get [find where name=$wgIf] public-key]] } do={}
  :if ($cur != $wpub) do={
    :if ($cfmDry != true) do={ :onerror e in={ /ppp/secret/set [find where name="cfm:key"] comment="cfm-sys:key sv=0" } do={} }
    $cfmLog "WireGuard: Schluessel weicht vom gemeinsamen der Router ab - Secret-Push angefordert (D84)"
  }
}
# Backups: Antworten ins WG-Netz über die MGMT-VIP zum Master, der den Tunnel hält
:if ([:len $wgV] > 0) do={
  :local wrd "no"
  :if ($wgDis = "no") do={ :set wrd "yes" }
  $cfmEnsure m="/ip/route" k="rt:wg" p=({"dst-address"=$wnet;"gateway"=[:tostr ([$cfmNet $mv]->"gw")];"disabled"=$wrd})
}
$cfmEnsure m="/interface/list/member" k="ilm:wg-mgmt" n=({"list"="Z-mgmt";"interface"=$wgIf}) p=({"list"="Z-mgmt";"interface"=$wgIf})
# Eigene Adresse auf wg-admin: die verbundene Route fürs ganze WG-Subnetz entsteht daraus von
# selbst (kein Proxy-ARP, keine Route je Peer nötig - anders als im MGMT-Subnetz zuvor).
$cfmEnsure m="/ip/address" k="ip:wg" n=({"interface"=$wgIf}) p=({"address"=([:tostr ($wbase + 1)] . "/" . $wpfx);"interface"=$wgIf})
# WG-Subnetz zu cfm-mgmt: sonst erreichen Peers zwar andere Geräte (per Zone), aber nicht cm1s
# eigene Dienste (SSH/Winbox) - die richten sich nach cfm-mgmt, nicht nach der Zonen-Liste.
$cfmEnsure m="/ip/firewall/address-list" k="al:mgmt:wg" p=({"list"="cfm-mgmt";"address"=$wnet})
:foreach pname,pd in=($cfmWg->"peers") do={
  :local pk [:tostr ($pd->"pubkey")]
  :if ([:len $pk] > 0) do={
    :local paddr ([:tostr ($wbase + [:tonum ($pd->"addr")])] . "/32")
    $cfmEnsure m="/interface/wireguard/peers" k=("wgp:" . $pname) n=({"interface"=$wgIf;"public-key"=$pk}) p=({"interface"=$wgIf;"public-key"=$pk;"allowed-address"=$paddr})
  }
}
