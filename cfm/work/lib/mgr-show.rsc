# ============================================================
# cfm lib/mgr-show.rsc – Manager: effektive Konfiguration und Unterschiede (TODO 12, D61)
#   $cfmShow host=<n> [ver=<N>] [objects=yes]
#     ohne objects: zusammengeführte Daten des Geräts aus work/ (ver=N: aus Release N) - Inventar,
#     Rollen, Hostfile, Ports mit aufgelösten Profilen, VLANs auf dem Gerät, WLAN-Anteil, Leases
#     objects=yes: Soll-Objekte per Probelauf auf dem Gerät (wie $cfmPlan: Stand work/, ohne post.rsc)
#   $cfmDiff [ver=<A>] [to=<B>|work]
#     Dateien, die sich zwischen zwei Ständen unterscheiden (Standard: letztes Release -> work/, also
#     "was ändert das nächste Release"), betroffene Geräte, für Datendateien die geänderten Zeilen
# ============================================================

:global cfmShow do={
  :global cfmInvLoad; :global cfmLoadData; :global cfmMB; :global cfmRings; :global cfmEnrolled
  :global cfmFileEx; :global cfmG; :global cfmVlans; :global cfmHost; :global cfmProfile; :global cfmWifi
  :global cfmLeases; :global cfmNet; :global cfmPlan; :global cfmPad
  :if ([:len $host] = 0) do={ :error "Aufruf: \$cfmShow host=<name> [ver=<N>] [objects=yes]" }
  :local d ([$cfmInvLoad]->$host)
  :if ([:typeof $d] != "array") do={ :error ("unbekannter Host " . $host) }
  :if ($objects = "yes") do={ $cfmPlan host=$host show="yes"; :return "" }
  :local b [$cfmMB]
  :local v 0
  :if ([:len [:tostr $ver]] > 0) do={ :set v [:tonum $ver] }
  :local dir ($b . "/work")
  :if ($v > 0) do={ :set dir ($b . "/archive/v" . $v) }
  :if (![$cfmFileEx ($dir . "/global.rsc")]) do={ :error ("Stand nicht vorhanden: " . $dir) }
  $cfmLoadData ver=$v
  :set cfmHost ({})
  :local hasHf [$cfmFileEx ($dir . "/hosts/" . $host . ".rsc")]
  :if ($hasHf) do={ /import file-name=($dir . "/hosts/" . $host . ".rsc") verbose=no }
  :local rl ("," . [:tostr ($d->"role")] . ",")
  :local ring [:tostr ($d->"ring")]
  :if ([:len $ring] = 0) do={ :set ring "2" }
  :local en "nein"
  :if ([$cfmEnrolled $d]) do={ :set en "ja" }
  :local src "work/"
  :if ($v > 0) do={ :set src ("v" . $v) }
  :put ($host . " (" . $src . "): Rollen base," . [:tostr ($d->"role")] . "  Ring " . $ring . " (v" . ([$cfmRings]->("r" . $ring)) . ")  MGMT " . [:tostr ($d->"ip")] . "  Seriennr. " . [:tostr ($d->"serial")] . "  aufgenommen: " . $en)
  :if (!$hasHf) do={ :put "  kein Hostfile" }
  :foreach k,x in=$cfmHost do={ :if ($k != "ports" and $k != "portDefault") do={ :put ("  " . [$cfmPad $k 14] . [:tostr $x]) } }
  # --- Ports mit aufgelösten Profilen; VLANs sammeln ---
  :local vl ({})
  :local pl ({})
  :local def [:tostr ($cfmHost->"portDefault")]
  :if ([:len $def] > 0) do={ :set ($pl->"(übrige)") $def }
  :foreach p,spec in=($cfmHost->"ports") do={ :set ($pl->$p) $spec }
  :put "Ports"
  :foreach p,spec in=$pl do={
    :local t ""
    :onerror e in={
      :local pr [$cfmProfile $spec]
      :if (!($pr->"bridge")) do={ :set t "nicht in der Bridge" } else={
        :local u [:tostr ($pr->"untag")]
        :if ([:len $u] > 0) do={ :set t ("untagged " . $u); :set ($vl->$u) "Port" }
        :local tl ""
        :foreach vid,m in=($pr->"tag") do={ :if ($m = 1) do={ :set tl ($tl . "," . $vid); :set ($vl->$vid) "Port" } }
        :if ([:len $tl] > 0) do={ :set t ($t . " tagged " . [:pick $tl 1 [:len $tl]]) }
        :set t ($t . " (" . ($pr->"frame") . ", edge " . ($pr->"edge") . ")")
      }
      :if ($pr->"disabled") do={ :set t ($t . ", abgeschaltet") }
    } do={ :set t ("FEHLER " . $e) }
    :put ("  " . [$cfmPad $p 12] . [$cfmPad $spec 14] . $t)
  }
  # --- VLANs auf dem Gerät (wie die Rolle base die Bridge-VLAN-Tabelle bildet) ---
  :local mv [:tostr ($cfmG->"mgmtVlan")]
  :set ($vl->$mv) "MGMT"
  :foreach x in=($cfmHost->"cpuVlans") do={ :set ($vl->[:tostr $x]) "cpuVlans" }
  :foreach vid,vv in=$cfmVlans do={
    :if ($rl ~ ",router," and [:tostr ($vv->"l3")] != "no") do={ :set ($vl->$vid) "router" }
    :if ($rl ~ ",manager" and [:tostr ($vv->"onboard")] = "yes") do={ :set ($vl->$vid) "Onboarding" }
  }
  :put "VLANs"
  :foreach vid,why in=$vl do={
    :local vv ($cfmVlans->$vid)
    :local t ([$cfmPad $vid 6] . [$cfmPad [:tostr ($vv->"name")] 12] . [$cfmPad ("Zone " . [:tostr ($vv->"zone")]) 16] . "(" . $why . ")")
    :if ($rl ~ ",router," and [:tostr ($vv->"l3")] != "no") do={
      :local nn [$cfmNet $vid]
      :if ([:len ($nn->"net")] > 0) do={ :set t ($t . "  " . ($nn->"net") . " Gateway " . [:tostr ($nn->"gw")]) }
      :if ([:len [:tostr ($vv->"dhcp")]] > 0) do={ :set t ($t . " DHCP " . ($vv->"dhcp")) }
    }
    :if ([:typeof $vv] != "array") do={ :set t ($t . "  fehlt in vlans.rsc!") }
    :put ("  " . $t)
  }
  # --- Router: feste Leases, DNS-Namen (D62) ---
  :if ($rl ~ ",router,") do={
    :local nl 0
    :foreach vid,ls in=$cfmLeases do={
      :local nn [$cfmNet $vid]
      :foreach ln,ld in=$ls do={
        :if ($nl = 0) do={ :put "Feste Leases" }
        :set nl ($nl + 1)
        :put ("  " . [$cfmPad $vid 6] . [$cfmPad $ln 20] . [$cfmPad [:tostr ($ld->"mac")] 19] . [:tostr (($nn->"addr") + [:tonum ($ld->"ip")])])
      }
    }
    :local nd 0
    :foreach hn,hd in=[$cfmInvLoad] do={ :if ([$cfmEnrolled $hd] and [:len [:tostr ($hd->"ip")]] > 0) do={ :set nd ($nd + 1) } }
    :put ("DNS-Namen unter ." . [:tostr ($cfmG->"domain")] . ": " . $nd . " Geräte, " . $nl . " Leases")
  }
  # --- WLAN ---
  :if ($rl ~ ",ap," or $rl ~ ",capsman,") do={
    :put "WLAN"
    :foreach k,s in=($cfmWifi->"ssids") do={
      :local t ([$cfmPad $k 10] . [$cfmPad [:tostr ($s->"ssid")] 18] . "VLAN " . [:tostr ($s->"vlan")] . ", Bänder " . [:tostr ($s->"bands")])
      :if ([:tostr ($s->"fallback")] = "yes") do={ :set t ($t . ", im Fallback") }
      :put ("  " . $t)
    }
    :local pin ($cfmWifi->"radios"->$host)
    :if ([:typeof $pin] = "array") do={ :put ("  Pins: " . [:tostr $pin]) }
  }
  :if ([$cfmFileEx ($dir . "/hosts/" . $host . ".post.rsc")]) do={ :put ("hosts/" . $host . ".post.rsc: freie Befehle, hier nicht ausgewertet") }
  :return ""
}

