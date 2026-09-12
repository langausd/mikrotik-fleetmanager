# ============================================================
# cfm lib/mgr-check.rsc – Manager-Funktionen: inhaltliche Prüfung und Probelauf
#   $cfmCheck            prüft die Daten in work/ (läuft auch bei jedem $cfmRelease, D27)
#   $cfmPlan host=<n>    Probelauf: das Gerät zeigt, was ein Release von work/ ändern würde
#   (Übersicht aller Befehle: lib/mgr-core.rsc)
# ============================================================

# ---------- Inhaltliche Prüfung von work/ -> {"err"={..};"warn"={..}} ----------
# Fehler: VLANs/Zonen, die Profile, WLAN, policy, mgmtAccess oder Hostfiles nennen, aber nicht
# existieren; unbekannte Port-Profile; doppelte MGMT-IPs; Rollen ohne Datei.
# Warnungen: Inventar-Eintrag ohne Hostfile.
:global cfmCheck do={
  :global cfmMB; :global cfmLoadData; :global cfmG; :global cfmVlans; :global cfmProfiles
  :global cfmWifi; :global cfmInvLoad; :global cfmHost
  :local b [$cfmMB]
  :local w ($b . "/work")
  :local err ({}); :local warn ({})
  :local le ""
  :onerror e in={ $cfmLoadData ver=0 } do={ :set le $e }
  :if ([:len $le] > 0) do={ :set ($err->0) ("Daten in work/ nicht ladbar: " . $le); :return ({"err"=$err;"warn"=$warn}) }
  :local zones ({})
  :foreach vid,v in=$cfmVlans do={ :set ($zones->[:tostr ($v->"zone")]) 1 }
  # VLAN-Spezifikation ("*", Zonen, VIDs, "!x") -> unbekannte Einträge
  :local badSpec do={
    :global cfmVlans
    :local r ""
    :foreach t in=[:toarray $1] do={
      :local x [:tostr $t]
      :if ([:pick $x 0 1] = "!") do={ :set x [:pick $x 1 [:len $x]] }
      :if ($x != "*" and [:typeof ($cfmVlans->$x)] != "array" and [:typeof ($z->$x)] = "nothing") do={ :set r ($r . " " . $x) }
    }
    :return $r
  }

  # Port-Profile
  :foreach pn,pr in=$cfmProfiles do={
    :local u [:tostr ($pr->"untag")]
    :if ([:len $u] > 0 and $u != "arg" and [:typeof ($cfmVlans->$u)] != "array") do={ :set ($err->[:len $err]) ("profiles.rsc: " . $pn . ": untag " . $u . " ist kein VLAN") }
    :local bs [$badSpec ($pr->"tag") z=$zones]
    :if ([:len $bs] > 0) do={ :set ($err->[:len $err]) ("profiles.rsc: " . $pn . ": unbekannte VLANs/Zonen:" . $bs) }
  }
  # WLAN
  :foreach k,s in=($cfmWifi->"ssids") do={
    :local vv [:tostr ($s->"vlan")]
    :if ([:len $vv] > 0 and [:typeof ($cfmVlans->$vv)] != "array") do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": VLAN " . $vv . " fehlt in vlans.rsc") }
  }
  # Zonen-Matrix, Management-Zugang, MGMT-VLAN
  :foreach z,to in=($cfmG->"policy") do={
    :if ([:typeof ($zones->$z)] = "nothing") do={ :set ($err->[:len $err]) ("global.rsc: policy nennt Zone " . $z . ", kein VLAN hat diese Zone") }
    :foreach t in=[:toarray $to] do={
      :if ($t != "*" and $t != "wan" and $t != "mtupdate" and [:typeof ($zones->$t)] = "nothing") do={ :set ($err->[:len $err]) ("global.rsc: policy " . $z . " -> unbekannte Zone " . $t) }
    }
  }
  :foreach z in=[:toarray ($cfmG->"mgmtAccess")] do={
    :if ([:typeof ($zones->$z)] = "nothing") do={ :set ($err->[:len $err]) ("global.rsc: mgmtAccess nennt unbekannte Zone " . $z) }
  }
  :if ([:typeof ($cfmVlans->[:tostr ($cfmG->"mgmtVlan")])] != "array") do={ :set ($err->[:len $err]) ("global.rsc: mgmtVlan " . ($cfmG->"mgmtVlan") . " fehlt in vlans.rsc") }

  # Inventar + Hostfiles
  :local ips ({})
  :foreach n,d in=[$cfmInvLoad] do={
    :local ip [:tostr ($d->"ip")]
    :if ([:len $ip] > 0) do={
      :if ([:typeof ($ips->$ip)] != "nothing") do={ :set ($err->[:len $err]) ("inventory: MGMT-IP " . $ip . " doppelt (" . ($ips->$ip) . ", " . $n . ")") }
      :set ($ips->$ip) $n
    }
    :foreach r in=[:toarray ($d->"role")] do={
      :if ([:len [/file/find where name=($w . "/roles/" . $r . ".rsc")]] = 0) do={ :set ($err->[:len $err]) ("inventory: " . $n . ": Rolle " . $r . " ohne roles/" . $r . ".rsc") }
    }
    :local hf ($w . "/hosts/" . $n . ".rsc")
    :if ([:len [/file/find where name=$hf]] = 0) do={ :set ($warn->[:len $warn]) ("inventory: " . $n . " hat kein hosts/" . $n . ".rsc") } else={
      :set cfmHost ({})
      :local he ""
      :onerror e in={ /import file-name=$hf verbose=no } do={ :set he $e }
      :if ([:len $he] > 0) do={ :set ($err->[:len $err]) ("hosts/" . $n . ".rsc: " . $he) } else={
        :local specs ({})
        :foreach p,sp in=($cfmHost->"ports") do={ :set ($specs->[:len $specs]) ({$p;$sp}) }
        :if ([:len [:tostr ($cfmHost->"portDefault")]] > 0) do={ :set ($specs->[:len $specs]) ({"portDefault";($cfmHost->"portDefault")}) }
        :foreach ps in=$specs do={
          :local sp [:tostr ($ps->1)]
          :local pn $sp; :local arg ""
          :local c [:find $sp ":"]
          :if ([:typeof $c] != "nil") do={ :set pn [:pick $sp 0 $c]; :set arg [:pick $sp ($c + 1) [:len $sp]] }
          :local pr ($cfmProfiles->$pn)
          :if ([:typeof $pr] != "array") do={ :set ($err->[:len $err]) ("hosts/" . $n . ".rsc: " . ($ps->0) . ": unbekanntes Port-Profil " . $sp) } else={
            :if ([:tostr ($pr->"untag")] = "arg" and [:typeof ($cfmVlans->$arg)] != "array") do={ :set ($err->[:len $err]) ("hosts/" . $n . ".rsc: " . ($ps->0) . ": VLAN " . $arg . " fehlt in vlans.rsc") }
          }
        }
      }
    }
  }
  # Hostfiles setzen u.U. Overrides in cfmG -> Daten neu laden
  :onerror e in={ $cfmLoadData ver=0 } do={}
  :return ({"err"=$err;"warn"=$warn})
}

