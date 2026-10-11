# ============================================================
# cfm lib/mgr-notify.rsc – Manager-Funktionen: Benachrichtigungen (D66)
#   $cfmNotify ev=<art> host=<n> st=on|off|once msg=<text>   eine Meldung per HTTP-POST (JSON)
#   $cfmNotify test=yes                                       Probemeldung an notify.url
#   $cfmNotifyTick                                            Zustände prüfen, Wechsel melden
#                                                             (aus $cfmTick, nur auf dem Primary)
#   (Übersicht aller Befehle: lib/mgr-core.rsc)
# Ziel: global.rsc "notify"={"url"=…;"stale"="30m";"licWarn"="14d"}, url leer = aus.
# Der Body ist JSON: {"site","host","ev","state","msg","text","time"} - z.B. für einen
# Webhook-Trigger von Home Assistant (docs/home-assistant.md), ntfy o.ä. mit derselben URL-Form.
# Dazu level/device/message für einen einfachen Empfänger: level error (apply, onboard, stumm), warning
# (wlan, "wieder ok"), action (update, lizenz, ros = Admin-Eingriff nötig), info (Probe); device = das
# betroffene Gerät, message = text. Neue RouterOS-Version (ros): einmal am Tag NEWESTa7.<rosChannel>
# bei upgrade.mikrotik.com, je neuer Version eine Meldung, solange ein aufgenommenes Gerät älter ist.
# Gemeldet wird nur ein Wechsel: einmal beim Eintreten ("on"), einmal bei "wieder ok" ("off"),
# gemerkt in meta/notify.dat. Scheitert die Zustellung, bleibt der Zustand offen und der nächste
# Tick versucht es erneut (pro Tick nach dem ersten Fehler keine weiteren Versuche).
# ============================================================

# JSON-String selbst bauen: Umlaute bleiben UTF-8 (nur " \ und Steuerzeichen werden maskiert)
:global cfmJStr do={
  :local s [:tostr $1]
  :local o ""
  :for i from=0 to=([:len $s] - 1) do={
    :local ch [:pick $s $i]
    :if ($ch = "\"" or $ch = "\\") do={ :set ch ("\\" . $ch) }
    :if ($ch = "\n") do={ :set ch "\\n" }
    :if ($ch = "\r") do={ :set ch "" }
    :if ($ch = "\t") do={ :set ch " " }
    :set o ($o . $ch)
  }
  :return ("\"" . $o . "\"")
}

:global cfmNotify do={
  :global cfmG; :global cfmLoadData; :global cfmJStr
  :if ([:typeof $cfmG] != "array") do={ $cfmLoadData }
  :local nc ($cfmG->"notify")
  :local u [:tostr ($nc->"url")]
  :if ([:len $u] = 0) do={
    :if ($test = "yes") do={ :put "notify.url ist leer - Benachrichtigungen aus" }
    :return false
  }
  :local e [:tostr $ev]; :local s [:tostr $st]; :local m [:tostr $msg]; :local h [:tostr $host]
  :if ($test = "yes") do={ :set e "test"; :set s "once"; :set m "Probemeldung von cfm" }
  :if ([:len $s] = 0) do={ :set s "once" }
  :local site [:tostr ($nc->"site")]
  :if ([:len $site] = 0) do={ :set site [/system/identity/get name] }
  :local t ($site . ": ")
  :if ([:len $h] > 0) do={ :set t ($t . $h . " - ") }
  :set t ($t . $m)
  :local tm ([/system/clock/get date] . " " . [/system/clock/get time])
  :local lv "warning"
  :if ($e ~ "^(apply|onboard|stumm)\$") do={ :set lv "error" }
  :if ($e ~ "^(update|lizenz|ros)\$") do={ :set lv "action" }
  :if ($s = "off") do={ :set lv "warning" }
  :if ($e = "test") do={ :set lv "info" }
  :local dv $h
  :if ([:len $dv] = 0) do={ :set dv [/system/identity/get name] }
  :local j ("{\"site\":" . [$cfmJStr $site] . ",\"host\":" . [$cfmJStr $h] . ",\"ev\":" . [$cfmJStr $e] . ",\"state\":" . [$cfmJStr $s] . ",\"msg\":" . [$cfmJStr $m] . ",\"text\":" . [$cfmJStr $t] . ",\"time\":" . [$cfmJStr $tm] . ",\"level\":" . [$cfmJStr $lv] . ",\"device\":" . [$cfmJStr $dv] . ",\"message\":" . [$cfmJStr $t] . "}")
  :local ok false
  :onerror x in={
    /tool/fetch url=$u http-method=post http-header-field="Content-Type: application/json" http-data=$j output=none as-value
    :set ok true
  } do={ :log warning ("cfm: Meldung nicht zugestellt (" . $e . " " . $h . "): " . $x) }
  :if ($ok) do={ :log info ("cfm: Meldung " . $e . "/" . $s . " " . $h . ": " . [:pick $m 0 120]) }
  :if ($test = "yes") do={ :if ($ok) do={ :put ("zugestellt an " . $u) } else={ :put ("nicht zugestellt an " . $u . " (Log)") } }
  :return $ok
}

