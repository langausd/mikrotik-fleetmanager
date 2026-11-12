# ============================================================
# cfm lib/router.site.rsc – Feature-Modul der Rolle router (DG4.6): Standortkopplung per WireGuard (DR4.3).
# router.rsc lädt es per $cfmFeat nur mit "sites" in wireguard.rsc. Je entferntem Standort:
#  * Interface wg-site-<name> (eigener listen-port, Standard 13232) in der Interface-Liste Z-<name> - der Standort
#    ist eine Zone wie jede andere, die Policy in global.rsc entscheidet (Zeile "<name>"=... und Ziel <name>)
#  * ein Peer mit dessen öffentlichem Schlüssel, allowed-address = seine Netze, Keepalive 25 s; der Endpoint
#    (Name:Port) wird über den ersten Upstream aufgelöst (:resolve server=), nicht über den Router-DNS - sonst
#    liefe ein Name in einer weitergeleiteten Domain in den noch nicht stehenden Tunnel. Das Skript cfm-wgsite
#    löst Namen alle 2 min erneut auf und setzt die Adresse nach einem DynDNS-Wechsel neu
#  * Routen zu seinen Netzen über das Interface; bei VRRP zusätzlich mit Distanz 10 über die MGMT-VIP: Auf den
#    Backups ist der Tunnel aus (on-master/on-backup wie wg-admin), die Route über das Interface inaktiv, die
#    über die VIP greift - ohne Umschalten per Skript
#  * DNS-Weiterleitung seiner Domain an seinen Resolver ("domain" -> "dns", FWD mit match-subdomain)
#  Ohne pubkey (Gegenstelle noch nicht eingerichtet) ist der Standort nur vorbereitet: Interface, Schlüssel, Zone
#  und Portfreigabe ja, Routen und DNS-Weiterleitung nein - sonst endete Verkehr zu seinen Netzen im Tunnel ohne
#  Peer, auch wenn sie bis zur Umstellung anders erreichbar sind (z.B. über ein VPN des Internet-Routers, DR4.3.1)
# Alle Router eines Standorts haben denselben privaten Schlüssel (Vault wg.site, Secret-Push; öffentlich
# "wgsitepub" im Manifest). Weicht ein Interface ab, fordert die Rolle den Secret-Push an (sv=0, wie DR4.2).
# Von der Rolle: cfmCtx->"wgV" = VLAN des WAN bei VRRP (leer = Einzelrouter), "mv" = MGMT-VLAN, "up" = Upstream
# ============================================================
:global cfmWg; :global cfmMf; :global cfmCtx; :global cfmDry
:global cfmEnsure; :global cfmNet; :global cfmLog; :global cfmWarn
:local wgV [:tostr ($cfmCtx->"wgV")]
:local mv [:tostr ($cfmCtx->"mv")]
:local up [:tostr ($cfmCtx->"up")]
# bei VRRP nur auf dem Master des WAN-VLANs an (wie wg-admin; danach schalten on-master/on-backup um)
:local wgDis "no"
:if ([:len $wgV] > 0) do={
  :set wgDis "yes"
  :local vi [/interface/vrrp/find where name=("vrrp" . $wgV)]
  :if ([:len $vi] > 0) do={ :if ([:tostr [/interface/vrrp/get [:pick $vi 0] running]] = "true") do={ :set wgDis "no" } }
}
:local spub [:tostr ($cfmMf->"wgsitepub")]
:local asked false
:local names ({})
:foreach sn,sd in=($cfmWg->"sites") do={
  :local ifn ("wg-site-" . $sn)
  :local port [:tonum ($sd->"port")]
  :if ([:typeof $port] != "num") do={ :set port 13232 }
  $cfmEnsure m="/interface/wireguard" k=("wg:site:" . $sn) n=({"name"=$ifn}) p=({"name"=$ifn;"listen-port"=$port;"disabled"=$wgDis})
  :if ([:len $spub] > 0 and !$asked) do={
    :local cur ""
    :onerror e in={ :set cur [:tostr [/interface/wireguard/get [find where name=$ifn] public-key]] } do={}
    :if ($cur != $spub) do={
      :set asked true
      :if ($cfmDry != true) do={ :onerror e in={ /ppp/secret/set [find where name="cfm:key"] comment="cfm-sys:key sv=0" } do={} }
      $cfmLog ("Standortkopplung: Schluessel von " . $ifn . " weicht vom gemeinsamen der Router ab - Secret-Push angefordert (DR4.3)")
    }
  }
  $cfmEnsure m="/interface/list/member" k=("ilm:site:" . $sn) n=({"list"=("Z-" . $sn);"interface"=$ifn}) p=({"list"=("Z-" . $sn);"interface"=$ifn})
  # Peer: ohne pubkey (Gegenstelle noch nicht eingerichtet) bleibt das Interface ohne Peer
  :local pk [:tostr ($sd->"pubkey")]
  :local aa ""
  :foreach n in=($sd->"nets") do={ :if ([:len $aa] > 0) do={ :set aa ($aa . ",") }; :set aa ($aa . [:tostr $n]) }
  :if ([:len $pk] > 0 and [:len $aa] > 0) do={
    :local pp ({"interface"=$ifn;"public-key"=$pk;"allowed-address"=$aa;"persistent-keepalive"="25s"})
    :local ep [:tostr ($sd->"endpoint")]
    :if ([:len $ep] > 0) do={
      :local c [:find $ep ":"]
      :local eh $ep
      :local epo 13232
      :if ([:typeof $c] != "nil") do={ :set eh [:pick $ep 0 $c]; :set epo [:tonum [:pick $ep ($c + 1) [:len $ep]]] }
      :set ($pp->"endpoint-port") $epo
      :if ([:typeof [:toip $eh]] = "ip") do={ :set ($pp->"endpoint-address") $eh } else={
        :set ($names->[:len $names]) ({("wgp:site:" . $sn);$eh})
        :local rip ""
        :onerror e in={ :if ([:len $up] > 0) do={ :set rip [:tostr [:resolve domain-name=$eh server=$up]] } else={ :set rip [:tostr [:resolve domain-name=$eh]] } } do={}
        :if ([:len $rip] > 0) do={ :set ($pp->"endpoint-address") $rip } else={ $cfmWarn ("Standort " . $sn . ": Endpoint " . $eh . " nicht aufloesbar - Tunnel wartet auf die Gegenstelle bzw. cfm-wgsite") }
      }
    }
    $cfmEnsure m="/interface/wireguard/peers" k=("wgp:site:" . $sn) n=({"interface"=$ifn;"public-key"=$pk}) p=$pp
  } else={
    :if ([:len $pk] = 0) do={ $cfmWarn ("Standort " . $sn . ": pubkey fehlt - nur vorbereitet, ohne Routen und DNS (eigener Schluessel: wgsitepub in \$cfmShow)") }
  }
  # Routen zu den Netzen des Standorts; bei VRRP Rückfall über die MGMT-VIP (Distanz 10), solange der Tunnel hier aus ist.
  # Nur mit pubkey (DR4.3.1): vorher hat der Tunnel keine Gegenstelle
  :if ([:len $pk] > 0) do={
    :local i 0
    :foreach n in=($sd->"nets") do={
      $cfmEnsure m="/ip/route" k=("rts:" . $sn . ":" . $i) p=({"dst-address"=[:tostr $n];"gateway"=$ifn;"distance"=1})
      :if ([:len $wgV] > 0) do={
        $cfmEnsure m="/ip/route" k=("rtb:" . $sn . ":" . $i) p=({"dst-address"=[:tostr $n];"gateway"=[:tostr ([$cfmNet $mv]->"gw")];"distance"=10})
      }
      :set i ($i + 1)
    }
    # Namen des Standorts: seine Domain samt Subdomains an seinen Resolver durch den Tunnel
    :local dom [:tostr ($sd->"domain")]
    :local dns [:tostr ($sd->"dns")]
    :if ([:len $dom] > 0 and [:len $dns] > 0) do={
      $cfmEnsure m="/ip/dns/static" k=("dnssite:" . $sn) n=({"name"=$dom;"type"="FWD"}) p=({"name"=$dom;"type"="FWD";"forward-to"=$dns;"match-subdomain"="yes"})
    }
  }
}
# Endpoint-Namen regelmäßig neu auflösen (DynDNS der Gegenstelle): Skript + Scheduler nur, wenn es Namen gibt;
# sonst räumt die GC beides weg
:if ([:len $names] > 0) do={
  :local lst ""
  :foreach e in=$names do={ :if ([:len $lst] > 0) do={ :set lst ($lst . ";") }; :set lst ($lst . "{\"" . ($e->0) . "\";\"" . ($e->1) . "\"}") }
  :local src "# cfm (Rolle router, DR4.3): Endpoint-Namen der Standortkopplung aufloesen, Adresse bei Aenderung setzen. Jeder Apply schreibt es neu\n"
  :set src ($src . ":local up \"" . $up . "\"\n:foreach e in={" . $lst . "} do={\n  :onerror err in={\n    :local ip\n    :if ([:len \$up] > 0) do={ :set ip [:resolve domain-name=(\$e->1) server=\$up] } else={ :set ip [:resolve domain-name=(\$e->1)] }\n    :local i [/interface/wireguard/peers/find where comment~(\"^cfm:\" . (\$e->0))]\n    :if ([:len \$i] > 0) do={\n      :if ([:tostr [/interface/wireguard/peers/get \$i endpoint-address]] != [:tostr \$ip]) do={ /interface/wireguard/peers/set \$i endpoint-address=\$ip; :log info (\"cfm: Standortkopplung: \" . (\$e->1) . \" -> \" . \$ip) }\n    }\n  } do={}\n}\n")
  $cfmEnsure m="/system/script" k="sys:wgsite" n=({"name"="cfm-wgsite"}) p=({"name"="cfm-wgsite";"source"=$src;"policy"="read,write,test"})
  $cfmEnsure m="/system/scheduler" k="sys:wgsite" n=({"name"="cfm-wgsite"}) p=({"name"="cfm-wgsite";"interval"="2m";"start-time"="startup";"on-event"="/system/script/run cfm-wgsite";"policy"="read,write,test"})
}
