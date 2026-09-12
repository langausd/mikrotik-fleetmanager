# ============================================================
# cfm lib/mgr-onboard.rsc – Manager-Funktionen: Onboarding per Push in die Werks-Config
#   $cfmRegister, $cfmOnboard, $cfmOnboardStatus, $cfmOnboardAbort, $cfmPending, $cfmApprove
#   Ablauf je Minute: $cfmOnbTick (aus $cfmTick)   (Übersicht aller Befehle: lib/mgr-core.rsc)
# ============================================================
# ---------- Onboarding: Push in die Werks-Config ----------
# $cfmRegister -> $cfmOnboard sw=.. port=.. -> Gerät einstecken -> $cfmOnbTick (im Tick)

# Versionsvergleich: $1 >= $2  (z.B. "7.24.2 (stable)" gegen "7.20")
:global cfmVerGe do={
  :local sp do={
    :local r ({})
    :local s ([:tostr $1] . ".")
    :local st 0
    :for i from=0 to=([:len $s] - 1) do={
      :if ([:pick $s $i] = ".") do={ :set ($r->[:len $r]) [:tonum [:pick $s $st $i]]; :set st ($i + 1) }
    }
    :return $r
  }
  :local a [$sp [:pick $1 0 [:find ($1 . " ") " "]]]
  :local b [$sp $2]
  :for i from=0 to=2 do={
    :local x ($a->$i)
    :local y ($b->$i)
    :if ([:typeof $x] != "num") do={ :set x 0 }
    :if ([:typeof $y] != "num") do={ :set y 0 }
    :if ($x > $y) do={ :return true }
    :if ($x < $y) do={ :return false }
  }
  :return true
}

# VID des Onboarding-VLANs (vlans.rsc: onboard="yes"), "" wenn keins; cfmVlans muss geladen sein
:global cfmOnbVid do={
  :global cfmVlans
  :foreach vid,v in=$cfmVlans do={ :if ([:tostr ($v->"onboard")] = "yes") do={ :return $vid } }
  :return ""
}

:global cfmRegister do={
  :global cfmInvLoad; :global cfmInvSave; :global cfmVaultSet; :global cfmMB; :global cfmRings
  :if ([:len $name] = 0 or [:len $serial] = 0 or [:len $ip] = 0) do={ :error "Aufruf: \$cfmRegister name=<n> serial=<Seriennr.> ip=<MGMT-IP> [role=<r>] [ring=<0-2>] [pw=<Aufkleber-Passwort>]" }
  :local inv [$cfmInvLoad]
  :local d ($inv->$name)
  :if ([:typeof $d] != "array") do={ :set d ({"role"="switch";"ring"=2}) }
  :set ($d->"serial") $serial
  :set ($d->"ip") $ip
  :if ([:len $role] > 0) do={ :set ($d->"role") $role }
  :if ([:len [:tostr $ring]] > 0) do={ :set ($d->"ring") [:tonum $ring] }
  :set ($inv->$name) $d
  $cfmInvSave $inv
  :if ([:len $pw] > 0) do={ $cfmVaultSet ("init." . $serial) $pw }
  :local v ([$cfmRings]->"latest")
  :if ([:len [/file/find where name=([$cfmMB] . "/archive/v" . $v . "/hosts/" . $name . ".rsc")]] = 0) do={
    :put ("Hinweis: hosts/" . $name . ".rsc fehlt in v" . $v . " - anlegen und releasen, sonst fehlt das Port-Profil des Uplinks")
  }
  :put ("Registriert: " . $name . " (" . $serial . ", " . ($d->"role") . ", Ring " . ($d->"ring") . ", " . $ip . ")")
}

