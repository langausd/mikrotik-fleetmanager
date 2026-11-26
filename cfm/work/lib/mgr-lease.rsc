# ============================================================
# cfm lib/mgr-lease.rsc – Manager: feste Leases von außen eintragen (TODO 102, DN1.3)
#   $cfmLease add name=<n> vlan=<vid> [mac=<MAC>] [ip=<Host-Teil>] [wifi=yes] [allow=<liste>,..] [acme=yes] [release=no]
#     trägt die Lease in work/leases.rsc ein, prüft ($cfmCheck) und gibt ein Release heraus (nur wenn work/ sonst dem
#     letzten Release entspricht). Ohne mac: zufällige lokal verwaltete MAC (02:…); ohne ip: erste freie Adresse über
#     dem DHCP-Pool, sonst darunter (ohne Gateway, dhcpGw, .251-.254 und vergebene Leases). Name, MAC oder IP schon
#     vergeben -> Abbruch; dieselbe Lease (Name, VLAN und MAC gleich) noch einmal -> "vorhanden", nichts geändert.
#     acme=yes: gibt den CNAME für acme-dns aus (Ziel aus global.rsc lease.acme), ändert dort nichts.
#   $cfmLease del name=<n> [release=no]     Lease entfernen (gleiche Regeln für das Release)
#   $cfmLease list [vlan=<vid>]             Leases aus work/leases.rsc
#   $cfmLeaseRun "<befehl> k=v …"           für das Skript cfm-lease (global.rsc lease): Argumente als Text aus
#                                           $cfmLeaseArg (SSH oder REST /execute), nichts davon wird ausgeführt
#   $cfmCheckLease                          Prüfung von global.rsc lease (aus $cfmCheck)
# Ausgabe für Werkzeuge: je eine Zeile "LEASE <ok|vorhanden|entfernt> vlan=… name=… mac=… ip=…",
# "RELEASE v<N>" bzw. "RELEASE nein (<Grund>)", "CNAME …" und am Ende "ERGEBNIS ok" oder "ERGEBNIS fehler: …".
# leases.rsc wird als Text bearbeitet (Kommentare und Reihenfolge bleiben): Eintrag im Block des VLANs als neue
# letzte Zeile, ohne passenden Block als Zeile ":set ($cfmLeases->…)" am Ende. Das Ergebnis wird vor dem Schreiben
# geladen und geprüft.
# ============================================================

# Text der Lease ohne Namen: {"mac"=…;"ip"=…[;"wifi"="yes"][;"allow"={…}]}
:global cfmLeaseTxt do={
  :local t ("{\"mac\"=\"" . $mac . "\";\"ip\"=" . $ip)
  :if ($wifi = "yes") do={ :set t ($t . ";\"wifi\"=\"yes\"") }
  :if ([:len $allow] > 0) do={
    :local l ""
    :foreach a in=$allow do={ :if ([:len $l] > 0) do={ :set l ($l . ";") }; :set l ($l . "\"" . $a . "\"") }
    :set t ($t . ";\"allow\"={" . $l . "}")
  }
  :return ($t . "}")
}

# leases.rsc laden, ohne den laufenden Stand zu verlieren -> Array der Leases oder Fehlertext (str)
:global cfmLeaseEval do={
  :global cfmLeases
  :local keep $cfmLeases
  :local r ""
  :onerror e in={ :set cfmLeases ({}); [[:parse $1]]; :set r $cfmLeases } do={ :set r ("nicht ladbar: " . $e) }
  :set cfmLeases $keep
  :return $r
}

