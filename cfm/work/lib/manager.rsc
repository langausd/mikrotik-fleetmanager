# ============================================================
# cfm lib/manager.rsc – Manager-Funktionen (installiert als Skript "cfm-mgr")
# Laden im Terminal des Managers:  /system script run cfm-mgr
#
#   $cfmRelease [msg="..."]            work/ prüfen -> archive/v<N> -> Ring 0 -> Push
#   $cfmPromote [ring=1|2]             Version des vorigen Rings freigeben
#   $cfmRollback ver=<N> [all=yes]     alten Stand als neue Version freigeben
#   $cfmStatus                         Flottenübersicht
#   $cfmEnroll name=<n> ip=<ip> [role=<r>] [ring=<0-2>] [rekey=yes]
#                                      Gerät aufnehmen / Ersatzgerät übernehmen
#   $cfmPush [host=<n>|ring=<r>] [force=yes]   sofortigen Pull auslösen
#   $cfmAudit host=<n> [op=report|mark|purge] [sel=all|A1,A3]
#   $cfmSecret key=<k> value=<v>       Vault: user.<name>, psk.<ssid-key>, vaultpw
#   $cfmSecretPush [host=<n>]          Secrets per SSH direkt in die Geräte schreiben
#   $cfmVaultBackup                    verschlüsseltes Backup (inkl. Vault) nach vault/
#   $cfmBootstrap                      bootstrap.rsc für neue Geräte erzeugen
#   $cfmPromoteManager                 (auf dem Backup) zum Primary befördern
#   Onboarding (Push in die Werks-Config):
#   $cfmRegister name=<n> serial=<s> ip=<ip> [role=..] [ring=..] [pw=<Aufkleber-Passwort>]
#   $cfmOnboard sw=<switch> port=<port> [name=<n>]   Port temporär ins Onboarding-VLAN
#   $cfmOnboardStatus | $cfmOnboardAbort | $cfmPending | $cfmApprove serial=.. name=.. ip=..
# Automatisch jede Minute (Scheduler cfm-mgr-tick): $cfmTick
# ============================================================

:global cfmMB do={
  :if ([:len [/file/find where name="flash" and type="directory"]] > 0) do={ :return "flash/cfm" }
  :return "cfm"
}
:global cfmWrite do={
  :if ([:len [/file/find where name=$1]] = 0) do={ /file/add name=$1 contents=$2 } else={ /file/set [/file/find where name=$1] contents=$2 }
}
:global cfmRead do={
  :local r ""
  :onerror e in={ :set r [/file/get [/file/find where name=$1] contents] } do={}
  :return $r
}
:global cfmJson do={
  :global cfmRead
  :local r ({})
  :local c [$cfmRead $1]
  :if ([:len $c] > 0) do={ :onerror e in={ :set r [:deserialize from=json $c] } do={} }
  :return $r
}
:global cfmNow do={ :return ([:tonsec [:timestamp]] / 1000000000) }
:global cfmEsc do={
  :local s [:tostr $1]
  :local o ""
  :for i from=0 to=([:len $s] - 1) do={
    :local ch [:pick $s $i]
    :if ($ch = "\"" or $ch = "\\" or $ch = "\$") do={ :set o ($o . "\\" . $ch) } else={ :set o ($o . $ch) }
  }
  :return $o
}
:global cfmPad do={
  :local s [:tostr $1]
  :while ([:len $s] < $2) do={ :set s ($s . " ") }
  :return $s
}

# ---------- Daten laden (vom Manager selbst geschrieben -> vertrauenswürdig) ----------
:global cfmRings do={
  :global cfmJson; :global cfmMB
  :local r [$cfmJson ([$cfmMB] . "/meta/rings.dat")]
  :if ([:typeof ($r->"latest")] = "nothing") do={ :set ($r->"latest") 0 }
  :return $r
}
:global cfmInvLoad do={
  :global cfmMB; :global cfmInv
  :set cfmInv ({})
  :onerror e in={ /import file-name=([$cfmMB] . "/meta/inventory.rsc") verbose=no } do={ :log warning ("cfm: inventory.rsc: " . $e) }
  :return $cfmInv
}
:global cfmInvSave do={
  :global cfmWrite; :global cfmMB
  :local s "# cfm – Inventar (Manager-Metadaten, wirkt sofort). Auch von \$cfmEnroll geschrieben.\n# Key = Identity; serial, role (base immer; router,switch,ap,manager,manager-backup), ring 0-2, ip (MGMT)\n:global cfmInv {\n"
  :local sep ""
  :foreach n,d in=$1 do={
    :set s ($s . $sep . "  \"" . $n . "\"={\"serial\"=\"" . ($d->"serial") . "\";\"role\"=\"" . ($d->"role") . "\";\"ring\"=" . ($d->"ring") . ";\"ip\"=\"" . ($d->"ip") . "\"}")
    :set sep ";\n"
  }
  $cfmWrite ([$cfmMB] . "/meta/inventory.rsc") ($s . "\n}\n")
}
# globale Daten (cfmG, cfmVlans, cfmWifi …) der Version ver (Default: neueste; 0 = work/)
:global cfmLoadData do={
  :global cfmMB; :global cfmRings
  :local b [$cfmMB]
  :local v $ver
  :if ([:len [:tostr $v]] = 0) do={ :set v ([$cfmRings]->"latest") }
  :local d ($b . "/archive/v" . $v)
  :if ($v = 0) do={ :set d ($b . "/work") }
  :foreach f in={"global.rsc";"vlans.rsc";"profiles.rsc";"wifi.rsc"} do={ /import file-name=($d . "/" . $f) verbose=no }
  :return $v
}