:global cfmPending do={
  :global cfmJson; :global cfmMB
  :local p [$cfmJson ([$cfmMB] . "/meta/pending.dat")]
  :if ([:len $p] = 0) do={ :put "keine unbekannten Geräte"; :return 0 }
  :foreach s,d in=$p do={ :put ($s . "  " . ($d->"model") . "  RouterOS " . ($d->"ver") . "  an " . ($d->"addr")) }
  :put "Freigabe: \$cfmApprove serial=<Seriennr.> name=<n> ip=<MGMT-IP> role=<r> ring=<0-2>"
  :return [:len $p]
}

:global cfmApprove do={
  :global cfmRegister; :global cfmJson; :global cfmWrite; :global cfmMB
  $cfmRegister name=$name serial=$serial ip=$ip role=$role ring=$ring pw=$pw
  :local f ([$cfmMB] . "/meta/pending.dat")
  :local p [$cfmJson $f]
  :set ($p->$serial)
  $cfmWrite $f [:serialize to=json $p]
  :put "freigegeben - die laufende Onboarding-Sitzung macht beim nächsten Tick weiter"
}

# Port auf dem Switch in den Onboarding-Modus schalten (on=yes: PVID = Onboarding-VLAN,
# untagged; die tagged VLANs des Profils bleiben) inkl. Fail-safe-Timer; on=no: Timer weg.
# Zurück aufs Profil setzt anschließend ein erzwungener Apply des Switches ($cfmOnboardEnd).
:global cfmOnbPort do={
  :global cfmInvLoad; :global cfmExec; :global cfmG; :global cfmLoadData; :global cfmOnbVid
  $cfmLoadData
  :local d ([$cfmInvLoad]->$sw)
  :if ([:typeof $d] != "array") do={ :error ("unbekannter Switch " . $sw) }
  :local c "/system/scheduler/remove [find where name=\"cfm-onboard-revert\"]; :put ok"
  :if ($on = "yes") do={
    :local ov [$cfmOnbVid]
    :if ([:len $ov] = 0) do={ :error "kein Onboarding-VLAN in vlans.rsc (onboard=yes)" }
    :local fs ([:totime ($cfmG->"onboard"->"timeout")] + 10m)
    # Reihenfolge: erst Bridge-VLAN-Tabelle (Port aus "tagged" nehmen und in einem Schritt nach
    # "untagged" – ein Trunk ist dort bereits tagged), erst dann die PVID
    :set c (":local p [/interface/bridge/port/find where interface=\"" . $port . "\"]; :if ([:len \$p] = 0) do={ :error \"Port " . $port . " ist nicht in der Bridge\" }; :local v [/interface/bridge/vlan/find where bridge=bridge and vlan-ids=" . $ov . "]; :if ([:len \$v] = 0) do={ /interface/bridge/vlan/add bridge=bridge vlan-ids=" . $ov . " untagged=" . $port . " comment=\"cfm-sys:onboard\" } else={ :local nt ({}); :foreach x in=[/interface/bridge/vlan/get \$v tagged] do={ :if ([:len \$x] > 0 and \$x != \"" . $port . "\") do={ :set (\$nt->[:len \$nt]) \$x } }; :local nu ({}); :foreach x in=[/interface/bridge/vlan/get \$v untagged] do={ :if ([:len \$x] > 0 and \$x != \"" . $port . "\") do={ :set (\$nu->[:len \$nu]) \$x } }; :set (\$nu->[:len \$nu]) \"" . $port . "\"; /interface/bridge/vlan/set \$v tagged=\$nt untagged=\$nu }; /interface/bridge/port/set \$p pvid=" . $ov . " frame-types=admit-all; /system/scheduler/remove [find where name=\"cfm-onboard-revert\"]; /system/scheduler/add name=cfm-onboard-revert interval=" . $fs . " comment=\"cfm-sys:onboard\" on-event=\":global cfmArg \\\"force\\\"; /system/scheduler/remove [find where name=cfm-onboard-revert]; /system script run cfm-agent\"; :put ok")
  }
  :local r [$cfmExec ip=($d->"ip") cmd=$c]
  :return ($r->"output")
}

