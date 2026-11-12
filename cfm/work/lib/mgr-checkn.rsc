# ============================================================
# cfm lib/mgr-checkn.rsc – Manager-Funktionen: WireGuard-Teil der inhaltlichen Prüfung
#   $cfmCheckNet z=<Zonen>   prüft wireguard.rsc (Admin-Peers DR4.1/DR4.2, Standortkopplung DR4.3, DynDNS DR4.4)
#                            und asymRouting in vlans.rsc (DR3.2, DR3.2.1 - Netze im Vergleich mit den Standorten)
#                            -> {"err"={..};"warn"={..}}
#   Aufruf nur aus $cfmCheck (lib/mgr-check.rsc), nachdem der die Daten geladen hat. Eigene Datei,
#   weil /file get nur ca. 60 KB liest (wie lib/mgr-checkw.rsc, DM1.1); $cfmCheck lädt sie aus demselben Stand nach.
# ============================================================

:global cfmCheckNet do={
  :global cfmWg; :global cfmVlans; :global cfmG; :global cfmNet; :global cfmVaultGet; :global cfmTarget
  :local err ({}); :local warn ({})
  # WireGuard (Peers zählen als Zone mgmt): Pubkey Pflicht, Tunnel-Adressen eindeutig, eigenes
  # Subnetz darf nicht mit einem VLAN aus vlans.rsc überlappen (sonst wieder Proxy-ARP-Ärger)
  :local wgAddrs ({})
  :if ([:len ($cfmWg->"peers")] > 0 and [:len [:tostr ($cfmWg->"net")]] = 0) do={
    :set ($err->[:len $err]) ("wireguard.rsc: peers vorhanden, aber net fehlt")
  }
  :foreach vid,v in=$cfmVlans do={
    :local vn [:tostr (([$cfmNet $vid])->"net")]
    :if ([:len $vn] > 0 and $vn = [:tostr ($cfmWg->"net")]) do={ :set ($err->[:len $err]) ("wireguard.rsc: net " . $vn . " überlappt mit VLAN " . $vid) }
  }
  :foreach k,p in=($cfmWg->"peers") do={
    :if ([:len [:tostr ($p->"pubkey")]] = 0) do={ :set ($err->[:len $err]) ("wireguard.rsc: peer " . $k . ": pubkey fehlt") }
    :local ad [:tostr ($p->"addr")]
    :if ([:len $ad] = 0) do={ :set ($err->[:len $err]) ("wireguard.rsc: peer " . $k . ": addr fehlt") } else={
      :if ([:typeof ($wgAddrs->$ad)] != "nothing") do={ :set ($err->[:len $err]) ("wireguard.rsc: peer " . $k . ": addr " . $ad . " doppelt vergeben (" . ($wgAddrs->$ad) . ")") }
      :set ($wgAddrs->$ad) $k
    }
  }
  # Standortkopplung (DR4.3): Name = Zonenname (klein, keine vorhandene Zone), Netze gültig und fremd, Port je
  # Standort eindeutig (auch gegen listenPort), Endpoint als Name:Port oder IP:Port, domain nur mit dns in den Netzen;
  # ohne pubkey nur eine Warnung (Gegenstelle noch nicht eingerichtet)
  :local sPorts ({})
  :local lp [:tostr ($cfmWg->"listenPort")]
  :if ([:len ($cfmWg->"peers")] > 0 and [:len $lp] > 0) do={ :set ($sPorts->$lp) "listenPort" }
  :local cidrOk do={ :local x [:tostr $1]; :local sl [:find $x "/"]; :if ([:typeof $sl] = "nil") do={ :return false }; :local pf [:tonum [:pick $x ($sl + 1) [:len $x]]]; :return ([:typeof [:toip [:pick $x 0 $sl]]] = "ip" and [:typeof $pf] = "num" and $pf >= 0 and $pf <= 32) }
  :foreach sn,sd in=($cfmWg->"sites") do={
    :local sw ("wireguard.rsc: sites " . $sn . ": ")
    :if (!($sn ~ "^[a-z0-9]([a-z0-9-]*[a-z0-9])?\$")) do={ :set ($err->[:len $err]) ($sw . "Name nur aus Kleinbuchstaben, Ziffern und \"-\" (wird Zone und Interface wg-site-<Name>)") }
    :if ([:typeof ($z->$sn)] != "nothing" or $sn = "wan" or $sn = "mtupdate") do={ :set ($err->[:len $err]) ($sw . "Name ist schon eine Zone in vlans.rsc") }
    :foreach k,v in=$sd do={ :if (!($k ~ "^(pubkey|endpoint|port|nets|domain|dns)\$")) do={ :set ($warn->[:len $warn]) ($sw . "unbekannter Schlüssel " . $k . " (pubkey, endpoint, port, nets, domain, dns)") } }
    :if ([:len [:tostr ($sd->"pubkey")]] = 0) do={ :set ($warn->[:len $warn]) ($sw . "pubkey fehlt - nur vorbereitet (Schlüssel, Zone, Port), ohne Routen und DNS-Weiterleitung, bis der Schlüssel des anderen Standorts eingetragen ist (DR4.3.1)") }
    :if ([:len ($sd->"nets")] = 0) do={ :set ($err->[:len $err]) ($sw . "nets fehlt (Netze des Standorts, z.B. {\"192.168.20.0/24\"})") }
    :foreach n in=($sd->"nets") do={
      :if (![$cidrOk $n]) do={ :set ($err->[:len $err]) ($sw . "nets: " . $n . " ist kein Netz (a.b.c.d/nn)") } else={
        :foreach vid,v in=$cfmVlans do={ :if ([:tostr (([$cfmNet $vid])->"net")] = [:tostr $n]) do={ :set ($err->[:len $err]) ($sw . "nets: " . $n . " ist das eigene VLAN " . $vid) } }
        :if ([:tostr $n] = [:tostr ($cfmWg->"net")]) do={ :set ($err->[:len $err]) ($sw . "nets: " . $n . " ist das WG-Netz der Admin-Peers") }
      }
    }
    :local sp [:tostr ($sd->"port")]
    :if ([:len $sp] = 0) do={ :set sp "13232" }
    :if (!($sp ~ "^[0-9]+\$")) do={ :set ($err->[:len $err]) ($sw . "port " . $sp . " ist keine Zahl") } else={
      :if ([:typeof ($sPorts->$sp)] != "nothing") do={ :set ($err->[:len $err]) ($sw . "port " . $sp . " schon bei " . ($sPorts->$sp) . " - je Standort ein eigener Port") }
      :set ($sPorts->$sp) $sn
    }
    :local ep [:tostr ($sd->"endpoint")]
    :if ([:len $ep] > 0) do={
      :local c [:find $ep ":"]
      :if ([:typeof $c] = "nil") do={ :set ($warn->[:len $warn]) ($sw . "endpoint ohne Port - es gilt 13232") } else={
        :local eh [:pick $ep 0 $c]
        :if (!([:pick $ep ($c + 1) [:len $ep]] ~ "^[0-9]+\$")) do={ :set ($err->[:len $err]) ($sw . "endpoint " . $ep . ": Port ist keine Zahl") }
        :if ([:typeof [:toip $eh]] != "ip" and !($eh ~ "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)+\\.?\$")) do={ :set ($err->[:len $err]) ($sw . "endpoint " . $ep . ": weder Adresse noch Name") }
      }
    } else={ :set ($warn->[:len $warn]) ($sw . "endpoint fehlt - dieser Standort wartet auf den Verbindungsaufbau der Gegenstelle") }
    :local sdom [:tostr ($sd->"domain")]
    :local sdns [:tostr ($sd->"dns")]
    :if ([:len $sdom] > 0) do={
      :if (!($sdom ~ "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)+\\.?\$")) do={ :set ($err->[:len $err]) ($sw . "domain " . $sdom . " ist kein Domainname") }
      :if ([:len $sdns] = 0) do={ :set ($err->[:len $err]) ($sw . "domain braucht dns (Resolver des Standorts, z.B. dessen MGMT- oder LAN-Gateway)") }
      :if ($sdom = [:tostr ($cfmG->"domain")]) do={ :set ($err->[:len $err]) ($sw . "domain ist die eigene Domain (global.rsc)") }
    }
    :if ([:len $sdns] > 0 and [:typeof [:toip $sdns]] != "ip") do={ :set ($err->[:len $err]) ($sw . "dns " . $sdns . " ist keine IPv4-Adresse") }
  }
  # DynDNS (DR4.4): self.ddns type dyndns2 (url, name), cloud oder api (vorgemerkt)
  :local sf ($cfmWg->"self")
  :if ([:typeof $sf] = "array") do={
    :foreach k,v in=$sf do={ :if (!($k ~ "^(name|ddns)\$")) do={ :set ($warn->[:len $warn]) ("wireguard.rsc: self: unbekannter Schlüssel " . $k . " (name, ddns)") } }
    :local dd ($sf->"ddns")
    :if ([:typeof $dd] = "array") do={
      :local dw "wireguard.rsc: self.ddns: "
      :foreach k,v in=$dd do={ :if (!($k ~ "^(type|url|name|ipUrl|interval)\$")) do={ :set ($warn->[:len $warn]) ($dw . "unbekannter Schlüssel " . $k . " (type, url, name, ipUrl, interval)") } }
      :local dt [:tostr ($dd->"type")]
      :if ([:len $dt] > 0 and !($dt ~ "^(dyndns2|cloud|api)\$")) do={ :set ($err->[:len $err]) ($dw . "type " . $dt . " (dyndns2, cloud oder api)") }
      :if ($dt = "dyndns2") do={
        :if (!([:tostr ($dd->"url")] ~ "^https?://")) do={ :set ($err->[:len $err]) ($dw . "url fehlt oder ist keine http(s)-URL (Update-URL des Anbieters, z.B. https://update.dedyn.io/nic/update)") }
        :if ([:len [:tostr ($dd->"name")]] = 0) do={ :set ($err->[:len $err]) ($dw . "name fehlt (der eigene DynDNS-Name)") }
        :if ([:len [$cfmVaultGet "ddns.auth"]] = 0) do={ :set ($warn->[:len $warn]) ($dw . "kein Zugang im Vault - \$cfmSecret key=ddns.auth value=\"user:passwort\"") }
        :local iu [:tostr ($dd->"ipUrl")]
        :if ([:len $iu] > 0 and !($iu ~ "^https?://")) do={ :set ($err->[:len $err]) ($dw . "ipUrl ist keine http(s)-URL") }
        :local di [:tostr ($dd->"interval")]
        :if ([:len $di] > 0 and [:typeof [:totime $di]] != "time") do={ :set ($err->[:len $err]) ($dw . "interval " . $di . " ist keine Zeitangabe (z.B. 5m)") }
      }
      :if ($dt = "api") do={ :set ($warn->[:len $warn]) ($dw . "type api ist vorgemerkt, noch nicht umgesetzt - kein Update") }
      :if ($dt = "cloud" and [:len ($cfmWg->"sites")] > 0) do={ :set ($warn->[:len $warn]) ($dw . "cloud: der Name gilt je Gerät (<SN>.sn.mynetname.net) - bei VRRP zeigt er auf einen Router, nicht auf den Master") }
    }
  }
  # Asymmetrisches Routing (DR3.2, DR3.2.1): "internet" und/oder Netze hinter dem Internet-Router, als Wert oder Liste.
  # "internet" läuft ohne conntrack - mit NAT der Zone setzen die Router kein notrack (Warnung, Hostfiles können die
  # policy überschreiben), NTP-Umleitung und Limit greifen dafür nicht bzw. nur im Upload. Ein Netz, das ein
  # Standort-Tunnel mit pubkey führt, lassen die Router aus (Warnung: Eintrag aufräumen)
  :foreach vid,v in=$cfmVlans do={
    :local ar ($v->"asymRouting")
    :if ([:typeof $ar] != "array") do={ :local a1 [:tostr $ar]; :set ar ({}); :if ([:len $a1] > 0) do={ :set ($ar->0) $a1 } }
    :if ([:len $ar] > 0) do={
      :local vw ("vlans.rsc: VLAN " . $vid . ": asymRouting ")
      :local inet false
      :foreach a in=$ar do={
        :local as [:tostr $a]
        :if ($as = "internet") do={ :set inet true } else={
          :if (![$cidrOk $as]) do={ :set ($err->[:len $err]) ($vw . $as . " ist weder internet noch ein Netz (a.b.c.d/nn)") } else={
            :foreach vid2,v2 in=$cfmVlans do={ :if ([:tostr (([$cfmNet $vid2])->"net")] = $as) do={ :set ($err->[:len $err]) ($vw . $as . " ist das eigene VLAN " . $vid2) } }
            :if ($as = [:tostr ($cfmWg->"net")]) do={ :set ($err->[:len $err]) ($vw . $as . " ist das WG-Netz der Admin-Peers") }
            :foreach sn,sd in=($cfmWg->"sites") do={
              :foreach n in=($sd->"nets") do={
                :if ([:tostr $n] = $as and [:len [:tostr ($sd->"pubkey")]] > 0) do={ :set ($warn->[:len $warn]) ($vw . $as . " geht durch den Standort-Tunnel " . $sn . " - die Router setzen dafür kein notrack, Eintrag entfernen") }
              }
            }
          }
        }
      }
      :if ([:tostr ($v->"l3")] = "no") do={ :set ($warn->[:len $warn]) ($vw . "ohne Router (l3=no) wirkt nicht") }
      :if ([:len [:tostr ($v->"limit")]] > 0 or [:len [:tostr ($v->"limitClient")]] > 0) do={ :set ($warn->[:len $warn]) ($vw . "+ limit: bremst diesen Verkehr nur im Upload (Antworten laufen am Router vorbei)") }
      :if ($inet) do={
        :if ([:tostr ($v->"ntp")] = "redirect") do={ :set ($warn->[:len $warn]) ($vw . "+ ntp redirect: NTP an Server im Internet wird nicht umgeleitet") }
        :local z [:tostr ($v->"zone")]
        :foreach t0 in=[:toarray ($cfmG->"policy"->$z)] do={
          :local pt [$cfmTarget $t0]
          :if ([:len [:tostr ($pt->"nat")]] > 0) do={ :set ($warn->[:len $warn]) ($vw . "internet wirkt nicht, solange die Zone " . $z . " NAT hat (" . $t0 . ") - die Router setzen dann kein notrack") }
        }
      }
    }
  }
  :return ({"err"=$err;"warn"=$warn})
}