# ---------- Vault (deaktivierte /ppp secret "cfm:<key>", Passwort = Secret) ----------
:global cfmVaultGet do={
  :local r ""
  :onerror e in={ :set r [/ppp/secret/get [find where name=("cfm:" . $1)] password] } do={}
  :return $r
}
:global cfmVaultSet do={
  :local n ("cfm:" . $1)
  :if ([:len [/ppp/secret/find where name=$n]] = 0) do={
    /ppp/secret/add name=$n password=$2 disabled=yes service=any comment="cfm-sys:vault"
  } else={ /ppp/secret/set [find where name=$n] password=$2 }
}
:global cfmSecret do={
  :global cfmVaultSet; :global cfmJson; :global cfmWrite; :global cfmMB
  :if ([:len $key] = 0 or [:len $value] = 0) do={ :error "Aufruf: \$cfmSecret key=<user.NAME|psk.SSIDKEY|vaultpw> value=<geheim>" }
  $cfmVaultSet $key $value
  :local f ([$cfmMB] . "/meta/vault.dat")
  :local vj [$cfmJson $f]
  :set ($vj->"ver") ([:tonum ($vj->"ver")] + 1)
  $cfmWrite $f [:serialize to=json $vj]
  :put ("Vault: " . $key . " gesetzt (Vault-Version " . ($vj->"ver") . "). Verteilung folgt automatisch.")
}

# ---------- SSH zu Geräten ----------
:global cfmExec do={
  :local r ({"exit-code"=255;"output"=""})
  :onerror e in={ :set r [/system/ssh-exec address=$ip user="cfm" command=$cmd as-value] } do={ :set ($r->"output") ("ssh-exec: " . $e) }
  :return $r
}

# ---------- Rolle / Primary ----------
:global cfmIsPrimary do={
  :global cfmMB; :global cfmG; :global cfmLoadData
  :if ([:len [/file/find where name=([$cfmMB] . "/meta/PROMOTED")]] > 0) do={ :return true }
  :if ([:typeof $cfmG] != "array") do={ $cfmLoadData }
  :local p [:pick ($cfmG->"managers") 0]
  :return ([:len [/ip/address/find where address~("^" . $p . "/")]] > 0)
}

# ---------- Externe Sicherung (Git-Host per ssh-exec) ----------
:global cfmHook do={
  :global cfmG; :global cfmLoadData
  :if ([:typeof $cfmG] != "array") do={ $cfmLoadData }
  :local h ($cfmG->"hook")
  :if ([:len [:tostr ($h->"host")]] = 0) do={ :return "" }
  :local hv "-"; :if ([:len [:tostr $ver]] > 0) do={ :set hv ("v" . $ver) }
  :local hh "-"; :if ([:len [:tostr $host]] > 0) do={ :set hh $host }
  :onerror e in={
    :local r [/system/ssh-exec address=($h->"host") user=($h->"user") command=($ev . " " . $hv . " " . $hh) as-value]
    :log info ("cfm: Hook " . $ev . ": " . [:pick ($r->"output") 0 200])
  } do={ :log warning ("cfm: Hook " . $ev . " fehlgeschlagen: " . $e) }
  :return ""
}

# ---------- Manifeste (pro Gerät, mit MAC) ----------
:global cfmManifests do={
  :global cfmMB; :global cfmRings; :global cfmInvLoad; :global cfmVaultGet; :global cfmWrite
  :global cfmJson; :global cfmG; :global cfmLoadData
  :local b [$cfmMB]
  :local rg [$cfmRings]
  $cfmLoadData
  :local reap ([:tonsec [:totime ($cfmG->"reapply")]] / 1000000000)
  :local inv [$cfmInvLoad]
  :local cnt 0
  :foreach name,d in=$inv do={
    :local ring [:tostr ($d->"ring")]
    :if ([:len $ring] = 0) do={ :set ring "2" }
    :local v ($rg->("r" . $ring))
    :local key [$cfmVaultGet ("mac." . ($d->"serial"))]
    :if ([:len $key] > 0 and [:len [:tostr $v]] > 0) do={
      :local fx ([$cfmJson ($b . "/archive/v" . $v . "/index.dat")]->"files")
      :local rl ("," . ($d->"role") . ",")
      :local want ({})
      :set ($want->[:len $want]) ({"lib/lib.rsc";1;1})
      :set ($want->[:len $want]) ({"lib/agent.rsc";0;1})
      :if ($rl ~ ",manager") do={ :set ($want->[:len $want]) ({"lib/manager.rsc";0;1}) }
      :foreach f in={"global.rsc";"vlans.rsc";"profiles.rsc";"wifi.rsc"} do={ :set ($want->[:len $want]) ({$f;1;1}) }
      :set ($want->[:len $want]) ({("hosts/" . $name . ".rsc");1;0})
      :set ($want->[:len $want]) ({"roles/base.rsc";1;1})
      :if ($rl ~ ",manager-backup,") do={ :set ($want->[:len $want]) ({"roles/manager.rsc";0;1}) }
      :foreach r in=[:toarray ($d->"role")] do={ :set ($want->[:len $want]) ({("roles/" . $r . ".rsc");1;1}) }
      :set ($want->[:len $want]) ({("hosts/" . $name . ".post.rsc");1;0})
      :local fl ({})
      :local ok true
      :foreach w in=$want do={
        :local h ($fx->($w->0))
        :if ([:len $h] > 0) do={ :set ($fl->[:len $fl]) ({($w->0);$h;($w->1)}) } else={
          :if (($w->2) = 1) do={ :set ok false; :log warning ("cfm: " . $name . ": Pflichtdatei fehlt in v" . $v . ": " . ($w->0)) }
        }
      }
      :if ($ok) do={
        :local m ({"v"=$v;"name"=$name;"role"=($d->"role");"ring"=[:tonum $ring];"ip"=($d->"ip");"serial"=($d->"serial");"reapply"=$reap;"watchdog"=($cfmG->"watchdog");"files"=$fl})
        :local body [:serialize to=json $m]
        :local mac [:convert ($key . [:convert $body transform=sha512 to=hex]) transform=sha512 to=hex]
        $cfmWrite ($b . "/live/m/" . ($d->"serial") . ".mf") ($body . "\n# mac=" . $mac . "\n")
        :set cnt ($cnt + 1)
      }
    }
  }
  :return $cnt
}

