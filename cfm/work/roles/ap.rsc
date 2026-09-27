# ============================================================
# Rolle ap – WLAN-Access-Point als CAP des (wifi-)CAPsMAN
#  SSIDs/Kanäle/Security rendert der CAPsMAN (Rolle capsman, D45). Welche Geräte das sind, steht im
#  Manifest-Feld cm (Name + MGMT-IP) – daraus caps-man-addresses/-names.
#  Lokaler Fallback (D46): Jedes Radio trägt zusätzlich eine lokale Kopie der Master-SSID
#  (configuration.manager=capsman-or-local). Reißt die Verbindung zum CAPsMAN ab, sendet der AP nach
#  ~10 s mit der lokalen Konfiguration weiter, statt die Radios abzuschalten; kommt der CAPsMAN
#  zurück, übernimmt er wieder. Passphrasen per Secret-Push aus dem Vault (wie beim CAPsMAN).
#  Lokales Forwarding: SSIDs landen per datapath vlan-id im VLAN,
#  der Uplink braucht daher das Profil "trunk-ap".
# ============================================================
:global cfmG; :global cfmMf; :global cfmEnsure; :global cfmSet; :global cfmLog; :global cfmDry
:global cfmWifi; :global cfmWifiRender

:local mv [:tostr ($cfmG->"mgmtVlan")]

# CAPsMAN-Geräte aus dem Manifest (fehlt cm bei einem Manager vor D45: alle Manager, Namen offen lassen)
:local cmA ({}); :local cmN ({})
:foreach c in=($cfmMf->"cm") do={
  :set ($cmA->[:len $cmA]) [:tostr ($c->"ip")]
  :set ($cmN->[:len $cmN]) [:tostr ($c->"n")]
}
:if ([:len $cmA] = 0) do={ :set cmA ($cfmG->"managers") }
:local cmS ""
:foreach n in=$cmN do={ :set cmS ($cmS . "," . $n) }
:if ([:len $cmS] > 0) do={ :set cmS [:pick $cmS 1 [:len $cmS]] }

# Lokaler Datapath (D41): Die Bridge ist beim wifi-CAPsMAN eine Einstellung des CAP. Der CAPsMAN
# schickt vlan-id und client-isolation, aber nie "bridge" (er kennt die Interfaces des CAP nicht).
# Ohne diesen Datapath wird kein Radio Bridge-Port: Clients melden sich an, erreichen aber kein
# VLAN. Virtuelle APs (slaves-datapath) zeigen darauf, vlan-id bleibt leer.
# Im Kommentar merkt er sich die CAPsMAN-Namen des letzten Apply (Zertifikatswechsel, s.u.).
:local dp "cfm-cap"
:local oldCm ""
:onerror e in={
  :local c [:tostr [/interface/wifi/datapath/get [find where comment~"^cfm:wdp-cap"] comment]]
  :local p [:find $c "cm="]
  :if ([:typeof $p] != "nil") do={ :set oldCm [:pick $c ($p + 3) [:len $c]] }
} do={}
:local dpx ""
:if ([:len $cmS] > 0) do={ :set dpx ("cm=" . $cmS) }
$cfmEnsure m="/interface/wifi/datapath" k="wdp-cap" n=({"name"=$dp}) p=({"name"=$dp;"bridge"="bridge"}) x=$dpx

# Zertifikate eines anderen CAPsMAN (TODO 26): Ein CAP vertraut nur der CA des CAPsMAN, bei dem er
# sein Zertifikat angefordert hat. Hängt er an einem CAPsMAN, der nicht in cm steht, oder hat sich cm
# seit dem letzten Apply geändert (Umzug der Rolle capsman), CAPsMAN-Zertifikate löschen und neu
# anfordern – den kurzen Abriss überbrückt der lokale Fallback.
:if ([:len $cmS] > 0) do={
  :local cur ""
  :onerror e in={ :set cur [:tostr [/interface/wifi/cap/get current-caps-man-identity]] } do={}
  :local foreign ([:len $cur] > 0 and [:typeof [:find $cmN $cur]] = "nil")
  :local moved ([:len $oldCm] > 0 and $oldCm != $cmS)
  :if (($foreign or $moved) and [:len [/certificate/find where trust-store=capsman]] > 0) do={
    :if ($cfmDry = true) do={ $cfmLog ("CAPsMAN-Zertifikate würden erneuert (verbunden: " . $cur . ", bisher: " . $oldCm . ", jetzt: " . $cmS . ")") } else={
      /interface/wifi/cap/set certificate=none
      /certificate/remove [find where trust-store=capsman]
      /interface/wifi/cap/set certificate=request
      $cfmLog ("CAPsMAN-Zertifikate erneuert (verbunden: " . $cur . ", bisher: " . $oldCm . ", jetzt: " . $cmS . ")")
    }
  }
}

