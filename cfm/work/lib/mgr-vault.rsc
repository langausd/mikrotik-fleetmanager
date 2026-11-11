# ============================================================
# cfm lib/mgr-vault.rsc – Manager-Funktionen: Vault, Secrets, Identitätsprüfung, Geräteschlüssel
#   $cfmSecret key=<k> value=<v>, $cfmSecretPush [host=<n>], $cfmVaultBackup,
#   $cfmRekey host=<n>|all=yes [sftp=yes]; intern $cfmVaultGet/$cfmVaultSet, $cfmChallenge (DS1.4),
#   $cfmWgKeyPair/$cfmWgKey [k=site] (gemeinsamer WireGuard-Schlüssel der Router, DR4.2; Standortkopplung DR4.3)
#   (Übersicht aller Befehle: lib/mgr-core.rsc)
# ============================================================

# ---------- Vault (deaktivierte /ppp secret "cfm:<key>", Passwort = Secret) ----------
:global cfmVaultGet do={
  :local r ""
  :onerror e in={ :set r [/ppp/secret/get [find where name=("cfm:" . $1)] password] } do={}
  :return $r
}
:global cfmVaultSet do={
  :local n ("cfm:" . $1)
  :if ([:len [/ppp/secret/find where name=$n]] = 0) do={
    /ppp/secret/add name=$n password=$2 disabled=yes service=any comment="cfm-sys:vault"
  } else={ /ppp/secret/set [find where name=$n] password=$2 }
}
:global cfmSecret do={
  :global cfmVaultSet; :global cfmJson; :global cfmWrite; :global cfmMB
  :if ([:len $key] = 0 or [:len $value] = 0) do={ :error "Aufruf: \$cfmSecret key=<user.NAME|psk.SSIDKEY|vaultpw|wg.admin|wg.site|ddns.auth> value=<geheim>" }
  $cfmVaultSet $key $value
  :local f ([$cfmMB] . "/meta/vault.dat")
  :local vj [$cfmJson $f]
  :set ($vj->"ver") ([:tonum ($vj->"ver")] + 1)
  # WireGuard-Schlüssel der Router (DR4.2 wg.admin, DR4.3 wg.site): öffentlichen Schlüssel für die Manifeste mitführen
  :if ($key = "wg.admin") do={ :global cfmWgKeyPair; :set ($vj->"wgpub") ([$cfmWgKeyPair $value]->"pub") }
  :if ($key = "wg.site") do={ :global cfmWgKeyPair; :set ($vj->"wgsitepub") ([$cfmWgKeyPair $value]->"pub") }
  $cfmWrite $f [:serialize to=json $vj]
  :put ("Vault: " . $key . " gesetzt (Vault-Version " . ($vj->"ver") . "). Verteilung folgt automatisch.")
}

# WireGuard-Schlüsselpaar über ein abgeschaltetes Hilfs-Interface: $1 = privater Schlüssel (leer = neu
# erzeugen) -> {"priv"=…;"pub"=…}
:global cfmWgKeyPair do={
  :onerror e in={ /interface/wireguard/remove [find where name="cfm-wgtmp"] } do={}
  :local lp [:rndnum from=40000 to=60000]
  :local i
  :if ([:len $1] > 0) do={ :set i [/interface/wireguard/add name="cfm-wgtmp" disabled=yes listen-port=$lp private-key=$1] } else={
    :set i [/interface/wireguard/add name="cfm-wgtmp" disabled=yes listen-port=$lp] }
  :local r ({"priv"=[/interface/wireguard/get $i private-key];"pub"=[/interface/wireguard/get $i public-key]})
  /interface/wireguard/remove $i
  :return $r
}