# ---------- Probelauf (D29) ----------
# Schnappschuss von work/ nach plan/, signiertes Plan-Manifest für den Host; das Gerät führt
# die Rollen im Trockenlauf aus (cfmDry, *.post.rsc übersprungen) und schreibt die Änderungen
# nach cfm/out/plan.txt. Gestartet per :execute (ssh-exec bricht lange Befehle ab), das
# Ergebnis holt der Manager per SFTP ab und erkennt es an einer Kennung (id).
:global cfmPlan do={
  :global cfmMB; :global cfmInvLoad; :global cfmWrite; :global cfmExec; :global cfmManifests
  :global cfmCheck; :global cfmParseWork
  :if ([:len $host] = 0) do={ :error "Aufruf: \$cfmPlan host=<name>" }
  :local d ([$cfmInvLoad]->$host)
  :if ([:typeof $d] != "array") do={ :error ("unbekannter Host " . $host) }
  :local b [$cfmMB]
  :local bad [$cfmParseWork]
  :if ([:len $bad] > 0) do={ :error ("Probelauf abgebrochen:" . $bad) }
  :local ck [$cfmCheck]
  :foreach e in=($ck->"err") do={ :put ("Fehler (ein Release würde abbrechen): " . $e) }
  :foreach w in=($ck->"warn") do={ :put ("Warnung: " . $w) }
  # Schnappschuss work/ -> plan/
  :foreach f in=[/file/find where name~("^" . $b . "/plan/") and type!="directory"] do={ /file/remove $f }
  :local idx ({})
  :foreach f in=[/file/find where name~("^" . $b . "/work/") and type!="directory"] do={
    :local n [/file/get $f name]
    :local rel [:pick $n ([:len $b] + 6) [:len $n]]
    :local c [/file/get $f contents]
    $cfmWrite ($b . "/plan/" . $rel) $c
    :set ($idx->$rel) [:convert $c transform=sha512 to=hex]
  }
  $cfmWrite ($b . "/plan/index.dat") [:serialize to=json ({"v"=0;"msg"="plan";"files"=$idx})]
  :if ([$cfmManifests plan=$host] = 0) do={ :error ("kein Plan-Manifest für " . $host . " (Geräteschlüssel oder Pflichtdateien fehlen, siehe Log)") }
  :local id [:rndstr length=12 from="0123456789abcdef"]
  :local c (":execute \":global cfmArg {\\\"mode\\\"=\\\"plan\\\";\\\"id\\\"=\\\"" . $id . "\\\"}; /system script run cfm-agent\"")
  :local r [$cfmExec ip=($d->"ip") cmd=$c]
  :if (($r->"exit-code") != 0) do={ :error ("Gerät nicht erreichbar: " . ($r->"output")) }
  :put ("Probelauf auf " . $host . " läuft ...")
  :local lf ($b . "/state/" . $host . "/plan.txt")
  :local got false
  :local i 0
  :while (!$got and $i < 60) do={
    :delay 3s
    :set i ($i + 1)
    :foreach p in={"cfm/out";"flash/cfm/out"} do={
      :if (!$got) do={
        :onerror e in={
          /tool/fetch url=("sftp://" . ($d->"ip") . "/" . $p . "/plan.txt") user="cfm" dst-path=$lf as-value
          :if ([:pick [/file/get [find where name=$lf] contents] 0 17] = ("# id=" . $id)) do={ :set got true }
        } do={}
      }
    }
  }
  :if (!$got) do={ :error "keine Antwort vom Probelauf (Agent beschäftigt?) - später erneut" }
  :put [/file/get [find where name=$lf] contents]
  :return ""
}
