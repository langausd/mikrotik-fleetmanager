# ============================================================
# cfm lib/capsman.ssid.rsc – Rumpf der Skripte cfm-ssid-<key>-on/-off (schaltbare SSID, DW4.1/DW4.2, DG4.6)
# Kein Import: $cfmCapsmanOn (lib/lib-wifi.rsc) setzt davor die Locals und dahinter den Aufruf. Als Funktion,
# damit die Datei allein :parse besteht ($cfmRelease).
#  st  "on"/"off"   k  Schlüssel der SSID in wifi.rsc (a-z0-9)   ssid  Name fürs Log
#  sf  Zustandsdatei <cfm>/ssid-<key>.txt                        aos   Auto-Aus nach s (0 = nie)
# Schaltet nur die Interfaces der SSID (Konfiguration cfm-<key> bzw. cfm-<key>-<Band>g) an allen CAPs und den
# eigenen Radios, die Regeln bleiben. :global cfmSsid<key> gilt für die Konsole, die Datei für Home Assistant
# und den Apply.
# ============================================================
:local ssidsw do={
  # Übergang von den dynamischen Interfaces vor DW4.2: die CAP-Radios einmal neu provisionieren
  :if ([:len [/interface/wifi/find where dynamic and configuration~"^cfm-"]] > 0) do={ /interface/wifi/radio/provision [find where !local]; :delay 8s }
  :local dis "no"
  :if ($st = "off") do={ :set dis "yes" }
  :foreach i in=[/interface/wifi/find where !dynamic and (configuration=("cfm-" . $k) or configuration~("^cfm-" . $k . "-[0-9]+g"))] do={ /interface/wifi/set $i disabled=$dis }
  :local v $st
  :if ($st = "on" and $aos > 0) do={ :set v ("on " . (([:tonsec [:timestamp]] / 1000000000) + $aos)) }
  :onerror e in={ /file/set $sf contents=$v } do={ /file/add name=$sf contents=$v }
  :local fs [:parse (":global cfmSsid" . $k . "; :set cfmSsid" . $k . " \"" . $st . "\"")]
  $fs
  :log info ("cfm: SSID " . $ssid . " " . $st)
}