# Gemeinsamer WireGuard-Schlüssel der Router (DR4.2): Vault "wg.admin", öffentlicher Schlüssel in
# meta/vault.dat ("wgpub"). Fehlt er, übernimmt der Manager den eines Routers, der wg-admin schon hat
# (bestehende Installation: die Clients behalten den Server-Schlüssel), sonst erzeugt er einen neuen.
# k=site (DR4.3): Schlüssel der Standortkopplung, Vault "wg.site", öffentlich "wgsitepub" - immer neu erzeugt
# (die Gegenstelle bekommt den öffentlichen Schlüssel aus $cfmShow bzw. meta/vault.dat).
# Liefert den öffentlichen Schlüssel.
:global cfmWgKey do={
  :global cfmVaultGet; :global cfmVaultSet; :global cfmJson; :global cfmWrite; :global cfmMB
  :global cfmWgKeyPair; :global cfmInvLoad; :global cfmEnrolled; :global cfmExec
  :local kk [:tostr $k]
  :if ([:len $kk] = 0) do={ :set kk "admin" }
  :local vk ("wg." . $kk)
  :local jf "wgpub"
  :if ($kk != "admin") do={ :set jf ("wg" . $kk . "pub") }
  :local f ([$cfmMB] . "/meta/vault.dat")
  :local vj [$cfmJson $f]
  :local priv [$cfmVaultGet $vk]
  :if ([:len $priv] > 0 and [:len [:tostr ($vj->$jf)]] > 0) do={ :return [:tostr ($vj->$jf)] }
  :local neu ([:len $priv] = 0)
  :if ($neu and $kk = "admin") do={
    :foreach n,d in=[$cfmInvLoad] do={
      :if ([:len $priv] = 0 and ("," . [:tostr ($d->"role")] . ",") ~ ",router," and [$cfmEnrolled $d]) do={
        :local wc ":put [/interface/wireguard/get [find where name=\"wg-admin\"] private-key]"
        :local o [:tostr ([$cfmExec ip=($d->"ip") cmd=$wc]->"output")]
        :if ([:len $o] >= 44 and [:pick $o 43 44] = "=") do={
          :set priv [:pick $o 0 44]
          :log info ("cfm: WireGuard-Schluessel der Router von " . $n . " uebernommen (DR4.2)")
        }
      }
    }
  }
  :local kp [$cfmWgKeyPair $priv]
  :if ([:len $priv] = 0) do={ :log info ("cfm: WireGuard-Schluessel " . $vk . " neu erzeugt") }
  :if ($neu) do={
    $cfmVaultSet $vk ($kp->"priv")
    :set ($vj->"ver") ([:tonum ($vj->"ver")] + 1)
  }
  :set ($vj->$jf) ($kp->"pub")
  $cfmWrite $f [:serialize to=json $vj]
  :return ($kp->"pub")
}

