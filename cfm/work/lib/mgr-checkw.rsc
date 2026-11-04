# ============================================================
# cfm lib/mgr-checkw.rsc – Manager-Funktionen: WLAN-Teil der inhaltlichen Prüfung
#   $cfmCheckWifi inv=<inventar>   prüft wifi.rsc (SSIDs, 6 GHz, PPSK, Pinning, andere Funknetze,
#                                  Steering, Fallback) -> {"err"={..};"warn"={..}}
#   Aufruf nur aus $cfmCheck (lib/mgr-check.rsc), nachdem der die Daten geladen hat. Eigene Datei,
#   weil /file get nur ca. 60 KB liest (TODO 73, DM1.1); $cfmCheck lädt sie aus demselben Stand nach.
# ============================================================

:global cfmCheckWifi do={
  :global cfmWifi; :global cfmVlans; :global cfmProfiles; :global cfmVaultGet
  :local err ({}); :local warn ({})
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
    :if ([:len [$cfmVaultGet ("psk." . $k)]] = 0) do={ :set ($warn->[:len $warn]) ("Vault: WLAN-Passphrase fehlt, \$cfmSecret key=psk." . $k . " value=...") }
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
      :if (!(("," . [:tostr ($inv->$apn->"role")] . ",") ~ ",(ap|capsman),")) do={ :set ($warn->[:len $warn]) ("wifi.rsc: radios nennt " . $apn . " ohne Rolle ap oder capsman (eigene Radios, capsmanRadios)") }
    }
    :foreach bb,ff in=$pins do={
      :if ([:typeof ($cfmWifi->"channels"->$bb)] != "array") do={ :set ($err->[:len $err]) ("wifi.rsc: radios " . $apn . ": Band " . $bb . " fehlt in channels") }
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
          :if (!(("," . [:tostr ($inv->$apn->"role")] . ",") ~ ",(ap|capsman),")) do={ :set ($warn->[:len $warn]) ("wifi.rsc: others " . $k . ": near nennt " . $apn . " ohne Rolle ap oder capsman") }
        }
      }
    }
  }
  :foreach k,c in=$o154 do={
    :local fz (2405 + (5 * ($c - 11)))
    :local nr [:tostr ($cfmWifi->"others"->$k->"near")]
    :foreach apn,pins in=($cfmWifi->"radios") do={
      :local pf [:tonum ($pins->"2")]
      :if ([:typeof $pf] = "num" and ([:len $nr] = 0 or [:typeof [:find ("," . $nr . ",") ("," . $apn . ",")]] != "nil")) do={
        :local d ($pf - $fz)
        :if ($d < 0) do={ :set d (0 - $d) }
        :if ($d <= 9) do={ :set ($warn->[:len $warn]) ("wifi.rsc: radios " . $apn . " 2=" . $pf . " überdeckt " . $k . " (" . [:tostr ($cfmWifi->"others"->$k->"type")] . " Kanal " . $c . ", " . $fz . " MHz)") }
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
  }
  # Fallback weiterer SSIDs (TODO 40a): die Master-SSID hat ihn immer
  :foreach k,s in=($cfmWifi->"ssids") do={
    :if ([:tostr ($s->"fallback")] = "yes" and $k = [:tostr ($cfmWifi->"master")]) do={ :set ($warn->[:len $warn]) ("wifi.rsc: fallback an der Master-SSID " . $k . " ist überflüssig (DW1.6)") }
  }
  :return ({"err"=$err;"warn"=$warn})
}
