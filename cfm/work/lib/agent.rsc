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
#  7. RouterOS-Auftrag im Manifest ("ros", $cfmUpgrade)? -> Pakete vom Manager laden,
#     Neustart sofort oder zum Zeitpunkt at (Scheduler cfm-upgrade)
#  8. Status (JSON) + Export (ohne Secrets) nach cfm/out/ – der Manager holt sie ab
#
# Modus über :global cfmArg (wird vom Aufrufer gesetzt, hier gelöscht):
#   ""  normal | "force" erzwingt Apply (auch "bad") | "wd" Watchdog
#   {"mode"="audit";"op"="report|mark|purge";"sel"="all|A1,A3"}
#   {"mode"="plan"}  Probelauf mit plan/m/<serial>.mf: zeigt Änderungen, wendet nichts an
# ============================================================
:global cfmConf; :global cfmArg; :global cfmMf; :global cfmDl; :global cfmDir

:local arg $cfmArg
:set cfmArg

:global cfmWrite do={
  :if ([:len [/file/find where name=$1]] = 0) do={ /file/add name=$1 contents=$2 } else={ /file/set [/file/find where name=$1] contents=$2 }
}

# SFTP zum Manager (Key-Login als cfmd-<name>). r=Pfad auf dem Manager (relativ zu cfm/, mit
# abs="yes" relativ zur Wurzel), l=lokale Datei, up="yes" = Upload, prefer=zuerst zu
# probierender Manager. Rückgabe: benutzter Manager
# Eigene Adressen überspringen, wenn es den Geräte-User hier nicht gibt: Der Agent eines Backup-Managers
# stünde sonst selbst in der Liste und scheiterte an der Anmeldung (TODO 44). Der Primary hat den User
# und holt seine Dateien weiter per SFTP bei sich selbst.
:global cfmFetch do={
  :global cfmConf
  :local own ({})
  :if ([:len [/user/find where name=($cfmConf->"user")]] = 0) do={
    :foreach i in=[/ip/address/find] do={
      :local a [:tostr [/ip/address/get $i address]]
      :set ($own->[:pick $a 0 [:find $a "/"]]) 1
    }
  }
  :local order ({})
  :if ([:len $prefer] > 0 and [:typeof ($own->$prefer)] = "nothing") do={ :set ($order->0) $prefer }
  :foreach m in=($cfmConf->"mgrs") do={ :if ($m != $prefer and [:typeof ($own->$m)] = "nothing") do={ :set ($order->[:len $order]) $m } }
  :foreach m in=$order do={
    :local ok false
    :local url ("sftp://" . $m . "/" . ($cfmConf->"path") . "/" . $r)
    :if ($abs = "yes") do={ :set url ("sftp://" . $m . "/" . $r) }
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
  # Architektur + installierte Pakete: daraus stellt der Manager RouterOS-Pakete bereit
  :set ($s->"arch") [/system/resource/get architecture-name]
  :local pk ({})
  :onerror e in={
    :foreach i in=[/system/package/find where !disabled and !available] do={ :set ($pk->[:len $pk]) [/system/package/get $i name] }
  } do={ :foreach i in=[/system/package/find] do={ :set ($pk->[:len $pk]) [/system/package/get $i name] } }
  :set ($s->"pkgs") $pk
  # freier Platz für RouterOS-Pakete ($cfmUpgrade, TODO 38). Mit flash/-Verzeichnis liegt die Wurzel
  # (Ablage der Pakete) im RAM, free-hdd-space beschreibt sie dann nicht -> keine Angabe
  :if (!($d ~ "^flash/")) do={ :set ($s->"fs") [/system/resource/get free-hdd-space] }
  # Nachbarn je physischem Port ($cfmLinks): {Port;Identität;Port der Gegenseite;"m"MAC;Plattform}
  # (interface ist bei Bridge-Ports eine Liste "ether2;bridge", interface-name z.B. "bridge/ether3")
  :local nb ({})
  :onerror e in={
    :foreach n in=[/ip/neighbor/find] do={
      :local g [/ip/neighbor/get $n]
      :local iv ($g->"interface")
      :local pt [:tostr $iv]
      :if ([:typeof $iv] = "array") do={ :set pt [:tostr ($iv->0)] }
      :if ([:len [/interface/ethernet/find where name=$pt]] > 0) do={
        :local rp [:tostr ($g->"interface-name")]
        :local sl [:find $rp "/"]
        :if ([:typeof $sl] != "nil") do={ :set rp [:pick $rp ($sl + 1) [:len $rp]] }
        :set ($nb->[:len $nb]) ({$pt;[:tostr ($g->"identity")];$rp;("m" . [:tostr ($g->"mac-address")]);[:tostr ($g->"platform")]})
      }
    }
  } do={}
  :set ($s->"nb") $nb
  # APs: aktueller Kanal je Radio ($cfmChannels), {Radio;"c"Kanal}
  :global cfmMf
  :if (("," . [:tostr ($cfmMf->"role")] . ",") ~ ",ap,") do={
    :local rd ({})
    :onerror e in={
      :foreach i in=[/interface/wifi/find] do={
        :local ch ""
        :onerror e2 in={ :set ch [:tostr ([/interface/wifi/monitor $i once as-value]->"channel")] } do={}
        :set ($rd->[:len $rd]) ({[/interface/wifi/get $i name];("c" . $ch)})
      }
    } do={}
    :set ($s->"radios") $rd
    # Lokaler Fallback (D46): CAP eingeschaltet, aber mit keinem CAPsMAN verbunden -> die Radios senden
    # mit der lokalen Kopie der Master-SSID, weitere SSIDs fehlen ($cfmStatus: "WLAN lokal", TODO 40d)
    :local fb false
    :onerror e in={
      :if ([/interface/wifi/cap/get enabled] and [:len [:tostr [/interface/wifi/cap/get current-caps-man-identity]]] = 0) do={ :set fb true }
    } do={}
    :if ($fb) do={
      :set ($s->"wfb") 1
      :log warning "cfm: WLAN im lokalen Fallback - kein CAPsMAN verbunden"
    }
  }
  # status.json zuerst: legt cfm/out/ an (auf frischen Geräten sonst "invalid file name" beim Export)
  $cfmWrite ($d . "/out/status.json") [:serialize to=json $s]
  :if ($exp = true) do={
    :onerror e in={ /export terse file=($d . "/out/export") } do={ :log warning ("cfm: Export fehlgeschlagen: " . $e) }
  }
  :return true
}

# Manifest prüfen: MAC = sha512(Geräteschlüssel . sha512(Body)). $1=Datei, key= -> Manifest
:global cfmMfRead do={
  :local raw [/file/get $1 contents]
  :local p [:find $raw "\n# mac="]
  :if ([:typeof $p] = "nil") do={ :error "Manifest ohne MAC - verworfen" }
  :local body [:pick $raw 0 $p]
  :local mac [:pick $raw ($p + 7) ($p + 135)]
  :if ([:convert ($key . [:convert $body transform=sha512 to=hex]) transform=sha512 to=hex] != $mac) do={ :error "Manifest-MAC ungültig - verworfen" }
  :return [:deserialize from=json $body]
}

# Dateien eines Manifests (mf=) nach d= laden und per SHA-512 prüfen (mgr= bevorzugt)
:global cfmGetFiles do={
  :global cfmFetch
  :foreach f in=[/file/find where name~("^" . $d . "/") and type!="directory"] do={ /file/remove $f }
  :local src [:tostr ($mf->"src")]
  :if ([:len $src] = 0) do={ :set src ("archive/v" . ($mf->"v")) }
  :foreach fe in=($mf->"files") do={
    :local lp ($d . "/" . ($fe->0))
    # bis zu fünf Versuche: ein Download kann unvollständig gelesen werden; nach einem Fehlschlag
    # wachsend warten (10/20/30/40 s) - solange ein Backup-Manager seinen Spiegel zieht (~1 min),
    # beantwortet der SFTP-Server des Primary keine weiteren Downloads (Labor, TODO 44)
    :local ok false
    :local info ""
    :for t from=1 to=5 do={
      :if (!$ok) do={
        :if ($t > 1) do={ :delay (($t - 1) * 10s) }
        :if ([$cfmFetch r=($src . "/" . ($fe->0)) l=$lp prefer=$mgr] != "") do={
          :delay 300ms
          :local c [/file/get $lp contents]
          :if ([:convert $c transform=sha512 to=hex] = ($fe->1)) do={ :set ok true } else={ :set info ("gelesen " . [:len $c] . " Byte, Versuch " . $t) }
        } else={ :set info ("Download fehlgeschlagen, Versuch " . $t) }
      }
    }
    :if (!$ok) do={ :error ("Hash stimmt nicht: " . ($fe->0) . " (" . $info . ")") }
  }
  :return true
}

# lib + Daten + Host + Rollen aus d= importieren (Reihenfolge laut Manifest mf=), danach
# verwaiste Objekte entfernen. skip="post": *.post.rsc überspringen (Probelauf).
# Die cfm-Objekte, die eine *.post.rsc anlegt, merkt sich der echte Lauf in <cfm>/post.json.
# Der Probelauf behält genau diese, statt sie als verwaist zu melden (D29).
# Rückgabe: "" oder "<datei>: <fehler>"
:global cfmImportAll do={
  :global cfmHost; :set cfmHost ({})
  :global cfmSeen; :global cfmDir; :global cfmWrite; :global cfmLog
  :local pf ($cfmDir . "/post.json")
  :local cur ""
  :local err ""
  :onerror e in={
    :foreach fe in=($mf->"files") do={
      :if (($fe->2) = 1) do={
        :set cur ($fe->0)
        :if ($skip = "post" and $cur ~ "\\.post\\.rsc\$") do={
          :local pk ({})
          :onerror e2 in={ :set pk [:deserialize from=json [/file/get $pf contents]] } do={}
          :local n 0
          :if ([:tostr ($pk->"file")] = $cur) do={
            :foreach m,ks in=($pk->"keys") do={
              :if ([:typeof ($cfmSeen->$m)] = "array") do={
                :foreach k,x in=$ks do={ :set ($cfmSeen->$m->$k) 1; :set n ($n + 1) }
              }
            }
          }
          $cfmLog ("(" . $cur . " im Probelauf übersprungen, " . $n . " Objekte daraus beibehalten)")
        } else={
          :local pre ({})
          :if ($cur ~ "\\.post\\.rsc\$") do={
            :foreach m,ks in=$cfmSeen do={ :foreach k,x in=$ks do={ :set ($pre->($m . "|" . $k)) 1 } }
          }
          /import file-name=($d . "/" . $cur) verbose=no
          :if ($cur = "lib/lib.rsc") do={ :global cfmBegin; $cfmBegin }
          :if ($cur ~ "\\.post\\.rsc\$") do={
            # Schlüssel, die erst diese Datei gesehen hat = ihre Objekte
            :local keys ({})
            :foreach m,ks in=$cfmSeen do={
              :foreach k,x in=$ks do={
                :if ([:typeof ($pre->($m . "|" . $k))] = "nothing") do={
                  :if ([:typeof ($keys->$m)] = "nothing") do={ :set ($keys->$m) ({}) }
                  :set ($keys->$m->$k) 1
                }
              }
            }
            # nur für den Probelauf: ein Schreibfehler darf den Apply nicht zurückrollen
            :onerror e3 in={ $cfmWrite $pf [:serialize to=json ({"file"=$cur;"keys"=$keys})] } do={ $cfmLog ("post.json nicht geschrieben: " . $e3) }
          }
        }
      }
    }
    :set cur "prune"
    :global cfmPrune; $cfmPrune
  } do={ :set err ($cur . ": " . $e) }
  :return $err
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
  :put "cfm: Agent läuft bereits - bitte später erneut"
  :if ([:len [/system/scheduler/find where name="cfm-agent-retry"]] = 0) do={
    :local ev "/system/scheduler/remove [find where name=cfm-agent-retry]; /system script run cfm-agent"
    :if ($arg = "force") do={ :set ev (":global cfmArg \"force\"; " . $ev) }
    /system/scheduler/add name=cfm-agent-retry interval=30s comment="cfm-sys:retry" on-event=$ev
  }
} else={
:onerror err in={
  :global cfmFetch; :global cfmWrite; :global cfmReport; :global cfmMfRead; :global cfmGetFiles
  :global cfmImportAll; :global cfmDry
  # nie im Trockenlauf-Zustand eines abgebrochenen Probelaufs anwenden
  :set cfmDry false

  # --- Identität & Schlüssel ---
  :local serial ""
  :onerror e in={ :set serial [/system routerboard get serial-number] } do={}
  :if ([:len $serial] = 0) do={ :onerror e in={ :set serial [/system/license/get system-id] } do={} }
  :if ([:len $serial] = 0) do={ :onerror e in={ :set serial [/system/license/get software-id] } do={} }
  # Dateiname des Manifests: "/" (System-ID einer CHR) wie am Manager durch "_" ersetzt (TODO 42)
  :local sfn ""
  :for i from=0 to=([:len $serial] - 1) do={ :local c [:pick $serial $i]; :if ($c = "/") do={ :set c "_" }; :set sfn ($sfn . $c) }
  :local key ""
  :local sv ""
  :onerror e in={
    :local kid [/ppp/secret/find where name="cfm:key"]
    :set key [/ppp/secret/get $kid password]
    :set sv [/ppp/secret/get $kid comment]
  } do={ :error "kein Geräteschlüssel cfm:key – Gerät ist nicht enrolled (\$cfmEnroll am Manager)" }
  :local st ({})
  :onerror e in={ :set st [:deserialize from=json [/file/get ($dir . "/state.json") contents]] } do={}

  :if ([:typeof $arg] = "array") do={
    # --- Audit-Modus (vom Manager per $cfmAudit ausgelöst) ---
    :if (($arg->"mode") = "audit") do={
      /import file-name=($cfmDl . "/lib/lib.rsc") verbose=no
      :global cfmAuditDev
      :local rep [$cfmAuditDev op=($arg->"op") sel=($arg->"sel")]
      $cfmWrite ($dir . "/out/audit.txt") $rep
      :put $rep
      :error "cfm-done"
    }
    # --- Probelauf (vom Manager per $cfmPlan ausgelöst): nichts anwenden, nur berichten ---
    :if (($arg->"mode") = "plan") do={
      :local pmgr [$cfmFetch r=("plan/m/" . $sfn . ".mf") l=($dir . "/plan.mf") prefer=($st->"mgr")]
      :if ($pmgr = "") do={ :error "Plan-Manifest nicht abrufbar" }
      :local pm [$cfmMfRead ($dir . "/plan.mf") key=$key]
      :local pd ($dir . "/pl")
      $cfmGetFiles mf=$pm d=$pd mgr=$pmgr
      :local dl0 $cfmDl
      :set cfmDl $pd
      :set cfmMf $pm
      :global cfmPlanOut; :set cfmPlanOut ""
      :set cfmDry true
      :local perr [$cfmImportAll mf=$pm d=$pd skip="post"]
      :set cfmDry false
      :set cfmDl $dl0
      :global cfmStat
      :local rep ("# id=" . [:tostr ($arg->"id")] . "\n" . $cfmPlanOut . "# Plan " . ($pm->"name") . " (Stand work/): " . [:tostr $cfmStat] . "\n")
      :if ([:len $perr] > 0) do={ :set rep ($rep . "# FEHLER im Probelauf (ein Apply würde zurückrollen): " . $perr . "\n") }
      $cfmWrite ($dir . "/out/plan.txt") $rep
      :put $rep
      :error "cfm-done"
    }
  }

  # --- Manifest holen ---
  :local mgr [$cfmFetch r=("live/m/" . $sfn . ".mf") l=($dir . "/mf.mf") prefer=($st->"mgr")]
  # RouterOS-Eigenheit (7.24, im CHR-Labor): Nach einem Neustart – besonders nach /system backup
  # load (Rollback) – nimmt die Bridge getaggte Frames ihrer Ports u.U. erst wieder an, wenn die
  # Ports neu starten. Findet der Boot-Lauf keinen Manager, die Ethernet-Ports der Bridge einmal
  # aus- und einschalten, erneut versuchen.
  :if ($mgr = "" and $arg = "boot") do={
    :log warning "cfm: nach dem Neustart kein Manager erreichbar - Bridge-Ports werden neu gestartet"
    :local bp ({})
    :foreach p in=[/interface/bridge/port/find where !disabled] do={
      :local ifn [/interface/bridge/port/get $p interface]
      :if ([:len [/interface/ethernet/find where name=$ifn and !disabled]] > 0) do={ :set ($bp->[:len $bp]) $ifn }
    }
    :foreach ifn in=$bp do={ /interface/ethernet/disable [find where name=$ifn] }
    :delay 2s
    :foreach ifn in=$bp do={ /interface/ethernet/enable [find where name=$ifn] }
    :delay 15s
    :set mgr [$cfmFetch r=("live/m/" . $sfn . ".mf") l=($dir . "/mf.mf") prefer=($st->"mgr")]
    :if ($mgr != "") do={ :log warning "cfm: Manager nach dem Neustart der Bridge-Ports wieder erreichbar" }
  }

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
  :if ($mgr = "") do={
    # Von Hand aus einer Admin-Sitzung gestartet (TODO 35): /tool/fetch nimmt den privaten Schlüssel
    # des aufrufenden Users, den nur cfm hat
    :local ow ""
    :onerror e in={
      :foreach j in=[/system/script/job/find where script="cfm-agent"] do={
        :local o [:tostr [/system/script/job/get $j owner]]
        :if ([:len $o] > 0 and $o != "cfm") do={ :set ow $o }
      }
    } do={}
    :if ([:len $ow] > 0) do={
      # :put für das Terminal, aus dem der Agent gestartet wurde; der Fehler selbst landet im Log
      :local m ("kein Manager erreichbar - der Agent läuft als " . $ow . ", der SFTP-Schlüssel gehört cfm: am Manager \$cfmPush host=" . [/system/identity/get name] . " verwenden")
      :put $m
      :error $m
    }
    :error "kein Manager erreichbar"
  }
  :set ($st->"mgr") $mgr

  # --- Manifest prüfen ---
  :local mf [$cfmMfRead ($dir . "/mf.mf") key=$key]
  :set cfmMf $mf
  :local v ($mf->"v")
  # Hash ohne RouterOS-Auftrag: ein neuer oder erledigter Auftrag löst keinen Apply aus
  :local m2 ({})
  :foreach k,x in=$mf do={ :if ($k != "ros") do={ :set ($m2->$k) $x } }
  :local mfh [:convert [:serialize to=json $m2] transform=md5 to=hex]
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
    $cfmGetFiles mf=$mf d=$cfmDl mgr=$mgr
    # Sicherung + Watchdog
    /system/backup/save name=($dir . "/pre") password=$key encryption=aes-sha256
    :set ($st->"pending") $v
    $cfmWrite ($dir . "/state.json") [:serialize to=json $st]
    /system/scheduler/remove [find where name="cfm-watchdog"]
    /system/scheduler/add name="cfm-watchdog" interval=($mf->"watchdog") comment="cfm-sys:watchdog" on-event=":global cfmArg \"wd\"; /system script run cfm-agent"
    # Anwenden
    :local aerr [$cfmImportAll mf=$mf d=$cfmDl]
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
    :if ([$cfmFetch r=("live/m/" . $sfn . ".mf") l=($dir . "/mf2.mf") prefer=$mgr] != "") do={
      :set ($st->"pending")
      /system/scheduler/remove [find where name="cfm-watchdog"]
    }
    :log info ("cfm: v" . $v . " angewendet " . [:tostr $cfmStat])
  }

  # --- RouterOS-Auftrag ($cfmUpgrade am Manager) ---
  :local boot ""
  :local ro ($mf->"ros")
  :local cur [/system/resource/get version]
  :set cur [:pick $cur 0 [:find ($cur . " ") " "]]
  :local upn [/system/scheduler/find where name="cfm-upgrade"]
  # Werte tragen ein Präfix (v…, @…, i…): :deserialize macht sonst aus "7.24.1" eine
  # IP-Adresse (7.24.0.1) und aus "2026-10-01 02:00" einen Zeitwert
  :local tv ""
  :if ([:typeof $ro] = "array") do={ :set tv [:pick [:tostr ($ro->"rv")] 1 99] }
  :if ([:len $tv] > 0 and $tv != $cur) do={
    :local tag ("cfm-sys:upgrade " . $tv . " " . [:tostr ($ro->"id")])
    :local planned false
    :if ([:len $upn] > 0) do={ :if ([/system/scheduler/get $upn comment] = $tag) do={ :set planned true } }
    :if (!$planned) do={
      :if (($st->"upa") = $tag) do={
        # Auftrag schon ausgeführt (Neustart oder Fenster verpasst), Gerät trotzdem nicht auf der
        # Zielversion: nicht endlos wiederholen, der Admin erteilt bei Bedarf einen neuen Auftrag
        :if (!([:tostr ($st->"upg")] ~ "^(fehlgeschlagen|Fenster|Platz)")) do={
          :log error ("cfm: RouterOS " . $tv . " nicht installiert - Auftrag fehlgeschlagen")
          :set ($st->"upg") ("fehlgeschlagen " . $tv)
        }
        :foreach fn in=($st->"upf") do={ :onerror e in={ /file/remove [find where name=$fn] } do={} }
      } else={
       # Platz vorab prüfen (TODO 38): Ein voller Flash lässt auch Config und Log scheitern. Der Manager
       # prüft beim Auftrag schon den gemeldeten Wert; 1 MB Reserve wie dort. Kein neuer Versuch - nach
       # dem Aufräumen einen neuen Auftrag erteilen.
       :local need 1048576
       :foreach pf in=($ro->"files") do={ :set need ($need + [:tonum ($pf->1)]) }
       :local free [/system/resource/get free-hdd-space]
       :if (!($dir ~ "^flash/") and $free < $need) do={
        :set ($st->"upa") $tag
        :set ($st->"upf") ({})
        :set ($st->"upg") ("Platz fehlt: " . ($free / 1024) . " KB frei, " . ($need / 1024) . " KB nötig")
        :log error ("cfm: RouterOS " . $tv . ": zu wenig Platz (" . ($free / 1024) . " KB frei, " . ($need / 1024) . " KB nötig) - nichts geladen")
       } else={
        # Pakete in die Wurzel laden: dort installiert RouterOS sie beim nächsten Start
        :local fl ({})
        :foreach pf in=($ro->"files") do={
          :local fn ($pf->0)
          :if ([$cfmFetch r=(($ro->"path") . "/" . $fn) l=$fn prefer=$mgr abs="yes"] = "") do={ :error ("Paket-Download fehlgeschlagen: " . $fn) }
          :delay 1s
          :if ([/file/get [find where name=$fn] size] != [:tonum ($pf->1)]) do={ :error ("Paketgröße stimmt nicht: " . $fn) }
          :set ($fl->[:len $fl]) $fn
        }
        :set ($st->"upf") $fl
        :set ($st->"upa") $tag
        :local act "/system/reboot"
        :if (($ro->"how") = "downgrade") do={ :set act "/system/package/downgrade" }
        :if ([:len $upn] > 0) do={ /system/scheduler/remove $upn }
        :local at [:tostr ($ro->"at")]
        :if ([:pick $at 0 1] = "@") do={ :set at [:pick $at 1 99] } else={ :set at "" }
        :if ([:len $at] > 0) do={
          # Zeitpunkte als Zahl JJJJMMTTHHMM vergleichen (Strings kennen kein < / >)
          :local nw ([/system/clock/get date] . " " . [:pick [/system/clock/get time] 0 5])
          :local an [:tonum ([:pick $at 0 4] . [:pick $at 5 7] . [:pick $at 8 10] . [:pick $at 11 13] . [:pick $at 14 16])]
          :local nn [:tonum ([:pick $nw 0 4] . [:pick $nw 5 7] . [:pick $nw 8 10] . [:pick $nw 11 13] . [:pick $nw 14 16])]
          :if ($an <= $nn) do={
            # Fenster schon vorbei (Gerät war offline oder der Download dauerte zu lange):
            # nicht außerhalb des Fensters neu starten, Pakete verwerfen
            :foreach fn in=$fl do={ :onerror e in={ /file/remove [find where name=$fn] } do={} }
            :set ($st->"upg") ("Fenster verpasst " . $at . ", neuen Auftrag erteilen")
            :log warning ("cfm: RouterOS " . $tv . ": Wartungsfenster " . $at . " verpasst")
          } else={
            /system/scheduler/add name=cfm-upgrade start-date=[:pick $at 0 10] start-time=([:pick $at 11 16] . ":00") interval=0 comment=$tag on-event=("/system/scheduler/remove [find where name=cfm-upgrade]; " . $act)
            :set ($st->"upg") ("geplant " . $tv . " am " . $at)
            :log warning ("cfm: RouterOS " . $tv . " geplant für " . $at)
          }
        } else={
          :set ($st->"upg") ("Neustart für " . $tv)
          :set boot $act
        }
       }
      }
    }
  } else={
    # kein offener Auftrag (mehr): geplanten Neustart und geladene Pakete verwerfen
    :if ([:len $upn] > 0) do={ /system/scheduler/remove $upn; :log info "cfm: geplantes RouterOS-Update verworfen" }
    :foreach fn in=($st->"upf") do={ :onerror e in={ /file/remove [find where name=$fn] } do={} }
    :set ($st->"upf"); :set ($st->"upa"); :set ($st->"upg")
  }

  # --- RouterBOARD-Firmware: Nach einem RouterOS-Update passt "current-firmware" nicht mehr zu
  #     "upgrade-firmware"; eine geflashte Firmware wird erst nach einem WEITEREN Neustart aktiv
  #     (RouterOS-Eigenheit). Nur prüfen, wenn nicht schon ein Neustart ansteht (oben).
  :if ([:len $boot] = 0) do={
    :local rbCur ""; :local rbUpg ""
    # /system/routerboard fehlt auf Geräten ohne RouterBOARD (CHR/x86) komplett - in fester
    # Slash-Schreibweise wäre das schon ein Parse-Fehler, den :onerror nicht abfängt. Deshalb per
    # :parse zur Laufzeit auflösen (wie $cfmRun es für alle dynamischen Menüs tut).
    :onerror e in={
      :local fc [:parse ":return [/system/routerboard/get current-firmware]"]
      :set rbCur [$fc]
      :local fu [:parse ":return [/system/routerboard/get upgrade-firmware]"]
      :set rbUpg [$fu]
    } do={}
    # auto-upgrade flasht nur beim Neustart direkt nach einem RouterOS-Update. Lief das Update vor
    # dem ersten Apply (Onboarding), flasht nie etwas, und ein bloßer Neustart dreht sich im Kreis
    # (hAP ax², 2026-09-23: Neustart alle 1-2 min). Deshalb selbst flashen und je Firmware-Version
    # höchstens einmal neu starten; "fw" merkt sich die Version über den Neustart hinweg.
    :if ([:len $rbUpg] > 0 and $rbUpg != $rbCur) do={
      :if ([:tostr ($st->"fw")] = $rbUpg) do={
        :if ([:tostr ($st->"fwe")] != $rbUpg) do={
          :log error ("cfm: RouterBOARD-Firmware " . $rbUpg . " nach dem Neustart nicht aktiv (aktuell " . $rbCur . ") - kein weiterer Neustart, /system/routerboard/upgrade von Hand")
          :set ($st->"fwe") $rbUpg
        }
      } else={
        :onerror e in={
          :local fx [:parse "/system/routerboard/upgrade"]
          $fx
          :delay 10s
        } do={ :log error ("cfm: RouterBOARD-Firmware " . $rbUpg . " flashen fehlgeschlagen: " . $e) }
        :set ($st->"fw") $rbUpg
        :log warning ("cfm: RouterBOARD-Firmware " . $rbUpg . " geflasht (aktuell " . $rbCur . ") - Neustart zum Aktivieren")
        :set boot "/system/reboot"
      }
    } else={ :set ($st->"fw"); :set ($st->"fwe") }
  }

  # --- Bericht ---
  # Vault-Stand neu lesen: Eine Rolle kann beim Apply einen Secret-Push anfordern (sv=0, z.B. neue
  # WLAN-Profile ohne Passphrase, D46) – so sieht der Manager das schon beim nächsten Collect
  :onerror e in={ :set sv [/ppp/secret/get [find where name="cfm:key"] comment] } do={}
  :local exp ($applied or ($now - [:tonum ($st->"et")]) > 86400)
  :if ($exp) do={ :set ($st->"et") $now }
  $cfmWrite ($dir . "/state.json") [:serialize to=json $st]
  $cfmReport st=$st serial=$serial target=$v sv=$sv now=$now exp=$exp
  :if ([:len $boot] > 0) do={
    :log warning ("cfm: Neustart für RouterOS-Update (" . $boot . ")")
    :delay 2s
    :execute $boot
  }
} do={ :if (!($err ~ "^cfm-done")) do={ :log error ("cfm: " . $err) } }
}
