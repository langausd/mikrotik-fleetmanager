# ============================================================
# cfm lib/mgr-net.rsc – Manager-Funktionen: Verkabelung (LLDP) und WLAN-Kanäle (D32, D33)
#   $cfmLinks [accept=yes] [export=yes]
#       Links aus den Nachbartabellen der Geräte (Status-Feld nb), Abgleich mit der Baseline
#       (meta/links.dat; accept=yes friert den aktuellen Stand ein) und mit den Angaben "links"
#       in work/hosts/<name>.rsc. Schreibt state/netzplan.md (Mermaid + Tabelle), mit
#       export=yes zusätzlich state/netzplan.dot (Graphviz) und state/netzplan.csv.
#   $cfmChannels   Kanäle der APs (Status-Feld radios); Warnung, wenn zwei APs am selben Switch
#                  denselben Kanal nutzen (Näherung für "benachbart")
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
  :global cfmInvLoad; :global cfmJson; :global cfmMB; :global cfmHost; :global cfmLoadData
  :local b [$cfmMB]
  :local out ({})
  :foreach name,d in=[$cfmInvLoad] do={
    :local hf ($b . "/work/hosts/" . $name . ".rsc")
    :if ([:len [/file/find where name=$hf]] > 0) do={
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
  :foreach name,d in=$inv do={
    :if (("," . ($d->"role") . ",") ~ ",ap,") do={
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
