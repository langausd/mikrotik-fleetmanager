# ============================================================
# cfm lib/mgr-net.rsc – Manager-Funktionen: Verkabelung (LLDP), WLAN-Kanäle, Gerätesuche (D32, D33, D81)
#   $cfmLinks [accept=yes] [export=yes]
#       Links aus den Nachbartabellen der Geräte (Status-Feld nb), Abgleich mit der Baseline
#       (meta/links.dat; accept=yes friert den aktuellen Stand ein) und mit den Angaben "links"
#       in work/hosts/<name>.rsc. Schreibt state/netzplan.md (Mermaid + Tabelle), mit
#       export=yes zusätzlich state/netzplan.dot (Graphviz) und state/netzplan.csv.
#   $cfmChannels   Kanäle der APs (Status-Feld radios); Warnung, wenn zwei APs am selben Switch
#                  denselben Kanal nutzen (Näherung für "benachbart")
#   (Kanal-Scan der APs mit Pin-Vorschlag, $cfmWifiScan: lib/mgr-scan.rsc)
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
