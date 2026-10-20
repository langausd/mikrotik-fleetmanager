# ============================================================
# cfm lib/lib-wifi.rsc – WLAN-Teil der Reconciler-Bibliothek (Geräteseite, D68)
# Nur im Manifest der Rollen ap, capsman und manager ($cfmManifests); der Agent importiert sie
# direkt nach lib/lib.rsc. Switches, Router und der Backup-Manager laden sie nicht. Die Bausteine
# ($cfmEnsure, $cfmBlock, $cfmSet …) und $cfmIsCapsman (braucht auch base) stehen in lib/lib.rsc;
# deren Syntaxfallen gelten hier ebenso.
# ============================================================

# WLAN-Profile aus wifi.rsc (D45/D46), gemeinsam für den CAPsMAN und den lokalen Fallback der APs:
# Steering, Kanal-Pools, je SSID Security (Passphrase nur per Secret-Push), Datapath (Bridge + VLAN)
# und Konfiguration, PPSK-Einträge, dazu je Band die Master-Konfiguration mit dem Kanal.
#  ohne ap    CAPsMAN: cfm-m<Band>, je gepinntem AP cfm-m<Band>-<AP> -> Liste der Provisioning-Regeln
#  ap=<Name>  lokal auf dem AP: cfm-l<Band> mit dem Pin dieses APs bzw. dem Pool -> {Band=Konfiguration}
:global cfmSsidState do={
  # Schaltbare SSID (D64): Zustand "on"/"off" aus <cfm>/ssid-<key>.txt auf dem CAPsMAN (schreiben die
  # Skripte cfm-ssid-<key>-on/-off), ohne Datei der Grundzustand aus wifi.rsc ("switch")
  :global cfmDir; :global cfmWifi
  :local st [:tostr ($cfmWifi->"ssids"->$1->"switch")]
  :local c ""
  :onerror e in={ :set c [/file/get ($cfmDir . "/ssid-" . $1 . ".txt") contents] } do={}
  :if ([:pick $c 0 2] = "on") do={ :set st "on" }
  :if ([:pick $c 0 3] = "off") do={ :set st "off" }
  :return $st
}

