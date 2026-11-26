# ============================================================
# Rolle manager – Config-Manager (Primary)
#  * installiert/aktualisiert die Manager-Funktionen (Module lib/mgr-*.rsc, Lader cfm-mgr)
#  * SFTP-Gruppe für Geräte, Verzeichnisstruktur
#  * CAPsMAN nur übergangsweise, solange kein Gerät die Rolle capsman hat (DW1.5)
# Wird von manager-backup.rsc mit cfmIsBackup=true wiederverwendet.
# ============================================================
:global cfmG; :global cfmMf; :global cfmDl
:global cfmEnsure; :global cfmLog; :global cfmDry; :global cfmHas; :global cfmVlanKey
:global cfmIsBackup

:local backup ($cfmIsBackup = true)
:local mv [:tostr ($cfmG->"mgmtVlan")]
:local base ($cfmG->"mgrPath")

# --- Manager-Funktionen: je Modul lib/mgr-*.rsc aus dem Manifest ein Skript cfm-mgr-<modul>,
#     das Skript cfm-mgr lädt alle (danach abweichende aus work/lib/, DM1.4). Fehlen die Module, bricht der Apply ab (-> Rollback),
#     statt einen Manager ohne Funktionen zu hinterlassen ---
:local pol "ftp,reboot,read,write,policy,test,password,sensitive"
# Erst alle Modultexte lesen, dann die Skripte setzen; jede Datei bis zu fünf Versuche (DM1.1.1). Auf einem
# Backup-Manager (hAP be³ Media, Flash, 7.25.1) fand "/file get <Name> contents" im Apply zweimal ein Modul nicht,
# jeweils gleich nach dem Ersetzen eines anderen Skripts - Rollback mit Neustart; von Hand nicht nachgestellt.
# Bleibt eine Datei unlesbar, steht ihr Name mit dem Fehler im Log.
:local msrc ({})
:foreach f in=($cfmMf->"files") do={
  :local p [:tostr ($f->0)]
  :if ($p ~ "^lib/mgr-") do={
    :local fn ($cfmDl . "/" . $p)
    :local c ""; :local ok false; :local le ""; :local n 0
    :while (!$ok and $n < 5) do={
      :if ($n > 0) do={ :delay 1s }
      :set n ($n + 1)
      :onerror e in={ :set c [/file get $fn contents]; :set ok true } do={ :set le $e }
    }
    :if (!$ok) do={
      :log error ("cfm: Manager-Modul " . $p . " nicht lesbar (5 Versuche): " . $le)
      :error ("Manager-Modul " . $p . " nicht lesbar: " . $le)
    }
    :if ($n > 1) do={ :log warning ("cfm: Manager-Modul " . $p . " erst im " . $n . ". Versuch lesbar (" . $le . ")") }
    :set ($msrc->$p) $c
  }
}
:local nmod 0
:foreach p,c in=$msrc do={
  :local mn [:pick $p 8 ([:len $p] - 4)]
  :local s ("cfm-mgr-" . $mn)
  $cfmEnsure m="/system/script" k=("sys:mgr-" . $mn) n=({"name"=$s}) p=({"name"=$s;"source"=$c;"policy"=$pol})
  :set nmod ($nmod + 1)
}
:if ($nmod = 0) do={ :error "Manager-Module lib/mgr-*.rsc fehlen im Manifest" }
# Lader: erst die installierten Module, dann die abweichenden aus work/lib/ ($cfmMgrFromWork, DM1.4; fehlt die
# Funktion, liefert der Aufruf still nichts)
:local ld ":foreach s in=[/system/script/find where name~\"^cfm-mgr-\"] do={ /system/script/run \$s }; :global cfmMgrFromWork; :onerror e in={ \$cfmMgrFromWork } do={ :log warning (\"cfm: cfm-mgr: \" . \$e) }"
$cfmEnsure m="/system/script" k="sys:mgr" n=({"name"="cfm-mgr"}) p=({"name"="cfm-mgr";"source"=$ld;"policy"=$pol})
# Allgemeiner Tick (Status, Ring-Aufstieg, Secret-Sync, Updates, Netzplan, Hook, Vault-Backup):
# Intervall aus global.rsc "mgrTick" (Default 10m, falls nicht gesetzt). Das Onboarding braucht
# einen eigenen, schnellen Tick (siehe unten) - sonst würde eine laufende Sitzung proportional
# langsamer voranschreiten, sobald "mgrTick" größer als 1m ist.
:local mgrTick [:tostr ($cfmG->"mgrTick")]
:if ([:len $mgrTick] = 0) do={ :set mgrTick "10m" }
# Beide Ticks starten zur selben Sekunde (start-time=startup) und dürfen nicht gleichzeitig arbeiten:
# Der allgemeine Tick wartet bis zu 60 s auf einen laufenden Onboarding-Tick (danach läuft er mit
# Warnung trotzdem) und setzt während seiner Arbeit cfmTickBusy. Der Onboarding-Tick wartet bis zu
# 30 s, solange cfmTickBusy gesetzt ist, und lässt danach seine Minute aus. Er wartet nie auf einen
# allgemeinen Tick, der selbst noch wartet (sonst warteten beide aufeinander), und kommt auch bei
# mgrTick=1m (Labor) zum Zug. Jeder überspringt sich außerdem, solange sein Vorlauf läuft (DM2.1).
$cfmEnsure m="/system/scheduler" k="sys:mgr-tick" n=({"name"="cfm-mgr-tick"}) p=({"name"="cfm-mgr-tick";"start-time"="startup";"interval"=$mgrTick;"on-event"=":if ([:len [/system/script/job/find where script=\"cfm-mgr-tick\"]] < 2) do={ :local w 0; :while ([:len [/system/script/job/find where script=\"cfm-mgr-onb-tick\"]] > 0 and \$w < 30) do={ :delay 2s; :set w (\$w + 1) }; :if (\$w >= 30) do={ :log warning \"cfm: mgr-tick laeuft trotz Onboarding-Tick (60 s gewartet)\" }; :global cfmTickBusy; :set cfmTickBusy true; :onerror e in={ /system script run cfm-mgr; :global cfmTick; \$cfmTick } do={ :log warning (\"cfm: mgr-tick: \" . \$e) }; :set cfmTickBusy false } else={ :log warning \"cfm: mgr-tick uebersprungen (Vorlauf haengt)\" }"})
# Nach dem Start die Manager-Funktionen gleich laden: Ein Scheduler mit start-time=startup und Intervall läuft
# zum ersten Mal erst nach Ablauf des Intervalls, nicht beim Booten (Labor 7.25.1, ROUTEROS-EIGENHEITEN) - bis zum
# ersten Tick fehlten sonst alle $cfm*-Befehle (DM2.1.1)
$cfmEnsure m="/system/scheduler" k="sys:mgr-boot" n=({"name"="cfm-mgr-boot"}) p=({"name"="cfm-mgr-boot";"start-time"="startup";"interval"="0s";"on-event"=":delay 10s; :onerror e in={ /system script run cfm-mgr } do={ :log warning (\"cfm: mgr-boot: \" . \$e) }"})
# Aufträge in meta/onboard.dat? Über den Namen statt /file/find (TODO 21: eine Suche über alle
# Dateien kostete auf Hardware jede Minute über 100 ms). Ablage wie $cfmMB.
# Falle beim on-event: Der String wird zweimal geparst (beim Erzeugen und bei jedem Lauf). Ein
# wörtliches "$" direkt vor einem schließenden Anführungszeichen (Regex-Endanker) braucht hier
# deshalb \\\$, sonst "syntax error" bei jedem Lauf (Hardware, 2026-09-22).
:local mb "cfm"
:onerror e in={ :if ([/file/get "flash" type] = "directory") do={ :set mb "flash/cfm" } } do={}
$cfmEnsure m="/system/scheduler" k="sys:mgr-onb-tick" n=({"name"="cfm-mgr-onb-tick"}) p=({"name"="cfm-mgr-onb-tick";"start-time"="startup";"interval"="1m";"on-event"=(":if ([:len [/system/script/job/find where script=\"cfm-mgr-onb-tick\"]] < 2) do={ :local s 0; :onerror e in={ :set s [/file/get \"" . $mb . "/meta/onboard.dat\" size] } do={}; :if (\$s > 2) do={ :global cfmTickBusy; :local w 0; :while (\$cfmTickBusy = true and [:len [/system/script/job/find where script=\"cfm-mgr-tick\"]] > 0 and \$w < 15) do={ :delay 2s; :set w (\$w + 1) }; :if (\$w < 15) do={ /system script run cfm-mgr; :global cfmOnbTickRun; \$cfmOnbTickRun } } } else={ :log warning \"cfm: mgr-onb-tick uebersprungen (Vorlauf haengt)\" }")})