# ---------- Release / Ringe ----------
:global cfmRelease do={
  :global cfmMB; :global cfmIsPrimary; :global cfmWrite; :global cfmRings; :global cfmManifests
  :global cfmHook; :global cfmPush; :global cfmNow
  :local b [$cfmMB]
  :if (![$cfmIsPrimary]) do={ :error "nicht Primary: Backup-Manager ist read-only (\$cfmPromoteManager)" }
  :local files [/file/find where name~("^" . $b . "/work/") and type!="directory"]
  :local bad ""
  :foreach f in=$files do={
    :local n [/file/get $f name]
    :if ([/file/get $f size] > 60000) do={ :set bad ($bad . " " . $n . " (>60KB)") } else={
      :if ($n ~ "\\.rsc\$") do={ :onerror e in={ :local x [:parse [/file/get $f contents]] } do={ :set bad ($bad . " " . $n . " (" . $e . ")") } }
    }
  }
  :if ([:len $bad] > 0) do={ :error ("Release abgebrochen:" . $bad) }
  :local rg [$cfmRings]
  :local v (($rg->"latest") + 1)
  :local src $from
  :local idx ({})
  :foreach f in=$files do={
    :local n [/file/get $f name]
    :local rel [:pick $n ([:len $b] + 6) [:len $n]]
    :local c [/file/get $f contents]
    $cfmWrite ($b . "/archive/v" . $v . "/" . $rel) $c
    :set ($idx->$rel) [:convert $c transform=sha512 to=hex]
  }
  :local ix ({"v"=$v;"msg"=[:tostr $msg];"date"=([/system/clock/get date] . " " . [/system/clock/get time]);"files"=$idx})
  $cfmWrite ($b . "/archive/v" . $v . "/index.dat") [:serialize to=json $ix]
  :local now [$cfmNow]
  :set ($rg->"latest") $v
  :foreach r in={"0";"1";"2"} do={
    :if ($r = "0" or [:typeof ($rg->("r" . $r))] = "nothing" or $all = "yes") do={ :set ($rg->("r" . $r)) $v; :set ($rg->("t" . $r)) $now }
  }
  $cfmWrite ($b . "/meta/rings.dat") [:serialize to=json $rg]
  :local n [$cfmManifests]
  :put ("Release v" . $v . " erstellt (" . [:len $idx] . " Dateien, " . $n . " Manifeste) -> Ring 0" . [:tostr $msg])
  :log info ("cfm: Release v" . $v . " " . [:tostr $msg])
  $cfmHook ev="release" ver=$v
  :if ($all = "yes") do={ $cfmPush } else={ $cfmPush ring=0 }
  :return $v
}

:global cfmPromote do={
  :global cfmMB; :global cfmRings; :global cfmWrite; :global cfmManifests; :global cfmHook
  :global cfmPush; :global cfmNow
  :local r [:tonum $ring]
  :if ($r < 1 or $r > 2) do={
    :local rg [$cfmRings]
    :set r 1
    :if (($rg->"r1") = ($rg->"r0")) do={ :set r 2 }
  }
  :local rg [$cfmRings]
  :local v ($rg->("r" . ($r - 1)))
  :set ($rg->("r" . $r)) $v
  :set ($rg->("t" . $r)) [$cfmNow]
  $cfmWrite ([$cfmMB] . "/meta/rings.dat") [:serialize to=json $rg]
  $cfmManifests
  :put ("Ring " . $r . " -> v" . $v)
  :log info ("cfm: Ring " . $r . " -> v" . $v)
  $cfmHook ev="promote" ver=$v host=("ring" . $r)
  $cfmPush ring=$r
}

:global cfmRollback do={
  :global cfmMB; :global cfmRelease; :global cfmWrite; :global cfmHook
  :local b [$cfmMB]
  :if ([:len [/file/find where name=($b . "/archive/v" . $ver . "/index.dat")]] = 0) do={ :error ("Version v" . $ver . " nicht im Archiv") }
  # work/ sichern und durch den alten Stand ersetzen, dann normal releasen
  :foreach f in=[/file/find where name~("^" . $b . "/work/") and type!="directory"] do={ /file/remove $f }
  :foreach f in=[/file/find where name~("^" . $b . "/archive/v" . $ver . "/") and type!="directory"] do={
    :local n [/file/get $f name]
    :local rel [:pick $n ([:len ($b . "/archive/v" . $ver)] + 1) [:len $n]]
    :if ($rel != "index.dat") do={ $cfmWrite ($b . "/work/" . $rel) [/file/get $f contents] }
  }
  :local v [$cfmRelease msg=(" Rollback auf v" . $ver) all=$all]
  $cfmHook ev="rollback" ver=$v host=("from-v" . $ver)
}

# ---------- Push-Trigger ----------
:global cfmPush do={
  :global cfmInvLoad; :global cfmExec
  :local c ":execute \"/system script run cfm-agent\""
  :if ($force = "yes") do={ :set c ":execute \":global cfmArg \\\"force\\\"; /system script run cfm-agent\"" }
  :foreach name,d in=[$cfmInvLoad] do={
    :if (([:len $host] = 0 or $host = $name) and ([:len [:tostr $ring]] = 0 or [:tostr $ring] = [:tostr ($d->"ring")])) do={
      :local r [$cfmExec ip=($d->"ip") cmd=$c]
      :if (($r->"exit-code") = 0) do={ :put ("Push -> " . $name) } else={ :put ("Push -> " . $name . " FEHLER " . ($r->"output")) }
    }
  }
}

