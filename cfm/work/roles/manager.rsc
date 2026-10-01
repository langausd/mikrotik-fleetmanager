# ============================================================
# Rolle manager – Config-Manager (Primary)
#  * installiert/aktualisiert die Manager-Funktionen (Module lib/mgr-*.rsc, Lader cfm-mgr)
#  * SFTP-Gruppe für Geräte, Verzeichnisstruktur
#  * CAPsMAN nur übergangsweise, solange kein Gerät die Rolle capsman hat (D45)
# Wird von manager-backup.rsc mit cfmIsBackup=true wiederverwendet.
# ============================================================
:global cfmG; :global cfmWifi; :global cfmMf; :global cfmDl
:global cfmEnsure; :global cfmSet; :global cfmBlock; :global cfmLog; :global cfmDry
:global cfmIsBackup

:local backup ($cfmIsBackup = true)
:local mv [:tostr ($cfmG->"mgmtVlan")]
:local base ($cfmG->"mgrPath")

# --- Manager-Funktionen: je Modul lib/mgr-*.rsc aus dem Manifest ein Skript cfm-mgr-<modul>,
#     das Skript cfm-mgr lädt alle. Fehlen die Module, bricht der Apply ab (-> Rollback),
#     statt einen Manager ohne Funktionen zu hinterlassen ---
:local pol "ftp,reboot,read,write,policy,test,password,sensitive"
:local nmod 0
:foreach f in=($cfmMf->"files") do={
  :local p [:tostr ($f->0)]
  :if ($p ~ "^lib/mgr-") do={
    :local mn [:pick $p 8 ([:len $p] - 4)]
    :local s ("cfm-mgr-" . $mn)
    $cfmEnsure m="/system/script" k=("sys:mgr-" . $mn) n=({"name"=$s}) p=({"name"=$s;"source"=[/file get ($cfmDl . "/" . $p) contents];"policy"=$pol})
    :set nmod ($nmod + 1)
  }
}
:if ($nmod = 0) do={ :error "Manager-Module lib/mgr-*.rsc fehlen im Manifest" }
:local ld ":foreach s in=[/system/script/find where name~\"^cfm-mgr-\"] do={ /system/script/run \$s }"
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
# mgrTick=1m (Labor) zum Zug. Jeder überspringt sich außerdem, solange sein Vorlauf läuft (D42).
$cfmEnsure m="/system/scheduler" k="sys:mgr-tick" n=({"name"="cfm-mgr-tick"}) p=({"name"="cfm-mgr-tick";"start-time"="startup";"interval"=$mgrTick;"on-event"=":if ([:len [/system/script/job/find where script=\"cfm-mgr-tick\"]] < 2) do={ :local w 0; :while ([:len [/system/script/job/find where script=\"cfm-mgr-onb-tick\"]] > 0 and \$w < 30) do={ :delay 2s; :set w (\$w + 1) }; :if (\$w >= 30) do={ :log warning \"cfm: mgr-tick laeuft trotz Onboarding-Tick (60 s gewartet)\" }; :global cfmTickBusy; :set cfmTickBusy true; :onerror e in={ /system script run cfm-mgr; :global cfmTick; \$cfmTick } do={ :log warning (\"cfm: mgr-tick: \" . \$e) }; :set cfmTickBusy false } else={ :log warning \"cfm: mgr-tick uebersprungen (Vorlauf haengt)\" }"})
# Aufträge in meta/onboard.dat? Über den Namen statt /file/find (TODO 21: eine Suche über alle
# Dateien kostete auf Hardware jede Minute über 100 ms). Ablage wie $cfmMB.
# Falle beim on-event: Der String wird zweimal geparst (beim Erzeugen und bei jedem Lauf). Ein
# wörtliches "$" direkt vor einem schließenden Anführungszeichen (Regex-Endanker) braucht hier
# deshalb \\\$, sonst "syntax error" bei jedem Lauf (Hardware, 2026-09-22).
:local mb "cfm"
:onerror e in={ :if ([/file/get "flash" type] = "directory") do={ :set mb "flash/cfm" } } do={}
$cfmEnsure m="/system/scheduler" k="sys:mgr-onb-tick" n=({"name"="cfm-mgr-onb-tick"}) p=({"name"="cfm-mgr-onb-tick";"start-time"="startup";"interval"="1m";"on-event"=(":if ([:len [/system/script/job/find where script=\"cfm-mgr-onb-tick\"]] < 2) do={ :local s 0; :onerror e in={ :set s [/file/get \"" . $mb . "/meta/onboard.dat\" size] } do={}; :if (\$s > 2) do={ :global cfmTickBusy; :local w 0; :while (\$cfmTickBusy = true and [:len [/system/script/job/find where script=\"cfm-mgr-tick\"]] > 0 and \$w < 15) do={ :delay 2s; :set w (\$w + 1) }; :if (\$w < 15) do={ /system script run cfm-mgr; :global cfmOnbTickRun; \$cfmOnbTickRun } } } else={ :log warning \"cfm: mgr-onb-tick uebersprungen (Vorlauf haengt)\" }")})

