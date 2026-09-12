# ============================================================
# cfm lib/mgr-ros.rsc – Manager-Funktionen: RouterOS-Pakete und -Updates (D30)
#   $cfmUpgrade ver=<x.y.z> host=<n>|ring=<r>|all=yes [at="YYYY-MM-DD HH:MM"]
#   $cfmUpgrade cancel=yes host=..|ring=..|all=yes        $cfmUpgrade   (offene Aufträge)
#   $cfmPkgPrune      nicht mehr genutzte Paketversionen löschen (läuft automatisch)
#   (Übersicht aller Befehle: lib/mgr-core.rsc)
#
# Ablauf: Vor dem Rollout lädt der Manager alle Pakete (routeros + Zusatzpakete) für alle
# betroffenen Architekturen von download.mikrotik.com nach <pkgPath>/<ver>/. Erst wenn alle da
# sind, landet der Auftrag im signierten Manifest der Geräte (Feld "ros"). Der Agent holt die
# Pakete per SFTP vom Manager, prüft die Größe und startet sofort oder zum Zeitpunkt at neu
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

# Paket <pkg>-<ver>[-<arch>].npk bereitstellen (laden, falls es fehlt) -> {Dateiname;Größe}
:global cfmPkgFetch do={
  :global cfmPkgDir
  :local sfx ("-" . $arch)
  :if ($arch ~ "^x86") do={ :set sfx "" }
  :local fn ($pkg . "-" . $ver . $sfx . ".npk")
  :local lp ([$cfmPkgDir] . "/" . $ver . "/" . $fn)
  :if ([:len [/file/find where name=$lp]] = 0) do={
    :local url ("https://download.mikrotik.com/routeros/" . $ver . "/" . $fn)
    :put ("lade " . $url)
    :local fe ""
    :onerror e in={ /tool/fetch url=$url dst-path=$lp as-value } do={ :set fe $e }
    :if ([:len $fe] > 0) do={
      :onerror e in={ /file/remove [find where name=$lp] } do={}
      :error ("Download fehlgeschlagen: " . $fn . " (" . $fe . ")")
    }
    :delay 1s
  }
  :local sz [/file/get [find where name=$lp] size]
  :if ($sz < 100000) do={
    /file/remove [find where name=$lp]
    :error ("Paket unvollständig oder ungültig: " . $fn)
  }
  :return ({$fn;$sz})
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
  :if (![$cfmIsPrimary]) do={ :error "nicht Primary: Backup-Manager ist read-only (\$cfmPromoteManager)" }
  :if ([:len $host] = 0 and [:len [:tostr $ring]] = 0 and $all != "yes") do={ :error "Aufruf: \$cfmUpgrade ver=<x.y.z> host=<n>|ring=<r>|all=yes [at=\"YYYY-MM-DD HH:MM\"]" }
  :local tg ({})
  :foreach name,d in=$inv do={
    :if ($all = "yes" or $host = $name or ([:len [:tostr $ring]] > 0 and [:tostr $ring] = [:tostr ($d->"ring")])) do={ :set ($tg->$name) $d }
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
        :set ($plan->$name) ({"arch"=$arch;"pkgs"=$pk;"how"=$how})
        :foreach p in=$pk do={ :set ($need->($arch . "|" . $p)) 1 }
      }
    }
  }
  :if ([:len $err] > 0) do={ :error ("Update abgebrochen:" . $err) }
  :if ([:len $plan] = 0) do={ :put "nichts zu tun"; :return "" }

  # --- alle Pakete vor dem Rollout bereitstellen (bricht bei einem Fehler ab) ---
  :local got ({})
  :foreach k,x in=$need do={
    :local p [:find $k "|"]
    :set ($got->$k) [$cfmPkgFetch ver=$ver arch=[:pick $k 0 $p] pkg=[:pick $k ($p + 1) [:len $k]]]
  }

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
