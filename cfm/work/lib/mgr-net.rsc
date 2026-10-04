# ============================================================
# cfm lib/mgr-net.rsc – Manager-Funktionen: Verkabelung (LLDP) und WLAN-Kanäle (D32, D33)
#   $cfmLinks [accept=yes] [export=yes]
#       Links aus den Nachbartabellen der Geräte (Status-Feld nb), Abgleich mit der Baseline
#       (meta/links.dat; accept=yes friert den aktuellen Stand ein) und mit den Angaben "links"
#       in work/hosts/<name>.rsc. Schreibt state/netzplan.md (Mermaid + Tabelle), mit
#       export=yes zusätzlich state/netzplan.dot (Graphviz) und state/netzplan.csv.
#   $cfmChannels   Kanäle der APs (Status-Feld radios); Warnung, wenn zwei APs am selben Switch
#                  denselben Kanal nutzen (Näherung für "benachbart")
#   $cfmWifiScan [host=] [band=2] [duration=10s] [data=yes]   Kanal-Scan der APs, Pin-Vorschlag (D56)
#   $cfmNetTick    (aus $cfmTick, alle 15 min) meldet neue oder behobene Abweichungen im Log
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
  :put $term
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
  :put $rows
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
# Vorschlag (nur 2,4 GHz): Kanalsätze 1/6/11 und 1/5/9/13 durchprobieren, Kosten je AP = Summe über
# gehörte Netze: Gewicht (Signal + 95 dB) mal Überlappung der Kanäle (gleich 4/4, 1 Kanal daneben
# 3/4 … ab 4 Kanälen Abstand 0); eigene APs, die sich hören, zählen doppelt. Bis 6 APs alle
# Kombinationen, darüber schrittweise. wifi.rsc bleibt unverändert - die Zeile "radios" zum
# Übernehmen steht in der Ausgabe.
:global cfmScanW do={ :local w ([:tonum $1] + 95); :if ($w < 0) do={ :set w 0 }; :return $w }
:global cfmScanOv do={
  # Überlappung zweier 2,4-GHz-Frequenzen in Vierteln (20 MHz breit, 5 MHz Raster)
  :local d (([:tonum $1] - [:tonum $2]) / 5)
  :if ($d < 0) do={ :set d (0 - $d) }
  :if ($d >= 4) do={ :return 0 }
  :return (4 - $d)
}
:global cfmWifiScan do={
  :global cfmInvLoad; :global cfmJson; :global cfmMB; :global cfmPad; :global cfmExec; :global cfmEnrolled
  :global cfmWrite; :global cfmCapsmen; :global cfmLoadData; :global cfmWifi; :global cfmScanW; :global cfmScanOv
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
  # Kosten je AP und Frequenz (fremde Netze) vorab
  :local fc ({})
  :foreach ap,nets in=($sc->"aps") do={
    :foreach cf in={2412;2432;2437;2452;2462;2472} do={
      :local c 0
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
  :if ($curOk) do={
    :local s ""
    :for i from=0 to=($na - 1) do={ :set s ($s . " " . ($aps->$i) . "=" . ($cur->$i)) }
    :put ("Aktuell:            Kosten " . [$cost aps=$aps fc=$fc nb=$nb pl=$cur] . " " . $s)
  }
  :foreach cs in={{"1/6/11";{2412;2437;2462}};{"1/5/9/13";{2412;2432;2452;2472}}} do={
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
