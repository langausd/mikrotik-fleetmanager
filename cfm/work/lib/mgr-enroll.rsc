# ============================================================
# cfm lib/mgr-enroll.rsc – Manager-Funktionen: Geräte aufnehmen
#   $cfmEnroll, $cfmBootstrap, $cfmTrust   (Übersicht aller Befehle: lib/mgr-core.rsc)
# ============================================================
# ---------- Vertrauen: alle Manager-Schlüssel auf Geräte verteilen ----------
# (nötig, damit ein später enrollter Backup-Manager im DR-Fall steuern kann)
:global cfmTrust do={
  :global cfmInvLoad; :global cfmMB; :global cfmRead; :global cfmExec
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
    :if ([:len $host] = 0 or $host = $n) do={
      :local r [$cfmExec ip=($d->"ip") cmd=$c]
      :if (($r->"output") ~ "true") do={ :set cnt ($cnt + 1) } else={ :log warning ("cfm: Trust " . $n . ": " . [:pick ($r->"output") 0 120]) }
    }
  }
  :return $cnt
}


# ---------- Onboarding ----------
:global cfmEnroll do={
  :global cfmMB; :global cfmExec; :global cfmInvLoad; :global cfmInvSave; :global cfmVaultSet
  :global cfmVaultGet; :global cfmManifests; :global cfmWrite; :global cfmRings; :global cfmG; :global cfmLoadData
  :if ([:len $name] = 0 or [:len $ip] = 0) do={ :error "Aufruf: \$cfmEnroll name=<identity> ip=<erreichbare IP> [role=..] [ring=..] [rekey=yes]" }
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
  :if ([:len [/user/find where name=$du]] = 0) do={
    /user/add name=$du group=cfm-dev password=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"] comment=("cfm-sys:dev " . $serial)
  } else={ /user/set [find where name=$du] comment=("cfm-sys:dev " . $serial) }
  /user/ssh-keys/remove [find where user=$du]
  :delay 500ms
  /file/add name=("cfm-import-" . $name . ".pem") contents=[/file/get [/file/find where name=$kf] contents]
  :delay 500ms
  /user/ssh-keys/import user=$du public-key-file=("cfm-import-" . $name . ".pem")
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
  :set c ($c . "/system/scheduler/remove [find where name=\"cfm-agent\"]; /system/scheduler/add name=cfm-agent comment=\"cfm-sys:agent\" start-time=startup interval=" . ($cfmG->"interval") . " on-event=\"/system script run cfm-agent\"; :put ok")
  :set r [$cfmExec ip=$ip cmd=$c]
  :if (!(($r->"output") ~ "ok")) do={ :error ("Agent-Installation fehlgeschlagen: " . ($r->"output")) }
  # 6) Vertrauen: neues Gerät kennt alle Manager; neuer Manager wird allen Geräten bekannt
  :global cfmTrust
  :if (("," . ($d->"role") . ",") ~ ",manager") do={ $cfmTrust } else={ $cfmTrust host=$name }
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
