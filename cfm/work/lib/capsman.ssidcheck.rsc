# ============================================================
# cfm lib/capsman.ssidcheck.rsc – Rumpf des Skripts cfm-ssid-check (schaltbare SSIDs, DW4.1/DW4.2, DG4.6)
# Kein Import: $cfmCapsmanOn (lib/lib-wifi.rsc) setzt davor ":local ssids" und dahinter den Aufruf. Als Funktion,
# damit die Datei allein :parse besteht ($cfmRelease). Läuft alle 10 min (Scheduler cfm-ssid-check).
#  ssids  je schaltbarer SSID {"k"=Schlüssel;"f"=Zustandsdatei;"d"=Grundzustand aus wifi.rsc;"a"=Auto-Aus in s}
# Zustand aus der Datei (ohne Datei der Grundzustand), Auto-Aus nach Ablauf ("on <Unixzeit>" -> Skript
# cfm-ssid-<key>-off), dann :global cfmSsid<key> setzen und den Zustand an den Interfaces durchsetzen - auch an
# denen eines neu verbundenen CAP, die eingeschaltet entstehen.
# ============================================================
:local ssidcheck do={
  :local now ([:tonsec [:timestamp]] / 1000000000)
  :foreach s in=$ssids do={
    :local k ($s->"k")
    :local c ""
    :onerror e in={ :set c [/file/get ($s->"f") contents] } do={}
    :local st ($s->"d")
    :if ([:pick $c 0 2] = "on") do={ :set st "on" }
    :if ([:pick $c 0 3] = "off") do={ :set st "off" }
    :local p [:find $c " "]
    :if (($s->"a") > 0 and [:pick $c 0 2] = "on" and [:typeof $p] = "num") do={
      :if ([:tonum [:pick $c ($p + 1) [:len $c]]] <= $now) do={ /system/script/run [find where name=("cfm-ssid-" . $k . "-off")]; :set st "off" }
    }
    :local fs [:parse (":global cfmSsid" . $k . "; :set cfmSsid" . $k . " \"" . $st . "\"")]
    $fs
    :local w "no"
    :if ($st = "off") do={ :set w "yes" }
    :foreach i in=[/interface/wifi/find where !dynamic and (configuration=("cfm-" . $k) or configuration~("^cfm-" . $k . "-[0-9]+g"))] do={
      :if ([/interface/wifi/get $i disabled] != ($st = "off")) do={ /interface/wifi/set $i disabled=$w }
    }
  }
}