# "YYYY-MM-DD[ …]" -> Tage seit 1970-01-01, -1 wenn unlesbar (Datumsformat ab RouterOS 7.10)
:global cfmDays do={
  :local s [:tostr $1]
  :if (!($s ~ "^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]")) do={ :return -1 }
  # führende Null selbst entfernen (":tonum" mit führender Null nicht verlassen)
  :local n2 do={ :local x [:pick $1 0 2]; :if ([:pick $x 0] = "0") do={ :set x [:pick $x 1] }; :return [:tonum $x] }
  :local y [:tonum [:pick $s 0 4]]
  :local m [$n2 [:pick $s 5 7]]
  :local d [$n2 [:pick $s 8 10]]
  :if ($m <= 2) do={ :set y ($y - 1) }
  :local era ($y / 400)
  :local yoe ($y - $era * 400)
  :local mp ($m + 9)
  :if ($m > 2) do={ :set mp ($m - 3) }
  :local doy ((153 * $mp + 2) / 5 + $d - 1)
  :local doe ($yoe * 365 + $yoe / 4 - $yoe / 100 + $doy)
  :return ($era * 146097 + $doe - 719468)
}

# CHR-Lizenz: now= renew= (next-renewal-at) deadline= (deadline-at) warn=<Tage> -> Meldung oder ""
# Überfällig heißt: next-renewal-at liegt mindestens einen Tag zurück (die Erneuerung scheiterte).
:global cfmNotifyLic do={
  :global cfmDays
  :local today [$cfmDays $now]
  :local r ""
  :local rn [:tostr $renew]
  :if ([:len $rn] > 0) do={
    :local rd [$cfmDays $rn]
    :if ($rd < 0) do={ :set r ("CHR-Lizenz: next-renewal-at unlesbar (" . $rn . ")") } else={
      :if ($rd < $today) do={ :set r ("CHR-Lizenz: Erneuerung überfällig seit " . [:pick $rn 0 10] . " (Weg zu licence.mikrotik.com prüfen)") }
    }
  }
  :local dl [:tostr $deadline]
  :if ([:len $dl] > 0) do={
    :local dd [$cfmDays $dl]
    :if ($dd >= 0 and ($dd - $today) <= [:tonum $warn]) do={
      :if ([:len $r] > 0) do={ :set r ($r . "; ") }
      :set r ($r . "CHR-Lizenz läuft am " . [:pick $dl 0 10] . " ab (in " . ($dd - $today) . " Tagen)")
    }
  }
  :return $r
}

# neueste RouterOS-Version im Kanal (global.rsc rosChannel) bei MikroTik, "" wenn nicht erreichbar.
# Labor: :global cfmRosFake "<version>" ersetzt die Abfrage
:global cfmRosLatest do={
  :global cfmG; :global cfmRosFake
  :if ([:len [:tostr $cfmRosFake]] > 0) do={ :return [:tostr $cfmRosFake] }
  :local ch [:tostr ($cfmG->"rosChannel")]
  :if ([:len $ch] = 0) do={ :set ch "stable" }
  :local v ""
  :onerror x in={
    :local r [/tool/fetch url=("https://upgrade.mikrotik.com/routeros/NEWESTa7." . $ch) output=user idle-timeout=15s as-value]
    :local d [:tostr ($r->"data")]
    :local p [:find $d " "]
    :if ([:typeof $p] = "nil") do={ :set v $d } else={ :set v [:pick $d 0 $p] }
  } do={ :log warning ("cfm: neueste RouterOS-Version nicht abrufbar: " . $x) }
  :if (!($v ~ "^[0-9]+\\.[0-9]+")) do={ :set v "" }
  :return $v
}

