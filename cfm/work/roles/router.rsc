# ============================================================
# Rolle router – Inter-VLAN-Routing, DHCP, Zonen-Firewall, NAT, VRRP
#  NAT nur, wo die policy es kennzeichnet (D38): "*wan" = masquerade, "wan@a.b.c.d" = src-nat auf
#  diese Adresse (liegt bei VRRP auf vrrp<VID> des WAN-VLANs und wandert mit dem Master).
#  Freigabelisten (D39): policy-Ziel "allow:<Liste>" aus global.rsc "allow".
#  Hostfile-Parameter:
#   routerId=1..4   VRRP aktiv: reale IP .250+id, VIP .gw, Prio 210-10*id
#                   (weglassen = Einzelrouter, bekommt .gw direkt)
#   wan={"if"="vlan20";"gw"="192.168.20.1";"dns"="192.168.20.1"}
#     oder {"if"="ether1";"dhcp"="yes"}  [optional "addr"="x.x.x.x/nn"]
# ============================================================
:global cfmG; :global cfmVlans; :global cfmHost; :global cfmMf; :global cfmWg
:global cfmEnsure; :global cfmSet; :global cfmBlock; :global cfmNet; :global cfmLog
:global cfmFind; :global cfmRun; :global cfmTarget

:local vr ([:len [:tostr ($cfmHost->"routerId")]] > 0)
:local rid [:tonum ($cfmHost->"routerId")]
:local mv [:tostr ($cfmG->"mgmtVlan")]

# --- Switch-Chip (D37): Routing in der CPU. Mit l3-hw-offloading routet der Switch-Chip (CRS3xx/5xx)
#     an der Zonen-Firewall vorbei, und VRRP funktioniert laut MikroTik nur mit l3-hw-offloading=no.
#     Geräte ohne Switch-Menü (CHR) oder ohne die Eigenschaft bleiben unberührt. Nach Entfernen der
#     Rolle bleibt es aus (von Hand wieder einschalten). ---
:local sws ({})
:onerror e in={ :set sws [$cfmFind "/interface/ethernet/switch" N=({})] } do={ :set sws ({}) }
:foreach sw in=$sws do={
  :local sc [$cfmRun "/interface/ethernet/switch/get" I=$sw]
  :if ([:typeof ($sc->"l3-hw-offloading")] != "nothing") do={
    $cfmSet m="/interface/ethernet/switch" n=({"name"=($sc->"name")}) p=({"l3-hw-offloading"="no"})
  }
}

# --- Zonen (Interface-Listen) ---
:local zones ({})
:foreach vid,v in=$cfmVlans do={
  :if ([:tostr ($v->"l3")] != "no" and [:len [:tostr ($v->"zone")]] > 0) do={ :set ($zones->($v->"zone")) 1 }
}
:foreach z,x in=$zones do={ $cfmEnsure m="/interface/list" k=("il:Z-" . $z) n=({"name"=("Z-" . $z)}) p=({"name"=("Z-" . $z)}) }
$cfmEnsure m="/interface/list" k="il:WAN" n=({"name"="WAN"}) p=({"name"="WAN"})

