# ============================================================
# cfm lib/mgr-netbox.rsc – Manager: Soll-Daten für den NetBox-Abgleich (TODO 55)
#   $cfmNetbox [ver=<N>]
#     wertet die Site-Daten aus (Standard: letztes Release, ver=0: work/) und schreibt sie als JSON:
#     state/netbox.json         Stand, global (domain, mgmtVlan), VLANs mit Netz und Gateway, feste Leases mit
#                               Adresse, WireGuard (Netz, Router, Peers, Standorte), Inventar
#     state/<name>/netbox.json  je Gerät das Hostfile (ohne ports), die Ports mit aufgelöstem Profil
#                               (untagged, tagged, bridge, disabled; "*" = portDefault), Bond-Slaves, MLAG
#     Rückgabe: Anzahl Geräte. tools/netbox-abgleich.py liest diese Dateien zusammen mit state/<name>/status.dat
#     und state/<name>/export.rsc (Ist) und vergleicht sie mit NetBox. Die Site-Daten selbst ändert nichts.
#     Die Daten werden je Gerät neu geladen: Ein Hostfile darf zentrale Daten überschreiben (Admin-Guide 4).
#   $cfmNetboxOut   für das Skript cfm-netbox-run (global.rsc netbox): $cfmNetbox, dann "CFMNB=<n>" und die Dateien
#                   für den Abgleich als Text (state/netbox.json, je Gerät netbox.json, status.dat, export.rsc; je Datei
#                   "##CFMF <pfad>" oder "##CFMF <pfad> NONE", je Stück "##CFMC <offset>" und die Daten). Der User
#                   cfm-netbox (ssh,read) darf /file/read nicht selbst, das Skript läuft mit den Rechten des Eigentümers
#   $cfmCheckNetbox w=<work>   Prüfung von global.rsc netbox (aus $cfmCheck): from, authorized_keys.cfm-netbox
# ============================================================

