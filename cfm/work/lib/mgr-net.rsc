# ============================================================
# cfm lib/mgr-net.rsc – Manager-Funktionen: Verkabelung (LLDP), WLAN-Kanäle, Gerätesuche (D32, D33, D81)
#   $cfmLinks [accept=yes] [export=yes]
#       Links aus den Nachbartabellen der Geräte (Status-Feld nb), Abgleich mit der Baseline
#       (meta/links.dat; accept=yes friert den aktuellen Stand ein) und mit den Angaben "links"
#       in work/hosts/<name>.rsc. Schreibt state/netzplan.md (Mermaid + Tabelle), mit
#       export=yes zusätzlich state/netzplan.dot (Graphviz) und state/netzplan.csv.
#   $cfmChannels   Kanäle der APs (Status-Feld radios); Warnung, wenn zwei APs am selben Switch
#                  denselben Kanal nutzen (Näherung für "benachbart")
#   $cfmWifiScan [host=] [band=2] [duration=10s] [data=yes]   Kanal-Scan der APs, Pin-Vorschlag (D56)
#   $cfmNetTick    (aus $cfmTick, alle 15 min) meldet neue oder behobene Abweichungen im Log
#   $cfmFind [text] [host=] [port=] [ap=] [ssid=] [vlan=] [signal=]   wo hängt ein Gerät? (D81)
#   (Übersicht aller Befehle: lib/mgr-core.rsc)
# ============================================================

# Links aus den gemeldeten Nachbarn. Schlüssel "a:pa|b:pb" (verwaltete Geräte, jede Richtung nur
# einmal) bzw. "a:pa|~name" (fremde Geräte) -> {"a";"pa";"b";"pb";"ext";"beide"}
:global cfmLinkScan do={
  :global cfmInvLoad; :global cfmJson; :global cfmMB
  :local b [$cfmMB]
  :local inv [$cfmInvLoad]
  :local lk ({})
  :foreach name,d in=$inv do={
    :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
    :foreach e in=($s->"nb") do={
      :local pt [:tostr ($e->0)]
      :local peer [:tostr ($e->1)]
      :local rp [:tostr ($e->2)]
      :if ([:len $peer] > 0 and [:typeof ($inv->$peer)] = "array") do={
        :local k1 ($name . ":" . $pt . "|" . $peer . ":" . $rp)
        :local k2 ($peer . ":" . $rp . "|" . $name . ":" . $pt)
        :if ([:typeof ($lk->$k2)] = "array") do={ :set ($lk->$k2->"beide") true } else={
          :if ([:typeof ($lk->$k1)] != "array") do={ :set ($lk->$k1) ({"a"=$name;"pa"=$pt;"b"=$peer;"pb"=$rp;"ext"=false;"beide"=false}) }
        }
      } else={
        :local lbl $peer
        :if ([:len $lbl] = 0) do={ :set lbl [:pick [:tostr ($e->3)] 1 99] }
        :set ($lk->($name . ":" . $pt . "|~" . $lbl)) ({"a"=$name;"pa"=$pt;"b"=$lbl;"pb"=$rp;"ext"=true;"beide"=false})
      }
    }
  }
  :return $lk
}

# Angaben "links" aus work/hosts/<name>.rsc gegen die gemeldeten Nachbarn -> Liste von Meldungen.
# Wert "gerät:port", "gerät" (beliebiger Port) oder "-" (dort darf nichts hängen)
:global cfmLinkExpect do={
  :global cfmInvLoad; :global cfmJson; :global cfmMB; :global cfmHost; :global cfmLoadData; :global cfmFileEx
  :local b [$cfmMB]
  :local out ({})
  :foreach name,d in=[$cfmInvLoad] do={
    :local hf ($b . "/work/hosts/" . $name . ".rsc")
    :if ([$cfmFileEx $hf]) do={
      :set cfmHost ({})
      :onerror e in={ /import file-name=$hf verbose=no } do={}
      :local ex ($cfmHost->"links")
      :if ([:typeof $ex] = "array") do={
        :local nb ([$cfmJson ($b . "/state/" . $name . "/status.dat")]->"nb")
        :foreach pt,want in=$ex do={
          :local w [:tostr $want]
          :local got ""
          :local ok false
          :foreach e in=$nb do={
            :if ([:tostr ($e->0)] = $pt) do={
              :local g ([:tostr ($e->1)] . ":" . [:tostr ($e->2)])
              :if ([:len $got] > 0) do={ :set got ($got . ", ") }
              :set got ($got . $g)
              :if ($g = $w or [:tostr ($e->1)] = $w) do={ :set ok true }
            }
          }
          :if ($w = "-") do={ :set ok ([:len $got] = 0) }
          :if ([:len $got] = 0) do={ :set got "nichts" }
          :if (!$ok) do={ :set ($out->[:len $out]) ($name . " " . $pt . ": erwartet " . $w . ", gefunden " . $got) }
        }
      }
    }
  }
  # Hostfiles setzen u.U. Overrides in cfmG -> Daten neu laden
  :onerror e in={ $cfmLoadData } do={}
  :return $out
}