# --- pro VLAN: Interface, Adressen, VRRP, DHCP ---
:foreach vid,v in=$cfmVlans do={
  :if ([:tostr ($v->"l3")] != "no") do={
    :local ifn ("vlan" . $vid)
    $cfmEnsure m="/interface/vlan" k=("vlan:" . $vid) n=({"name"=$ifn}) p=({"name"=$ifn;"interface"="bridge";"vlan-id"=[:tonum $vid]}) x=($v->"name")
    :local z [:tostr ($v->"zone")]
    :if ([:len $z] > 0) do={
      $cfmEnsure m="/interface/list/member" k=("ilm:" . $vid) n=({"list"=("Z-" . $z);"interface"=$ifn}) p=({"list"=("Z-" . $z);"interface"=$ifn})
    }
    :local nn [$cfmNet $vid]
    :if ([:len ($nn->"net")] > 0) do={
      :local gw ($nn->"gw")
      :local gwIf $ifn
      :if ($vr) do={
        :if ($vid != $mv) do={
          $cfmEnsure m="/ip/address" k=("ip:" . $vid) n=({"interface"=$ifn}) p=({"address"=([:tostr (($nn->"addr") + 250 + $rid)] . "/" . ($nn->"pfx"));"interface"=$ifn})
        }
        :local vrid [:tonum $vid]
        :if ($vrid > 255) do={ :set vrid [:tonum ($v->"vrid")] }
        :local om ""; :local ob ""
        :if ([:len [:tostr ($v->"dhcp")]] > 0 and [:tostr ($v->"dhcp")] != "no") do={
          :set om ("/ip/dhcp-server/enable [find name=dhcp" . $vid . "]")
          :set ob ("/ip/dhcp-server/disable [find name=dhcp" . $vid . "]")
        }
        $cfmEnsure m="/interface/vrrp" k=("vrrp:" . $vid) n=({"name"=("vrrp" . $vid)}) p=({"name"=("vrrp" . $vid);"interface"=$ifn;"vrid"=$vrid;"priority"=(210 - 10 * $rid);"interval"="400ms";"version"=3;"on-master"=$om;"on-backup"=$ob})
        :set gwIf ("vrrp" . $vid)
        $cfmEnsure m="/ip/address" k=("vip:" . $vid) n=({"interface"=$gwIf}) p=({"address"=([:tostr $gw] . "/32");"interface"=$gwIf})
      } else={
        :if ($vid != $mv or [:tostr $gw] != ($cfmMf->"ip")) do={
          $cfmEnsure m="/ip/address" k=("ip:" . $vid) n=({"interface"=$ifn;"address"=([:tostr $gw] . "/" . ($nn->"pfx"))}) p=({"address"=([:tostr $gw] . "/" . ($nn->"pfx"));"interface"=$ifn})
        }
      }
      # DHCP (nur wenn dhcp="a-b"); bei VRRP läuft er nur auf dem Master
      :local dh [:tostr ($v->"dhcp")]
      :if ([:len $dh] > 0 and $dh != "no" and [:tostr ($v->"onboard")] != "yes") do={
        :local s [:find $dh "-"]
        :local ra (($nn->"addr") + [:tonum [:pick $dh 0 $s]])
        :local rb (($nn->"addr") + [:tonum [:pick $dh ($s + 1) [:len $dh]]])
        $cfmEnsure m="/ip/pool" k=("pool:" . $vid) n=({"name"=("pool" . $vid)}) p=({"name"=("pool" . $vid);"ranges"=([:tostr $ra] . "-" . [:tostr $rb])})
        :local lt [:tostr ($v->"lease")]
        :if ([:len $lt] = 0) do={ :set lt "30m" }
        $cfmEnsure m="/ip/dhcp-server" k=("dhcp:" . $vid) n=({"name"=("dhcp" . $vid)}) p=({"name"=("dhcp" . $vid);"interface"=$ifn;"address-pool"=("pool" . $vid);"lease-time"=$lt}) a=({"disabled"="yes"})
        :local on "yes"
        :if ($vr) do={ :set on [:tostr [/interface/vrrp/get [find name=("vrrp" . $vid)] running]] ; :if ($on = "true") do={ :set on "yes" } else={ :set on "no" } }
        :local dis "yes"
        :if ($on = "yes") do={ :set dis "no" }
        $cfmSet m="/ip/dhcp-server" n=({"name"=("dhcp" . $vid)}) p=({"disabled"=$dis})
        :local dns [:tostr ($v->"dns")]
        :if ([:len $dns] = 0) do={ :set dns [:tostr $gw] }
        $cfmEnsure m="/ip/dhcp-server/network" k=("dn:" . $vid) n=({"address"=($nn->"net")}) p=({"address"=($nn->"net");"gateway"=[:tostr $gw];"dns-server"=$dns;"domain"=($cfmG->"domain")})
      }
    }
  }
}

