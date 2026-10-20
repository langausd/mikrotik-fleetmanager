# ============================================================
# cfm lib/mgr-vault.rsc – Manager-Funktionen: Vault, Secrets, Identitätsprüfung, Geräteschlüssel
#   $cfmSecret key=<k> value=<v>, $cfmSecretPush [host=<n>], $cfmVaultBackup,
#   $cfmRekey host=<n>|all=yes [sftp=yes]; intern $cfmVaultGet/$cfmVaultSet, $cfmChallenge (D28),
#   $cfmWgKeyPair/$cfmWgKey (gemeinsamer WireGuard-Schlüssel der Router, D84)
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
  :if ([:len $key] = 0 or [:len $value] = 0) do={ :error "Aufruf: \$cfmSecret key=<user.NAME|psk.SSIDKEY|vaultpw|wg.admin> value=<geheim>" }
  $cfmVaultSet $key $value
  :local f ([$cfmMB] . "/meta/vault.dat")
  :local vj [$cfmJson $f]
  :set ($vj->"ver") ([:tonum ($vj->"ver")] + 1)
  # WireGuard-Schlüssel der Router (D84): öffentlichen Schlüssel für die Manifeste mitführen
  :if ($key = "wg.admin") do={ :global cfmWgKeyPair; :set ($vj->"wgpub") ([$cfmWgKeyPair $value]->"pub") }
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

# Gemeinsamer WireGuard-Schlüssel der Router (D84): Vault "wg.admin", öffentlicher Schlüssel in
# meta/vault.dat ("wgpub"). Fehlt er, übernimmt der Manager den eines Routers, der wg-admin schon hat
# (bestehende Installation: die Clients behalten den Server-Schlüssel), sonst erzeugt er einen neuen.
# Liefert den öffentlichen Schlüssel.
:global cfmWgKey do={
  :global cfmVaultGet; :global cfmVaultSet; :global cfmJson; :global cfmWrite; :global cfmMB
  :global cfmWgKeyPair; :global cfmInvLoad; :global cfmEnrolled; :global cfmExec
  :local f ([$cfmMB] . "/meta/vault.dat")
  :local vj [$cfmJson $f]
  :local priv [$cfmVaultGet "wg.admin"]
  :if ([:len $priv] > 0 and [:len [:tostr ($vj->"wgpub")]] > 0) do={ :return [:tostr ($vj->"wgpub")] }
  :local neu ([:len $priv] = 0)
  :if ($neu) do={
    :foreach n,d in=[$cfmInvLoad] do={
      :if ([:len $priv] = 0 and ("," . [:tostr ($d->"role")] . ",") ~ ",router," and [$cfmEnrolled $d]) do={
        :local wc ":put [/interface/wireguard/get [find where name=\"wg-admin\"] private-key]"
        :local o [:tostr ([$cfmExec ip=($d->"ip") cmd=$wc]->"output")]
        :if ([:len $o] >= 44 and [:pick $o 43 44] = "=") do={
          :set priv [:pick $o 0 44]
          :log info ("cfm: WireGuard-Schlüssel der Router von " . $n . " übernommen (D84)")
        }
      }
    }
  }
  :local kp [$cfmWgKeyPair $priv]
  :if ([:len $priv] = 0) do={ :log info "cfm: WireGuard-Schlüssel der Router neu erzeugt (D84)" }
  :if ($neu) do={
    $cfmVaultSet "wg.admin" ($kp->"priv")
    :set ($vj->"ver") ([:tonum ($vj->"ver")] + 1)
  }
  :set ($vj->"wgpub") ($kp->"pub")
  $cfmWrite $f [:serialize to=json $vj]
  :return ($kp->"pub")
}