:global cfmWifiRender do={
  :global cfmWifi; :global cfmEnsure; :global cfmLog; :global cfmDry; :global cfmVlans
  :local w $cfmWifi
  :local d ($w->"defaults")
  :local mk ($w->"master")
  :local loc ([:len $ap] > 0)
  $cfmEnsure m="/interface/wifi/steering" k="wst" n=({"name"="cfm-steer"}) p=({"name"="cfm-steer";"rrm"=($d->"rrm");"wnm"=($d->"wnm")})
  # Steering je Band (TODO 39, D55): Liegt ein Client länger als "after" unter "threshold" (dBm), schickt
  # der AP ihm unaufgefordert BSS-Transition-Requests (802.11v, RouterOS >= 7.21) mit den Nachbar-APs
  # derselben SSID; "kick" trennt ihn, wenn er danach immer noch bleibt (leer = nie trennen).
  # Eigenes Profil cfm-steer-<Band>g, die Konfigurationen dieses Bands zeigen darauf.
  :local stn ({})
  :foreach b,c in=($w->"channels") do={
    :local st ($w->"steer"->$b)
    :set ($stn->$b) "cfm-steer"
    :if ([:typeof $st] = "array" and [:len [:tostr ($st->"threshold")]] > 0) do={
      :local sn ("cfm-steer-" . $b . "g")
      :local sp ({"name"=$sn;"rrm"=($d->"rrm");"wnm"=($d->"wnm");"transition-threshold"=[:tonum ($st->"threshold")];"transition-time"="unlimited"})
      :if ([:len [:tostr ($st->"after")]] > 0) do={ :set ($sp->"transition-threshold-time") ($st->"after") }
      :if ([:len [:tostr ($st->"kick")]] > 0) do={ :set ($sp->"transition-time") [:tostr ($st->"kick")] }
      :if ([:len [:tostr ($st->"count")]] > 0) do={ :set ($sp->"transition-request-count") [:tostr ($st->"count")] }
      :if ([:len [:tostr ($st->"period")]] > 0) do={ :set ($sp->"transition-request-period") ($st->"period") }
      $cfmEnsure m="/interface/wifi/steering" k=("wst:" . $b) n=({"name"=$sn}) p=$sp
      :set ($stn->$b) $sn
    }
  }
  # Mindestsignal bei der Anmeldung (TODO 39): schwächere Clients weist der AP ab. Ein Wert für alle
  # Bänder - die access-list kennt kein Band, nur Interfaces, und die der CAPs entstehen dynamisch.
  :local msg [:tostr ($w->"minSignal")]
  :if ([:len $msg] > 0) do={
    $cfmEnsure m="/interface/wifi/access-list" k="wacl:min" p=({"signal-range"=("-120.." . ([:tonum $msg] - 1));"action"="reject"})
  }
  # Kanal-Pools: RouterOS wählt selbst und prüft nachts neu (reselect, D32), DFS-Kanäle optional meiden
  :foreach b,c in=($w->"channels") do={
    :local cp ({"name"=("cfm-" . $b . "g");"band"=($c->"band");"frequency"=($c->"freq");"width"=($c->"width")})
    # als HH:MM:SS angeben: "03:00" liest RouterOS als 3 Minuten, der Vergleich schlüge jedes Mal fehl
    :local rs [:tostr ($w->"reselect")]
    :if ([:len $rs] = 5) do={ :set rs ($rs . ":00") }
    :if ([:len $rs] > 0) do={ :set ($cp->"reselect-time") $rs }
    :if ([:len [:tostr ($c->"skipDfs")]] > 0) do={ :set ($cp->"skip-dfs-channels") ($c->"skipDfs") }
    $cfmEnsure m="/interface/wifi/channel" k=("wch:" . $b) n=({"name"=("cfm-" . $b . "g")}) p=$cp
  }
  # Security je Band (z.B. 6 GHz: nur WPA3 mit PMF required): Ein Kanal-Eintrag mit sec/ft/ftOverDs/pmf
  # überschreibt die Werte der SSIDs auf diesem Band -> eigenes Profil cfm-<SSID>-<Band>g (gleiche
  # Passphrase per Secret-Push), für Slave-SSIDs dazu eine eigene Konfiguration gleichen Namens
  :local bov ({})
  :foreach b,c in=($w->"channels") do={
    :foreach f in={"sec";"ft";"ftOverDs";"pmf"} do={ :if ([:len [:tostr ($c->$f)]] > 0) do={ :set ($bov->$b) 1 } }
  }
  # eigene Konfiguration je Band für weitere SSIDs: bei eigener Security (bov) oder eigenem Steering
  :local bcf ({})
  :foreach b,c in=($w->"channels") do={ :if ([:typeof ($bov->$b)] != "nothing" or ($stn->$b) != "cfm-steer") do={ :set ($bcf->$b) 1 } }
  :foreach k,s in=($w->"ssids") do={
    :local o ({})
    :foreach f in={"sec";"ft";"ftOverDs";"pmf";"isolation"} do={
      :set ($o->$f) ($d->$f)
      :if ([:len [:tostr ($s->$f)]] > 0) do={ :set ($o->$f) ($s->$f) }
    }
    :local nm ("cfm-" . $k)
    :local sp ({"name"=$nm;"authentication-types"=($o->"sec");"ft"=($o->"ft");"ft-over-ds"=($o->"ftOverDs");"management-protection"=($o->"pmf")})
    # PPSK (D32): Multi-Passphrase-Gruppe = Name des Profils; entfällt PPSK, wird sie gelöst
    :local pp ([:typeof ($w->"ppsk"->$k)] = "array")
    :if ($pp) do={ :set ($sp->"multi-passphrase-group") $nm }
    $cfmEnsure m="/interface/wifi/security" k=("wsec:" . $k) n=({"name"=$nm}) p=$sp
    :if (!$pp and $cfmDry != true) do={
      :onerror e in={
        :if ([:len [:tostr [/interface/wifi/security/get [find where name=$nm] multi-passphrase-group]]] > 0) do={
          /interface/wifi/security/unset [find where name=$nm] multi-passphrase-group
          $cfmLog ("PPSK-Gruppe an " . $nm . " entfernt")
        }
      } do={}
    }
    # Beim CAPsMAN gehen davon vlan-id und client-isolation an die CAPs; "bridge" gilt nur für
    # eigene Radios, die CAPs hängen ihre Radios selbst an die Bridge (Rolle ap, D41)
    :local dpp ({"name"=$nm;"bridge"="bridge";"vlan-id"=($s->"vlan");"client-isolation"=($o->"isolation")})
    # Isoliertes VLAN (D76): Client-Isolation an, Interfaces in die Liste cfm-iso (dort filtert die Bridge
    # des AP). Ob der CAPsMAN interface-list an die CAPs weitergibt, ist auf Hardware offen; die Rolle ap
    # trägt die Interfaces sonst selbst ein, lokale Datapaths (Fallback) haben die Liste ohnehin
    :local isoS ([:tostr ($cfmVlans->[:tostr ($s->"vlan")]->"isolate")] = "yes")
    :if ($isoS) do={ :set ($dpp->"client-isolation") "yes"; :set ($dpp->"interface-list") "cfm-iso" }
    $cfmEnsure m="/interface/wifi/datapath" k=("wdp:" . $k) n=({"name"=$nm}) p=$dpp
    :if (!$isoS and $cfmDry != true) do={
      :onerror e in={
        :local il [:tostr [/interface/wifi/datapath/get [find where name=$nm] interface-list]]
        :if ([:len $il] > 0 and $il != "none") do={ /interface/wifi/datapath/unset [find where name=$nm] interface-list; $cfmLog ("Datapath " . $nm . ": nicht mehr isoliert") }
      } do={}
    }
    $cfmEnsure m="/interface/wifi/configuration" k=("wcf:" . $k) n=({"name"=$nm}) p=({"name"=$nm;"mode"="ap";"ssid"=($s->"ssid");"country"=($w->"country");"security"=$nm;"datapath"=$nm;"steering"="cfm-steer"})
    :foreach b,c in=($w->"channels") do={
      :if ([:typeof ($bcf->$b)] != "nothing" and ($k = $mk or (("," . ($s->"bands") . ",") ~ ("," . $b . ",")))) do={
        :local bn ($nm . "-" . $b . "g")
        :local bsec $nm
        :if ([:typeof ($bov->$b)] != "nothing") do={
          :set bsec $bn
          :local bp ({"name"=$bn;"authentication-types"=($o->"sec");"ft"=($o->"ft");"ft-over-ds"=($o->"ftOverDs");"management-protection"=($o->"pmf")})
          :foreach f,pn in={"sec"="authentication-types";"ft"="ft";"ftOverDs"="ft-over-ds";"pmf"="management-protection"} do={
            :if ([:len [:tostr ($c->$f)]] > 0) do={ :set ($bp->$pn) ($c->$f) }
          }
          $cfmEnsure m="/interface/wifi/security" k=("wsec:" . $k . "-" . $b) n=({"name"=$bn}) p=$bp
        }
        :if ($k != $mk) do={
          $cfmEnsure m="/interface/wifi/configuration" k=("wcf:" . $k . "-" . $b) n=({"name"=$bn}) p=({"name"=$bn;"mode"="ap";"ssid"=($s->"ssid");"country"=($w->"country");"security"=$bsec;"datapath"=$nm;"steering"=($stn->$b)})
        }
      }
    }
  }
  # PPSK-Einträge: je Passphrase ein VLAN. Angelegt mit Zufallswert, die echte Passphrase kommt per
  # Secret-Push aus dem Vault (ppsk.<ssid>.<name>) – sie steht nie in Daten, Log oder Probelauf.
  :foreach k,ents in=($w->"ppsk") do={
    :foreach e,o in=$ents do={
      :local mp ({"group"=("cfm-" . $k);"vlan-id"=($o->"vlan");"isolation"="no"})
      :if ([:len [:tostr ($o->"isolation")]] > 0) do={ :set ($mp->"isolation") ($o->"isolation") }
      :if ([:len [:tostr ($o->"expires")]] > 0) do={ :set ($mp->"expires") ($o->"expires") }
      $cfmEnsure m="/interface/wifi/security/multi-passphrase" k=("mpp:" . $k . "." . $e) p=$mp a=({"passphrase"=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"]})
    }
  }
  # Master-Konfiguration je Band (trägt den Kanal; Security des Bands, s.o.)
  :local ms ($w->"ssids"->$mk)
  :local msec ({})
  :foreach b,c in=($w->"channels") do={
    :set ($msec->$b) ("cfm-" . $mk)
    :if ([:typeof ($bov->$b)] != "nothing") do={ :set ($msec->$b) ("cfm-" . $mk . "-" . $b . "g") }
  }
  :local mcfg do={
    :global cfmEnsure
    $cfmEnsure m="/interface/wifi/configuration" k=("wcf:" . $key) n=({"name"=$name}) p=({"name"=$name;"mode"="ap";"ssid"=($s->"ssid");"country"=$country;"security"=$sec;"datapath"=("cfm-" . $mk);"steering"=$stg;"channel"=$ch})
  }
  :local pinch do={
    :global cfmEnsure
    :local chn ("cfm-" . $b . "g-" . $apn)
    $cfmEnsure m="/interface/wifi/channel" k=("wch:" . $b . "-" . $apn) n=({"name"=$chn}) p=({"name"=$chn;"band"=($c->"band");"frequency"=$f;"width"=($c->"width")})
    :return $chn
  }
  :if ($loc) do={
    :local cf ({})
    :foreach b,c in=($w->"channels") do={
      :local chn ("cfm-" . $b . "g")
      :local f [:tostr ($w->"radios"->$ap->$b)]
      :if ([:len $f] > 0) do={ :set chn [$pinch b=$b apn=$ap c=$c f=$f] }
      $mcfg key=("l" . $b) name=("cfm-l" . $b) s=$ms mk=$mk country=($w->"country") ch=$chn sec=($msec->$b) stg=($stn->$b)
      :set ($cf->$b) ("cfm-l" . $b)
    }
    :return $cf
  }
  # CAPsMAN: gepinnte APs vor den generischen Regeln
  :local rules ({})
  :foreach apn,pins in=($w->"radios") do={
    :foreach b,f in=$pins do={
      :local chn [$pinch b=$b apn=$apn c=($w->"channels"->$b) f=$f]
      $mcfg key=("m" . $b . "-" . $apn) name=("cfm-m" . $b . "-" . $apn) s=$ms mk=$mk country=($w->"country") ch=$chn sec=($msec->$b) stg=($stn->$b)
      :set ($rules->[:len $rules]) ({"b"=$b;"cfg"=("cfm-m" . $b . "-" . $apn);"re"=("^" . $apn . "\$")})
    }
  }
  :foreach b,c in=($w->"channels") do={
    $mcfg key=("m" . $b) name=("cfm-m" . $b) s=$ms mk=$mk country=($w->"country") ch=("cfm-" . $b . "g") sec=($msec->$b) stg=($stn->$b)
    :set ($rules->[:len $rules]) ({"b"=$b;"cfg"=("cfm-m" . $b);"re"=""})
  }
  # MLO (Wi-Fi 7): Standard aus - ein MLD bietet kein FT an ("MLO does not support Fast Transition"),
  # Clients im FT-Verbund mieden deshalb die Wi-Fi-7-APs; außerdem gibt es nur ein mld-datapath je CAP
  # (VLAN der Master-SSID), weitere SSIDs landeten per MLO dort. multi-link-mode kennt nicht jede
  # RouterOS-Version: Probe gegen eine Regel, die es nicht gibt ("no such item" = Parameter bekannt).
  :local mlm [:tostr ($w->"mlo")]
  :if ([:len $mlm] = 0) do={ :set mlm "disabled" }
  :local mlOk true
  :onerror e in={
    :local f [:parse ("/interface/wifi/provisioning/set *FFFFFF multi-link-mode=" . $mlm)]
    $f
  } do={ :if ($e ~ "bad parameter") do={ :set mlOk false } }
  :local pl ({})
  # Schaltbare SSIDs (D64): stehen seit D90 immer in den Regeln, mit festen Interfaces (create-enabled);
  # geschaltet werden ihre Interfaces am CAPsMAN (Skripte cfm-ssid-<key>-on/-off, $cfmCapsmanOn).
  # cfmSsidSw = Menge der schaltbaren Schlüssel
  :global cfmSsidSw; :set cfmSsidSw ({})
  :foreach k,s in=($w->"ssids") do={
    :if ($k != $mk and [:len [:tostr ($s->"switch")]] > 0) do={ :set ($cfmSsidSw->$k) 1 }
  }
  :foreach r in=$rules do={
    :local b ($r->"b")
    :local sl ({})
    # schaltbare SSIDs immer hinter den festen: so behalten die virtuellen Interfaces der übrigen ihre
    # Nummern (Home Assistant ordnet Clients nach Interfaces zu, Befund 2026-10-14)
    :foreach sw in={false;true} do={
      :foreach k,s in=($w->"ssids") do={
        :if ($k != $mk and ([:typeof ($cfmSsidSw->$k)] != "nothing") = $sw and (("," . ($s->"bands") . ",") ~ ("," . $b . ","))) do={
          :local cn ("cfm-" . $k)
          :if ([:typeof ($bcf->$b)] != "nothing") do={ :set cn ("cfm-" . $k . "-" . $b . "g") }
          :set ($sl->[:len $sl]) $cn
        }
      }
    }
    # Feste Interfaces (create-enabled, D90): Anders als dynamische lassen sie sich einzeln ab- und
    # anschalten - eine SSID schaltet so, ohne alle Radios neu zu provisionieren. Interface-Namen aus
    # Identity und Band (z.B. ap1-2g) statt cap-wifiN - so ist in Registration-Tabelle und Monitoring der
    # AP erkennbar (D47)
    :local pr ({"action"="create-enabled";"supported-bands"=($w->"channels"->$b->"band");"master-configuration"=($r->"cfg");"slave-configurations"=$sl;"name-format"=("%I-" . $b . "g")})
    :if ($mlOk) do={ :set ($pr->"multi-link-mode") $mlm }
    :if ([:len ($r->"re")] > 0) do={ :set ($pr->"identity-regexp") ($r->"re") }
    :set ($pl->[:len $pl]) $pr
  }
  :return $pl
}

# Master-SSID ohne Passphrase (Profil neu angelegt: CAPsMAN nach einem Umzug, lokaler Fallback der
# APs)? Dann die Secrets als veraltet markieren – der Manager schiebt beim nächsten Tick alle PSKs aus
# dem Vault nach ($cfmSecretSync vergleicht die gemeldete Vault-Version). Nur die Master-SSID zählt:
# Fehlt für eine andere SSID die PSK im Vault, meldet das $cfmCheck. Liefert true, wenn sie fehlt.
:global cfmPskMissing do={
  :global cfmDry; :global cfmLog; :global cfmWifi
  :if ($cfmDry = true) do={ :return false }
  :local nm ("cfm-" . [:tostr ($cfmWifi->"master")])
  :local miss false
  :onerror e in={
    # samt der Profile je Band (cfm-<SSID>-<Band>g, z.B. 6 GHz)
    :foreach i in=[/interface/wifi/security/find where (name=$nm or name~("^" . $nm . "-[0-9]+g\$"))] do={
      :if ([:len [:tostr [/interface/wifi/security/get $i passphrase]]] = 0) do={ :set miss true }
    }
  } do={}
  :if ($miss) do={
    :onerror e in={ /ppp/secret/set [find where name="cfm:key"] comment="cfm-sys:key sv=0" } do={}
    $cfmLog ("WLAN-Passphrase fehlt (" . $nm . ") - Secret-Push angefordert")
  }
  :return $miss
}

# CAPsMAN rendern und einschalten (Rolle capsman bzw. übergangsweise der Primary-Manager, D45).
# Ohne Passphrasen bliebe der Dienst an, die APs verteilten aber SSIDs, an denen sich niemand anmelden
# kann – deshalb erst einschalten, wenn der Secret-Push sie gesetzt hat (er schaltet ihn dann selbst
# ein). Bis dahin senden die APs mit ihrer lokalen Kopie weiter (D46).
:global cfmCapsmanOn do={
  :global cfmG; :global cfmWifiRender; :global cfmBlock; :global cfmSet; :global cfmPskMissing; :global cfmWarn; :global cfmEnsure
  :local pl [$cfmWifiRender]
  $cfmBlock m="/interface/wifi/provisioning" k="wprov" l=$pl
  :local en "yes"
  :if ([$cfmPskMissing]) do={
    :set en "no"
    $cfmWarn "CAPsMAN bleibt aus, bis der Secret-Push die WLAN-Passphrasen gesetzt hat"
  }
  $cfmSet m="/interface/wifi/capsman" p=({"enabled"=$en;"interfaces"=("vlan" . [:tostr ($cfmG->"mgmtVlan")]);"certificate"="auto";"ca-certificate"="auto";"require-peer-certificate"="no";"upgrade-policy"="none"})
  # Schaltbare SSIDs (D64, D90): Jede SSID mit "switch" hat feste Interfaces (Regeln mit create-enabled).
  # Die Skripte cfm-ssid-<key>-on/-off schalten nur deren Interfaces ab bzw. an - an allen CAPs und den
  # eigenen Radios; neu provisioniert wird dabei nichts. Zustand in <cfm>/ssid-<key>.txt, den jeder Apply
  # und cfm-ssid-check (alle 10 min, auch Auto-Aus) an den Interfaces durchsetzen - auch an denen eines neu
  # verbundenen CAP, die eingeschaltet entstehen. dont-require-permissions: der API-User aus capsmanApi
  # (Gruppe read,api,test) darf die Skripte starten, ohne selbst schreiben zu dürfen. :global
  # cfmSsid<key> ("on"/"off") gilt für die Konsole, HA liest Interfaces und Datei
  # (tools/home-assistant/cfm_ssid.py). Übergang von den dynamischen Interfaces vor D90: Gibt es noch
  # welche, provisioniert das erste Schalten die CAP-Radios einmal neu (~3 s ohne WLAN, früher jedes Mal).
  :global cfmSsidSw; :global cfmSsidState; :global cfmDir; :global cfmWifi; :global cfmDry; :global cfmLog
  :global cfmStat
  :local ck ""
  :foreach k,x in=$cfmSsidSw do={
    :local s ($cfmWifi->"ssids"->$k)
    :local sf ($cfmDir . "/ssid-" . $k . ".txt")
    # Interfaces der SSID: Konfiguration cfm-<key> bzw. je Band cfm-<key>-<Band>g (Schlüssel nur a-z0-9)
    :local sel ("!dynamic and (configuration=\"cfm-" . $k . "\" or configuration~\"^cfm-" . $k . "-[0-9]+g\")")
    :local aos 0
    :if ([:len [:tostr ($s->"autoOff")]] > 0) do={ :set aos ([:tonsec [:totime ($s->"autoOff")]] / 1000000000) }
    :foreach act in={"on";"off"} do={
      :local dis "no"
      :if ($act = "off") do={ :set dis "yes" }
      :local src ("# cfm (Rolle capsman, D64/D90): SSID " . ($s->"ssid") . " " . $act . " - für Home Assistant, jeder Apply schreibt es neu\n")
      :set src ($src . ":local st \"" . $act . "\"\n")
      :set src ($src . ":if ([:len [/interface/wifi/find where dynamic and configuration~\"^cfm-\"]] > 0) do={ /interface/wifi/radio/provision [find where !local]; :delay 8s }\n")
      :set src ($src . ":foreach i in=[/interface/wifi/find where " . $sel . "] do={ /interface/wifi/set \$i disabled=" . $dis . " }\n")
      :set src ($src . ":local v \$st\n:if (\$st = \"on\" and " . $aos . " > 0) do={ :set v (\"on \" . (([:tonsec [:timestamp]] / 1000000000) + " . $aos . ")) }\n")
      :set src ($src . ":onerror e in={ /file/set \"" . $sf . "\" contents=\$v } do={ /file/add name=\"" . $sf . "\" contents=\$v }\n")
      :set src ($src . ":global cfmSsid" . $k . "; :set cfmSsid" . $k . " \$st\n")
      :set src ($src . ":log info (\"cfm: SSID " . ($s->"ssid") . " \" . \$st)\n")
      $cfmEnsure m="/system/script" k=("sys:ssid-" . $k . "-" . $act) n=({"name"=("cfm-ssid-" . $k . "-" . $act)}) p=({"name"=("cfm-ssid-" . $k . "-" . $act);"source"=$src;"policy"="ftp,read,write,test";"dont-require-permissions"="yes"})
    }
    # Prüfung: Zustand aus der Datei (ohne Datei der Grundzustand), Auto-Aus nach autoOff, dann den Zustand an
    # den Interfaces durchsetzen
    :local df [:tostr ($s->"switch")]
    :set ck ($ck . ":local c" . $k . " \"\"\n:onerror e in={ :set c" . $k . " [/file/get \"" . $sf . "\" contents] } do={}\n")
    :set ck ($ck . ":global cfmSsid" . $k . "\n:set cfmSsid" . $k . " \"" . $df . "\"\n")
    :set ck ($ck . ":if ([:pick \$c" . $k . " 0 2] = \"on\") do={ :set cfmSsid" . $k . " \"on\" }\n:if ([:pick \$c" . $k . " 0 3] = \"off\") do={ :set cfmSsid" . $k . " \"off\" }\n")
    :if ($aos > 0) do={
      :set ck ($ck . ":local p" . $k . " [:find \$c" . $k . " \" \"]\n")
      :set ck ($ck . ":if ([:pick \$c" . $k . " 0 2] = \"on\" and [:typeof \$p" . $k . "] = \"num\") do={ :if ([:tonum [:pick \$c" . $k . " (\$p" . $k . " + 1) [:len \$c" . $k . "]]] <= \$now) do={ /system/script/run cfm-ssid-" . $k . "-off; :set cfmSsid" . $k . " \"off\" } }\n")
    }
    :set ck ($ck . ":local w" . $k . " \"no\"\n:if (\$cfmSsid" . $k . " = \"off\") do={ :set w" . $k . " \"yes\" }\n")
    :set ck ($ck . ":foreach i in=[/interface/wifi/find where " . $sel . "] do={ :if ([/interface/wifi/get \$i disabled] != (\$cfmSsid" . $k . " = \"off\")) do={ /interface/wifi/set \$i disabled=\$w" . $k . " } }\n")
    # Zustand gleich jetzt setzen: Variable für die Konsole und die Interfaces (Probelauf: nur melden)
    :local st [$cfmSsidState $k]
    :local fs [:parse (":global cfmSsid" . $k . "; :set cfmSsid" . $k . " \"" . $st . "\"")]
    $fs
    :local dis "no"
    :if ($st = "off") do={ :set dis "yes" }
    :local ff [:parse (":return [/interface/wifi/find where " . $sel . "]")]
    :foreach i in=[$ff] do={
      :if ([/interface/wifi/get $i disabled] != ($st = "off")) do={
        :local nm [/interface/wifi/get $i name]
        :if ($cfmDry = true) do={ $cfmLog ("SSID " . ($s->"ssid") . " " . $st . ": Interface " . $nm . " würde geschaltet") } else={
          /interface/wifi/set $i disabled=$dis
          $cfmLog ("SSID " . ($s->"ssid") . " " . $st . ": Interface " . $nm . " geschaltet")
        }
        :set ($cfmStat->"set") (($cfmStat->"set") + 1)
      }
    }
  }
  # Nicht mehr schaltbar ("switch" entfernt), Zustandsdatei noch da: Die SSID gilt wieder fest - abgeschaltete
  # Interfaces einschalten, Datei weg (sonst blieben die festen Interfaces einer zuletzt ausgeschalteten aus)
  :foreach k,s in=($cfmWifi->"ssids") do={
    :local sf ($cfmDir . "/ssid-" . $k . ".txt")
    :local ex false
    :if ([:typeof ($cfmSsidSw->$k)] = "nothing") do={ :onerror e in={ :set ex ([:len [/file/get $sf name]] > 0) } do={} }
    :if ($ex) do={
      :local ff [:parse (":return [/interface/wifi/find where !dynamic and disabled and (configuration=\"cfm-" . $k . "\" or configuration~\"^cfm-" . $k . "-[0-9]+g\")]")]
      :local n 0
      :foreach i in=[$ff] do={
        :if ($cfmDry != true) do={ /interface/wifi/set $i disabled=no }
        :set n ($n + 1)
      }
      :if ($cfmDry != true) do={ /file/remove $sf }
      $cfmLog ("SSID " . [:tostr ($s->"ssid")] . " nicht mehr schaltbar: " . $n . " Interfaces eingeschaltet, Zustandsdatei entfernt")
    }
  }
  :if ([:len $ck] > 0) do={
    :set ck ("# cfm (Rolle capsman, D64/D90): Zustand der schaltbaren SSIDs für Home Assistant, Auto-Aus, Interfaces\n:local now ([:tonsec [:timestamp]] / 1000000000)\n" . $ck)
    $cfmEnsure m="/system/script" k="sys:ssid-check" n=({"name"="cfm-ssid-check"}) p=({"name"="cfm-ssid-check";"source"=$ck;"policy"="ftp,read,write,test"})
    $cfmEnsure m="/system/scheduler" k="sys:ssid-check" n=({"name"="cfm-ssid-check"}) p=({"name"="cfm-ssid-check";"interval"="10m";"start-time"="startup";"on-event"="/system/script/run cfm-ssid-check";"disabled"="no"})
  }
  # Eigene Radios (TODO 24, D53): Ein CAPsMAN verwaltet sich laut MikroTik nicht selbst als CAP, kann
  # seine Radios aber über /interface/wifi/radio/provision mit denselben Regeln provisionieren
  # (Profile, Pins, virtuelle APs; der Datapath trägt "bridge" für genau diesen Fall). Hostfile
  # capsmanRadios="yes". Neu provisioniert wird nur, wenn sich WLAN-Daten oder Regeln geändert haben
  # (kurzer Aussetzer nur der eigenen Radios); der Stand steht in <cfm>/wifi-local.txt. Schalter
  # wieder aus: cfm-Regeln kurz abschalten und neu provisionieren -> Radios unkonfiguriert (Doku).
  :global cfmHost
  :local lr ([:tostr ($cfmHost->"capsmanRadios")] = "yes")
  :local sf ($cfmDir . "/wifi-local.txt")
  :local old ""
  :onerror e in={ :set old [/file/get $sf contents] } do={}
  :local nr 0
  :onerror e in={ :set nr [:len [/interface/wifi/radio/find where local]] } do={}
  :if ($nr > 0 and ($lr or [:len $old] > 0)) do={
    :local h ""
    :if ($lr and $en = "yes") do={ :set h [:convert ([:serialize to=json $cfmWifi] . [:serialize to=json $pl]) transform=md5 to=hex] }
    :if ($lr and $en != "yes") do={ :set h $old }
    :if ($h != $old) do={
      :if ($cfmDry = true) do={
        :if ($lr) do={ $cfmLog ("eigene Radios (" . $nr . ") würden über den eigenen CAPsMAN provisioniert") } else={ $cfmLog ("eigene Radios (" . $nr . ") würden zurückgesetzt (capsmanRadios aus)") }
      } else={
        :if ($lr) do={
          # Wi-Fi 7 (hAP be³): ab Werk hängen die Radios am statischen, abgeschalteten MLD - ohne MLO
          # blieben sie aus ("mld-interface not enabled"), wie bei den APs (D46) lösen
          :if ([:len [:tostr ($cfmWifi->"mlo")]] = 0 or [:tostr ($cfmWifi->"mlo")] = "disabled") do={
            :local smld false
            :foreach x in=[/interface/wifi/find where !dynamic] do={ :if ([:len [:tostr ([/interface/wifi/get $x]->"mld-name")]] > 0) do={ :set smld true } }
            :if ($smld) do={ :foreach i in=[/interface/wifi/find where default-name~"^wifi" and !dynamic] do={ :onerror e in={ /interface/wifi/unset $i value-name=mld-interface } do={} } }
          }
          /interface/wifi/radio/provision [find where local]
          :if ([:len $old] = 0) do={ /file/add name=$sf contents=$h } else={ /file/set $sf contents=$h }
          $cfmLog ("eigene Radios (" . $nr . ") über den eigenen CAPsMAN provisioniert")
          # Schaltbare SSIDs (D90): Die eigenen Radios haben jetzt neue feste Interfaces, alle eingeschaltet -
          # den Schaltzustand gleich durchsetzen, nicht erst mit dem nächsten cfm-ssid-check (bis zu 10 min)
          :if ([:len $cfmSsidSw] > 0) do={ :delay 3s; :onerror e in={ /system/script/run [find name="cfm-ssid-check"] } do={} }
        } else={
          :local on [/interface/wifi/provisioning/find where comment~"^cfm:" and !disabled]
          /interface/wifi/provisioning/disable $on
          :delay 1s
          /interface/wifi/radio/provision [find where local]
          :delay 1s
          /interface/wifi/provisioning/enable $on
          /file/remove $sf
          $cfmLog ("eigene Radios (" . $nr . ") zurückgesetzt (capsmanRadios aus)")
        }
      }
    }
  }
  # Lese-Zugang per API (D47): Gruppe read,api,test, User (Passwort per Secret-Push aus dem Vault,
  # user.<name>; bis dahin abgeschaltet), Freigabe in local-input nur für capsmanApi.from. Den
  # Dienst selbst öffnet base. Zieht der CAPsMAN um, räumt die GC das alte Gerät auf.
  :local capi ($cfmG->"capsmanApi")
  :if ([:typeof $capi] = "array") do={
    :if ([:len ($capi->"from")] > 0) do={
      :local au [:tostr ($capi->"user")]
      :if ([:len $au] = 0) do={ :set au "homeassistant" }
      :local ap [:tostr ($capi->"port")]
      :if ([:len $ap] = 0) do={ :set ap "8728" }
      $cfmEnsure m="/user/group" k="grp:api" n=({"name"="cfm-api"}) p=({"name"="cfm-api";"policy"="read,api,test"})
      $cfmEnsure m="/user" k=("user:" . $au) n=({"name"=$au}) p=({"name"=$au;"group"="cfm-api"}) a=({"password"=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"];"disabled"="yes"})
      :local fl ({})
      :foreach a in=($capi->"from") do={ :set ($fl->[:len $fl]) ({"chain"="local-input";"action"="accept";"protocol"="tcp";"dst-port"=$ap;"src-address"=$a}) }
      $cfmBlock m="/ip/firewall/filter" k="capi" l=$fl
    }
  }
  :return true
}