# --- SFTP-Zugang der Geräte (User cfmd-<name> legt $cfmEnroll an) ---
$cfmEnsure m="/user/group" k="grp:dev" n=({"name"="cfm-dev"}) p=({"name"="cfm-dev";"policy"="ssh,ftp,read"})

# --- Manager-Schlüssel auch für die Admin-User aus users: $cfm*-Befehle nutzen ssh-exec mit dem
#     Schlüssel des angemeldeten Users – nötig, sobald der Werks-User admin abgeschaltet ist ---
:foreach u,g in=($cfmG->"users") do={
  :if ([:len [/user/find where name=$u]] > 0 and [:len [/user/ssh-keys/private/find where user=$u]] = 0) do={
    :if ($cfmDry = true) do={ $cfmLog ("Manager-Schlüssel für " . $u . " würde importiert") } else={
      /ip/ssh/export-host-key key-file-prefix=cfm-uk
      :delay 1s
      :onerror e in={ /user/ssh-keys/private/import user=$u private-key-file=cfm-uk_ed25519.pem; $cfmLog ("Manager-Schlüssel für " . $u . " importiert") } do={ $cfmLog ("Manager-Schlüssel für " . $u . " fehlgeschlagen: " . $e) }
      :onerror e in={ /file/remove [find where name~"^cfm-uk"] } do={}
    }
  }
}
:if ($cfmDry != true) do={
  :foreach d in={"work";"meta";"live";"live/m";"archive";"state";"vault"} do={
    :local ex false
    :onerror e in={ :local x [/file/get ($base . "/" . $d) name]; :set ex true } do={}
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
    $cfmEnsure m="/interface/vlan" k=("vlan:" . $vid) n=({"name"=$ifn}) p=({"name"=$ifn;"interface"="bridge";"vlan-id"=[:tonum $vid]}) x=($v->"name")
    $cfmEnsure m="/ip/address" k=("obip:" . $vid) n=({"interface"=$ifn;"address"=$oad}) p=({"address"=$oad;"interface"=$ifn})
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

# --- CAPsMAN (D45): eigene Rolle capsman. Hat im Inventar noch kein Gerät diese Rolle, bleibt der
#     Primary übergangsweise CAPsMAN (der Manager nennt ihn dann im Manifest-Feld cm). Der Backup
#     rendert keinen CAPsMAN mehr – bei einem Ausfall zieht die Rolle capsman auf ein anderes Gerät ---
:global cfmIsCapsman; :global cfmHas; :global cfmCapsmanOn
# Rest der früheren Übernahme durch den Backup (Netwatch-Down-Skript), falls noch vorhanden
:if ($cfmDry != true) do={ :onerror e in={ /system/scheduler/remove [find where name="cfm-takeover"] } do={} }
:if (!$backup and [$cfmIsCapsman] and ![$cfmHas "capsman"]) do={ $cfmCapsmanOn }
