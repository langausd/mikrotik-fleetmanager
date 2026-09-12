# ============================================================
# cfm lib/agent.rsc – Geräte-Agent (installiert als Skript "cfm-agent")
# Läuft beim Boot, alle <interval> und per Push-Trigger vom Manager.
#
#  1. Manifest live/m/<serial>.mf vom ersten erreichbaren Manager holen
#  2. MAC mit Geräteschlüssel (cfm:key) prüfen – sonst verwerfen
#  3. Neu/geändert (oder Reapply fällig)? -> Dateien laden, SHA-512 prüfen
#  4. /system backup save, Watchdog scharf schalten
#  5. lib + Daten + Host + Rollen importieren, verwaiste Objekte entfernen
#     Fehler -> Version als "bad" merken, Rollback per /system backup load
#  6. Erreichbarkeit bestätigen -> Watchdog aus; sonst Rollback nach Timeout
#  7. Status (JSON) + Export (ohne Secrets) nach cfm/out/ – der Manager holt sie ab
#
# Modus über :global cfmArg (wird vom Aufrufer gesetzt, hier gelöscht):
#   ""  normal | "force" erzwingt Apply (auch "bad") | "wd" Watchdog
#   {"mode"="audit";"op"="report|mark|purge";"sel"="all|A1,A3"}
# ============================================================
:global cfmConf; :global cfmArg; :global cfmMf; :global cfmDl; :global cfmDir

:local arg $cfmArg
:set cfmArg

:global cfmWrite do={
  :if ([:len [/file/find where name=$1]] = 0) do={ /file/add name=$1 contents=$2 } else={ /file/set [/file/find where name=$1] contents=$2 }
}

# SFTP zum Manager (Key-Login als cfmd-<name>). r=Pfad auf dem Manager, l=lokale Datei,
# up="yes" = Upload, prefer=zuerst zu probierender Manager. Rückgabe: benutzter Manager
:global cfmFetch do={
  :global cfmConf
  :local order ({})
  :if ([:len $prefer] > 0) do={ :set ($order->0) $prefer }
  :foreach m in=($cfmConf->"mgrs") do={ :if ($m != $prefer) do={ :set ($order->[:len $order]) $m } }
  :foreach m in=$order do={
    :local ok false
    :local url ("sftp://" . $m . "/" . ($cfmConf->"path") . "/" . $r)
    :onerror e in={
      :if ($up = "yes") do={
        /tool/fetch url=$url user=($cfmConf->"user") src-path=$l upload=yes as-value
      } else={
        /tool/fetch url=$url user=($cfmConf->"user") dst-path=$l as-value
      }
      :set ok true
    } do={}
    :if ($ok) do={ :return $m }
  }
  :return ""
}

# Status + (optional) Export lokal ablegen (cfm/out/). Der Manager holt beides per
# SFTP ab ($cfmCollect) – Geräte haben am Manager bewusst nur Lesezugriff.
:global cfmReport do={
  :global cfmWrite; :global cfmDir
  :local d $cfmDir
  :local s $st
  :set ($s->"serial") $serial
  :set ($s->"target") $target
  :set ($s->"sv") $sv
  :set ($s->"ros") [/system/resource/get version]
  :set ($s->"model") [/system/resource/get board-name]
  :set ($s->"seen") $now
  # status.json zuerst: legt cfm/out/ an (auf frischen Geräten sonst "invalid file name" beim Export)
  $cfmWrite ($d . "/out/status.json") [:serialize to=json $s]
  :if ($exp = true) do={
    :onerror e in={ /export terse file=($d . "/out/export") } do={ :log warning ("cfm: Export fehlgeschlagen: " . $e) }
  }
  :return true
}

/system/script/run cfm-conf
:local dir "cfm"
:if ([:len [/file/find where name="flash" and type="directory"]] > 0) do={ :set dir "flash/cfm" }
:set cfmDir $dir
:set cfmDl ($dir . "/dl")
:local now ([:tonsec [:timestamp]] / 1000000000)

