# ============================================================
# Rolle manager – Config-Manager (Primary) + wifi-CAPsMAN
#  * installiert/aktualisiert die Manager-Funktionen (Module lib/mgr-*.rsc, Lader cfm-mgr)
#  * SFTP-Gruppe für Geräte, Verzeichnisstruktur
#  * rendert die komplette CAPsMAN-Konfiguration aus wifi.rsc
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
$cfmEnsure m="/system/scheduler" k="sys:mgr-tick" n=({"name"="cfm-mgr-tick"}) p=({"name"="cfm-mgr-tick";"start-time"="startup";"interval"=$mgrTick;"on-event"="/system script run cfm-mgr; :global cfmTick; \$cfmTick"})
$cfmEnsure m="/system/scheduler" k="sys:mgr-onb-tick" n=({"name"="cfm-mgr-onb-tick"}) p=({"name"="cfm-mgr-onb-tick";"start-time"="startup";"interval"="1m";"on-event"="/system script run cfm-mgr; :global cfmOnbTickRun; \$cfmOnbTickRun"})

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
    :if ([:len [/file find where name=($base . "/" . $d)]] = 0) do={ :onerror e in={ /file add name=($base . "/" . $d) type=directory } do={} }
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

# --- CAPsMAN aus wifi.rsc ---
:local w $cfmWifi
:local d ($w->"defaults")
:local mk ($w->"master")
$cfmEnsure m="/interface/wifi/steering" k="wst" n=({"name"="cfm-steer"}) p=({"name"="cfm-steer";"rrm"=($d->"rrm");"wnm"=($d->"wnm")})
# Kanal-Pools: RouterOS wählt selbst und prüft nachts neu (reselect, D32), DFS-Kanäle optional meiden
:foreach b,c in=($w->"channels") do={
  :local cp ({"name"=("cfm-" . $b . "g");"band"=($c->"band");"frequency"=($c->"freq");"width"=($c->"width")})
  # als HH:MM:SS angeben: "03:00" liest RouterOS als 3 Minuten, der Vergleich schlüge jedes Mal fehl
  :local rs [:tostr ($w->"reselect")]
  :if ([:len $rs] = 5) do={ :set rs ($rs . ":00") }
  :if ([:len $rs] > 0) do={ :set ($cp->"reselect-time") $rs }
  :if ([:len [:tostr ($c->"skipDfs")]] > 0) do={ :set ($cp->"skip-dfs-channels") ($c->"skipDfs") }
  $cfmEnsure m="/interface/wifi/channel" k=("wch:" . $b) n=({"name"=("cfm-" . $b . "g")}) p=$cp
}
:foreach k,s in=($w->"ssids") do={
  :local o ({})
  :foreach f in={"sec";"ft";"ftOverDs";"pmf";"isolation"} do={
    :set ($o->$f) ($d->$f)
    :if ([:len [:tostr ($s->$f)]] > 0) do={ :set ($o->$f) ($s->$f) }
  }
  :local nm ("cfm-" . $k)
  :local sp ({"name"=$nm;"authentication-types"=($o->"sec");"ft"=($o->"ft");"ft-over-ds"=($o->"ftOverDs");"management-protection"=($o->"pmf")})
  # PPSK (D32): Multi-Passphrase-Gruppe = Name des Profils; entfällt PPSK, wird sie gelöst
  :local pp ([:typeof ($w->"ppsk"->$k)] = "array")
  :if ($pp) do={ :set ($sp->"multi-passphrase-group") $nm }
  $cfmEnsure m="/interface/wifi/security" k=("wsec:" . $k) n=({"name"=$nm}) p=$sp
  :if (!$pp and $cfmDry != true) do={
    :onerror e in={
      :if ([:len [:tostr [/interface/wifi/security/get [find where name=$nm] multi-passphrase-group]]] > 0) do={
        /interface/wifi/security/unset [find where name=$nm] multi-passphrase-group
        $cfmLog ("PPSK-Gruppe an " . $nm . " entfernt")
      }
    } do={}
  }
  $cfmEnsure m="/interface/wifi/datapath" k=("wdp:" . $k) n=({"name"=$nm}) p=({"name"=$nm;"bridge"="bridge";"vlan-id"=($s->"vlan");"client-isolation"=($o->"isolation")})
  $cfmEnsure m="/interface/wifi/configuration" k=("wcf:" . $k) n=({"name"=$nm}) p=({"name"=$nm;"mode"="ap";"ssid"=($s->"ssid");"country"=($w->"country");"security"=$nm;"datapath"=$nm;"steering"="cfm-steer"})
}