# Text -> Liste der Zeilen (ohne \r)
:global cfmDiffLines do={
  :local r ({})
  :local t [:tostr $1]
  :while ([:len $t] > 0) do={
    :local p [:find $t "\n"]
    :local l $t
    :if ([:typeof $p] = "nil") do={ :set t "" } else={ :set l [:pick $t 0 $p]; :set t [:pick $t ($p + 1) [:len $t]] }
    :if ([:len $l] > 0 and [:pick $l ([:len $l] - 1) [:len $l]] = "\r") do={ :set l [:pick $l 0 ([:len $l] - 1)] }
    :set ($r->[:len $r]) $l
  }
  :return $r
}

# Zeilenunterschied zweier Texte ($1 alt, $2 neu) mit :put. Gemeinsamer Anfang und gemeinsames Ende
# fallen weg, dazwischen kürzeste Änderungsfolge per LCS (bis 40 000 Zellen), sonst ein Block alt/neu.
# "@@ Zeile A / B" = erste betroffene Zeile im alten / neuen Stand.
:global cfmDiffText do={
  :global cfmDiffLines
  :local a [$cfmDiffLines $1]
  :local b [$cfmDiffLines $2]
  :local na [:len $a]
  :local nb [:len $b]
  :local cut do={ :local x [:tostr $1]; :if ([:len $x] > 150) do={ :return ([:pick $x 0 150] . " …") }; :return $x }
  :local s 0
  :while ($s < $na and $s < $nb and ($a->$s) = ($b->$s)) do={ :set s ($s + 1) }
  :local ea $na
  :local eb $nb
  :while ($ea > $s and $eb > $s and ($a->($ea - 1)) = ($b->($eb - 1))) do={ :set ea ($ea - 1); :set eb ($eb - 1) }
  :local ma ($ea - $s)
  :local mb ($eb - $s)
  :if ($ma = 0 and $mb = 0) do={ :return false }
  :if ($ma = 0 or $mb = 0 or ($ma * $mb) > 40000) do={
    :put ("  @@ Zeile " . ($s + 1) . " / " . ($s + 1))
    # :for mit from > to zählte rückwärts - nur laufen lassen, wenn es Zeilen gibt
    :if ($ea > $s) do={ :for i from=$s to=($ea - 1) do={ :put ("  - " . [$cut ($a->$i)]) } }
    :if ($eb > $s) do={ :for j from=$s to=($eb - 1) do={ :put ("  + " . [$cut ($b->$j)]) } }
    :return true
  }
  # L(i,j) = Länge der längsten gemeinsamen Folge von a[s+i..ea) und b[s+j..eb)
  :local L ({})
  :local zero ({})
  :for j from=0 to=$mb do={ :set ($zero->$j) 0 }
  :set ($L->$ma) $zero
  :for i from=($ma - 1) to=0 step=-1 do={
    :local row ({})
    :set ($row->$mb) 0
    :local nx ($L->($i + 1))
    :for j from=($mb - 1) to=0 step=-1 do={
      :if (($a->($s + $i)) = ($b->($s + $j))) do={ :set ($row->$j) (($nx->($j + 1)) + 1) } else={
        :local x ($nx->$j)
        :local y ($row->($j + 1))
        :if ($x >= $y) do={ :set ($row->$j) $x } else={ :set ($row->$j) $y }
      }
    }
    :set ($L->$i) $row
  }
  :local i 0
  :local j 0
  :local hl ({})
  :local ha 0
  :local hb 0
  :while ($i < $ma or $j < $mb) do={
    :local same false
    :if ($i < $ma and $j < $mb) do={ :if (($a->($s + $i)) = ($b->($s + $j))) do={ :set same true } }
    :if ($same) do={
      :if ([:len $hl] > 0) do={ :put ("  @@ Zeile " . ($ha + 1) . " / " . ($hb + 1)); :foreach x in=$hl do={ :put $x }; :set hl ({}) }
      :set i ($i + 1)
      :set j ($j + 1)
    } else={
      :if ([:len $hl] = 0) do={ :set ha ($s + $i); :set hb ($s + $j) }
      :local del false
      :if ($j >= $mb) do={ :set del true } else={
        :if ($i < $ma) do={ :if ((($L->($i + 1))->$j) >= (($L->$i)->($j + 1))) do={ :set del true } }
      }
      :if ($del) do={
        :set ($hl->[:len $hl]) ("  - " . [$cut ($a->($s + $i))])
        :set i ($i + 1)
      } else={
        :set ($hl->[:len $hl]) ("  + " . [$cut ($b->($s + $j))])
        :set j ($j + 1)
      }
    }
  }
  :if ([:len $hl] > 0) do={ :put ("  @@ Zeile " . ($ha + 1) . " / " . ($hb + 1)); :foreach x in=$hl do={ :put $x } }
  :return true
}

