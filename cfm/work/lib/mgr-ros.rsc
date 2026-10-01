# ============================================================
# cfm lib/mgr-ros.rsc – Manager-Funktionen: RouterOS-Pakete und -Updates (D30)
#   $cfmUpgrade ver=<x.y.z> host=<n>|ring=<r>|all=yes [at="YYYY-MM-DD HH:MM"]
#   $cfmUpgrade ver=<x.y.z> host=..|ring=..|all=yes check=yes   Probe ohne Auftrag und ohne Download:
#                     Pakete, fehlende Dateien, Bedarf und freier Platz je Gerät
#   $cfmUpgrade cancel=yes host=..|ring=..|all=yes        $cfmUpgrade   (offene Aufträge)
#   $cfmPkgPrune      nicht mehr genutzte Paketversionen löschen (läuft automatisch)
#   (Übersicht aller Befehle: lib/mgr-core.rsc)
#
# Ablauf: Vor dem Rollout lädt der Manager alle Pakete (routeros + Zusatzpakete) für alle
# betroffenen Architekturen von download.mikrotik.com nach <pkgPath>/<ver>/ (ohne Internet: von Hand
# ablegen, $cfmUpgrade nennt alle fehlenden) und prüft die NPK-Kennung. Geräte, deren gemeldeter
# freier Platz nicht reicht, bekommen keinen Auftrag (TODO 38). Erst wenn alle Pakete da
# sind, landet der Auftrag im signierten Manifest der Geräte (Feld "ros"). Der Agent prüft den Platz
# erneut, holt die Pakete per SFTP vom Manager, prüft die Größe und startet sofort oder zum Zeitpunkt at neu
# (bei älterer Zielversion per /system/package/downgrade). Die Echtheit der Pakete prüft
# RouterOS beim Installieren selbst (signierte npk). Erledigte Aufträge trägt $cfmUpgTick aus.
# Auftragswerte tragen ein Präfix ("rv"="v7.25", "at"="@2026-10-01 02:00", "id"="i…"), weil
# :deserialize Strings wie "7.25.1" in IP-Adressen und Datumsangaben in Zeitwerte umwandelt.
# ============================================================

# "YYYY-MM-DD HH:MM" -> Zahl JJJJMMTTHHMM (Strings lassen sich nicht mit < / > vergleichen)
:global cfmDtNum do={
  :local s [:tostr $1]
  :return [:tonum ([:pick $s 0 4] . [:pick $s 5 7] . [:pick $s 8 10] . [:pick $s 11 13] . [:pick $s 14 16])]
}

# Paketablage: pkgPath aus global.rsc (z.B. USB/NVMe bei kleinem Flash), sonst <cfm>/pkg
:global cfmPkgDir do={
  :global cfmG; :global cfmMB
  :local p [:tostr ($cfmG->"pkgPath")]
  :if ([:len $p] = 0) do={ :set p ([$cfmMB] . "/pkg") }
  :return $p
}

# Echtes RouterOS-Paket? NPK-Kennung in den ersten vier Bytes (1e f1 d0 ba) statt einer Mindestgröße
# (TODO 37: ups-<ver>-arm.npk hat nur ~45 KB, eine Fehlerseite kann größer sein). Ohne /file/read
# (ältere RouterOS-Versionen) bleibt die Größe als grobe Prüfung.
:global cfmPkgOk do={
  :local ok false
  :local rd false
  :onerror e in={
    :local r [/file/read file=$1 chunk-size=4 as-value]
    :set rd true
    :set ok ([:convert ($r->"data") to=hex] = "1ef1d0ba")
  } do={}
  :if (!$rd) do={ :set ok ([/file/get [find where name=$1] size] >= 20000) }
  :return $ok
}

