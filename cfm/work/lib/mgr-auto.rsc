# ============================================================
# cfm lib/mgr-auto.rsc – Manager-Funktionen: Automatik
#   $cfmTick (Scheduler cfm-mgr-tick, Intervall global.rsc "mgrTick"), $cfmOnbTickRun (Scheduler
#   cfm-mgr-onb-tick, fest 1m), $cfmAutoPromote, $cfmSecretSync, $cfmFollow (Scheduler cfm-mgr-follow,
#   Nachfassen nach einem Push), $cfmHookState, $cfmMirror, $cfmPromoteManager; Benachrichtigungen: lib/mgr-notify.rsc
# ============================================================
# ---------- Automatik (Scheduler cfm-mgr-tick) ----------
:global cfmAutoPromote do={
  :global cfmRings; :global cfmInvLoad; :global cfmJson; :global cfmMB; :global cfmNow; :global cfmPromote
  :global cfmG; :global cfmEnrolled
  :local rg [$cfmRings]
  :local b [$cfmMB]
  :local now [$cfmNow]
  :foreach r in={1;2} do={
    :local prev ($rg->("r" . ($r - 1)))
    :if (($rg->("r" . $r)) != $prev) do={
      :local soak [:tostr [:pick ($cfmG->"ringSoak") ($r - 1)]]
      :if ($soak != "manual" and ($now - [:tonum ($rg->("t" . ($r - 1)))]) > ([:tonsec [:totime $soak]] / 1000000000)) do={
        :local ok true
        # nicht aufgenommene Geräte (Platzhalter) melden nie einen Status und hielten den Ring sonst auf
        :foreach name,d in=[$cfmInvLoad] do={
          :if ([:tonum ($d->"ring")] = ($r - 1) and [$cfmEnrolled $d]) do={
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

# Nachfassen nach einem Push (Befund 2026-10-28): Legt der Apply auf einem CAPsMAN eine neue Master-SSID
# an, fehlt ihrem Profil die Passphrase - er bleibt aus, bis der Secret-Push kommt ($cfmPskMissing meldet
# SV 0), mit dem allgemeinen Tick bis zu mgrTick ohne WLAN. $cfmPush trägt angestoßene CAPsMAN-Geräte
# deshalb in meta/follow.dat ein (Name -> Zeitpunkt), der Scheduler cfm-mgr-follow holt alle 30 s ihren
# Status ab. Meldet einer einen Lauf seit dem Push mit veraltetem SV, pusht er die Secrets sofort. Nach
# 10 min ohne Meldung übernimmt wieder der allgemeine Tick ($cfmSecretSync); leer, entfernt er sich.
:global cfmFollowAdd do={
  :global cfmMB; :global cfmJson; :global cfmWrite
  :local f ([$cfmMB] . "/meta/follow.dat")
  :local q [$cfmJson $f]
  :foreach n,t in=$1 do={ :set ($q->$n) $t }
  $cfmWrite $f [:serialize to=json $q]
  :if ([:len [/system/scheduler/find where name="cfm-mgr-follow"]] = 0) do={
    /system/scheduler/add name="cfm-mgr-follow" interval=30s comment="cfm-sys:follow" on-event=":if ([:len [/system/script/job/find where script=\"cfm-mgr-follow\"]] < 2) do={ :global cfmTickBusy; :if (\$cfmTickBusy != true) do={ :onerror e in={ /system script run cfm-mgr; :global cfmFollow; \$cfmFollow } do={ :log warning (\"cfm: follow: \" . \$e) } } }"
  }
}

:global cfmFollow do={
  :global cfmMB; :global cfmJson; :global cfmWrite; :global cfmNow; :global cfmCollect; :global cfmSecretPush
  :global cfmSpTry; :global cfmFileEx
  :local b [$cfmMB]
  :local f ($b . "/meta/follow.dat")
  :local vv [:tonum ([$cfmJson ($b . "/meta/vault.dat")]->"ver")]
  :if ([:typeof $vv] != "num") do={ :set vv 0 }
  :local now [$cfmNow]
  :local rest ({})
  :foreach name,t in=[$cfmJson $f] do={
    :local done (($now - [:tonum $t]) > 600)
    :if (!$done) do={
      $cfmCollect host=$name
      :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
      # seen = Start des Laufs, der den Status geschrieben hat: erst ein Lauf nach dem Push zählt
      :if ([:tonum ($s->"seen")] >= [:tonum $t]) do={
        :set done true
        :local sv [:tostr ($s->"sv")]
        :local p [:find $sv "sv="]
        :if ([:typeof $p] != "nil") do={ :set sv [:pick $sv ($p + 3) [:len $sv]] }
        :if (($s->"res") = "ok" and $vv > 0 and [:tonum $sv] != $vv) do={
          :log info ("cfm: " . $name . " meldet nach dem Push Secrets v" . $sv . " (Vault v" . $vv . ") - Secret-Push sofort")
          :if ([:typeof $cfmSpTry] != "array") do={ :set cfmSpTry ({}) }
          :set ($cfmSpTry->$name) $now
          $cfmSecretPush host=$name
        }
      }
    }
    :if (!$done) do={ :set ($rest->$name) $t }
  }
  :if ([:len $rest] > 0) do={ $cfmWrite $f [:serialize to=json $rest] } else={
    :if ([$cfmFileEx $f]) do={ /file/remove $f }
    /system/scheduler/remove [find where name="cfm-mgr-follow"]
  }
}

:global cfmHookState do={
  :global cfmMB; :global cfmJson; :global cfmWrite; :global cfmHook
  :local b [$cfmMB]
  # Signatur über Name + Änderungszeit aller Exporte/Audits (Strings lassen sich
  # in RouterOS nicht mit < / > vergleichen)
  :local all ""
  :foreach f in=[/file/find where name~("^" . $b . "/state/(.*/(export.rsc|audit.txt)|netzplan.md)\$")] do={
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
  :global cfmFileEx; :global cfmMB; :global cfmConf; :global cfmJson; :global cfmInvLoad; :global cfmNow; :global cfmMirT; :global cfmRings
  :global cfmDevUser
  :local now [$cfmNow]
  :if (($now - [:tonum $cfmMirT]) < 300) do={ :return false }
  :set cfmMirT $now
  /system/script/run cfm-conf
  :local b [$cfmMB]
  :local src ("sftp://" . [:pick ($cfmConf->"mgrs") 0] . "/" . ($cfmConf->"path") . "/")
  :local u ($cfmConf->"user")
  # Flag statt :return im :onerror-Block (dort verlässt :return die Funktion nicht)
  :local get do={ :local ok false; :onerror e in={ /tool/fetch url=($s . $r) user=$u dst-path=$l as-value; :set ok true } do={}; :return $ok }
  # erfolgreicher Abruf = Primary erreichbar (Überwachung durch den Backup, $cfmNotifyBackupTick)
  :global cfmMirLast
  :if ([$get s=$src u=$u r="meta/rings.dat" l=($b . "/meta/rings.dat")]) do={ :set cfmMirLast $now }
  :foreach f in={"meta/inventory.rsc";"meta/vault.dat"} do={ $get s=$src u=$u r=$f l=($b . "/" . $f) }
  :local rg [$cfmRings]
  :foreach r in={"r0";"r1";"r2";"latest"} do={
    :local v ($rg->$r)
    :if ([:len [:tostr $v]] > 0 and ![$cfmFileEx ($b . "/archive/v" . $v . "/index.dat")]) do={
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
    # Dateiname aus der Seriennummer: Die System-ID einer CHR kann "/" enthalten (TODO 42)
    :local sfn ""
    :for i from=0 to=([:len ($d->"serial")] - 1) do={ :local c [:pick ($d->"serial") $i]; :if ($c = "/") do={ :set c "_" }; :set sfn ($sfn . $c) }
    $get s=$src u=$u r=("live/m/" . $sfn . ".mf") l=($b . "/live/m/" . $sfn . ".mf")
    # SFTP-User der Geräte (D67), gesperrt bis zur Beförderung: Der Spiegel kann älter sein als der
    # Primary, ein Gerät darf daraus nur nach $cfmPromoteManager ziehen. Nicht für dieses Gerät selbst -
    # sein Agent überspringt die eigenen Adressen, solange der User fehlt (TODO 44)
    :local own ([:len [/ip/address/find where address~("^" . [:tostr ($d->"ip")] . "/")]] > 0)
    :if ([$get s=$src u=$u r=("meta/keys/" . $name . ".pem") l=($b . "/meta/keys/" . $name . ".pem")] and !$own) do={ $cfmDevUser name=$name serial=($d->"serial") dis=yes }
    :foreach f in={"status.dat";"export.rsc";"audit.txt"} do={ $get s=$src u=$u r=("state/" . $name . "/" . $f) l=($b . "/state/" . $name . "/" . $f) }
  }
  # der Spiegel wächst sonst unbegrenzt (gleiche Regel wie auf dem Primary)
  :global cfmArchivePrune; $cfmArchivePrune
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
  # Geräte-User freischalten, den eigenen anlegen (D67): ab hier ziehen die Geräte - und der eigene
  # Agent - bei diesem Manager
  :global cfmDevUsersOn
  :put ("SFTP-User freigeschaltet: " . [$cfmDevUsersOn])
  :put ("Befördert: dieser Manager ist jetzt Primary (work/ = v" . $v . "). Reihenfolge in global.rsc managers anpassen und releasen!")
}

:global cfmTick do={
  :global cfmIsPrimary; :global cfmMirror; :global cfmAutoPromote; :global cfmSecretSync
  :global cfmHookState; :global cfmVaultBackup; :global cfmJson; :global cfmMB; :global cfmVaultGet
  :onerror e in={
    :if ([$cfmIsPrimary]) do={
      # Schrittmarken im Log: bleibt ein Lauf hängen, zeigt die letzte Zeile, wo
      :log info "cfm: tick collect"
      :global cfmCollect; $cfmCollect
      :log info "cfm: tick promote"
      $cfmAutoPromote
      :log info "cfm: tick secrets"
      $cfmSecretSync
      :log info "cfm: tick upgrade"
      :global cfmUpgTick; $cfmUpgTick
      :log info "cfm: tick net"
      :global cfmNetTick; $cfmNetTick
      :log info "cfm: tick hook"
      $cfmHookState
      :log info "cfm: tick notify"
      :global cfmNotifyTick; $cfmNotifyTick
      :local vj [$cfmJson ([$cfmMB] . "/meta/vault.dat")]
      # als String vergleichen: [:tonum nothing] ist nil, und "3 != nil" ist weder wahr noch falsch
      :if ([:tostr ($vj->"ver")] != [:tostr ($vj->"bver")] and [:len [$cfmVaultGet "vaultpw"]] > 0) do={ $cfmVaultBackup }
      :log info "cfm: tick ende"
    } else={
      $cfmMirror
      :global cfmNotifyBackupTick; $cfmNotifyBackupTick
    }
  } do={ :log warning ("cfm: tick: " . $e) }
}

# Eigener, schneller Tick nur fürs Onboarding (Scheduler cfm-mgr-onb-tick, fest 1m): der
# allgemeine Tick (cfm-mgr-tick) ist über global.rsc "mgrTick" konfigurierbar und meist deutlich
# langsamer (Default 10m) - eine laufende Onboarding-Sitzung (DHCP-Warten, Probe, Fail-safe-Timer)
# würde sonst proportional langsamer voranschreiten.
:global cfmOnbTickRun do={
  :global cfmIsPrimary; :global cfmOnbTick
  :onerror e in={ :if ([$cfmIsPrimary]) do={ $cfmOnbTick } } do={ :log warning ("cfm: onb-tick: " . $e) }
}