:global cfmOnboard do={
  :global cfmJson; :global cfmWrite; :global cfmMB; :global cfmOnbPort; :global cfmNow; :global cfmInvLoad
  :if ([:len $sw] = 0 or [:len $port] = 0) do={ :error "Aufruf: \$cfmOnboard sw=<Switch> port=<Port> [name=<registriertes Gerät>]" }
  :local f ([$cfmMB] . "/meta/onboard.dat")
  :local ses [$cfmJson $f]
  :if ([:len [:tostr ($ses->"state")]] > 0) do={ :error ("es läuft bereits eine Sitzung an " . ($ses->"sw") . "/" . ($ses->"port") . " (" . ($ses->"state") . "), ggf. \$cfmOnboardAbort") }
  :if ([:len $name] > 0 and [:typeof ([$cfmInvLoad]->$name)] != "array") do={ :error ("Gerät " . $name . " ist nicht registriert (\$cfmRegister)") }
  :local r [$cfmOnbPort sw=$sw port=$port on="yes"]
  :if (!($r ~ "(^|\n)ok")) do={
    # nichts halb umgeschaltet zurücklassen: Switch per erzwungenem Apply auf sein Profil
    :global cfmPush
    $cfmPush host=$sw force="yes"
    :error ("Port konnte nicht umgeschaltet werden (Switch wird zurückgesetzt): " . $r)
  }
  :local ns ({"sw"=$sw;"port"=$port;"name"=[:tostr $name];"t0"=[$cfmNow];"state"="wait";"upd"=0;"msg"="warte auf Gerät"})
  $cfmWrite $f [:serialize to=json $ns]
  :log info ("cfm: Onboarding-Port " . $sw . "/" . $port . " aktiv")
  :put ("Onboarding-Port " . $sw . "/" . $port . " ist aktiv. Gerät jetzt einstecken bzw. einschalten - Stand: \$cfmOnboardStatus")
}

:global cfmOnboardStatus do={
  :global cfmJson; :global cfmMB
  :local s [$cfmJson ([$cfmMB] . "/meta/onboard.dat")]
  :if ([:len [:tostr ($s->"state")]] = 0) do={ :put "keine Onboarding-Sitzung aktiv"; :return "" }
  :put ("Sitzung " . ($s->"sw") . "/" . ($s->"port") . "  Status: " . ($s->"state") . "  Gerät: " . [:tostr ($s->"name")] . "  " . [:tostr ($s->"msg")])
  :return ($s->"state")
}

# Sitzung beenden: Fail-safe weg, Port per erzwungenem Apply zurück auf sein Profil
:global cfmOnboardEnd do={
  :global cfmJson; :global cfmWrite; :global cfmMB; :global cfmOnbPort; :global cfmPush
  :local f ([$cfmMB] . "/meta/onboard.dat")
  :local s [$cfmJson $f]
  :if ([:len [:tostr ($s->"sw")]] = 0) do={ :return false }
  $cfmOnbPort sw=($s->"sw") port=($s->"port") on="no"
  $cfmPush host=($s->"sw") force="yes"
  $cfmWrite $f "{}"
  :log info ("cfm: Onboarding " . ($s->"sw") . "/" . ($s->"port") . " beendet: " . [:tostr $msg])
  :return true
}

:global cfmOnboardAbort do={
  :global cfmOnboardEnd
  $cfmOnboardEnd msg="abgebrochen"
  :put "Onboarding abgebrochen, der Port fällt auf sein Profil zurück"
}

# Platzhalter ersetzen: $1 Text, $2 Suchtext, $3 Ersatz
:global cfmSub do={
  :local t [:tostr $1]
  :local o ""
  :local p [:find $t $2]
  :while ([:typeof $p] != "nil") do={
    :set o ($o . [:pick $t 0 $p] . $3)
    :set t [:pick $t ($p + [:len $2]) [:len $t]]
    :set p [:find $t $2]
  }
  :return ($o . $t)
}

