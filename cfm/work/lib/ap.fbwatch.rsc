# ============================================================
# cfm lib/ap.fbwatch.rsc – Rumpf des Skripts cfm-fallback (Rolle ap, DW1.12, DG4.6)
# Kein Import: roles/ap.rsc setzt davor die Locals und dahinter den Aufruf (wie lib/base.portsw.rsc). Als Funktion,
# damit die Datei allein :parse besteht ($cfmRelease). Läuft alle 10 s (Scheduler cfm-fallback).
#  iso  isolierte VLANs {"<VID>"=1} (DP3.1), leer = nichts nachtragen
# Lokaler Fallback weiterer SSIDs (TODO 84): Ist der CAP zweimal hintereinander mit keinem CAPsMAN verbunden (~20 s),
# schaltet es die lokalen virtuellen APs der Fallback-SSIDs ein (Kommentar cfm:wfb:…, angelegt von der Rolle, normal
# aus); ist er wieder verbunden, sofort aus. Die vom CAPsMAN angelegten virtuellen APs nimmt RouterOS im Fallback
# außer Betrieb (Hardware 2026-11-16), die Master-SSID sendet über die lokale Konfiguration der Radios (DW1.6).
# Isolierte VLANs (DP3.1.1): Der CAP legt seine virtuellen APs bei jedem Verbinden neu an, die statischen Mitglieder
# in cfm-iso zeigen dann ins Leere. Zwei Takte nach dem Wiederverbinden (und nach dem Start) trägt es die
# WLAN-Interfaces isolierter VLANs nach und entfernt Verweise auf verschwundene - wie der Agent, aber ohne bis zu
# dessen nächstem Lauf zu warten. Schlüssel wie Rolle und Agent (ilm:ISO:<Interface>).
# Zustand in Globals: cfmFbN (Takte ohne CAPsMAN), cfmFbC (zuletzt verbunden), cfmFbIso (Takte bis zum Nachtragen).
# Log nur bei einem Wechsel.
# ============================================================
:local fbwatch do={
  :global cfmFbN; :global cfmFbC; :global cfmFbIso
  :if ([:typeof $cfmFbN] != "num") do={ :set cfmFbN 0 }
  :local c false
  :onerror e in={ :set c ([:len [:tostr [/interface/wifi/cap/get current-caps-man-identity]]] > 0) } do={}
  :local fb [/interface/wifi/find where comment~"^cfm:wfb:"]
  :if ($c) do={
    :set cfmFbN 0
    :local s ""
    :foreach i in=$fb do={
      :if (![/interface/wifi/get $i disabled]) do={ /interface/wifi/set $i disabled=yes; :set s ($s . " " . [/interface/wifi/get $i name]) }
    }
    :if ([:len $s] > 0) do={ :log info ("cfm: CAPsMAN wieder verbunden - lokale Fallback-SSIDs aus:" . $s) }
    :if ($cfmFbC != true) do={ :set cfmFbIso 2 }
    :set cfmFbC true
  } else={
    :set cfmFbN ($cfmFbN + 1)
    :set cfmFbC false
    :if ($cfmFbN >= 2) do={
      :local s ""
      :foreach i in=$fb do={
        :if ([/interface/wifi/get $i disabled]) do={ /interface/wifi/set $i disabled=no; :set s ($s . " " . [/interface/wifi/get $i name]) }
      }
      :if ([:len $s] > 0) do={ :log warning ("cfm: kein CAPsMAN seit ~" . ($cfmFbN * 10) . " s - lokale Fallback-SSIDs an:" . $s) }
    }
  }
  :if ([:typeof $cfmFbIso] = "num") do={
    :set cfmFbIso ($cfmFbIso - 1)
    :if ($cfmFbIso <= 0) do={
      :set cfmFbIso
      :if ($c and [:len $iso] > 0 and [:len [/interface/list/find where name="cfm-iso"]] > 0) do={
        :onerror e in={
          :foreach bp in=[/interface/bridge/port/find where dynamic] do={
            :local nm [:tostr [/interface/bridge/port/get $bp interface]]
            :local pv [:tostr [/interface/bridge/port/get $bp pvid]]
            :if ([:typeof ($iso->$pv)] != "nothing" and [:len [/interface/wifi/find where name=$nm]] > 0) do={
              :if ([:len [/interface/list/member/find where list="cfm-iso" and interface=$nm]] = 0) do={
                /interface/list/member/add list="cfm-iso" interface=$nm comment=("cfm:ilm:ISO:" . $nm)
                :log info ("cfm: " . $nm . " (VLAN " . $pv . ") in cfm-iso nachgetragen (nach dem Verbinden)")
              }
            }
          }
          :foreach mi in=[/interface/list/member/find where list="cfm-iso" and comment~"^cfm:ilm:ISO:" and !dynamic] do={
            :local inm [:tostr [/interface/list/member/get $mi interface]]
            :if ([:len [/interface/find where name=$inm]] = 0) do={
              :local cm [:tostr [/interface/list/member/get $mi comment]]
              /interface/list/member/remove $mi
              :log info ("cfm: cfm-iso: Verweis auf " . [:pick $cm 12 [:len $cm]] . " entfernt (Interface neu angelegt)")
            }
          }
        } do={ :log warning ("cfm: cfm-iso nicht nachgetragen: " . $e) }
      }
    }
  }
}
