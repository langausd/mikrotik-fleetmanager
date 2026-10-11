# ============================================================
# cfm lib/mgr-enroll.rsc – Manager-Funktionen: Geräte aufnehmen
#   $cfmEnroll, $cfmBootstrap, $cfmTrust, $cfmDevUser, $cfmRekeySsh
#   (Übersicht aller Befehle: lib/mgr-core.rsc)
# ============================================================
# ---------- Vertrauen: alle Manager-Schlüssel auf Geräte verteilen ----------
# (nötig, damit ein später enrollter Backup-Manager im DR-Fall steuern kann)
:global cfmTrust do={
  :global cfmInvLoad; :global cfmMB; :global cfmRead; :global cfmExec; :global cfmEnrolled
  :local b [$cfmMB]
  :local inv [$cfmInvLoad]
  :local c ":local old [/user/ssh-keys/find where user=cfm]; :local ok true;"
  :local i 0
  :foreach n,d in=$inv do={
    :if (("," . ($d->"role") . ",") ~ ",manager") do={
      :local k [$cfmRead ($b . "/meta/keys/" . $n . ".pem")]
      :if ([:len $k] > 0) do={
        :set i ($i + 1)
        :local e ""
        :for j from=0 to=([:len $k] - 1) do={ :local ch [:pick $k $j]; :if ($ch = "\n") do={ :set e ($e . "\\n") } else={ :if ($ch != "\r") do={ :set e ($e . $ch) } } }
        :set c ($c . "/file/add name=cfm-trust" . $i . ".pem contents=\"" . $e . "\"; :delay 300ms; :onerror x in={ /user/ssh-keys/import user=cfm public-key-file=cfm-trust" . $i . ".pem } do={ :set ok false };")
      }
    }
  }
  :set c ($c . ":if (\$ok) do={ /user/ssh-keys/remove \$old }; :put \$ok")
  :local cnt 0
  :foreach n,d in=$inv do={
    :if (([:len $host] = 0 or $host = $n) and [$cfmEnrolled $d]) do={
      :local r [$cfmExec ip=($d->"ip") cmd=$c]
      :if (($r->"output") ~ "true") do={ :set cnt ($cnt + 1) } else={ :log warning ("cfm: Trust " . $n . ": " . [:pick ($r->"output") 0 120]) }
    }
  }
  :return $cnt
}


# ---------- SFTP-User eines Geräts (cfmd-<name>) aus meta/keys/<name>.pem (D67) ----------
# Primary: bei $cfmEnroll und $cfmRekey sftp=yes. Backup-Manager: nach jedem Spiegel - ohne die User
# könnten die Geräte im Ernstfall nicht von ihm ziehen. Der Kommentar trägt einen Hash des Schlüssels;
# stimmt er und hat der User genau einen Schlüssel, bleibt alles stehen. pem= statt der Datei,
# add=yes: Schlüssel zusätzlich aufnehmen, die vorhandenen bleiben (Rotation, Phase 2).
# dis=yes (Backup-Manager): User gesperrt - ein unbeförderter Backup lieferte sonst seinen älteren Spiegel
# aus, sobald der Primary kurz nicht antwortet (Labor: ein Gerät wandte v6 statt v12 an). Frei schaltet
# sie erst $cfmPromoteManager ($cfmDevUsersOn).
:global cfmDevUser do={
  :global cfmMB; :global cfmRead
  :local k [:tostr $pem]
  :if ([:len $k] = 0) do={ :set k [$cfmRead ([$cfmMB] . "/meta/keys/" . $name . ".pem")] }
  :if (!($k ~ "BEGIN PUBLIC KEY")) do={ :return false }
  :local du ("cfmd-" . $name)
  :local cm ("cfm-sys:dev " . $serial . " k=" . [:pick [:convert $k transform=md5 to=hex] 0 12])
  :local dv ($dis = "yes")
  :local uid [/user/find where name=$du]
  :if ([:len $uid] = 0) do={
    /user/add name=$du group=cfm-dev password=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"] comment=$cm disabled=$dv
  } else={
    :local u0 [:pick $uid 0]
    :if ([/user/get $u0 disabled] != $dv) do={ /user/set $u0 disabled=$dv }
    :if ($add != "yes" and [/user/get $u0 comment] = $cm and [:len [/user/ssh-keys/find where user=$du]] = 1) do={ :return true }
    /user/set $u0 comment=$cm
  }
  :local old [/user/ssh-keys/find where user=$du]
  :local fn ("cfm-import-" . $name . ".pem")
  /file/add name=$fn contents=$k
  :delay 500ms
  :local ok false
  :onerror e in={ /user/ssh-keys/import user=$du public-key-file=$fn; :set ok true } do={ :log warning ("cfm: SFTP-User " . $du . ": Import fehlgeschlagen: " . $e) }
  :onerror e in={ /file/remove $fn } do={}
  :if ($ok and $add != "yes") do={ :foreach i in=$old do={ :onerror e in={ /user/ssh-keys/remove $i } do={} } }
  :return $ok
}

