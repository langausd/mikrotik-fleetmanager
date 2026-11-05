# ============================================================
# cfm lib/mgr-sniff.rsc – Manager-Funktionen: Mitschnitt einzelner Geräte (MACs) auf einem Router
#   $cfmSniff host=<n> mac=<MAC[,MAC…]>|lease=<Name[,Name…]> [dauer=2h] [max=20] [iface=<Interface>]
#                                   startet /tool/sniffer auf <n> (Rolle router oder manager: dort läuft der
#                                   Verkehr der Clients ins Internet durch), nur Pakete dieser MACs, in eine Datei
#                                   auf dem Gerät (max MB); nach dauer stoppt das Gerät selbst
#   $cfmSniff host=<n> stop=yes     vorzeitig beenden
#   $cfmSniff                       laufende und abgeholte Mitschnitte
#   $cfmSniffTick                   (Manager-Tick) holt beendete Mitschnitte nach cfm/sniff/<n>-<Zeit>.pcap
#   Auswerten am Rechner: tools/pcap-ziele.py (Internet-Ziele je Gerät, Vorschlag für allow).
#   (Übersicht aller Befehle: lib/mgr-core.rsc)
# ============================================================

:global cfmSniff do={
  :global cfmInvLoad; :global cfmExec; :global cfmMB; :global cfmJson; :global cfmWrite; :global cfmNow
  :global cfmLoadData; :global cfmLeases
  :local b [$cfmMB]
  :local jf ($b . "/meta/sniff.dat")
  :local jobs [$cfmJson $jf]
  :if ([:len $host] = 0) do={
    :put "Mitschnitte (cfm/sniff/, auswerten mit tools/pcap-ziele.py):"
    :foreach n,j in=$jobs do={ :put ("  laeuft: " . $n . " bis " . [:tostr ($j->"bis")] . " (" . [:tostr ($j->"mac")] . ")") }
    :foreach f in=[/file/find where name~("^" . $b . "/sniff/.*\\.pcap\$")] do={ :put ("  " . [/file/get $f name] . " " . [/file/get $f size] . " Byte") }
    :return ""
  }
  :local inv [$cfmInvLoad]
  :local d ($inv->$host)
  :if ([:typeof $d] != "array") do={ :error ("cfmSniff: " . $host . " nicht im Inventar") }
  :if (!(("," . [:tostr ($d->"role")] . ",") ~ ",(router|manager),")) do={ :error ("cfmSniff: " . $host . " hat weder Rolle router noch manager - dort läuft der Verkehr der Clients nicht durch") }
  :local ip [:tostr ($d->"ip")]
  :if ($stop = "yes") do={
    :local r [$cfmExec ip=$ip cmd=("/tool/sniffer/stop; /system/scheduler/remove [find where name=\"cfm-sniff-stop\"]; :put ok")]
    :if (!(($r->"output") ~ "ok")) do={ :error ("cfmSniff: " . $host . " nicht erreichbar: " . [:pick ($r->"output") 0 120]) }
    :if ([:typeof ($jobs->$host)] = "array") do={ :set ($jobs->$host->"bis") [$cfmNow]; $cfmWrite $jf [:serialize to=json $jobs] }
    :put ("Mitschnitt auf " . $host . " beendet - der nächste Manager-Tick holt ihn ab (oder \$cfmSniffTick)")
    :return ""
  }
  # MACs direkt oder über die Namen in leases.rsc (alle VLANs)
  :local macs ({})
  :foreach m in=[:toarray $mac] do={ :if ([:len [:tostr $m]] > 0) do={ :set ($macs->[:len $macs]) [:tostr $m] } }
  :if ([:len $lease] > 0) do={
    $cfmLoadData
    :foreach nm in=[:toarray $lease] do={
      :local hit ""
      :foreach vid,ls in=$cfmLeases do={ :if ([:len [:tostr ($ls->[:tostr $nm]->"mac")]] > 0) do={ :set hit [:tostr ($ls->[:tostr $nm]->"mac")] } }
      :if ([:len $hit] = 0) do={ :error ("cfmSniff: Lease " . $nm . " ohne MAC in leases.rsc") }
      :set ($macs->[:len $macs]) $hit
    }
  }
  :if ([:len $macs] = 0) do={ :error "Aufruf: \$cfmSniff host=<n> mac=<MAC[,MAC]>|lease=<Name[,Name]> [dauer=2h] [max=20] [iface=<Interface>]" }
  :if ([:len $macs] > 16) do={ :error "cfmSniff: höchstens 16 MACs (Grenze von /tool/sniffer)" }
  :foreach m in=$macs do={ :if (!($m ~ "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}\$")) do={ :error ("cfmSniff: " . $m . " ist keine MAC-Adresse") } }
  :local du 7200
  :if ([:len $dauer] > 0) do={ :set du ([:tonsec [:totime $dauer]] / 1000000000) }
  :if ($du < 10) do={ :error ("cfmSniff: dauer " . $dauer . " ist keine Dauer (z.B. 2h, 30m)") }
  :local mx 20
  :if ([:len $max] > 0) do={ :set mx [:tonum $max] }
  :if ([:typeof $mx] != "num" or $mx < 1) do={ :error "cfmSniff: max in MB (Zahl)" }
  # Platz: auf dem Gerät für die Datei, auf dem Manager für die Abholung (je mit 5 MB Rest)
  # Läuft der Mitschnitt auf dem Manager selbst (Router und Manager in einem, z.B. CRS), schreibt er gleich nach
  # sniff/ - Abholen hieße die Datei auf demselben Speicher verdoppeln
  :local self ([:len [/ip/address/find where address~("^" . $ip . "/")]] > 0)
  :if (!$self and ([/system/resource/get free-hdd-space] / 1048576) < ($mx + 5)) do={ :error ("cfmSniff: auf dem Manager sind keine " . ($mx + 5) . " MB frei für die Abholung - max kleiner wählen") }
  :local fn "sniff.pcap"
  :if ($self) do={
    :onerror e in={ :if ([:len [/file/find where name=($b . "/sniff")]] = 0) do={ /file/add name=($b . "/sniff") type=directory } } do={}
    :local ts [:pick [:tostr [/system/clock/get date]] 0 10]
    :local tm [:tostr [/system/clock/get time]]
    :set fn ($host . "-" . $ts . "-" . [:pick $tm 0 2] . [:pick $tm 3 5] . ".pcap")
  }
  :local ml ""
  :foreach m in=$macs do={ :set ml ($ml . "," . $m) }
  :set ml [:pick $ml 1 [:len $ml]]
  :local fi "all"
  :if ([:len $iface] > 0) do={ :set fi $iface }
  # Datei unter cfm/out/ (bzw. flash/cfm/out/): von dort holt der Manager per SFTP (wie den Status)
  :local c (":local o \"cfm/out\"; :onerror e in={ :if ([/file/get flash type] = \"directory\") do={ :set o \"flash/cfm/out\" } } do={}; ")
  :if ($self) do={ :set c (":local o \"" . $b . "/sniff\"; ") }
  :set c ($c . ":if (([/system/resource/get free-hdd-space] / 1048576) < " . ($mx + 5) . ") do={ :put \"ERR kein Platz\" } else={ ")
  :set c ($c . "/tool/sniffer/stop; :onerror e in={ /file/remove [find where name=(\$o . \"/" . $fn . "\")] } do={}; ")
  :set c ($c . "/tool/sniffer/set filter-mac-address=" . $ml . " filter-interface=" . $fi . " file-name=(\$o . \"/" . $fn . "\") file-limit=" . ($mx * 1024) . " memory-limit=1024 streaming-enabled=no only-headers=no filter-stream=no; ")
  :set c ($c . "/system/scheduler/remove [find where name=\"cfm-sniff-stop\"]; ")
  :set c ($c . "/system/scheduler/add name=\"cfm-sniff-stop\" interval=" . $du . "s comment=\"cfm-sys:sniff\" on-event=\"/tool/sniffer/stop; /system/scheduler/remove [find where name=\\\"cfm-sniff-stop\\\"]\"; ")
  :set c ($c . "/tool/sniffer/start; :put (\"OK \" . \$o) }")
  :local r [$cfmExec ip=$ip cmd=$c]
  :local out [:tostr ($r->"output")]
  :if (!($out ~ "OK ")) do={ :error ("cfmSniff: Start auf " . $host . " gescheitert: " . [:pick $out 0 160]) }
  :local p [:find $out "OK "]
  :local od [:pick $out ($p + 3) [:len $out]]
  :foreach t in={"\r";"\n"} do={ :local q [:find $od $t]; :if ([:typeof $q] = "num") do={ :set od [:pick $od 0 $q] } }
  :set ($jobs->$host) ({"bis"=([$cfmNow] + $du);"mac"=$ml;"dir"=$od;"max"=$mx;"self"=$self;"fn"=$fn})
  $cfmWrite $jf [:serialize to=json $jobs]
  :log info ("cfm: Mitschnitt auf " . $host . " gestartet (" . $ml . ", " . ($du / 60) . " min, max " . $mx . " MB)")
  :put ("Mitschnitt auf " . $host . " läuft " . ($du / 60) . " min (" . $ml . ", höchstens " . $mx . " MB). Danach holt ihn der Manager-Tick nach " . $b . "/sniff/; vorzeitig beenden: \$cfmSniff host=" . $host . " stop=yes")
  :return ""
}