:global cfmLinks do={
  :global cfmLinkScan; :global cfmLinkExpect; :global cfmJson; :global cfmWrite; :global cfmRead
  :global cfmMB; :global cfmPad; :global cfmInvLoad
  :local b [$cfmMB]
  :local lk [$cfmLinkScan]
  :local bf ($b . "/meta/links.dat")
  # Baseline einfrieren (Datum mit Präfix: :deserialize machte daraus sonst einen Zeitwert)
  :if ($accept = "yes") do={
    :local ks ({})
    :foreach k,l in=$lk do={ :set ($ks->[:len $ks]) $k }
    $cfmWrite $bf [:serialize to=json ({"links"=$ks;"date"=("@" . [/system/clock/get date] . " " . [/system/clock/get time])})]
    :if ($quiet != "yes") do={ :put ("Baseline gespeichert: " . [:len $ks] . " Links") }
  }
  :local bj [$cfmJson $bf]
  :local hasBl ([:typeof ($bj->"links")] = "array")
  :local bl ({})
  :if ($hasBl) do={ :foreach x in=($bj->"links") do={ :set ($bl->[:tostr $x]) 1 } }

  # Status je Link: ok | einseitig (nur eine Seite meldet) | extern | neu (nicht in der Baseline)
  :local seen ({})
  :foreach k,l in=$lk do={
    :local rk (($l->"b") . ":" . ($l->"pb") . "|" . ($l->"a") . ":" . ($l->"pa"))
    :local st "ok"
    :if ($hasBl) do={
      :if ([:typeof ($bl->$k)] = "nothing" and [:typeof ($bl->$rk)] = "nothing") do={ :set st "neu" } else={ :set ($seen->$k) 1; :set ($seen->$rk) 1 }
    }
    :if ($st = "ok" and ($l->"ext")) do={ :set st "extern" }
    :if ($st = "ok" and !($l->"beide")) do={ :set st "einseitig" }
    :set ($lk->$k->"st") $st
  }
  # Baseline-Links, die niemand mehr meldet: fehlt
  :if ($hasBl) do={
    :foreach x,v in=$bl do={
      :if ([:typeof ($seen->$x)] = "nothing") do={
        :local p [:find $x "|"]
        :local l1 [:pick $x 0 $p]
        :local l2 [:pick $x ($p + 1) [:len $x]]
        :local c1 [:find $l1 ":"]
        :local r ({"a"=[:pick $l1 0 $c1];"pa"=[:pick $l1 ($c1 + 1) [:len $l1]];"ext"=false;"st"="fehlt";"b"="";"pb"=""})
        :if ([:pick $l2 0 1] = "~") do={ :set ($r->"ext") true; :set ($r->"b") [:pick $l2 1 [:len $l2]] } else={
          :local c2 [:find $l2 ":"]
          :set ($r->"b") [:pick $l2 0 $c2]
          :set ($r->"pb") [:pick $l2 ($c2 + 1) [:len $l2]]
        }
        :set ($lk->("fehlt|" . $x)) $r
      }
    }
  }

  # Abweichungen: Baseline (neu/fehlt) und Hostfile-Angaben
  :local dev ({})
  :foreach k,l in=$lk do={
    :if (($l->"st") = "neu" or ($l->"st") = "fehlt") do={
      :local bp ($l->"b")
      :if ([:len ($l->"pb")] > 0) do={ :set bp ($bp . ":" . ($l->"pb")) }
      :set ($dev->[:len $dev]) (($l->"st") . ": " . ($l->"a") . ":" . ($l->"pa") . " - " . $bp)
    }
  }
  :foreach m in=[$cfmLinkExpect] do={ :set ($dev->[:len $dev]) $m }

  # Netzplan: Knoten = alle Geräte des Inventars + fremde Nachbarn
  :local ids ({})
  :local nodes ""
  :local i 0
  :foreach n,d in=[$cfmInvLoad] do={
    :set ($ids->$n) ("n" . $i)
    :set nodes ($nodes . "  n" . $i . "[\"" . $n . "\"]\n")
    :set i ($i + 1)
  }
  :local edges ""
  :local dot ""
  :local csv "geraet_a;port_a;geraet_b;port_b;status\n"
  :local tab "| Gerät A | Port | Gerät B | Port | Status |\n|---|---|---|---|---|\n"
  :local term ""
  :foreach k,l in=$lk do={
    :local bk ($l->"b")
    :if ($l->"ext") do={ :set bk ("~" . ($l->"b")) }
    :if ([:typeof ($ids->$bk)] = "nothing") do={
      :set ($ids->$bk) ("x" . $i)
      :set nodes ($nodes . "  x" . $i . "([\"" . ($l->"b") . "\"])\n")
      :set i ($i + 1)
    }
    :if ([:typeof ($ids->($l->"a"))] = "nothing") do={
      :set ($ids->($l->"a")) ("x" . $i)
      :set nodes ($nodes . "  x" . $i . "[\"" . ($l->"a") . "\"]\n")
      :set i ($i + 1)
    }
    :local ar "---"
    :local ds ""
    :if (($l->"st") = "neu") do={ :set ar "==="; :set ds ", style=bold" }
    :if (($l->"st") = "fehlt") do={ :set ar "-.-"; :set ds ", style=dashed" }
    :local lab (($l->"pa") . " / " . ($l->"pb"))
    :set edges ($edges . "  " . ($ids->($l->"a")) . " " . $ar . "|\"" . $lab . "\"| " . ($ids->$bk) . "\n")
    :set dot ($dot . "  \"" . ($l->"a") . "\" -- \"" . ($l->"b") . "\" [label=\"" . $lab . "\"" . $ds . "];\n")
    :set csv ($csv . ($l->"a") . ";" . ($l->"pa") . ";" . ($l->"b") . ";" . ($l->"pb") . ";" . ($l->"st") . "\n")
    :set tab ($tab . "| " . ($l->"a") . " | " . ($l->"pa") . " | " . ($l->"b") . " | " . ($l->"pb") . " | " . ($l->"st") . " |\n")
    :set term ($term . [$cfmPad ($l->"a") 10] . [$cfmPad ($l->"pa") 14] . [$cfmPad ($l->"b") 18] . [$cfmPad ($l->"pb") 14] . ($l->"st") . "\n")
  }
  :local body ("```mermaid\ngraph LR\n" . $nodes . $edges . "```\n\n" . $tab)
  :if ([:len $dev] > 0) do={
    :set body ($body . "\n## Abweichungen\n\n")
    :foreach x in=$dev do={ :set body ($body . "- " . $x . "\n") }
  }
  # nur schreiben, wenn sich der Inhalt geändert hat (die Git-Sicherung reagiert auf Änderungen)
  :local sig [:convert $body transform=md5 to=hex]
  :local mf ($b . "/state/netzplan.md")
  :if ($quiet != "yes" or !([$cfmRead $mf] ~ $sig)) do={
    :local bld "keine (\$cfmLinks accept=yes)"
    :if ($hasBl) do={ :set bld [:pick [:tostr ($bj->"date")] 1 99] }
    $cfmWrite $mf ("# Netzplan (cfm)\n\nStand: " . [/system/clock/get date] . " " . [/system/clock/get time] . ", " . [:len $lk] . " Links, Baseline: " . $bld . "\n<!-- sig=" . $sig . " -->\n\n" . $body)
  }
  :if ($export = "yes") do={
    $cfmWrite ($b . "/state/netzplan.dot") ("graph netzplan {\n  node [shape=box];\n" . $dot . "}\n")
    $cfmWrite ($b . "/state/netzplan.csv") $csv
  }
  :if ($quiet = "yes") do={ :return $dev }
  :put ([$cfmPad "GERAET" 10] . [$cfmPad "PORT" 14] . [$cfmPad "NACHBAR" 18] . [$cfmPad "PORT" 14] . "STATUS")
  :global cfmPutLines; $cfmPutLines $term
  :if (!$hasBl) do={ :put "Noch keine Baseline: \$cfmLinks accept=yes friert den aktuellen Stand ein." }
  :foreach x in=$dev do={ :put ("Abweichung: " . $x) }
  :put ("geschrieben: " . $mf)
  :if ($export = "yes") do={ :put ("zusätzlich: " . $b . "/state/netzplan.dot und netzplan.csv") }
  :return $dev
}