# ---------- Secret-Push ----------
:global cfmSecretPush do={
  :global cfmInvLoad; :global cfmVaultGet; :global cfmExec; :global cfmEsc; :global cfmJson
  :global cfmMB; :global cfmG; :global cfmWifi; :global cfmLoadData; :global cfmChallenge; :global cfmCapsmen
  :global cfmEnrolled; :global cfmWg; :global cfmHostName
  :local hn [$cfmHostName $host]; :local host $hn
  $cfmLoadData
  :local vv [:tonum ([$cfmJson ([$cfmMB] . "/meta/vault.dat")]->"ver")]
  :local done 0
  :local inv [$cfmInvLoad]
  :local cms [$cfmCapsmen $inv]
  :foreach name,d in=$inv do={
   # nicht aufgenommene Geräte gar nicht erst prüfen (sonst eine Warnung je Release, TODO 28)
   :if (([:len $host] = 0 or $host = $name) and [$cfmEnrolled $d]) do={
    # Identitätsprüfung: Secrets nur an ein Gerät, das seinen Geräteschlüssel kennt
    :if (![$cfmChallenge ip=($d->"ip") serial=($d->"serial")]) do={
      :log warning ("cfm: Secret-Push " . $name . ": Identitaetspruefung fehlgeschlagen (Geraeteschluessel falsch oder Geraet nicht erreichbar) - uebersprungen")
    } else={
      :local c ":local ok true;"
      :local upw false
      :foreach u,g in=($cfmG->"users") do={
        :local pw [$cfmVaultGet ("user." . $u)]
        :if ([:len $pw] > 0) do={
          :set upw true
          :set c ($c . ":if ([:len [/user/find where name=\"" . $u . "\"]] > 0) do={ /user/set [find where name=\"" . $u . "\"] password=\"" . [$cfmEsc $pw] . "\" disabled=no } else={ :set ok false };")
        }
      }
      # Werks-User admin gleich mit abschalten, wenn das Gerät den effektiven Wert
      # adminUser=disable meldet (inkl. Hostfile-Ausnahme) und die eigenen User gesetzt sind.
      # Die Rolle base setzt das bei jedem Apply ohnehin durch.
      :if ([:tostr ([$cfmJson ([$cfmMB] . "/state/" . $name . "/status.dat")]->"au")] = "disable" and $upw) do={
        :set c ($c . ":if (\$ok) do={ /user/set [find where name=\"admin\"] disabled=yes };")
      }
      :local rl ("," . ($d->"role") . ",")
      # Gemeinsamer WireGuard-Schlüssel der Router (DR4.2); fehlt wg-admin noch, beim nächsten Mal
      :if ($rl ~ ",router," and [:typeof $cfmWg] = "array" and [:len ($cfmWg->"peers")] > 0) do={
        :local wk [$cfmVaultGet "wg.admin"]
        :if ([:len $wk] > 0) do={
          :set c ($c . "{ :local i [/interface/wireguard/find where name=\"wg-admin\"]; :if ([:len \$i] > 0) do={ :if ([/interface/wireguard/get \$i private-key] != \"" . [$cfmEsc $wk] . "\") do={ /interface/wireguard/set \$i private-key=\"" . [$cfmEsc $wk] . "\" } } else={ :set ok false } };")
        }
      }
      # Standortkopplung (DR4.3): ein Schlüssel wg.site für alle wg-site-<Standort>; fehlen sie noch, beim nächsten Mal.
      # DynDNS-Zugang (DR4.4): "user:passwort" als abgeschaltetes /ppp/secret cfm:ddns (wie der Vault selbst)
      :if ($rl ~ ",router," and [:typeof $cfmWg] = "array" and [:len ($cfmWg->"sites")] > 0) do={
        :local sk [$cfmVaultGet "wg.site"]
        :if ([:len $sk] > 0) do={
          :set c ($c . "{ :local l [/interface/wireguard/find where name~\"^wg-site-\"]; :if ([:len \$l] > 0) do={ :foreach i in=\$l do={ :if ([/interface/wireguard/get \$i private-key] != \"" . [$cfmEsc $sk] . "\") do={ /interface/wireguard/set \$i private-key=\"" . [$cfmEsc $sk] . "\" } } } else={ :set ok false } };")
        }
      }
      :if ($rl ~ ",router," and [:len [:tostr ($cfmWg->"self"->"ddns"->"type")]] > 0) do={
        :local da [$cfmVaultGet "ddns.auth"]
        :if ([:len $da] > 0) do={
          :set c ($c . "{ :local i [/ppp/secret/find where name=\"cfm:ddns\"]; :if ([:len \$i] = 0) do={ /ppp/secret/add name=\"cfm:ddns\" password=\"" . [$cfmEsc $da] . "\" disabled=yes service=any comment=\"cfm-sys:ddns\" } else={ :if ([/ppp/secret/get \$i password] != \"" . [$cfmEsc $da] . "\") do={ /ppp/secret/set \$i password=\"" . [$cfmEsc $da] . "\" } } };")
        }
      }
      # SNMPv3 (TODO 54): ein Satz für alle Geräte; fehlt die Community noch (Apply steht aus), beim nächsten Mal
      :local snmp ($cfmG->"snmp")
      :if ([:typeof $snmp] = "array") do={
        :if ([:len ($snmp->"from")] > 0) do={
          :local su [:tostr ($snmp->"user")]
          :if ([:len $su] = 0) do={ :set su "librenms" }
          :local pa [$cfmVaultGet "snmp.auth"]
          :local pv [$cfmVaultGet "snmp.priv"]
          :if ([:len $pa] > 0 and [:len $pv] > 0) do={
            :set c ($c . "{ :local i [/snmp/community/find where name=\"" . $su . "\"]; :if ([:len \$i] > 0) do={ :if ([/snmp/community/get \$i authentication-password] != \"" . [$cfmEsc $pa] . "\" or [/snmp/community/get \$i encryption-password] != \"" . [$cfmEsc $pv] . "\") do={ /snmp/community/set \$i authentication-password=\"" . [$cfmEsc $pa] . "\" encryption-password=\"" . [$cfmEsc $pv] . "\" } } else={ :set ok false } };")
          }
        }
      }
      # WLAN-Passphrasen: an den CAPsMAN (DW1.5) und an die APs für ihren lokalen Fallback (DW1.6)
      :local iscm false
      :foreach cm in=$cms do={ :if ([:tostr ($cm->"n")] = $name) do={ :set iscm true } }
      :if ($iscm or $rl ~ ",ap,") do={
        :foreach k,s in=($cfmWifi->"ssids") do={
          :local psk [$cfmVaultGet ("psk." . $k)]
          :if ([:len $psk] > 0) do={
            :local ep [$cfmEsc $psk]
            :set c ($c . "{ :local i [/interface/wifi/security/find where name=\"cfm-" . $k . "\"]; :if ([:len \$i] > 0) do={ :if ([/interface/wifi/security/get \$i passphrase] != \"" . $ep . "\") do={ /interface/wifi/security/set \$i passphrase=\"" . $ep . "\" } } else={ :set ok false } };")
            # Profile je Band (z.B. 6 GHz nur WPA3: cfm-<SSID>-6g) mit derselben Passphrase
            :set c ($c . ":foreach i in=[/interface/wifi/security/find where name~\"^cfm-" . $k . "-[0-9]+g\\\$\"] do={ :if ([/interface/wifi/security/get \$i passphrase] != \"" . $ep . "\") do={ /interface/wifi/security/set \$i passphrase=\"" . $ep . "\" } };")
            # PPSK an der SSID (DW2.2): die normale Passphrase steht zusätzlich als Gruppeneintrag cfm:mpp:<SSID>
            # (ohne ihn gilt sie nicht); fehlt er, legt ihn der nächste Apply mit dem Wert des Profils an
            :if ([:typeof ($cfmWifi->"ppsk"->$k)] = "array" and [:tostr ($s->"ppskOnly")] != "yes") do={
              :set c ($c . ":foreach i in=[/interface/wifi/security/multi-passphrase/find where comment=\"cfm:mpp:" . $k . "\"] do={ :if ([/interface/wifi/security/multi-passphrase/get \$i passphrase] != \"" . $ep . "\") do={ /interface/wifi/security/multi-passphrase/set \$i passphrase=\"" . $ep . "\" } };")
            }
          }
        }
        # PPSK-Passphrasen (CAPsMAN bzw. Fallback legen die Multi-Passphrase-Einträge mit Zufallswert an)
        :foreach k,ents in=($cfmWifi->"ppsk") do={
          :foreach e,o in=$ents do={
            :local pp [$cfmVaultGet ("ppsk." . $k . "." . $e)]
            :if ([:len $pp] > 0) do={
              :local tg ("cfm:mpp:" . $k . "." . $e)
              # nur bei Abweichung setzen: jede Änderung eines Eintrags trennt dessen Clients (Hardware 7.25)
              :set c ($c . "{ :local i [/interface/wifi/security/multi-passphrase/find where comment=\"" . $tg . "\"]; :if ([:len \$i] > 0) do={ :foreach j in=\$i do={ :if ([/interface/wifi/security/multi-passphrase/get \$j passphrase] != \"" . [$cfmEsc $pp] . "\") do={ /interface/wifi/security/multi-passphrase/set \$j passphrase=\"" . [$cfmEsc $pp] . "\" } } } else={ :set ok false } };")
            }
          }
        }
      }
      :if ($rl ~ ",manager-backup,") do={
        :foreach i in=[/ppp/secret/find where name~"^cfm:" and name!="cfm:key"] do={
          :local n [/ppp/secret/get $i name]
          :set c ($c . "/ppp/secret/remove [find where name=\"" . $n . "\"]; /ppp/secret/add name=\"" . $n . "\" password=\"" . [$cfmEsc [/ppp/secret/get $i password]] . "\" disabled=yes service=any comment=\"cfm-sys:vault\";")
        }
      }
      # Lese-User der API (DU2.1) auf dem CAPsMAN und auf Geräten mit umschaltbarem Port (DP1.4.1). Am CAPsMAN muss
      # es ihn geben (sonst beim nächsten Push); ob ein anderes Gerät einen portSwitch hat, weiß nur das Gerät -
      # dort nur setzen, wenn es den User gibt (legt die Rolle base an und fordert dabei den Push an). Kein Hostfile
      # hier laden: Das setzte cfmHost auf dem Manager, mitten in einen Apply hinein (Labor 2026-11-06)
      :local capi ($cfmG->"capsmanApi")
      :if ([:typeof $capi] = "array") do={
        :if ([:len ($capi->"from")] > 0) do={
          :local au [:tostr ($capi->"user")]
          :if ([:len $au] = 0) do={ :set au "homeassistant" }
          :local apw [$cfmVaultGet ("user." . $au)]
          :if ([:len $apw] > 0) do={
            :local us ("/user/set [find where name=\"" . $au . "\"] password=\"" . [$cfmEsc $apw] . "\" disabled=no")
            :if ($iscm) do={
              :set c ($c . ":if ([:len [/user/find where name=\"" . $au . "\"]] > 0) do={ " . $us . " } else={ :set ok false };")
            } else={
              :set c ($c . ":if ([:len [/user/find where name=\"" . $au . "\" and group=\"cfm-api\"]] > 0) do={ " . $us . " };")
            }
          }
        }
      }
      # User der DNS-Selbstbedienung auf den Routern (DN3.2); fehlt er noch (Apply steht aus), beim nächsten Mal
      :global cfmDns
      :if ($rl ~ ",router," and [:len ($cfmDns->"self"->"zones")] > 0) do={
        :local su [:tostr ($cfmDns->"self"->"user")]
        :if ([:len $su] = 0) do={ :set su "dns" }
        :local spw [$cfmVaultGet ("user." . $su)]
        :if ([:len $spw] > 0) do={
          :set c ($c . ":if ([:len [/user/find where name=\"" . $su . "\"]] > 0) do={ /user/set [find where name=\"" . $su . "\"] password=\"" . [$cfmEsc $spw] . "\" disabled=no } else={ :set ok false };")
        }
      }
      # Ein neuer CAPsMAN wartet mit dem Einschalten auf die Passphrasen (cfmCapsmanOn)
      # Nur mit der Passphrase der Master-SSID im Vault – sonst schaltet die Rolle ihn beim nächsten Apply
      # wieder aus ($cfmPskMissing), und jeder Secret-Push schaltete hin und her
      # Schaltet der Push ihn ein, fehlen den eigenen Radios die übrigen SSIDs: Die Rolle hat sie bei
      # ausgeschaltetem CAPsMAN nicht provisioniert (capsmanRadios). Dann einen erzwungenen Apply anstoßen -
      # erst nach dem neuen SV, sonst meldete er noch den alten (Befund 2026-10-28)
      :set c ($c . ":local ra false;")
      :if ($iscm and [:len [$cfmVaultGet ("psk." . [:tostr ($cfmWifi->"master")])]] > 0) do={ :set c ($c . ":if (\$ok) do={ :onerror e in={ :if (![/interface/wifi/capsman/get enabled] and [:len [/interface/wifi/radio/find where local]] > 0) do={ :set ra true }; /interface/wifi/capsman/set enabled=yes } do={} };") }
      :set c ($c . ":if (\$ok) do={ /ppp/secret/set [find where name=\"cfm:key\"] comment=\"cfm-sys:key sv=" . $vv . "\" };")
      :set c ($c . ":if (\$ra) do={ :execute \":global cfmArg \\\"force\\\"; /system script run cfm-agent\"; :log info \"cfm: CAPsMAN per Secret-Push eingeschaltet - Apply fuer die eigenen Radios\" }; :put \$ok")
      :local r [$cfmExec ip=($d->"ip") cmd=$c]
      :if (($r->"output") ~ "true") do={ :set done ($done + 1); :log info ("cfm: Secrets v" . $vv . " -> " . $name) } else={
        :log warning ("cfm: Secret-Push " . $name . " unvollstaendig/fehlgeschlagen: " . [:pick ($r->"output") 0 120]) }
    }
   }
  }
  :return $done
}