# --- Signer der Zertifikate (DS3.6, global.rsc tls): User cfm-cert nur mit ssh,read (liest state/<name>/tls.csr),
#     nur von tls.from, nur per Key (authorized_keys.cfm-cert; ohne Datei kann er sich nicht anmelden), und das Skript
#     cfm-cert-pull, das er starten darf (dont-require-permissions, wie cfm-dnsreq) - es holt die Zertifikate
#     vom Signer ($cfmTlsPull) und stößt die Geräte an. SSH-Freigabe für tls.from setzt base. Ohne tls räumt die GC auf ---
:local tls ($cfmG->"tls")
:if (!$backup and [:typeof $tls] = "array" and [:len [:tostr ($tls->"signer")]] > 0 and [:len ($tls->"from")] > 0) do={
  :local fa ""
  :foreach x in=($tls->"from") do={ :local a [:tostr $x]; :if (!($a ~ "/")) do={ :set a ($a . "/32") }; :if ([:len $fa] > 0) do={ :set fa ($fa . ",") }; :set fa ($fa . $a) }
  $cfmEnsure m="/user/group" k="grp:cert" n=({"name"="cfm-cert"}) p=({"name"="cfm-cert";"policy"="ssh,read"})
  $cfmEnsure m="/user" k="user:cfm-cert" n=({"name"="cfm-cert"}) p=({"name"="cfm-cert";"group"="cfm-cert";"address"=$fa;"disabled"="no"}) a=({"password"=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"]})
  :local src ":if ([:len [/system/script/job/find where script=\"cfm-cert-pull\"]] > 1) do={ :put \"cfm-cert-pull laeuft bereits\"; :error \"cfm-done\" }; /system script run cfm-mgr; :global cfmTlsPull; :put (\"geaendert: \" . [\$cfmTlsPull])"
  $cfmEnsure m="/system/script" k="sys:cert-pull" n=({"name"="cfm-cert-pull"}) p=({"name"="cfm-cert-pull";"source"=$src;"policy"=$pol;"dont-require-permissions"="yes"})
  # Key des Signers: dieselbe Logik wie die Admin-Keys (Sollzustand aus der Datei), nur für diesen User
  :local akx false
  :onerror e in={ :set akx ([:len [/file/get ($cfmDl . "/authorized_keys.cfm-cert") name]] > 0) } do={}
  :if ($akx) do={
    :global cfmCtx; :global cfmFeat
    :set cfmCtx ({"users"={"cfm-cert"="cfm-cert"}})
    $cfmFeat "base.sshkeys"
    :set cfmCtx ({})
  } else={ $cfmLog "tls: authorized_keys.cfm-cert fehlt - der Signer kann sich nicht anmelden" }
}

# --- NetBox-Abgleich (DT2.3, global.rsc netbox): User cfm-netbox nur mit ssh,read, nur
#     von netbox.from, nur per Key (authorized_keys.cfm-netbox), und das Skript cfm-netbox-run, das er starten darf
#     (dont-require-permissions) - es wertet die Site-Daten aus und gibt Soll und Ist als Text aus ($cfmNetboxOut, letztes
#     Release; /file/read darf der User selbst nicht). SSH-Freigabe setzt base.
#     Nur auf dem Primary (dort liegt der Status der Geräte). Ohne netbox räumt die GC auf ---
# Adressen ohne Präfix mit /32: RouterOS speichert sie beim User so, sonst meldet jeder Apply eine Änderung
:local nbc ($cfmG->"netbox")
:if (!$backup and [:typeof $nbc] = "array" and [:len ($nbc->"from")] > 0) do={
  :local fa ""
  :foreach x in=($nbc->"from") do={ :local a [:tostr $x]; :if (!($a ~ "/")) do={ :set a ($a . "/32") }; :if ([:len $fa] > 0) do={ :set fa ($fa . ",") }; :set fa ($fa . $a) }
  $cfmEnsure m="/user/group" k="grp:netbox" n=({"name"="cfm-netbox"}) p=({"name"="cfm-netbox";"policy"="ssh,read"})
  $cfmEnsure m="/user" k="user:cfm-netbox" n=({"name"="cfm-netbox"}) p=({"name"="cfm-netbox";"group"="cfm-netbox";"address"=$fa;"disabled"="no"}) a=({"password"=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"]})
  :local src ":if ([:len [/system/script/job/find where script=\"cfm-netbox-run\"]] > 1) do={ :put \"cfm-netbox-run laeuft bereits\"; :error \"cfm-done\" }; /system script run cfm-mgr; :global cfmNetboxOut; \$cfmNetboxOut"
  $cfmEnsure m="/system/script" k="sys:netbox-run" n=({"name"="cfm-netbox-run"}) p=({"name"="cfm-netbox-run";"source"=$src;"policy"=$pol;"dont-require-permissions"="yes"})
  :local akx false
  :onerror e in={ :set akx ([:len [/file/get ($cfmDl . "/authorized_keys.cfm-netbox") name]] > 0) } do={}
  :if ($akx) do={
    :global cfmCtx; :global cfmFeat
    :set cfmCtx ({"users"={"cfm-netbox"="cfm-netbox"}})
    $cfmFeat "base.sshkeys"
    :set cfmCtx ({})
  } else={ $cfmLog "netbox: authorized_keys.cfm-netbox fehlt - NetBox kann sich nicht anmelden" }
}

# --- Leases von außen (DN1.3, global.rsc lease): User cfm-lease nur mit ssh,read (rest=yes: dazu api,rest-api),
#     nur von lease.from, per Key (authorized_keys.cfm-lease) bzw. Passwort von Hand (REST), und das Skript
#     cfm-lease (dont-require-permissions): liest die Argumente als Text aus $cfmLeaseArg (in derselben Sitzung
#     gesetzt) und ruft $cfmLeaseRun. Nur auf dem Primary. Ohne lease räumt die GC auf ---
:local lsc ($cfmG->"lease")
:if (!$backup and [:typeof $lsc] = "array" and [:len ($lsc->"from")] > 0) do={
  :local fa ""
  :foreach x in=($lsc->"from") do={ :local a [:tostr $x]; :if (!($a ~ "/")) do={ :set a ($a . "/32") }; :if ([:len $fa] > 0) do={ :set fa ($fa . ",") }; :set fa ($fa . $a) }
  :local lpol "ssh,read"
  :if ([:tostr ($lsc->"rest")] = "yes") do={ :set lpol "ssh,read,api,rest-api" }
  $cfmEnsure m="/user/group" k="grp:lease" n=({"name"="cfm-lease"}) p=({"name"="cfm-lease";"policy"=$lpol})
  $cfmEnsure m="/user" k="user:cfm-lease" n=({"name"="cfm-lease"}) p=({"name"="cfm-lease";"group"="cfm-lease";"address"=$fa;"disabled"="no"}) a=({"password"=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"]})
  :local src ":global cfmLeaseArg; :local a [:tostr \$cfmLeaseArg]; :set cfmLeaseArg; :if ([:len [/system/script/job/find where script=\"cfm-lease\"]] > 1) do={ :put \"ERGEBNIS fehler: cfm-lease laeuft bereits\"; :error \"cfm-done\" }; /system script run cfm-mgr; :global cfmLeaseRun; \$cfmLeaseRun \$a"
  $cfmEnsure m="/system/script" k="sys:lease" n=({"name"="cfm-lease"}) p=({"name"="cfm-lease";"source"=$src;"policy"=$pol;"dont-require-permissions"="yes"})
  :local akx false
  :onerror e in={ :set akx ([:len [/file/get ($cfmDl . "/authorized_keys.cfm-lease") name]] > 0) } do={}
  :if ($akx) do={
    :global cfmCtx; :global cfmFeat
    :set cfmCtx ({"users"={"cfm-lease"="cfm-lease"}})
    $cfmFeat "base.sshkeys"
    :set cfmCtx ({})
  } else={ :if ([:tostr ($lsc->"rest")] != "yes") do={ $cfmLog "lease: authorized_keys.cfm-lease fehlt - Anmeldung per SSH nicht moeglich" } }
}

# --- SFTP-Zugang der Geräte (User cfmd-<name> legt $cfmEnroll an) ---
$cfmEnsure m="/user/group" k="grp:dev" n=({"name"="cfm-dev"}) p=({"name"="cfm-dev";"policy"="ssh,ftp,read"})

# --- Manager-Schlüssel auch für die Admin-User aus users: $cfm*-Befehle nutzen ssh-exec mit dem
#     Schlüssel des angemeldeten Users – nötig, sobald der Werks-User admin abgeschaltet ist ---
:foreach u,g in=($cfmG->"users") do={
  :if ([:len [/user/find where name=$u]] > 0 and [:len [/user/ssh-keys/private/find where user=$u]] = 0) do={
    :if ($cfmDry = true) do={ $cfmLog ("Manager-Schluessel fuer " . $u . " wuerde importiert") } else={
      /ip/ssh/export-host-key key-file-prefix=cfm-uk
      :delay 1s
      :onerror e in={ /user/ssh-keys/private/import user=$u private-key-file=cfm-uk_ed25519.pem; $cfmLog ("Manager-Schluessel fuer " . $u . " importiert") } do={ $cfmLog ("Manager-Schluessel fuer " . $u . " fehlgeschlagen: " . $e) }
      :onerror e in={ /file/remove [find where name~"^cfm-uk"] } do={}
    }
  }
}
:if ($cfmDry != true) do={
  :foreach d in={"work";"meta";"live";"live/m";"archive";"state";"vault"} do={
    :local ex false
    :onerror e in={ :if ([:len [/file/get ($base . "/" . $d) name]] > 0) do={ :set ex true } } do={}
    :if (!$ex) do={ :onerror e in={ /file add name=($base . "/" . $d) type=directory } do={} }
  }
}

# --- Onboarding-VLAN (vlans.rsc: onboard="yes"): Adresse = Host-Anteil der MGMT-IP,
#     DHCP nur auf dem Primary (für Werksgeräte mit DHCP-Client, z.B. APs im CAPs-Modus)
:global cfmVlans; :global cfmNet
:foreach vid,v in=$cfmVlans do={
  :if ([:tostr ($v->"onboard")] = "yes") do={
    :local nn [$cfmNet $vid]
    :local ifn ("vlan" . $vid)
    :local oip (($nn->"addr") | ([:toip ($cfmMf->"ip")] & 0.0.0.255))
    :local oad ([:tostr $oip] . "/" . ($nn->"pfx"))
    $cfmEnsure m="/interface/vlan" k=("vlan:" . $vid) n=[$cfmVlanKey $vid] p=({"name"=$ifn;"interface"="bridge";"vlan-id"=[:tonum $vid]}) x=($v->"name")
    # Legt die Rolle router hier dieselbe Adresse an (ip:<VID>: .250+routerId bzw. das Gateway), gehört sie
    # ihr - sonst übernähmen beide Rollen das Objekt bei jedem Apply abwechselnd (Kommentarwechsel)
    :local rad ""
    :if ([$cfmHas "router"] and [:tostr ($v->"l3")] != "no") do={
      :global cfmHost
      :set rad ([:tostr ($nn->"gw")] . "/" . ($nn->"pfx"))
      :if ([:len [:tostr ($cfmHost->"routerId")]] > 0) do={ :set rad ([:tostr (($nn->"addr") + 250 + [:tonum ($cfmHost->"routerId")])] . "/" . ($nn->"pfx")) }
    }
    :if ($rad != $oad) do={
      $cfmEnsure m="/ip/address" k=("obip:" . $vid) n=({"interface"=$ifn;"address"=$oad}) p=({"address"=$oad;"interface"=$ifn})
    }
    :local dh [:tostr ($v->"dhcp")]
    :if (!$backup and [:len $dh] > 0 and $dh != "no") do={
      :local s [:find $dh "-"]
      :local ra (($nn->"addr") + [:tonum [:pick $dh 0 $s]])
      :local rb (($nn->"addr") + [:tonum [:pick $dh ($s + 1) [:len $dh]]])
      :local lt [:tostr ($v->"lease")]
      :if ([:len $lt] = 0) do={ :set lt "10m" }
      $cfmEnsure m="/ip/pool" k=("obpool:" . $vid) n=({"name"=("pool" . $vid)}) p=({"name"=("pool" . $vid);"ranges"=([:tostr $ra] . "-" . [:tostr $rb])})
      $cfmEnsure m="/ip/dhcp-server" k=("obdhcp:" . $vid) n=({"name"=("dhcp" . $vid)}) p=({"name"=("dhcp" . $vid);"interface"=$ifn;"address-pool"=("pool" . $vid);"lease-time"=$lt;"disabled"="no"})
      $cfmEnsure m="/ip/dhcp-server/network" k=("obdn:" . $vid) n=({"address"=($nn->"net")}) p=({"address"=($nn->"net");"gateway"=[:tostr ($nn->"gw")];"dns-server"=[:tostr ($nn->"gw")]})
    }
  }
}

# --- CAPsMAN (DW1.5): eigene Rolle capsman. Hat im Inventar noch kein Gerät diese Rolle, bleibt der
#     Primary übergangsweise CAPsMAN (der Manager nennt ihn dann im Manifest-Feld cm). Der Backup
#     rendert keinen CAPsMAN mehr – bei einem Ausfall zieht die Rolle capsman auf ein anderes Gerät ---
:global cfmIsCapsman; :global cfmCapsmanOn
:if (!$backup and [$cfmIsCapsman] and ![$cfmHas "capsman"]) do={
  :if ([:typeof $cfmCapsmanOn] = "nothing") do={ :error "lib/lib-wifi.rsc fehlt im Manifest (DG4.3)" }
  $cfmCapsmanOn
}