# Paket <pkg>-<ver>[-<arch>].npk bereitstellen (laden, falls es fehlt; dl=no: nur nachsehen)
# -> {"fn"=Dateiname;"sz"=Größe;"err"=""|Grund}. Kein :error, damit $cfmUpgrade alle fehlenden
# Pakete auf einmal nennen kann (Manager ohne Internet: Dateien von Hand ablegen, TODO 37)
:global cfmPkgFetch do={
  :global cfmPkgDir; :global cfmPkgOk
  :local sfx ("-" . $arch)
  :if ($arch ~ "^x86") do={ :set sfx "" }
  :local fn ($pkg . "-" . $ver . $sfx . ".npk")
  :local lp ([$cfmPkgDir] . "/" . $ver . "/" . $fn)
  :local r ({"fn"=$fn;"sz"=0;"err"=""})
  :global cfmFileEx
  :if (![$cfmFileEx $lp]) do={
    :if ($dl = "no") do={ :set ($r->"err") "fehlt"; :return $r }
    :local url ("https://download.mikrotik.com/routeros/" . $ver . "/" . $fn)
    :put ("lade " . $url)
    :local fe ""
    :onerror e in={ /tool/fetch url=$url dst-path=$lp as-value } do={ :set fe $e }
    :if ([:len $fe] > 0) do={
      :onerror e in={ /file/remove [find where name=$lp] } do={}
      :set ($r->"err") ("Download fehlgeschlagen (" . $fe . ")")
      :return $r
    }
    :delay 1s
  }
  :if (![$cfmPkgOk $lp]) do={
    # Probe (dl=no) ändert nichts; sonst weg damit, der nächste Auftrag lädt neu
    :if ($dl = "no") do={ :set ($r->"err") "kein RouterOS-Paket (NPK-Kennung fehlt)"; :return $r }
    /file/remove [find where name=$lp]
    :set ($r->"err") "kein RouterOS-Paket (NPK-Kennung fehlt), gelöscht"
    :return $r
  }
  :set ($r->"sz") [/file/get [find where name=$lp] size]
  :return $r
}

# Bytes -> "12,3 MB"
:global cfmMiB do={
  :local b [:tonum $1]
  :return (($b / 1048576) . "," . (($b % 1048576) * 10 / 1048576) . " MB")
}

# Paketversionen löschen, die kein Gerät installiert hat und kein offener Auftrag nennt
:global cfmPkgPrune do={
  :global cfmPkgDir; :global cfmInvLoad; :global cfmJson; :global cfmMB
  :local b [$cfmMB]
  :local pd [$cfmPkgDir]
  :local used ({})
  :foreach name,d in=[$cfmInvLoad] do={
    :local r [:tostr ([$cfmJson ($b . "/state/" . $name . "/status.dat")]->"ros")]
    :set ($used->[:pick $r 0 [:find ($r . " ") " "]]) 1
  }
  :foreach name,o in=[$cfmJson ($b . "/meta/upgrade.dat")] do={ :set ($used->[:pick [:tostr ($o->"rv")] 1 99]) 1 }
  :local n 0
  :foreach f in=[/file/find where name~("^" . $pd . "/[^/]+\$") and type="directory"] do={
    :local vd [/file/get $f name]
    :local ver [:pick $vd ([:len $pd] + 1) [:len $vd]]
    :if ([:typeof ($used->$ver)] = "nothing") do={
      :foreach x in=[/file/find where name~("^" . $vd . "/")] do={ /file/remove $x }
      :onerror e in={ /file/remove [find where name=$vd] } do={}
      :set n ($n + 1)
      :log info ("cfm: Paketversion " . $ver . " gelöscht (nicht mehr im Einsatz)")
    }
  }
  :return $n
}