# --- WAN / Uplink ---
:local wan ($cfmHost->"wan")
:local wdns ""
:if ([:typeof $wan] = "array") do={
  $cfmEnsure m="/interface/list/member" k="ilm:wan" n=({"list"="WAN";"interface"=($wan->"if")}) p=({"list"="WAN";"interface"=($wan->"if")})
  :if ([:len [:tostr ($wan->"addr")]] > 0) do={
    $cfmEnsure m="/ip/address" k="ip:wan" p=({"address"=($wan->"addr");"interface"=($wan->"if")})
  }
  :if ([:tostr ($wan->"dhcp")] = "yes") do={
    $cfmEnsure m="/ip/dhcp-client" k="dc:wan" n=({"interface"=($wan->"if")}) p=({"interface"=($wan->"if");"add-default-route"="yes";"use-peer-dns"="yes";"use-peer-ntp"="no"})
  } else={
    $cfmEnsure m="/ip/route" k="rt:wan" p=({"dst-address"="0.0.0.0/0";"gateway"=($wan->"gw")})
  }
  :set wdns [:tostr ($wan->"dns")]
}
$cfmSet m="/ip/dns" p=({"allow-remote-requests"="yes";"servers"=$wdns})
:local ntpSrv $wdns
:if ([:len $ntpSrv] = 0) do={ :set ntpSrv "0.de.pool.ntp.org,1.de.pool.ntp.org" }
$cfmSet m="/system/ntp/client" p=({"enabled"="yes";"servers"=$ntpSrv})
$cfmSet m="/system/ntp/server" p=({"enabled"="yes"})

# --- WireGuard-Fernzugang (D36): eigenes, nicht überlappendes Subnetz (wireguard.rsc "net") -
#     RouterOS legt sonst keine Route für "allowed-address" an, wenn sie in einem bereits
#     verbundenen Subnetz (z.B. MGMT) liegt, und ohne eigenes Subnetz bräuchte es zusätzlich
#     Proxy-ARP (frühere Version, siehe docs/TODO.md "Bekannte Fehler" zur Vorgeschichte). Peers
#     zählen trotzdem als Zone mgmt (volle mgmt-Rechte) über die Interface-Liste, unabhängig vom
#     Subnetz. Privater Schlüssel wird beim ersten Anlegen automatisch erzeugt (wie SSH-Host-Keys)
#     und bleibt auf dem Gerät - kein Vault-Eintrag nötig. Öffentlichen Schlüssel abrufen:
#     /interface/wireguard/print. Leere peers-Liste = Interface bleibt aus. ---
:local wgIf ""
:if ([:typeof $cfmWg] = "array" and [:len ($cfmWg->"peers")] > 0) do={
  :set wgIf "wg-admin"
  :local wnet [:tostr ($cfmWg->"net")]
  :local wslash [:find $wnet "/"]
  :local wbase [:toip [:pick $wnet 0 $wslash]]
  :local wpfx [:pick $wnet ($wslash + 1) [:len $wnet]]
  $cfmEnsure m="/interface/wireguard" k="wg:admin" n=({"name"=$wgIf}) p=({"name"=$wgIf;"listen-port"=[:tonum ($cfmWg->"listenPort")]})
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
}

# --- Adresslisten ---
:foreach n in={"10.0.0.0/8";"172.16.0.0/12";"192.168.0.0/16"} do={
  $cfmEnsure m="/ip/firewall/address-list" k=("al:priv:" . $n) p=({"list"="cfm-private";"address"=$n})
}
# MikroTik-Update-Server als FQDN (RouterOS löst sie dynamisch auf) – Ziel für policy "mtupdate"
:foreach h in=($cfmG->"onboard"->"mtHosts") do={
  $cfmEnsure m="/ip/firewall/address-list" k=("al:mt:" . $h) p=({"list"="cfm-mtupdate";"address"=$h})
}
# Freigabelisten (D39): Hostnamen löst RouterOS dynamisch auf, IPs/Netze gelten direkt
:foreach ln,lst in=($cfmG->"allow") do={
  :foreach h in=$lst do={
    $cfmEnsure m="/ip/firewall/address-list" k=("al:allow:" . $ln . ":" . $h) p=({"list"=("cfm-allow-" . $ln);"address"=$h})
  }
}
:foreach n in=($cfmG->"mgmtExtra") do={
  $cfmEnsure m="/ip/firewall/address-list" k=("al:mgmt:" . $n) p=({"list"="cfm-mgmt";"address"=$n})
}