# Eintrag in den Text einfügen: $1 Text, vid, name, lt (Lease-Text) -> neuer Text
:global cfmLeaseIns do={
  :local c [:tostr $1]
  :local ent ("\"" . $name . "\"=" . $lt)
  # am Zeilenanfang: der Kopfkommentar zeigt dieselbe Zeile als Beispiel
  # ("\n" . Text): Fundstelle = Index der Zeile im Text, auch ganz am Anfang
  :local g [:find ("\n" . $c) "\n:global cfmLeases" -1]
  :if ([:typeof $g] != "num") do={ :return ($c . "\n:global cfmLeases ({})\n:set (\$cfmLeases->\"" . $vid . "\") {" . $ent . "}\n") }
  # leere Form: zum Block machen
  :local em ":global cfmLeases ({})"
  :if ([:pick $c $g ($g + [:len $em])] = $em) do={
    :local rest [:pick $c ($g + [:len $em]) [:len $c]]
    :if (!([:tostr $rest] ~ "cfmLeases->")) do={
      :return ([:pick $c 0 $g] . ":global cfmLeases {\n  \"" . $vid . "\"={\n    " . $ent . "\n  }\n}" . $rest)
    }
  }
  # Block des VLANs ("\n  \"<vid>\"={\n" … "\n  }")
  :local hd ("\n  \"" . $vid . "\"={\n")
  :local s [:find $c $hd ($g - 1)]
  :if ([:typeof $s] = "num") do={
    :local e [:find $c "\n  }" ($s + [:len $hd] - 2)]
    :if ([:typeof $e] = "num") do={
      :local seg [:pick $c ($s + [:len $hd]) $e]
      :local sep ""
      :if ([:len $seg] > 0 and [:typeof [:find $seg "="]] = "num") do={ :set sep ";" }
      # vor "\n  }" einfügen; die bisher letzte Zeile bekommt das Semikolon
      :if ([:len $seg] = 0) do={ :return ([:pick $c 0 ($s + [:len $hd])] . "    " . $ent . [:pick $c $e [:len $c]]) }
      :return ([:pick $c 0 $e] . $sep . "\n    " . $ent . [:pick $c $e [:len $c]])
    }
  }
  # kein passender Block: Zeile anhängen (wie bisher von Hand oder im Labor)
  :local nl ""
  :if ([:pick $c ([:len $c] - 1) [:len $c]] != "\n") do={ :set nl "\n" }
  :return ($c . $nl . ":if ([:typeof (\$cfmLeases->\"" . $vid . "\")] != \"array\") do={ :set (\$cfmLeases->\"" . $vid . "\") ({}) }\n:set (\$cfmLeases->\"" . $vid . "\"->\"" . $name . "\") " . $lt . "\n")
}

# Eintrag entfernen: $1 Text, vid, name -> neuer Text oder "" (nicht zeilenweise gefunden)
:global cfmLeaseCut do={
  :local c [:tostr $1]
  :local k ("\"" . $name . "\"={\"")
  # erst nach der Zeile :global cfmLeases suchen (der Kopfkommentar enthält ein Beispiel)
  :local g [:find ("\n" . $c) "\n:global cfmLeases" -1]
  :if ([:typeof $g] != "num") do={ :return "" }
  # Zeilenform von $cfmLeaseIns (ohne Block des VLANs): :set ($cfmLeases->"<vid>"->"<name>") {...}
  :local sl (":set (\$cfmLeases->\"" . $vid . "\"->\"" . $name . "\") ")
  :local q [:find ("\n" . $c) ("\n" . $sl) ($g - 1)]
  :if ([:typeof $q] = "num") do={
    :local qe [:find $c "\n" $q]
    :if ([:typeof $qe] != "num") do={ :set qe ([:len $c] - 1) }
    # die :if-Zeile davor gehört dazu, wenn sie genau so von $cfmLeaseIns stammt
    :local il (":if ([:typeof (\$cfmLeases->\"" . $vid . "\")] != \"array\") do={ :set (\$cfmLeases->\"" . $vid . "\") ({}) }\n")
    :local qs $q
    :if ($q >= [:len $il] and [:pick $c ($q - [:len $il]) $q] = $il) do={ :set qs ($q - [:len $il]) }
    :return ([:pick $c 0 $qs] . [:pick $c ($qe + 1) [:len $c]])
  }
  :local p [:find $c $k $g]
  :if ([:typeof $p] != "num") do={ :return "" }
  # nur eine Zeile im Block: davor nur Leerzeichen bis zum Zeilenanfang
  :local ls $p
  :while ($ls > 0 and [:pick $c ($ls - 1) $ls] = " ") do={ :set ls ($ls - 1) }
  :if ($ls = 0 or [:pick $c ($ls - 1) $ls] != "\n") do={ :return "" }
  :local le [:find $c "\n" $p]
  :if ([:typeof $le] != "num") do={ :return "" }
  :local line [:pick $c $ls $le]
  :if ([:pick $line ([:len $line] - 1) [:len $line]] = ";") do={
    :return ([:pick $c 0 ($ls - 1)] . [:pick $c $le [:len $c]])
  }
  # letzte Zeile im Block: das Semikolon der Zeile davor entfällt
  :local a [:pick $c 0 ($ls - 1)]
  :if ([:pick $a ([:len $a] - 1) [:len $a]] = ";") do={ :set a [:pick $a 0 ([:len $a] - 1)] }
  :return ($a . [:pick $c $le [:len $c]])
}

