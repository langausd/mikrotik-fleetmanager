# ============================================================
# cfm lib/mgr-core.rsc – Manager-Funktionen: Kern
# Die Manager-Funktionen liegen in lib/mgr-*.rsc (je Datei < 60 KB, Grenze von /file get).
# Jede Datei wird als Skript cfm-mgr-<modul> installiert; das Skript cfm-mgr lädt alle.
#   mgr-core     Hilfsfunktionen, Daten, Vault, Release/Ringe, Archiv, Push, Status, Audit,
#                Secrets, Identitätsprüfung und Geräteschlüssel
#   mgr-check    inhaltliche Prüfung von work/ ($cfmCheck), Probelauf ($cfmPlan)
#   mgr-enroll   Geräte aufnehmen, Bootstrap-Datei, Manager-Schlüssel verteilen
#   mgr-onboard  Onboarding per Push in die Werks-Config
#   mgr-ros      RouterOS-Pakete und -Updates ($cfmUpgrade)
#   mgr-net      Verkabelung per LLDP ($cfmLinks, Netzplan), WLAN-Kanäle ($cfmChannels)
#   mgr-auto     Automatik (Scheduler cfm-mgr-tick), Spiegel und Übernahme durch den Backup
# Die Module hängen nur beim Aufruf voneinander ab (:global in den Funktionen), die
# Ladereihenfolge ist daher egal.
#
# Laden im Terminal des Managers:  /system script run cfm-mgr
#
#   $cfmRelease [msg="..."] [force=yes]  work/ prüfen -> archive/v<N> -> Ring 0 -> Push
#                                      (force=yes: trotz Fehlern der inhaltlichen Prüfung)
#   $cfmCheck                          inhaltliche Prüfung von work/ (läuft auch beim Release)
#   $cfmPlan host=<n>                  Probelauf: was würde ein Release von work/ ändern?
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
#   $cfmRekey host=<n>|all=yes         Geräteschlüssel (Manifest-Signatur) erneuern
#   $cfmArchivePrune [keep=<n>]        alte Versionen löschen (läuft nach jedem Release)
#   $cfmUpgrade ver=<x.y.z> host=<n>|ring=<r>|all=yes [at="YYYY-MM-DD HH:MM"]
#                                      RouterOS-Update/-Downgrade, Pakete kommen vom Manager
#   $cfmUpgrade cancel=yes host=..|ring=..|all=yes   Auftrag zurückziehen; ohne ver: Übersicht
#   $cfmLinks [accept=yes] [export=yes]   Verkabelung (LLDP) prüfen, Netzplan state/netzplan.md
#   $cfmChannels                       Kanäle der APs, Warnung bei gleichem Kanal an einem Switch
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
# plan=<host>: nur für diesen Host ein Plan-Manifest aus dem Schnappschuss plan/ ($cfmPlan)
:global cfmManifests do={
  :global cfmMB; :global cfmRings; :global cfmInvLoad; :global cfmVaultGet; :global cfmWrite
  :global cfmJson; :global cfmG; :global cfmLoadData
  :local b [$cfmMB]
  :local rg [$cfmRings]
  :local pl [:len $plan]
  :if ($pl > 0) do={ $cfmLoadData ver=0 } else={ $cfmLoadData }
  :local reap ([:tonsec [:totime ($cfmG->"reapply")]] / 1000000000)
  :local inv [$cfmInvLoad]
  :local ord [$cfmJson ($b . "/meta/upgrade.dat")]
  :local cnt 0
  :foreach name,d in=$inv do={
   :if ($pl = 0 or $plan = $name) do={
    :local ring [:tostr ($d->"ring")]
    :if ([:len $ring] = 0) do={ :set ring "2" }
    :local v ($rg->("r" . $ring))
    :local src ("archive/v" . $v)
    :local out ($b . "/live/m/" . ($d->"serial") . ".mf")
    :if ($pl > 0) do={ :set v 0; :set src "plan"; :set out ($b . "/plan/m/" . ($d->"serial") . ".mf") }
    :local key [$cfmVaultGet ("mac." . ($d->"serial"))]
    :if ([:len $key] > 0 and [:len [:tostr $v]] > 0) do={
      :local fx ([$cfmJson ($b . "/" . $src . "/index.dat")]->"files")
      :local rl ("," . ($d->"role") . ",")
      :local want ({})
      :set ($want->[:len $want]) ({"lib/lib.rsc";1;1})
      :set ($want->[:len $want]) ({"lib/agent.rsc";0;1})
      # Manager-Funktionen: alle Module lib/mgr-*.rsc der Version (installiert die Rolle manager)
      :if ($rl ~ ",manager") do={
        :foreach p,h in=$fx do={ :if ($p ~ "^lib/mgr-") do={ :set ($want->[:len $want]) ({$p;0;1}) } }
      }
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
          :if (($w->2) = 1) do={ :set ok false; :log warning ("cfm: " . $name . ": Pflichtdatei fehlt in " . $src . ": " . ($w->0)) }
        }
      }
      :if ($ok) do={
        :local m ({"v"=$v;"src"=$src;"name"=$name;"role"=($d->"role");"ring"=[:tonum $ring];"ip"=($d->"ip");"serial"=($d->"serial");"reapply"=$reap;"watchdog"=($cfmG->"watchdog");"files"=$fl})
        # offener RouterOS-Auftrag ($cfmUpgrade); ändert den Manifest-Hash des Agents nicht
        :if ($pl = 0 and [:typeof ($ord->$name)] = "array") do={ :set ($m->"ros") ($ord->$name) }
        :local body [:serialize to=json $m]
        :local mac [:convert ($key . [:convert $body transform=sha512 to=hex]) transform=sha512 to=hex]
        $cfmWrite $out ($body . "\n# mac=" . $mac . "\n")
        :set cnt ($cnt + 1)
      }
    }
   }
  }
  :return $cnt
}