# --- Firewall (Regelblock; eigene Regeln in Chains local-input / local-forward) ---
:local r ({})
:set ($r->[:len $r]) ({"chain"="input";"action"="accept";"connection-state"="established,related,untracked"})
:set ($r->[:len $r]) ({"chain"="input";"action"="drop";"connection-state"="invalid"})
:set ($r->[:len $r]) ({"chain"="input";"action"="accept";"protocol"="icmp"})
:if ([:len $wgIf] > 0) do={ :set ($r->[:len $r]) ({"chain"="input";"action"="accept";"protocol"="udp";"dst-port"=[:tostr ($cfmWg->"listenPort")]}) }
:if ($vr) do={ :set ($r->[:len $r]) ({"chain"="input";"action"="accept";"protocol"="vrrp"}) }
:foreach z in=[:toarray ($cfmG->"mgmtAccess")] do={
  :if (($zones->$z) = 1) do={ :set ($r->[:len $r]) ({"chain"="input";"action"="accept";"in-interface-list"=("Z-" . $z)}) }
}
:set ($r->[:len $r]) ({"chain"="input";"action"="accept";"src-address-list"="cfm-mgmt"})
:set ($r->[:len $r]) ({"chain"="input";"action"="accept";"in-interface-list"="!WAN";"protocol"="udp";"dst-port"="53,67,123"})
:set ($r->[:len $r]) ({"chain"="input";"action"="accept";"in-interface-list"="!WAN";"protocol"="tcp";"dst-port"="53"})
:set ($r->[:len $r]) ({"chain"="input";"action"="accept";"dst-address"="127.0.0.1"})
# Verbindungen des Geräts zu sich selbst (Router + Manager: Status-Abholung, Agent-Pull und
# Watchdog-Bestätigung an die eigene MGMT-IP) kommen nicht über Z-mgmt herein
:set ($r->[:len $r]) ({"chain"="input";"action"="accept";"src-address-type"="local"})
:set ($r->[:len $r]) ({"chain"="input";"action"="jump";"jump-target"="local-input"})
:set ($r->[:len $r]) ({"chain"="input";"action"="drop"})
:set ($r->[:len $r]) ({"chain"="forward";"action"="fasttrack-connection";"connection-state"="established,related"})
:set ($r->[:len $r]) ({"chain"="forward";"action"="accept";"connection-state"="established,related,untracked"})
:set ($r->[:len $r]) ({"chain"="forward";"action"="drop";"connection-state"="invalid"})
:local natR ({})
:local natZ ({})
:local natA ({})
:local inet ({})
:foreach from,to in=($cfmG->"policy") do={
  :if (($zones->$from) = 1) do={
    :foreach t0 in=[:toarray $to] do={
      :local pt [$cfmTarget $t0]
      :local t ($pt->"t")
      :local dl ""
      :if ($t = "*") do={
        :set ($r->[:len $r]) ({"chain"="forward";"action"="accept";"in-interface-list"=("Z-" . $from)})
        :set ($inet->$from) 1
      }
      :if ($t = "wan") do={
        :set dl "!cfm-private"
        :set ($r->[:len $r]) ({"chain"="forward";"action"="accept";"in-interface-list"=("Z-" . $from);"out-interface-list"="WAN";"dst-address-list"=$dl})
        :set ($inet->$from) 1
      }
      :if ($t = "mtupdate") do={
        :set dl "cfm-mtupdate"
        :set ($r->[:len $r]) ({"chain"="forward";"action"="accept";"in-interface-list"=("Z-" . $from);"out-interface-list"="WAN";"dst-address-list"=$dl})
      }
      # Freigabeliste: Ziele überall (Internet oder z.B. ein Proxy in einer anderen Zone)
      :if ([:pick $t 0 6] = "allow:") do={
        :set dl ("cfm-allow-" . [:pick $t 6 [:len $t]])
        :set ($r->[:len $r]) ({"chain"="forward";"action"="accept";"in-interface-list"=("Z-" . $from);"dst-address-list"=$dl})
      }
      :if (($zones->$t) = 1) do={ :set ($r->[:len $r]) ({"chain"="forward";"action"="accept";"in-interface-list"=("Z-" . $from);"out-interface-list"=("Z-" . $t)}) }
      # NAT nur Richtung WAN und nur, wenn gekennzeichnet
      :local nat [:tostr ($pt->"nat")]
      :if ([:len $nat] > 0 and [:len $dl] > 0) do={
        :set ($natZ->$from) 1
        :local nr ({"chain"="srcnat";"src-address-list"=("cfm-z-" . $from);"out-interface-list"="WAN";"dst-address-list"=$dl})
        :if ($nat = "masq") do={ :set ($nr->"action") "masquerade" } else={
          :set ($nr->"action") "src-nat"; :set ($nr->"to-addresses") $nat; :set ($natA->$nat) 1
        }
        :set ($natR->[:len $natR]) $nr
      }
    }
  }
}
:set ($r->[:len $r]) ({"chain"="forward";"action"="accept";"connection-nat-state"="dstnat"})
:set ($r->[:len $r]) ({"chain"="forward";"action"="jump";"jump-target"="local-forward"})
:set ($r->[:len $r]) ({"chain"="forward";"action"="drop"})
$cfmBlock m="/ip/firewall/filter" k="fw" l=$r