# Manager-Tick: beendete Mitschnitte abholen (eine Minute Nachlauf, damit der Sniffer die Datei geschrieben hat),
# auf dem Gerät löschen. Nicht erreichbar: beim nächsten Tick wieder, nach einem Tag aufgeben.
:global cfmSniffTick do={
  :global cfmInvLoad; :global cfmExec; :global cfmMB; :global cfmJson; :global cfmWrite; :global cfmNow
  :local b [$cfmMB]
  :local jf ($b . "/meta/sniff.dat")
  :if ([:len [/file/find where name=$jf]] = 0) do={ :return 0 }
  :local jobs [$cfmJson $jf]
  :local now [$cfmNow]
  :local inv [$cfmInvLoad]
  :local n 0
  :local fertig ({})
  :onerror e in={ :if ([:len [/file/find where name=($b . "/sniff")]] = 0) do={ /file/add name=($b . "/sniff") type=directory } } do={}
  :foreach h,j in=$jobs do={
    :if ($now > ([:tonum ($j->"bis")] + 60)) do={
      :local ip [:tostr ($inv->$h->"ip")]
      :local od [:tostr ($j->"dir")]
      :if ([:len $od] = 0) do={ :set od "cfm/out" }
      :local ts [:pick [:tostr [/system/clock/get date]] 0 10]
      :local tm [:tostr [/system/clock/get time]]
      :local dst ($b . "/sniff/" . $h . "-" . $ts . "-" . [:pick $tm 0 2] . [:pick $tm 3 5] . ".pcap")
      :local ok false
      :if (($j->"self") = true) do={
        # auf dem Manager selbst: Datei liegt schon unter sniff/, nur stoppen
        /tool/sniffer/stop
        /system/scheduler/remove [find where name="cfm-sniff-stop"]
        :log info ("cfm: Mitschnitt " . $h . " fertig: " . $od . "/" . [:tostr ($j->"fn")])
        :set n ($n + 1)
        :set ($fertig->[:len $fertig]) $h
      } else={
      :if ([:len $ip] > 0) do={
        # Sniffer sicher stoppen (er schreibt die Datei dabei zu Ende), dann abholen und dort löschen
        $cfmExec ip=$ip cmd=("/tool/sniffer/stop; /system/scheduler/remove [find where name=\"cfm-sniff-stop\"]")
        :onerror e in={ /tool/fetch url=("sftp://" . $ip . "/" . $od . "/sniff.pcap") user="cfm" dst-path=$dst as-value; :set ok true } do={ :log warning ("cfm: Mitschnitt " . $h . " nicht abgeholt: " . $e) }
      }
      :if ($ok) do={
        $cfmExec ip=$ip cmd=(":onerror e in={ /file/remove [find where name=\"" . $od . "/sniff.pcap\"] } do={}")
        :log info ("cfm: Mitschnitt " . $h . " abgeholt: " . $dst)
        :set n ($n + 1)
      }
      :if ($ok or $now > ([:tonum ($j->"bis")] + 86400)) do={ :set ($fertig->[:len $fertig]) $h }
      }
    }
  }
  :foreach h in=$fertig do={ :set ($jobs->$h) }
  :if ([:len $fertig] > 0) do={
    :if ([:len $jobs] = 0) do={ /file/remove [find where name=$jf] } else={ $cfmWrite $jf [:serialize to=json $jobs] }
  }
  :return $n
}