:global cfmNotifyTick do={
  :global cfmG; :global cfmLoadData; :global cfmInvLoad; :global cfmJson; :global cfmMB; :global cfmNow
  :global cfmEnrolled; :global cfmRings; :global cfmWrite; :global cfmNotify; :global cfmNotifyLic
  :global cfmRosLatest; :global cfmVerGe
  $cfmLoadData
  :local nc ($cfmG->"notify")
  :if ([:len [:tostr ($nc->"url")]] = 0) do={ :return 0 }
  :local stale 1800
  :if ([:len [:tostr ($nc->"stale")]] > 0) do={ :set stale ([:tonsec [:totime ($nc->"stale")]] / 1000000000) }
  :local lw 14
  :if ([:len [:tostr ($nc->"licWarn")]] > 0) do={ :set lw ([:tonsec [:totime ($nc->"licWarn")]] / 86400000000000) }
  :local b [$cfmMB]
  :local now [$cfmNow]
  :local rg [$cfmRings]
  # aktuelle Probleme: Schlüssel "<art>:<gerät>" -> Text
  :local cur ({})
  :foreach name,d in=[$cfmInvLoad] do={
    :if ([$cfmEnrolled $d]) do={
      :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
      :local res [:tostr ($s->"res")]
      :local p ""
      :if ([:len $res] > 0 and $res != "ok") do={ :set p $res }
      # bad wie in $cfmStatus: nur solange sie nicht älter ist als IST oder SOLL ist
      :local bv [:tonum ($s->"bad")]
      :local iv [:tonum ($s->"v")]; :if ([:typeof $iv] != "num") do={ :set iv 0 }
      :local sv0 [:tonum ($rg->("r" . ($d->"ring")))]; :if ([:typeof $sv0] != "num") do={ :set sv0 0 }
      :if ([:typeof $bv] = "num" and ($bv >= $iv or $bv = $sv0)) do={ :set p ("bad v" . $bv . " " . $p) }
      :if ([:len $p] > 0) do={ :set ($cur->("apply:" . $name)) ("Apply-Fehler: " . $p) }
      :local sn [:tonum ($s->"seen")]
      :if ([:typeof $sn] = "num" and ($now - $sn) > $stale) do={ :set ($cur->("stumm:" . $name)) ("stumm: kein Status seit " . (($now - $sn) / 60) . " min") }
      :if ([:tostr ($s->"wfb")] = "1") do={ :set ($cur->("wlan:" . $name)) "WLAN lokal: kein CAPsMAN verbunden" }
      :local ug [:tostr ($s->"upg")]
      :if ($ug ~ "^(fehlgeschlagen|Fenster verpasst|Platz fehlt)") do={ :set ($cur->("update:" . $name)) ("RouterOS-Update: " . $ug) }
    }
  }
  # Lizenz des Managers selbst (nur CHR hat next-renewal-at/deadline-at)
  :local lic ({})
  :onerror x in={ :set lic [/system/license/get] } do={}
  :local lm [$cfmNotifyLic now=[/system/clock/get date] renew=($lic->"next-renewal-at") deadline=($lic->"deadline-at") warn=$lw]
  :if ([:len $lm] > 0) do={ :set ($cur->("lizenz:" . [/system/identity/get name])) $lm }
  # Wechsel gegen meta/notify.dat melden
  :local f ($b . "/meta/notify.dat")
  :local nj [$cfmJson $f]
  :local act ($nj->"act")
  :if ([:typeof $act] != "array") do={ :set act ({}) }
  :local down false
  :local n 0
  :local chg false
  :foreach k,m in=$cur do={
    :if (!$down and [:typeof ($act->$k)] != "array") do={
      :local p [:find $k ":"]
      :if ([$cfmNotify ev=[:pick $k 0 $p] host=[:pick $k ($p + 1) [:len $k]] st="on" msg=$m]) do={
        :set ($act->$k) ({"t"=$now;"m"=$m})
        :set n ($n + 1)
        :set chg true
      } else={ :set down true }
    }
  }
  :local gone ({})
  :foreach k,a in=$act do={
    :if (!$down and [:typeof ($cur->$k)] = "nothing") do={
      :local p [:find $k ":"]
      :if ([$cfmNotify ev=[:pick $k 0 $p] host=[:pick $k ($p + 1) [:len $k]] st="off" msg=("wieder ok (war: " . [:tostr ($a->"m")] . ")")]) do={
        :set ($gone->$k) 1
        :set n ($n + 1)
      } else={ :set down true }
    }
  }
  :foreach k,x in=$gone do={ :set ($act->$k); :set chg true }
  :set ($nj->"act") $act
  # neue RouterOS-Version: einmal am Tag fragen, je Version einmal melden (als Text gespeichert -
  # :deserialize machte aus "7.24.5" eine IP-Adresse, deshalb mit Präfix v)
  :local rst [:tonum ($nj->"rost")]
  :if ([:typeof $rst] != "num") do={ :set rst 0 }
  :if (!$down and ($now - $rst) > 86400) do={
    :set ($nj->"rost") $now
    :set chg true
    :local nv [$cfmRosLatest]
    :if ([:len $nv] > 0 and ("v" . $nv) != [:tostr ($nj->"rosv")]) do={
      :local old ""
      :foreach name,d in=[$cfmInvLoad] do={
        :if ([$cfmEnrolled $d]) do={
          :local rv [:tostr ([$cfmJson ($b . "/state/" . $name . "/status.dat")]->"ros")]
          :set rv [:pick $rv 0 [:find ($rv . " ") " "]]
          :if ([:len $rv] > 0 and ![$cfmVerGe $rv $nv]) do={ :set old ($old . " " . $name . "=" . $rv) }
        }
      }
      :if ([:len $old] > 0) do={
        :local ch [:tostr ($cfmG->"rosChannel")]; :if ([:len $ch] = 0) do={ :set ch "stable" }
        :if ([$cfmNotify ev="ros" host="" st="once" msg=("RouterOS " . $nv . " (" . $ch . ") verfügbar, älter:" . $old . " - prüfen mit \$cfmUpgrade ver=" . $nv . " all=yes check=yes")]) do={ :set ($nj->"rosv") ("v" . $nv); :set n ($n + 1) } else={ :set ($nj->"rost") 0 }
      } else={ :set ($nj->"rosv") ("v" . $nv) }
    }
  }
  :if ($chg) do={ $cfmWrite $f [:serialize to=json $nj] }
  :return $n
}
