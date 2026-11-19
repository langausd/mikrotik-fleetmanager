# ============================================================
# cfm lib/mgr-scan.rsc – Manager-Funktionen: Kanal-Scan der APs und Pin-Vorschlag (DW3.2, DW3.3, DW3.5)
#   $cfmWifiScan [host=<ap>] [band=2|5|6] [duration=10s] [data=yes] [all=yes]
#   (Übersicht aller Befehle: lib/mgr-core.rsc; Kanäle der APs: $cfmChannels in lib/mgr-net.rsc)
# ============================================================

# ---------- Kanalplan per Scan (TODO 41, DW3.2) ----------
# $cfmWifiScan [host=<AP>] [band=2|5|6] [duration=10s] [data=yes] [all=yes]
# Jeder AP (Rolle ap, aufgenommen) scannt nacheinander auf seinen Radios des Bands (Standard 2,4 GHz),
# ebenso der CAPsMAN, wenn er mitfunkt (capsmanRadios, TODO 46)
# (/interface/wifi/scan … as-value). Ein Radio unter CAPsMAN-Kontrolle lehnt den Scan am CAP ab
# ("not allowed") - gescannt wird deshalb auf dem CAPsMAN am Interface <AP>-<Band>g (DU2.1, DW3.3), erst
# ab ~10 s Dauer kommen dort Ergebnisse (5 s lieferten keine, Hardware 2026-10-03). Radios ohne
# CAPsMAN scannen direkt am AP. Das Radio verlässt dafür den Kanal, verbundene Clients wechseln kurz
# zum Nachbarn. Die BSSIDs der eigenen APs kennt der CAPsMAN (Interface-Namen <AP>-<Band>g).
# Ergebnis in state/wifiscan.json (eine Messung ganz ohne Netze überschreibt sie nicht); data=yes
# rechnet nur mit der letzten Messung, host= ersetzt in ihr nur diesen AP (gleiches Band).
# Vorschlag (nur 2,4 GHz): Kanalsätze 1/6/11, 1/5/9/13 und 1/5/9 durchprobieren, Kosten je AP = Summe
# über gehörte Netze: Gewicht (Signal + 95 dB) mal Überlappung der Kanäle (gleich 4/4, 1 Kanal daneben
# 3/4 … ab 4 Kanälen Abstand 0); eigene APs, die sich hören, zählen doppelt. Dazu die anderen
# Funknetze aus wifi.rsc "others" (TODO 51, $cfmOthCost; Arbeitsstand work/), für Zigbee/Thread mit
# Kanal "auto" ein Kanalvorschlag je Satz. Bis 6 APs alle Kombinationen, darüber schrittweise.
# wifi.rsc bleibt unverändert - die Zeile "radios" zum Übernehmen steht in der Ausgabe.
# Band 5/6 (TODO 93, DW3.9): Kanal und Breite je AP über $cfmScanPlan (oben), Netze mit ihrem Block (Index 4/5),
# Kanal und Sendeleistung je AP aus monitor unter "pw" in der Messung; all=yes: alle EU-Kanäle statt des Pools.
:global cfmScanW do={ :local w ([:tonum $1] + 95); :if ($w < 0) do={ :set w 0 }; :return $w }
:global cfmScanOv do={
  # Überlappung zweier 2,4-GHz-Frequenzen in Vierteln (20 MHz breit, 5 MHz Raster)
  :local d (([:tonum $1] - [:tonum $2]) / 5)
  :if ($d < 0) do={ :set d (0 - $d) }
  :if ($d >= 4) do={ :return 0 }
  :return (4 - $d)
}
# Andere Funknetze im 2,4-GHz-Band (TODO 51): wifi.rsc "others", je Eintrag "type" (zigbee, thread,
# milight-rgbw, milight-cct, milight-rgbcct, ble, bt), bei Zigbee/Thread "ch" (11-26 oder "auto"),
# optional "near" (APs neben dem Sender, z.B. "ap1,ap2") und "w" (Gewicht dort, Standard je Typ).
# $cfmOthSig <Eintrag> -> {{Frequenz;Gewicht an near-APs;Gewicht sonst};...}, leer bei Kanal auto.
# Gewichte wie ein fremdes WLAN mit Signal + 95 dB: Zigbee/Thread 60 (also wie -35 dBm), Milight und
# BLE je Frequenz 30 bzw. 20 (Befehle und Advertising laufen auf allen drei), Bluetooth classic 2 je
# 1-MHz-Kanal (springt über alle 79 - fast gleiche Kosten auf jedem WLAN-Kanal); sonst ein Drittel.
:global cfmOthSig do={
  :local e $1
  :local t [:tostr ($e->"type")]
  :local fl ({})
  :local wn 60
  :if ($t = "zigbee" or $t = "thread") do={
    :local k [:tonum ($e->"ch")]
    :if ([:typeof $k] = "num") do={ :if ($k >= 11 and $k <= 26) do={ :set ($fl->0) (2405 + (5 * ($k - 11))) } }
  }
  :if ($t = "milight-rgbw") do={ :set fl {2411;2442;2473}; :set wn 30 }
  :if ($t = "milight-cct") do={ :set fl {2406;2441;2476}; :set wn 30 }
  :if ($t = "milight-rgbcct") do={ :set fl {2410;2441;2472}; :set wn 30 }
  :if ($t = "ble") do={ :set fl {2402;2426;2480}; :set wn 20 }
  :if ($t = "bt") do={ :for i from=2402 to=2480 do={ :set ($fl->[:len $fl]) $i }; :set wn 2 }
  :local w [:tonum ($e->"w")]
  :if ([:typeof $w] = "num") do={ :set wn $w }
  :local wf ($wn / 3)
  :if ($wf < 1) do={ :set wf 1 }
  :local r ({})
  :foreach f in=$fl do={ :set ($r->[:len $r]) ({$f;$wn;$wf}) }
  :return $r
}
# Überlappung eines schmalen Senders (Frequenz $2) mit einem 20-MHz-WLAN-Kanal (Mitte $1) in Vierteln:
# im Kanal (bis 9 MHz neben der Mitte) 4, knapp daneben (bis 13 MHz, Seitenband) 1, sonst 0
:global cfmOthOv do={
  :local d ([:tonum $1] - [:tonum $2])
  :if ($d < 0) do={ :set d (0 - $d) }
  :if ($d <= 9) do={ :return 4 }
  :if ($d <= 13) do={ :return 1 }
  :return 0
}
# steht AP $2 in near des Eintrags $1?
:global cfmOthNear do={ :return ([:typeof [:find ("," . [:tostr ($1->"near")] . ",") ("," . $2 . ",")]] != "nil") }
# Kosten der anderen Netze $oth für AP $ap auf der WLAN-Frequenz $f
:global cfmOthCost do={
  :global cfmOthSig; :global cfmOthOv; :global cfmOthNear
  :local c 0
  :foreach k,e in=$oth do={
    :local nr [$cfmOthNear $e $ap]
    :foreach s in=[$cfmOthSig $e] do={
      :local w ($s->2)
      :if ($nr) do={ :set w ($s->1) }
      :set c ($c + ($w * [$cfmOthOv $f ($s->0)]))
    }
  }
  :return $c
}
# ---------- Vorschlag 5/6 GHz (TODO 93, DW3.9) ----------
# Block eines Kanals aus Scan oder monitor ("5700/ax/eeCe": je 20 MHz ein Buchstabe, C = Primärkanal) -> {unten;oben}
# in MHz; maßgeblich ist das Segment nur aus C/e - Zusätze wie "/D" (DFS) oder "/I" dahinter zählen nicht (TODO 95);
# ohne solches Segment 20 MHz um die Frequenz
:global cfmScanBlk do={
  # Zeichenweise statt :find mit Startposition (leere Segmente wie in "2412/ax/" liefen sonst endlos, Labor 19.11.)
  :local ch [:tostr $1]
  :local n [:len $ch]
  :local fq [:tonum [:pick $ch 0 [:find ($ch . "/") "/"]]]
  :local s ""
  :local g ""
  :local sn false
  :for i from=0 to=$n do={
    :local c "/"
    :if ($i < $n) do={ :set c [:pick $ch $i ($i + 1)] }
    :if ($c = "/") do={
      :if ($sn and $s = "" and [:len $g] > 0 and [:typeof [:find $g "C"]] = "num" and !($g ~ "[^Ce]")) do={ :set s $g }
      :set sn true
      :set g ""
    } else={ :set g ($g . $c) }
  }
  :if ([:len $s] = 0) do={ :return ({($fq - 10);($fq + 10)}) }
  :local ci [:find $s "C"]
  :local lo ($fq - 10 - (20 * $ci))
  :return ({$lo;($lo + (20 * [:len $s]))})
}
# Block zu Primärfrequenz $1 und Breite $2 (MHz) im Raster des Bands: 5 GHz ab Kanal 36 bzw. 149 (wie $cfmCheck),
# 6 GHz ab Kanal 1 (80 MHz: 1-13, 17-29 …; 160 MHz: 1-29, 33-61, 65-93)
:global cfmScanGrid do={
  :local f [:tonum $1]; :local w [:tonum $2]
  :if ($w <= 20) do={ :return ({($f - 10);($f + 10)}) }
  :local g ($w / 5)
  :if ($f >= 5925) do={
    :local c6 (($f - 5950) / 5)
    :local s6 (1 + ((($c6 - 1) / $g) * $g))
    :local l6 (5950 + (5 * $s6) - 10)
    :return ({$l6;($l6 + $w)})
  }
  :local ch (($f - 5000) / 5)
  :local base 36
  :if ($ch >= 149) do={ :set base 149 }
  :local st ($base + ((($ch - $base) / $g) * $g))
  :local lo (5000 + (5 * $st) - 10)
  :return ({$lo;($lo + $w)})
}
# Störanteil in Hundertsteln (Entscheidung A, 2026-11-17): ein Block nlo-nhi, der unseren Primärkanal (f ± 10 MHz)
# überdeckt, zählt voll (100), sonst die Hälfte des Anteils der überlappten MHz an unserem Block lo-hi
:global cfmScanOv5 do={
  :local pf [:tonum $f]; :local l1 [:tonum $lo]; :local h1 [:tonum $hi]; :local l2 [:tonum $nlo]; :local h2 [:tonum $nhi]
  :if ($l2 < ($pf + 10) and $h2 > ($pf - 10)) do={ :return 100 }
  :local a $l1
  :if ($l2 > $a) do={ :set a $l2 }
  :local z $h1
  :if ($h2 < $z) do={ :set z $h2 }
  :if ($z <= $a) do={ :return 0 }
  :return ((50 * ($z - $a)) / ($h1 - $l1))
}
# $cfmScanPlan sc= nb= aps= bd= inv= [all=yes] [pre=<cfmChLive vor dem Scan>] - aufgerufen von $cfmWifiScan für Band 5 und 6.
# Kandidaten je AP: (Primärfrequenz, Breite) - Primärfrequenzen aus dem Pool (channels), eine Liste in radios ersetzt
# ihn für diesen AP (ihr "/<Breite>" begrenzt die Breite), ein einzelner Pin kommt dazu; all=yes nimmt alle
# EU-Kanäle (5 GHz 36-64 und 100-140, 6 GHz die PSC-Kanäle) dazu. Breiten bis zur höchsten aus width. Zulässig nur
# ganze Blöcke in 5150-5350, 5470-5725 (EU, DW3.8) oder 5725-5850 (nur Pool-Kanäle), 6 GHz 5945-6425; skipDfs
# 10min-cac lässt das Wetterradar (5600-5650) aus, all alle DFS-Kanäle.
# Kosten in Hundertsteln eines fremden Netzes mit Gewicht 1 (Signal + 95 dB, wie bei 2,4 GHz):
#   fremde Netze  Gewicht x Störanteil ($cfmScanOv5) mit ihrem Block aus dem Scan
#   eigene APs    doppeltes Gewicht, die sich hören (in beiden Richtungen gezählt)
#   DFS           nur an APs mit lokalem Fallback (Rolle ap; der CAPsMAN funkt ohne Fallback): 20, Wetterradar 60
#   Leistung      3 je dB unter der besten Möglichkeit des AP; EU-Grenze je Teilband (23/30/14 dBm, 6 GHz 23),
#                 begrenzt durch txPower oder die gemessene Leistung, wenn sie unter der Grenze ihres Teilbands lag
#                 (dann ist das die Grenze des Radios)
#   Breite        Plan "breit": 20 je fehlender Verdopplung bis zur höchsten Breite (≈ ein fremdes Netz mit -75 dBm
#                 voll überlappend); Plan "robust": keine eigenen APs überlappend, Breite nur bei Gleichstand
# Suche: alle Kombinationen der je AP besten K Kandidaten (höchstens ~2000 Pläne), dann zwei Runden je AP alle
# Kandidaten bei festen übrigen.
:global cfmScanPlan do={
  :global cfmLoadData; :global cfmWifi; :global cfmScanW; :global cfmScanBlk; :global cfmScanGrid; :global cfmScanOv5
  :global cfmPad; :global cfmChLive
  :local own ($sc->"own")
  :onerror e in={ $cfmLoadData ver=0 } do={ :put ("wifi.rsc nicht ladbar - kein Vorschlag: " . $e); :return false }
  :local chs ($cfmWifi->"channels"->$bd)
  :if ([:typeof $chs] != "array") do={ :put ("kein Vorschlag: channels \"" . $bd . "\" fehlt in wifi.rsc"); :return true }
  :local wdt [:tostr ($chs->"width")]
  :local mw 20
  :foreach x in={40;80;160} do={ :if ($wdt ~ [:tostr $x]) do={ :set mw $x } }
  :local dbl do={ :local w [:tonum $1]; :if ($w >= 160) do={ :return 3 }; :if ($w >= 80) do={ :return 2 }; :if ($w >= 40) do={ :return 1 }; :return 0 }
  :local dmx [$dbl $mw]
  :local has do={ :foreach p in=$2 do={ :if ($p = [:tonum $1]) do={ :return true } }; :return false }
  :local tab do={ :local f [:tonum $1]; :if ($f >= 5925) do={ :return 23 }; :if ($f > 5725) do={ :return 14 }; :if ($f > 5400) do={ :return 30 }; :return 23 }
  :local sk [:tostr ($chs->"skipDfs")]
  :local pool ({})
  :foreach x in=[:toarray [:tostr ($chs->"freq")]] do={ :local n [:tonum $x]; :if ([:typeof $n] = "num") do={ :set ($pool->[:len $pool]) $n } }
  :local base ({})
  :foreach x in=$pool do={ :set ($base->[:len $base]) $x }
  :if ($all = "yes" or [:len $pool] = 0) do={
    :local eu ({})
    :if ($bd = "6") do={ :set eu {5975;6055;6135;6215;6295;6375} } else={
      :for c from=36 to=64 step=4 do={ :set ($eu->[:len $eu]) (5000 + (5 * $c)) }
      :for c from=100 to=140 step=4 do={ :set ($eu->[:len $eu]) (5000 + (5 * $c)) }
    }
    :foreach x in=$eu do={ :if (!([$has $x $base])) do={ :set ($base->[:len $base]) $x } }
  }
  # Kandidaten je AP: {f;w;unten;oben;fremd;dBm;dfs(0/1/2);DFS-Malus;Leistungs-Malus;Kosten breit;Kosten robust}
  :local apl ({})
  :local cand ({})
  :foreach ap in=$aps do={
    :local rv [:tostr ($cfmWifi->"radios"->$ap->$bd)]
    :if ($rv = "off") do={ :put ("  " . $ap . ": radios \"" . $bd . "\"=off - nicht im Vorschlag") } else={
      :local rf $rv
      :local amw $mw
      :local sl [:find $rv "/"]
      :if ([:typeof $sl] = "num") do={ :set rf [:pick $rv 0 $sl] }
      :local pr ({})
      :if ([:typeof [:find $rf ","]] = "num") do={
        :foreach x in=[:toarray $rf] do={ :local n [:tonum $x]; :if ([:typeof $n] = "num") do={ :set ($pr->[:len $pr]) $n } }
        :if ([:typeof $sl] = "num") do={
          :local wn [:tonum [:pick $rv ($sl + 1) [:len $rv]]]
          :if ([:typeof $wn] = "num" and $wn < $amw) do={ :set amw $wn }
        }
      } else={
        :foreach x in=$base do={ :set ($pr->[:len $pr]) $x }
        :local n [:tonum $rf]
        :if ([:typeof $n] = "num") do={ :if (!([$has $n $pr])) do={ :set ($pr->[:len $pr]) $n } }
      }
      # Fallback: Rolle ap; ein AP, den das Inventar nicht kennt, zählt als AP
      :local isFb true
      :local d ($inv->$ap)
      :if ([:typeof $d] = "array") do={ :set isFb (("," . [:tostr ($d->"role")] . ",") ~ ",ap,") }
      # Leistungsgrenze: txPower, sonst die gemessene, wenn sie unter der EU-Grenze ihres Teilbands lag
      :local cap 999
      :local tp [:tostr ($cfmWifi->"txPower"->$ap->$bd)]
      :if ([:len $tp] > 0) do={ :set cap [:tonum $tp] } else={
        :local mt [:tonum ($sc->"pw"->$ap->"tx")]
        :local mf [:tonum ($sc->"pw"->$ap->"f")]
        :if ([:typeof $mt] = "num" and [:typeof $mf] = "num") do={ :if ($mt < ([$tab $mf] - 1)) do={ :set cap $mt } }
      }
      :local cl ({})
      :local pmax 0
      :foreach f in=$pr do={
        :foreach w in={20;40;80;160} do={
          :if ($w <= $amw) do={
            :local bl [$cfmScanGrid $f $w]
            :local lo ($bl->0)
            :local hi ($bl->1)
            :local v false
            :if ($bd = "6") do={ :set v ($lo >= 5945 and $hi <= 6425) } else={
              :if (($lo >= 5150 and $hi <= 5350) or ($lo >= 5470 and $hi <= 5725)) do={ :set v true }
              :if ($lo >= 5725 and $hi <= 5850 and [$has $f $pool]) do={ :set v true }
            }
            :local dfs 0
            :if ($bd != "6" and $hi > 5250 and $lo < 5725) do={ :set dfs 1 }
            :if ($dfs = 1 and $lo < 5650 and $hi > 5600) do={ :set dfs 2 }
            :if ($sk = "all" and $dfs > 0) do={ :set v false }
            :if ($sk = "10min-cac" and $dfs = 2) do={ :set v false }
            :if ($v) do={
              :local pw [$tab $f]
              :if ($cap < $pw) do={ :set pw $cap }
              :if ($pw > $pmax) do={ :set pmax $pw }
              :set ($cl->[:len $cl]) ({$f;$w;$lo;$hi;0;$pw;$dfs;0;0;0;0})
            }
          }
        }
      }
      :if ([:len $cl] = 0) do={ :put ("  " . $ap . ": keine zulässigen Kanäle (Pool/radios, skipDfs, EU-Grenzen) - nicht im Vorschlag") } else={
        :local nets ($sc->"aps"->$ap)
        :local c2 ({})
        :foreach c in=$cl do={
          :local fo 0
          :foreach n in=$nets do={
            :if ([:len [:tostr ($own->[:tostr ($n->0)])]] = 0) do={
              :local nl ($n->4)
              :local nh ($n->5)
              :if ([:typeof $nl] != "num" or [:typeof $nh] != "num") do={ :set nl (($n->2) - 10); :set nh (($n->2) + 10) }
              :set fo ($fo + ([$cfmScanW ($n->3)] * [$cfmScanOv5 f=($c->0) lo=($c->2) hi=($c->3) nlo=$nl nhi=$nh]))
            }
          }
          :local dm 0
          :if ($isFb and ($c->6) = 1) do={ :set dm 2000 }
          :if ($isFb and ($c->6) = 2) do={ :set dm 6000 }
          :local pwc (300 * ($pmax - ($c->5)))
          :local dl ($dmx - [$dbl ($c->1)])
          :set ($c2->[:len $c2]) ({($c->0);($c->1);($c->2);($c->3);$fo;($c->5);($c->6);$dm;$pwc;($fo + $dm + $pwc + (2000 * $dl));($fo + $dm + $pwc + $dl)})
        }
        :set ($cand->[:len $apl]) $c2
        :set ($apl->[:len $apl]) $ap
      }
    }
  }
  :local na [:len $apl]
  :if ($na = 0) do={ :put "kein AP mit zulässigen Kanälen - kein Vorschlag"; :return true }
  # eigene APs, die sich hören: {i;j;doppeltes Gewicht}
  :local prs ({})
  :for i from=0 to=($na - 1) do={
    :for j from=0 to=($na - 1) do={
      :if ($i != $j) do={
        :local s ($nb->(($apl->$i) . "|" . ($apl->$j)))
        :if ([:typeof $s] = "num") do={ :set ($prs->[:len $prs]) ({$i;$j;(2 * [$cfmScanW $s])}) }
      }
    }
  }
  # Kosten eines Plans {AP-Index -> Kandidaten-Index} mit Spalte mi (9 breit, 10 robust) -> {Kosten;eigene überlappen}
  :local pcost do={
    :global cfmScanOv5
    # benannte Argumente kommen als Text an ("mi=9"), Listenindex braucht eine Zahl
    :local m [:tonum $mi]
    :local t 0
    :local ov false
    :for i from=0 to=([:len $pl] - 1) do={
      :local cl ($cand->$i)
      :local c ($cl->($pl->$i))
      :set t ($t + ($c->$m))
    }
    :foreach p in=$prs do={
      :local ca ($cand->($p->0))
      :local a ($ca->($pl->($p->0)))
      :local cc ($cand->($p->1))
      :local c ($cc->($pl->($p->1)))
      :if (($a->2) < ($c->3) and ($c->2) < ($a->3)) do={
        :set ov true
        :set t ($t + (($p->2) * [$cfmScanOv5 f=($a->0) lo=($a->2) hi=($a->3) nlo=($c->2) nhi=($c->3)]))
      }
    }
    :return ({$t;$ov})
  }
  :local srch do={
    :local na [:len $cand]
    :local m [:tonum $mi]
    :local rbb ([:tostr $rb] = "true")
    :local K 1
    :local go true
    :while ($go) do={
      :local p 1
      :for i from=1 to=$na do={ :set p ($p * ($K + 1)) }
      :if ($p <= 2000 and $K < 99) do={ :set K ($K + 1) } else={ :set go false }
    }
    :local tops ({})
    :for i from=0 to=($na - 1) do={
      :local cl ($cand->$i)
      :local us ({})
      :local tl ({})
      :for t from=1 to=$K do={
        :local bi -1
        :local bv 0
        :foreach k,c in=$cl do={
          :if ([:typeof ($us->("k" . $k))] = "nothing") do={ :if ($bi < 0 or ($c->$m) < $bv) do={ :set bi $k; :set bv ($c->$m) } }
        }
        :if ($bi >= 0) do={ :set ($us->("k" . $bi)) 1; :set ($tl->[:len $tl]) $bi }
      }
      :set ($tops->$i) $tl
    }
    :local tot 1
    :for i from=0 to=($na - 1) do={ :set tot ($tot * [:len ($tops->$i)]) }
    :local best ({})
    :local bt 0
    :local bo true
    :local have false
    :for x from=0 to=($tot - 1) do={
      :local pl ({})
      :local y $x
      :for i from=0 to=($na - 1) do={
        :local tl ($tops->$i)
        :local n [:len $tl]
        :set ($pl->$i) ($tl->($y % $n))
        :set y ($y / $n)
      }
      :local r [$pc cand=$cand pl=$pl prs=$prs mi=$mi]
      :local bet true
      :if ($have) do={
        :if ($rbb and (($r->1) != $bo)) do={ :set bet (!($r->1)) } else={ :set bet (($r->0) < $bt) }
      }
      :if ($bet) do={ :set have true; :set best $pl; :set bt ($r->0); :set bo ($r->1) }
    }
    :for rd from=1 to=2 do={
      :for i from=0 to=($na - 1) do={
        :foreach k,c in=($cand->$i) do={
          :local pl ({})
          :foreach q,v in=$best do={ :set ($pl->$q) $v }
          :set ($pl->$i) $k
          :local r [$pc cand=$cand pl=$pl prs=$prs mi=$mi]
          :local bet false
          :if ($rbb and (($r->1) != $bo)) do={ :set bet (!($r->1)) } else={ :set bet (($r->0) < $bt) }
          :if ($bet) do={ :set best $pl; :set bt ($r->0); :set bo ($r->1) }
        }
      }
    }
    :return ({$best;$bt;$bo})
  }
  :local ns ""
  :for i from=0 to=($na - 1) do={ :set ns ($ns . " " . ($apl->$i) . " " . [:len ($cand->$i)]) }
  :put ("Kandidaten (Kanal/Breite) je AP:" . $ns . " - bis " . $mw . " MHz, Pool " . [:tostr ($chs->"freq")] . ", skipDfs " . $sk)
  # aktueller Stand: vom CAPsMAN vor dem Scan (pre=, TODO 95) bzw. live (data=yes), sonst monitor-Werte der Messung
  :local live $pre
  :if ([:typeof $live] != "array" or [:len $live] = 0) do={ :set live [$cfmChLive inv=$inv] }
  :local cur ({})
  :local cs ""
  :local cok true
  :for i from=0 to=($na - 1) do={
    :local ap ($apl->$i)
    :local c [:tostr ($live->($ap . "-" . $bd . "g"))]
    :if ([:len $c] = 0) do={ :set c [:tostr ($sc->"pw"->$ap->"ch")] }
    :if ([:len $c] = 0) do={ :set cok false; :set cs ($cs . " " . $ap . "=?") } else={
      :local f [:tonum [:pick $c 0 [:find ($c . "/") "/"]]]
      :local bl [$cfmScanBlk $c]
      :local w (($bl->1) - ($bl->0))
      :set cs ($cs . " " . $ap . "=" . $f . "/" . $w)
      :local hit -1
      :foreach k,x in=($cand->$i) do={ :if (($x->0) = $f and ($x->1) = $w) do={ :set hit $k } }
      :if ($hit < 0) do={ :set cok false; :set cs ($cs . " (kein Kandidat)") } else={ :set ($cur->$i) $hit }
    }
  }
  :if ($cok) do={
    :local r [$pcost cand=$cand pl=$cur prs=$prs mi=9]
    :put ("Aktuell:          Kosten " . (($r->0) / 100) . $cs)
  } else={ :put ("Aktuell:" . $cs) }
  :foreach md in={{"breit";9;0};{"robust";10;1}} do={
    :local rb (($md->2) = 1)
    :local r [$srch cand=$cand prs=$prs mi=($md->1) rb=$rb pc=$pcost]
    :local pl ($r->0)
    :local s ""
    :local fo 0
    :local dm 0
    :local pw 0
    :local ind 0
    :local rad ({})
    :foreach a,m in=($cfmWifi->"radios") do={ :set ($rad->$a) $m }
    :for i from=0 to=($na - 1) do={
      :local cl ($cand->$i)
      :local c ($cl->($pl->$i))
      :local pin (($c->0) . "/" . ($c->1))
      :set s ($s . " " . ($apl->$i) . "=" . $pin)
      :set fo ($fo + ($c->4))
      :set dm ($dm + ($c->7))
      :set pw ($pw + ($c->8))
      :set ind ($ind + ($c->($md->1)))
      :local m ($rad->($apl->$i))
      :if ([:typeof $m] != "array") do={ :set m ({}) }
      :set ($m->$bd) $pin
      :set ($rad->($apl->$i)) $m
    }
    :local ln ("Vorschlag " . [$cfmPad ($md->0) 7] . "Kosten " . (($r->1) / 100) . " " . $s)
    :if ($rb and ($r->2)) do={ :set ln ($ln . "  (ohne Überlappung eigener APs nicht möglich)") }
    :put $ln
    :put ("  Anteile: fremde Netze " . ($fo / 100) . ", eigene APs " . ((($r->1) - $ind) / 100) . ", DFS " . ($dm / 100) . ", Leistung " . ($pw / 100) . ", Breite " . (($ind - $fo - $dm - $pw) / 100))
    :local wr ""
    :foreach a,m in=$rad do={
      :local e ""
      :if ([:typeof $m] = "array") do={ :foreach bb,v in=$m do={ :set e ($e . ";\"" . $bb . "\"=\"" . $v . "\"") } }
      :if ([:len $e] > 0) do={ :set wr ($wr . ";\"" . $a . "\"={" . [:pick $e 1 [:len $e]] . "}") }
    }
    :put ("  wifi.rsc: \"radios\"={" . [:pick $wr 1 [:len $wr]] . "}")
  }
  :put "Pins mit Breite (DW3.8); Pins anderer Bänder und APs stammen aus wifi.rsc (Arbeitsstand)."
  :return true
}
:global cfmWifiScan do={
  :global cfmInvLoad; :global cfmJson; :global cfmMB; :global cfmPad; :global cfmExec; :global cfmEnrolled
  :global cfmWrite; :global cfmCapsmen; :global cfmLoadData; :global cfmWifi; :global cfmScanW; :global cfmScanOv
  :global cfmOthCost; :global cfmOthSig; :global cfmOthOv; :global cfmOthNear; :global cfmHostName; :global cfmScanBlk
  :local hn [$cfmHostName $host]; :local host $hn
  :local b [$cfmMB]
  :local f ($b . "/state/wifiscan.json")
  :local inv [$cfmInvLoad]
  :local bd [:tostr $band]
  :if ([:len $bd] = 0) do={ :set bd "2" }
  :local dur [:tostr $duration]
  :if ([:len $dur] = 0) do={ :set dur "10s" }
  :local sc ({})
  # Kanal und Sendeleistung vor dem Scan (TODO 95): während und kurz nach dem Scan meldet monitor die Scan-Kanäle
  # oder nichts
  :local lv0 ({})
  :if ($data = "yes") do={
    :set sc [$cfmJson $f]
    :local tn 0
    :foreach ap,nets in=($sc->"aps") do={ :set tn ($tn + [:len $nets]) }
    :if ($tn = 0) do={ :put "keine Messung mit Netzen in state/wifiscan.json - erst ohne data=yes scannen"; :return false }
    :set bd [:tostr ($sc->"band")]
  } else={
    # rsc-check: erlaubt json-typ (t nur für Menschen, cfm liest es nicht zurück)
    :set sc ({"band"=$bd;"t"=([/system/clock/get date] . " " . [/system/clock/get time]);"own"=({});"aps"=({});"pw"=({})})
    # host=: in die letzte Messung desselben Bands einfügen (die übrigen APs müssen nicht neu scannen)
    :if ([:len $host] > 0) do={
      :local old [$cfmJson $f]
      :if ([:tostr ($old->"band")] = $bd and [:typeof ($old->"aps")] = "array") do={
        :set ($sc->"aps") ($old->"aps")
        :if ([:typeof ($old->"own")] = "array") do={ :set ($sc->"own") ($old->"own") }
        :if ([:typeof ($old->"pw")] = "array") do={ :set ($sc->"pw") ($old->"pw") }
        :put "übrige APs aus der letzten Messung (state/wifiscan.json)"
      }
    }
    # eigene BSSIDs vom CAPsMAN: Interface-Name <AP>-<Band>g[n], MAC = BSSID
    :local oc ":local o ({}); :foreach i in=[/interface/wifi/find] do={ :set (\$o->(\"m\" . [:tostr [/interface/wifi/get \$i mac-address]])) [/interface/wifi/get \$i name] }; :put [:serialize to=json \$o]"
    :foreach c in=[$cfmCapsmen $inv] do={
      :local r [$cfmExec ip=($c->"ip") cmd=$oc]
      :local oj ({})
      :onerror e in={ :set oj [:deserialize from=json ($r->"output")] } do={}
      :foreach m,nm in=$oj do={
        # letztes "-<Band>g" im Namen (Identities dürfen selbst "-" enthalten, virtuelle APs hängen
        # eine Nummer an)
        :local p -1
        :for i from=0 to=([:len $nm] - 3) do={ :if ([:pick $nm $i ($i + 3)] ~ "^-[256]g\$") do={ :set p $i } }
        :if ($p > 0) do={ :set ($sc->"own"->$m) [:pick $nm 0 $p] }
      }
    }
    :local bre ($bd . "ghz")
    :if ([:totime $dur] < 10s) do={ :put ("duration " . $dur . " -> 10s (über den CAPsMAN liefern kürzere Scans nichts)"); :set dur "10s" }
    :local cml [$cfmCapsmen $inv]
    :if ($bd != "2") do={ :global cfmChLive; :set lv0 [$cfmChLive inv=$inv] }
    # der CAPsMAN selbst, wenn er mitfunkt (capsmanRadios, TODO 46): seine Radios heißen wie die der
    # CAPs <Name>-<Band>g und lassen sich dort scannen; ohne dieses Interface sendet er nicht
    :local cmSet ({})
    :foreach c in=$cml do={ :set ($cmSet->[:tostr ($c->"n")]) 1 }
    :foreach name,d in=$inv do={
      :local isAp (("," . [:tostr ($d->"role")] . ",") ~ ",ap,")
      :local isCm ([:typeof ($cmSet->$name)] != "nothing")
      :if (([:len $host] = 0 or $host = $name) and ($isAp or $isCm) and [$cfmEnrolled $d]) do={
        :put ("Scan " . $name . " (" . $bd . " GHz, " . $dur . " je Radio) ...")
        # zuerst auf dem CAPsMAN am Interface <AP>-<Band>g; nur die vier gebrauchten Felder zurück
        :local lst ({})
        :local via ""
        :local sel (":foreach x in=[/interface/wifi/scan \$i duration=" . $dur . " as-value] do={ :set (\$r->[:len \$r]) ({\"address\"=(\$x->\"address\");\"channel\"=(\$x->\"channel\");\"signal\"=(\$x->\"signal\");\"ssid\"=(\$x->\"ssid\")}) }")
        :foreach c in=$cml do={
          :if ($via = "") do={
            :local cc (":local r ({}); :local i [/interface/wifi/find where name=\"" . $name . "-" . $bd . "g\"]; :if ([:len \$i] = 0) do={ :put \"none\" } else={ :onerror e in={ " . $sel . " } do={ :set (\$r->[:len \$r]) ({\"err\"=\$e}) }; :put [:serialize to=json \$r] }")
            :local r [$cfmExec ip=($c->"ip") cmd=$cc]
            :local out [:tostr ($r->"output")]
            :if ([:pick $out 0 4] != "none") do={
              :onerror e in={ :set lst [:deserialize from=json $out]; :set via ($c->"n") } do={ :put ("  " . $name . ": keine Daten vom CAPsMAN " . ($c->"n") . " (" . [:pick $out 0 120] . ")") }
            }
          }
        }
        # Radios ohne CAPsMAN: direkt am AP (nicht am CAPsMAN: ohne eigenes Interface sendet er nicht)
        :if ($via = "" and $isAp) do={
          :local cmd (":local r ({}); :foreach i in=[/interface/wifi/find where default-name~\"^wifi\"] do={ :local n [/interface/wifi/get \$i name]; :local bs \"\"; :onerror e in={ :set bs [:tostr [/interface/wifi/radio/get [find where interface=\$n] bands]] } do={}; :if (\$bs ~ \"" . $bre . "\") do={ :onerror e in={ " . $sel . " } do={ :set (\$r->[:len \$r]) ({\"err\"=\$e}) } } }; :put [:serialize to=json \$r]")
          :local r [$cfmExec ip=($d->"ip") cmd=$cmd]
          :onerror e in={ :set lst [:deserialize from=json ($r->"output")]; :set via "AP" } do={ :put ("  " . $name . ": keine Daten (" . [:pick ($r->"output") 0 120] . ")") }
        }
        :local nets ({})
        :foreach x in=$lst do={
          :if ([:len [:tostr ($x->"err")]] > 0) do={ :put ("  " . $name . ": Scan-Fehler " . ($x->"err")) } else={
            # Feldnamen auf Hardware (hAP ax³, 7.24.4): address, channel ("2437/ax"), signal, ssid,
            # security, active - die Alternativen bleiben für andere Versionen
            :local bss [:tostr ($x->"address")]; :if ([:len $bss] = 0) do={ :set bss [:tostr ($x->"bssid")] }
            :local ch [:tostr ($x->"channel")]; :if ([:len $ch] = 0) do={ :set ch [:tostr ($x->"frequency")] }
            :local sg [:tostr ($x->"sig")]; :if ([:len $sg] = 0) do={ :set sg [:tostr ($x->"signal")] }
            :local fq [:tonum [:pick $ch 0 [:find ($ch . "/") "/"]]]
            # belegter Block (TODO 93) aus den Buchstaben hinter der Frequenz ("5700/ax/eeCe" -> 5650-5730)
            :local bl [$cfmScanBlk $ch]
            :if ([:typeof $fq] = "num" and [:len $sg] > 0) do={ :set ($nets->[:len $nets]) ({("m" . $bss);[:tostr ($x->"ssid")];$fq;[:tonum $sg];($bl->0);($bl->1)}) }
          }
        }
        :if ($via = "" and !$isAp) do={
          :put ("  " . $name . ": eigene Radios senden nicht (capsmanRadios aus) - nicht im Vorschlag")
        } else={
          :set ($sc->"aps"->$name) $nets
          :put ("  " . [:len $nets] . " Netze (über " . $via . ")")
        }
      }
    }
    :local tn 0
    :foreach ap,nets in=($sc->"aps") do={ :set tn ($tn + [:len $nets]) }
    :if ($tn = 0) do={ :put "keine Netze gemessen - kein Vorschlag, state/wifiscan.json bleibt unverändert"; :return false }
    # Kanal und Sendeleistung (monitor am CAPsMAN, vor dem Scan gelesen) für Band 5/6: aktueller Stand und
    # Leistungsgrenze (TODO 93, 95); APs aus einer älteren Messung (host=) behalten ihre Werte
    :if ($bd != "2") do={
      :local lv $lv0
      :foreach ap,x in=($sc->"aps") do={
        :local c [:tostr ($lv->($ap . "-" . $bd . "g"))]
        :if ([:len $c] > 0) do={
          :local e ({"ch"=$c;"f"=[:tonum [:pick $c 0 [:find ($c . "/") "/"]]]})
          :local tx [:tonum ($lv->($ap . "-" . $bd . "g|tx"))]
          :if ([:typeof $tx] = "num") do={ :set ($e->"tx") $tx }
          :set ($sc->"pw"->$ap) $e
        }
      }
    }
    $cfmWrite $f [:serialize to=json $sc]
  }
  # --- Auswertung: je AP fremde Netze nach Kanal, eigene Nachbarn ---
  :local own ($sc->"own")
  :local aps ({})
  :local nb ({})
  :foreach ap,nets in=($sc->"aps") do={
    :local byf ({})
    :foreach n in=$nets do={
      :local o [:tostr ($own->[:tostr ($n->0)])]
      :if ([:len $o] > 0) do={
        :if ($o != $ap) do={
          :local k ($ap . "|" . $o)
          :if ([:typeof ($nb->$k)] = "nothing" or ($n->3) > ($nb->$k)) do={ :set ($nb->$k) ($n->3) }
        }
      } else={
        :local fk [:tostr ($n->2)]
        :if ([:typeof ($byf->$fk)] != "array") do={ :set ($byf->$fk) ({0;-120}) }
        :set ($byf->$fk->0) (($byf->$fk->0) + 1)
        :if (($n->3) > ($byf->$fk->1)) do={ :set ($byf->$fk->1) ($n->3) }
      }
    }
    :set ($aps->[:len $aps]) $ap
    :local row ""
    :foreach fk,v in=$byf do={ :set row ($row . " " . $fk . ":" . ($v->0) . "/" . ($v->1)) }
    :put ([$cfmPad $ap 12] . "fremd (MHz:Anzahl/stärkstes dBm):" . $row)
  }
  :foreach k,sg in=$nb do={ :put ("eigener Nachbar " . $k . " " . $sg . " dBm") }
  # 5 und 6 GHz: Kanal und Breite je AP (TODO 93, DW3.9)
  :if ($bd != "2") do={ :global cfmScanPlan; :return [$cfmScanPlan sc=$sc nb=$nb aps=$aps bd=$bd inv=$inv all=$all pre=$lv0] }
  :local na [:len $aps]
  :if ($na = 0) do={ :put "keine Scan-Daten"; :return false }
  # andere Funknetze (TODO 51) aus dem Arbeitsstand
  :onerror e in={ $cfmLoadData ver=0 } do={ :put ("wifi.rsc nicht ladbar, ohne andere Funknetze: " . $e) }
  :local oth ($cfmWifi->"others")
  :if ([:typeof $oth] != "array") do={ :set oth ({}) }
  :foreach k,e in=$oth do={
    :local t [:tostr ($e->"type")]
    :local fs ""
    :foreach x in=[$cfmOthSig $e] do={ :if ([:len $fs] < 40) do={ :set fs ($fs . "," . ($x->0)) } }
    :local ch [:tostr ($e->"ch")]
    :local nr [:tostr ($e->"near")]
    :local d $t
    :if ($t = "zigbee" or $t = "thread") do={ :set d ($d . " Kanal " . $ch); :if ([:len $ch] = 0) do={ :set d ($d . "auto") } }
    :if ($t = "bt") do={ :set fs ",2402-2480" }
    :if ([:len $fs] > 0) do={ :set d ($d . ", " . [:pick $fs 1 [:len $fs]] . " MHz") }
    :if ([:len $nr] > 0) do={ :set d ($d . ", bei " . $nr) }
    :put ("anderes Netz " . $k . ": " . $d)
  }
  # aktueller Stand (Status-Feld radios: "c2412/ax/…")
  :local cur ({})
  :local curOk true
  # Aktuell: live vom CAPsMAN (TODO 91), sonst aus dem Status des letzten Agent-Laufs
  :global cfmChLive
  :local live [$cfmChLive inv=$inv]
  :for i from=0 to=($na - 1) do={
    :local st [$cfmJson ($b . "/state/" . ($aps->$i) . "/status.dat")]
    :local cq ""
    :foreach r in=($st->"radios") do={
      :local ch [:pick [:tostr ($r->1)] 1 99]
      :local fq [:tonum [:pick $ch 0 [:find ($ch . "/") "/"]]]
      :if ([:typeof $fq] = "num" and $fq < 2500) do={ :set cq $fq }
    }
    :local lv [:tostr ($live->(($aps->$i) . "-2g"))]
    :if ([:len $lv] > 0) do={
      :local lq [:tonum [:pick $lv 0 [:find ($lv . "/") "/"]]]
      :if ([:typeof $lq] = "num") do={ :set cq $lq }
    }
    :if ([:len [:tostr $cq]] = 0) do={ :set curOk false } else={ :set ($cur->$i) $cq }
  }
  # Kosten je AP und Frequenz (fremde und andere Netze) vorab, für das Raster und den aktuellen Stand
  :local fc ({})
  :local fl {2412;2432;2437;2452;2462;2472}
  :foreach i,cq in=$cur do={ :if ([:typeof [:find $fl $cq]] = "nil") do={ :set ($fl->[:len $fl]) $cq } }
  :foreach ap,nets in=($sc->"aps") do={
    :foreach cf in=$fl do={
      :local c [$cfmOthCost oth=$oth ap=$ap f=$cf]
      :foreach n in=$nets do={
        :if ([:len [:tostr ($own->[:tostr ($n->0)])]] = 0) do={ :set c ($c + ([$cfmScanW ($n->3)] * [$cfmScanOv $cf ($n->2)])) }
      }
      :set ($fc->($ap . "|" . $cf)) $c
    }
  }
  # Kosten eines Plans {AP-Index -> Frequenz}
  :local cost do={
    :global cfmScanW; :global cfmScanOv
    :local t 0
    :for i from=0 to=([:len $aps] - 1) do={
      :local a ($aps->$i)
      :set t ($t + ($fc->($a . "|" . ($pl->$i))))
      :for j from=0 to=([:len $aps] - 1) do={
        :if ($j != $i) do={
          :local s ($nb->($a . "|" . ($aps->$j)))
          :if ([:typeof $s] = "num") do={ :set t ($t + (2 * [$cfmScanW $s] * [$cfmScanOv ($pl->$i) ($pl->$j)])) }
        }
      }
    }
    :return $t
  }
  # Kanal für Zigbee/Thread mit "auto" zu einem Plan: am wenigsten von dessen WLAN-Kanälen überdeckt
  # (APs aus near dreifach), nicht auf oder neben einem anderen 802.15.4-Netz, 26 nur nachrangig
  # (manche Geräte können ihn nicht oder nur mit weniger Leistung); bei Gleichstand der Kanal mit dem
  # größten Abstand zum nächsten WLAN-Kanal, dann der niedrigste
  :local auto do={
    :global cfmOthOv; :global cfmOthNear
    :local out ""
    :local used ({})
    :foreach k,e in=$oth do={
      :local t [:tostr ($e->"type")]
      :local c [:tonum ($e->"ch")]
      :if (($t = "zigbee" or $t = "thread") and [:typeof $c] = "num") do={ :set ($used->[:len $used]) $c }
    }
    :foreach k,e in=$oth do={
      :local t [:tostr ($e->"type")]
      :if (($t = "zigbee" or $t = "thread") and [:typeof [:tonum ($e->"ch")]] != "num") do={
        :local bk 0
        :local bs 0
        :for z from=11 to=26 do={
          :local fz (2405 + (5 * ($z - 11)))
          :local sc 0
          :local md 99
          :for i from=0 to=([:len $aps] - 1) do={
            :local m 1
            :if ([$cfmOthNear $e ($aps->$i)]) do={ :set m 3 }
            :set sc ($sc + ($m * [$cfmOthOv ($pl->$i) $fz]))
            :local d (($pl->$i) - $fz)
            :if ($d < 0) do={ :set d (0 - $d) }
            :if ($d < $md) do={ :set md $d }
          }
          :foreach u in=$used do={
            :local d ($u - $z)
            :if ($d < 0) do={ :set d (0 - $d) }
            :if ($d = 0) do={ :set sc ($sc + 100) }
            :if ($d = 1) do={ :set sc ($sc + 2) }
          }
          # 26 verliert nur gleiche Kosten (halber Punkt), der Abstand entscheidet erst danach
          :set sc ($sc * 2)
          :if ($z = 26) do={ :set sc ($sc + 1) }
          :local v (($sc * 100) - $md)
          # v wird negativ (Abstand abgezogen) - erster Kanal über bk = 0, nicht über bs < 0
          :if ($bk = 0 or $v < $bs) do={ :set bs $v; :set bk $z }
        }
        :set ($used->[:len $used]) $bk
        :set out ($out . "  " . $k . " (" . $t . "): Kanal " . $bk . " (" . (2405 + (5 * ($bk - 11))) . " MHz)\n")
      }
    }
    :return $out
  }
  :if ($curOk) do={
    :local s ""
    :for i from=0 to=($na - 1) do={ :set s ($s . " " . ($aps->$i) . "=" . ($cur->$i)) }
    :put ("Aktuell:            Kosten " . [$cost aps=$aps fc=$fc nb=$nb pl=$cur] . " " . $s)
  }
  :foreach cs in={{"1/6/11";{2412;2437;2462}};{"1/5/9/13";{2412;2432;2452;2472}};{"1/5/9";{2412;2432;2452}}} do={
    :local fr ($cs->1)
    :local nk [:len $fr]
    :local best ({})
    :local bc -1
    :if ($na <= 6) do={
      :local tot 1
      :for i from=1 to=$na do={ :set tot ($tot * $nk) }
      :for x from=0 to=($tot - 1) do={
        :local pl ({})
        :local y $x
        :for i from=0 to=($na - 1) do={ :set ($pl->$i) ($fr->($y % $nk)); :set y ($y / $nk) }
        :local c [$cost aps=$aps fc=$fc nb=$nb pl=$pl]
        :if ($bc < 0 or $c < $bc) do={ :set bc $c; :set best $pl }
      }
    } else={
      # schrittweise: je AP den besten Kanal bei festen übrigen, drei Runden
      :for i from=0 to=($na - 1) do={ :set ($best->$i) ($fr->0) }
      :for rd from=1 to=3 do={
        :for i from=0 to=($na - 1) do={
          :foreach cf in=$fr do={
            :local pl ({})
            :for k from=0 to=($na - 1) do={ :set ($pl->$k) ($best->$k) }
            :set ($pl->$i) $cf
            :local c [$cost aps=$aps fc=$fc nb=$nb pl=$pl]
            :if ($bc < 0 or $c < $bc) do={ :set bc $c; :set best $pl }
          }
        }
      }
    }
    :local s ""
    :local wr ""
    :for i from=0 to=($na - 1) do={
      :set s ($s . " " . ($aps->$i) . "=" . ($best->$i))
      :set wr ($wr . ";\"" . ($aps->$i) . "\"={\"2\"=\"" . ($best->$i) . "\"}")
    }
    :put ("Vorschlag " . [$cfmPad ($cs->0) 9] . "Kosten " . $bc . " " . $s)
    :put ("  wifi.rsc: \"radios\"={" . [:pick $wr 1 [:len $wr]] . "}")
    :local ao [$auto aps=$aps pl=$best oth=$oth]
    :if ([:len $ao] > 0) do={ :global cfmPutLines; :put "  Kanal für neue 802.15.4-Netze:"; $cfmPutLines $ao }
  }
  :put "Pins in wifi.rsc behalten Kanäle anderer Bänder bei - bestehende 5/6-GHz-Pins in die Zeile übernehmen."
  :return true
}