# Beförderung eines Backup-Managers: alle Geräte-User freischalten, den eigenen anlegen
:global cfmDevUsersOn do={
  :global cfmInvLoad; :global cfmDevUser
  :local n 0
  :foreach name,d in=[$cfmInvLoad] do={ :if ([$cfmDevUser name=$name serial=($d->"serial")]) do={ :set n ($n + 1) } }
  :return $n
}

# PEM für einen RouterOS-String in einem ssh-exec-Befehl: Zeilenumbrüche als \n, ohne \r
:global cfmPemEsc do={
  :local k [:tostr $1]
  :local e ""
  :for j from=0 to=([:len $k] - 1) do={ :local ch [:pick $k $j]; :if ($ch = "\n") do={ :set e ($e . "\\n") } else={ :if ($ch != "\r") do={ :set e ($e . $ch) } } }
  :return $e
}
# Text zwischen zwei Marken der ssh-exec-Ausgabe, \r entfernt
:global cfmBetween do={
  :local s [:tostr $1]
  :local a [:find $s $2]
  :if ([:typeof $a] = "nil") do={ :return "" }
  :set a ($a + [:len $2])
  :local z [:find $s $3 $a]
  :if ([:typeof $z] = "nil") do={ :return "" }
  :local r ""
  :for j from=$a to=($z - 1) do={ :local ch [:pick $s $j]; :if ($ch != "\r") do={ :set r ($r . $ch) } }
  :while ([:pick $r 0] = "\n") do={ :set r [:pick $r 1 [:len $r]] }
  :return $r
}

