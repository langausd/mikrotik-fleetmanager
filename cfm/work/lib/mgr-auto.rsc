# ============================================================
# cfm lib/mgr-auto.rsc – Manager-Funktionen: Automatik
#   $cfmTick (jede Minute, Scheduler cfm-mgr-tick), $cfmAutoPromote, $cfmSecretSync,
#   $cfmHookState, $cfmMirror, $cfmPromoteManager, $cfmTakeover
# ============================================================
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
