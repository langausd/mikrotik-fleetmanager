# ============================================================
# cfm lib/capsman.reprov.rsc – Rumpf des Skripts cfm-reprov (veraltete CAP-Interfaces, DG4.6)
# Kein Import: $cfmCapsmanOn (lib/lib-wifi.rsc) setzt davor ":local aps" (Identities der CAPs mit veralteten
# Interfaces, jeder Apply neu) und dahinter den Aufruf. Als Funktion, damit die Datei allein :parse besteht.
# Startet der Mensch, wann die ~3 s ohne WLAN je AP passen: neu provisionieren, danach den Schaltzustand der
# SSIDs durchsetzen (Neuprovisionieren legt die festen Interfaces eingeschaltet neu an).
# ============================================================
:local reprov do={
  :if ([:len $aps] = 0) do={ :log info "cfm: reprov: keine veralteten CAPs" }
  :foreach a in=$aps do={
    :foreach r in=[/interface/wifi/radio/find where !local] do={
      :local c [:tostr [/interface/wifi/radio/get $r cap]]
      :if ([:pick $c 0 [:find $c "@"]] = $a) do={ /interface/wifi/radio/provision $r }
    }
    :log info ("cfm: reprov: " . $a . " neu provisioniert")
    :delay 8s
    :if ([:len [/system/script/find where name="cfm-ssid-check"]] > 0) do={ /system/script/run cfm-ssid-check }
    :delay 20s
  }
}
