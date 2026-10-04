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
  :global cfmNet; :global cfmTarget; :global cfmLeases; :global cfmMacUp
  :local b [$cfmMB]
  :local w ($b . "/work")
  :local err ({}); :local warn ({})
  :local le ""
  # Datei vorhanden? Über den Namen statt /file/find (TODO 21). Lokal statt $cfmFileEx, weil
  # $cfmRelease diesen Prüfer aus work/ lädt, während noch die alten Manager-Module laufen
  :local fex do={ :local r false; :onerror e in={ :if ([:len [/file/get $1 name]] > 0) do={ :set r true } } do={}; :return $r }
  :onerror e in={ $cfmLoadData ver=0 } do={ :set le $e }
  # Helfer aus lib/lib.rsc (lädt $cfmLoadData mit): fehlen sie, liefern Aufrufe stillschweigend
  # nichts und die Prüfung liefe halb blind
  :if ([:typeof $cfmNet] = "nothing" or [:typeof $cfmTarget] = "nothing") do={
    :set ($err->[:len $err]) "lib/lib.rsc nicht geladen: Prüfung von VLAN-Netzen und Policy-Zielen nicht möglich"
  }
  :if ([:len $le] > 0) do={ :set ($err->0) ("Daten in work/ nicht ladbar: " . $le); :return ({"err"=$err;"warn"=$warn}) }
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
  # Feste Leases (D62): VLAN mit DHCP der Router, Name als DNS-Label (eindeutig, kein Gerätename),
  # MAC und Adresse je VLAN eindeutig, Adresse im Netz und nicht die des Gateways
  :local lName ({})
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
        }
        :local h [:tonum ($ld->"ip")]
        :if ([:typeof $h] != "num" or $h < 1 or $h > $hmax) do={ :set ($err->[:len $err]) ($w . "ip = Host-Anteil 1-" . $hmax) } else={
          :if ($h = $gwh) do={ :set ($err->[:len $err]) ($w . "ip ist die Adresse des Gateways") }
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
    :if ([:typeof $lst] != "array") do={ :set ($err->[:len $err]) ("global.rsc: allow " . $ln . " ist keine Liste") }
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
  # CAPsMAN (D45): höchstens ein Gerät mit Rolle capsman (kein Standby: ein zweiter aktiver CAPsMAN
  # verteilt eine zweite CA, CAPs hängen dann am falschen). Ohne übernimmt übergangsweise der Primary.
  :if ([:len ($cfmWifi->"ssids")] > 0) do={
    :local cmn ({})
    :foreach n,d in=$inv do={ :if (("," . [:tostr ($d->"role")] . ",") ~ ",capsman,") do={ :set ($cmn->[:len $cmn]) $n } }
    :if ([:len $cmn] = 0) do={ :set ($warn->[:len $warn]) "inventory: kein Gerät mit Rolle capsman – CAPsMAN bleibt übergangsweise auf dem Primary-Manager (D45)" }
    :if ([:len $cmn] > 1) do={ :set ($err->[:len $err]) ("inventory: Rolle capsman mehrfach vergeben (" . [:tostr $cmn] . ") – nur ein CAPsMAN vorgesehen (D45)") }
  }
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
  # Kanal-Pinning (radios): bekannte APs, bekannte Bänder
  :foreach apn,pins in=($cfmWifi->"radios") do={
    :if ([:typeof ($inv->$apn)] != "array") do={ :set ($warn->[:len $warn]) ("wifi.rsc: radios nennt " . $apn . ", nicht im Inventar") } else={
      :if (!(("," . [:tostr ($inv->$apn->"role")] . ",") ~ ",(ap|capsman),")) do={ :set ($warn->[:len $warn]) ("wifi.rsc: radios nennt " . $apn . " ohne Rolle ap oder capsman (eigene Radios, capsmanRadios)") }
    }
    :foreach bb,ff in=$pins do={
      :if ([:typeof ($cfmWifi->"channels"->$bb)] != "array") do={ :set ($err->[:len $err]) ("wifi.rsc: radios " . $apn . ": Band " . $bb . " fehlt in channels") }
    }
  }
  # Steering je Band und Mindestsignal (TODO 39): Schwellen in dBm, Band muss es geben
  :foreach bb,st in=($cfmWifi->"steer") do={
    :if ([:typeof ($cfmWifi->"channels"->$bb)] != "array") do={ :set ($err->[:len $err]) ("wifi.rsc: steer: Band " . $bb . " fehlt in channels") }
    :local th [:tonum ($st->"threshold")]
    :if ([:typeof $th] != "num" or $th > -40 or $th < -100) do={ :set ($err->[:len $err]) ("wifi.rsc: steer " . $bb . ": threshold " . [:tostr ($st->"threshold")] . " ist kein Pegel in dBm (-100..-40)") }
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
  :onerror e in={ $cfmLoadData ver=0 } do={}
  :return ({"err"=$err;"warn"=$warn})
}

# ---------- Probelauf (D29) ----------
# Schnappschuss von work/ nach plan/, signiertes Plan-Manifest für den Host; das Gerät führt
# die Rollen im Trockenlauf aus (cfmDry, *.post.rsc übersprungen) und schreibt die Änderungen
# nach cfm/out/plan.txt. Gestartet per :execute (ssh-exec bricht lange Befehle ab), das
# Ergebnis holt der Manager per SFTP ab und erkennt es an einer Kennung (id).
:global cfmPlan do={
  :global cfmMB; :global cfmInvLoad; :global cfmWrite; :global cfmExec; :global cfmManifests
  :global cfmCheck; :global cfmParseWork
  :if ([:len $host] = 0) do={ :error "Aufruf: \$cfmPlan host=<name>" }
  :local d ([$cfmInvLoad]->$host)
  :if ([:typeof $d] != "array") do={ :error ("unbekannter Host " . $host) }
  :local b [$cfmMB]
  :local bad [$cfmParseWork]
  :if ([:len $bad] > 0) do={ :error ("Probelauf abgebrochen:" . $bad) }
  :local ck [$cfmCheck]
  :foreach e in=($ck->"err") do={ :put ("Fehler (ein Release würde abbrechen): " . $e) }
  :foreach w in=($ck->"warn") do={ :put ("Warnung: " . $w) }
  # Schnappschuss work/ -> plan/
  :foreach f in=[/file/find where name~("^" . $b . "/plan/") and type!="directory"] do={ /file/remove $f }
  :local idx ({})
  :foreach f in=[/file/find where name~("^" . $b . "/work/") and type!="directory"] do={
    :local n [/file/get $f name]
    :local rel [:pick $n ([:len $b] + 6) [:len $n]]
    :local c [/file/get $f contents]
    $cfmWrite ($b . "/plan/" . $rel) $c
    :set ($idx->$rel) [:convert $c transform=sha512 to=hex]
  }
  $cfmWrite ($b . "/plan/index.dat") [:serialize to=json ({"v"=0;"msg"="plan";"files"=$idx})]
  :if ([$cfmManifests plan=$host] = 0) do={ :error ("kein Plan-Manifest für " . $host . " (Geräteschlüssel oder Pflichtdateien fehlen, siehe Log)") }
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
  :put $pc
  :if ($show = "yes" and [:typeof [:find $pc "# Soll-Objekte"]] = "nil") do={ :put ("Hinweis: Der Agent auf " . $host . " kennt die Objektliste noch nicht (erst nach dem nächsten Release) - oben steht der normale Plan") }
  :return ""
}
