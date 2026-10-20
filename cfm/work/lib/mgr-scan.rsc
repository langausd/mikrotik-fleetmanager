# ============================================================
# cfm lib/mgr-scan.rsc – Manager-Funktionen: Kanal-Scan der APs und Pin-Vorschlag (D56, D60, D80)
#   $cfmWifiScan [host=<ap>] [band=2] [duration=10s] [data=yes]
#   (Übersicht aller Befehle: lib/mgr-core.rsc; Kanäle der APs: $cfmChannels in lib/mgr-net.rsc)
# ============================================================

# ---------- Kanalplan per Scan (TODO 41, D56) ----------
# $cfmWifiScan [host=<AP>] [band=2|5|6] [duration=10s] [data=yes]
# Jeder AP (Rolle ap, aufgenommen) scannt nacheinander auf seinen Radios des Bands (Standard 2,4 GHz),
# ebenso der CAPsMAN, wenn er mitfunkt (capsmanRadios, TODO 46)
# (/interface/wifi/scan … as-value). Ein Radio unter CAPsMAN-Kontrolle lehnt den Scan am CAP ab
# ("not allowed") - gescannt wird deshalb auf dem CAPsMAN am Interface <AP>-<Band>g (D47, D60), erst
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
:global cfmWifiScan do={
  :global cfmInvLoad; :global cfmJson; :global cfmMB; :global cfmPad; :global cfmExec; :global cfmEnrolled
  :global cfmWrite; :global cfmCapsmen; :global cfmLoadData; :global cfmWifi; :global cfmScanW; :global cfmScanOv
  :global cfmOthCost; :global cfmOthSig; :global cfmOthOv; :global cfmOthNear
  :local b [$cfmMB]
  :local f ($b . "/state/wifiscan.json")
  :local inv [$cfmInvLoad]
  :local bd [:tostr $band]
  :if ([:len $bd] = 0) do={ :set bd "2" }
  :local dur [:tostr $duration]
  :if ([:len $dur] = 0) do={ :set dur "10s" }
  :local sc ({})
  :if ($data = "yes") do={
    :set sc [$cfmJson $f]
    :local tn 0
    :foreach ap,nets in=($sc->"aps") do={ :set tn ($tn + [:len $nets]) }
    :if ($tn = 0) do={ :put "keine Messung mit Netzen in state/wifiscan.json - erst ohne data=yes scannen"; :return false }
    :set bd [:tostr ($sc->"band")]
  } else={
    # rsc-check: erlaubt json-typ (t nur für Menschen, cfm liest es nicht zurück)
    :set sc ({"band"=$bd;"t"=([/system/clock/get date] . " " . [/system/clock/get time]);"own"=({});"aps"=({})})
    # host=: in die letzte Messung desselben Bands einfügen (die übrigen APs müssen nicht neu scannen)
    :if ([:len $host] > 0) do={
      :local old [$cfmJson $f]
      :if ([:tostr ($old->"band")] = $bd and [:typeof ($old->"aps")] = "array") do={
        :set ($sc->"aps") ($old->"aps")
        :if ([:typeof ($old->"own")] = "array") do={ :set ($sc->"own") ($old->"own") }
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
            :if ([:typeof $fq] = "num" and [:len $sg] > 0) do={ :set ($nets->[:len $nets]) ({("m" . $bss);[:tostr ($x->"ssid")];$fq;[:tonum $sg]}) }
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
  :if ($bd != "2") do={ :put "Vorschlag nur für 2,4 GHz"; :return true }
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
  :for i from=0 to=($na - 1) do={
    :local st [$cfmJson ($b . "/state/" . ($aps->$i) . "/status.dat")]
    :local cq ""
    :foreach r in=($st->"radios") do={
      :local ch [:pick [:tostr ($r->1)] 1 99]
      :local fq [:tonum [:pick $ch 0 [:find ($ch . "/") "/"]]]
      :if ([:typeof $fq] = "num" and $fq < 2500) do={ :set cq $fq }
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