:global cfmVaultBackup do={
  :global cfmVaultGet; :global cfmMB; :global cfmJson; :global cfmWrite; :global cfmHook
  :local pw [$cfmVaultGet "vaultpw"]
  :if ([:len $pw] = 0) do={ :error "Vault-Passwort fehlt: \$cfmSecret key=vaultpw value=..." }
  :local b [$cfmMB]
  :local vn ($b . "/vault/" . [/system/identity/get name] . "-vault")
  /system/backup/save name=$vn password=$pw encryption=aes-sha256
  :delay 2s
  # .backup ist für lesende SFTP-Nutzer (Git-Host) gesperrt -> als .bak ablegen
  :onerror e in={ /file/remove [find where name=($vn . ".bak")] } do={}
  /file/set [find where name=($vn . ".backup")] name=($vn . ".bak")
  :local f ($b . "/meta/vault.dat")
  :local vj [$cfmJson $f]
  :set ($vj->"bver") ($vj->"ver")
  $cfmWrite $f [:serialize to=json $vj]
  :log info "cfm: Vault-Backup geschrieben"
  $cfmHook ev="vault"
}

# ---------- Identitätsprüfung (DS1.4, vor jedem Secret-Push) ----------
# ssh-exec prüft keine Host-Schlüssel. Deshalb beweist das Gerät, dass es seinen
# Geräteschlüssel kennt: sha512(Schlüssel . Zufallswert). ip= serial= -> true/false
:global cfmChallenge do={
  :global cfmVaultGet; :global cfmExec
  :local key [$cfmVaultGet ("mac." . $serial)]
  :if ([:len $key] = 0) do={ :return false }
  :local n [:rndstr length=32 from="0123456789abcdef"]
  :local c (":put [:convert ([/ppp/secret/get [find where name=\"cfm:key\"] password] . \"" . $n . "\") transform=sha512 to=hex]")
  :local r [$cfmExec ip=$ip cmd=$c]
  :return (($r->"output") ~ [:convert ($key . $n) transform=sha512 to=hex])
}