# ---------- Status ----------
:global cfmStatus do={
  :global cfmInvLoad; :global cfmRings; :global cfmJson; :global cfmMB; :global cfmPad; :global cfmNow
  :global cfmJson
  :local b [$cfmMB]
  :local rg [$cfmRings]
  :local vj [$cfmJson ($b . "/meta/vault.dat")]
  :local now [$cfmNow]
  :put ("Releases: latest v" . ($rg->"latest") . "  Ring0 v" . ($rg->"r0") . "  Ring1 v" . ($rg->"r1") . "  Ring2 v" . ($rg->"r2") . "   Vault v" . [:tonum ($vj->"ver")])
  :put ([$cfmPad "NAME" 10] . [$cfmPad "RING" 5] . [$cfmPad "SOLL" 6] . [$cfmPad "IST" 6] . [$cfmPad "ERGEBNIS" 26] . [$cfmPad "SV" 4] . "ZULETZT")
  :foreach name,d in=[$cfmInvLoad] do={
    :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
    :local sv [:tostr ($s->"sv")]
    :local p [:find $sv "sv="]
    :if ([:typeof $p] != "nil") do={ :set sv [:pick $sv ($p + 3) [:len $sv]] }
    :local age "-"
    :if ([:len [:tostr ($s->"seen")]] > 0) do={ :set age (($now - [:tonum ($s->"seen")]) / 60 . " min") }
    :local res [:tostr ($s->"res")]
    :if ([:len [:tostr ($s->"pending")]] > 0) do={ :set res ($res . " pend v" . ($s->"pending")) }
    :if ([:len [:tostr ($s->"bad")]] > 0) do={ :set res ($res . " bad v" . ($s->"bad")) }
    :put ([$cfmPad $name 10] . [$cfmPad ($d->"ring") 5] . [$cfmPad ("v" . ($rg->("r" . ($d->"ring")))) 6] . [$cfmPad ("v" . [:tostr ($s->"v")]) 6] . [$cfmPad [:pick $res 0 25] 26] . [$cfmPad $sv 4] . $age)
  }
}

# ---------- Audit (Hand-Objekte auf einem Gerät) ----------
:global cfmAudit do={
  :global cfmInvLoad; :global cfmExec; :global cfmHook
  :local d ([$cfmInvLoad]->$host)
  :if ([:typeof $d] != "array") do={ :error ("unbekannter Host " . $host) }
  :local o $op; :if ([:len $o] = 0) do={ :set o "report" }
  :local s $sel; :if ([:len $s] = 0) do={ :set s "all" }
  :if ($o != "report" and [:len $sel] = 0) do={ :error "mark/purge braucht sel=all oder sel=A1,A3" }
  :local r [$cfmExec ip=($d->"ip") cmd=(":global cfmArg {\"mode\"=\"audit\";\"op\"=\"" . $o . "\";\"sel\"=\"" . $s . "\"}; /system script run cfm-agent")]
  :put ($r->"output")
  :global cfmWrite; :global cfmMB
  $cfmWrite ([$cfmMB] . "/state/" . $host . "/audit.txt") ($r->"output")
  $cfmHook ev="audit" host=$host
}

# ---------- Rückkanal: Status + Export bei den Geräten abholen ----------
# Geräte haben am Manager nur Lesezugriff; der Manager (User cfm auf dem Gerät)
# holt cfm/out/status.json und – wenn neu – cfm/out/export.rsc nach state/<name>/.
:global cfmCollect do={
  :global cfmInvLoad; :global cfmMB; :global cfmJson
  :local b [$cfmMB]
  :local n 0
  :foreach name,d in=[$cfmInvLoad] do={
    :if (([:len $host] = 0 or $host = $name) and [:len [:tostr ($d->"ip")]] > 0) do={
      :if ([/ping ($d->"ip") count=1] > 0) do={
        :local sd ($b . "/state/" . $name)
        :local old [$cfmJson ($sd . "/status.dat")]
        :local got ""
        :foreach p in={"cfm/out";"flash/cfm/out"} do={
          :if ($got = "") do={
            :onerror e in={ /tool/fetch url=("sftp://" . ($d->"ip") . "/" . $p . "/status.json") user="cfm" dst-path=($sd . "/status.dat") as-value; :set got $p } do={}
          }
        }
        :if ($got != "") do={
          :set n ($n + 1)
          :local new [$cfmJson ($sd . "/status.dat")]
          :if ([:tostr ($new->"et")] != [:tostr ($old->"et")] or [:len [/file/find where name=($sd . "/export.rsc")]] = 0) do={
            :onerror e in={ /tool/fetch url=("sftp://" . ($d->"ip") . "/" . $got . "/export.rsc") user="cfm" dst-path=($sd . "/export.rsc") as-value } do={}
          }
        }
      }
    }
  }
  :return $n
}

# ---------- Vertrauen: alle Manager-Schlüssel auf Geräte verteilen ----------
# (nötig, damit ein später enrollter Backup-Manager im DR-Fall steuern kann)
:global cfmTrust do={
  :global cfmInvLoad; :global cfmMB; :global cfmRead; :global cfmExec
  :local b [$cfmMB]
  :local inv [$cfmInvLoad]
  :local c ":local old [/user/ssh-keys/find where user=cfm]; :local ok true;"
  :local i 0
  :foreach n,d in=$inv do={
    :if (("," . ($d->"role") . ",") ~ ",manager") do={
      :local k [$cfmRead ($b . "/meta/keys/" . $n . ".pem")]
      :if ([:len $k] > 0) do={
        :set i ($i + 1)
        :local e ""
        :for j from=0 to=([:len $k] - 1) do={ :local ch [:pick $k $j]; :if ($ch = "\n") do={ :set e ($e . "\\n") } else={ :if ($ch != "\r") do={ :set e ($e . $ch) } } }
        :set c ($c . "/file/add name=cfm-trust" . $i . ".pem contents=\"" . $e . "\"; :delay 300ms; :onerror x in={ /user/ssh-keys/import user=cfm public-key-file=cfm-trust" . $i . ".pem } do={ :set ok false };")
      }
    }
  }
  :set c ($c . ":if (\$ok) do={ /user/ssh-keys/remove \$old }; :put \$ok")
  :local cnt 0
  :foreach n,d in=$inv do={
    :if ([:len $host] = 0 or $host = $n) do={
      :local r [$cfmExec ip=($d->"ip") cmd=$c]
      :if (($r->"output") ~ "true") do={ :set cnt ($cnt + 1) } else={ :log warning ("cfm: Trust " . $n . ": " . [:pick ($r->"output") 0 120]) }
    }
  }
  :return $cnt
}