:local cp ({"enabled"="yes";"caps-man-addresses"=$cmA;"discovery-interfaces"=("vlan" . $mv);"lock-to-caps-man"="no";"certificate"="request";"slaves-datapath"=$dp})
:if ([:len $cmN] > 0) do={ :set ($cp->"caps-man-names") $cmN }
$cfmSet m="/interface/wifi/cap" p=$cp

# MLO (Wi-Fi 7, z.B. hAP be³): Der CAPsMAN fasst Radios mit gleicher SSID zu einem MLD-Interface
# zusammen, über das der Verkehr läuft. Auch dafür kommen Bridge und vlan-id nicht vom CAPsMAN an
# (Hardware-Befund: MLD ohne Datapath kein Bridge-Port -> kein DHCP; mit dem Profil cfm-cap PVID 1).
# Eigener Datapath mit dem VLAN der Master-SSID; ein mld-datapath gilt für alle MLDs des CAP, weitere
# SSIDs mit MLO bräuchten eigene VLANs (TODO 32). Ohne Wi-Fi 7 wirkungslos.
:local mdp "cfm-mld"
:local mdpp ({"name"=$mdp;"bridge"="bridge"})
:local mvl [:tostr ($cfmWifi->"ssids"->[:tostr ($cfmWifi->"master")]->"vlan")]
:if ([:len $mvl] > 0) do={ :set ($mdpp->"vlan-id") [:tonum $mvl] }
$cfmEnsure m="/interface/wifi/datapath" k="wdp-mld" n=({"name"=$mdp}) p=$mdpp
:onerror e in={ $cfmSet m="/interface/wifi/cap" p=({"mld-datapath"=$mdp}) } do={ $cfmLog ("mld-datapath nicht gesetzt: " . $e) }

# Lokaler Fallback (D46): Profile wie beim CAPsMAN, Master-Konfiguration cfm-l<Band> je Band
:local lcf [$cfmWifiRender ap=[:tostr ($cfmMf->"name")]]
# Passphrasen fehlen (neue Profile): Secret-Push anfordern
:global cfmPskMissing
$cfmPskMissing

# Lokale Radios: CAPsMAN mit lokalem Fallback. Band über /interface/wifi/radio; Radios ohne Band in
# wifi.rsc (z.B. 6 GHz, TODO 32) bleiben reine CAPs. Datapath des Radios = Datapath der Master-SSID
# (Bridge + VLAN), gilt so im CAPsMAN-Betrieb (dieselbe vlan-id) wie im Fallback.
:local mdpn ("cfm-" . [:tostr ($cfmWifi->"master")])
:foreach i in=[/interface/wifi/find where default-name~"^wifi"] do={
  :local rn [/interface/wifi/get $i name]
  :local b ""
  :onerror e in={
    :local bs [:tostr [/interface/wifi/radio/get [find where interface=$rn] bands]]
    :if ($bs ~ "2ghz") do={ :set b "2" }
    :if ($bs ~ "5ghz") do={ :set b "5" }
  } do={}
  :local cfg [:tostr ($lcf->$b)]
  :local curM [:tostr [/interface/wifi/get $i configuration.manager]]
  :local curC [:tostr [/interface/wifi/get $i configuration]]
  :local curD [:tostr [/interface/wifi/get $i datapath]]
  :local curX [/interface/wifi/get $i disabled]
  :if ([:len $cfg] > 0) do={
    :if ($curM != "capsman-or-local" or $curC != $cfg or $curD != $mdpn or $curX = true) do={
      :if ($cfmDry != true) do={ /interface/wifi/set $i configuration=$cfg configuration.manager=capsman-or-local datapath=$mdpn disabled=no }
      $cfmLog ("Radio " . $rn . ": CAPsMAN mit lokalem Fallback " . $cfg . ", Datapath " . $mdpn)
    }
  } else={
    :if ($curM != "capsman" or $curD != $dp) do={
      :if ($cfmDry != true) do={ /interface/wifi/set $i configuration.manager=capsman datapath=$dp }
      $cfmLog ("Radio " . $rn . " -> CAPsMAN, Datapath " . $dp)
    }
  }
}