:global cfmNetbox do={
  :global cfmInvLoad; :global cfmLoadData; :global cfmMB; :global cfmRings; :global cfmFileEx; :global cfmG
  :global cfmVlans; :global cfmHost; :global cfmProfile; :global cfmLeases; :global cfmNet; :global cfmMlagOf
  :global cfmVids; :global cfmWg; :global cfmWrite; :global cfmEnrolled; :global cfmNow
  :local b [$cfmMB]
  :local v [:tonum ([$cfmRings]->"latest")]
  :if ([:len [:tostr $ver]] > 0) do={ :set v [:tonum $ver] }
  :local dir ($b . "/work")
  :if ($v > 0) do={ :set dir ($b . "/archive/v" . $v) }
  :if (![$cfmFileEx ($dir . "/global.rsc")]) do={ :error ("Stand nicht vorhanden: " . $dir) }
  :local inv [$cfmInvLoad]
  # hold=yes: Ein Apply auf diesem Gerät wartet, bis alle Hostfiles gelesen sind (cfmMgrData, $cfmLoadData)
  $cfmLoadData ver=$v hold="yes"
  # --- VLANs mit Netz und Gateway (bei VRRP die VIP) ---
  :local vl ({})
  :foreach vid,vv in=$cfmVlans do={
    :local e ({"name"=[:tostr ($vv->"name")];"zone"=[:tostr ($vv->"zone")];"l3"=([:tostr ($vv->"l3")] != "no");"dhcp"=[:tostr ($vv->"dhcp")];"isolate"=([:tostr ($vv->"isolate")] = "yes")})
    :local nn [$cfmNet $vid]
    :if ([:len ($nn->"net")] > 0) do={ :set ($e->"net") ($nn->"net"); :set ($e->"gw") [:tostr ($nn->"gw")] }
    :set ($vl->$vid) $e
  }
  # --- feste Leases (DN1.1) mit voller Adresse ---
  :local ls ({})
  :foreach vid,l in=$cfmLeases do={
    :local nn [$cfmNet $vid]
    :foreach ln,ld in=$l do={
      :local a ""
      :if ([:len ($nn->"net")] > 0) do={ :set a [:tostr (($nn->"addr") + [:tonum ($ld->"ip")])] }
      :set ($ls->[:len $ls]) ({"vlan"=$vid;"name"=$ln;"mac"=[:tostr ($ld->"mac")];"ip"=$a})
    }
  }
  # --- WireGuard (DR4.1-DR4.3): Router .1 im Netz, Peers, Standorte; Schlüssel nicht ---
  :local wg ({})
  :if ([:typeof $cfmWg] = "array") do={
    :local wn [:tostr ($cfmWg->"net")]
    :local pe ({})
    :if ([:len $wn] > 0) do={
      :set ($wg->"net") $wn
      :local wa [:toip [:pick $wn 0 [:find $wn "/"]]]
      :set ($wg->"router") [:tostr ($wa + 1)]
      :foreach pn,pd in=($cfmWg->"peers") do={ :set ($pe->$pn) [:tostr ($wa + [:tonum ($pd->"addr")])] }
    }
    :set ($wg->"peers") $pe
    :local st ({})
    :foreach sn,sd in=($cfmWg->"sites") do={
      :local sp [:tostr ($sd->"port")]
      :if ([:len $sp] = 0) do={ :set sp "13232" }
      :set ($st->$sn) ({"endpoint"=[:tostr ($sd->"endpoint")];"port"=$sp;"nets"=[:tostr ($sd->"nets")];"domain"=[:tostr ($sd->"domain")];"prepared"=([:len [:tostr ($sd->"pubkey")]] = 0)})
    }
    :set ($wg->"sites") $st
  }
  :local hl ({})
  :foreach hn,hd in=$inv do={
    :set ($hl->$hn) ({"serial"=[:tostr ($hd->"serial")];"role"=[:tostr ($hd->"role")];"ring"=[:tostr ($hd->"ring")];"ip"=[:tostr ($hd->"ip")];"enrolled"=[$cfmEnrolled $hd]})
  }
  :local g ({"domain"=[:tostr ($cfmG->"domain")];"mgmtVlan"=[:tostr ($cfmG->"mgmtVlan")]})
  $cfmWrite ($b . "/state/netbox.json") [:serialize to=json ({"v"=$v;"t"=[$cfmNow];"g"=$g;"vlans"=$vl;"leases"=$ls;"wg"=$wg;"inv"=$hl})]
  # --- je Gerät: Hostfile und Ports mit aufgelöstem Profil ---
  :local n 0
  :foreach hn,hd in=$inv do={
    :if ($n > 0) do={ $cfmLoadData ver=$v hold="yes" }
    :set cfmHost ({})
    :local hf ($dir . "/hosts/" . $hn . ".rsc")
    :local hasHf [$cfmFileEx $hf]
    :if ($hasHf) do={ [[:parse [/file/get $hf contents]]] }
    :local h ({"hostfile"=$hasHf})
    :foreach k,x in=$cfmHost do={ :if ($k != "ports") do={ :set ($h->$k) $x } }
    :local pl ({})
    :foreach p,spec in=($cfmHost->"ports") do={ :set ($pl->$p) [:tostr $spec] }
    :local def [:tostr ($cfmHost->"portDefault")]
    :if ([:len $def] > 0) do={ :set ($pl->"*") $def }
    # Slaves eines Bonds (DP2.1) bzw. MLAG-Bonds/-Peers (DP2.2) -> Name des Bonds; ports/portDefault gelten für sie nicht
    :local slv ({})
    :foreach bn,bd in=($cfmHost->"bonds") do={ :foreach s in=[:toarray ($bd->"slaves")] do={ :set ($slv->[:tostr $s]) $bn } }
    :local hm [$cfmMlagOf $hn]
    :if ([:len $hm] > 0) do={
      :set ($pl->($hm->"peer")) "*mlag-peer"
      :foreach s in=[:toarray ($hm->"peerSlaves")] do={ :set ($slv->[:tostr $s]) ($hm->"peer") }
      :foreach bn,bd in=($hm->"bonds") do={
        :set ($pl->$bn) [:tostr ($bd->"profile")]
        :foreach s in=[:toarray ($bd->"slaves")] do={ :set ($slv->[:tostr $s]) $bn }
      }
      :set ($h->"mlag") ({"pair"=($hm->"pair");"partner"=($hm->"partner");"peer"=($hm->"peer")})
    }
    :local po ({})
    :foreach p,spec in=$pl do={
      :local e ({"spec"=$spec})
      :onerror err in={
        :local pr
        :if ($spec = "*mlag-peer") do={ :set pr ({"tag"=[$cfmVids "*"];"untag"="";"bridge"=true;"disabled"=false}) } else={ :set pr [$cfmProfile $spec] }
        :local tl ""
        :foreach vid,m in=($pr->"tag") do={ :if ($m = 1) do={ :set tl ($tl . "," . $vid) } }
        :if ([:len $tl] > 0) do={ :set tl [:pick $tl 1 [:len $tl]] }
        :set ($e->"untag") [:tostr ($pr->"untag")]
        :set ($e->"tag") $tl
        :set ($e->"bridge") ($pr->"bridge")
        :set ($e->"disabled") ($pr->"disabled")
      } do={ :set ($e->"err") $err }
      :set ($po->$p) $e
    }
    :set ($h->"ports") $po
    :set ($h->"slaves") $slv
    $cfmWrite ($b . "/state/" . $hn . "/netbox.json") [:serialize to=json $h]
    :set n ($n + 1)
  }
  :global cfmMgrData; :set cfmMgrData 0
  :return $n
}