# --- NAT (D38) ---
# Quellnetze je Zone mit NAT als Adressliste für die srcnat-Regeln
:foreach vid,v in=$cfmVlans do={
  :local z [:tostr ($v->"zone")]
  :if ([:tostr ($v->"l3")] != "no" and ($natZ->$z) = 1) do={
    :local nn [$cfmNet $vid]
    :if ([:len ($nn->"net")] > 0) do={
      $cfmEnsure m="/ip/firewall/address-list" k=("al:z:" . $z . ":" . $vid) p=({"list"=("cfm-z-" . $z);"address"=($nn->"net")})
    }
  }
}
:if ([:len $wgIf] > 0 and ($natZ->"mgmt") = 1) do={
  $cfmEnsure m="/ip/firewall/address-list" k="al:z:mgmt:wg" p=({"list"="cfm-z-mgmt";"address"=($cfmWg->"net")})
}
# Feste NAT-Adressen: bei VRRP auf vrrp<VID> des WAN-VLANs (nur auf dem Master aktiv), sonst am WAN
:foreach na,x in=$natA do={
  :local nif [:tostr ($wan->"if")]
  :if ($vr and [:pick $nif 0 4] = "vlan") do={
    :local wv [:pick $nif 4 [:len $nif]]
    :if ([:typeof ($cfmVlans->$wv)] = "array" and [:tostr ($cfmVlans->$wv->"l3")] != "no") do={ :set nif ("vrrp" . $wv) }
  }
  :if ([:len $nif] > 0) do={
    $cfmEnsure m="/ip/address" k=("ip:nat:" . $na) n=({"interface"=$nif;"address"=($na . "/32")}) p=({"address"=($na . "/32");"interface"=$nif})
  }
}
# DNS-Umleitung (D39) für Zonen ohne allgemeinen Internetzugang: fest eingebaute externe
# DNS-Server landen beim Router, der dieselben Antworten wie für die Freigabelisten nutzt
:foreach z,x in=$zones do={
  :if ([:typeof ($inet->$z)] = "nothing") do={
    :foreach pr in={"udp";"tcp"} do={
      :set ($natR->[:len $natR]) ({"chain"="dstnat";"action"="redirect";"to-ports"="53";"in-interface-list"=("Z-" . $z);"protocol"=$pr;"dst-port"="53";"dst-address-list"="!cfm-private"})
    }
  }
}
$cfmBlock m="/ip/firewall/nat" k="nat" l=$natR