# Unterscheidet sich work/ (außer leases.rsc) vom letzten Release? -> "" oder Liste der Dateien
:global cfmLeaseWorkDiff do={
  :global cfmMB; :global cfmRings; :global cfmJson
  :local b [$cfmMB]
  :local v ([$cfmRings]->"latest")
  :if ([:tonum $v] = 0) do={ :return "noch kein Release" }
  :local ix ([$cfmJson ($b . "/archive/v" . $v . "/index.dat")]->"files")
  :if ([:typeof $ix] != "array") do={ :return ("archive/v" . $v . "/index.dat fehlt") }
  :local d ""; :local seen ({})
  :foreach f in=[/file/find where name~("^" . $b . "/work/") and type!="directory"] do={
    :local n [/file/get $f name]
    :local rel [:pick $n ([:len $b] + 6) [:len $n]]
    :set ($seen->$rel) 1
    :if ($rel != "leases.rsc") do={
      :if ([:typeof ($ix->$rel)] = "nothing") do={ :set d ($d . " " . $rel) } else={
        :if ([:convert [/file/get $f contents] transform=sha512 to=hex] != ($ix->$rel)) do={ :set d ($d . " " . $rel) }
      }
    }
  }
  :foreach rel,h in=$ix do={ :if ($rel != "leases.rsc" and [:typeof ($seen->$rel)] = "nothing") do={ :set d ($d . " -" . $rel) } }
  :return $d
}

# Release nach einer Änderung an leases.rsc; Rückgabe "v<N>" oder "nein (<Grund>)"
:global cfmLeaseRelease do={
  :global cfmLeaseWorkDiff; :global cfmRelease; :global cfmRings
  :if ($1 = "no") do={ :return "nein (release=no)" }
  :local d [$cfmLeaseWorkDiff]
  :if ([:len $d] > 0) do={ :return ("nein (work/ hat weitere Änderungen:" . $d . " - Release macht der Admin)") }
  # Ringe auf demselben Stand: an alle (die Lease ist die einzige Änderung), sonst nur Ring 0
  :local rg [$cfmRings]
  :local all "no"
  :if ([:tostr ($rg->"r0")] = [:tostr ($rg->"latest")] and [:tostr ($rg->"r1")] = [:tostr ($rg->"latest")] and [:tostr ($rg->"r2")] = [:tostr ($rg->"latest")]) do={ :set all "yes" }
  :local v ""
  :onerror e in={ :set v [$cfmRelease msg=$2 all=$all] } do={ :return ("nein (" . $e . ")") }
  :if ($all = "yes") do={ :return ("v" . $v) }
  :return ("v" . $v . " (nur Ring 0 - Ringe 1/2 stehen auf älteren Versionen, Router dort erst nach \$cfmPromote)")
}

