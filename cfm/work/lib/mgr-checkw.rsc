# ============================================================
# cfm lib/mgr-checkw.rsc – Manager-Funktionen: WLAN-Teil der inhaltlichen Prüfung
#   $cfmCheckWifi inv=<inventar>   prüft wifi.rsc (SSIDs, 6 GHz, PPSK, Pinning/Pools/txPower, andere Funknetze,
#                                  Steering, Fallback, DFS) -> {"err"={..};"warn"={..};"note"={..}}
#   Aufruf nur aus $cfmCheck (lib/mgr-check.rsc), nachdem der die Daten geladen hat. Eigene Datei,
#   weil /file get nur ca. 60 KB liest (TODO 73, DM1.1); $cfmCheck lädt sie aus demselben Stand nach.
# ============================================================

:global cfmCheckWifi do={
  :global cfmWifi; :global cfmVlans; :global cfmProfiles; :global cfmVaultGet
  :local err ({}); :local warn ({}); :local note ({})
  # Geräte mit Radios im WLAN: Rolle ap oder capsman, dazu die CAPsMAN-Geräte nach $cfmCapsmen (ohne Gerät mit
  # Rolle capsman der Manager, der mit capsmanRadios mitfunkt; TODO 95)
  :global cfmCapsmen
  :local radio ({})
  :foreach n,d in=$inv do={ :if (("," . [:tostr ($d->"role")] . ",") ~ ",(ap|capsman),") do={ :set ($radio->$n) 1 } }
  :foreach c in=[$cfmCapsmen $inv] do={ :set ($radio->[:tostr ($c->"n")]) 1 }
  # Liegt VLAN v in der Spezifikation ("*", Zonen, VIDs, "!x")? (wie in $cfmCheck)
  :local inSpec do={
    :global cfmVlans
    :local z [:tostr ($cfmVlans->$v->"zone")]
    :local r false
    :foreach t in=[:toarray $1] do={
      :local x [:tostr $t]
      :if ($x = "*" or $x = $v or $x = $z) do={ :set r true }
      :if ($x = ("!" . $v) or $x = ("!" . $z)) do={ :set r false }
    }
    :return $r
  }

  # Kanalangabe je AP (DW3.8): "5500", "5180,5200" oder mit Breite "5500/80" -> Frequenzen ohne Breite
  :local pinF do={
    :local v [:tostr $1]
    :local sl [:find $v "/"]
    :if ([:typeof $sl] = "num") do={ :return [:pick $v 0 $sl] }
    :return $v
  }
  # Breite in MHz: aus "/<Breite>", sonst die größte aus width in channels ("20/40/80mhz" -> 80)
  :local pinW do={
    :local v [:tostr $1]
    :local sl [:find $v "/"]
    :if ([:typeof $sl] = "num") do={ :return [:tonum [:pick $v ($sl + 1) [:len $v]]] }
    :local w [:tostr $2]
    :local m [:find $w "mhz"]
    :if ([:typeof $m] = "num") do={ :set w [:pick $w 0 $m] }
    :local r 20
    :local p 0
    :while ([:typeof [:find $w "/" $p]] = "num") do={ :set p ([:find $w "/" $p] + 1) }
    :local n [:tonum [:pick $w $p [:len $w]]]
    :if ([:typeof $n] = "num") do={ :set r $n }
    :return $r
  }
  # belegter Block eines 5-GHz-Kanals (Primärfrequenz $1, Breite $2 in MHz) -> {unten;oben} in MHz; Raster der Blöcke
  # ab Kanal 36 bzw. 149 (40 MHz: 36+40, 44+48 …; 80 MHz: 36-48, 52-64, 100-112, 116-128, 132-144, 149-161)
  :local block5 do={
    :local f [:tonum $1]; :local w [:tonum $2]
    :if ($w <= 20) do={ :return ({($f - 10);($f + 10)}) }
    :local ch (($f - 5000) / 5)
    :local g ($w / 5)
    :local base 36
    :if ($ch >= 149) do={ :set base 149 }
    :local st ($base + ((($ch - $base) / $g) * $g))
    :local lo (5000 + (5 * $st) - 10)
    :return ({$lo;($lo + $w)})
  }

  # WLAN
  :foreach k,s in=($cfmWifi->"ssids") do={
    :local vv [:tostr ($s->"vlan")]
    :if ([:len $vv] > 0 and [:typeof ($cfmVlans->$vv)] != "array") do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": VLAN " . $vv . " fehlt in vlans.rsc") }
    :if ($k = "cap") do={ :set ($err->[:len $err]) "wifi.rsc: SSID-Schlüssel cap ist reserviert (Datapath cfm-cap der APs, DW1.3)" }
    # schaltbare SSID (DW4.1): nicht die Master-SSID, Schlüssel wird Teil eines Variablennamens
    :local sw [:tostr ($s->"switch")]
    :if ([:len $sw] > 0) do={
      :if ($sw != "on" and $sw != "off") do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": switch = on oder off (Grundzustand)") }
      :if ($k = [:tostr ($cfmWifi->"master")]) do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": die Master-SSID ist nicht schaltbar") }
      :if (!($k ~ "^[a-z0-9]+\$")) do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": schaltbar nur mit Schlüssel aus Kleinbuchstaben und Ziffern") }
      :if ([:tostr ($s->"fallback")] = "yes") do={ :set ($warn->[:len $warn]) ("wifi.rsc: SSID " . $k . ": switch gilt nur für den CAPsMAN, im lokalen Fallback sendet sie trotzdem") }
    }
    :local ao [:tostr ($s->"autoOff")]
    :if ([:len $ao] > 0) do={
      :local ok false
      :onerror e in={ :if ([:totime $ao] > 0s) do={ :set ok true } } do={}
      :if (!$ok) do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": autoOff " . $ao . " ist keine Dauer (z.B. 50h)") }
      :if ([:len $sw] = 0) do={ :set ($warn->[:len $warn]) ("wifi.rsc: SSID " . $k . ": autoOff wirkt nur mit switch") }
    }
    # nur PPSK-Passphrasen (DW2.2): keine gemeinsame Passphrase, also auch kein psk.<SSID>
    :local po [:tostr ($s->"ppskOnly")]
    :if ([:len $po] > 0 and $po != "yes" and $po != "no") do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": ppskOnly = yes oder no") }
    :if ($po = "yes") do={
      :if ([:len ($cfmWifi->"ppsk"->$k)] = 0) do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": ppskOnly braucht mindestens einen Eintrag unter ppsk") }
      :if ($k = [:tostr ($cfmWifi->"master")]) do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": die Master-SSID braucht eine eigene Passphrase (kein ppskOnly)") }
    } else={
      :if ([:len [$cfmVaultGet ("psk." . $k)]] = 0) do={ :set ($warn->[:len $warn]) ("Vault: WLAN-Passphrase fehlt, \$cfmSecret key=psk." . $k . " value=...") }
    }
  }
  # 6 GHz verlangt WPA3 mit PMF (kein WPA2-Übergang): Security je Band im Kanal-Eintrag (sec/pmf)
  :foreach b,c in=($cfmWifi->"channels") do={
    :if ([:tostr ($c->"band")] ~ "^6ghz") do={
      :local sec [:tostr ($c->"sec")]
      :if ([:len $sec] = 0) do={ :set sec [:tostr ($cfmWifi->"defaults"->"sec")] }
      :local pmf [:tostr ($c->"pmf")]
      :if ([:len $pmf] = 0) do={ :set pmf [:tostr ($cfmWifi->"defaults"->"pmf")] }
      :if ($sec ~ "wpa2" or !($sec ~ "wpa3") or $pmf != "required") do={ :set ($err->[:len $err]) ("wifi.rsc: Kanal " . $b . " (6 GHz) braucht \"sec\"=\"wpa3-psk\" und \"pmf\"=\"required\"") }
    }
  }
  :local mlo [:tostr ($cfmWifi->"mlo")]
  :if ([:len $mlo] > 0 and $mlo != "disabled" and $mlo != "auto" and $mlo != "all" and $mlo != "master") do={ :set ($err->[:len $err]) ("wifi.rsc: mlo=" . $mlo . " unbekannt (disabled|auto|all|master)") }
  # MLO je SSID (DW2.3.1): wie $cfmMloOf in lib/lib-wifi.rsc, hier selbst gerechnet (der Prüfer läuft auch vor dem
  # ersten Apply einer neuen lib-wifi). RouterOS nimmt je Provisioning-Regel nur die Master-SSID oder alle SSIDs ins
  # MLD, und es gibt nur ein mld-datapath je CAP (VLAN der Master-SSID)
  :local mmk [:tostr ($cfmWifi->"master")]
  :local mlx ({})
  :foreach k,s in=($cfmWifi->"ssids") do={
    :local v [:tostr ($s->"mlo")]
    :if ([:len $v] > 0 and $v != "enabled" and $v != "disabled") do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": mlo = enabled oder disabled") }
    :if ([:len $v] > 0) do={ :set ($mlx->$k) ($v = "enabled") } else={
      :if ($k = $mmk) do={ :set ($mlx->$k) ($mlo = "master" or $mlo = "all" or $mlo = "auto") } else={ :set ($mlx->$k) ($mlo = "all" or $mlo = "auto") }
    }
  }
  :local mlv [:tostr ($cfmWifi->"ssids"->$mmk->"vlan")]
  :foreach k,on in=$mlx do={
    :if ($k != $mmk and $on = true) do={
      :if (($mlx->$mmk) != true) do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": MLO nur zusammen mit der Master-SSID " . $mmk . " (RouterOS: multi-link-mode master oder all)") }
      :if ([:tostr ($cfmWifi->"ssids"->$k->"vlan")] != $mlv) do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": MLO nur im VLAN der Master-SSID (" . $mlv . ") - es gibt ein mld-datapath je CAP, der Verkehr landete dort") }
    }
  }
  :if (($mlx->$mmk) = true) do={
    :foreach b,c in=($cfmWifi->"channels") do={
      :local on ""
      :local off ""
      :foreach k,s in=($cfmWifi->"ssids") do={
        :if ($k != $mmk and (("," . ($s->"bands") . ",") ~ ("," . $b . ","))) do={
          :if (($mlx->$k) = true) do={ :set on ($on . " " . $k) } else={ :set off ($off . " " . $k) }
        }
      }
      :if ([:len $on] > 0 and [:len $off] > 0) do={ :set ($err->[:len $err]) ("wifi.rsc: MLO auf Band " . $b . " nur an" . $on . ", nicht an" . $off . " - RouterOS nimmt je Regel nur die Master-SSID oder alle (DW2.3.1)") }
    }
    :set ($note->[:len $note]) ("wifi.rsc: MLO an der Master-SSID " . $mmk . " - FT am MLD erst ab RouterOS 7.25 (vorher mieden FT-Clients die Wi-Fi-7-APs); nach dem Umschalten am CAPsMAN cfm-reprov")
  }
  # PPSK (Multi-Passphrase, DW2.2): nur WPA2-PSK, VLAN vorhanden und auf den AP-Uplinks (trunk-ap)
  :local apTag [:tostr ($cfmProfiles->"trunk-ap"->"tag")]
  :foreach k,ents in=($cfmWifi->"ppsk") do={
    :local s ($cfmWifi->"ssids"->$k)
    :if ([:typeof $s] != "array") do={ :set ($err->[:len $err]) ("wifi.rsc: ppsk nennt unbekannte SSID " . $k) } else={
      :local sec [:tostr ($s->"sec")]
      :if ([:len $sec] = 0) do={ :set sec [:tostr ($cfmWifi->"defaults"->"sec")] }
      :if ($sec ~ "wpa3") do={ :set ($err->[:len $err]) ("wifi.rsc: PPSK auf SSID " . $k . " braucht sec=wpa2-psk (Multi-Passphrase gibt es nicht mit WPA3)") }
    }
    :foreach e,o in=$ents do={
      :local vv [:tostr ($o->"vlan")]
      :if ([:typeof ($cfmVlans->$vv)] != "array") do={ :set ($err->[:len $err]) ("wifi.rsc: PPSK " . $k . "." . $e . ": VLAN " . $vv . " fehlt in vlans.rsc") } else={
        :if ([:len $apTag] > 0 and ![$inSpec $apTag v=$vv]) do={ :set ($warn->[:len $warn]) ("wifi.rsc: PPSK " . $k . "." . $e . ": VLAN " . $vv . " fehlt im AP-Uplink-Profil trunk-ap") }
      }
      :if ([:len [$cfmVaultGet ("ppsk." . $k . "." . $e)]] = 0) do={ :set ($warn->[:len $warn]) ("Vault: Passphrase fehlt, \$cfmSecret key=ppsk." . $k . "." . $e . " value=...") }
    }
  }
  # PPSK: Das WLAN-Interface filtert alle Clients einer SSID gleich - Gruppen anders isoliert als die SSID
  :foreach k,ents in=($cfmWifi->"ppsk") do={
    :local sv [:tostr ($cfmWifi->"ssids"->$k->"vlan")]
    :local si ([:tostr ($cfmVlans->$sv->"isolate")] = "yes")
    :foreach e,o in=$ents do={
      :local gv [:tostr ($o->"vlan")]
      :if (([:tostr ($cfmVlans->$gv->"isolate")] = "yes") != $si) do={ :set ($warn->[:len $warn]) ("wifi.rsc: ppsk " . $k . "." . $e . ": VLAN " . $gv . " anders isoliert als VLAN " . $sv . " der SSID - es gilt die Isolation der SSID (DP3.1)") }
    }
  }
  # Kanal-Pinning (radios): bekannte APs, bekannte Bänder
  :foreach apn,pins in=($cfmWifi->"radios") do={
    :if ([:typeof ($inv->$apn)] != "array") do={ :set ($warn->[:len $warn]) ("wifi.rsc: radios nennt " . $apn . ", nicht im Inventar") } else={
      :if ([:typeof ($radio->$apn)] = "nothing") do={ :set ($warn->[:len $warn]) ("wifi.rsc: radios nennt " . $apn . " ohne Rolle ap oder capsman und ist nicht der CAPsMAN (eigene Radios, capsmanRadios)") }
    }
    # Wert je Band (DW3.7): Frequenz, Liste (Pool dieses AP) oder "off"; Frequenzen im Bereich des Bands
    :local noff 0
    :foreach bb,ff in=$pins do={
      :local fv [:tostr $ff]
      :if ([:typeof ($cfmWifi->"channels"->$bb)] != "array") do={ :set ($err->[:len $err]) ("wifi.rsc: radios " . $apn . ": Band " . $bb . " fehlt in channels") } else={
        :if ($fv = "off") do={ :set noff ($noff + 1) } else={
          :if (!($fv ~ "^[0-9]+(,[0-9]+)*(/(20|40|80|160))?\$")) do={ :set ($err->[:len $err]) ("wifi.rsc: radios " . $apn . " " . $bb . "=" . $fv . ": weder Frequenz (MHz), Liste (je mit /20, /40, /80 oder /160) noch off") } else={
            :local lo 2400; :local hi 2500
            :if ($bb = "5") do={ :set lo 5150; :set hi 5900 }
            :if ($bb = "6") do={ :set lo 5925; :set hi 7125 }
            :local fl [$pinF $fv]
            :local wn [$pinW $fv ($cfmWifi->"channels"->$bb->"width")]
            :if ($bb = "2" and $wn > 40) do={ :set ($err->[:len $err]) ("wifi.rsc: radios " . $apn . " 2=" . $fv . ": 2,4 GHz höchstens 40 MHz") }
            :foreach f in=[:toarray $fl] do={
              :local n [:tonum $f]
              :if ($n < $lo or $n > $hi) do={ :set ($err->[:len $err]) ("wifi.rsc: radios " . $apn . " " . $bb . ": " . $n . " MHz liegt nicht im Band (" . $lo . "-" . $hi . ")") } else={
                # EU (DW3.8): 5470-5725 MHz - ein Block darf nicht über 5725 reichen (80 MHz auf 132-144 = 5650-5730)
                :if ($bb = "5") do={
                  :local bl [$block5 $n $wn]
                  :if (($bl->0) < 5725 and ($bl->1) > 5725) do={
                    :local t ("wifi.rsc: radios " . $apn . " 5=" . $fv . ": " . $n . " MHz mit " . $wn . " MHz belegt " . ($bl->0) . "-" . ($bl->1) . " MHz, über dem Ende des Bands 5470-5725 (EU)")
                    :if ([:typeof [:find $fl ","]] = "num") do={ :set ($warn->[:len $warn]) ($t . " - RouterOS kann diesen Block wählen; Breite angeben (z.B. /40)") } else={ :set ($err->[:len $err]) ($t . " - schmaler pinnen (z.B. /40)") }
                  }
                  # DFS (DW3.10): Block mit mehr CAC als dfs erlaubt - RouterOS meidet ihn (skip-dfs-channels)
                  :local ev [:tostr ($cfmWifi->"dfs"->$apn)]
                  :if ([:len $ev] = 0) do={ :set ev [:tostr ($cfmWifi->"channels"->"5"->"dfs")] }
                  :local cls 0
                  :if (($bl->1) > 5250 and ($bl->0) < 5725) do={ :set cls 1 }
                  :if ($cls = 1 and ($bl->0) < 5650 and ($bl->1) > 5600) do={ :set cls 2 }
                  :if (($ev = "no-cac" and $cls > 0) or ($ev = "1min-cac" and $cls = 2)) do={
                    :local t ("wifi.rsc: radios " . $apn . " 5=" . $fv . ": " . $n . " MHz mit " . $wn . " MHz belegt " . ($bl->0) . "-" . ($bl->1) . " MHz")
                    :if ($cls = 2) do={ :set t ($t . " (Wetterradar, 10 min CAC)") } else={ :set t ($t . " (DFS)") }
                    :set t ($t . ", dfs=" . $ev . " erlaubt das nicht")
                    :if ([:typeof [:find $fl ","]] = "num") do={ :set ($warn->[:len $warn]) ($t . " - RouterOS lässt diesen Kanal aus") } else={ :set ($err->[:len $err]) ($t . " - anderen Kanal pinnen oder dfs je AP erlauben (\"dfs\"={\"" . $apn . "\"=\"10min-cac\"})") }
                  }
                }
              }
            }
          }
        }
      }
    }
    :if ($noff > 0 and $noff >= [:len ($cfmWifi->"channels")]) do={ :set ($warn->[:len $warn]) ("wifi.rsc: radios " . $apn . ": alle Bänder off - der AP sendet nichts") }
  }
  # DFS (DW3.10): dfs = höchste erlaubte CAC (no-cac | 1min-cac | 10min-cac), unter channels nur bei 5 GHz, je AP als
  # eigene Map ohne Band. skipDfs gibt es nicht mehr (Breaking Change 2026-11-21) - Übersetzung in der Meldung
  :local dfsV ({"no-cac"=1;"1min-cac"=1;"10min-cac"=1})
  :foreach bb,c in=($cfmWifi->"channels") do={
    :local sk [:tostr ($c->"skipDfs")]
    :if ([:len $sk] > 0) do={
      :local nv "10min-cac"
      :if ($sk = "all") do={ :set nv "no-cac" }
      :if ($sk = "10min-cac") do={ :set nv "1min-cac" }
      :set ($err->[:len $err]) ("wifi.rsc: channels " . $bb . ": skipDfs gibt es nicht mehr - \"skipDfs\"=\"" . $sk . "\" heißt jetzt \"dfs\"=\"" . $nv . "\" (höchste erlaubte CAC, DW3.10)")
    }
    :local dv [:tostr ($c->"dfs")]
    :if ([:len $dv] > 0) do={
      :if ($bb != "5") do={ :set ($err->[:len $err]) ("wifi.rsc: channels " . $bb . ": dfs nur bei 5 GHz") }
      :if ([:typeof ($dfsV->$dv)] = "nothing") do={ :set ($err->[:len $err]) ("wifi.rsc: channels " . $bb . ": dfs=" . $dv . " unbekannt (no-cac | 1min-cac | 10min-cac)") }
    }
  }
  :local gdfs [:tostr ($cfmWifi->"channels"->"5"->"dfs")]
  :local has5 ([:typeof ($cfmWifi->"channels"->"5")] = "array")
  :foreach apn,dv in=($cfmWifi->"dfs") do={
    :if ([:typeof ($inv->$apn)] != "array") do={ :set ($warn->[:len $warn]) ("wifi.rsc: dfs nennt " . $apn . ", nicht im Inventar") } else={
      :if ([:typeof ($radio->$apn)] = "nothing") do={ :set ($warn->[:len $warn]) ("wifi.rsc: dfs nennt " . $apn . " ohne Rolle ap oder capsman und ist nicht der CAPsMAN") }
    }
    :if ([:typeof $dv] = "array") do={ :set ($err->[:len $err]) ("wifi.rsc: dfs " . $apn . ": nur der Wert, ohne Band (gilt für 5 GHz), z.B. \"" . $apn . "\"=\"10min-cac\"") } else={
      :if ([:typeof ($dfsV->[:tostr $dv])] = "nothing") do={ :set ($err->[:len $err]) ("wifi.rsc: dfs " . $apn . "=" . [:tostr $dv] . " unbekannt (no-cac | 1min-cac | 10min-cac)") }
    }
    :if (!$has5) do={ :set ($warn->[:len $warn]) ("wifi.rsc: dfs " . $apn . " wirkt nicht, channels hat kein Band 5") }
  }
  # Wetterradar an APs mit lokalem Fallback (Rolle ap): 10 min CAC bei jedem Neuprovisionieren und im Fallback.
  # Nur bei ausdrücklichem Wert (je AP oder unter channels), nicht beim RouterOS-Standard ohne Angabe
  :if ($has5) do={
    :local wl ""
    :foreach n,d in=$inv do={
      :if (("," . [:tostr ($d->"role")] . ",") ~ ",ap,") do={
        :local ev [:tostr ($cfmWifi->"dfs"->$n)]
        :if ([:len $ev] = 0) do={ :set ev $gdfs }
        :if ($ev = "10min-cac" and [:tostr ($cfmWifi->"radios"->$n->"5")] != "off") do={ :if ([:len $wl] > 0) do={ :set wl ($wl . ", ") }; :set wl ($wl . $n) }
      }
    }
    :if ([:len $wl] > 0) do={ :set ($warn->[:len $warn]) ("wifi.rsc: dfs 10min-cac an APs mit Fallback (" . $wl . "): auf Wetterradar-Kanälen (5600-5650) ist 5 GHz nach jedem Neuprovisionieren und im Fallback bis zu 10 min still") }
  }
  # Sendeleistung je AP und Band (TODO 72, DW3.7): bekannte APs, Bänder aus channels, ganze dBm 1-30
  :foreach apn,tp in=($cfmWifi->"txPower") do={
    :if ([:typeof ($inv->$apn)] != "array") do={ :set ($warn->[:len $warn]) ("wifi.rsc: txPower nennt " . $apn . ", nicht im Inventar") } else={
      :if ([:typeof ($radio->$apn)] = "nothing") do={ :set ($warn->[:len $warn]) ("wifi.rsc: txPower nennt " . $apn . " ohne Rolle ap oder capsman und ist nicht der CAPsMAN") }
    }
    :if ([:typeof $tp] != "array") do={ :set ($err->[:len $err]) ("wifi.rsc: txPower " . $apn . ": je Band angeben, z.B. {\"5\"=17}") } else={
      :foreach bb,v in=$tp do={
        :if ([:typeof ($cfmWifi->"channels"->$bb)] != "array") do={ :set ($err->[:len $err]) ("wifi.rsc: txPower " . $apn . ": Band " . $bb . " fehlt in channels") }
        :local n [:tonum $v]
        :if ([:typeof $n] != "num" or $n < 1 or $n > 30 or [:tostr $n] != [:tostr $v]) do={ :set ($err->[:len $err]) ("wifi.rsc: txPower " . $apn . " " . $bb . "=" . [:tostr $v] . ": ganze dBm 1-30") }
        :if ([:tostr ($cfmWifi->"radios"->$apn->$bb)] = "off") do={ :set ($warn->[:len $warn]) ("wifi.rsc: txPower " . $apn . " " . $bb . " wirkt nicht, das Band ist dort off") }
      }
    }
  }
  # Andere Funknetze im 2,4-GHz-Band (TODO 51): Typ, Kanal, near, Gewicht; ein Pin auf 2,4 GHz, der
  # ein Zigbee-/Thread-Netz mit festem Kanal überdeckt (bis 9 MHz neben der Mitte), an einem AP aus
  # near (ohne near an jedem AP) -> Warnung. Ohne die Helfer aus mgr-scan ($cfmRelease prüft mit den
  # alten Manager-Modulen)
  :local o154 ({})
  :foreach k,e in=($cfmWifi->"others") do={
    :local t [:tostr ($e->"type")]
    :if ([:typeof $e] != "array" or !($t ~ "^(zigbee|thread|milight-rgbw|milight-cct|milight-rgbcct|ble|bt)\$")) do={
      :set ($err->[:len $err]) ("wifi.rsc: others " . $k . ": type " . $t . " unbekannt (zigbee|thread|milight-rgbw|milight-cct|milight-rgbcct|ble|bt)")
    } else={
      :local ch [:tostr ($e->"ch")]
      :if ($t = "zigbee" or $t = "thread") do={
        :local c [:tonum $ch]
        :if ([:typeof $c] = "num") do={
          :if ($c < 11 or $c > 26) do={ :set ($err->[:len $err]) ("wifi.rsc: others " . $k . ": ch " . $ch . " liegt nicht in 11-26") } else={
            :foreach ok,oc in=$o154 do={ :if ($oc = $c) do={ :set ($warn->[:len $warn]) ("wifi.rsc: others " . $k . " und " . $ok . " auf demselben Kanal " . $c) } }
            :set ($o154->$k) $c
          }
        } else={
          :if ([:len $ch] > 0 and $ch != "auto") do={ :set ($err->[:len $err]) ("wifi.rsc: others " . $k . ": ch " . $ch . " ist weder 11-26 noch auto") }
        }
      } else={
        :if ([:len $ch] > 0) do={ :set ($warn->[:len $warn]) ("wifi.rsc: others " . $k . ": ch gilt nur für zigbee/thread (" . $t . " hat feste Kanäle)") }
      }
      :local w [:tostr ($e->"w")]
      :if ([:len $w] > 0) do={
        :local wn [:tonum $w]
        :if ([:typeof $wn] != "num" or $wn < 1 or $wn > 200) do={ :set ($err->[:len $err]) ("wifi.rsc: others " . $k . ": w " . $w . " ist kein Gewicht (1-200)") }
      }
      :foreach apn in=[:toarray [:tostr ($e->"near")]] do={
        :if ([:typeof ($inv->$apn)] != "array") do={ :set ($warn->[:len $warn]) ("wifi.rsc: others " . $k . ": near nennt " . $apn . ", nicht im Inventar") } else={
          :if ([:typeof ($radio->$apn)] = "nothing") do={ :set ($warn->[:len $warn]) ("wifi.rsc: others " . $k . ": near nennt " . $apn . " ohne Rolle ap oder capsman und ist nicht der CAPsMAN") }
        }
      }
    }
  }
  :foreach k,c in=$o154 do={
    :local fz (2405 + (5 * ($c - 11)))
    :local nr [:tostr ($cfmWifi->"others"->$k->"near")]
    :foreach apn,pins in=($cfmWifi->"radios") do={
      # Pin oder Pool dieses AP (DW3.7): jede Frequenz der Liste
      :if ([:len $nr] = 0 or [:typeof [:find ("," . $nr . ",") ("," . $apn . ",")]] != "nil") do={
        :foreach f in=[:toarray [$pinF ($pins->"2")]] do={
          :local pf [:tonum $f]
          :if ([:typeof $pf] = "num") do={
            :local d ($pf - $fz)
            :if ($d < 0) do={ :set d (0 - $d) }
            :if ($d <= 9) do={ :set ($warn->[:len $warn]) ("wifi.rsc: radios " . $apn . " 2=" . $pf . " überdeckt " . $k . " (" . [:tostr ($cfmWifi->"others"->$k->"type")] . " Kanal " . $c . ", " . $fz . " MHz)") }
          }
        }
      }
    }
  }
  # Steering je Band und Mindestsignal (TODO 39): Schwellen in dBm, Band muss es geben
  :foreach bb,st in=($cfmWifi->"steer") do={
    :if ([:typeof ($cfmWifi->"channels"->$bb)] != "array") do={ :set ($err->[:len $err]) ("wifi.rsc: steer: Band " . $bb . " fehlt in channels") }
    :local hasDr ([:len [:tostr ($st->"drop")]] > 0)
    # threshold (Steering) oder drop (Trennschwelle, TODO 61, DW2.5) - eines von beiden
    :if ([:len [:tostr ($st->"threshold")]] > 0 or !$hasDr) do={
      :local th [:tonum ($st->"threshold")]
      :if ([:typeof $th] != "num" or $th > -40 or $th < -100) do={ :set ($err->[:len $err]) ("wifi.rsc: steer " . $bb . ": threshold " . [:tostr ($st->"threshold")] . " ist kein Pegel in dBm (-100..-40)") }
    }
    :foreach f in={"drop";"join"} do={
      :if ([:len [:tostr ($st->$f)]] > 0) do={
        :local v [:tonum ($st->$f)]
        :if ([:typeof $v] != "num" or $v > -40 or $v < -100) do={ :set ($err->[:len $err]) ("wifi.rsc: steer " . $bb . ": " . $f . " " . [:tostr ($st->$f)] . " ist kein Pegel in dBm (-100..-40)") }
      }
    }
    :if (!$hasDr and ([:len [:tostr ($st->"join")]] > 0 or [:len [:tostr ($st->"hold")]] > 0)) do={ :set ($err->[:len $err]) ("wifi.rsc: steer " . $bb . ": join/hold wirken nur mit drop") }
    :if ([:len [:tostr ($st->"hold")]] > 0 and !([:tostr ($st->"hold")] ~ "^([0-9]+[wdhms])+\$")) do={ :set ($err->[:len $err]) ("wifi.rsc: steer " . $bb . ": hold " . [:tostr ($st->"hold")] . " ist keine Dauer (z.B. 30s)") }
    :if ($hasDr) do={
      :local dr [:tonum ($st->"drop")]
      :local jn $dr
      :if ([:len [:tostr ($st->"join")]] > 0) do={ :set jn [:tonum ($st->"join")] }
      :if ([:typeof $jn] = "num" and [:typeof $dr] = "num") do={
        :if ($jn < $dr) do={ :set ($err->[:len $err]) ("wifi.rsc: steer " . $bb . ": join " . $jn . " liegt unter drop " . $dr . " - angemeldete Clients würden sofort getrennt") }
        :if ($jn = $dr) do={ :set ($warn->[:len $warn]) ("wifi.rsc: steer " . $bb . ": join = drop - am Rand pendelt ein Client (getrennt, Sekunden später wieder angemeldet); join einige dB über drop setzen (DW2.5)") }
      }
      # isolierte VLANs (DP3.1) bleiben ausgenommen: ihr datapath trägt schon in cfm-iso ein
      :foreach k,s in=($cfmWifi->"ssids") do={
        :if ([:tostr ($cfmVlans->[:tostr ($s->"vlan")]->"isolate")] = "yes" and ($k = [:tostr ($cfmWifi->"master")] or (("," . ($s->"bands") . ",") ~ ("," . $bb . ",")))) do={
          :set ($warn->[:len $warn]) ("wifi.rsc: steer " . $bb . ": drop gilt nicht für SSID " . $k . " (VLAN " . [:tostr ($s->"vlan")] . " isoliert, DP3.1/DW2.5)")
        }
      }
    }
  }
  :if ([:len [:tostr ($cfmWifi->"minSignal")]] > 0) do={
    :local ms [:tonum ($cfmWifi->"minSignal")]
    :if ([:typeof $ms] != "num" or $ms > -40 or $ms < -100) do={ :set ($err->[:len $err]) ("wifi.rsc: minSignal " . [:tostr ($cfmWifi->"minSignal")] . " ist kein Pegel in dBm (-100..-40)") }
    # Die Regeln der Trennschwelle (wcut) stehen vor wacl:min und decken jedes Signal ab: Auf Bändern mit drop gilt
    # bei der Anmeldung join, minSignal erreicht dort nur isolierte SSIDs (DP3.1) - Hardware 2026-11-19 (TODO 96)
    :local jl ""
    :local fb ""
    :foreach bb,c in=($cfmWifi->"channels") do={
      :local st ($cfmWifi->"steer"->$bb)
      :if ([:typeof $st] = "array" and [:len [:tostr ($st->"drop")]] > 0) do={
        :local jn [:tostr ($st->"join")]
        :if ([:len $jn] = 0) do={ :set jn [:tostr ($st->"drop")] }
        :set jl ($jl . ", " . $bb . " join " . $jn)
      } else={ :set fb ($fb . "," . $bb) }
    }
    :if ([:typeof $ms] = "num" and [:len $jl] > 0) do={
      :local wo "keinem Band"
      :if ([:len $fb] > 0) do={ :set wo ("Band " . [:pick $fb 1 [:len $fb]]) }
      :set ($note->[:len $note]) ("wifi.rsc: minSignal " . $ms . " gilt bei der Anmeldung nur auf " . $wo . " (und für isolierte SSIDs); mit Trennschwelle gilt join: " . [:pick $jl 2 [:len $jl]] . " (DW2.5)")
    }
  }
  # Fallback weiterer SSIDs (TODO 40a): die Master-SSID hat ihn immer
  :foreach k,s in=($cfmWifi->"ssids") do={
    :if ([:tostr ($s->"fallback")] = "yes" and $k = [:tostr ($cfmWifi->"master")]) do={ :set ($warn->[:len $warn]) ("wifi.rsc: fallback an der Master-SSID " . $k . " ist überflüssig (DW1.6)") }
    :if ([:len [:tostr ($s->"fallback")]] > 0 and !([:tostr ($s->"fallback")] ~ "^(yes|no)\$")) do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": fallback = yes oder no") }
    # Der Schalter (DW4.1) lebt auf dem CAPsMAN - im Fallback weiß der AP nichts davon (DW1.12)
    :if ([:tostr ($s->"fallback")] = "yes" and [:len [:tostr ($s->"switch")]] > 0) do={ :set ($warn->[:len $warn]) ("wifi.rsc: SSID " . $k . ": fallback mit switch - im lokalen Fallback sendet sie unabhängig vom Schalter") }
  }
  # Pool 5 GHz (DW3.8, TODO 90): RouterOS wählt die Breite bis zum Höchstwert aus width - ein Block über 5725 MHz
  # (Ende des Bands 5470-5725, EU) ist dann möglich und wurde gewählt (80 MHz auf 132-144, Hardware 2026-11-17)
  :local c5 ($cfmWifi->"channels"->"5")
  :if ([:typeof $c5] = "array") do={
    :local w5 [$pinW "" ($c5->"width")]
    :local over ""
    :foreach f in=[:toarray [:tostr ($c5->"freq")]] do={
      :local n [:tonum $f]
      :if ([:typeof $n] = "num") do={
        :local bl [$block5 $n $w5]
        :if (($bl->0) < 5725 and ($bl->1) > 5725) do={ :set over ($over . "," . $n) }
      }
    }
    :if ([:len $over] > 0) do={ :set ($warn->[:len $warn]) ("wifi.rsc: channels 5: " . [:pick $over 1 [:len $over]] . " MHz mit bis zu " . $w5 . " MHz reicht über 5725 MHz (Ende des Bands 5470-5725, EU) - aus dem Pool nehmen oder width schmaler; je AP z.B. radios \"5\"=\"5660/40\" (DW3.8)") }
  }
  # DFS (TODO 87): Kanäle 5260-5720 MHz im Pool oder in radios - gewollt, aber mit Nebenwirkung -> Hinweis
  :local dfs do={
    :local r ""
    :foreach f in=[:toarray [:tostr $1]] do={
      :local n [:tonum $f]
      :if ([:typeof $n] = "num" and $n > 5250 and $n < 5730) do={ :set r ($r . "," . $n) }
    }
    :if ([:len $r] > 0) do={ :set r [:pick $r 1 [:len $r]] }
    :return $r
  }
  # dfs=no-cac (DW3.10): RouterOS meidet die DFS-Kanäle, kein Hinweis (Pins dagegen meldet die Prüfung oben)
  :local dc ""
  :if ($gdfs != "no-cac") do={ :set dc [$dfs ($cfmWifi->"channels"->"5"->"freq")] }
  :local da ""
  :foreach apn,pins in=($cfmWifi->"radios") do={
    :local ev [:tostr ($cfmWifi->"dfs"->$apn)]
    :if ([:len $ev] = 0) do={ :set ev $gdfs }
    :if ($ev != "no-cac" and [:typeof $pins] = "array" and [:len [$dfs [$pinF ($pins->"5")]]] > 0) do={ :set da ($da . ", " . $apn . " " . [$dfs [$pinF ($pins->"5")]]) }
  }
  :if ([:len $dc] > 0 or [:len $da] > 0) do={
    :local s "wifi.rsc: 5 GHz mit DFS-Kanälen ("
    :if ([:len $dc] > 0) do={ :set s ($s . "Pool " . $dc) }
    :if ([:len $da] > 0) do={ :if ([:len $dc] > 0) do={ :set s ($s . "; ") }; :set s ($s . "radios " . [:pick $da 2 [:len $da]]) }
    :set ($note->[:len $note]) ($s . "): nach jedem Start eines Radios dort mindestens 60 s kein 5 GHz (CAC), bei Radar Kanalwechsel - auch im lokalen Fallback der APs")
  }
  :return ({"err"=$err;"warn"=$warn;"note"=$note})
}