# ---------- Geräteschlüssel erneuern (DS1.4, nur per Befehl) ----------
# Nicht während eines Applys: dessen Rollback-Sicherung ist mit dem alten Schlüssel verschlüsselt.
:global cfmRekey do={
  :global cfmInvLoad; :global cfmChallenge; :global cfmExec; :global cfmVaultSet; :global cfmManifests
  :global cfmJson; :global cfmWrite; :global cfmMB; :global cfmIsPrimary; :global cfmEnrolled; :global cfmHostName
  :local hn [$cfmHostName $host]; :local host $hn
  :if (![$cfmIsPrimary]) do={ :error "nicht Primary: Backup-Manager ist read-only (\$cfmPromoteManager)" }
  :if ([:len $host] = 0 and $all != "yes") do={ :error "Aufruf: \$cfmRekey host=<name> | all=yes [sftp=yes]" }
  :local n 0
  # sftp=yes: SFTP-/Host-Schlüssel statt Geräteschlüssel (DS2.5, lib/mgr-enroll.rsc); Manager zuletzt
  :if ($sftp = "yes") do={
    :global cfmRekeySsh
    :foreach pass in={false;true} do={
      :foreach name,d in=[$cfmInvLoad] do={
        :local im ((("," . ($d->"role") . ",") ~ ",manager"))
        :if ($im = $pass and (($all = "yes" and [$cfmEnrolled $d]) or $host = $name)) do={ :if ([$cfmRekeySsh host=$name]) do={ :set n ($n + 1) } }
      }
    }
    :return $n
  }
  :foreach name,d in=[$cfmInvLoad] do={
    :if (($all = "yes" and [$cfmEnrolled $d]) or $host = $name) do={
      :if (![$cfmChallenge ip=($d->"ip") serial=($d->"serial")]) do={ :put ("Rekey " . $name . ": Identitätsprüfung fehlgeschlagen - übersprungen") } else={
        :local k [:rndstr length=64 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"]
        :local c (":if ([:len [/system/scheduler/find where name=\"cfm-watchdog\"]] = 0 and [:len [/system/script/job/find where script=\"cfm-agent\"]] = 0) do={ /ppp/secret/set [find where name=\"cfm:key\"] password=\"" . $k . "\"; :put rekey-ok } else={ :put busy }")
        :local r [$cfmExec ip=($d->"ip") cmd=$c]
        :if (($r->"output") ~ "rekey-ok") do={
          $cfmVaultSet ("mac." . ($d->"serial")) $k
          :set n ($n + 1)
          :put ("Rekey " . $name . ": neuer Geräteschlüssel aktiv")
          :log info ("cfm: Geraeteschluessel " . $name . " erneuert")
        } else={ :put ("Rekey " . $name . ": gerade nicht möglich (Apply läuft oder nicht erreichbar), später erneut: " . [:pick ($r->"output") 0 80]) }
      }
    }
  }
  :if ($n > 0) do={
    # Manifeste neu signieren; Vault-Version erhöhen, damit Backup-Manager und Vault-Backup nachziehen
    $cfmManifests
    :local f ([$cfmMB] . "/meta/vault.dat")
    :local vj [$cfmJson $f]
    :set ($vj->"ver") ([:tonum ($vj->"ver")] + 1)
    $cfmWrite $f [:serialize to=json $vj]
  }
  :return $n
}