:global cfmLease do={
  :global cfmMB; :global cfmIsPrimary; :global cfmLoadData; :global cfmVlans; :global cfmG; :global cfmNet
  :global cfmMacUp; :global cfmInvLoad; :global cfmRead; :global cfmWrite; :global cfmCheck; :global cfmLower
  :global cfmLeaseTxt; :global cfmLeaseEval; :global cfmLeaseIns; :global cfmLeaseCut; :global cfmLeaseRelease
  :local fail do={ :put ("ERGEBNIS fehler: " . $1); :return false }
  :local cmd [:tostr $1]
  :if ($cmd != "add" and $cmd != "del" and $cmd != "list") do={ :return [$fail "Befehl add, del oder list"] }
  :if (![$cfmIsPrimary]) do={ :return [$fail "nicht Primary: Leases nur am Primary-Manager"] }
  :local b [$cfmMB]
  :local fn ($b . "/work/leases.rsc")
  :local c [$cfmRead $fn]
  :if ([:len $c] = 0) do={ :return [$fail "work/leases.rsc fehlt"] }
  :local cur [$cfmLeaseEval $c]
  :if ([:typeof $cur] != "array") do={ :return [$fail ("work/leases.rsc " . $cur)] }
  :onerror e in={ $cfmLoadData ver=0 } do={ :return [$fail ("Daten in work/ nicht ladbar: " . $e)] }
  :local nm [:tostr $name]

  :if ($cmd = "list") do={
    :foreach vid,ls in=$cur do={
      :if ([:len [:tostr $vlan]] = 0 or [:tostr $vlan] = $vid) do={
        :local nn [$cfmNet $vid]
        :foreach n,d in=$ls do={ :put ("LEASE vlan=" . $vid . " name=" . $n . " mac=" . ($d->"mac") . " ip=" . (($nn->"addr") + [:tonum ($d->"ip")])) }
      }
    }
    :put "ERGEBNIS ok"
    :return true
  }

  :if (!($nm ~ "^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\$") or [:len $nm] > 63) do={ :return [$fail ("name: Buchstaben, Ziffern und \"-\" (DNS-Label, bis 63 Zeichen)")] }
  # wo steht der Name schon?
  :local hasV ""
  :foreach vid,ls in=$cur do={ :if ([:typeof ($ls->$nm)] = "array") do={ :set hasV $vid } }

  :if ($cmd = "del") do={
    :if ([:len $hasV] = 0) do={ :return [$fail ("Lease " . $nm . " gibt es nicht")] }
    :local nc [$cfmLeaseCut $c vid=$hasV name=$nm]
    :if ([:len $nc] = 0) do={ :return [$fail ("Lease " . $nm . " steht nicht als eigene Zeile in leases.rsc - bitte im Editor löschen")] }
    :local chk [$cfmLeaseEval $nc]
    :if ([:typeof $chk] != "array" or [:typeof ($chk->$hasV->$nm)] != "nothing") do={ :return [$fail "Entfernen ergäbe kein gültiges leases.rsc - nichts geändert"] }
    $cfmWrite $fn $nc
    :put ("LEASE entfernt vlan=" . $hasV . " name=" . $nm)
    :put ("RELEASE " . [$cfmLeaseRelease [:tostr $release] ("lease: " . $nm . " entfernt")])
    :put "ERGEBNIS ok"
    :return true
  }

  # --- add ---
  :local vid [:tostr $vlan]
  :local v ($cfmVlans->$vid)
  :if ([:typeof $v] != "array") do={ :return [$fail ("vlan " . $vid . " fehlt in vlans.rsc")] }
  :local dh [:tostr ($v->"dhcp")]
  :if ([:len $dh] = 0 or $dh = "no" or [:tostr ($v->"onboard")] = "yes") do={ :return [$fail ("VLAN " . $vid . " ohne DHCP der Router - die Lease wirkte nicht")] }
  # $cfmMacUp mit leerem Text liefe rückwärts (:for … to=-1)
  :local mc ""
  :if ([:len [:tostr $mac]] > 0) do={ :set mc [$cfmMacUp [:tostr $mac]] }
  :if ([:len $mc] > 0 and !($mc ~ "^([0-9A-F][0-9A-F]:){5}[0-9A-F][0-9A-F]\$")) do={ :return [$fail "mac ungültig (AA:BB:CC:DD:EE:FF)"] }
  :local nn [$cfmNet $vid]
  # schon da?
  :if ([:len $hasV] > 0) do={
    :local o ($cur->$hasV->$nm)
    :if ($hasV = $vid and ([:len $mc] = 0 or [$cfmMacUp ($o->"mac")] = $mc) and ([:len [:tostr $ip]] = 0 or [:tonum $ip] = [:tonum ($o->"ip")])) do={
      :put ("LEASE vorhanden vlan=" . $vid . " name=" . $nm . " mac=" . ($o->"mac") . " ip=" . (($nn->"addr") + [:tonum ($o->"ip")]))
      :put "RELEASE nein (unverändert)"
      :put "ERGEBNIS ok"
      :return true
    }
    :return [$fail ("Name " . $nm . " schon vergeben (VLAN " . $hasV . ", MAC " . ($o->"mac") . ")")]
  }
  :foreach hn,hd in=[$cfmInvLoad] do={ :if ([$cfmLower $hn] = [$cfmLower $nm]) do={ :return [$fail ("Name " . $nm . " ist ein Gerät (gleicher DNS-Name)")] } }
  # MAC und Adressen der Leases
  :local usedM ({}); :local usedIp ({})
  :foreach lv,ls in=$cur do={
    :foreach n,d in=$ls do={
      :set ($usedM->[$cfmMacUp ($d->"mac")]) ($n . " (VLAN " . $lv . ")")
      :if ($lv = $vid) do={ :set ($usedIp->[:tostr [:tonum ($d->"ip")]]) $n }
    }
  }
  :if ([:len $mc] > 0 and [:typeof ($usedM->$mc)] != "nothing") do={ :return [$fail ("MAC " . $mc . " schon bei " . ($usedM->$mc))] }
  :if ([:len $mc] = 0) do={
    :local tries 0
    :while ([:len $mc] = 0 and $tries < 20) do={
      :local r [:rndstr length=10 from="0123456789ABCDEF"]
      :local m ("02:" . [:pick $r 0 2] . ":" . [:pick $r 2 4] . ":" . [:pick $r 4 6] . ":" . [:pick $r 6 8] . ":" . [:pick $r 8 10])
      :if ([:typeof ($usedM->$m)] = "nothing") do={ :set mc $m }
      :set tries ($tries + 1)
    }
  }
  # Netzgröße, Gateway, Pool
  :local hmax 254
  :if ([:len [:tostr ($nn->"pfx")]] > 0) do={
    :set hmax 1
    :for i from=1 to=(32 - [:tonum ($nn->"pfx")]) do={ :set hmax ($hmax * 2) }
    :set hmax ($hmax - 2)
  }
  :local gwh [:tonum ($v->"gw")]
  :if ([:typeof $gwh] != "num") do={ :set gwh 1 }
  :local dgw [:tonum ($v->"dhcpGw")]
  :local pool ({}); :local plo 0; :local phi 0
  :foreach rg in=[:toarray $dh] do={
    :local m [:find $rg "-"]
    :if ([:typeof $m] = "num") do={
      :local lo [:tonum [:pick $rg 0 $m]]; :local hi [:tonum [:pick $rg ($m + 1) [:len $rg]]]
      :if ([:typeof $lo] = "num" and [:typeof $hi] = "num") do={
        :set ($pool->[:len $pool]) ({$lo;$hi})
        :if ($plo = 0 or $lo < $plo) do={ :set plo $lo }
        :if ($hi > $phi) do={ :set phi $hi }
      }
    }
  }
  :local inPool do={ :local r false; :foreach p in=$2 do={ :if ($1 >= ($p->0) and $1 <= ($p->1)) do={ :set r true } }; :return $r }
  :local h 0
  :if ([:len [:tostr $ip]] > 0) do={
    :set h [:tonum $ip]
    :if ([:typeof $h] != "num" or $h < 1 or $h > $hmax) do={ :return [$fail ("ip = Host-Anteil 1-" . $hmax)] }
    :if ($h = $gwh or $h = $dgw) do={ :return [$fail "ip ist die Adresse des Gateways"] }
    :if ([:typeof ($usedIp->[:tostr $h])] != "nothing") do={ :return [$fail ("ip ." . $h . " schon bei " . ($usedIp->[:tostr $h]))] }
    :if ([$inPool $h $pool]) do={ :put ("Hinweis: ." . $h . " liegt im DHCP-Pool " . $dh) }
  } else={
    :local top $hmax
    :if ($top > 250) do={ :set top 250 }
    :for i from=($phi + 1) to=$top do={
      :if ($h = 0 and $i != $gwh and $i != $dgw and [:typeof ($usedIp->[:tostr $i])] = "nothing" and ![$inPool $i $pool]) do={ :set h $i }
    }
    :if ($h = 0 and $plo > 2) do={
      :for i from=($plo - 1) to=2 step=-1 do={
        :if ($h = 0 and $i != $gwh and $i != $dgw and [:typeof ($usedIp->[:tostr $i])] = "nothing" and ![$inPool $i $pool]) do={ :set h $i }
      }
    }
    :if ($h = 0) do={ :return [$fail ("keine freie Adresse außerhalb des Pools in VLAN " . $vid)] }
  }
  # Freigaben (Listen aus global.rsc allow, Prüfung macht $cfmCheck)
  :local al ({})
  :foreach a in=[:toarray [:tostr $allow]] do={
    :if (!([:tostr $a] ~ "^[*A-Za-z0-9._@-]+\$")) do={ :return [$fail ("allow " . $a . ": nur Buchstaben, Ziffern, * . _ @ -")] }
    :set ($al->[:len $al]) [:tostr $a]
  }
  :local wf ""
  :if ([:tostr $wifi] = "yes") do={ :set wf "yes" }
  :local lt [$cfmLeaseTxt mac=$mc ip=$h wifi=$wf allow=$al]
  :local nc [$cfmLeaseIns $c vid=$vid name=$nm lt=$lt]
  :local chk [$cfmLeaseEval $nc]
  :if ([:typeof $chk] != "array") do={ :return [$fail ("Einfügen ergäbe kein gültiges leases.rsc (" . $chk . ") - nichts geändert")] }
  :if ([$cfmMacUp ($chk->$vid->$nm->"mac")] != $mc or [:tonum ($chk->$vid->$nm->"ip")] != $h) do={ :return [$fail "Einfügen nicht wie erwartet - nichts geändert"] }
  $cfmWrite $fn $nc
  # inhaltliche Prüfung: Fehler zur neuen Lease -> zurück; andere Fehler -> Lease bleibt, kein Release
  :local ck [$cfmCheck quiet=yes]
  :local mine ""; :local other 0
  :foreach x in=($ck->"err") do={
    :if ([:typeof [:find $x ("leases.rsc: VLAN " . $vid . " " . $nm . ":")]] = "num" or [:typeof [:find $x ("Name " . $nm . " ")]] = "num") do={ :set mine ($mine . " " . $x) } else={ :set other ($other + 1) }
  }
  :if ([:len $mine] > 0) do={
    $cfmWrite $fn $c
    :return [$fail ("Prüfung:" . $mine . " - nichts geändert")]
  }
  :put ("LEASE ok vlan=" . $vid . " name=" . $nm . " mac=" . $mc . " ip=" . (($nn->"addr") + $h))
  :foreach x in=($ck->"warn") do={ :if ([:typeof [:find $x (" " . $nm . ":")]] = "num") do={ :put ("Warnung: " . $x) } }
  :if ($other > 0) do={
    :put ("RELEASE nein (" . $other . " andere Prüffehler in work/ - \$cfmCheck)")
  } else={
    :put ("RELEASE " . [$cfmLeaseRelease [:tostr $release] ("lease: " . $nm . " (VLAN " . $vid . ")")])
  }
  :if ([:tostr $acme] = "yes") do={
    :local dom [:tostr ($cfmG->"domain")]
    :local tg [:tostr ($cfmG->"lease"->"acme")]
    :local fq ([$cfmLower $nm] . "." . $dom)
    :if ([:len $tg] > 0) do={
      :put ("CNAME _acme-challenge." . $fq . ". CNAME " . $tg . ".")
    } else={
      :put ("CNAME _acme-challenge." . $fq . ". CNAME <acme-dns-Subdomain> (global.rsc lease.acme fehlt)")
    }
  }
  :put "ERGEBNIS ok"
  :return true
}