:global cfmNetboxOut do={
  :global cfmNetbox; :global cfmMB; :global cfmInvLoad
  :local n [$cfmNetbox]
  :put ("CFMNB=" . $n)
  :local b [$cfmMB]
  :local fl ({($b . "/state/netbox.json")})
  :foreach hn,hd in=[$cfmInvLoad] do={
    :foreach f in={"netbox.json";"status.dat";"export.rsc"} do={ :set ($fl->[:len $fl]) ($b . "/state/" . $hn . "/" . $f) }
  }
  :foreach f in=$fl do={
    :local sz -1
    :onerror e in={ :set sz [/file/get $f size] } do={}
    :if ($sz < 0) do={ :put ("##CFMF " . $f . " NONE") } else={
      :put ("##CFMF " . $f)
      :local o 0
      :while ($o < $sz) do={
        :put ("##CFMC " . $o)
        :put ([/file/read file=$f offset=$o chunk-size=30000 as-value]->"data")
        :set o ($o + 30000)
      }
    }
  }
}

:global cfmCheckNetbox do={
  :global cfmG
  :local err ({}); :local warn ({})
  :local nb ($cfmG->"netbox")
  :if ([:typeof $nb] = "nothing") do={ :return ({"err"=$err;"warn"=$warn}) }
  :if ([:typeof $nb] != "array") do={ :set ($err->0) "global.rsc: netbox muss ein Array sein ({\"from\"=…})"; :return ({"err"=$err;"warn"=$warn}) }
  :if ([:len $nb] = 0) do={ :return ({"err"=$err;"warn"=$warn}) }
  :if ([:len ($nb->"from")] = 0) do={ :set ($warn->[:len $warn]) "global.rsc: netbox ohne from - NetBox kann sich nicht anmelden (kein User cfm-netbox)" }
  :foreach a in=($nb->"from") do={
    :local ip [:tostr $a]
    :if ([:typeof [:find $ip "/"]] != "nil") do={ :set ip [:pick $ip 0 [:find $ip "/"]] }
    :if ([:typeof [:toip $ip]] != "ip") do={ :set ($err->[:len $err]) ("global.rsc: netbox from: " . $a . " ist keine IPv4-Adresse/kein Netz") }
  }
  :local ok false
  :onerror e in={ :set ok ([:len [/file/get ($w . "/authorized_keys.cfm-netbox") name]] > 0) } do={}
  :if (!$ok and [:len ($nb->"from")] > 0) do={ :set ($warn->[:len $warn]) "netbox: authorized_keys.cfm-netbox fehlt in work/ - NetBox kann sich nicht anmelden" }
  :return ({"err"=$err;"warn"=$warn})
}