# ---------- Secret-Push ----------
:global cfmSecretPush do={
  :global cfmInvLoad; :global cfmVaultGet; :global cfmExec; :global cfmEsc; :global cfmJson
  :global cfmMB; :global cfmG; :global cfmWifi; :global cfmLoadData
  $cfmLoadData
  :local vv [:tonum ([$cfmJson ([$cfmMB] . "/meta/vault.dat")]->"ver")]
  :local done 0
  :foreach name,d in=[$cfmInvLoad] do={
    :if ([:len $host] = 0 or $host = $name) do={
      :local c ":local ok true;"
      :local upw false
      :foreach u,g in=($cfmG->"users") do={
        :local pw [$cfmVaultGet ("user." . $u)]
        :if ([:len $pw] > 0) do={
          :set upw true
          :set c ($c . ":if ([:len [/user/find where name=\"" . $u . "\"]] > 0) do={ /user/set [find where name=\"" . $u . "\"] password=\"" . [$cfmEsc $pw] . "\" disabled=no } else={ :set ok false };")
        }
      }
      # Werks-User admin gleich mit abschalten, wenn das Gerät den effektiven Wert
      # adminUser=disable meldet (inkl. Hostfile-Ausnahme) und die eigenen User gesetzt sind.
      # Die Rolle base setzt das bei jedem Apply ohnehin durch.
      :if ([:tostr ([$cfmJson ([$cfmMB] . "/state/" . $name . "/status.dat")]->"au")] = "disable" and $upw) do={
        :set c ($c . ":if (\$ok) do={ /user/set [find where name=\"admin\"] disabled=yes };")
      }
      :local rl ("," . ($d->"role") . ",")
      :if ($rl ~ ",manager") do={
        :foreach k,s in=($cfmWifi->"ssids") do={
          :local psk [$cfmVaultGet ("psk." . $k)]
          :if ([:len $psk] > 0) do={
            :set c ($c . ":if ([:len [/interface/wifi/security/find where name=\"cfm-" . $k . "\"]] > 0) do={ /interface/wifi/security/set [find where name=\"cfm-" . $k . "\"] passphrase=\"" . [$cfmEsc $psk] . "\" } else={ :set ok false };")
          }
        }
      }
      :if ($rl ~ ",manager-backup,") do={
        :foreach i in=[/ppp/secret/find where name~"^cfm:" and name!="cfm:key"] do={
          :local n [/ppp/secret/get $i name]
          :set c ($c . "/ppp/secret/remove [find where name=\"" . $n . "\"]; /ppp/secret/add name=\"" . $n . "\" password=\"" . [$cfmEsc [/ppp/secret/get $i password]] . "\" disabled=yes service=any comment=\"cfm-sys:vault\";")
        }
      }
      :set c ($c . ":if (\$ok) do={ /ppp/secret/set [find where name=\"cfm:key\"] comment=\"cfm-sys:key sv=" . $vv . "\" }; :put \$ok")
      :local r [$cfmExec ip=($d->"ip") cmd=$c]
      :if (($r->"output") ~ "true") do={ :set done ($done + 1); :log info ("cfm: Secrets v" . $vv . " -> " . $name) } else={
        :log warning ("cfm: Secret-Push " . $name . " unvollständig/fehlgeschlagen: " . [:pick ($r->"output") 0 120]) }
    }
  }
  :return $done
}

:global cfmVaultBackup do={
  :global cfmVaultGet; :global cfmMB; :global cfmJson; :global cfmWrite; :global cfmHook
  :local pw [$cfmVaultGet "vaultpw"]
  :if ([:len $pw] = 0) do={ :error "Vault-Passwort fehlt: \$cfmSecret key=vaultpw value=..." }
  :local b [$cfmMB]
  :local vn ($b . "/vault/" . [/system/identity/get name] . "-vault")
  /system/backup/save name=$vn password=$pw encryption=aes-sha256
  :delay 2s
  # .backup ist für lesende SFTP-Nutzer (Git-Host) gesperrt -> als .bak ablegen
  :onerror e in={ /file/remove [find where name=($vn . ".bak")] } do={}
  /file/set [find where name=($vn . ".backup")] name=($vn . ".bak")
  :local f ($b . "/meta/vault.dat")
  :local vj [$cfmJson $f]
  :set ($vj->"bver") ($vj->"ver")
  $cfmWrite $f [:serialize to=json $vj]
  :log info "cfm: Vault-Backup geschrieben"
  $cfmHook ev="vault"
}