# ---------- WLAN-Kanäle ----------
:global cfmChannels do={
  :global cfmInvLoad; :global cfmJson; :global cfmMB; :global cfmPad
  :local b [$cfmMB]
  :local inv [$cfmInvLoad]
  :local rows ""
  :local n 0
  :local by ({})
  # APs und der CAPsMAN, sofern er eigene Radios meldet (capsmanRadios, TODO 46)
  :global cfmCapsmen
  :local cmSet ({})
  :foreach c in=[$cfmCapsmen $inv] do={ :set ($cmSet->[:tostr ($c->"n")]) 1 }
  :foreach name,d in=$inv do={
    :if ((("," . ($d->"role") . ",") ~ ",ap,") or [:typeof ($cmSet->$name)] != "nothing") do={
      :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
      # Switch am Uplink = verwalteter Nachbar des APs
      :local sw ""
      :foreach e in=($s->"nb") do={ :if ([:typeof ($inv->[:tostr ($e->1)])] = "array") do={ :set sw [:tostr ($e->1)] } }
      :foreach r in=($s->"radios") do={
        :local ch [:pick [:tostr ($r->1)] 1 99]
        :local fq [:pick $ch 0 [:find ($ch . "/") "/"]]
        :set n ($n + 1)
        :set rows ($rows . [$cfmPad $name 10] . [$cfmPad [:tostr ($r->0)] 10] . [$cfmPad $ch 22] . $sw . "\n")
        :if ([:len $fq] > 0 and [:len $sw] > 0) do={
          :local k ($sw . "|" . $fq)
          :if ([:typeof ($by->$k)] != "array") do={ :set ($by->$k) ({}) }
          :set ($by->$k->[:len ($by->$k)]) ($name . ":" . [:tostr ($r->0)])
        }
      }
    }
  }
  :local warn ({})
  :foreach k,l in=$by do={
    :if ([:len $l] > 1) do={
      :local p [:find $k "|"]
      :local lst ""
      :foreach x in=$l do={ :set lst ($lst . " " . $x) }
      :set ($warn->[:len $warn]) ("Kanal " . [:pick $k ($p + 1) [:len $k]] . " mehrfach an " . [:pick $k 0 $p] . ":" . $lst)
    }
  }
  :if ($quiet = "yes") do={ :return $warn }
  :if ($n = 0) do={
    :put "keine Funkdaten: APs melden ihre Kanäle mit jedem Agent-Lauf (Status-Feld radios)"
    :return $warn
  }
  :put ([$cfmPad "AP" 10] . [$cfmPad "RADIO" 10] . [$cfmPad "KANAL" 22] . "SWITCH")
  :global cfmPutLines; $cfmPutLines $rows
  :foreach x in=$warn do={ :put ("Warnung: " . $x) }
  :return $warn
}

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