# Nur ein Lauf gleichzeitig, geprüft über die Job-Liste: gilt unabhängig davon, aus welcher
# Sitzung (Scheduler, Push per SSH) der Lauf kam. Ein übersprungener Lauf, z.B. ein Push
# während eines Applys, wird nach 30 s nachgeholt; ein erzwungener bleibt dabei erzwungen.
:if ([:len [/system/script/job/find where script="cfm-agent"]] > 1 and $arg != "wd") do={
  :log info "cfm: Agent läuft bereits – neuer Versuch in 30 s"
  :if ([:len [/system/scheduler/find where name="cfm-agent-retry"]] = 0) do={
    :local ev "/system/scheduler/remove [find where name=cfm-agent-retry]; /system script run cfm-agent"
    :if ($arg = "force") do={ :set ev (":global cfmArg \"force\"; " . $ev) }
    /system/scheduler/add name=cfm-agent-retry interval=30s comment="cfm-sys:retry" on-event=$ev
  }
} else={
:onerror err in={
  :global cfmFetch; :global cfmWrite; :global cfmReport

  # --- Identität & Schlüssel ---
  :local serial ""
  :onerror e in={ :set serial [/system routerboard get serial-number] } do={}
  :if ([:len $serial] = 0) do={ :onerror e in={ :set serial [/system/license/get system-id] } do={} }
  :if ([:len $serial] = 0) do={ :onerror e in={ :set serial [/system/license/get software-id] } do={} }
  :local key ""
  :local sv ""
  :onerror e in={
    :local kid [/ppp/secret/find where name="cfm:key"]
    :set key [/ppp/secret/get $kid password]
    :set sv [/ppp/secret/get $kid comment]
  } do={ :error "kein Geräteschlüssel cfm:key – Gerät ist nicht enrolled (\$cfmEnroll am Manager)" }
  :local st ({})
  :onerror e in={ :set st [:deserialize from=json [/file/get ($dir . "/state.json") contents]] } do={}

  # --- Audit-Modus (vom Manager per $cfmAudit ausgelöst) ---
  :if ([:typeof $arg] = "array") do={
    :if (($arg->"mode") = "audit") do={
      /import file-name=($cfmDl . "/lib/lib.rsc") verbose=no
      :global cfmAudit
      :local rep [$cfmAudit op=($arg->"op") sel=($arg->"sel")]
      $cfmWrite ($dir . "/out/audit.txt") $rep
      :put $rep
      :error "cfm-done"
    }
  }

  # --- Manifest holen ---
  :local mgr [$cfmFetch r=("live/m/" . $serial . ".mf") l=($dir . "/mf.mf") prefer=($st->"mgr")]

  # --- Watchdog-Lauf: Apply bestätigen oder zurückrollen ---
  :if ($arg = "wd") do={
    /system/scheduler/remove [find where name="cfm-watchdog"]
    :if ([:len [:tostr ($st->"pending")]] > 0) do={
      :if ($mgr != "") do={
        :log info ("cfm: Watchdog – Manager erreichbar, v" . ($st->"pending") . " bestätigt")
        :set ($st->"pending")
        $cfmWrite ($dir . "/state.json") [:serialize to=json $st]
      } else={
        :log error ("cfm: Watchdog – kein Manager erreichbar nach Apply v" . ($st->"pending") . " -> Rollback")
        :set ($st->"bad") ($st->"pending")
        :set ($st->"pending")
        :set ($st->"res") "rollback-watchdog"
        $cfmWrite ($dir . "/state.json") [:serialize to=json $st]
        :delay 2s
        /system/backup/load name=($dir . "/pre.backup") password=$key
      }
    }
    :error "cfm-done"
  }
  :if ($mgr = "") do={ :error "kein Manager erreichbar" }
  :set ($st->"mgr") $mgr

  # --- Manifest prüfen ---
  :local raw [/file/get ($dir . "/mf.mf") contents]
  :local p [:find $raw "\n# mac="]
  :if ([:typeof $p] = "nil") do={ :error "Manifest ohne MAC – verworfen" }
  :local body [:pick $raw 0 $p]
  :local mac [:pick $raw ($p + 7) ($p + 135)]
  :if ([:convert ($key . [:convert $body transform=sha512 to=hex]) transform=sha512 to=hex] != $mac) do={ :error "Manifest-MAC ungültig – verworfen" }
  :local mf [:deserialize from=json $body]
  :set cfmMf $mf
  :local v ($mf->"v")
  :local mfh [:convert $body transform=md5 to=hex]
  :set ($st->"name") ($mf->"name")
  :set ($st->"ring") ($mf->"ring")
  :set ($st->"role") ($mf->"role")

  :local need (($st->"mfh") != $mfh)
  :if (!$need and ($now - [:tonum ($st->"t")]) > [:tonum ($mf->"reapply")]) do={ :set need true }
  :if ($arg = "force") do={ :set need true }
  :if ($need and ($st->"bad") = $v and $arg != "force") do={
    :set need false
    :log warning ("cfm: v" . $v . " ist als fehlerhaft markiert – übersprungen (force am Manager: \$cfmPush host=" . ($mf->"name") . " force=yes)")
  }

  :local applied false
  :if ($need) do={
    :log info ("cfm: wende v" . $v . " an (Rollen: base," . ($mf->"role") . ")")
    # Dateien laden + prüfen
    :foreach f in=[/file/find where name~("^" . $cfmDl . "/") and type!="directory"] do={ /file/remove $f }
    :foreach fe in=($mf->"files") do={
      :local lp ($cfmDl . "/" . ($fe->0))
      :if ([$cfmFetch r=("archive/v" . $v . "/" . ($fe->0)) l=$lp prefer=$mgr] = "") do={ :error ("Download fehlgeschlagen: " . ($fe->0)) }
      :if ([:convert [/file/get $lp contents] transform=sha512 to=hex] != ($fe->1)) do={ :error ("Hash stimmt nicht: " . ($fe->0)) }
    }
    # Sicherung + Watchdog
    /system/backup/save name=($dir . "/pre") password=$key encryption=aes-sha256
    :set ($st->"pending") $v
    $cfmWrite ($dir . "/state.json") [:serialize to=json $st]
    /system/scheduler/remove [find where name="cfm-watchdog"]
    /system/scheduler/add name="cfm-watchdog" interval=($mf->"watchdog") comment="cfm-sys:watchdog" on-event=":global cfmArg \"wd\"; /system script run cfm-agent"
    # Anwenden
    :global cfmHost; :set cfmHost ({})
    :local cur ""
    :local aerr ""
    :onerror e in={
      :foreach fe in=($mf->"files") do={
        :if (($fe->2) = 1) do={
          :set cur ($fe->0)
          /import file-name=($cfmDl . "/" . ($fe->0)) verbose=no
          :if (($fe->0) = "lib/lib.rsc") do={ :global cfmBegin; $cfmBegin }
        }
      }
      :set cur "prune"
      :global cfmPrune; $cfmPrune
    } do={ :set aerr ($cur . ": " . $e) }
    :if ([:len $aerr] > 0) do={
      :log error ("cfm: Apply v" . $v . " fehlgeschlagen (" . $aerr . ") -> Rollback")
      :set ($st->"bad") $v
      :set ($st->"pending")
      :set ($st->"res") ("failed " . $aerr)
      $cfmWrite ($dir . "/state.json") [:serialize to=json $st]
      $cfmReport st=$st serial=$serial target=$v sv=$sv now=$now exp=false
      /system/scheduler/remove [find where name="cfm-watchdog"]
      :delay 2s
      /system/backup/load name=($dir . "/pre.backup") password=$key
      :error "cfm-done"
    }
    :global cfmStat
    :set ($st->"v") $v
    :set ($st->"mfh") $mfh
    :set ($st->"t") $now
    :set ($st->"res") "ok"
    :set ($st->"stats") $cfmStat
    # effektiver adminUser-Wert (inkl. Hostfile-Ausnahme), danach richtet sich der Secret-Push
    :global cfmAU
    :set ($st->"au") [:tostr $cfmAU]
    :set applied true
    # Erreichbarkeit direkt bestätigen (sonst entscheidet der Watchdog)
    :if ([$cfmFetch r=("live/m/" . $serial . ".mf") l=($dir . "/mf2.mf") prefer=$mgr] != "") do={
      :set ($st->"pending")
      /system/scheduler/remove [find where name="cfm-watchdog"]
    }
    :log info ("cfm: v" . $v . " angewendet " . [:tostr $cfmStat])
  }

  # --- Bericht ---
  :local exp ($applied or ($now - [:tonum ($st->"et")]) > 86400)
  :if ($exp) do={ :set ($st->"et") $now }
  $cfmWrite ($dir . "/state.json") [:serialize to=json $st]
  $cfmReport st=$st serial=$serial target=$v sv=$sv now=$now exp=$exp
} do={ :if ($err != "cfm-done") do={ :log error ("cfm: " . $err) } }
}