# ---------- SFTP-/Host-Schlüssel erneuern ($cfmRekey sftp=yes, D67) ----------
# Der SFTP-Schlüssel eines Geräts ist sein exportierter ed25519-Host-Key (D28): Die Erneuerung ändert
# deshalb auch den Host-Key (SSH-Clients melden ihn einmal als geändert). Ablauf ohne Lücke:
#  1. Gerät: neuen Host-Key erzeugen, exportieren, öffentlichen Teil ausgeben. Ein Manager gibt auch
#     den privaten Teil aus und löscht die Dateien sofort (seine Geräte-User dürfen per SFTP lesen) -
#     der private Schlüssel lebt danach nur in dieser Funktion.
#  2. Manager: neuen Schlüssel zusätzlich bei cfmd-<name>. Bei einem Manager-Gerät zusätzlich beim
#     User cfm ALLER aufgenommenen Geräte (er ist dort der Trust-Key, D35); fehlt auch nur eines,
#     Abbruch: $cfmTrust stellt den alten Stand her, der alte Schlüssel gilt weiter.
#  3. Gerät: neuen privaten Schlüssel importieren (cfm; bei Managern jeder User mit privatem Schlüssel,
#     das sind alles Kopien des Host-Keys), die alten entfernen.
#  4. meta/keys/<name>.pem, cfmd-<name> nur noch mit dem neuen Schlüssel; Manager: $cfmTrust (alter
#     Schlüssel überall weg), Bootstrap-Datei neu. Der Backup-Manager zieht mit seinem nächsten Spiegel nach.
:global cfmRekeySsh do={
  :global cfmInvLoad; :global cfmChallenge; :global cfmExec; :global cfmEnrolled; :global cfmDevUser
  :global cfmPemEsc; :global cfmBetween; :global cfmTrust; :global cfmMB; :global cfmWrite; :global cfmFileEx
  :global cfmBootstrap; :global cfmG; :global cfmLoadData
  :local inv [$cfmInvLoad]
  :local d ($inv->$host)
  :if ([:typeof $d] != "array" or ![$cfmEnrolled $d]) do={ :put ("Rekey SFTP " . $host . ": nicht aufgenommen - übersprungen"); :return false }
  :local mgr ((("," . ($d->"role") . ",") ~ ",manager"))
  :if (![$cfmChallenge ip=($d->"ip") serial=($d->"serial")]) do={ :put ("Rekey SFTP " . $host . ": Identitätsprüfung fehlgeschlagen - übersprungen"); :return false }
  # 1) neuer Host-Key
  :local c ":if ([:len [/system/scheduler/find where name=\"cfm-watchdog\"]] = 0 and [:len [/system/script/job/find where script=\"cfm-agent\"]] = 0) do={ /ip/ssh/set host-key-type=ed25519; /ip/ssh/regenerate-host-key; :delay 1s; /file/remove [find where name~\"^cfm-rk\"]; /ip/ssh/export-host-key key-file-prefix=cfm-rk; :delay 1s; :put \"<<PUB\"; :put [/file/get cfm-rk_ed25519_pub.pem contents]; :put \"PUB>>\";"
  :if ($mgr) do={ :set c ($c . " :put \"<<PRV\"; :put [/file/get cfm-rk_ed25519.pem contents]; :put \"PRV>>\"; /file/remove [find where name~\"^cfm-rk\"];") }
  :set c ($c . " } else={ :put busy }")
  :local r [$cfmExec ip=($d->"ip") cmd=$c]
  :local pub [$cfmBetween ($r->"output") "<<PUB" "PUB>>"]
  :local prv ""
  :if ($mgr) do={ :set prv [$cfmBetween ($r->"output") "<<PRV" "PRV>>"] }
  :if (!($pub ~ "BEGIN PUBLIC KEY") or ($mgr and !($prv ~ "PRIVATE KEY"))) do={
    :put ("Rekey SFTP " . $host . ": gerade nicht möglich (Apply läuft oder Export fehlgeschlagen): " . [:pick ($r->"output") 0 80])
    :return false
  }
  :set pub [:pick $pub [:find $pub "-----BEGIN"] [:len $pub]]
  # 2) neuen Schlüssel zusätzlich hinterlegen
  :if (![$cfmDevUser name=$host serial=($d->"serial") pem=$pub add=yes]) do={ :put ("Rekey SFTP " . $host . ": Import bei cfmd-" . $host . " fehlgeschlagen - abgebrochen"); :return false }
  :if ($mgr) do={
    :local ac ("/file/add name=cfm-rk.pem contents=\"" . [$cfmPemEsc $pub] . "\"; :delay 300ms; :onerror x in={ /user/ssh-keys/import user=cfm public-key-file=cfm-rk.pem; :put rk-ok } do={ :put (\"rk-fail \" . \$x) }; :onerror x in={ /file/remove cfm-rk.pem } do={}")
    :local miss ""
    :foreach n,x in=$inv do={
      :if ([$cfmEnrolled $x]) do={
        :local ar [$cfmExec ip=($x->"ip") cmd=$ac]
        :if (!(($ar->"output") ~ "rk-ok")) do={ :set miss ($miss . " " . $n) }
      }
    }
    :if ([:len $miss] > 0) do={
      :put ("Rekey SFTP " . $host . ": neuer Manager-Schlüssel nicht auf allen Geräten (" . $miss . " ) - abgebrochen, der alte gilt weiter")
      $cfmTrust
      $cfmDevUser name=$host serial=($d->"serial")
      :log warning ("cfm: Rekey SFTP " . $host . " abgebrochen, nicht erreicht:" . $miss)
      :return false
    }
  }
  # 3) Gerät stellt um
  :local sc ""
  :if ($mgr) do={
    :set sc (":local us ({}); :foreach i in=[/user/ssh-keys/private/find] do={ :set (\$us->[/user/ssh-keys/private/get \$i user]) 1 }; :local ok true; :foreach u,x in=\$us do={ :local old [/user/ssh-keys/private/find where user=\$u]; /file/add name=cfm-rk_ed25519.pem contents=\"" . [$cfmPemEsc $prv] . "\"; :delay 300ms; :onerror e in={ /user/ssh-keys/private/import user=\$u private-key-file=cfm-rk_ed25519.pem; :foreach i in=\$old do={ /user/ssh-keys/private/remove \$i } } do={ :set ok false }; :onerror e in={ /file/remove [find where name~\"^cfm-rk\"] } do={} }; :if (\$ok) do={ :put rk-ok } else={ :put rk-fail }")
  } else={
    :set sc (":local old [/user/ssh-keys/private/find where user=cfm]; :onerror e in={ /user/ssh-keys/private/import user=cfm private-key-file=cfm-rk_ed25519.pem; :foreach i in=\$old do={ /user/ssh-keys/private/remove \$i }; :put rk-ok } do={ :put (\"rk-fail \" . \$e) }; :onerror e in={ /file/remove [find where name~\"^cfm-rk\"] } do={}")
  }
  :set prv ""
  :set r [$cfmExec ip=($d->"ip") cmd=$sc]
  :if (!(($r->"output") ~ "rk-ok")) do={
    :put ("Rekey SFTP " . $host . ": Umstellung auf dem Gerät fehlgeschlagen - alter Schlüssel gilt weiter: " . [:pick ($r->"output") 0 80])
    $cfmDevUser name=$host serial=($d->"serial")
    :if ($mgr) do={ $cfmTrust }
    :return false
  }
  # 4) neuer Schlüssel ist maßgeblich
  $cfmWrite ([$cfmMB] . "/meta/keys/" . $host . ".pem") $pub
  $cfmDevUser name=$host serial=($d->"serial")
  :if ($mgr) do={
    :local tc [$cfmTrust]
    :put ("Rekey SFTP " . $host . ": Manager-Schlüssel auf " . $tc . " Geräten, alter entfernt")
    :if ([$cfmFileEx ([$cfmMB] . "/cfm-bootstrap.rsc")]) do={ $cfmBootstrap }
    :if ([:typeof $cfmG] != "array") do={ $cfmLoadData }
    :if ([:len [:tostr ($cfmG->"hook"->"host")]] > 0) do={ :put ("Hinweis: Git-Host " . ($cfmG->"hook"->"host") . " kennt noch den alten Manager-Schlüssel - neuen aus meta/keys/" . $host . ".pem eintragen (ssh-keygen -i -m PKCS8 -f <datei>)") }
  }
  :put ("Rekey SFTP " . $host . ": neuer SFTP-/Host-Schlüssel aktiv")
  :log info ("cfm: SFTP-/Host-Schlüssel " . $host . " erneuert")
  :return true
}