# Argumente als Text ("add name=x vlan=177 …") -> $cfmLease. Nur bekannte Schlüssel, Werte ohne Leerzeichen;
# nichts davon wird geparst oder ausgeführt
:global cfmLeaseRun do={
  :global cfmLease
  :local s [:tostr $1]
  :local w ({}); :local cur ""
  :for i from=0 to=([:len $s] - 1) do={
    :local ch [:pick $s $i]
    :if ($ch = " " or $ch = "\t" or $ch = "\n" or $ch = "\r") do={ :if ([:len $cur] > 0) do={ :set ($w->[:len $w]) $cur; :set cur "" } } else={ :set cur ($cur . $ch) }
  }
  :if ([:len $cur] > 0) do={ :set ($w->[:len $w]) $cur }
  :if ([:len $w] = 0) do={ :put "ERGEBNIS fehler: kein Befehl (add|del|list)"; :return false }
  :local a ({})
  :local keys ",name,vlan,mac,ip,wifi,allow,acme,release,"
  :for i from=1 to=([:len $w] - 1) do={
    :local t ($w->$i)
    :local p [:find $t "="]
    :if ([:typeof $p] != "num") do={ :put ("ERGEBNIS fehler: " . $t . " (erwartet k=v)"); :return false }
    :local k [:pick $t 0 $p]; :local v [:pick $t ($p + 1) [:len $t]]
    :if (!($keys ~ ("," . $k . ","))) do={ :put ("ERGEBNIS fehler: unbekannter Schlüssel " . $k); :return false }
    :if (!($v ~ "^[A-Za-z0-9:._@*,-]*\$")) do={ :put ("ERGEBNIS fehler: " . $k . ": unzulässige Zeichen"); :return false }
    :set ($a->$k) $v
  }
  :return [$cfmLease ($w->0) name=($a->"name") vlan=($a->"vlan") mac=($a->"mac") ip=($a->"ip") wifi=($a->"wifi") allow=($a->"allow") acme=($a->"acme") release=($a->"release")]
}

