# ============================================================
# cfm – WLAN (gerendert vom CAPsMAN auf den Config-Managern)
#  ssids     Key = interner Name. vlan = Datapath-VLAN, bands = "2,5",
#            sec/ft/pmf/isolation überschreiben die defaults.
#            Passphrase NUR im Vault: cfm:psk.<key>  ($cfmSecret key=psk.main value=...)
#  master    SSID, die das physische Radio trägt (die übrigen werden virtuelle APs)
#  channels  Kanal-Pools je Band; RouterOS wählt daraus den passendsten Kanal.
#            skipDfs = "10min-cac" (Wetterradar-Kanäle meiden) | "all" | "disabled"
#  reselect  Uhrzeit der nächtlichen Kanal-Neuwahl (reselect-time), leer = nur beim Start
#  ppsk      mehrere Passphrasen mit eigenem VLAN je SSID (RouterOS ≥ 7.17, nur WPA2-PSK,
#            VLAN nur mit wifi-qcom). Beispiel für die IoT-SSID:
#              "ppsk"={"iot"={"kameras"={"vlan"=31;"isolation"="yes"};"gast"={"vlan"=40}}}
#            optional "expires"="2026-12-31 23:59:59". Passphrasen NUR im Vault:
#            $cfmSecret key=ppsk.iot.kameras value=...
#  radios    optionales Pinning pro AP-Identity: {"ap1"={"5"="5180";"2"="2412"}}
# ============================================================
:global cfmWifi {
  "country"="Germany";
  "master"="main";
  "defaults"={"sec"="wpa2-psk,wpa3-psk";"ft"="yes";"ftOverDs"="yes";"pmf"="allowed";"rrm"="yes";"wnm"="yes";"isolation"="no"};
  "ssids"={
    "main"={"ssid"="Demo";"vlan"=20;"bands"="2,5"};
    "guest"={"ssid"="Demo-Gast";"vlan"=40;"bands"="2,5";"isolation"="yes"};
    "event"={"ssid"="Demo-Event";"vlan"=40;"bands"="2,5";"isolation"="yes"};
    "iot"={"ssid"="Demo-IoT";"vlan"=30;"bands"="2";"sec"="wpa2-psk";"ft"="no";"pmf"="disabled"}
  };
  "channels"={
    "2"={"band"="2ghz-ax";"freq"="2412,2437,2462";"width"="20mhz"};
    "5"={"band"="5ghz-ax";"freq"="5180,5200,5220,5240,5745,5765,5785,5805,5825";"width"="20/40/80mhz";"skipDfs"="10min-cac"}
  };
  "reselect"="03:00";
  "ppsk"={};
  "radios"={}
}
