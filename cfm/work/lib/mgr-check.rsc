# ============================================================
# cfm lib/mgr-check.rsc – Manager-Funktionen: inhaltliche Prüfung und Probelauf
#   $cfmCheck            prüft die Daten in work/ (läuft auch bei jedem $cfmRelease, D27)
#   $cfmPlan host=<n>    Probelauf: das Gerät zeigt, was ein Release von work/ ändern würde
#   (Übersicht aller Befehle: lib/mgr-core.rsc)
# ============================================================

# ---------- Inhaltliche Prüfung von work/ -> {"err"={..};"warn"={..}} ----------
# Fehler: VLANs/Zonen, die Profile, WLAN, policy, mgmtAccess oder Hostfiles nennen, aber nicht
# existieren; unbekannte Port-Profile; doppelte MGMT-IPs; Rollen ohne Datei.
# Warnungen: Inventar-Eintrag ohne Hostfile.
:global cfmCheck do={
  :global cfmMB; :global cfmLoadData; :global cfmG; :global cfmVlans; :global cfmProfiles
  :global cfmWifi; :global cfmInvLoad; :global cfmHost; :global cfmVaultGet; :global cfmWg
  :global cfmNet; :global cfmTarget
  :local b [$cfmMB]
  :local w ($b . "/work")
  :local err ({}); :local warn ({})
  :local le ""
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
  }
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
      :if ([:len [/file/find where name=($w . "/roles/" . $r . ".rsc")]] = 0) do={ :set ($err->[:len $err]) ("inventory: " . $n . ": Rolle " . $r . " ohne roles/" . $r . ".rsc") }
    }
    :local hf ($w . "/hosts/" . $n . ".rsc")
    :if ([:len [/file/find where name=$hf]] = 0) do={ :set ($warn->[:len $warn]) ("inventory: " . $n . " hat kein hosts/" . $n . ".rsc") } else={
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
      }
    }
  }
  # Persönliche Admin-SSH-Keys (work/authorized_keys, OpenSSH-Format, D35): optional, grobe
  # Zeilenprüfung (kein RouterOS-Skript, daher kein :parse möglich)
  :local akf ($w . "/authorized_keys")
  :if ([:len [/file/find where name=$akf]] > 0) do={
    :local ln 0
    :local t ([/file/get $akf contents] . "\n")
    :while ([:len $t] > 0) do={
      :set ln ($ln + 1)
      :local p [:find $t "\n"]
      :local l [:pick $t 0 $p]
      :set t [:pick $t ($p + 1) [:len $t]]
      :if ([:len $l] > 0 and [:pick $l ([:len $l] - 1) [:len $l]] = "\r") do={ :set l [:pick $l 0 ([:len $l] - 1)] }
      :if ([:len $l] > 0 and [:pick $l 0 1] != "#") do={
        :local sp [:find $l " "]
        :local ok false
        :if ([:typeof $sp] != "nil") do={
          :local typ [:pick $l 0 $sp]
          :if ($typ ~ "^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-|sk-ssh-ed25519|sk-ecdsa-sha2-)") do={ :set ok true }
        }
        :if (!$ok) do={ :set ($err->[:len $err]) ("authorized_keys: Zeile " . $ln . ": kein gültiger OpenSSH-Public-Key (Format \"<typ> <base64> [kommentar]\", keine Optionen wie command=... davor)") }
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
  :local c (":execute \":global cfmArg {\\\"mode\\\"=\\\"plan\\\";\\\"id\\\"=\\\"" . $id . "\\\"}; /system script run cfm-agent\"")
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
  :put [/file/get [find where name=$lf] contents]
  :return ""
}
