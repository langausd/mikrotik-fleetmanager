# ============================================================
# cfm lib/mgr-check.rsc – Manager-Funktionen: inhaltliche Prüfung und Probelauf
#   $cfmCheck            prüft die Daten in work/ (läuft auch bei jedem $cfmRelease, DG2.4)
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
  :global cfmMlag; :global cfmMlagOf; :global cfmDns; :global cfmKib
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
  # mlag.rsc (DP2.2) selbst laden: $cfmLoadData des installierten Managers kennt sie vor DP2.2 nicht
  :set cfmMlag ({})
  :if ([$fex ($w . "/mlag.rsc")]) do={ :onerror e in={ /import file-name=($w . "/mlag.rsc") verbose=no } do={ :set ($err->[:len $err]) ("mlag.rsc: " . $e) } }
  # dns.rsc (DN3.1) ebenso
  :set cfmDns ({})
  :if ([$fex ($w . "/dns.rsc")]) do={ :onerror e in={ /import file-name=($w . "/dns.rsc") verbose=no } do={ :set ($err->[:len $err]) ("dns.rsc: " . $e) } }
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
  # VLANs der AP-Uplinks (Client-VLAN je MAC unten; WLAN und PPSK prüft lib/mgr-checkw.rsc)
  :local apTag [:tostr ($cfmProfiles->"trunk-ap"->"tag")]
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
  # dhcpGw (DN1.2): Host-Anteil, nur mit dhcp, nicht im Pool, nicht das Gateway selbst
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
  # Feste Leases (DN1.1): VLAN mit DHCP der Router, Name als DNS-Label (eindeutig, kein Gerätename),
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
          # Client-VLAN je MAC (DW2.6): ein Gerät mit zufälliger MAC je SSID landet nach einem Wechsel wieder im
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
  # NTP-Umleitung (DN2.2): nur "redirect", braucht ein Router-Interface
  :foreach vid,v in=$cfmVlans do={
    :local nt [:tostr ($v->"ntp")]
    :if ([:len $nt] > 0 and $nt != "redirect") do={ :set ($err->[:len $err]) ("vlans.rsc: VLAN " . $vid . ": ntp " . $nt . " (nur redirect)") }
    :if ($nt = "redirect" and [:tostr ($v->"l3")] = "no") do={ :set ($warn->[:len $warn]) ("vlans.rsc: VLAN " . $vid . ": ntp redirect ohne Router (l3=no) wirkt nicht") }
  }
  # DNS der Router (DN3.1): Adressen gültig, Größe lesbar, Adlisten per https, Domains ohne Leerzeichen,
  # Log-Schalter; unbekannte Schlüssel (Tippfehler) als Warnung
  :local dn "dns.rsc: "
  :local dnOk do={ :return ([:tostr $1] ~ "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)+\\.?\$") }
  :foreach k,v in=$cfmDns do={
    :if (!($k ~ "^(servers|cache|adlists|allow|forward|log|self)\$")) do={ :set ($warn->[:len $warn]) ($dn . "unbekannter Schlüssel " . $k . " (servers, cache, adlists, allow, forward, log, self)") }
  }
  :foreach a in=($cfmDns->"servers") do={ :if ([:typeof [:toip $a]] != "ip") do={ :set ($err->[:len $err]) ($dn . "servers: " . $a . " ist keine IPv4-Adresse") } }
  :local dc [:tostr ($cfmDns->"cache")]
  :if ([:len $dc] > 0 and [:typeof [$cfmKib $dc]] != "num") do={ :set ($err->[:len $err]) ($dn . "cache " . $dc . " (z.B. 64M, Einheiten k/M/G oder KiB als Zahl)") }
  :if ([:len ($cfmDns->"adlists")] > 0 and [:len $dc] = 0) do={ :set ($warn->[:len $warn]) ($dn . "adlists ohne cache - die Listen liegen im DNS-Cache (RouterOS-Standard 2M), je 100 000 Namen gut 7 MB") }
  :foreach u in=($cfmDns->"adlists") do={
    :local us [:tostr $u]
    :if ([:pick $us 0 8] != "https://") do={
      :if ([:pick $us 0 7] = "http://") do={ :set ($warn->[:len $warn]) ($dn . "adlists: " . $us . " ohne https (keine Zertifikatsprüfung)") } else={ :set ($err->[:len $err]) ($dn . "adlists: " . $us . " ist keine http(s)-URL") }
    }
  }
  :foreach a in=($cfmDns->"allow") do={ :if (![$dnOk $a]) do={ :set ($err->[:len $err]) ($dn . "allow: " . $a . " ist kein Domainname") } }
  :foreach fd,fs in=($cfmDns->"forward") do={
    :if (![$dnOk $fd]) do={ :set ($err->[:len $err]) ($dn . "forward: " . $fd . " ist kein Domainname") }
    :foreach a in=[:toarray $fs] do={ :if ([:typeof [:toip $a]] != "ip") do={ :set ($err->[:len $err]) ($dn . "forward " . $fd . ": " . $a . " ist keine IPv4-Adresse") } }
  }
  :local dlm ($cfmDns->"log"->"memory")
  :if ([:len [:tostr $dlm]] > 0 and !([:tostr $dlm] ~ "^[0-9]+\$")) do={ :set ($err->[:len $err]) ($dn . "log memory " . $dlm . " (Zeilen als Zahl, 0 = aus)") }
  :local dls [:tostr ($cfmDns->"log"->"syslog")]
  :if ([:len $dls] > 0 and $dls != "yes" and $dls != "no") do={ :set ($err->[:len $err]) ($dn . "log syslog " . $dls . " (yes oder no)") }
  :if ($dls = "yes" and [:len [:tostr ($cfmG->"syslog")]] = 0) do={ :set ($warn->[:len $warn]) ($dn . "log syslog=yes wirkt nur mit syslog in global.rsc") }
  # DNS-Selbstbedienung (DN3.2): Zonen vorhanden, deny als Domainnamen, hours 1..168, User-Name, RAM-Log nötig
  :local ds ($cfmDns->"self")
  :if ([:typeof $ds] = "array") do={
    :foreach k,v in=$ds do={ :if (!($k ~ "^(zones|deny|hours|user)\$")) do={ :set ($warn->[:len $warn]) ($dn . "self: unbekannter Schlüssel " . $k . " (zones, deny, hours, user)") } }
    :if ([:len ($ds->"zones")] = 0) do={ :set ($warn->[:len $warn]) ($dn . "self ohne zones - Selbstbedienung aus") }
    :foreach z in=($ds->"zones") do={
      :local zf false
      :foreach vid,v in=$cfmVlans do={ :if ([:tostr ($v->"zone")] = $z and [:tostr ($v->"l3")] != "no") do={ :set zf true } }
      :if (!$zf) do={ :set ($err->[:len $err]) ($dn . "self zones: keine geroutete Zone " . $z . " in vlans.rsc") }
    }
    :foreach a in=($ds->"deny") do={ :if (![$dnOk $a] or [:tostr $a] ~ "[A-Z]") do={ :set ($err->[:len $err]) ($dn . "self deny: " . $a . " ist kein Domainname (klein geschrieben)") } }
    :local sh [:tostr ($ds->"hours")]
    :if ([:len $sh] > 0 and (!($sh ~ "^[0-9]+\$") or [:tonum $sh] < 1 or [:tonum $sh] > 168)) do={ :set ($err->[:len $err]) ($dn . "self hours " . $sh . " (Stunden, 1 bis 168)") }
    :local su [:tostr ($ds->"user")]
    :if ([:len $su] = 0) do={ :set su "dns" }
    :if (!($su ~ "^[a-z][a-z0-9_-]*\$") or [:typeof ($cfmG->"users"->$su)] != "nothing" or $su = [:tostr ($cfmG->"capsmanApi"->"user")]) do={ :set ($err->[:len $err]) ($dn . "self user " . $su . " (Kleinbuchstaben, nicht einer der users oder der capsmanApi-User)") }
    :if ([:len ($ds->"zones")] > 0) do={
      :if ([:len [$cfmVaultGet ("user." . $su)]] = 0) do={ :set ($warn->[:len $warn]) ($dn . "self: Passwort fehlt, \$cfmSecret key=user." . $su . " value=... (bis dahin ist der User aus)") }
      :if ([:tonum $dlm] = 0 or [:len [:tostr $dlm]] = 0) do={ :set ($err->[:len $err]) ($dn . "self braucht log memory (das Lesezeichen liest den RAM-Puffer cfmdns)") }
      :if ([:len [:tostr ($cfmG->"notify"->"url")]] = 0) do={ :set ($warn->[:len $warn]) ($dn . "self ohne notify.url in global.rsc - Freischaltungen werden nicht gemeldet") }
      :if ([:len ($cfmDns->"servers")] = 0) do={ :set ($warn->[:len $warn]) ($dn . "self ohne servers: Freischaltungen gehen an wan.dns der Router, ein Router ohne wan.dns bekommt keine Selbstbedienung") }
    }
  }
  # Asymmetrisches Routing (DR3.2): nur "internet". Der Verkehr ins Internet läuft ohne conntrack - mit NAT
  # der Zone setzen die Router kein notrack (Warnung, Hostfiles können die policy überschreiben), NTP-Umleitung
  # und Limit greifen dafür nicht bzw. nur im Upload
  :foreach vid,v in=$cfmVlans do={
    :local ar [:tostr ($v->"asymRouting")]
    :if ([:len $ar] > 0) do={
      :local vw ("vlans.rsc: VLAN " . $vid . ": asymRouting ")
      :if ($ar != "internet") do={ :set ($err->[:len $err]) ($vw . $ar . " (nur internet)") }
      :if ([:tostr ($v->"l3")] = "no") do={ :set ($warn->[:len $warn]) ($vw . "ohne Router (l3=no) wirkt nicht") }
      :if ([:tostr ($v->"ntp")] = "redirect") do={ :set ($warn->[:len $warn]) ($vw . "+ ntp redirect: NTP an Server im Internet wird nicht umgeleitet") }
      :if ([:len [:tostr ($v->"limit")]] > 0 or [:len [:tostr ($v->"limitClient")]] > 0) do={ :set ($warn->[:len $warn]) ($vw . "+ limit: bremst ins Internet nur den Upload (Antworten laufen am Router vorbei)") }
      :local z [:tostr ($v->"zone")]
      :foreach t0 in=[:toarray ($cfmG->"policy"->$z)] do={
        :local pt [$cfmTarget $t0]
        :if ([:len [:tostr ($pt->"nat")]] > 0) do={ :set ($warn->[:len $warn]) ($vw . "wirkt nicht, solange die Zone " . $z . " NAT hat (" . $t0 . ") - die Router setzen dann kein notrack") }
      }
    }
  }
  # Bandbreitenlimit (DR2.7): "Download/Upload" mit k/M/G, wirkt nur mit Router-Interface und Subnetz
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
  # Isolierte VLANs (DP3.1): isolate yes/no, Ausnahmen auflösbar (Name mit MAC in leases.rsc oder MAC),
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
      # NAT-Kennzeichen (DR2.3): nur für Ziele ins Internet bzw. Freigabelisten, Adresse gültig
      :local nat [:tostr ($pt->"nat")]
      :if ([:len $nat] > 0) do={
        :if ($t != "wan" and $t != "mtupdate" and !$al) do={ :set ($err->[:len $err]) ("global.rsc: policy " . $z . " -> " . $t0 . ": NAT nur für wan, mtupdate und allow:<Liste>") }
        :if ($nat != "masq" and [:typeof [:toip $nat]] != "ip") do={ :set ($err->[:len $err]) ("global.rsc: policy " . $z . " -> " . $t0 . ": ungültiges NAT-Kennzeichen (*ziel oder ziel@Adresse)") }
      }
    }
  }
  :foreach ln,lst in=($cfmG->"allow") do={
    :if ([:typeof $lst] != "array") do={ :set ($err->[:len $err]) ("global.rsc: allow " . $ln . " ist keine Liste") } else={
      # Ports je Eintrag (DP3.1): "ziel:tcp/443,8883" bzw. "ziel:udp/123"; ein anderer Zusatz nach ":" ist ein
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
  # Feature-Module (DG4.6): tools/upload-seed.sh lädt nur die hoch, die die Site-Daten nutzen. Schaltet eine Site ein
  # Feature danach ein (cfm-Editor, /file edit), fehlt sein Modul in work/ - die Geräte bekämen es nicht, ihr Apply
  # bräche ab (Rollback). Bedingungen wie in den Rollen (vor den Hostfiles: die ändern cfmG u.U.)
  :local fneed ({})
  :local rtr false
  :foreach n,d in=$inv do={ :if (("," . [:tostr ($d->"role")] . ",") ~ ",router,") do={ :set rtr true } }
  :if ($rtr and [:len $cfmDns] > 0) do={ :set ($fneed->"router.dns") "dns.rsc" }
  :if ($rtr and [:len ($cfmDns->"self"->"zones")] > 0) do={ :set ($fneed->"router.dnsreq") "dns.rsc self" }
  :if ($rtr and [:len ($cfmWg->"peers")] > 0) do={ :set ($fneed->"router.wg") "wireguard.rsc peers" }
  :if ([:typeof ($cfmG->"snmp")] = "array") do={ :if ([:len ($cfmG->"snmp"->"from")] > 0) do={ :set ($fneed->"base.snmp") "global.rsc snmp" } }
  :foreach vid,v in=$cfmVlans do={ :if ([:tostr ($v->"isolate")] = "yes") do={ :set ($fneed->"base.iso") ("vlans.rsc isolate, VLAN " . $vid) } }
  :foreach u,g in=($cfmG->"users") do={ :if ([$fex ($w . "/authorized_keys." . $u)]) do={ :set ($fneed->"base.sshkeys") ("authorized_keys." . $u) } }
  :foreach vid,v in=$cfmVlans do={ :if ($rtr and ([:len [:tostr ($v->"limit")]] > 0 or [:len [:tostr ($v->"limitClient")]] > 0)) do={ :set ($fneed->"router.limit") ("vlans.rsc limit, VLAN " . $vid) } }
  :if ([:len $cfmMlag] > 0) do={ :set ($fneed->"base.bond") "mlag.rsc" }
  # schaltbare SSIDs (DW4.1): Rümpfe der Skripte auf dem CAPsMAN; cfm-reprov braucht er immer
  :foreach k,s in=($cfmWifi->"ssids") do={
    :if ($k != [:tostr ($cfmWifi->"master")] and [:len [:tostr ($s->"switch")]] > 0) do={
      :set ($fneed->"capsman.ssid") ("wifi.rsc switch, SSID " . $k); :set ($fneed->"capsman.ssidcheck") ("wifi.rsc switch, SSID " . $k)
    }
  }
  :set ($fneed->"capsman.reprov") "CAPsMAN"
  # bonds im Hostfile: unten beim Import der Hostfiles, geprüft am Ende
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
        :if ([:len ($cfmHost->"bonds")] > 0) do={ :set ($fneed->"base.bond") ("hosts/" . $n . ".rsc bonds") }
        # stp="none" (Bridge ohne RSTP, DP1.2): Dann faengt niemand eine Schleife ab. Zwei Ports im
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
            # isoliertes VLAN ungetaggt an einem Port mit weiteren getaggten VLANs: kein Client-Port (DP3.1)
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
        # Bonds (DP2.1): Modus, Slaves (nicht doppelt, nicht zugleich unter ports), Profil unter ports
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
        # MLAG (DP2.2): Ports aus mlag.rsc nicht zugleich im Hostfile, kein stp=none
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
        # erwartete Verkabelung ("links", DU1.1): Gegenstelle sollte im Inventar stehen
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
  # MLAG-Paare (DP2.2): zwei Knoten aus dem Inventar im selben Ring, Primary einer davon, Peer- und
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
  # CAPsMAN (DW1.5): höchstens ein Gerät mit Rolle capsman (kein Standby: ein zweiter aktiver CAPsMAN
  # verteilt eine zweite CA, CAPs hängen dann am falschen). Ohne übernimmt übergangsweise der Primary.
  :if ([:len ($cfmWifi->"ssids")] > 0) do={
    :local cmn ({})
    :foreach n,d in=$inv do={ :if (("," . [:tostr ($d->"role")] . ",") ~ ",capsman,") do={ :set ($cmn->[:len $cmn]) $n } }
    :if ([:len $cmn] = 0) do={ :set ($warn->[:len $warn]) "inventory: kein Gerät mit Rolle capsman – CAPsMAN bleibt übergangsweise auf dem Primary-Manager (DW1.5)" }
    :if ([:len $cmn] > 1) do={ :set ($err->[:len $err]) ("inventory: Rolle capsman mehrfach vergeben (" . [:tostr $cmn] . ") – nur ein CAPsMAN vorgesehen (DW1.5)") }
  }
  # Benachrichtigungen (DU4.1): URL mit http(s)://, Zeiten lesbar
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
  # API-Zugang auf dem CAPsMAN (DU2.1): Adressen gültig, Passwort im Vault
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
  # WLAN (lib/mgr-checkw.rsc, TODO 73): aus demselben Stand wie die Daten laden - $cfmRelease importiert
  # nur diese Datei aus work/, die installierte WLAN-Prüfung wäre nach einem Framework-Update veraltet.
  # Fehlt die Datei im Stand (Probelauf aus einem alten Verzeichnis), prüft die installierte.
  :if ([$fex ($w . "/lib/mgr-checkw.rsc")]) do={ :onerror e in={ /import file-name=($w . "/lib/mgr-checkw.rsc") verbose=no } do={ :set ($err->[:len $err]) ("lib/mgr-checkw.rsc: " . $e) } }
  :global cfmCheckWifi
  :if ([:typeof $cfmCheckWifi] = "nothing") do={ :set ($err->[:len $err]) "lib/mgr-checkw.rsc fehlt: WLAN-Daten nicht geprüft - Framework hochladen: tools/upload-seed.sh" } else={
    :local cw [$cfmCheckWifi inv=$inv]
    :foreach x in=($cw->"err") do={ :set ($err->[:len $err]) $x }
    :foreach x in=($cw->"warn") do={ :set ($warn->[:len $warn]) $x }
  }
  # Persönliche Admin-SSH-Keys je User (work/authorized_keys.<user>, OpenSSH-Format, DS3.3): optional,
  # grobe Zeilenprüfung (kein RouterOS-Skript, daher kein :parse möglich). RouterOS kennt nur
  # rsa, ed25519 und ed25519-sk. Die gemeinsame Datei authorized_keys (DS3.2) gilt nicht mehr.
  :if ([$fex ($w . "/authorized_keys")]) do={ :set ($err->[:len $err]) "authorized_keys: die gemeinsame Datei gilt nicht mehr (DS3.3) - Keys je Person nach authorized_keys.<user> verschieben und die Datei löschen" }
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

  :foreach m,why in=$fneed do={
    :if (![$fex ($w . "/lib/" . $m . ".rsc")]) do={ :set ($err->[:len $err]) ("lib/" . $m . ".rsc fehlt, " . $why . " nutzt das Feature (DG4.6) - Framework hochladen: tools/upload-seed.sh") }
  }

  # Hostfiles setzen u.U. Overrides in cfmG -> Daten neu laden
  :onerror e in={ $cfmLoadData ver=0 dir=$dir } do={}
  :return ({"err"=$err;"warn"=$warn})
}

# ---------- Probelauf (DG3.4) ----------
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
  # show=yes: alle Soll-Objekte statt der Änderungen ($cfmShow objects=yes, DU1.2)
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