# SFTP als admin mit Passwort zum Werksgerät. up=yes: Upload l -> r, sonst Download r -> l
:global cfmOnbSftp do={
  :local ok false
  :onerror e in={
    :if ($up = "yes") do={
      /tool/fetch url=("sftp://" . $a . "/" . $r) user="admin" password=$p src-path=$l upload=yes as-value
    } else={
      /tool/fetch url=("sftp://" . $a . "/" . $r) user="admin" password=$p dst-path=$l as-value
    }
    :set ok true
  } do={}
  :return $ok
}

# Zustandsmaschine der Onboarding-Sitzung (Tick, jede Minute):
#   update -> wait -> probe -> eval -> (update | pending | push) -> enroll -> Ende
:global cfmOnbTick do={
  :global cfmJson; :global cfmWrite; :global cfmMB; :global cfmNow; :global cfmG; :global cfmLoadData
  :global cfmInvLoad; :global cfmVaultGet; :global cfmOnbVid; :global cfmNet; :global cfmOnboardEnd
  :global cfmVerGe; :global cfmExec; :global cfmEnroll; :global cfmBootstrap; :global cfmRings
  :global cfmRead; :global cfmSub; :global cfmOnbSftp; :global cfmOnbPort; :global cfmHook; :global cfmOnbBusy
  :local b [$cfmMB]
  :local f ($b . "/meta/onboard.dat")
  :local s [$cfmJson $f]
  :local st [:tostr ($s->"state")]
  :if ([:len $st] = 0) do={ :return "" }
  :local now [$cfmNow]
  :if ([:typeof $cfmOnbBusy] = "num" and ($now - $cfmOnbBusy) < 300) do={ :return "busy" }
  :set cfmOnbBusy $now
  $cfmLoadData
  :local to ([:tonsec [:totime ($cfmG->"onboard"->"timeout")]] / 1000000000)
  :if (($now - [:tonum ($s->"t0")]) > $to) do={ :set cfmOnbBusy; $cfmOnboardEnd msg=("Timeout im Status " . $st); :return "timeout" }
  :local ov [$cfmOnbVid]
  :local onet [$cfmNet $ov]
  :local gw [:tostr ($onet->"gw")]
  :local inv [$cfmInvLoad]
  :local rv ([$cfmRings]->"latest")
  :local fail ""
  :local pw ""
  :if ([:len [:tostr ($s->"pwk")]] > 0 and ($s->"pwk") != "-") do={ :set pw [$cfmVaultGet ($s->"pwk")] }

  # update: nach dem Update-Neustart erneut prüfen
  :if ($st = "update") do={
    :if (($now - [:tonum ($s->"tu")]) > 150) do={ :set st "wait"; :set ($s->"msg") "Update sollte fertig sein, prüfe erneut" }
  }

  # wait: Gerät suchen (Werks-IP .1 oder DHCP-Lease) und Probe hochladen
  :if ($st = "wait") do={
    $cfmOnbPort sw=($s->"sw") port=($s->"port") on="yes"
    :local probe [$cfmRead ($b . "/archive/v" . $rv . "/lib/onboard-probe.rsc")]
    :if ([:len $probe] = 0) do={ :set fail ("lib/onboard-probe.rsc fehlt in v" . $rv) } else={
      :set probe [$cfmSub [$cfmSub $probe "@GW@" $gw] "@CH@" [:tostr ($cfmG->"rosChannel")]]
      $cfmWrite ($b . "/onb/probe.rsc") $probe
      :local cands ({})
      :local dip [:tostr (($onet->"addr") + 1)]
      :if ([/ping $dip count=1] > 0) do={ :set ($cands->[:len $cands]) $dip }
      :foreach l in=[/ip/dhcp-server/lease/find where server=("dhcp" . $ov) and status="bound"] do={
        :set ($cands->[:len $cands]) [:tostr [/ip/dhcp-server/lease/get $l address]]
      }
      :local pks ({})
      :foreach n,d in=$inv do={
        :local ser [:tostr ($d->"serial")]
        :if ([:len $ser] > 0) do={
          :if (($s->"name") = $n or ([:len [:tostr ($s->"name")]] = 0 and [:len [$cfmVaultGet ("mac." . $ser)]] = 0)) do={ :set ($pks->[:len $pks]) ("init." . $ser) }
        }
      }
      :set ($pks->[:len $pks]) "-"
      :local done false
      :foreach a in=$cands do={
        :foreach k in=$pks do={
          :local kp ""
          :if ($k != "-") do={ :set kp [$cfmVaultGet $k] }
          :if (!$done and ($k = "-" or [:len $kp] > 0)) do={
            :if ([$cfmOnbSftp a=$a p=$kp r="cfm-probe.auto.rsc" l=($b . "/onb/probe.rsc") up="yes"]) do={
              :set done true
              :set pw $kp
              :set ($s->"addr") $a
              :set ($s->"pwk") $k
              :set st "probe"
              :set ($s->"msg") ("Probe an " . $a . " übertragen")
            }
          }
        }
      }
      :if ($done) do={ :delay 20s }
    }
  }

  # probe: Ergebnis (cfm-probe.txt) holen und zerlegen
  :if ($st = "probe") do={
    :if ([$cfmOnbSftp a=($s->"addr") p=$pw r="cfm-probe.txt" l=($b . "/onb/probe.txt")]) do={
      :local t ([$cfmRead ($b . "/onb/probe.txt")] . "\n")
      :while ([:len $t] > 0) do={
        :local n [:find $t "\n"]
        :local ln [:pick $t 0 $n]
        :set t [:pick $t ($n + 1) [:len $t]]
        :local e [:find $ln "="]
        :if ([:typeof $e] != "nil") do={ :set ($s->("p-" . [:pick $ln 0 $e])) [:pick $ln ($e + 1) [:len $ln]] }
      }
      :set st "eval"
    } else={ :set ($s->"msg") "warte auf Probe-Ergebnis" }
  }

  # eval: Seriennummer gegen die Registrierung, Update-Entscheidung
  :if ($st = "eval") do={
    :local ser [:tostr ($s->"p-serial")]
    :local nm ""
    :foreach n,d in=$inv do={ :if ([:tostr ($d->"serial")] = $ser) do={ :set nm $n } }
    :if ([:len [:tostr ($s->"name")]] > 0 and $nm != ($s->"name")) do={
      :set fail ("Seriennummer " . $ser . " passt nicht zu " . ($s->"name"))
    } else={
      :if ([:len $nm] = 0) do={
        :local pf ($b . "/meta/pending.dat")
        :local pd [$cfmJson $pf]
        :set ($pd->$ser) ({"model"=($s->"p-model");"ver"=($s->"p-ver");"addr"=($s->"addr");"t"=$now})
        $cfmWrite $pf [:serialize to=json $pd]
        :set ($s->"msg") ("unbekannte Seriennummer " . $ser . ", Freigabe per \$cfmApprove")
        :set st "pending"
      } else={
        :set ($s->"dev") $nm
        :local up [:tostr ($s->"p-update")]
        :if ($up ~ "^[0-9]") do={
          :set ($s->"upd") ([:tonum ($s->"upd")] + 1)
          :if (($s->"upd") > 2) do={ :set fail "Update wiederholt erfolglos" } else={
            :set st "update"
            :set ($s->"tu") $now
            :set ($s->"msg") ("RouterOS-Update auf " . $up . " läuft")
          }
        } else={
          :if (![$cfmVerGe ($s->"p-ver") ($cfmG->"rosMin")]) do={
            :set fail ("RouterOS " . ($s->"p-ver") . " ist älter als " . ($cfmG->"rosMin") . " und ein Update war nicht möglich (" . $up . ")")
          } else={ :set st "push" }
        }
      }
    }
  }

  # pending: weiter, sobald die Seriennummer registriert ist
  :if ($st = "pending") do={
    :foreach n,d in=$inv do={ :if ([:tostr ($d->"serial")] = [:tostr ($s->"p-serial")]) do={ :set st "eval" } }
  }

  # push: gerätespezifischen Bootstrap + Reset hochladen, dann auf die MGMT-IP warten und enrollen
  :if ($st = "push") do={
    :local nm ($s->"dev")
    :local fip [:tostr ($inv->$nm->"ip")]
    :if ([:len [:tostr ($s->"tp")]] = 0) do={
      :local bf [$cfmBootstrap name=$nm]
      :local rp "cfm-bootstrap.rsc"
      :if (($s->"p-flash") = "yes") do={ :set rp "flash/cfm-bootstrap.rsc" }
      $cfmWrite ($b . "/onb/go.rsc") [$cfmSub [$cfmRead ($b . "/archive/v" . $rv . "/lib/onboard-go.rsc")] "@PATH@" $rp]
      :local u1 [$cfmOnbSftp a=($s->"addr") p=$pw r=$rp l=$bf up="yes"]
      :local u2 false
      :if ($u1) do={ :set u2 [$cfmOnbSftp a=($s->"addr") p=$pw r="cfm-go.auto.rsc" l=($b . "/onb/go.rsc") up="yes"] }
      :if ($u2) do={
        :set ($s->"tp") $now
        :set ($s->"msg") ("Bootstrap übertragen, " . $nm . " setzt sich zurück")
      } else={ :set fail "Upload des Bootstraps fehlgeschlagen" }
    } else={
      :local r [$cfmExec ip=$fip cmd=":put ok"]
      :if (($r->"output") ~ "ok") do={
        :onerror e in={ /file/remove [find where name=($b . "/state/" . $nm . "/status.dat")] } do={}
        :local ee ""
        :onerror e in={ $cfmEnroll name=$nm ip=$fip } do={ :set ee $e }
        :if ([:len $ee] > 0) do={ :set fail ("Enroll: " . $ee) } else={
          :set st "enroll"
          :set ($s->"te") $now
          :set ($s->"msg") "enrolled, warte auf den ersten Apply"
        }
      } else={
        :if (($now - [:tonum ($s->"tp")]) > 600) do={ :set fail ($nm . " ist nach dem Reset nicht unter " . $fip . " erreichbar") }
      }
    }
  }

  # enroll: erster Apply bestätigt -> Port zurück aufs Profil, fertig
  :if ($st = "enroll") do={
    :local nm ($s->"dev")
    :local sd [$cfmJson ($b . "/state/" . $nm . "/status.dat")]
    :local want ([$cfmRings]->("r" . [:tostr ($inv->$nm->"ring")]))
    :if (($sd->"res") = "ok" and [:tostr ($sd->"v")] = [:tostr $want]) do={
      :set cfmOnbBusy
      $cfmOnboardEnd msg=("erfolgreich: " . $nm)
      $cfmHook ev="onboard" host=$nm
      :return "done"
    }
    :if ([:tostr ($sd->"res")] ~ "^failed") do={ :set fail ($nm . ": erster Apply fehlgeschlagen (" . ($sd->"res") . ")") }
    :if (($now - [:tonum ($s->"te")]) > 900) do={ :set fail ($nm . ": erster Apply nicht bestätigt") }
  }

  :set cfmOnbBusy
  :if ([:len $fail] > 0) do={
    :log warning ("cfm: Onboarding fehlgeschlagen: " . $fail)
    $cfmOnboardEnd msg=("FEHLER: " . $fail)
    :return "fail"
  }
  :set ($s->"state") $st
  $cfmWrite $f [:serialize to=json $s]
  :return $st
}
