# ============================================================
# cfm lib/mgr-check.rsc – Manager-Funktionen: inhaltliche Prüfung und Probelauf
#   $cfmCheck            prüft die Daten in work/ (läuft auch bei jedem $cfmRelease, D27)
#   $cfmPlan host=<n>    Probelauf: das Gerät zeigt, was ein Release von work/ ändern würde
#   (Übersicht aller Befehle: lib/mgr-core.rsc)
# ============================================================

# ---------- Inhaltliche Prüfung von work/ -> {"err"={..};"warn"={..}} ----------
# Fehler: VLANs/Zonen, die Profile, WLAN, policy, mgmtAccess oder Hostfiles nennen, aber nicht
# existieren; unbekannte Port-Profile; doppelte MGMT-IPs; Rollen ohne Datei; unbekannte IP-Dienste
# oder doppelte Ports in services.
# Warnungen: Inventar-Eintrag ohne Hostfile.
:global cfmCheck do={
  :global cfmMB; :global cfmLoadData; :global cfmG; :global cfmVlans; :global cfmProfiles
  :global cfmWifi; :global cfmInvLoad; :global cfmHost; :global cfmVaultGet; :global cfmWg
  :global cfmNet; :global cfmTarget; :global cfmLeases; :global cfmMacUp; :global cfmMgrData; :global cfmLimit
  :global cfmMlag; :global cfmMlagOf
  :local b [$cfmMB]
  # dir=<verzeichnis>: statt work/ prüfen ($cfmPlan from=)
  :local w ($b . "/work")
  :if ([:len [:tostr $dir]] > 0) do={ :set w ($b . "/" . $dir) }
  :local err ({}); :local warn ({})
  :local le ""
  # Datei vorhanden? Über den Namen statt /file/find (TODO 21). Lokal statt $cfmFileEx, weil
  # $cfmRelease diesen Prüfer aus work/ lädt, während noch die alten Manager-Module laufen
  :local fex do={ :local r false; :onerror e in={ :if ([:len [/file/get $1 name]] > 0) do={ :set r true } } do={}; :return $r }
  # hold=yes: Ein Apply auf diesem Gerät wartet, bis die Prüfung durch ist - sie importiert gleich alle
  # Hostfiles in cfmHost, den der Apply liest (cfmMgrData, Gegenstück zu cfmApplyBusy)
  :onerror e in={ $cfmLoadData ver=0 dir=$dir hold="yes" } do={ :set le $e }
  # Helfer aus lib/lib.rsc (lädt $cfmLoadData mit): fehlen sie, liefern Aufrufe stillschweigend
  # nichts und die Prüfung liefe halb blind
  :if ([:typeof $cfmNet] = "nothing" or [:typeof $cfmTarget] = "nothing") do={
    :set ($err->[:len $err]) "lib/lib.rsc nicht geladen: Prüfung von VLAN-Netzen und Policy-Zielen nicht möglich"
  }
  :if ([:len $le] > 0) do={ :set cfmMgrData 0; :set ($err->0) ("Daten in work/ nicht ladbar: " . $le); :return ({"err"=$err;"warn"=$warn}) }
  # mlag.rsc (D75) selbst laden: $cfmLoadData des installierten Managers kennt sie vor D75 nicht
  :set cfmMlag ({})
  :if ([$fex ($w . "/mlag.rsc")]) do={ :onerror e in={ /import file-name=($w . "/mlag.rsc") verbose=no } do={ :set ($err->[:len $err]) ("mlag.rsc: " . $e) } }
  # Profil gültig? -> "" oder Fehlertext (Hostfile-Ports, Bonds, MLAG-Bonds)
  :local profOk do={
    :global cfmProfiles; :global cfmVlans
    :local sp [:tostr $1]; :local pn $sp; :local arg ""
    :local c [:find $sp ":"]
    :if ([:typeof $c] != "nil") do={ :set pn [:pick $sp 0 $c]; :set arg [:pick $sp ($c + 1) [:len $sp]] }
    :local pr ($cfmProfiles->$pn)
    :if ([:typeof $pr] != "array") do={ :return ("unbekanntes Port-Profil " . $sp) }
    :if ([:tostr ($pr->"untag")] = "arg" and [:typeof ($cfmVlans->$arg)] != "array") do={ :return ("VLAN " . $arg . " fehlt in vlans.rsc") }
    :return ""
  }
  # MLAG-Knoten: wirksame STP-Priorität je Knoten (Vergleich unten)
  :local mstp ({})
  :local zones ({})
  :foreach vid,v in=$cfmVlans do={ :set ($zones->[:tostr ($v->"zone")]) 1 }
  # VLAN-Spezifikation ("*", Zonen, VIDs, "!x") -> unbekannte Einträge
  :local badSpec do={
    :global cfmVlans
    :local r ""
    :foreach t in=[:toarray $1] do={
      :local x [:tostr $t]
      :if ([:pick $x 0 1] = "!") do={ :set x [:pick $x 1 [:len $x]] }
      :if ($x != "*" and [:typeof ($cfmVlans->$x)] != "array" and [:typeof ($z->$x)] = "nothing") do={ :set r ($r . " " . $x) }
    }
    :return $r
  }
  # Liegt VLAN v in der Spezifikation ("*", Zonen, VIDs, "!x")?
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

  # Port-Profile
  :foreach pn,pr in=$cfmProfiles do={
    :local u [:tostr ($pr->"untag")]
    :if ([:len $u] > 0 and $u != "arg" and [:typeof ($cfmVlans->$u)] != "array") do={ :set ($err->[:len $err]) ("profiles.rsc: " . $pn . ": untag " . $u . " ist kein VLAN") }
    :local bs [$badSpec ($pr->"tag") z=$zones]
    :if ([:len $bs] > 0) do={ :set ($err->[:len $err]) ("profiles.rsc: " . $pn . ": unbekannte VLANs/Zonen:" . $bs) }
  }
  # WLAN
  :foreach k,s in=($cfmWifi->"ssids") do={
    :local vv [:tostr ($s->"vlan")]
    :if ([:len $vv] > 0 and [:typeof ($cfmVlans->$vv)] != "array") do={ :set ($err->[:len $err]) ("wifi.rsc: SSID " . $k . ": VLAN " . $vv . " fehlt in vlans.rsc") }
    :if ($k = "cap") do={ :set ($err->[:len $err]) "wifi.rsc: SSID-Schlüssel cap ist reserviert (Datapath cfm-cap der APs, D41)" }
    # schaltbare SSID (D64): nicht die Master-SSID, Schlüssel wird Teil eines Variablennamens
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
  # PPSK (Multi-Passphrase, D32): nur WPA2-PSK, VLAN vorhanden und auf den AP-Uplinks (trunk-ap)
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
  # WireGuard (Peers zählen als Zone mgmt): Pubkey Pflicht, Tunnel-Adressen eindeutig, eigenes
  # Subnetz darf nicht mit einem VLAN aus vlans.rsc überlappen (sonst wieder Proxy-ARP-Ärger)
  :local wgAddrs ({})
  :if ([:len ($cfmWg->"peers")] > 0 and [:len [:tostr ($cfmWg->"net")]] = 0) do={
    :set ($err->[:len $err]) ("wireguard.rsc: peers vorhanden, aber net fehlt")
  }
  :foreach vid,v in=$cfmVlans do={
    :local vn [:tostr (([$cfmNet $vid])->"net")]
    :if ([:len $vn] > 0 and $vn = [:tostr ($cfmWg->"net")]) do={ :set ($err->[:len $err]) ("wireguard.rsc: net " . $vn . " überlappt mit VLAN " . $vid) }
  }
  :foreach k,p in=($cfmWg->"peers") do={
    :if ([:len [:tostr ($p->"pubkey")]] = 0) do={ :set ($err->[:len $err]) ("wireguard.rsc: peer " . $k . ": pubkey fehlt") }
    :local ad [:tostr ($p->"addr")]
    :if ([:len $ad] = 0) do={ :set ($err->[:len $err]) ("wireguard.rsc: peer " . $k . ": addr fehlt") } else={
      :if ([:typeof ($wgAddrs->$ad)] != "nothing") do={ :set ($err->[:len $err]) ("wireguard.rsc: peer " . $k . ": addr " . $ad . " doppelt vergeben (" . ($wgAddrs->$ad) . ")") }
      :set ($wgAddrs->$ad) $k
    }
  }
  # dhcpGw (D82): Host-Anteil, nur mit dhcp, nicht im Pool, nicht das Gateway selbst
  :foreach vid,v in=$cfmVlans do={
    :local dg [:tostr ($v->"dhcpGw")]
    :if ([:len $dg] > 0) do={
      :local w ("vlans.rsc: VLAN " . $vid . ": dhcpGw " . $dg . " ")
      :local h [:tonum $dg]
      :local dh [:tostr ($v->"dhcp")]
      :if ([:typeof $h] != "num" or $h < 1 or $h > 254) do={ :set ($err->[:len $err]) ($w . "muss ein Host-Anteil 1-254 sein") } else={
        :if ([:len $dh] = 0 or $dh = "no") do={ :set ($warn->[:len $warn]) ($w . "wirkt nur mit dhcp") } else={
          :local s [:find $dh "-"]
          :if ([:typeof $s] = "num") do={
            :if ($h >= [:tonum [:pick $dh 0 $s]] and $h <= [:tonum [:pick $dh ($s + 1) [:len $dh]]]) do={ :set ($err->[:len $err]) ($w . "liegt im DHCP-Bereich " . $dh) }
          }
        }
        :local gwh [:tonum ($v->"gw")]
        :if ([:typeof $gwh] != "num") do={ :set gwh 1 }
        :if ($h = $gwh) do={ :set ($warn->[:len $warn]) ($w . "ist das Gateway selbst (Eintrag überflüssig)") }
      }
    }
  }
  # Feste Leases (D62): VLAN mit DHCP der Router, Name als DNS-Label (eindeutig, kein Gerätename),
  # MAC und Adresse je VLAN eindeutig, Adresse im Netz und nicht die des Gateways
  :local lName ({}); :local lWifi ({})
  :foreach vid,ls in=$cfmLeases do={
    :local v ($cfmVlans->[:tostr $vid])
    :if ([:typeof $v] != "array") do={ :set ($err->[:len $err]) ("leases.rsc: VLAN " . $vid . " fehlt in vlans.rsc") } else={
      :local dh [:tostr ($v->"dhcp")]
      :if ([:len $dh] = 0 or $dh = "no" or [:tostr ($v->"onboard")] = "yes") do={ :set ($warn->[:len $warn]) ("leases.rsc: VLAN " . $vid . " ohne DHCP der Router - die Leases wirken nicht") }
      :local nn [$cfmNet $vid]
      :local hmax 254
      :if ([:len [:tostr ($nn->"pfx")]] > 0) do={
        :set hmax 1
        :for i from=1 to=(32 - [:tonum ($nn->"pfx")]) do={ :set hmax ($hmax * 2) }
        :set hmax ($hmax - 2)
      }
      :local gwh [:tonum ($v->"gw")]
      :if ([:typeof $gwh] != "num") do={ :set gwh 1 }
      :local lMac ({}); :local lIp ({})
      :foreach ln,ld in=$ls do={
        :local w ("leases.rsc: VLAN " . $vid . " " . $ln . ": ")
        :if (!($ln ~ "^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\$")) do={ :set ($err->[:len $err]) ($w . "Name nur aus Buchstaben, Ziffern und \"-\" (DNS)") }
        :if ([:typeof ($lName->$ln)] != "nothing") do={ :set ($err->[:len $err]) ($w . "Name schon in VLAN " . ($lName->$ln)) }
        :set ($lName->$ln) $vid
        :local mac [$cfmMacUp ($ld->"mac")]
        :if (!($mac ~ "^([0-9A-F][0-9A-F]:){5}[0-9A-F][0-9A-F]\$")) do={ :set ($err->[:len $err]) ($w . "MAC fehlt oder ungültig (AA:BB:CC:DD:EE:FF)") } else={
          :if ([:typeof ($lMac->$mac)] != "nothing") do={ :set ($err->[:len $err]) ($w . "MAC schon bei " . ($lMac->$mac)) }
          :set ($lMac->$mac) $ln
          # Client-VLAN je MAC (D95): ein Gerät mit zufälliger MAC je SSID landet nach einem Wechsel wieder im
          # VLAN der SSID; das VLAN muss auf den AP-Uplinks liegen (wie bei PPSK)
          :if ([:tostr ($ld->"wifi")] = "yes") do={
            :if ([:typeof ($lWifi->$mac)] != "nothing") do={ :set ($err->[:len $err]) ($w . "wifi: MAC schon mit wifi in VLAN " . ($lWifi->$mac) . " - nur ein VLAN je MAC") }
            :set ($lWifi->$mac) $vid
            :if ([:typeof [:find "26AE" [:pick $mac 1 2]]] = "num") do={ :set ($warn->[:len $warn]) ($w . "wifi: lokal verwaltete (zufällige) MAC - wechselt das Gerät sie, gilt wieder das VLAN der SSID") }
            :if ([:len $apTag] > 0 and ![$inSpec $apTag v=[:tostr $vid]]) do={ :set ($warn->[:len $warn]) ($w . "wifi: VLAN " . $vid . " fehlt im AP-Uplink-Profil trunk-ap") }
          }
        }
        :local wf [:tostr ($ld->"wifi")]
        :if ([:len $wf] > 0 and $wf != "yes" and $wf != "no") do={ :set ($err->[:len $err]) ($w . "wifi nur \"yes\" oder \"no\"") }
        :local h [:tonum ($ld->"ip")]
        :if ([:typeof $h] != "num" or $h < 1 or $h > $hmax) do={ :set ($err->[:len $err]) ($w . "ip = Host-Anteil 1-" . $hmax) } else={
          :if ($h = $gwh) do={ :set ($err->[:len $err]) ($w . "ip ist die Adresse des Gateways") }
          :if ([:tostr $h] = [:tostr ($v->"dhcpGw")]) do={ :set ($err->[:len $err]) ($w . "ip ist dhcpGw (Gateway der Clients)") }
          :if ([:typeof ($lIp->[:tostr $h])] != "nothing") do={ :set ($err->[:len $err]) ($w . "ip schon bei " . ($lIp->[:tostr $h])) }
          :set ($lIp->[:tostr $h]) $ln
          :if ($h >= 251 and $h <= 254) do={ :set ($warn->[:len $warn]) ($w . ".251-.254 nutzen VRRP-Router als eigene Adresse (routerId 1-4)") }
        }
      }
    }
  }
  :foreach hn,hd in=[$cfmInvLoad] do={
    :if ([:typeof ($lName->$hn)] != "nothing") do={ :set ($err->[:len $err]) ("leases.rsc: Name " . $hn . " ist auch ein Gerät (gleicher DNS-Name)") }
  }
  # NTP-Umleitung (D93): nur "redirect", braucht ein Router-Interface
  :foreach vid,v in=$cfmVlans do={
    :local nt [:tostr ($v->"ntp")]
    :if ([:len $nt] > 0 and $nt != "redirect") do={ :set ($err->[:len $err]) ("vlans.rsc: VLAN " . $vid . ": ntp " . $nt . " (nur redirect)") }
    :if ($nt = "redirect" and [:tostr ($v->"l3")] = "no") do={ :set ($warn->[:len $warn]) ("vlans.rsc: VLAN " . $vid . ": ntp redirect ohne Router (l3=no) wirkt nicht") }
  }
  # Bandbreitenlimit (D97): "Download/Upload" mit k/M/G, wirkt nur mit Router-Interface und Subnetz
  :foreach vid,v in=$cfmVlans do={
    :local any false
    :foreach f in={"limit";"limitClient"} do={
      :local lv [:tostr ($v->$f)]
      :if ([:len $lv] > 0) do={
        :set any true
        :if ([:typeof [$cfmLimit $lv]] != "array") do={ :set ($err->[:len $err]) ("vlans.rsc: VLAN " . $vid . ": " . $f . " " . $lv . " (Download/Upload, z.B. 50M/10M; Einheiten k, M, G ohne Komma)") }
      }
    }
    :if ($any and ([:tostr ($v->"l3")] = "no" or [:len ([$cfmNet $vid]->"net")] = 0)) do={ :set ($warn->[:len $warn]) ("vlans.rsc: VLAN " . $vid . ": limit ohne Router-Interface (l3=no) oder Subnetz wirkt nicht") }
  }
  # Isolierte VLANs (D76): isolate yes/no, Ausnahmen auflösbar (Name mit MAC in leases.rsc oder MAC),
  # nicht das Onboarding-VLAN, ohne Router nur Broadcast und Ausnahmen
  :foreach vid,v in=$cfmVlans do={
    :local is [:tostr ($v->"isolate")]
    :local vw ("vlans.rsc: VLAN " . $vid . ": ")
    :if ([:len $is] > 0 and $is != "yes" and $is != "no") do={ :set ($err->[:len $err]) ($vw . "isolate " . $is . " (yes oder no)") }
    :if ($is = "yes") do={
      :if ([:tostr ($v->"onboard")] = "yes") do={ :set ($err->[:len $err]) ($vw . "das Onboarding-VLAN nicht isolieren") }
      :if ([:tostr ($v->"l3")] = "no") do={ :set ($warn->[:len $warn]) ($vw . "isolate ohne Router (l3=no) - die Clients erreichen nur Broadcast und die Ausnahmen") }
      :foreach a in=[:toarray ($v->"isolateAllow")] do={
        :local mac [:tostr $a]
        :local ok ([:len $mac] = 17 and $mac ~ "^[0-9A-Fa-f][0-9A-Fa-f](:[0-9A-Fa-f][0-9A-Fa-f])+\$")
        :if (!$ok and [:len [:tostr ($cfmLeases->$vid->$a->"mac")]] = 0) do={ :set ($err->[:len $err]) ($vw . "isolateAllow " . $a . ": weder MAC-Adresse noch Name mit MAC in leases.rsc (VLAN " . $vid . ")") }
      }
    } else={
      :if ([:len [:tostr ($v->"isolateAllow")]] > 0) do={ :set ($warn->[:len $warn]) ($vw . "isolateAllow wirkt nur mit isolate=yes") }
    }
  }
  # PPSK: Das WLAN-Interface filtert alle Clients einer SSID gleich - Gruppen anders isoliert als die SSID
  :foreach k,ents in=($cfmWifi->"ppsk") do={
    :local sv [:tostr ($cfmWifi->"ssids"->$k->"vlan")]
    :local si ([:tostr ($cfmVlans->$sv->"isolate")] = "yes")
    :foreach e,o in=$ents do={
      :local gv [:tostr ($o->"vlan")]
      :if (([:tostr ($cfmVlans->$gv->"isolate")] = "yes") != $si) do={ :set ($warn->[:len $warn]) ("wifi.rsc: ppsk " . $k . "." . $e . ": VLAN " . $gv . " anders isoliert als VLAN " . $sv . " der SSID - es gilt die Isolation der SSID (D76)") }
    }
  }
  # IP-Dienste: nur RouterOS-Namen (http/https blieben stillschweigend wirkungslos), jeder Port nur
  # einmal (www-ssl und reverse-proxy stehen ab Werk beide auf 443)
  :local svp ({})
  :foreach sn,sp in=($cfmG->"services") do={
    :if (!($sn ~ "^(telnet|ftp|www|www-ssl|reverse-proxy|api|api-ssl|ssh|winbox)\$")) do={ :set ($err->[:len $err]) ("global.rsc: services nennt unbekannten Dienst " . $sn . " (RouterOS-Namen: telnet, ftp, www, www-ssl, reverse-proxy, api, api-ssl, ssh, winbox)") }
    :local pk [:tostr $sp]
    :if ([:typeof ($svp->$pk)] != "nothing") do={ :set ($err->[:len $err]) ("global.rsc: services: Port " . $pk . " doppelt (" . ($svp->$pk) . ", " . $sn . ")") }
    :set ($svp->$pk) $sn
  }
  # Zonen-Matrix, Management-Zugang, MGMT-VLAN
  :foreach z,to in=($cfmG->"policy") do={
    :if ([:typeof ($zones->$z)] = "nothing") do={ :set ($err->[:len $err]) ("global.rsc: policy nennt Zone " . $z . ", kein VLAN hat diese Zone") }
    :foreach t0 in=[:toarray $to] do={
      :local pt [$cfmTarget $t0]
      :local t ($pt->"t")
      :local al ([:pick $t 0 6] = "allow:")
      :if ($al) do={
        :if ([:typeof ($cfmG->"allow"->[:pick $t 6 [:len $t]])] != "array") do={ :set ($err->[:len $err]) ("global.rsc: policy " . $z . " -> " . $t0 . ": Liste fehlt in allow") }
      } else={
        :if ($t != "*" and $t != "wan" and $t != "mtupdate" and [:typeof ($zones->$t)] = "nothing") do={ :set ($err->[:len $err]) ("global.rsc: policy " . $z . " -> unbekannte Zone " . $t) }
      }
      # NAT-Kennzeichen (D38): nur für Ziele ins Internet bzw. Freigabelisten, Adresse gültig
      :local nat [:tostr ($pt->"nat")]
      :if ([:len $nat] > 0) do={
        :if ($t != "wan" and $t != "mtupdate" and !$al) do={ :set ($err->[:len $err]) ("global.rsc: policy " . $z . " -> " . $t0 . ": NAT nur für wan, mtupdate und allow:<Liste>") }
        :if ($nat != "masq" and [:typeof [:toip $nat]] != "ip") do={ :set ($err->[:len $err]) ("global.rsc: policy " . $z . " -> " . $t0 . ": ungültiges NAT-Kennzeichen (*ziel oder ziel@Adresse)") }
      }
    }
  }
  :foreach ln,lst in=($cfmG->"allow") do={
    :if ([:typeof $lst] != "array") do={ :set ($err->[:len $err]) ("global.rsc: allow " . $ln . " ist keine Liste") } else={
      # Ports je Eintrag (D76): "ziel:tcp/443,8883" bzw. "ziel:udp/123"; ein anderer Zusatz nach ":" ist ein
      # Tippfehler (sonst würde er als Hostname aufgelöst)
      :foreach h in=$lst do={
        :local e [:tostr $h]
        :local c [:find $e ":"]
        :if ([:typeof $c] != "nil") do={
          :local sp [:pick $e ($c + 1) [:len $e]]
          :if (!($sp ~ "^(tcp|udp)/[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*\$") or [:typeof [:find $sp ":"]] != "nil") do={ :set ($err->[:len $err]) ("global.rsc: allow " . $ln . ": " . $e . " - Ports als ziel:tcp/443,8883 oder ziel:udp/123") }
        }
      }
    }
  }
  :foreach z in=[:toarray ($cfmG->"mgmtAccess")] do={
    :if ([:typeof ($zones->$z)] = "nothing") do={ :set ($err->[:len $err]) ("global.rsc: mgmtAccess nennt unbekannte Zone " . $z) }
  }
  :if ([:typeof ($cfmVlans->[:tostr ($cfmG->"mgmtVlan")])] != "array") do={ :set ($err->[:len $err]) ("global.rsc: mgmtVlan " . ($cfmG->"mgmtVlan") . " fehlt in vlans.rsc") }

  # Inventar + Hostfiles
  :local ips ({})
  :local inv [$cfmInvLoad]
  :foreach n,d in=$inv do={
    :local ip [:tostr ($d->"ip")]
    :if ([:len $ip] > 0) do={
      :if ([:typeof ($ips->$ip)] != "nothing") do={ :set ($err->[:len $err]) ("inventory: MGMT-IP " . $ip . " doppelt (" . ($ips->$ip) . ", " . $n . ")") }
      :set ($ips->$ip) $n
    }
    :foreach r in=[:toarray ($d->"role")] do={
      :if (![$fex ($w . "/roles/" . $r . ".rsc")]) do={ :set ($err->[:len $err]) ("inventory: " . $n . ": Rolle " . $r . " ohne roles/" . $r . ".rsc") }
    }
    # AP mit wifi-qcom-ac (TODO 23): übernimmt vlan-id nicht vom CAPsMAN - Pakete aus dem letzten Status
    :if (("," . [:tostr ($d->"role")] . ",") ~ ",ap,") do={
      :local sp ""
      :onerror e in={ :set sp [:tostr ([:deserialize from=json [/file/get ($b . "/state/" . $n . "/status.dat") contents]]->"pkgs")] } do={}
      :if ($sp ~ "wifi-qcom-ac") do={ :set ($warn->[:len $warn]) ("inventory: " . $n . " hat das Paket wifi-qcom-ac - SSIDs bekommen dort ihr VLAN nicht vom CAPsMAN (TODO 23)") }
    }
    :local hf ($w . "/hosts/" . $n . ".rsc")
    :if (![$fex $hf]) do={ :set ($warn->[:len $warn]) ("inventory: " . $n . " hat kein hosts/" . $n . ".rsc") } else={
      :set cfmMgrData ([:tonsec [:timestamp]] / 1000000000)
      :set cfmHost ({})
      :local he ""
      :onerror e in={ /import file-name=$hf verbose=no } do={ :set he $e }
      :if ([:len $he] > 0) do={ :set ($err->[:len $err]) ("hosts/" . $n . ".rsc: " . $he) } else={
        # stp="none" (Bridge ohne RSTP, D40): Dann faengt niemand eine Schleife ab. Zwei Ports im
        # selben VLAN oder mehrere Trunks sind dort ein Fehler - auf einem normalen Switch dagegen
        # ueblich, deshalb nur bei stp="none" pruefen.
        :local nostp ([:tostr ($cfmHost->"stp")] = "none")
        :local uvid ({})
        :local trunks ({})
        :local specs ({})
        :foreach p,sp in=($cfmHost->"ports") do={ :set ($specs->[:len $specs]) ({$p;$sp}) }
        :if ([:len [:tostr ($cfmHost->"portDefault")]] > 0) do={ :set ($specs->[:len $specs]) ({"portDefault";($cfmHost->"portDefault")}) }
        :foreach ps in=$specs do={
          :local sp [:tostr ($ps->1)]
          :local pn $sp; :local arg ""
          :local c [:find $sp ":"]
          :if ([:typeof $c] != "nil") do={ :set pn [:pick $sp 0 $c]; :set arg [:pick $sp ($c + 1) [:len $sp]] }
          :local pr ($cfmProfiles->$pn)
          :if ([:typeof $pr] != "array") do={ :set ($err->[:len $err]) ("hosts/" . $n . ".rsc: " . ($ps->0) . ": unbekanntes Port-Profil " . $sp) } else={
            :if ([:tostr ($pr->"untag")] = "arg" and [:typeof ($cfmVlans->$arg)] != "array") do={ :set ($err->[:len $err]) ("hosts/" . $n . ".rsc: " . ($ps->0) . ": VLAN " . $arg . " fehlt in vlans.rsc") }
            # isoliertes VLAN ungetaggt an einem Port mit weiteren getaggten VLANs: kein Client-Port (D76)
            :if ([:tostr ($pr->"untag")] = "arg" and [:tostr ($cfmVlans->$arg->"isolate")] = "yes" and [:len [:tostr ($pr->"tag")]] > 0) do={ :set ($warn->[:len $warn]) ("hosts/" . $n . ".rsc: " . ($ps->0) . ": isoliertes VLAN " . $arg . " an einem Port mit getaggten VLANs - dort wird nicht isoliert (nur reine Access-Ports)") }
            :if ($nostp) do={
              :if ([:tostr ($pr->"untag")] = "arg") do={
                :if ([:typeof ($uvid->$arg)] != "nothing") do={
                  :set ($warn->[:len $warn]) ("hosts/" . $n . ".rsc: " . ($uvid->$arg) . " und " . ($ps->0) . " liegen beide untagged in VLAN " . $arg . "; mit stp=none faengt keine Bridge die Schleife ab")
                } else={ :set ($uvid->$arg) ($ps->0) }
              }
              :if ([:len [:tostr ($pr->"tag")]] > 0) do={ :set ($trunks->($ps->0)) 1 }
            }
          }
        }
        :if ([:len $trunks] > 1) do={
          :set ($warn->[:len $warn]) ("hosts/" . $n . ".rsc: mehrere Ports mit getaggten VLANs bei stp=none; mit stp=none faengt keine Bridge die Schleife ab")
        }
        # Bonds (D74): Modus, Slaves (nicht doppelt, nicht zugleich unter ports), Profil unter ports
        :local hsl ({})
        :foreach bn,bd in=($cfmHost->"bonds") do={
          :local bw ("hosts/" . $n . ".rsc: bonds " . $bn . ": ")
          :local md [:tostr ($bd->"mode")]
          :if ([:len $md] > 0 and $md != "802.3ad" and $md != "active-backup") do={ :set ($err->[:len $err]) ($bw . "mode " . $md . " (802.3ad oder active-backup)") }
          :if ([:len [:tostr ($bd->"slaves")]] = 0) do={ :set ($err->[:len $err]) ($bw . "slaves fehlt") }
          :foreach x in=[:toarray ($bd->"slaves")] do={
            :if ([:typeof ($hsl->$x)] != "nothing") do={ :set ($err->[:len $err]) ($bw . "Port " . $x . " steckt schon in " . ($hsl->$x)) }
            :set ($hsl->$x) $bn
            :if ([:typeof ($cfmHost->"ports"->$x)] != "nothing") do={ :set ($warn->[:len $warn]) ($bw . "Port " . $x . " ist Slave, sein Eintrag unter ports gilt nicht") }
          }
          :local pp [:tostr ($bd->"primary")]
          :if ([:len $pp] > 0 and [:typeof ($hsl->$pp)] = "nothing") do={ :set ($err->[:len $err]) ($bw . "primary " . $pp . " ist kein Slave") }
          :if ([:typeof ($cfmHost->"ports"->$bn)] = "nothing") do={ :set ($warn->[:len $warn]) ($bw . "kein Profil unter ports - der Bond kommt nicht in die Bridge") }
        }
        # MLAG (D75): Ports aus mlag.rsc nicht zugleich im Hostfile, kein stp=none
        :local hm [$cfmMlagOf $n]
        :if ([:len $hm] > 0) do={
          :local mw ("mlag.rsc: " . ($hm->"pair") . ": " . $n . ": ")
          :local mps ({})
          :foreach x in=[:toarray ($hm->"peerSlaves")] do={ :set ($mps->$x) ($hm->"peer") }
          :foreach bn,bd in=($hm->"bonds") do={
            :foreach x in=[:toarray ($bd->"slaves")] do={
              :if ([:typeof ($mps->$x)] != "nothing") do={ :set ($err->[:len $err]) ($mw . "Port " . $x . " steckt in " . ($mps->$x) . " und " . $bn) }
              :set ($mps->$x) $bn
            }
            :if ([:typeof ($cfmHost->"bonds"->$bn)] != "nothing" or [:typeof ($cfmHost->"ports"->$bn)] != "nothing") do={ :set ($err->[:len $err]) ($mw . "Bond " . $bn . " steht auch im Hostfile") }
          }
          :foreach x,bn in=$mps do={
            :if ([:typeof ($hsl->$x)] != "nothing" or [:typeof ($cfmHost->"ports"->$x)] != "nothing") do={ :set ($err->[:len $err]) ($mw . "Port " . $x . " (" . $bn . ") steht auch im Hostfile unter ports/bonds") }
          }
          :if ([:tostr ($cfmHost->"stp")] = "none") do={ :set ($err->[:len $err]) ($mw . "stp=none - MLAG braucht auf beiden Knoten dieselbe STP-Einstellung") }
          :local sp [:tostr ($hm->"stp")]
          :if ([:len $sp] = 0) do={ :set sp [:tostr ($cfmHost->"stpPrio")] }
          :if ([:len $sp] = 0) do={ :set sp "0x8000" }
          :set ($mstp->$n) [:tonum $sp]
        }
        # erwartete Verkabelung ("links", D33): Gegenstelle sollte im Inventar stehen
        :foreach lp,lw in=($cfmHost->"links") do={
          :local pe [:tostr $lw]
          :local c2 [:find $pe ":"]
          :if ([:typeof $c2] != "nil") do={ :set pe [:pick $pe 0 $c2] }
          :if ($pe != "-" and [:typeof ($inv->$pe)] != "array") do={ :set ($warn->[:len $warn]) ("hosts/" . $n . ".rsc: links " . $lp . ": " . $pe . " steht nicht im Inventar") }
        }
        # eigene Radios des CAPsMAN (TODO 24): wirken nur auf dem CAPsMAN
        :if ([:tostr ($cfmHost->"capsmanRadios")] = "yes") do={
          :local rl ("," . [:tostr ($d->"role")] . ",")
          :if (!($rl ~ ",capsman,") and !($rl ~ ",manager,")) do={ :set ($warn->[:len $warn]) ("hosts/" . $n . ".rsc: capsmanRadios ohne Rolle capsman - wirkt nur auf dem CAPsMAN") }
        }
      }
    }
  }
  # MLAG-Paare (D75): zwei Knoten aus dem Inventar im selben Ring, Primary einer davon, Peer- und
  # Bond-Ports je Knoten, mlag-id eindeutig, gleiche STP-Priorität, Knoten nur in einem Paar
  :local mnode ({})
  :foreach pn,p in=$cfmMlag do={
    :local mw ("mlag.rsc: " . $pn . ": ")
    :local pk do={ :if ([:typeof $1] = "array") do={ :return [:tostr ($1->$2)] }; :return [:tostr $1] }
    :local nodes [:toarray ($p->"nodes")]
    :if ([:len $nodes] != 2) do={ :set ($err->[:len $err]) ($mw . "nodes braucht genau zwei Geräte") } else={
      :foreach x in=$nodes do={
        :if ([:typeof ($inv->$x)] != "array") do={ :set ($err->[:len $err]) ($mw . $x . " steht nicht im Inventar") }
        :if ([:typeof ($mnode->$x)] != "nothing") do={ :set ($err->[:len $err]) ($mw . $x . " ist schon Knoten von " . ($mnode->$x)) }
        :set ($mnode->$x) $pn
        :if ([:len [$pk ($p->"peer") $x]] = 0) do={ :set ($err->[:len $err]) ($mw . "peer: keine Ports für " . $x) }
      }
      :local n0 [:pick $nodes 0]; :local n1 [:pick $nodes 1]
      :local r0 [:tostr ($inv->$n0->"ring")]; :local r1 [:tostr ($inv->$n1->"ring")]
      :if ([:len $r0] = 0) do={ :set r0 "2" }
      :if ([:len $r1] = 0) do={ :set r1 "2" }
      :if ($r0 != $r1) do={ :set ($err->[:len $err]) ($mw . $n0 . " (Ring " . $r0 . ") und " . $n1 . " (Ring " . $r1 . ") in denselben Ring legen - sonst läuft ein Knoten mit MLAG, der andere ohne") }
      :if ([:typeof [:find $nodes [:tostr ($p->"primary")]]] = "nil") do={ :set ($err->[:len $err]) ($mw . "primary muss " . $n0 . " oder " . $n1 . " sein") }
      :if ([:typeof ($mstp->$n0)] = "num" and [:typeof ($mstp->$n1)] = "num" and ($mstp->$n0) != ($mstp->$n1)) do={ :set ($err->[:len $err]) ($mw . "STP-Priorität von " . $n0 . " und " . $n1 . " verschieden - stpPrio im Paar setzen") }
      :local ids ({})
      :foreach bn,bd in=($p->"bonds") do={
        :local id [:tonum ($bd->"id")]
        :if ([:typeof $id] != "num" or $id < 1) do={ :set ($err->[:len $err]) ($mw . "bonds " . $bn . ": id fehlt (Zahl ab 1)") } else={
          :if ([:typeof ($ids->[:tostr $id])] != "nothing") do={ :set ($err->[:len $err]) ($mw . "mlag-id " . $id . " doppelt (" . ($ids->[:tostr $id]) . ", " . $bn . ")") }
          :set ($ids->[:tostr $id]) $bn
        }
        :foreach x in=$nodes do={ :if ([:len [$pk ($bd->"ports") $x]] = 0) do={ :set ($err->[:len $err]) ($mw . "bonds " . $bn . ": keine Ports für " . $x) } }
        :local pe [$profOk ($bd->"profile")]
        :if ([:len $pe] > 0) do={ :set ($err->[:len $err]) ($mw . "bonds " . $bn . ": " . $pe) }
      }
    }
  }
  # CAPsMAN (D45): höchstens ein Gerät mit Rolle capsman (kein Standby: ein zweiter aktiver CAPsMAN
  # verteilt eine zweite CA, CAPs hängen dann am falschen). Ohne übernimmt übergangsweise der Primary.
  :if ([:len ($cfmWifi->"ssids")] > 0) do={
    :local cmn ({})
    :foreach n,d in=$inv do={ :if (("," . [:tostr ($d->"role")] . ",") ~ ",capsman,") do={ :set ($cmn->[:len $cmn]) $n } }
    :if ([:len $cmn] = 0) do={ :set ($warn->[:len $warn]) "inventory: kein Gerät mit Rolle capsman – CAPsMAN bleibt übergangsweise auf dem Primary-Manager (D45)" }
    :if ([:len $cmn] > 1) do={ :set ($err->[:len $err]) ("inventory: Rolle capsman mehrfach vergeben (" . [:tostr $cmn] . ") – nur ein CAPsMAN vorgesehen (D45)") }
  }
  # Benachrichtigungen (D66): URL mit http(s)://, Zeiten lesbar
  :local nfy ($cfmG->"notify")
  :if ([:typeof $nfy] = "array") do={
    :local nu [:tostr ($nfy->"url")]
    :if ([:len $nu] > 0 and !($nu ~ "^https?://[^/]+")) do={ :set ($err->[:len $err]) ("global.rsc: notify url " . $nu . " ist keine http(s)-URL") }
    :foreach nk in={"stale";"licWarn"} do={
      :local nv [:tostr ($nfy->$nk)]
      :local tok false
      :onerror x in={ :if ([:typeof [:totime $nv]] = "time") do={ :set tok true } } do={}
      :if ([:len $nv] > 0 and !$tok) do={ :set ($err->[:len $err]) ("global.rsc: notify " . $nk . "=" . $nv . " ist keine Zeitangabe (z.B. 30m, 14d)") }
    }
  } else={ :if ([:typeof $nfy] != "nothing") do={ :set ($err->[:len $err]) "global.rsc: notify muss ein Array sein ({\"url\"=…})" } }
  # API-Zugang auf dem CAPsMAN (D47): Adressen gültig, Passwort im Vault
  :local capi ($cfmG->"capsmanApi")
  :if ([:typeof $capi] = "array") do={
    :if ([:len ($capi->"from")] > 0) do={
      :foreach a in=($capi->"from") do={
        :local ip [:tostr $a]
        :if ([:typeof [:find $ip "/"]] != "nil") do={ :set ip [:pick $ip 0 [:find $ip "/"]] }
        :if ([:typeof [:toip $ip]] != "ip") do={ :set ($err->[:len $err]) ("global.rsc: capsmanApi from: " . $a . " ist keine IPv4-Adresse/kein Netz") }
      }
      :local au [:tostr ($capi->"user")]
      :if ([:len $au] = 0) do={ :set au "homeassistant" }
      :if ([:typeof ($cfmG->"users"->$au)] != "nothing") do={ :set ($err->[:len $err]) ("global.rsc: capsmanApi user " . $au . " steht auch in users (Admin) - eigenen Namen wählen") }
      :if ([:len [$cfmVaultGet ("user." . $au)]] = 0) do={ :set ($warn->[:len $warn]) ("Vault: Passwort des API-Users fehlt, \$cfmSecret key=user." . $au . " value=...") }
    }
  }
  # SNMPv3 für LibreNMS (TODO 54): Adressen, Protokoll, Passwörter im Vault (RouterOS: mindestens 8 Zeichen)
  :local snmp ($cfmG->"snmp")
  :if ([:typeof $snmp] = "array") do={
    :if ([:len ($snmp->"from")] > 0) do={
      :foreach a in=($snmp->"from") do={
        :local ip [:tostr $a]
        :if ([:typeof [:find $ip "/"]] != "nil") do={ :set ip [:pick $ip 0 [:find $ip "/"]] }
        :if ([:typeof [:toip $ip]] != "ip") do={ :set ($err->[:len $err]) ("global.rsc: snmp from: " . $a . " ist keine IPv4-Adresse/kein Netz") }
      }
      :local sa [:tostr ($snmp->"auth")]
      :if ([:len $sa] > 0 and !($sa ~ "^(SHA1|SHA256|SHA384|SHA512)\$")) do={ :set ($err->[:len $err]) ("global.rsc: snmp auth=" . $sa . " unbekannt (SHA1|SHA256|SHA384|SHA512)") }
      :foreach k in={"snmp.auth";"snmp.priv"} do={
        :local pw [$cfmVaultGet $k]
        :if ([:len $pw] = 0) do={ :set ($warn->[:len $warn]) ("Vault: SNMP-Passwort fehlt, \$cfmSecret key=" . $k . " value=...") } else={
          :if ([:len $pw] < 8) do={ :set ($err->[:len $err]) ("Vault: " . $k . " ist kürzer als 8 Zeichen (RouterOS lehnt es ab)") }
        }
      }
    }
  } else={ :if ([:typeof $snmp] != "nothing") do={ :set ($err->[:len $err]) "global.rsc: snmp muss ein Array sein ({\"from\"=…})" } }
  :local slf [:tostr ($cfmG->"syslogFormat")]
  :if ([:len $slf] > 0 and $slf != "syslog" and $slf != "default") do={ :set ($err->[:len $err]) ("global.rsc: syslogFormat=" . $slf . " unbekannt (syslog|default)") }
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
    # threshold (Steering) oder drop (Trennschwelle, TODO 61, D92) - eines von beiden
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
        :if ($jn = $dr) do={ :set ($warn->[:len $warn]) ("wifi.rsc: steer " . $bb . ": join = drop - am Rand pendelt ein Client (getrennt, Sekunden später wieder angemeldet); join einige dB über drop setzen (D92)") }
      }
      # isolierte VLANs (D76) bleiben ausgenommen: ihr datapath trägt schon in cfm-iso ein
      :foreach k,s in=($cfmWifi->"ssids") do={
        :if ([:tostr ($cfmVlans->[:tostr ($s->"vlan")]->"isolate")] = "yes" and ($k = [:tostr ($cfmWifi->"master")] or (("," . ($s->"bands") . ",") ~ ("," . $bb . ",")))) do={
          :set ($warn->[:len $warn]) ("wifi.rsc: steer " . $bb . ": drop gilt nicht für SSID " . $k . " (VLAN " . [:tostr ($s->"vlan")] . " isoliert, D76/D92)")
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
    :if ([:tostr ($s->"fallback")] = "yes" and $k = [:tostr ($cfmWifi->"master")]) do={ :set ($warn->[:len $warn]) ("wifi.rsc: fallback an der Master-SSID " . $k . " ist überflüssig (D46)") }
  }
  # Persönliche Admin-SSH-Keys je User (work/authorized_keys.<user>, OpenSSH-Format, D65): optional,
  # grobe Zeilenprüfung (kein RouterOS-Skript, daher kein :parse möglich). RouterOS kennt nur
  # rsa, ed25519 und ed25519-sk. Die gemeinsame Datei authorized_keys (D35) gilt nicht mehr.
  :if ([$fex ($w . "/authorized_keys")]) do={ :set ($err->[:len $err]) "authorized_keys: die gemeinsame Datei gilt nicht mehr (D65) - Keys je Person nach authorized_keys.<user> verschieben und die Datei löschen" }
  :foreach f in=[/file/find where name~("^" . $w . "/authorized_keys\\.") and type!="directory"] do={
    :local fn [/file/get $f name]
    :local rel [:pick $fn ([:len $w] + 1) [:len $fn]]
    :local u [:pick $rel 16 [:len $rel]]
    :if ([:typeof ($cfmG->"users"->$u)] = "nothing") do={ :set ($warn->[:len $warn]) ($rel . ": " . $u . " steht nicht in global.rsc users - die Keys wirken nirgends") }
    :local ln 0
    :local t ([/file/get $f contents] . "\n")
    :while ([:len $t] > 0) do={
      :set ln ($ln + 1)
      :local p [:find $t "\n"]
      :local l [:pick $t 0 $p]
      :set t [:pick $t ($p + 1) [:len $t]]
      :if ([:len $l] > 0 and [:pick $l ([:len $l] - 1) [:len $l]] = "\r") do={ :set l [:pick $l 0 ([:len $l] - 1)] }
      :if ([:len $l] > 0 and [:pick $l 0 1] != "#") do={
        :local ok false
        :if ($l ~ "^(ssh-ed25519|ssh-rsa|sk-ssh-ed25519@openssh\\.com) [A-Za-z0-9+/]+=*( |\$)") do={ :set ok true }
        :if (!$ok) do={ :set ($err->[:len $err]) ($rel . ": Zeile " . $ln . ": kein gültiger OpenSSH-Public-Key (\"<typ> <base64> [kommentar]\", Typ ssh-ed25519, ssh-rsa oder sk-ssh-ed25519@openssh.com, keine Optionen wie command=... davor)") }
      }
    }
  }

  # Hostfiles setzen u.U. Overrides in cfmG -> Daten neu laden
  :onerror e in={ $cfmLoadData ver=0 dir=$dir } do={}
  :return ({"err"=$err;"warn"=$warn})
}

# ---------- Probelauf (D29) ----------
# Schnappschuss von work/ nach plan/, signiertes Plan-Manifest für den Host; das Gerät führt
# die Rollen im Trockenlauf aus (cfmDry, *.post.rsc übersprungen) und schreibt die Änderungen
# nach cfm/out/plan.txt. Gestartet per :execute (ssh-exec bricht lange Befehle ab), das
# Ergebnis holt der Manager per SFTP ab und erkennt es an einer Kennung (id).
# from=<verzeichnis>: Schnappschuss aus <mgrPath>/<verzeichnis>/ statt work/ (ein vollständiger
# Stand wie work/, z.B. das Zielbild eines Umbaus), role=<rollen>: statt der Rollen aus dem Inventar.
# Beides wirkt nur auf diesen Probelauf; work/ und das Inventar bleiben unberührt.
:global cfmPlan do={
  :global cfmMB; :global cfmInvLoad; :global cfmWrite; :global cfmExec; :global cfmManifests
  :global cfmCheck; :global cfmParseWork; :global cfmFileEx
  :if ([:len $host] = 0) do={ :error "Aufruf: \$cfmPlan host=<name> [from=<verzeichnis>] [role=<rollen>]" }
  :local d ([$cfmInvLoad]->$host)
  :if ([:typeof $d] != "array") do={ :error ("unbekannter Host " . $host) }
  :local b [$cfmMB]
  :local src "work"
  :if ([:len $from] > 0) do={
    :if (!($from ~ "^[A-Za-z0-9_-]+\$") or $from ~ "^(work|plan|archive|live|meta|state|pkg|out|dl)\$") do={ :error ("from=" . $from . ": nur ein eigenes Verzeichnis unter " . $b . "/ (Buchstaben, Ziffern, - und _)") }
    :if (![$cfmFileEx ($b . "/" . $from . "/lib/mgr-core.rsc")] or ![$cfmFileEx ($b . "/" . $from . "/global.rsc")]) do={ :error ($b . "/" . $from . "/ ist kein vollständiger Stand (lib/mgr-core.rsc, global.rsc fehlen)") }
    :set src $from
  }
  :if ([:len $role] > 0 and !($role ~ "^[a-z-]+(,[a-z-]+)*\$")) do={ :error ("role=" . $role . ": Rollen kommagetrennt, z.B. switch,router") }
  :if ($src != "work" or [:len $role] > 0) do={
    :local rr [:tostr ($d->"role")]
    :if ([:len $role] > 0) do={ :set rr $role }
    :put ("Probelauf aus " . $b . "/" . $src . "/, Rollen " . $rr . " (work/ und Inventar bleiben unberührt)")
  }
  :local bad [$cfmParseWork dir=$src]
  :if ([:len $bad] > 0) do={ :error ("Probelauf abgebrochen:" . $bad) }
  :local ck [$cfmCheck dir=$src]
  :foreach e in=($ck->"err") do={ :put ("Fehler (ein Release würde abbrechen): " . $e) }
  :foreach w in=($ck->"warn") do={ :put ("Warnung: " . $w) }
  # Schnappschuss work/ (bzw. from=) -> plan/
  :foreach f in=[/file/find where name~("^" . $b . "/plan/") and type!="directory"] do={ /file/remove $f }
  :local idx ({})
  :foreach f in=[/file/find where name~("^" . $b . "/" . $src . "/") and type!="directory"] do={
    :local n [/file/get $f name]
    :local rel [:pick $n ([:len $b] + [:len $src] + 2) [:len $n]]
    :local c [/file/get $f contents]
    $cfmWrite ($b . "/plan/" . $rel) $c
    :set ($idx->$rel) [:convert $c transform=sha512 to=hex]
  }
  $cfmWrite ($b . "/plan/index.dat") [:serialize to=json ({"v"=0;"msg"="plan";"files"=$idx})]
  :if ([$cfmManifests plan=$host role=$role] = 0) do={ :error ("kein Plan-Manifest für " . $host . " (Geräteschlüssel oder Pflichtdateien fehlen, siehe Log)") }
  :local id [:rndstr length=12 from="0123456789abcdef"]
  # show=yes: alle Soll-Objekte statt der Änderungen ($cfmShow objects=yes, D61)
  :local sh ""
  :if ($show = "yes") do={ :set sh ";\\\"show\\\"=\\\"yes\\\"" }
  :local c (":execute \":global cfmArg {\\\"mode\\\"=\\\"plan\\\";\\\"id\\\"=\\\"" . $id . "\\\"" . $sh . "}; /system script run cfm-agent\"")
  :local r [$cfmExec ip=($d->"ip") cmd=$c]
  :if (($r->"exit-code") != 0) do={ :error ("Gerät nicht erreichbar: " . ($r->"output")) }
  :put ("Probelauf auf " . $host . " läuft ...")
  :local lf ($b . "/state/" . $host . "/plan.txt")
  :local got false
  :local i 0
  :while (!$got and $i < 60) do={
    :delay 3s
    :set i ($i + 1)
    :foreach p in={"cfm/out";"flash/cfm/out"} do={
      :if (!$got) do={
        :onerror e in={
          /tool/fetch url=("sftp://" . ($d->"ip") . "/" . $p . "/plan.txt") user="cfm" dst-path=$lf as-value
          :if ([:pick [/file/get [find where name=$lf] contents] 0 17] = ("# id=" . $id)) do={ :set got true }
        } do={}
      }
    }
  }
  :if (!$got) do={ :error "keine Antwort vom Probelauf (Agent beschäftigt?) - später erneut" }
  :local pc [/file/get [find where name=$lf] contents]
  :global cfmPutLines; $cfmPutLines $pc
  :if ($show = "yes" and [:typeof [:find $pc "# Soll-Objekte"]] = "nil") do={ :put ("Hinweis: Der Agent auf " . $host . " kennt die Objektliste noch nicht (erst nach dem nächsten Release) - oben steht der normale Plan") }
  :return ""
}