# ---------- Onboarding ----------
:global cfmEnroll do={
  :global cfmMB; :global cfmExec; :global cfmInvLoad; :global cfmInvSave; :global cfmVaultSet
  :global cfmVaultGet; :global cfmManifests; :global cfmWrite; :global cfmRings; :global cfmG; :global cfmLoadData
  :if ([:len $name] = 0 or [:len $ip] = 0) do={ :error "Aufruf: \$cfmEnroll name=<identity> ip=<erreichbare IP> [role=..] [ring=..] [rekey=yes]" }
  :local b [$cfmMB]
  $cfmLoadData
  # 1) Seriennummer
  :local sc ":local s; :onerror e in={:set s [/system routerboard get serial-number]} do={}; :if ([:len \$s]=0) do={:onerror e in={:set s [/system/license/get system-id]} do={}}; :if ([:len \$s]=0) do={:onerror e in={:set s [/system/license/get software-id]} do={}}; :put \$s"
  :local r [$cfmExec ip=$ip cmd=$sc]
  :if (($r->"exit-code") != 0) do={ :error ("Gerät nicht per SSH (User cfm) erreichbar: " . ($r->"output")) }
  :local serial [:pick ($r->"output") 0 [:find ($r->"output") "\r"]]
  :if ([:typeof [:find ($r->"output") "\r"]] = "nil") do={ :set serial [:pick ($r->"output") 0 [:find (($r->"output") . "\n") "\n"]] }
  # 2) Geräteschlüssel (asymmetrisch): Host-Key ed25519 erzeugen/exportieren, Private-Key für User cfm
  :local rk "no"; :if ($rekey = "yes") do={ :set rk "yes" }
  :set r [$cfmExec ip=$ip cmd=(":if ([:len [/user/ssh-keys/private/find where user=cfm]] = 0 or \"" . $rk . "\" = \"yes\") do={ /ip/ssh/set host-key-type=ed25519; /ip/ssh/regenerate-host-key; :delay 1s; /ip/ssh/export-host-key key-file-prefix=cfm-id; :delay 1s; /user/ssh-keys/private/remove [find where user=cfm]; /user/ssh-keys/private/import user=cfm private-key-file=cfm-id_ed25519.pem } else={ /ip/ssh/export-host-key key-file-prefix=cfm-id; :delay 1s }; :put [/file/get cfm-id_ed25519_pub.pem contents]; /file/remove [find where name~\"^cfm-id\"]")]
  :local pub ($r->"output")
  :if (!($pub ~ "BEGIN PUBLIC KEY")) do={ :error ("Schlüsselexport fehlgeschlagen: " . $pub) }
  :local kf ($b . "/meta/keys/" . $name . ".pem")
  $cfmWrite $kf [:pick $pub [:find $pub "-----BEGIN"] [:len $pub]]
  :local du ("cfmd-" . $name)
  :if ([:len [/user/find where name=$du]] = 0) do={
    /user/add name=$du group=cfm-dev password=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"] comment=("cfm-sys:dev " . $serial)
  } else={ /user/set [find where name=$du] comment=("cfm-sys:dev " . $serial) }
  /user/ssh-keys/remove [find where user=$du]
  :delay 500ms
  /file/add name=("cfm-import-" . $name . ".pem") contents=[/file/get [/file/find where name=$kf] contents]
  :delay 500ms
  /user/ssh-keys/import user=$du public-key-file=("cfm-import-" . $name . ".pem")
  # 3) Inventar (Ersatzgerät: alte Seriennummer + MAC-Schlüssel entfernen)
  :local inv [$cfmInvLoad]
  :local d ($inv->$name)
  :if ([:typeof $d] != "array") do={ :set d ({"role"="switch";"ring"=2}) }
  :if ([:len [:tostr ($d->"serial")]] > 0 and ($d->"serial") != $serial) do={
    /ppp/secret/remove [find where name=("cfm:mac." . ($d->"serial"))]
    :put ("Ersatzgerät: " . ($d->"serial") . " -> " . $serial)
  }
  :set ($d->"serial") $serial
  :set ($d->"ip") $ip
  :if ([:len $role] > 0) do={ :set ($d->"role") $role }
  :if ([:len [:tostr $ring]] > 0) do={ :set ($d->"ring") [:tonum $ring] }
  :set ($inv->$name) $d
  $cfmInvSave $inv
  # 4) MAC-Schlüssel erzeugen, im Vault ablegen und per SSH ins Gerät schreiben
  :local k [:rndstr length=64 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"]
  $cfmVaultSet ("mac." . $serial) $k
  $cfmManifests
  # 5) Agent-Konfiguration + Agent + Scheduler auf dem Gerät
  :local ms ""
  :foreach a in=($cfmG->"managers") do={ :set ms ($ms . ";\\\"" . $a . "\\\"") }
  :local conf (":global cfmConf {\\\"mgrs\\\"={" . [:pick $ms 1 [:len $ms]] . "};\\\"path\\\"=\\\"" . ($cfmG->"mgrPath") . "\\\";\\\"user\\\"=\\\"" . $du . "\\\"}")
  :local v ([$cfmRings]->("r" . ($d->"ring")))
  :local p0 [:pick ($cfmG->"managers") 0]
  :local c ("/ppp/secret/remove [find where name=\"cfm:key\"]; /ppp/secret/add name=\"cfm:key\" password=\"" . $k . "\" disabled=yes service=any comment=\"cfm-sys:key sv=0\";")
  :set c ($c . "/system/script/remove [find where name=\"cfm-conf\"]; /system/script/add name=cfm-conf policy=read comment=\"cfm-sys:conf\" source=\"" . $conf . "\";")
  :set c ($c . "/tool/fetch url=\"sftp://" . $p0 . "/" . ($cfmG->"mgrPath") . "/archive/v" . $v . "/lib/agent.rsc\" user=" . $du . " dst-path=cfm/agent-init.rsc as-value; :delay 1s;")
  :set c ($c . "/system/script/remove [find where name=\"cfm-agent\"]; /system/script/add name=cfm-agent comment=\"cfm-sys:agent\" policy=ftp,reboot,read,write,policy,test,password,sensitive source=[/file/get cfm/agent-init.rsc contents];")
  :set c ($c . "/system/scheduler/remove [find where name=\"cfm-agent\"]; /system/scheduler/add name=cfm-agent comment=\"cfm-sys:agent\" start-time=startup interval=" . ($cfmG->"interval") . " on-event=\"/system script run cfm-agent\"; :put ok")
  :set r [$cfmExec ip=$ip cmd=$c]
  :if (!(($r->"output") ~ "ok")) do={ :error ("Agent-Installation fehlgeschlagen: " . ($r->"output")) }
  # 6) Vertrauen: neues Gerät kennt alle Manager; neuer Manager wird allen Geräten bekannt
  :global cfmTrust
  :if (("," . ($d->"role") . ",") ~ ",manager") do={ $cfmTrust } else={ $cfmTrust host=$name }
  :local ex ":execute \"/system script run cfm-agent\""
  $cfmExec ip=$ip cmd=$ex
  :put ("Enrolled: " . $name . " (" . $serial . ", " . ($d->"role") . ", Ring " . ($d->"ring") . ") – erster Pull läuft. Secrets folgen automatisch nach dem ersten Apply.")
  :log info ("cfm: enrolled " . $name . " " . $serial)
}

# ---------- Bootstrap-Datei für neue Geräte ----------
:global cfmBootstrap do={
  :global cfmMB; :global cfmWrite; :global cfmInvLoad; :global cfmG; :global cfmLoadData; :global cfmRead
  $cfmLoadData
  :local b [$cfmMB]
  :local keys ""
  :foreach n,d in=[$cfmInvLoad] do={
    :if (("," . ($d->"role") . ",") ~ ",manager") do={
      :local k [$cfmRead ($b . "/meta/keys/" . $n . ".pem")]
      :if ([:len $k] > 0) do={
        :local e ""
        :for i from=0 to=([:len $k] - 1) do={ :local ch [:pick $k $i]; :if ($ch = "\n") do={ :set e ($e . "\\n") } else={ :if ($ch != "\r") do={ :set e ($e . $ch) } } }
        :set keys ($keys . ";\"" . $e . "\"")
      }
    }
  }
  :local mv ($cfmG->"mgmtVlan")
  :global cfmVlans
  :local vv ($cfmVlans->[:tostr $mv])
  :local go 1
  :if ([:len [:tostr ($vv->"gw")]] > 0) do={ :set go [:tonum ($vv->"gw")] }
  :local net ("192.168." . $mv . ".0/24")
  :if ([:len [:tostr ($vv->"net")]] > 0) do={ :set net ($vv->"net") }
  :local na [:toip [:pick $net 0 [:find $net "/"]]]
  :local gwip [:tostr ($na + $go)]
  :local pfx [:pick $net ([:find $net "/"] + 1) [:len $net]]
  :local ipx ([:tostr ($na + 99)] . "/" . $pfx)
  :local up "ether1"
  :local out ($b . "/cfm-bootstrap.rsc")
  :local hint "# Auf neuem/zurückgesetztem Gerät: IP/Uplink anpassen, dann /import cfm-bootstrap.rsc\n# Danach am Manager: \$cfmEnroll name=<name> ip=<ip> role=<rolle> ring=<0-2>\n"
  # name=<n>: gerätespezifisch für den Onboarding-Push (MGMT-IP aus dem Inventar, alle Ports)
  :if ([:len $name] > 0) do={
    :local d ([$cfmInvLoad]->$name)
    :if ([:typeof $d] != "array") do={ :error ("unbekanntes Gerät " . $name) }
    :set ipx (($d->"ip") . "/" . $pfx)
    :set up "*"
    :set out ($b . "/onb/" . $name . "-bootstrap.rsc")
    :set hint ("# gerätespezifisch für " . $name . " (Onboarding-Push, läuft per run-after-reset)\n")
  }
  :local s ("# cfm bootstrap – erzeugt am " . [/system/clock/get date] . " von " . [/system/identity/get name] . "\n" . $hint)
  :set s ($s . ":local ip \"" . $ipx . "\"\n:local uplink \"" . $up . "\"\n:local mv " . $mv . "\n:local gw \"" . $gwip . "\"\n")
  :set s ($s . ":local keys {" . [:pick $keys 1 [:len $keys]] . "}\n")
  :global cfmRings
  :local body [$cfmRead ($b . "/archive/v" . ([$cfmRings]->"latest") . "/lib/bootstrap-body.rsc")]
  :if ([:len $body] = 0) do={ :set body [$cfmRead ($b . "/work/lib/bootstrap-body.rsc")] }
  $cfmWrite $out ($s . $body)
  :if ([:len $name] = 0) do={ :put ("geschrieben: " . $out . " (per Winbox/SFTP holen)") }
  :return $out
}

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

# ---------- Automatik (Scheduler cfm-mgr-tick) ----------
:global cfmAutoPromote do={
  :global cfmRings; :global cfmInvLoad; :global cfmJson; :global cfmMB; :global cfmNow; :global cfmPromote
  :global cfmG
  :local rg [$cfmRings]
  :local b [$cfmMB]
  :local now [$cfmNow]
  :foreach r in={1;2} do={
    :local prev ($rg->("r" . ($r - 1)))
    :if (($rg->("r" . $r)) != $prev) do={
      :local soak [:tostr [:pick ($cfmG->"ringSoak") ($r - 1)]]
      :if ($soak != "manual" and ($now - [:tonum ($rg->("t" . ($r - 1)))]) > ([:tonsec [:totime $soak]] / 1000000000)) do={
        :local ok true
        :foreach name,d in=[$cfmInvLoad] do={
          :if ([:tonum ($d->"ring")] = ($r - 1)) do={
            :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
            :if (($s->"v") != $prev or ($s->"res") != "ok" or [:len [:tostr ($s->"pending")]] > 0) do={ :set ok false }
          }
        }
        :if ($ok) do={ $cfmPromote ring=$r; :return true }
      }
    }
  }
  :return false
}

:global cfmSecretSync do={
  :global cfmInvLoad; :global cfmJson; :global cfmMB; :global cfmSecretPush; :global cfmNow; :global cfmSpTry
  :local b [$cfmMB]
  :local vv [:tonum ([$cfmJson ($b . "/meta/vault.dat")]->"ver")]
  :if ($vv = 0) do={ :return 0 }
  :if ([:typeof $cfmSpTry] != "array") do={ :set cfmSpTry ({}) }
  :local now [$cfmNow]
  :foreach name,d in=[$cfmInvLoad] do={
    :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
    :local sv [:tostr ($s->"sv")]
    :local p [:find $sv "sv="]
    :if ([:typeof $p] != "nil") do={ :set sv [:pick $sv ($p + 3) [:len $sv]] }
    :if (($s->"res") = "ok" and [:tonum $sv] != $vv and ($now - [:tonum ($cfmSpTry->$name)]) > 900) do={
      :set ($cfmSpTry->$name) $now
      $cfmSecretPush host=$name
    }
  }
}

:global cfmHookState do={
  :global cfmMB; :global cfmJson; :global cfmWrite; :global cfmHook
  :local b [$cfmMB]
  # Signatur über Name + Änderungszeit aller Exporte/Audits (Strings lassen sich
  # in RouterOS nicht mit < / > vergleichen)
  :local all ""
  :foreach f in=[/file/find where name~("^" . $b . "/state/.*/(export.rsc|audit.txt)\$")] do={
    :set all ($all . [/file/get $f name] . "@" . [:tostr [/file/get $f last-modified]] . ";")
  }
  :local sig [:convert $all transform=md5 to=hex]
  :local hf ($b . "/meta/hook.dat")
  :local hj [$cfmJson $hf]
  :if ([:len $all] > 0 and $sig != ($hj->"state")) do={
    :set ($hj->"state") $sig
    $cfmWrite $hf [:serialize to=json $hj]
    $cfmHook ev="state"
  }
}

:global cfmMirror do={
  :global cfmMB; :global cfmConf; :global cfmJson; :global cfmInvLoad; :global cfmNow; :global cfmMirT; :global cfmRings
  :local now [$cfmNow]
  :if (($now - [:tonum $cfmMirT]) < 300) do={ :return false }
  :set cfmMirT $now
  /system/script/run cfm-conf
  :local b [$cfmMB]
  :local src ("sftp://" . [:pick ($cfmConf->"mgrs") 0] . "/" . ($cfmConf->"path") . "/")
  :local u ($cfmConf->"user")
  # Flag statt :return im :onerror-Block (dort verlässt :return die Funktion nicht)
  :local get do={ :local ok false; :onerror e in={ /tool/fetch url=($s . $r) user=$u dst-path=$l as-value; :set ok true } do={}; :return $ok }
  :foreach f in={"meta/rings.dat";"meta/inventory.rsc";"meta/vault.dat"} do={ $get s=$src u=$u r=$f l=($b . "/" . $f) }
  :local rg [$cfmRings]
  :foreach r in={"r0";"r1";"r2";"latest"} do={
    :local v ($rg->$r)
    :if ([:len [:tostr $v]] > 0 and [:len [/file/find where name=($b . "/archive/v" . $v . "/index.dat")]] = 0) do={
      :local ip ("archive/v" . $v . "/")
      # Hilfsdatei ohne führenden Punkt (RouterOS listet Dotfiles nicht in /file).
      # index.dat erst schreiben, wenn ALLE Dateien da sind – sonst beim nächsten Lauf erneut.
      :if ([$get s=$src u=$u r=($ip . "index.dat") l=($b . "/mirror-index.dat")]) do={
        :local fx ([$cfmJson ($b . "/mirror-index.dat")]->"files")
        :local okAll ([:len $fx] > 0)
        :foreach rel,h in=$fx do={ :if (![$get s=$src u=$u r=($ip . $rel) l=($b . "/" . $ip . $rel)]) do={ :set okAll false } }
        :if ($okAll) do={ $get s=$src u=$u r=($ip . "index.dat") l=($b . "/" . $ip . "index.dat") } else={ :log warning ("cfm: Spiegel v" . $v . " unvollständig, neuer Versuch beim nächsten Lauf") }
      }
    }
  }
  :foreach name,d in=[$cfmInvLoad] do={
    $get s=$src u=$u r=("live/m/" . ($d->"serial") . ".mf") l=($b . "/live/m/" . ($d->"serial") . ".mf")
    :foreach f in={"status.dat";"export.rsc";"audit.txt"} do={ $get s=$src u=$u r=("state/" . $name . "/" . $f) l=($b . "/state/" . $name . "/" . $f) }
  }
  :return true
}

:global cfmPromoteManager do={
  :global cfmMB; :global cfmWrite; :global cfmRings
  :local b [$cfmMB]
  :local v ([$cfmRings]->"latest")
  $cfmWrite ($b . "/meta/PROMOTED") ("promoted " . [/system/clock/get date])
  :foreach f in=[/file/find where name~("^" . $b . "/archive/v" . $v . "/") and type!="directory"] do={
    :local n [/file/get $f name]
    :local rel [:pick $n ([:len ($b . "/archive/v" . $v)] + 1) [:len $n]]
    :if ($rel != "index.dat") do={ $cfmWrite ($b . "/work/" . $rel) [/file/get $f contents] }
  }
  :put ("Befördert: dieser Manager ist jetzt Primary (work/ = v" . $v . "). Reihenfolge in global.rsc managers anpassen und releasen!")
}

:global cfmTakeCnt
:global cfmTakeover do={
  :global cfmG; :global cfmLoadData; :global cfmTakeCnt
  $cfmLoadData
  :if ([/ping [:pick ($cfmG->"managers") 0] count=3] = 0) do={ :set cfmTakeCnt ([:tonum $cfmTakeCnt] + 1) } else={ :set cfmTakeCnt 0 }
  :if ($cfmTakeCnt >= 3) do={
    /interface/wifi/capsman/set enabled=yes
    /system/scheduler/remove [find where name="cfm-takeover"]
    :log warning "cfm: Primary-Manager seit 3 min weg – CAPsMAN auf Backup aktiviert"
  }
}

:global cfmTick do={
  :global cfmIsPrimary; :global cfmMirror; :global cfmAutoPromote; :global cfmSecretSync
  :global cfmHookState; :global cfmVaultBackup; :global cfmJson; :global cfmMB; :global cfmVaultGet
  :onerror e in={
    :if ([$cfmIsPrimary]) do={
      :global cfmCollect; $cfmCollect
      :global cfmOnbTick; $cfmOnbTick
      $cfmAutoPromote
      $cfmSecretSync
      $cfmHookState
      :local vj [$cfmJson ([$cfmMB] . "/meta/vault.dat")]
      # als String vergleichen: [:tonum nothing] ist nil, und "3 != nil" ist weder wahr noch falsch
      :if ([:tostr ($vj->"ver")] != [:tostr ($vj->"bver")] and [:len [$cfmVaultGet "vaultpw"]] > 0) do={ $cfmVaultBackup }
    } else={ $cfmMirror }
  } do={ :log warning ("cfm: tick: " . $e) }
}
