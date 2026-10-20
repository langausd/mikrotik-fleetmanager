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
  # schaltbare SSIDs (D64): im Zustand "off" nicht in den Regeln; je Regel (Schlüssel wie $cfmBlock:
  # wprov:00, wprov:01 …) merkt cfmSsidSw den Namen der Konfiguration für die Schalt-Skripte
  :global cfmSsidSw; :set cfmSsidSw ({})
  :global cfmSsidState
  :local son ({})
  :foreach k,s in=($w->"ssids") do={
    :if ($k != $mk and [:len [:tostr ($s->"switch")]] > 0) do={ :set ($cfmSsidSw->$k) ({}); :set ($son->$k) [$cfmSsidState $k] }
  }
  # Für die Schalt-Skripte zusätzlich die Regeln jeder Kombination der Schaltzustände (Schlüssel "c" plus
  # je schaltbarer SSID in Schlüsselreihenfolge 1/0): Signatur wie $cfmBlock und Merker der eigenen Radios
  # (wifi-local.txt). Die Skripte setzen beide nach dem Schalten, sonst gälte ein Schalten beim nächsten
  # Apply als Änderung (Regelblock neu, eigene Radios neu provisioniert). Ab 5 schaltbaren SSIDs
  # (32 Kombinationen) nicht mehr - dann bleibt es dort beim Neuaufbau.
  :global cfmSsidSig; :set cfmSsidSig ({})
  :local nsw [:len $cfmSsidSw]
  :local cmax -1
  :if ($nsw > 0 and $nsw < 5) do={ :set cmax ((1 << $nsw) - 1) }
  :local wj [:serialize to=json $w]
  :for c from=-1 to=$cmax do={
    :local stc $son
    :local cb "c"
    :if ($c >= 0) do={
      :set stc ({})
      :local j 0
      :foreach k,x in=$cfmSsidSw do={
        :if ((($c >> $j) & 1) = 1) do={ :set ($stc->$k) "on"; :set cb ($cb . "1") } else={ :set ($stc->$k) "off"; :set cb ($cb . "0") }
        :set j ($j + 1)
      }
    }
    :local lst ({})
    :foreach r in=$rules do={
      :local b ($r->"b")
      :local sl ({})
      :local rk ("wprov:" . [:pick [:tostr (100 + [:len $lst])] 1 3])
      # schaltbare SSIDs immer hinter den festen (wie im Skript cfm-ssid-<key>-on): Schalten verschiebt
      # sonst die Nummern der übrigen virtuellen Interfaces, und Home Assistant verliert die Zuordnung
      :foreach sw in={false;true} do={
        :foreach k,s in=($w->"ssids") do={
          :if ($k != $mk and ([:typeof ($cfmSsidSw->$k)] = "array") = $sw and (("," . ($s->"bands") . ",") ~ ("," . $b . ","))) do={
            :local cn ("cfm-" . $k)
            :if ([:typeof ($bcf->$b)] != "nothing") do={ :set cn ("cfm-" . $k . "-" . $b . "g") }
            :if ($sw) do={ :set ($cfmSsidSw->$k->$rk) $cn }
            :if ([:tostr ($stc->$k)] != "off") do={ :set ($sl->[:len $sl]) $cn }
          }
        }
      }
      # Interface-Namen aus Identity und Band (z.B. ap1-2g) statt cap-wifiN, das sich bei jeder
      # Neuverbindung verschiebt - so ist in Registration-Tabelle und Monitoring der AP erkennbar (D47)
      :local pr ({"action"="create-dynamic-enabled";"supported-bands"=($w->"channels"->$b->"band");"master-configuration"=($r->"cfg");"slave-configurations"=$sl;"name-format"=("%I-" . $b . "g")})
      :if ($mlOk) do={ :set ($pr->"multi-link-mode") $mlm }
      :if ([:len ($r->"re")] > 0) do={ :set ($pr->"identity-regexp") ($r->"re") }
      :set ($lst->[:len $lst]) $pr
    }
    :if ($c < 0) do={ :set pl $lst } else={
      :set ($cfmSsidSig->$cb) ({[:convert [:tostr $lst] transform=md5 to=hex];[:convert ($wj . [:serialize to=json $lst]) transform=md5 to=hex]})
    }
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
  # Schaltzustand (D64) gegen die Regeln auf dem Gerät: Weicht er ab (Regel von Hand geändert, Grundzustand
  # in wifi.rsc ohne Zustandsdatei geändert), startet der Apply unten das Schalt-Skript - wie ein Schalten
  # aus Home Assistant, samt Neu-Provisionierung der APs. Nur Regeln mit derselben Nummer und Master-
  # Konfiguration (verschobene Nummern baut $cfmBlock ohnehin neu).
  :global cfmSsidSw; :global cfmSsidState
  :local swFix ({})
  :foreach k,mp in=$cfmSsidSw do={
    :local st [$cfmSsidState $k]
    :foreach i,pr in=$pl do={
      :local rk ("wprov:" . [:pick [:tostr (100 + $i)] 1 3])
      :local cn [:tostr ($mp->$rk)]
      :if ([:len $cn] > 0) do={
        :foreach id in=[/interface/wifi/provisioning/find where comment~("^cfm:" . $rk . "( |\$)") and master-configuration=($pr->"master-configuration")] do={
          :local has false
          :foreach x in=[/interface/wifi/provisioning/get $id slave-configurations] do={ :if ([:tostr $x] = $cn) do={ :set has true } }
          :if ($has != ($st != "off")) do={ :set ($swFix->$k) $st }
        }
      }
    }
  }
  $cfmBlock m="/interface/wifi/provisioning" k="wprov" l=$pl
  :local en "yes"
  :if ([$cfmPskMissing]) do={
    :set en "no"
    $cfmWarn "CAPsMAN bleibt aus, bis der Secret-Push die WLAN-Passphrasen gesetzt hat"
  }
  $cfmSet m="/interface/wifi/capsman" p=({"enabled"=$en;"interfaces"=("vlan" . [:tostr ($cfmG->"mgmtVlan")]);"certificate"="auto";"ca-certificate"="auto";"require-peer-certificate"="no";"upgrade-policy"="none"})
  # Schaltbare SSIDs (D64): Skripte cfm-ssid-<key>-on/-off nehmen die SSID in die Provisioning-Regeln
  # auf bzw. heraus und provisionieren die CAP-Radios neu (alle SSIDs eines APs ~3 s weg); Zustand in
  # <cfm>/ssid-<key>.txt, den der nächste Apply übernimmt. dont-require-permissions: der API-User aus
  # capsmanApi (Gruppe read,api,test) darf sie starten, ohne selbst schreiben zu dürfen. cfm-ssid-check
  # (alle 10 min) schaltet nach autoOff ab und hält :global cfmSsid<key> ("on"/"off") für die Konsole –
  # nicht für HA: die API zeigt globale Variablen nur mit write+policy, ein API-Lauf ändert sie nicht
  # (HA liest Regeln und Datei, tools/home-assistant/cfm_ssid.py).
  :global cfmSsidSw; :global cfmSsidState; :global cfmDir; :global cfmWifi; :global cfmSsidSig
  # Nach dem Schalten Signatur von wprov und Merker der eigenen Radios auf die neue Kombination der
  # Schaltzustände setzen (Tabelle aus $cfmWifiRender; Zustand je SSID wie $cfmSsidState aus der Datei)
  :local sgsrc ""
  :if ([:len $cfmSsidSig] > 0) do={
    :local sm ""
    :foreach cb,x in=$cfmSsidSig do={ :set sm ($sm . ";\"" . $cb . "\"={\"" . ($x->0) . "\";\"" . ($x->1) . "\"}") }
    :set sgsrc (":local cb \"c\"\n")
    :foreach kk,x in=$cfmSsidSw do={
      :local db "1"
      :if ([:tostr ($cfmWifi->"ssids"->$kk->"switch")] = "off") do={ :set db "0" }
      :set sgsrc ($sgsrc . ":do { :local b \"" . $db . "\"; :local c \"\"; :onerror e in={ :set c [/file/get \"" . $cfmDir . "/ssid-" . $kk . ".txt\" contents] } do={}; :if ([:pick \$c 0 2] = \"on\") do={ :set b \"1\" }; :if ([:pick \$c 0 3] = \"off\") do={ :set b \"0\" }; :set cb (\$cb . \$b) }\n")
    }
    :set sgsrc ($sgsrc . ":local sg ({" . [:pick $sm 1 [:len $sm]] . "})\n:local lh \"\"\n")
    :set sgsrc ($sgsrc . ":if ([:typeof (\$sg->\$cb)] = \"array\") do={\n  :set lh (\$sg->\$cb->1)\n")
    :set sgsrc ($sgsrc . "  :foreach i in=[/interface/wifi/provisioning/find where comment~\"^cfm:wprov:00 sig=\"] do={ /interface/wifi/provisioning/set \$i comment=(\"cfm:wprov:00 sig=\" . (\$sg->\$cb->0)) }\n}\n")
  }
  :local ck ""
  :foreach k,mp in=$cfmSsidSw do={
    :local s ($cfmWifi->"ssids"->$k)
    :local sf ($cfmDir . "/ssid-" . $k . ".txt")
    :local aos 0
    :if ([:len [:tostr ($s->"autoOff")]] > 0) do={ :set aos ([:tonsec [:totime ($s->"autoOff")]] / 1000000000) }
    :local am ""
    :foreach rk,cn in=$mp do={ :set am ($am . ";\"" . $rk . "\"=\"" . $cn . "\"") }
    :set am ("({" . [:pick $am 1 [:len $am]] . "})")
    :foreach act in={"on";"off"} do={
      :local src ("# cfm (Rolle capsman, D64): SSID " . ($s->"ssid") . " " . $act . " - für Home Assistant, jeder Apply schreibt es neu\n")
      :set src ($src . ":local st \"" . $act . "\"\n:local add " . $am . "\n")
      :set src ($src . ":foreach id in=[/interface/wifi/provisioning/find where comment~\"^cfm:wprov:\"] do={\n")
      :set src ($src . "  :local c [:tostr [/interface/wifi/provisioning/get \$id comment]]\n")
      :set src ($src . "  :local nm [:tostr (\$add->[:pick \$c 4 [:find (\$c . \" \") \" \"]])]\n")
      :set src ($src . "  :if ([:len \$nm] > 0) do={\n    :local nl ({})\n")
      :set src ($src . "    :foreach x in=[/interface/wifi/provisioning/get \$id slave-configurations] do={ :if ([:tostr \$x] != \$nm) do={ :set (\$nl->[:len \$nl]) [:tostr \$x] } }\n")
      :set src ($src . "    :if (\$st = \"on\") do={ :set (\$nl->[:len \$nl]) \$nm }\n")
      :set src ($src . "    :if ([:len \$nl] = 0) do={ /interface/wifi/provisioning/set \$id slave-configurations=\"\" } else={ /interface/wifi/provisioning/set \$id slave-configurations=\$nl }\n  }\n}\n")
      :set src ($src . ":local v \$st\n:if (\$st = \"on\" and " . $aos . " > 0) do={ :set v (\"on \" . (([:tonsec [:timestamp]] / 1000000000) + " . $aos . ")) }\n")
      :set src ($src . ":onerror e in={ /file/set \"" . $sf . "\" contents=\$v } do={ /file/add name=\"" . $sf . "\" contents=\$v }\n")
      :set src ($src . $sgsrc)
      :set src ($src . ":global cfmSsid" . $k . "; :set cfmSsid" . $k . " \$st\n:delay 1s\n/interface/wifi/radio/provision [find where !local]\n")
      # eigene Radios des CAPsMAN (capsmanRadios, D53; Merker wifi-local.txt) ebenfalls neu provisionieren
      # und den Merker nachführen
      :local lhs ""
      :if ([:len $sgsrc] > 0) do={ :set lhs ("; :if ([:len \$lh] > 0) do={ /file/set \"" . $cfmDir . "/wifi-local.txt\" contents=\$lh }") }
      :set src ($src . ":onerror e in={ :local x [/file/get \"" . $cfmDir . "/wifi-local.txt\" name]; /interface/wifi/radio/provision [find where local]" . $lhs . " } do={}\n")
      :set src ($src . ":log info (\"cfm: SSID " . ($s->"ssid") . " \" . \$st)\n")
      $cfmEnsure m="/system/script" k=("sys:ssid-" . $k . "-" . $act) n=({"name"=("cfm-ssid-" . $k . "-" . $act)}) p=({"name"=("cfm-ssid-" . $k . "-" . $act);"source"=$src;"policy"="ftp,read,write,test";"dont-require-permissions"="yes"})
    }
    # Prüfung: Zustand für die Konsole aus der Datei (ohne Datei der Grundzustand), Auto-Aus nach autoOff
    :local df [:tostr ($s->"switch")]
    :set ck ($ck . ":local c" . $k . " \"\"\n:onerror e in={ :set c" . $k . " [/file/get \"" . $sf . "\" contents] } do={}\n")
    :set ck ($ck . ":global cfmSsid" . $k . "\n:set cfmSsid" . $k . " \"" . $df . "\"\n")
    :set ck ($ck . ":if ([:pick \$c" . $k . " 0 2] = \"on\") do={ :set cfmSsid" . $k . " \"on\" }\n:if ([:pick \$c" . $k . " 0 3] = \"off\") do={ :set cfmSsid" . $k . " \"off\" }\n")
    :if ($aos > 0) do={
      :set ck ($ck . ":local p" . $k . " [:find \$c" . $k . " \" \"]\n")
      :set ck ($ck . ":if ([:pick \$c" . $k . " 0 2] = \"on\" and [:typeof \$p" . $k . "] = \"num\") do={ :if ([:tonum [:pick \$c" . $k . " (\$p" . $k . " + 1) [:len \$c" . $k . "]]] <= \$now) do={ /system/script/run cfm-ssid-" . $k . "-off } }\n")
    }
    # Zustand gleich jetzt setzen (sonst erst nach dem ersten Prüflauf)
    :local fs [:parse (":global cfmSsid" . $k . "; :set cfmSsid" . $k . " \"" . [$cfmSsidState $k] . "\"")]
    $fs
  }
  :if ([:len $ck] > 0) do={
    :set ck ("# cfm (Rolle capsman, D64): Zustand der schaltbaren SSIDs für Home Assistant, Auto-Aus\n:local now ([:tonsec [:timestamp]] / 1000000000)\n" . $ck)
    $cfmEnsure m="/system/script" k="sys:ssid-check" n=({"name"="cfm-ssid-check"}) p=({"name"="cfm-ssid-check";"source"=$ck;"policy"="ftp,read,write,test"})
    $cfmEnsure m="/system/scheduler" k="sys:ssid-check" n=({"name"="cfm-ssid-check"}) p=({"name"="cfm-ssid-check";"interval"="10m";"start-time"="startup";"on-event"="/system/script/run cfm-ssid-check";"disabled"="no"})
  }
  # Regeln passten nicht zum Schaltzustand (oben vor $cfmBlock ermittelt): Schalt-Skript starten
  :global cfmDry; :global cfmLog
  :foreach k,st in=$swFix do={
    :local sn ("cfm-ssid-" . $k . "-" . $st)
    :local sd ("SSID " . ($cfmWifi->"ssids"->$k->"ssid") . ": Regeln passen nicht zum Zustand " . $st)
    :if ($cfmDry = true) do={ $cfmLog ($sd . " - würde " . $sn . " starten (APs ~3 s weg)") } else={
      /system/script/run [find name=$sn]
      $cfmLog ($sd . " - " . $sn . " gestartet")
    }
  }
  # Eigene Radios (TODO 24, D53): Ein CAPsMAN verwaltet sich laut MikroTik nicht selbst als CAP, kann
  # seine Radios aber über /interface/wifi/radio/provision mit denselben Regeln provisionieren
  # (Profile, Pins, virtuelle APs; der Datapath trägt "bridge" für genau diesen Fall). Hostfile
  # capsmanRadios="yes". Neu provisioniert wird nur, wenn sich WLAN-Daten oder Regeln geändert haben
  # (kurzer Aussetzer nur der eigenen Radios); der Stand steht in <cfm>/wifi-local.txt. Schalter
  # wieder aus: cfm-Regeln kurz abschalten und neu provisionieren -> Radios unkonfiguriert (Doku).
  :global cfmHost; :global cfmDir; :global cfmWifi; :global cfmDry; :global cfmLog
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