# work/-Dateien auf Größe (/file get liest nur ~60 KB) und Syntax (:parse) prüfen -> "" oder Liste
:global cfmParseWork do={
  :global cfmMB
  :local b [$cfmMB]
  :local bad ""
  :foreach f in=[/file/find where name~("^" . $b . "/work/") and type!="directory"] do={
    :local n [/file/get $f name]
    :if ([/file/get $f size] > 60000) do={ :set bad ($bad . " " . $n . " (>60KB)") } else={
      :if ($n ~ "\\.rsc\$") do={ :onerror e in={ :local x [:parse [/file/get $f contents]] } do={ :set bad ($bad . " " . $n . " (" . $e . ")") } }
    }
  }
  :return $bad
}

# ---------- Release / Ringe ----------
:global cfmRelease do={
  :global cfmMB; :global cfmIsPrimary; :global cfmWrite; :global cfmRings; :global cfmManifests
  :global cfmHook; :global cfmPush; :global cfmNow; :global cfmParseWork; :global cfmCheck; :global cfmArchivePrune
  :local b [$cfmMB]
  :if (![$cfmIsPrimary]) do={ :error "nicht Primary: Backup-Manager ist read-only (\$cfmPromoteManager)" }
  :local bad [$cfmParseWork]
  :if ([:len $bad] > 0) do={ :error ("Release abgebrochen:" . $bad) }
  # inhaltliche Prüfung (mgr-check): Fehler stoppen das Release, force=yes übergeht sie
  :local ck [$cfmCheck]
  :foreach w in=($ck->"warn") do={ :put ("Warnung: " . $w) }
  :if ([:len ($ck->"err")] > 0) do={
    :foreach e in=($ck->"err") do={ :put ("Fehler: " . $e) }
    :if ($force != "yes") do={ :error ("Release abgebrochen (Prüfung): " . [:len ($ck->"err")] . " Fehler - beheben oder force=yes") }
    :put "force=yes: Release trotz Prüffehlern"
  }
  :local files [/file/find where name~("^" . $b . "/work/") and type!="directory"]
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
  :local pr [$cfmArchivePrune]
  :if ($pr > 0) do={ :put ("Archiv: " . $pr . " alte Versionen gelöscht") }
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
  # force: ein alter, bewährter Stand soll nicht an neueren Prüfregeln scheitern
  :local v [$cfmRelease msg=(" Rollback auf v" . $ver) all=$all force="yes"]
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
  :local ord [$cfmJson ($b . "/meta/upgrade.dat")]
  :put ([$cfmPad "NAME" 10] . [$cfmPad "RING" 5] . [$cfmPad "SOLL" 6] . [$cfmPad "IST" 6] . [$cfmPad "ERGEBNIS" 26] . [$cfmPad "SV" 4] . [$cfmPad "ROUTEROS" 16] . "ZULETZT")
  :foreach name,d in=[$cfmInvLoad] do={
    :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
    :local ros [:tostr ($s->"ros")]
    :set ros [:pick $ros 0 [:find ($ros . " ") " "]]
    :if ([:typeof ($ord->$name)] = "array") do={ :set ros ($ros . "->" . [:pick [:tostr ($ord->$name->"rv")] 1 99]) }
    :local sv [:tostr ($s->"sv")]
    :local p [:find $sv "sv="]
    :if ([:typeof $p] != "nil") do={ :set sv [:pick $sv ($p + 3) [:len $sv]] }
    :local age "-"
    :if ([:len [:tostr ($s->"seen")]] > 0) do={ :set age (($now - [:tonum ($s->"seen")]) / 60 . " min") }
    :local res [:tostr ($s->"res")]
    :if ([:len [:tostr ($s->"pending")]] > 0) do={ :set res ($res . " pend v" . ($s->"pending")) }
    :if ([:len [:tostr ($s->"bad")]] > 0) do={ :set res ($res . " bad v" . ($s->"bad")) }
    :put ([$cfmPad $name 10] . [$cfmPad ($d->"ring") 5] . [$cfmPad ("v" . ($rg->("r" . ($d->"ring")))) 6] . [$cfmPad ("v" . [:tostr ($s->"v")]) 6] . [$cfmPad [:pick $res 0 25] 26] . [$cfmPad $sv 4] . [$cfmPad $ros 16] . $age)
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

# ---------- Secret-Push ----------
:global cfmSecretPush do={
  :global cfmInvLoad; :global cfmVaultGet; :global cfmExec; :global cfmEsc; :global cfmJson
  :global cfmMB; :global cfmG; :global cfmWifi; :global cfmLoadData; :global cfmChallenge
  $cfmLoadData
  :local vv [:tonum ([$cfmJson ([$cfmMB] . "/meta/vault.dat")]->"ver")]
  :local done 0
  :foreach name,d in=[$cfmInvLoad] do={
   :if ([:len $host] = 0 or $host = $name) do={
    # Identitätsprüfung: Secrets nur an ein Gerät, das seinen Geräteschlüssel kennt
    :if (![$cfmChallenge ip=($d->"ip") serial=($d->"serial")]) do={
      :log warning ("cfm: Secret-Push " . $name . ": Identitätsprüfung fehlgeschlagen (Geräteschlüssel falsch oder Gerät nicht erreichbar) - übersprungen")
    } else={
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
        # PPSK-Passphrasen (die Rolle manager legt die Multi-Passphrase-Einträge mit Zufallswert an)
        :foreach k,ents in=($cfmWifi->"ppsk") do={
          :foreach e,o in=$ents do={
            :local pp [$cfmVaultGet ("ppsk." . $k . "." . $e)]
            :if ([:len $pp] > 0) do={
              :local tg ("cfm:mpp:" . $k . "." . $e)
              :set c ($c . ":if ([:len [/interface/wifi/security/multi-passphrase/find where comment=\"" . $tg . "\"]] > 0) do={ /interface/wifi/security/multi-passphrase/set [find where comment=\"" . $tg . "\"] passphrase=\"" . [$cfmEsc $pp] . "\" } else={ :set ok false };")
            }
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

# ---------- Archiv aufräumen (D27) ----------
# Behält die letzten archiveKeep Versionen (global.rsc, Standard 10) und alle Versionen, die ein
# Ring nutzt oder die ein Gerät meldet (angewendet, ausstehend, als fehlerhaft markiert).
:global cfmArchivePrune do={
  :global cfmMB; :global cfmRings; :global cfmInvLoad; :global cfmJson; :global cfmG
  :local b [$cfmMB]
  :local rg [$cfmRings]
  :local k [:tonum $keep]
  :if ([:typeof $k] != "num") do={ :set k [:tonum ($cfmG->"archiveKeep")] }
  :if ([:typeof $k] != "num") do={ :set k 10 }
  :if ($k < 1) do={ :set k 1 }
  :local used ({})
  :foreach r in={"r0";"r1";"r2";"latest"} do={ :set ($used->[:tostr ($rg->$r)]) 1 }
  :foreach name,d in=[$cfmInvLoad] do={
    :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
    :foreach f in={"v";"pending";"bad";"target"} do={ :if ([:len [:tostr ($s->$f)]] > 0) do={ :set ($used->[:tostr ($s->$f)]) 1 } }
  }
  :local lim ([:tonum ($rg->"latest")] - $k)
  :local pre ($b . "/archive/v")
  :local n 0
  :foreach f in=[/file/find where name~("^" . $pre . "[0-9]+\$") and type="directory"] do={
    :local vs [:pick [/file/get $f name] [:len $pre] 99]
    :if ([:tonum $vs] <= $lim and [:typeof ($used->$vs)] = "nothing") do={
      :local dd ($pre . $vs)
      # index.dat zuerst: eine halb gelöschte Version gilt damit sofort als nicht vorhanden
      :onerror e in={ /file/remove [find where name=($dd . "/index.dat")] } do={}
      :foreach x in=[/file/find where name~("^" . $dd . "/") and type!="directory"] do={ /file/remove $x }
      :local ds [/file/find where name~("^" . $dd . "(/|\$)") and type="directory"]
      :for i from=([:len $ds] - 1) to=0 step=-1 do={ :onerror e in={ /file/remove [:pick $ds $i] } do={} }
      :set n ($n + 1)
    }
  }
  :if ($n > 0) do={ :log info ("cfm: Archiv: " . $n . " alte Versionen gelöscht (behalten: " . $k . " + genutzte)") }
  :return $n
}

# ---------- Identitätsprüfung (D28, vor jedem Secret-Push) ----------
# ssh-exec prüft keine Host-Schlüssel. Deshalb beweist das Gerät, dass es seinen
# Geräteschlüssel kennt: sha512(Schlüssel . Zufallswert). ip= serial= -> true/false
:global cfmChallenge do={
  :global cfmVaultGet; :global cfmExec
  :local key [$cfmVaultGet ("mac." . $serial)]
  :if ([:len $key] = 0) do={ :return false }
  :local n [:rndstr length=32 from="0123456789abcdef"]
  :local c (":put [:convert ([/ppp/secret/get [find where name=\"cfm:key\"] password] . \"" . $n . "\") transform=sha512 to=hex]")
  :local r [$cfmExec ip=$ip cmd=$c]
  :return (($r->"output") ~ [:convert ($key . $n) transform=sha512 to=hex])
}

# ---------- Geräteschlüssel erneuern (D28, nur per Befehl) ----------
# Nicht während eines Applys: dessen Rollback-Sicherung ist mit dem alten Schlüssel verschlüsselt.
:global cfmRekey do={
  :global cfmInvLoad; :global cfmChallenge; :global cfmExec; :global cfmVaultSet; :global cfmManifests
  :global cfmJson; :global cfmWrite; :global cfmMB; :global cfmIsPrimary
  :if (![$cfmIsPrimary]) do={ :error "nicht Primary: Backup-Manager ist read-only (\$cfmPromoteManager)" }
  :if ([:len $host] = 0 and $all != "yes") do={ :error "Aufruf: \$cfmRekey host=<name> | all=yes" }
  :local n 0
  :foreach name,d in=[$cfmInvLoad] do={
    :if ($all = "yes" or $host = $name) do={
      :if (![$cfmChallenge ip=($d->"ip") serial=($d->"serial")]) do={ :put ("Rekey " . $name . ": Identitätsprüfung fehlgeschlagen - übersprungen") } else={
        :local k [:rndstr length=64 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"]
        :local c (":if ([:len [/system/scheduler/find where name=\"cfm-watchdog\"]] = 0 and [:len [/system/script/job/find where script=\"cfm-agent\"]] = 0) do={ /ppp/secret/set [find where name=\"cfm:key\"] password=\"" . $k . "\"; :put rekey-ok } else={ :put busy }")
        :local r [$cfmExec ip=($d->"ip") cmd=$c]
        :if (($r->"output") ~ "rekey-ok") do={
          $cfmVaultSet ("mac." . ($d->"serial")) $k
          :set n ($n + 1)
          :put ("Rekey " . $name . ": neuer Geräteschlüssel aktiv")
          :log info ("cfm: Geräteschlüssel " . $name . " erneuert")
        } else={ :put ("Rekey " . $name . ": gerade nicht möglich (Apply läuft oder nicht erreichbar), später erneut: " . [:pick ($r->"output") 0 80]) }
      }
    }
  }
  :if ($n > 0) do={
    # Manifeste neu signieren; Vault-Version erhöhen, damit Backup-Manager und Vault-Backup nachziehen
    $cfmManifests
    :local f ([$cfmMB] . "/meta/vault.dat")
    :local vj [$cfmJson $f]
    :set ($vj->"ver") ([:tonum ($vj->"ver")] + 1)
    $cfmWrite $f [:serialize to=json $vj]
  }
  :return $n
}