:global cfmDiff do={
  :global cfmMB; :global cfmRings; :global cfmJson; :global cfmInvLoad; :global cfmRead; :global cfmDiffText
  :local b [$cfmMB]
  :local va [:tostr $ver]
  :if ([:len $va] = 0) do={ :set va [:tostr ([$cfmRings]->"latest")] }
  :local vb [:tostr $to]
  :if ([:len $vb] = 0) do={ :set vb "work" }
  # Dateien eines Stands {Pfad=SHA-512}: Release aus index.dat, work/ frisch berechnet
  :local idx do={
    :global cfmJson
    :if ($v = "work") do={
      :local r ({})
      :foreach f in=[/file/find where name~("^" . $b . "/work/") and type!="directory"] do={
        :local n [/file/get $f name]
        :set ($r->[:pick $n ([:len $b] + 6) [:len $n]]) [:convert [/file/get $f contents] transform=sha512 to=hex]
      }
      :return $r
    }
    :return ([$cfmJson ($b . "/archive/v" . $v . "/index.dat")]->"files")
  }
  :local fa [$idx v=$va b=$b]
  :local fb [$idx v=$vb b=$b]
  :if ([:len $fa] = 0) do={ :error ("Stand " . $va . " nicht vorhanden (Archiv: archiveKeep)") }
  :if ([:len $fb] = 0) do={ :error ("Stand " . $vb . " nicht vorhanden (Archiv: archiveKeep)") }
  :local pa ($b . "/archive/v" . $va)
  :if ($va = "work") do={ :set pa ($b . "/work") }
  :local pb ($b . "/archive/v" . $vb)
  :if ($vb = "work") do={ :set pb ($b . "/work") }
  :local la ("v" . $va)
  :if ($va = "work") do={ :set la "work/" }
  :local lb ("v" . $vb)
  :if ($vb = "work") do={ :set lb "work/" }
  :put ("Unterschied " . $la . " -> " . $lb)
  :local ch ({})
  :foreach rel,h in=$fb do={
    :if ([:typeof ($fa->$rel)] = "nothing") do={ :set ($ch->$rel) "neu" } else={ :if (($fa->$rel) != $h) do={ :set ($ch->$rel) "geändert" } }
  }
  :foreach rel,h in=$fa do={ :if ([:typeof ($fb->$rel)] = "nothing") do={ :set ($ch->$rel) "entfernt" } }
  :if ([:len $ch] = 0) do={ :put "keine Unterschiede"; :return false }
  :foreach rel,t in=$ch do={ :put ("  " . $t . ": " . $rel) }
  # betroffene Geräte - wie die Manifeste die Dateien zuordnen
  :local common {"global.rsc"=1;"vlans.rsc"=1;"profiles.rsc"=1;"wifi.rsc"=1;"wireguard.rsc"=1;"leases.rsc"=1;"lib/lib.rsc"=1;"lib/agent.rsc"=1;"roles/base.rsc"=1}
  :local all false
  # authorized_keys.<user> (D65): jedes Gerät mit diesem User
  :foreach rel,t in=$ch do={ :if ([:typeof ($common->$rel)] != "nothing" or $rel ~ "^authorized_keys\\.") do={ :set all true } }
  :if ($all) do={ :put "betroffen: alle Geräte (gemeinsame Datei)" } else={
    :local aff ""
    :foreach name,d in=[$cfmInvLoad] do={
      :local rl ("," . [:tostr ($d->"role")] . ",")
      :local hit false
      :foreach rel,t in=$ch do={
        :if ($rel = ("hosts/" . $name . ".rsc") or $rel = ("hosts/" . $name . ".post.rsc")) do={ :set hit true }
        :if ($rel ~ "^roles/") do={
          :local r [:pick $rel 6 ([:len $rel] - 4)]
          :if ($rl ~ ("," . $r . ",") or ($r = "manager" and $rl ~ ",manager-backup,")) do={ :set hit true }
        }
        :if ($rel ~ "^lib/mgr-" and $rl ~ ",manager") do={ :set hit true }
      }
      :if ($hit) do={ :set aff ($aff . " " . $name) }
    }
    :if ([:len $aff] = 0) do={ :set aff " keine" }
    :put ("betroffen:" . $aff)
  }
  # geänderte Zeilen der Datendateien (lib/ und roles/ nur als Datei)
  :foreach rel,t in=$ch do={
    :if ($rel ~ "^(global|vlans|profiles|wifi|wireguard|leases)\\.rsc\$" or $rel ~ "^hosts/" or $rel ~ "^authorized_keys\\.") do={
      :put ""
      :put ($rel . ":")
      :local ta ""
      :local tb ""
      :if ($t != "neu") do={ :set ta [$cfmRead ($pa . "/" . $rel)] }
      :if ($t != "entfernt") do={ :set tb [$cfmRead ($pb . "/" . $rel)] }
      $cfmDiffText $ta $tb
    }
  }
  :return true
}
