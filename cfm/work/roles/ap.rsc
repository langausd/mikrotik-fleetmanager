# ============================================================
# Rolle ap – WLAN-Access-Point als CAP des (wifi-)CAPsMAN
#  SSIDs/Kanäle/Security rendert der CAPsMAN (Rolle capsman, DW1.5). Welche Geräte das sind, steht im
#  Manifest-Feld cm (Name + MGMT-IP) – daraus caps-man-addresses/-names.
#  Lokaler Fallback (DW1.6): Jedes Radio trägt zusätzlich eine lokale Kopie der Master-SSID
#  (configuration.manager=capsman-or-local). Reißt die Verbindung zum CAPsMAN ab, sendet der AP nach
#  ~10 s mit der lokalen Konfiguration weiter, statt die Radios abzuschalten; kommt der CAPsMAN
#  zurück, übernimmt er wieder. Passphrasen per Secret-Push aus dem Vault (wie beim CAPsMAN). Weitere SSIDs mit
#  fallback="yes" über eigene lokale virtuelle APs, geschaltet vom Skript cfm-fallback (DW1.12).
#  Lokales Forwarding: SSIDs landen per datapath vlan-id im VLAN,
#  der Uplink braucht daher das Profil "trunk-ap".
# ============================================================
:global cfmG; :global cfmMf; :global cfmEnsure; :global cfmSet; :global cfmLog; :global cfmDry
:global cfmWifi; :global cfmWifiRender
:if ([:typeof $cfmWifiRender] = "nothing") do={ :error "lib/lib-wifi.rsc fehlt im Manifest (DG4.3)" }

:local mv [:tostr ($cfmG->"mgmtVlan")]

# Radios mit wifi-qcom-ac (hAP ac², cAP ac …) übernehmen vlan-id nicht vom CAPsMAN (TODO 23) - die
# SSIDs landen dann nicht in ihrem VLAN. cfm unterstützt das Paket noch nicht, nur Warnung
:global cfmWarn
:local qac 0
:onerror e in={ :set qac [:len [/system/package/find where name="wifi-qcom-ac" and !disabled and !available]] } do={ :set qac [:len [/system/package/find where name="wifi-qcom-ac" and !disabled]] }
:if ($qac > 0) do={ $cfmWarn "Paket wifi-qcom-ac: SSIDs bekommen ihr VLAN nicht vom CAPsMAN (TODO 23) - Rolle ap hier nicht verwenden" }

# CAPsMAN-Geräte aus dem Manifest (fehlt cm bei einem Manager vor DW1.5: alle Manager, Namen offen lassen)
:local cmA ({}); :local cmN ({})
:foreach c in=($cfmMf->"cm") do={
  :set ($cmA->[:len $cmA]) [:tostr ($c->"ip")]
  :set ($cmN->[:len $cmN]) [:tostr ($c->"n")]
}
:if ([:len $cmA] = 0) do={ :set cmA ($cfmG->"managers") }
:local cmS ""
:foreach n in=$cmN do={ :set cmS ($cmS . "," . $n) }
:if ([:len $cmS] > 0) do={ :set cmS [:pick $cmS 1 [:len $cmS]] }