# ---------- Onboarding ----------
:global cfmEnroll do={
  :global cfmMB; :global cfmExec; :global cfmInvLoad; :global cfmInvSave; :global cfmVaultSet
  :global cfmVaultGet; :global cfmManifests; :global cfmWrite; :global cfmRings; :global cfmG; :global cfmLoadData
  :if ([:len $name] = 0 or [:len $ip] = 0) do={ :error "Aufruf: \$cfmEnroll name=<identity> ip=<erreichbare IP> [role=..] [ring=..] [rekey=yes] [noapply=yes]" }
  :local b [$cfmMB]
  $cfmLoadData
  # 1) Seriennummer
  :local sc ":local s; :onerror e in={:set s [/system routerboard get serial-number]} do={}; :if ([:len \$s]=0) do={:onerror e in={:set s [/system/license/get system-id]} do={}}; :if ([:len \$s]=0) do={:onerror e in={:set s [/system/license/get software-id]} do={}}; :put \$s"
  :local r [$cfmExec ip=$ip cmd=$sc]
  :if (($r->"exit-code") != 0) do={ :error ("Gerät nicht per SSH (User cfm) erreichbar: " . ($r->"output")) }
  :local serial [:pick ($r->"output") 0 [:find ($r->"output") "\r"]]
  :if ([:typeof [:find ($r->"output") "\r"]] = "nil") do={ :set serial [:pick ($r->"output") 0 [:find (($r->"output") . "\n") "\n"]] }
  # 2) Geräteschlüssel (asymmetrisch): Host-Key ed25519 erzeugen/exportieren, Private-Key für User cfm
  :local rk "no"; :if ($rekey = "yes") do={ :set rk "yes" }
  :set r [$cfmExec ip=$ip cmd=(":if ([:len [/user/ssh-keys/private/find where user=cfm]] = 0 or \"" . $rk . "\" = \"yes\") do={ /ip/ssh/set host-key-type=ed25519; /ip/ssh/regenerate-host-key; :delay 1s; /ip/ssh/export-host-key key-file-prefix=cfm-id; :delay 1s; /user/ssh-keys/private/remove [find where user=cfm]; /user/ssh-keys/private/import user=cfm private-key-file=cfm-id_ed25519.pem } else={ /ip/ssh/export-host-key key-file-prefix=cfm-id; :delay 1s }; :put [/file/get cfm-id_ed25519_pub.pem contents]; /file/remove [find where name~\"^cfm-id\"]")]
  :local pub ($r->"output")
  :if (!($pub ~ "BEGIN PUBLIC KEY")) do={ :error ("Schlüsselexport fehlgeschlagen: " . $pub) }
  :local kf ($b . "/meta/keys/" . $name . ".pem")
  $cfmWrite $kf [:pick $pub [:find $pub "-----BEGIN"] [:len $pub]]
  :local du ("cfmd-" . $name)
  :global cfmDevUser
  :if (![$cfmDevUser name=$name serial=$serial]) do={ :error ("SFTP-User " . $du . ": Schlüssel-Import fehlgeschlagen (Log)") }
  # 3) Inventar (Ersatzgerät: alte Seriennummer + MAC-Schlüssel entfernen)
  :local inv [$cfmInvLoad]
  :local d ($inv->$name)
  :if ([:typeof $d] != "array") do={ :set d ({"role"="switch";"ring"=2}) }
  :if ([:len [:tostr ($d->"serial")]] > 0 and ($d->"serial") != $serial) do={
    /ppp/secret/remove [find where name=("cfm:mac." . ($d->"serial"))]
    :put ("Ersatzgerät: " . ($d->"serial") . " -> " . $serial)
  }
  :set ($d->"serial") $serial
  :set ($d->"ip") $ip
  :if ([:len $role] > 0) do={ :set ($d->"role") $role }
  :if ([:len [:tostr $ring]] > 0) do={ :set ($d->"ring") [:tonum $ring] }
  :set ($inv->$name) $d
  $cfmInvSave $inv
  # 4) MAC-Schlüssel erzeugen, im Vault ablegen und per SSH ins Gerät schreiben
  :local k [:rndstr length=64 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"]
  $cfmVaultSet ("mac." . $serial) $k
  $cfmManifests
  # 5) Agent-Konfiguration + Agent + Scheduler auf dem Gerät
  :local ms ""
  :foreach a in=($cfmG->"managers") do={ :set ms ($ms . ";\\\"" . $a . "\\\"") }
  :local conf (":global cfmConf {\\\"mgrs\\\"={" . [:pick $ms 1 [:len $ms]] . "};\\\"path\\\"=\\\"" . ($cfmG->"mgrPath") . "\\\";\\\"user\\\"=\\\"" . $du . "\\\"}")
  :local v ([$cfmRings]->("r" . ($d->"ring")))
  :local p0 [:pick ($cfmG->"managers") 0]
  :local c ("/ppp/secret/remove [find where name=\"cfm:key\"]; /ppp/secret/add name=\"cfm:key\" password=\"" . $k . "\" disabled=yes service=any comment=\"cfm-sys:key sv=0\";")
  :set c ($c . "/system/script/remove [find where name=\"cfm-conf\"]; /system/script/add name=cfm-conf policy=read comment=\"cfm-sys:conf\" source=\"" . $conf . "\";")
  :set c ($c . "/tool/fetch url=\"sftp://" . $p0 . "/" . ($cfmG->"mgrPath") . "/archive/v" . $v . "/lib/agent.rsc\" user=" . $du . " dst-path=cfm/agent-init.rsc as-value; :delay 1s;")
  :set c ($c . "/system/script/remove [find where name=\"cfm-agent\"]; /system/script/add name=cfm-agent comment=\"cfm-sys:agent\" policy=ftp,reboot,read,write,policy,test,password,sensitive source=[/file/get cfm/agent-init.rsc contents];")
  # noapply=yes: Bestandsgerät erst prüfen - Scheduler aus, kein erster Lauf. Danach $cfmPlan host=<n>,
  # anwenden mit $cfmExec ip=<ip> cmd="/system/scheduler/enable [find name=cfm-agent]" + $cfmPush host=<n>
  :local sdis "no"; :if ($noapply = "yes") do={ :set sdis "yes" }
  :set c ($c . "/system/scheduler/remove [find where name=\"cfm-agent\"]; /system/scheduler/add name=cfm-agent comment=\"cfm-sys:agent\" start-time=startup interval=" . ($cfmG->"interval") . " disabled=" . $sdis . " on-event=\"/system script run cfm-agent\"; :put ok")
  :set r [$cfmExec ip=$ip cmd=$c]
  :if (!(($r->"output") ~ "ok")) do={ :error ("Agent-Installation fehlgeschlagen: " . ($r->"output")) }
  # 6) Vertrauen: neues Gerät kennt alle Manager; neuer Manager wird allen Geräten bekannt
  :global cfmTrust
  :if (("," . ($d->"role") . ",") ~ ",manager") do={ $cfmTrust } else={ $cfmTrust host=$name }
  :if ($noapply = "yes") do={
    :put ("Enrolled ohne Apply: " . $name . " (" . $serial . ", " . ($d->"role") . ", Ring " . ($d->"ring") . ") – Scheduler aus. Jetzt \$cfmPlan host=" . $name)
    :log info ("cfm: enrolled (noapply) " . $name . " " . $serial)
    :return ""
  }
  :local ex ":execute \"/system script run cfm-agent\""
  $cfmExec ip=$ip cmd=$ex
  :put ("Enrolled: " . $name . " (" . $serial . ", " . ($d->"role") . ", Ring " . ($d->"ring") . ") – erster Pull läuft. Secrets folgen automatisch nach dem ersten Apply.")
  :log info ("cfm: enrolled " . $name . " " . $serial)
}

# ---------- Bootstrap-Datei für neue Geräte ----------
:global cfmBootstrap do={
  :global cfmMB; :global cfmWrite; :global cfmInvLoad; :global cfmG; :global cfmLoadData; :global cfmRead
  $cfmLoadData
  :local b [$cfmMB]
  :local keys ""
  :foreach n,d in=[$cfmInvLoad] do={
    :if (("," . ($d->"role") . ",") ~ ",manager") do={
      :local k [$cfmRead ($b . "/meta/keys/" . $n . ".pem")]
      :if ([:len $k] > 0) do={
        :local e ""
        :for i from=0 to=([:len $k] - 1) do={ :local ch [:pick $k $i]; :if ($ch = "\n") do={ :set e ($e . "\\n") } else={ :if ($ch != "\r") do={ :set e ($e . $ch) } } }
        :set keys ($keys . ";\"" . $e . "\"")
      }
    }
  }
  :local mv ($cfmG->"mgmtVlan")
  :global cfmVlans
  :local vv ($cfmVlans->[:tostr $mv])
  :local go 1
  :if ([:len [:tostr ($vv->"gw")]] > 0) do={ :set go [:tonum ($vv->"gw")] }
  :local net ("192.168." . $mv . ".0/24")
  :if ([:len [:tostr ($vv->"net")]] > 0) do={ :set net ($vv->"net") }
  :local na [:toip [:pick $net 0 [:find $net "/"]]]
  :local gwip [:tostr ($na + $go)]
  :local pfx [:pick $net ([:find $net "/"] + 1) [:len $net]]
  :local ipx ([:tostr ($na + 99)] . "/" . $pfx)
  :local up "ether1"
  :local out ($b . "/cfm-bootstrap.rsc")
  :local hint "# Auf neuem/zurückgesetztem Gerät: IP/Uplink anpassen, dann /import cfm-bootstrap.rsc\n# Danach am Manager: \$cfmEnroll name=<name> ip=<ip> role=<rolle> ring=<0-2>\n"
  # name=<n>: gerätespezifisch für den Onboarding-Push (MGMT-IP aus dem Inventar, alle Ports)
  :if ([:len $name] > 0) do={
    :local d ([$cfmInvLoad]->$name)
    :if ([:typeof $d] != "array") do={ :error ("unbekanntes Gerät " . $name) }
    :set ipx (($d->"ip") . "/" . $pfx)
    :set up "*"
    :set out ($b . "/onb/" . $name . "-bootstrap.rsc")
    :set hint ("# gerätespezifisch für " . $name . " (Onboarding-Push, läuft per run-after-reset)\n")
  }
  :local s ("# cfm bootstrap – erzeugt am " . [/system/clock/get date] . " von " . [/system/identity/get name] . "\n" . $hint)
  :set s ($s . ":local ip \"" . $ipx . "\"\n:local uplink \"" . $up . "\"\n:local mv " . $mv . "\n:local gw \"" . $gwip . "\"\n")
  :set s ($s . ":local keys {" . [:pick $keys 1 [:len $keys]] . "}\n")
  :global cfmRings
  :local body [$cfmRead ($b . "/archive/v" . ([$cfmRings]->"latest") . "/lib/bootstrap-body.rsc")]
  :if ([:len $body] = 0) do={ :set body [$cfmRead ($b . "/work/lib/bootstrap-body.rsc")] }
  $cfmWrite $out ($s . $body)
  :if ([:len $name] = 0) do={ :put ("geschrieben: " . $out . " (per Winbox/SFTP holen)") }
  :return $out
}