# PPSK-Einträge: je Passphrase ein VLAN. Angelegt mit Zufallswert, die echte Passphrase kommt per
# Secret-Push aus dem Vault (ppsk.<ssid>.<name>) – sie steht nie in Daten, Log oder Probelauf.
:foreach k,ents in=($w->"ppsk") do={
  :foreach e,o in=$ents do={
    :local mp ({"group"=("cfm-" . $k);"vlan-id"=($o->"vlan");"isolation"="no"})
    :if ([:len [:tostr ($o->"isolation")]] > 0) do={ :set ($mp->"isolation") ($o->"isolation") }
    :if ([:len [:tostr ($o->"expires")]] > 0) do={ :set ($mp->"expires") ($o->"expires") }
    $cfmEnsure m="/interface/wifi/security/multi-passphrase" k=("mpp:" . $k . "." . $e) p=$mp a=({"passphrase"=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"]})
  }
}

# Master-Konfiguration je Band (trägt den Kanal) + optionales Pinning pro AP
:local ms ($w->"ssids"->$mk)
:local mcfg do={
  :global cfmEnsure
  $cfmEnsure m="/interface/wifi/configuration" k=("wcf:" . $key) n=({"name"=$name}) p=({"name"=$name;"mode"="ap";"ssid"=($s->"ssid");"country"=$country;"security"=("cfm-" . $mk);"datapath"=("cfm-" . $mk);"steering"="cfm-steer";"channel"=$ch})
}
:local rules ({})
:foreach ap,pins in=($w->"radios") do={
  :foreach b,f in=$pins do={
    :local c ($w->"channels"->$b)
    :local chn ("cfm-" . $b . "g-" . $ap)
    $cfmEnsure m="/interface/wifi/channel" k=("wch:" . $b . "-" . $ap) n=({"name"=$chn}) p=({"name"=$chn;"band"=($c->"band");"frequency"=$f;"width"=($c->"width")})
    $mcfg key=("m" . $b . "-" . $ap) name=("cfm-m" . $b . "-" . $ap) s=$ms mk=$mk country=($w->"country") ch=$chn
    :set ($rules->[:len $rules]) ({"b"=$b;"cfg"=("cfm-m" . $b . "-" . $ap);"re"=("^" . $ap . "\$")})
  }
}
:foreach b,c in=($w->"channels") do={
  $mcfg key=("m" . $b) name=("cfm-m" . $b) s=$ms mk=$mk country=($w->"country") ch=("cfm-" . $b . "g")
  :set ($rules->[:len $rules]) ({"b"=$b;"cfg"=("cfm-m" . $b);"re"=""})
}

# Provisioning (Reihenfolge: gepinnte APs vor generischen Regeln)
:local pl ({})
:foreach r in=$rules do={
  :local b ($r->"b")
  :local sl ({})
  :foreach k,s in=($w->"ssids") do={
    :if ($k != $mk and (("," . ($s->"bands") . ",") ~ ("," . $b . ","))) do={ :set ($sl->[:len $sl]) ("cfm-" . $k) }
  }
  :local pr ({"action"="create-dynamic-enabled";"supported-bands"=($w->"channels"->$b->"band");"master-configuration"=($r->"cfg");"slave-configurations"=$sl})
  :if ([:len ($r->"re")] > 0) do={ :set ($pr->"identity-regexp") ($r->"re") }
  :set ($pl->[:len $pl]) $pr
}
$cfmBlock m="/interface/wifi/provisioning" k="wprov" l=$pl

# CAPsMAN-Dienst: Primary aktiv; Backup passiv – außer der Netwatch meldet
# den Primary als "down" (dann hat cfm-takeover übernommen und bleibt aktiv)
:local cp ({"interfaces"=("vlan" . $mv);"certificate"="auto";"ca-certificate"="auto";"require-peer-certificate"="no";"upgrade-policy"="none"})
:if (!$backup) do={ :set ($cp->"enabled") "yes" } else={
  :local nws "unknown"
  :onerror e in={ :set nws [:tostr [/tool/netwatch/get [find where comment~"^cfm:nw:primary"] status]] } do={}
  :if ($nws != "down") do={ :set ($cp->"enabled") "no" }
}
$cfmSet m="/interface/wifi/capsman" p=$cp

:if ($backup) do={
  :local prim [:pick ($cfmG->"managers") 0]
  :local down (":if ([:len [/system/scheduler/find name=cfm-takeover]] = 0) do={ /system/scheduler/add name=cfm-takeover interval=1m on-event=\"/system script run cfm-mgr; :global cfmTakeover; \\\$cfmTakeover\" }")
  :local up ("/system/scheduler/remove [find name=cfm-takeover]; :global cfmTakeCnt 0; :if ([:tostr [/interface/wifi/capsman/get enabled]] ~ \"yes|true\") do={ /interface/wifi/capsman/set enabled=no; :log warning \"cfm: Primary-Manager zurück – CAPsMAN auf Backup deaktiviert\" }")
  $cfmEnsure m="/tool/netwatch" k="nw:primary" n=({"host"=$prim}) p=({"host"=$prim;"type"="icmp";"interval"="30s";"down-script"=$down;"up-script"=$up})
}