# Lokaler Datapath (DW1.3): Die Bridge ist beim wifi-CAPsMAN eine Einstellung des CAP. Der CAPsMAN
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
    :if ($cfmDry = true) do={ $cfmLog ("CAPsMAN-Zertifikate wuerden erneuert (verbunden: " . $cur . ", bisher: " . $oldCm . ", jetzt: " . $cmS . ")") } else={
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

# Lokaler Fallback (DW1.6): Profile wie beim CAPsMAN, Master-Konfiguration cfm-l<Band> je Band
:local lcf [$cfmWifiRender ap=[:tostr ($cfmMf->"name")]]
# Passphrasen fehlen (neue Profile): Secret-Push anfordern
:global cfmPskMissing
$cfmPskMissing

# Lokale Radios: CAPsMAN mit lokalem Fallback. Band über /interface/wifi/radio; Radios ohne Band in
# wifi.rsc bleiben reine CAPs. Datapath des Radios = Datapath der Master-SSID
# (Bridge + VLAN), gilt so im CAPsMAN-Betrieb (dieselbe vlan-id) wie im Fallback.
:local mdpn ("cfm-" . [:tostr ($cfmWifi->"master")])
# Wi-Fi 7 (hAP be³): Ab Werk hängen die Radios am statischen, abgeschalteten MLD mld1. Im
# CAPsMAN-Betrieb stört das nicht (der CAPsMAN legt sein MLD dynamisch an), im Fallback blieben die
# Radios damit aus ("mld-interface not enabled"). Deshalb lösen – lokal senden sie dann ohne MLO.
# Im CAPsMAN-Betrieb zeigt mld-interface das dynamische MLD, der statische Wert ist nicht lesbar;
# das unset leert ihn trotzdem und stört das dynamische MLD nicht (Hardware-Test) -> bei jedem Apply
# still, sofern das Gerät ein statisches MLD hat. Über das Eigenschafts-Array: Radios ohne MLO
# kennen mld-name nicht.
:local smld false
:foreach x in=[/interface/wifi/find where !dynamic] do={
  :if ([:len [:tostr ([/interface/wifi/get $x]->"mld-name")]] > 0) do={ :set smld true }
}
# Radios mit lokaler Konfiguration {Name=Band} - für die lokalen virtuellen APs der Fallback-SSIDs (DW1.12)
:local rads ({})
:foreach i in=[/interface/wifi/find where default-name~"^wifi"] do={
  :local rn [/interface/wifi/get $i name]
  :local b ""
  :onerror e in={
    :local bs [:tostr [/interface/wifi/radio/get [find where interface=$rn] bands]]
    :if ($bs ~ "2ghz") do={ :set b "2" }
    :if ($bs ~ "5ghz") do={ :set b "5" }
    :if ($bs ~ "6ghz") do={ :set b "6" }
  } do={}
  :local cfg [:tostr ($lcf->$b)]
  :local curM [:tostr [/interface/wifi/get $i configuration.manager]]
  :local curC [:tostr [/interface/wifi/get $i configuration]]
  :local curD [:tostr [/interface/wifi/get $i datapath]]
  :local curX [/interface/wifi/get $i disabled]
  # Band an diesem AP aus (radios "off", DW3.7): Radio abschalten - im CAPsMAN-Betrieb wie im Fallback
  :if ($cfg = "off") do={
    :if (!$curX) do={
      :if ($cfmDry != true) do={ /interface/wifi/set $i disabled=yes }
      $cfmLog ("Radio " . $rn . ": Band " . $b . " aus (wifi.rsc radios)")
    }
  } else={
  :if ([:len $cfg] > 0) do={
    :set ($rads->$rn) $b
    :if ($curM != "capsman-or-local" or $curC != $cfg or $curD != $mdpn or $curX = true) do={
      :if ($cfmDry != true) do={ /interface/wifi/set $i configuration=$cfg configuration.manager=capsman-or-local datapath=$mdpn disabled=no }
      $cfmLog ("Radio " . $rn . ": CAPsMAN mit lokalem Fallback " . $cfg . ", Datapath " . $mdpn)
    }
    :if ($smld and $cfmDry != true) do={ /interface/wifi/unset $i value-name=mld-interface }
  } else={
    :if ($curM != "capsman" or $curD != $dp) do={
      :if ($cfmDry != true) do={ /interface/wifi/set $i configuration.manager=capsman datapath=$dp }
      $cfmLog ("Radio " . $rn . " -> CAPsMAN, Datapath " . $dp)
    }
  }
  }
}

# Weitere SSIDs im lokalen Fallback (TODO 84, DW1.12, ersetzt DW1.8): fallback="yes" an einer SSID -> je Radio, dessen
# Band die SSID trägt, ein eigener lokaler virtueller AP fb-<key>-<Radio> mit der lokalen Konfiguration der SSID
# (cfm-<key> bzw. cfm-<key>-<Band>g; deren Datapath: Bridge + VLAN, cfm-iso bei isolierten VLANs). Normal aus - das
# Skript cfm-fallback (unten) schaltet ihn ein, wenn der CAP ~20 s keinen CAPsMAN hat, und beim Wiederverbinden aus;
# der Apply rührt den Schaltzustand nicht an. Die vom CAPsMAN angelegten virtuellen APs nimmt RouterOS im Fallback
# außer Betrieb, auch mit slaves-static und lokaler Konfiguration daran (Hardware 2026-11-16).
# /interface/wifi steht nicht in cfmMenus (das Audit meldete sonst jedes Radio und jedes Interface des CAPsMAN als
# unverwaltet): hier bei jedem Lauf indizieren, damit der Abgleich fb-… auch nach dem Entfernen von fallback abräumt
:global cfmIndex
$cfmIndex "/interface/wifi"
:local fbs ""
:foreach k,s in=($cfmWifi->"ssids") do={
  :if ($k != [:tostr ($cfmWifi->"master")] and [:tostr ($s->"fallback")] = "yes") do={
    :foreach rn,b in=$rads do={
      :if (("," . [:tostr ($s->"bands")] . ",") ~ ("," . $b . ",")) do={
        :local cfg ("cfm-" . $k)
        :if ([:len [/interface/wifi/configuration/find where name=($cfg . "-" . $b . "g")]] > 0) do={ :set cfg ($cfg . "-" . $b . "g") }
        :local nm ("fb-" . $k . "-" . $rn)
        :local fi [$cfmEnsure m="/interface/wifi" k=("wfb:" . $k . "-" . $rn) n=({"name"=$nm}) p=({"name"=$nm;"master-interface"=$rn;"configuration"=$cfg}) a=({"disabled"="yes";"configuration.manager"="local"})]
        :if ($cfmDry != true and [:typeof $fi] = "id") do={
          :if ([:tostr [/interface/wifi/get $fi configuration.manager]] != "local") do={ /interface/wifi/set $fi configuration.manager=local }
        }
        :set fbs ($fbs . " " . $nm)
      }
    }
  }
}
# slaves-static (DW1.8) braucht der Fallback nicht mehr: Mit slaves-static bekamen die virtuellen APs bei jedem
# Neuprovisionieren neue Namen, die alten blieben liegen (TODO 85). Ist es noch an, einmal abschalten - das trennt den
# CAP kurz vom CAPsMAN (DW1.9); danach räumt der zweite Apply die übrig gebliebenen statischen auf (unten)
:local cst ""
:onerror e in={ :set cst [:tostr [/interface/wifi/cap/get slaves-static]] } do={}
:local sstOn ($cst = "true" or $cst = "yes")
:if ($sstOn) do={
  :onerror e in={
    $cfmSet m="/interface/wifi/cap" p=({"slaves-static"="no"})
    :if ($cfmDry != true) do={ :global cfmApFollow; :set cfmApFollow true }
  } do={ $cfmLog ("slaves-static nicht abgeschaltet: " . $e) }
}
# Übrig gebliebene statische virtuelle APs (TODO 85, DW1.12): Ohne slaves-static legt der CAPsMAN seine virtuellen
# APs dynamisch an; statische mit master-interface ohne Kommentar cfm… stammen aus der Zeit mit slaves-static (je
# Neuprovisionieren neue, die alten deaktiviert). Entfernen - nicht im Apply, der slaves-static gerade abschaltet (dort
# sind sie noch in Gebrauch), nicht auf dem CAPsMAN-Gerät (dessen eigene Radios haben statische virtuelle APs aus der
# Provisionierung). Eigene von Hand: Kommentar mit "cfm" beginnen lassen (z.B. cfm-override), dann bleiben sie.
:global cfmIsCapsman
:if (!$sstOn and ![$cfmIsCapsman]) do={
  :foreach i in=[/interface/wifi/find where !dynamic] do={
    :local mi ""
    :onerror e in={ :set mi [:tostr [/interface/wifi/get $i master-interface]] } do={}
    :local cm [:tostr [/interface/wifi/get $i comment]]
    :if ([:len $mi] > 0 and !($cm ~ "^cfm")) do={
      :local vn [/interface/wifi/get $i name]
      :if ($cfmDry = true) do={ $cfmLog ("statischer virtueller AP " . $vn . " (an " . $mi . ", ohne cfm-Kommentar) wuerde entfernt") } else={
        /interface/wifi/remove $i
        $cfmLog ("statischer virtueller AP " . $vn . " (an " . $mi . ") entfernt - Rest aus slaves-static")
      }
    }
  }
}

# Isolierte VLANs (DP3.1): WLAN-Interfaces, deren Bridge-Port in einem isolierten VLAN liegt, in die Liste
# cfm-iso - sofern der Datapath sie nicht schon selbst einträgt (der CAPsMAN gibt interface-list nicht an die CAPs
# weiter, Hardware 2026-11-04). Gilt für Interfaces, die beim Apply bestehen.
:global cfmVlans
:local isv ({})
:foreach vid,v in=$cfmVlans do={ :if ([:tostr ($v->"isolate")] = "yes") do={ :set ($isv->$vid) 1 } }
# für den Agent: Er trägt neu entstandene Interfaces dieser VLANs auch zwischen zwei Applys nach
:global cfmIsoV
:set cfmIsoV $isv
:if ([:len $isv] > 0) do={
  :foreach bp in=[/interface/bridge/port/find where dynamic] do={
    :local nm [:tostr [/interface/bridge/port/get $bp interface]]
    :local pv [:tostr [/interface/bridge/port/get $bp pvid]]
    :if ([:typeof ($isv->$pv)] != "nothing" and [:len [/interface/wifi/find where name=$nm]] > 0) do={
      :if ([:len [/interface/list/member/find where list="cfm-iso" and interface=$nm and dynamic]] = 0) do={
        $cfmEnsure m="/interface/list/member" k=("ilm:ISO:" . $nm) n=({"list"="cfm-iso";"interface"=$nm}) p=({"list"="cfm-iso";"interface"=$nm})
      }
    }
  }
}

# Skript cfm-fallback (DW1.12, Rumpf lib/ap.fbwatch.rsc, DG4.6): alle 10 s - lokale Fallback-SSIDs ein/aus nach der
# Verbindung zum CAPsMAN, cfm-iso nach dem Wiederverbinden. Nur mit Fallback-SSIDs oder isolierten VLANs; sonst
# entfernt der Apply Skript und Scheduler (nicht mehr gesehen)
:if ([:len $fbs] > 0 or [:len $isv] > 0) do={
  :global cfmBody
  :local isl ""
  :foreach vid,x in=$isv do={ :set isl ($isl . ";\"" . $vid . "\"=1") }
  :if ([:len $isl] > 0) do={ :set isl [:pick $isl 1 [:len $isl]] }
  :local src ("# cfm (Rolle ap, DW1.12): lokale Fallback-SSIDs nach der CAPsMAN-Verbindung schalten, cfm-iso nachtragen. Jeder Apply schreibt es neu\n:local iso ({" . $isl . "})\n")
  :set src ($src . [$cfmBody "ap.fbwatch"] . "\n\$fbwatch iso=\$iso\n")
  $cfmEnsure m="/system/script" k="sys:fallback" n=({"name"="cfm-fallback"}) p=({"name"="cfm-fallback";"source"=$src;"policy"="read,write,test"})
  $cfmEnsure m="/system/scheduler" k="sys:fallback" n=({"name"="cfm-fallback"}) p=({"name"="cfm-fallback";"interval"="10s";"start-time"="startup";"on-event"="/system/script/run cfm-fallback";"disabled"="no"})
}