# Prüfung von global.rsc lease (aus $cfmCheck) -> {"err"=…;"warn"=…}
:global cfmCheckLease do={
  :global cfmG
  :local err ({}); :local warn ({})
  :local lc ($cfmG->"lease")
  :if ([:typeof $lc] = "array" and [:len $lc] > 0) do={
    :foreach k,x in=$lc do={ :if ($k != "from" and $k != "rest" and $k != "acme") do={ :set ($warn->[:len $warn]) ("global.rsc: lease " . $k . " unbekannt (from, rest, acme)") } }
    :if ([:len ($lc->"from")] = 0) do={ :set ($warn->[:len $warn]) "global.rsc: lease ohne from - niemand kann Leases eintragen (kein User cfm-lease)" }
    :foreach a in=($lc->"from") do={
      :local s [:tostr $a]; :local p [:find $s "/"]
      :if ([:typeof $p] = "num") do={ :set s [:pick $s 0 $p] }
      :if ([:typeof [:toip $s]] != "ip") do={ :set ($err->[:len $err]) ("global.rsc: lease from: " . $a . " ist keine IPv4-Adresse/kein Netz") }
    }
    :local r [:tostr ($lc->"rest")]
    :if ([:len $r] > 0 and $r != "yes" and $r != "no") do={ :set ($err->[:len $err]) "global.rsc: lease rest nur \"yes\" oder \"no\"" }
    :if ($r = "yes" and [:len [:tostr ($cfmG->"services"->"www-ssl")]] = 0) do={ :set ($warn->[:len $warn]) "global.rsc: lease rest=yes ohne www-ssl in services - REST geht nur über https" }
    :local ok false
    :onerror e in={ :set ok ([:len [/file/get ($w . "/authorized_keys.cfm-lease") name]] > 0) } do={}
    :if (!$ok and $r != "yes") do={ :set ($warn->[:len $warn]) "lease: authorized_keys.cfm-lease fehlt in work/ - Anmeldung per SSH nicht möglich" }
    :local tg [:tostr ($lc->"acme")]
    :if ([:len $tg] > 0 and !($tg ~ "^[A-Za-z0-9_.-]+\$")) do={ :set ($err->[:len $err]) "global.rsc: lease acme = CNAME-Ziel (acme-dns-Subdomain, z.B. 0123….auth.example.net)" }
  }
  :return ({"err"=$err;"warn"=$warn})
}