# ---------- Automatische Prüfung (aus $cfmTick) ----------
:global cfmNetT
:global cfmNetTick do={
  :global cfmNetT; :global cfmNow; :global cfmLinks; :global cfmChannels; :global cfmMB
  :global cfmJson; :global cfmWrite
  :local now [$cfmNow]
  :if (($now - [:tonum $cfmNetT]) < 900) do={ :return false }
  :set cfmNetT $now
  :local dev [$cfmLinks quiet=yes]
  :foreach x in=[$cfmChannels quiet=yes] do={ :set ($dev->[:len $dev]) $x }
  :local sig ("s" . [:convert [:tostr $dev] transform=md5 to=hex])
  :local f ([$cfmMB] . "/meta/netcheck.dat")
  :local nj [$cfmJson $f]
  :if ($sig != [:tostr ($nj->"sig")]) do={
    :foreach x in=$dev do={ :log warning ("cfm: Netz: " . $x) }
    :if ([:len $dev] = 0) do={ :log info "cfm: Netz: keine Abweichungen" }
    :set ($nj->"sig") $sig
    $cfmWrite $f [:serialize to=json $nj]
  }
  :return true
}

# ---------- Gerätesuche (TODO 53) ----------
# Teiltext als Regex ohne Rücksicht auf Groß-/Kleinschreibung (die RouterOS-Regex kennt kein (?i)),
# Sonderzeichen maskiert. Eine MAC darf auch als aabbccddeeff oder aa-bb-cc-… kommen.
:global cfmCiRe do={
  :local lo "abcdefghijklmnopqrstuvwxyz"; :local up "ABCDEFGHIJKLMNOPQRSTUVWXYZ"; :local sp ".^\$*+?()[]{}|\\"
  :local s [:tostr $1]
  :if ([:len $s] = 12 and $s ~ "^[0-9A-Fa-f]+\$") do={
    :local m ""
    :for i from=0 to=10 step=2 do={ :if ($i > 0) do={ :set m ($m . ":") }; :set m ($m . [:pick $s $i ($i + 2)]) }
    :set s $m
  }
  :if ($s ~ "^[0-9A-Fa-f]+(-[0-9A-Fa-f]+)+\$") do={
    :local m ""
    :for i from=0 to=([:len $s] - 1) do={ :local c [:pick $s $i]; :if ($c = "-") do={ :set c ":" }; :set m ($m . $c) }
    :set s $m
  }
  :local r ""
  :if ([:len $s] = 0) do={ :return $r }
  :for i from=0 to=([:len $s] - 1) do={
    :local c [:pick $s $i]
    :local p [:find $lo $c]; :local q [:find $up $c]
    :if ([:typeof $p] = "num") do={ :set c ("[" . $c . [:pick $up $p] . "]") } else={
      :if ([:typeof $q] = "num") do={ :set c ("[" . [:pick $lo $q] . $c . "]") } else={
        :if ([:typeof [:find $sp $c]] = "num") do={ :set c ("\\" . $c) }
      }
    }
    :set r ($r . $c)
  }
  :return $r
}
# Wo hängt ein Gerät? Fragt alle aufgenommenen Geräte live per SSH ab (Bridge-Hosts, ARP, DHCP-Leases,
# auf CAPsMAN und APs die WLAN-Registrierung) und verknüpft alles über die MAC. Endpunkt ist ein Port
# ohne verwalteten Nachbarn (LLDP/MNDP; ein Bond über seine Ports). Unter mehreren solchen Ports gilt
# der mit den wenigsten MACs: Ein Port zu einem fremden Switch oder Hypervisor sieht viele (an einem Standort die
# VLAN-Karte des CHR hinter der PVE-Bridge alle 50 im VLAN), der Port des Geräts wenige. Wer nur an
# Uplinks auftaucht, steht mit "über Uplink" da (z.B. hinter einem Port mit verwaltetem Nachbarn).
# data=<datei>: statt der Geräte gespeicherte Antworten {"<gerät>"=<Antwort>} auswerten (Labor: das CHR
# hat keine Clients und kein WLAN). quiet=yes: keine Tabelle (Meldungen zu stummen Geräten bleiben).
# Rückgabe (cfm-Monitor): Liste {"mac";"ip"=(..);"name"=(..);"best"={Gerät;Port;VLAN;Nachbar;MACs};
# "uplink"=true|false;"links"=Links per LLDP (eigenes Gerät);"w"={"ap";"band";"ssid";"sig";"up";"vid";"rate"};"src"=Gerät mit ARP/Lease}
:global cfmFind do={
  :global cfmInvLoad; :global cfmEnrolled; :global cfmExec; :global cfmCapsmen; :global cfmPad
  :global cfmCiRe; :global cfmMB; :global cfmJson; :global cfmG; :global cfmNet
  :local q [:tostr $1]; :local fh [:tostr $host]; :local fp [:tostr $port]; :local fa [:tostr $ap]
  :local fs [:tostr $ssid]; :local fv [:tostr $vlan]; :local fg [:tostr $signal]
  :local say ($quiet != "yes")
  :if ([:len ($q . $fh . $fp . $fa . $fs . $fv . $fg)] = 0) do={
    :put "Aufruf: \$cfmFind <text> [host=<gerät>] [port=<port>] [ap=<ap>] [ssid=<ssid>] [vlan=<vid>] [signal=<dBm>]"
    :put "  text: Teil einer MAC, IP, eines Namens, Geräts/Ports, APs oder einer SSID (groß/klein egal)"
    :put "  signal=-75: nur WLAN-Clients mit -75 dBm oder schwächer"
    :return ({})
  }
  :local re [$cfmCiRe $q]
  :local t0 [:timestamp]
  # Namen aus work/leases.rsc, ohne die globale Variable anzufassen (der Agent des Managers nutzt sie
  # beim Apply) und ohne /import (meldet jede Datei im Terminal): ":global cfmLeases" wird lokal
  :local lz ({})
  :onerror e in={
    :local c ("\n" . [/file/get ([$cfmMB] . "/work/leases.rsc") contents])
    :local p [:find $c "\n:global cfmLeases"]
    :if ([:typeof $p] = "num") do={
      :local fn [:parse ([:pick $c 0 $p] . "\n:local cfmLeases" . [:pick $c ($p + 18) [:len $c]] . "\n:return \$cfmLeases")]
      :set lz [$fn]
    }
  } do={}
  :local inv [$cfmInvLoad]
  :local cms ({})
  :foreach c in=[$cfmCapsmen $inv] do={ :set ($cms->[:tostr ($c->"n")]) 1 }
  :local dc ":local f ({}); :local n ({}); :local b ({}); :local a ({}); :local l ({}); :local w ({}); :foreach i in=[/ip/neighbor/find] do={ :local g [/ip/neighbor/get \$i]; :local iv (\$g->\"interface\"); :local p [:tostr \$iv]; :if ([:typeof \$iv] = \"array\") do={ :set p [:tostr (\$iv->0)] }; :set (\$n->\$p) ([:tostr (\$n->\$p)] . \",\" . [:tostr (\$g->\"identity\")]) }; :foreach i in=[/interface/bonding/find] do={ :set (\$b->[/interface/bonding/get \$i name]) [/interface/bonding/get \$i slaves] }; :foreach i in=[/interface/bridge/host/find where !local] do={ :local g [/interface/bridge/host/get \$i]; :set (\$f->[:len \$f]) ({[:tostr (\$g->\"mac-address\")];[:tostr (\$g->\"on-interface\")];[:tostr (\$g->\"vid\")]}) }; :foreach i in=[/ip/arp/find] do={ :local g [/ip/arp/get \$i]; :if ([:len [:tostr (\$g->\"mac-address\")]] > 0) do={ :set (\$a->[:len \$a]) ({[:tostr (\$g->\"address\")];[:tostr (\$g->\"mac-address\")];[:tostr (\$g->\"interface\")]}) } }; :foreach i in=[/ip/dhcp-server/lease/find] do={ :local g [/ip/dhcp-server/lease/get \$i]; :set (\$l->[:len \$l]) ({[:tostr (\$g->\"address\")];[:tostr (\$g->\"mac-address\")];[:tostr (\$g->\"host-name\")];[:tostr (\$g->\"status\")];[:tostr (\$g->\"comment\")]}) }; "
  :local wc ":foreach i in=[/interface/wifi/registration-table/find] do={ :local g [/interface/wifi/registration-table/get \$i]; :set (\$w->[:len \$w]) ({[:tostr (\$g->\"mac-address\")];[:tostr (\$g->\"interface\")];[:tostr (\$g->\"ssid\")];[:tostr (\$g->\"signal\")];[:tostr (\$g->\"band\")];[:tostr (\$g->\"uptime\")];[:tostr (\$g->\"vlan-id\")];[:tostr (\$g->\"tx-rate\")]}) }; "
  :local ec ":put [:serialize to=json ({\"f\"=\$f;\"n\"=\$n;\"b\"=\$b;\"a\"=\$a;\"l\"=\$l;\"w\"=\$w})]"
  :local dat ({}); :local ok ({})
  :if ([:len $data] > 0) do={ :set dat [$cfmJson ([$cfmMB] . "/" . $data)]; :foreach n,x in=$dat do={ :set ($ok->$n) 1 } }
  :foreach name,d in=$inv do={
    :local ip [:tostr ($d->"ip")]
    :if ([:len $data] = 0 and [:len $ip] > 0 and [$cfmEnrolled $d]) do={
      :if ([:typeof ([/ping $ip count=1 as-value]->"time")] = "time") do={
        :local c $dc
        :if ((("," . [:tostr ($d->"role")] . ",") ~ ",ap,") or [:typeof ($cms->$name)] != "nothing") do={ :set c ($c . $wc) }
        :local r [$cfmExec ip=$ip cmd=($c . $ec)]
        :local j
        :onerror e in={ :set j [:deserialize from=json ($r->"output")] } do={}
        :if ([:typeof $j] = "array") do={ :set ($dat->$name) $j; :set ($ok->$name) 1 } else={
          :put ("  " . $name . ": keine Daten (" . [:pick [:tostr ($r->"output")] 0 100] . ")")
        }
      } else={ :put ("  " . $name . ": nicht erreichbar") }
    }
  }
  # Verknüpfen: "m<MAC>" -> Eintrag
  :local rec ({})
  :local nr ({"mac"="";"ip"=({});"name"=({});"loc"=({});"up"=({});"lldp"=({});"w"=({});"src"=""})
  # eigene Geräte: Bridge-MAC aus dem Status (inm: Name -> Schlüssel, für den Ort per LLDP)
  :local inm ({})
  :foreach name,d in=$inv do={
    :local m [:tostr ([$cfmJson ([$cfmMB] . "/state/" . $name . "/status.dat")]->"mac")]
    :if ([:len $m] > 0) do={
      :local k ("m" . $m)
      :if ([:typeof ($rec->$k)] = "nothing") do={ :set ($rec->$k) $nr; :set ($rec->$k->"mac") $m }
      :set ($rec->$k->"name"->[:len ($rec->$k->"name")]) $name
      :set ($rec->$k->"ip"->[:len ($rec->$k->"ip")]) [:tostr ($d->"ip")]
      :set ($inm->$name) $k
    }
  }
  :foreach vid,ents in=$lz do={
    :foreach nm,o in=$ents do={
      :local m ""
      :local s [:tostr ($o->"mac")]
      :if ([:len $s] > 0) do={ :for i from=0 to=([:len $s] - 1) do={
        :local c [:pick $s $i]; :local x [:find "abcdef" $c]
        :if ([:typeof $x] = "num") do={ :set c [:pick "ABCDEF" $x] }
        :set m ($m . $c)
      } }
      :local k ("m" . $m)
      :if ([:typeof ($rec->$k)] = "nothing") do={ :set ($rec->$k) $nr; :set ($rec->$k->"mac") $m }
      :set ($rec->$k->"name"->[:len ($rec->$k->"name")]) $nm
      # feste Adresse aus dem Host-Anteil (Netz des VLANs per $cfmNet aus der Gerätebibliothek)
      :local nn ({})
      :onerror e in={ :set nn [$cfmNet $vid] } do={}
      :if ([:len [:tostr ($nn->"net")]] > 0 and [:typeof [:tonum ($o->"ip")]] = "num") do={
        :local la [:tostr (($nn->"addr") + [:tonum ($o->"ip")])]
        :if ([:typeof [:find ($rec->$k->"ip") $la]] != "num") do={ :set ($rec->$k->"ip"->[:len ($rec->$k->"ip")]) $la }
      }
    }
  }
  :foreach dv,j in=$dat do={
    # Uplinks: Ports mit einem verwalteten, erreichbaren Nachbarn
    :local nb ($j->"n"); :local upl ({})
    :foreach p,ids in=$nb do={
      :foreach x in=[:toarray [:tostr $ids]] do={ :if ([:typeof ($ok->[:tostr $x])] != "nothing") do={ :set ($upl->$p) [:tostr $x] } }
    }
    :foreach bn,sl in=($j->"b") do={
      :foreach s in=$sl do={ :if ([:typeof ($upl->[:tostr $s])] != "nothing") do={ :set ($upl->$bn) ($upl->[:tostr $s]) } }
    }
    # MACs je Port (Rangfolge mehrerer Endpunkte)
    :local cn ({})
    :foreach e in=($j->"f") do={ :local p [:tostr ($e->1)]; :if ([:typeof ($cn->$p)] = "nothing") do={ :set ($cn->$p) 1 } else={ :set ($cn->$p) (($cn->$p) + 1) } }
    :foreach e in=($j->"f") do={
      :local m [:tostr ($e->0)]; :local p [:tostr ($e->1)]; :local k ("m" . $m)
      :if ([:typeof ($rec->$k)] = "nothing") do={ :set ($rec->$k) $nr; :set ($rec->$k->"mac") $m }
      :local u [:tostr ($upl->$p)]
      :if ([:len $u] > 0) do={
        :set ($rec->$k->"up"->[:len ($rec->$k->"up")]) ({$dv;$p;[:tostr ($e->2)];$u;($cn->$p)})
      } else={
        # fremder Nachbar am Port (z.B. ein Server mit LLDP): erster Name
        :local fn ""
        :foreach x in=[:toarray [:tostr ($nb->$p)]] do={ :if ([:len $fn] = 0) do={ :set fn [:tostr $x] } }
        :set ($rec->$k->"loc"->[:len ($rec->$k->"loc")]) ({$dv;$p;[:tostr ($e->2)];$fn;($cn->$p)})
      }
    }
    # eigene Geräte stehen dort, wo ein anderes sie per LLDP/MNDP an einem Bridge-Port sieht (ihre MAC lernt
    # sonst jeder Port, der MGMT-Verkehr sieht, z.B. die MGMT-Karte eines CHR hinter der PVE-Bridge)
    :foreach p,ids in=$nb do={
      :if ([:typeof ($cn->$p)] != "nothing") do={
        :foreach x in=[:toarray [:tostr $ids]] do={
          :local ik [:tostr ($inm->[:tostr $x])]
          :if ([:len $ik] > 0 and [:tostr $x] != $dv) do={ :set ($rec->$ik->"lldp"->[:len ($rec->$ik->"lldp")]) ({$dv;$p;"";[:tostr $x];($cn->$p)}) }
        }
      }
    }
    # ARP und Leases: IP, Name
    :foreach e in=(($j->"a"), ($j->"l")) do={
      :local m [:tostr ($e->1)]; :local k ("m" . $m)
      :if ([:len $m] > 0) do={
        :if ([:typeof ($rec->$k)] = "nothing") do={ :set ($rec->$k) $nr; :set ($rec->$k->"mac") $m }
        :local ip [:tostr ($e->0)]
        :if ([:typeof [:find ($rec->$k->"ip") $ip]] != "num") do={ :set ($rec->$k->"ip"->[:len ($rec->$k->"ip")]) $ip }
        :if ([:len ($rec->$k->"src")] = 0) do={ :set ($rec->$k->"src") $dv }
        :if ([:len $e] = 5) do={
          :foreach nm in={[:tostr ($e->2)];[:tostr ($e->4)]} do={
            :if ([:len $nm] > 0 and [:typeof [:find ($rec->$k->"name") $nm]] != "num") do={ :set ($rec->$k->"name"->[:len ($rec->$k->"name")]) $nm }
          }
        }
      }
    }
    # WLAN: AP und Band aus dem Interface-Namen <AP>-<Band>g (CAPsMAN), sonst das Gerät selbst
    :foreach e in=($j->"w") do={
      :local m [:tostr ($e->0)]; :local k ("m" . $m)
      :if ([:typeof ($rec->$k)] = "nothing") do={ :set ($rec->$k) $nr; :set ($rec->$k->"mac") $m }
      :local ifn [:tostr ($e->1)]; :local an $dv; :local bs ([:pick [:tostr ($e->4)] 0 1] . "g")
      :local p -1
      :if ([:len $ifn] >= 3) do={ :for i from=0 to=([:len $ifn] - 3) do={ :if ([:pick $ifn $i ($i + 3)] ~ "^-[256]g\$") do={ :set p $i } } }
      :if ($p > 0) do={ :set an [:pick $ifn 0 $p]; :set bs [:pick $ifn ($p + 1) [:len $ifn]] }
      :set ($rec->$k->"w") ({"ap"=$an;"band"=$bs;"ssid"=[:tostr ($e->2)];"sig"=[:tostr ($e->3)];"up"=[:tostr ($e->5)];"vid"=[:tostr ($e->6)];"rate"=[:tostr ($e->7)]})
    }
  }
  # Filtern und ausgeben
  :local res ({})
  :if ($say) do={ :put ([$cfmPad "MAC" 18] . [$cfmPad "IP" 16] . [$cfmPad "Name" 21] . [$cfmPad "Ort" 27] . [$cfmPad "VLAN" 5] . "Info") }
  :foreach k,r in=$rec do={
    :local w ($r->"w"); :local hw ([:len $w] > 0)
    # bester Ort: Port mit den wenigsten MACs, sonst der Uplink mit den wenigsten
    :local dl ($r->"lldp"); :if ([:len $dl] = 0) do={ :set dl ($r->"loc") }; :if ([:len $dl] = 0) do={ :set dl ($r->"up") }
    :local upl ([:len ($r->"lldp")] = 0 and [:len ($r->"loc")] = 0)
    :local bl ({})
    :foreach x in=$dl do={ :if ([:len $bl] = 0 or [:tonum ($x->4)] < [:tonum ($bl->4)]) do={ :set bl $x } }
    # Ort per LLDP hat kein VLAN: das MGMT-VLAN (die Bridge-MAC eines Geräts steht in allen seinen VLANs),
    # sonst aus den Bridge-Einträgen derselben MAC (am selben Port, sonst irgendeinem)
    :if ([:len $bl] > 0 and [:len [:tostr ($bl->2)]] = 0) do={ :set ($bl->2) [:tostr ($cfmG->"mgmtVlan")] }
    :if ([:len $bl] > 0 and [:len [:tostr ($bl->2)]] = 0) do={
      :foreach y in=(($r->"up"), ($r->"loc")) do={
        :if ([:len [:tostr ($bl->2)]] = 0 or (($y->0) = ($bl->0) and ($y->1) = ($bl->1))) do={ :set ($bl->2) [:tostr ($y->2)] }
      }
    }
    :local hay (($r->"mac") . " " . [:tostr ($r->"ip")] . " " . [:tostr ($r->"name")])
    :if ([:len $bl] > 0) do={ :set hay ($hay . " " . ($bl->0) . ":" . ($bl->1) . " " . ($bl->3)) }
    :if ($hw) do={ :set hay ($hay . " " . ($w->"ap") . " " . ($w->"ssid")) }
    :local hit ([:len $re] = 0 or $hay ~ $re)
    :if ($hit and [:len ($fh . $fp . $fv)] > 0) do={
      :local any false
      :if ($hw) do={
        :set any (([:len $fh] = 0 or ($w->"ap") = $fh) and [:len $fp] = 0 and ([:len $fv] = 0 or ($w->"vid") = $fv))
      } else={
        :if ([:len $bl] > 0) do={ :set any (([:len $fh] = 0 or ($bl->0) = $fh) and ([:len $fp] = 0 or ($bl->1) = $fp) and ([:len $fv] = 0 or ($bl->2) = $fv)) }
      }
      :set hit $any
    }
    :if ($hit and [:len ($fa . $fs . $fg)] > 0) do={
      :set hit ($hw and ([:len $fa] = 0 or ($w->"ap") = $fa) and ([:len $fs] = 0 or ($w->"ssid") = $fs))
      :if ($hit and [:len $fg] > 0) do={ :set hit ([:tonum ($w->"sig")] <= [:tonum $fg]) }
    }
    :if ($hit) do={
      :set ($res->[:len $res]) ({"mac"=($r->"mac");"ip"=($r->"ip");"name"=($r->"name");"best"=$bl;"uplink"=$upl;"links"=[:len ($r->"lldp")];"w"=$w;"src"=($r->"src")})
      :if ($say) do={
        :local ip [:tostr (($r->"ip")->0)]; :if ([:len ($r->"ip")] > 1) do={ :set ip ($ip . "+") }
        :local nm [:pick [:tostr (($r->"name")->0)] 0 20]
        :local ort ""; :local vl ""; :local inf ""
        :if ([:len $bl] > 0) do={
          :set ort (($bl->0) . " " . ($bl->1)); :set vl ($bl->2)
          :if ([:len ($r->"lldp")] > 0) do={
            :set inf "cfm-Gerät, per LLDP"
            :if ([:len ($r->"lldp")] > 1) do={ :set inf ("cfm-Gerät, " . [:len ($r->"lldp")] . " Links per LLDP") }
          } else={ :if ($upl) do={ :set inf ("über Uplink zu " . ($bl->3)) } else={
            :if ([:len ($bl->3)] > 0) do={ :set inf ("Nachbar " . ($bl->3)) }
            :if (($bl->4) > 1) do={ :if ([:len $inf] > 0) do={ :set inf ($inf . ", ") }; :set inf ($inf . ($bl->4) . " MACs am Port") }
          } }
        }
        :if ($hw) do={
          :set ort (($w->"ap") . " " . ($w->"band")); :set vl ($w->"vid")
          :set inf (($w->"ssid") . " " . ($w->"sig") . " dBm " . ([:tonum ($w->"rate")] / 1000000) . " Mbit/s seit " . ($w->"up"))
        }
        :if ([:len $ort] = 0) do={ :set ort "-"; :set inf ("nur ARP/Lease bei " . ($r->"src")) }
        :put ([$cfmPad ($r->"mac") 18] . [$cfmPad $ip 16] . [$cfmPad $nm 21] . [$cfmPad [:pick $ort 0 26] 27] . [$cfmPad $vl 5] . $inf)
      }
    }
  }
  :if ($say) do={ :put ([:len $res] . " Treffer, " . [:len $dat] . " Geräte abgefragt in " . ([:tonsec ([:timestamp] - $t0)] / 1000000000) . " s") }
  :return $res
}