# ---------- Secret-Push ----------
:global cfmSecretPush do={
  :global cfmInvLoad; :global cfmVaultGet; :global cfmExec; :global cfmEsc; :global cfmJson
  :global cfmMB; :global cfmG; :global cfmWifi; :global cfmLoadData; :global cfmChallenge; :global cfmCapsmen
  :global cfmEnrolled; :global cfmWg
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
      :log warning ("cfm: Secret-Push " . $name . ": Identitätsprüfung fehlgeschlagen (Geräteschlüssel falsch oder Gerät nicht erreichbar) - übersprungen")
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
      # Gemeinsamer WireGuard-Schlüssel der Router (D84); fehlt wg-admin noch, beim nächsten Mal
      :if ($rl ~ ",router," and [:typeof $cfmWg] = "array" and [:len ($cfmWg->"peers")] > 0) do={
        :local wk [$cfmVaultGet "wg.admin"]
        :if ([:len $wk] > 0) do={
          :set c ($c . ":if ([:len [/interface/wireguard/find where name=\"wg-admin\"]] > 0) do={ /interface/wireguard/set [find where name=\"wg-admin\"] private-key=\"" . [$cfmEsc $wk] . "\" } else={ :set ok false };")
        }
      }
      # WLAN-Passphrasen: an den CAPsMAN (D45) und an die APs für ihren lokalen Fallback (D46)
      :local iscm false
      :foreach cm in=$cms do={ :if ([:tostr ($cm->"n")] = $name) do={ :set iscm true } }
      :if ($iscm or $rl ~ ",ap,") do={
        :foreach k,s in=($cfmWifi->"ssids") do={
          :local psk [$cfmVaultGet ("psk." . $k)]
          :if ([:len $psk] > 0) do={
            :set c ($c . ":if ([:len [/interface/wifi/security/find where name=\"cfm-" . $k . "\"]] > 0) do={ /interface/wifi/security/set [find where name=\"cfm-" . $k . "\"] passphrase=\"" . [$cfmEsc $psk] . "\" } else={ :set ok false };")
            # Profile je Band (z.B. 6 GHz nur WPA3: cfm-<SSID>-6g) mit derselben Passphrase
            :set c ($c . ":foreach i in=[/interface/wifi/security/find where name~\"^cfm-" . $k . "-[0-9]+g\\\$\"] do={ /interface/wifi/security/set \$i passphrase=\"" . [$cfmEsc $psk] . "\" };")
          }
        }
        # PPSK-Passphrasen (CAPsMAN bzw. Fallback legen die Multi-Passphrase-Einträge mit Zufallswert an)
        :foreach k,ents in=($cfmWifi->"ppsk") do={
          :foreach e,o in=$ents do={
            :local pp [$cfmVaultGet ("ppsk." . $k . "." . $e)]
            :if ([:len $pp] > 0) do={
              :local tg ("cfm:mpp:" . $k . "." . $e)
              :set c ($c . ":if ([:len [/interface/wifi/security/multi-passphrase/find where comment=\"" . $tg . "\"]] > 0) do={ /interface/wifi/security/multi-passphrase/set [find where comment=\"" . $tg . "\"] passphrase=\"" . [$cfmEsc $pp] . "\" } else={ :set ok false };")
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
      # Lese-User der API auf dem CAPsMAN (D47)
      :local capi ($cfmG->"capsmanApi")
      :if ($iscm and [:typeof $capi] = "array") do={
        :if ([:len ($capi->"from")] > 0) do={
          :local au [:tostr ($capi->"user")]
          :if ([:len $au] = 0) do={ :set au "homeassistant" }
          :local apw [$cfmVaultGet ("user." . $au)]
          :if ([:len $apw] > 0) do={
            :set c ($c . ":if ([:len [/user/find where name=\"" . $au . "\"]] > 0) do={ /user/set [find where name=\"" . $au . "\"] password=\"" . [$cfmEsc $apw] . "\" disabled=no } else={ :set ok false };")
          }
        }
      }
      # Ein neuer CAPsMAN wartet mit dem Einschalten auf die Passphrasen (cfmCapsmanOn)
      # Nur mit der Passphrase der Master-SSID im Vault – sonst schaltet die Rolle ihn beim nächsten Apply
      # wieder aus ($cfmPskMissing), und jeder Secret-Push schaltete hin und her
      :if ($iscm and [:len [$cfmVaultGet ("psk." . [:tostr ($cfmWifi->"master")])]] > 0) do={ :set c ($c . ":if (\$ok) do={ :onerror e in={ /interface/wifi/capsman/set enabled=yes } do={} };") }
      :set c ($c . ":if (\$ok) do={ /ppp/secret/set [find where name=\"cfm:key\"] comment=\"cfm-sys:key sv=" . $vv . "\" }; :put \$ok")
      :local r [$cfmExec ip=($d->"ip") cmd=$c]
      :if (($r->"output") ~ "true") do={ :set done ($done + 1); :log info ("cfm: Secrets v" . $vv . " -> " . $name) } else={
        :log warning ("cfm: Secret-Push " . $name . " unvollständig/fehlgeschlagen: " . [:pick ($r->"output") 0 120]) }
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

# ---------- Identitätsprüfung (D28, vor jedem Secret-Push) ----------
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

# ---------- Geräteschlüssel erneuern (D28, nur per Befehl) ----------
# Nicht während eines Applys: dessen Rollback-Sicherung ist mit dem alten Schlüssel verschlüsselt.
:global cfmRekey do={
  :global cfmInvLoad; :global cfmChallenge; :global cfmExec; :global cfmVaultSet; :global cfmManifests
  :global cfmJson; :global cfmWrite; :global cfmMB; :global cfmIsPrimary; :global cfmEnrolled
  :if (![$cfmIsPrimary]) do={ :error "nicht Primary: Backup-Manager ist read-only (\$cfmPromoteManager)" }
  :if ([:len $host] = 0 and $all != "yes") do={ :error "Aufruf: \$cfmRekey host=<name> | all=yes [sftp=yes]" }
  :local n 0
  # sftp=yes: SFTP-/Host-Schlüssel statt Geräteschlüssel (D67, lib/mgr-enroll.rsc); Manager zuletzt
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
          :log info ("cfm: Geräteschlüssel " . $name . " erneuert")
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