:global cfmUpgrade do={
  :global cfmMB; :global cfmInvLoad; :global cfmJson; :global cfmWrite; :global cfmManifests
  :global cfmPush; :global cfmVerGe; :global cfmPkgFetch; :global cfmPkgPrune; :global cfmPkgDir
  :global cfmIsPrimary; :global cfmNow; :global cfmDtNum; :global cfmLoadData; :global cfmPad
  :global cfmEnrolled; :global cfmMiB
  :local b [$cfmMB]
  :local of ($b . "/meta/upgrade.dat")
  :local ord [$cfmJson $of]
  :local inv [$cfmInvLoad]
  # ohne ver/cancel: offene Aufträge anzeigen
  :if ([:len $ver] = 0 and $cancel != "yes") do={
    :if ([:len $ord] = 0) do={ :put "keine offenen RouterOS-Aufträge" }
    :foreach name,o in=$ord do={
      :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
      :local w "sofort"
      :if ([:len [:tostr ($o->"at")]] > 0) do={ :set w [:pick [:tostr ($o->"at")] 1 99] }
      :put ([$cfmPad $name 10] . [$cfmPad ([:tostr ($s->"ros")] . " -> " . [:pick [:tostr ($o->"rv")] 1 99]) 32] . [$cfmPad $w 18] . [:tostr ($s->"upg")])
    }
    :return ""
  }
  :local chk ($check = "yes")
  :if (!$chk and ![$cfmIsPrimary]) do={ :error "nicht Primary: Backup-Manager ist read-only (\$cfmPromoteManager)" }
  :if ([:len $host] = 0 and [:len [:tostr $ring]] = 0 and $all != "yes") do={ :error "Aufruf: \$cfmUpgrade ver=<x.y.z> host=<n>|ring=<r>|all=yes [at=\"YYYY-MM-DD HH:MM\"] [check=yes]" }
  # nur aufgenommene Geräte (TODO 28): Platzhalter melden nie Architektur/Pakete und hielten den Auftrag auf
  :local tg ({})
  :foreach name,d in=$inv do={
    :if ($all = "yes" or $host = $name or ([:len [:tostr $ring]] > 0 and [:tostr $ring] = [:tostr ($d->"ring")])) do={
      :if ([$cfmEnrolled $d]) do={ :set ($tg->$name) $d } else={
        :if ($host = $name) do={ :error ($name . " ist nicht aufgenommen") }
        :put ($name . ": nicht aufgenommen - übersprungen")
      }
    }
  }
  :if ([:len $tg] = 0) do={ :error "kein passendes Gerät im Inventar" }

  # --- Auftrag zurückziehen ---
  :if ($cancel = "yes") do={
    :local no ({})
    :foreach name,o in=$ord do={
      :if ([:typeof ($tg->$name)] = "nothing") do={ :set ($no->$name) $o } else={ :put ("Auftrag " . $name . " zurückgezogen") }
    }
    $cfmWrite $of [:serialize to=json $no]
    $cfmManifests
    :foreach name,d in=$tg do={ $cfmPush host=$name }
    $cfmPkgPrune
    :return ""
  }

  # --- Zeitpunkt prüfen ---
  :local when [:tostr $at]
  :if ([:len $when] > 0) do={
    :if ([:len $when] != 16 or [:pick $when 4 5] != "-" or [:pick $when 10 11] != " " or [:pick $when 13 14] != ":") do={ :error "at im Format \"YYYY-MM-DD HH:MM\" angeben" }
    :local now ([/system/clock/get date] . " " . [:pick [/system/clock/get time] 0 5])
    :if ([$cfmDtNum $when] <= [$cfmDtNum $now]) do={ :error ("at liegt nicht in der Zukunft (jetzt " . $now . ")") }
  }

  # --- je Gerät: Architektur + Pakete aus dem Status, Upgrade oder Downgrade ---
  $cfmLoadData
  :local need ({})
  :local plan ({})
  :local err ""
  :foreach name,d in=$tg do={
    :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
    :local cur [:tostr ($s->"ros")]
    :set cur [:pick $cur 0 [:find ($cur . " ") " "]]
    :local arch [:tostr ($s->"arch")]
    :local pk ($s->"pkgs")
    :if ([:len $arch] = 0 or [:len $pk] = 0) do={ :set err ($err . " " . $name . " (Status ohne Architektur/Pakete, nächsten Agent-Lauf abwarten)") } else={
      :if ($cur = $ver) do={ :put ($name . ": hat bereits " . $ver) } else={
        :local how "upgrade"
        :if (![$cfmVerGe $ver $cur]) do={ :set how "downgrade" }
        :set ($plan->$name) ({"arch"=$arch;"pkgs"=$pk;"how"=$how;"cur"=$cur;"fs"=($s->"fs")})
        :foreach p in=$pk do={ :set ($need->($arch . "|" . $p)) 1 }
      }
    }
  }
  :if ([:len $err] > 0) do={ :error ("Update abgebrochen:" . $err) }
  :if ([:len $plan] = 0) do={ :put "nichts zu tun"; :return "" }

  # --- alle Pakete vor dem Rollout bereitstellen; check=yes lädt nichts, sieht nur nach ---
  :local dl "yes"; :if ($chk) do={ :set dl "no" }
  :local got ({})
  :local miss ""
  :foreach k,x in=$need do={
    :local p [:find $k "|"]
    :local pf [$cfmPkgFetch ver=$ver arch=[:pick $k 0 $p] pkg=[:pick $k ($p + 1) [:len $k]] dl=$dl]
    :if ([:len ($pf->"err")] > 0) do={ :set miss ($miss . "\n  " . ($pf->"fn") . ": " . ($pf->"err")) } else={ :set ($got->$k) ({($pf->"fn");($pf->"sz")}) }
  }
  :local pdir ([$cfmPkgDir] . "/" . $ver)
  :local mhint ""
  :if ([:len $miss] > 0) do={ :set mhint ("Pakete fehlen oder sind ungültig - von https://download.mikrotik.com/routeros/" . $ver . "/<Datei> laden und nach " . $pdir . "/ legen:" . $miss) }

  # --- freier Platz je Gerät (TODO 38): Die Pakete landen im Flash; 1 MB Reserve für Config, Log und
  #     die Sicherung des Agents. Geräte ohne Angabe (flash/-Verzeichnis, älterer Agent) prüft der Agent ---
  :local nospace ({})
  :foreach name,pl in=$plan do={
    :local sum 0
    :local unk false
    :foreach p in=($pl->"pkgs") do={
      :local g ($got->(($pl->"arch") . "|" . $p))
      :if ([:typeof $g] = "array") do={ :set sum ($sum + [:tonum ($g->1)]) } else={ :set unk true }
    }
    :local fs [:tostr ($pl->"fs")]
    :local vd "ok"
    :local fstxt "frei ?"
    :if ([:len $fs] > 0) do={
      :set fstxt ("frei " . [$cfmMiB $fs])
      :if (!$unk and ($sum + 1048576) > [:tonum $fs]) do={ :set vd "zu wenig Platz"; :set ($nospace->$name) 1 }
    }
    :local ntxt "Bedarf ?"
    :if (!$unk) do={ :set ntxt ("Bedarf " . [$cfmMiB $sum]) }
    :if ($unk) do={ :set vd "Pakete fehlen" }
    :put ([$cfmPad $name 12] . [$cfmPad (($pl->"cur") . " -> " . $ver) 20] . [$cfmPad ($pl->"how") 10] . [$cfmPad ($pl->"arch") 8] . [$cfmPad $ntxt 18] . [$cfmPad $fstxt 16] . $vd)
  }
  :if ($chk) do={
    :if ([:len $mhint] > 0) do={ :put $mhint } else={ :put ("alle Pakete liegen in " . $pdir . "/") }
    :put "Probe (check=yes): kein Auftrag erteilt"
    :return ""
  }
  :if ([:len $miss] > 0) do={ :error ("Update abgebrochen: " . $mhint) }
  :foreach name,x in=$nospace do={
    :put ($name . ": zu wenig Platz für die Pakete (+1 MB Reserve) - kein Auftrag; aufräumen oder anders aktualisieren (TODO 38)")
    :set ($plan->$name)
  }
  :if ([:len $plan] = 0) do={ :put "kein Gerät mit genug Platz - nichts zu tun"; :return "" }

  # --- Aufträge schreiben, Manifeste neu signieren, Geräte anstoßen ---
  :local id ("i" . [$cfmNow])
  :local wat ""
  :if ([:len $when] > 0) do={ :set wat ("@" . $when) }
  :local path ([$cfmPkgDir] . "/" . $ver)
  :foreach name,pl in=$plan do={
    :local fl ({})
    :foreach p in=($pl->"pkgs") do={ :set ($fl->[:len $fl]) ($got->(($pl->"arch") . "|" . $p)) }
    :set ($ord->$name) ({"rv"=("v" . $ver);"at"=$wat;"id"=$id;"how"=($pl->"how");"path"=$path;"files"=$fl})
  }
  $cfmWrite $of [:serialize to=json $ord]
  $cfmManifests
  :foreach name,pl in=$plan do={
    :local w "sofort"
    :if ([:len $when] > 0) do={ :set w ("am " . $when) }
    :put ("Auftrag " . $name . ": " . ($pl->"how") . " auf " . $ver . " (" . $w . ")")
    $cfmPush host=$name
  }
  :log info ("cfm: RouterOS-Auftrag " . $ver . " für " . [:len $plan] . " Geräte")
  :return ""
}

# Erledigte Aufträge (Gerät meldet die Zielversion) austragen, danach Pakete aufräumen
:global cfmUpgTick do={
  :global cfmMB; :global cfmJson; :global cfmWrite; :global cfmManifests; :global cfmPkgPrune
  :local b [$cfmMB]
  :local of ($b . "/meta/upgrade.dat")
  :local ord [$cfmJson $of]
  :if ([:len $ord] = 0) do={ :return 0 }
  :local no ({})
  :local done 0
  :foreach name,o in=$ord do={
    :local r [:tostr ([$cfmJson ($b . "/state/" . $name . "/status.dat")]->"ros")]
    :local tv [:pick [:tostr ($o->"rv")] 1 99]
    :if ([:pick $r 0 [:find ($r . " ") " "]] = $tv) do={
      :set done ($done + 1)
      :log info ("cfm: RouterOS " . $name . " -> " . $tv . " erledigt")
    } else={ :set ($no->$name) $o }
  }
  :if ($done > 0) do={
    $cfmWrite $of [:serialize to=json $no]
    $cfmManifests
    $cfmPkgPrune
  }
  :return $done
}
