# ============================================================
# cfm lib/mgr-core.rsc – Manager-Funktionen: Kern
# Die Manager-Funktionen liegen in lib/mgr-*.rsc (je Datei < 60 KB, Grenze von /file get).
# Jede Datei wird als Skript cfm-mgr-<modul> installiert; das Skript cfm-mgr lädt alle.
#   mgr-core     Hilfsfunktionen, Daten, Vault, Release/Ringe, Archiv, Push, Status, Audit,
#                Secrets, Identitätsprüfung und Geräteschlüssel
#   mgr-check    inhaltliche Prüfung von work/ ($cfmCheck), Probelauf ($cfmPlan)
#   mgr-enroll   Geräte aufnehmen, Bootstrap-Datei, Manager-Schlüssel verteilen
#   mgr-onboard  Onboarding per Push in die Werks-Config
#   mgr-ros      RouterOS-Pakete und -Updates ($cfmUpgrade)
#   mgr-net      Verkabelung per LLDP ($cfmLinks, Netzplan), WLAN-Kanäle ($cfmChannels), Gerätesuche
#   mgr-auto     Automatik (Scheduler cfm-mgr-tick), Spiegel des Backups, Beförderung
#   mgr-notify   Benachrichtigungen per HTTP-POST bei Zustandswechseln (D66)
#   mgr-mf       Manifest-Regeln (welche Dateien ein Gerät bekommt); lädt $cfmManifests aus der
#                jeweiligen Version (D70)
# Die Module hängen nur beim Aufruf voneinander ab (:global in den Funktionen), die
# Ladereihenfolge ist daher egal.
#
# Laden im Terminal des Managers:  /system script run cfm-mgr
#
#   $cfmRelease [msg="..."] [force=yes]  work/ prüfen -> archive/v<N> -> Ring 0 -> Push
#                                      (force=yes: trotz Fehlern der inhaltlichen Prüfung)
#   $cfmCheck                          inhaltliche Prüfung von work/ (läuft auch beim Release)
#   $cfmPlan host=<n>                  Probelauf: was würde ein Release von work/ ändern?
#   $cfmPlan host=<n> from=<verz> role=<rollen>   dasselbe für einen anderen Stand (<mgrPath>/<verz>/)
#                                      und/oder andere Rollen, z.B. das Zielbild eines Umbaus
#   $cfmPromote [ring=1|2]             Version des vorigen Rings freigeben
#   $cfmRollback ver=<N> [all=yes]     alten Stand als neue Version freigeben
#   $cfmStatus                         Flottenübersicht
#   $cfmEnroll name=<n> ip=<ip> [role=<r>] [ring=<0-2>] [rekey=yes]
#                                      Gerät aufnehmen / Ersatzgerät übernehmen
#   $cfmPush [host=<n>|ring=<r>] [force=yes]   sofortigen Pull auslösen (nur aufgenommene Geräte)
#   $cfmAudit host=<n> [op=report|mark|purge] [sel=all|A1,A3]
#   $cfmSecret key=<k> value=<v>       Vault: user.<name>, psk.<ssid-key>, ppsk.<ssid-key>.<name>,
#                                      vaultpw, wg.admin (D84)
#   $cfmSecretPush [host=<n>]          Secrets per SSH direkt in die Geräte schreiben
#   $cfmVaultBackup                    verschlüsseltes Backup (inkl. Vault) nach vault/
#   $cfmRekey host=<n>|all=yes         Geräteschlüssel (Manifest-Signatur) erneuern
#   $cfmRekey host=<n>|all=yes sftp=yes  SFTP-/Host-Schlüssel erneuern (Manager: zweiphasig, D67)
#   $cfmNotify test=yes                Probemeldung an global.rsc notify (D66)
#   $cfmArchivePrune [keep=<n>]        alte Versionen löschen (läuft nach jedem Release)
#   $cfmUpgrade ver=<x.y.z> host=<n>|ring=<r>|all=yes [at="YYYY-MM-DD HH:MM"]
#                                      RouterOS-Update/-Downgrade, Pakete kommen vom Manager
#   $cfmUpgrade ver=<x.y.z> host=..|ring=..|all=yes check=yes   Probe: Pakete, fehlende Dateien, Platz
#   $cfmUpgrade cancel=yes host=..|ring=..|all=yes   Auftrag zurückziehen; ohne ver: Übersicht
#   $cfmLinks [accept=yes] [export=yes]   Verkabelung (LLDP) prüfen, Netzplan state/netzplan.md
#   $cfmChannels                       Kanäle der APs, Warnung bei gleichem Kanal an einem Switch
#   $cfmFind [text] [host=<n>] [port=<p>] [ap=<ap>] [ssid=<s>] [vlan=<vid>] [signal=<dBm>]
#                                      Gerät suchen (MAC, IP, Name, Port, AP/SSID/Signal), live
#   $cfmWifiScan [host=<ap>] [band=2] [duration=10s] [data=yes]
#                                      Kanal-Scan aller APs nacheinander, Pin-Vorschlag für 2,4 GHz
#   $cfmBootstrap                      bootstrap.rsc für neue Geräte erzeugen
#   $cfmPromoteManager                 (auf dem Backup) zum Primary befördern
#   Onboarding (Push in die Werks-Config):
#   $cfmRegister name=<n> serial=<s> ip=<ip> [role=..] [ring=..] [pw=<Aufkleber-Passwort>]
#   $cfmOnboard sw=<switch> port=<port> [name=<n>]   Port temporär ins Onboarding-VLAN
#   $cfmOnboard manual=yes [name=<n>] [sw=.. port=..]  Switch nicht verwaltet: Port schaltet der Admin
#   $cfmOnboardStatus | $cfmOnboardAbort | $cfmPending | $cfmApprove serial=.. name=.. ip=..
# Automatisch: $cfmTick (Scheduler cfm-mgr-tick, Intervall global.rsc "mgrTick", Default 10m),
# $cfmOnbTickRun (Scheduler cfm-mgr-onb-tick, fest 1m, nur fürs Onboarding)
# ============================================================

# Dateien über den Namen ansprechen statt per /file/find (TODO 21): find wertet jede Datei aus
# (Hardware ~0,2 ms je Datei, CHR mit 600 Dateien 8 ms je Suche), /file/get <Name> braucht
# 0,05 ms. Suchen per Regex nur noch dort, wo wirklich mehrere Dateien gemeint sind.
:global cfmFileEx do={
  # Eine gelöschte Datei liefert /file/get u.U. dauerhaft weiter - als Eintrag ohne Namen (nur .id,
  # Labor 7.24.5, 2026-10-04); /file/find sieht sie nicht. Deshalb auf den Namen prüfen
  :local r false
  :onerror e in={ :if ([:len [/file/get $1 name]] > 0) do={ :set r true } } do={}
  :return $r
}
# Ablage einmal je Sitzung bestimmen (das flash/-Verzeichnis kommt und geht nicht im Betrieb)
:global cfmMB do={
  :global cfmMBv
  :if ([:typeof $cfmMBv] = "str") do={ :return $cfmMBv }
  :local r "cfm"
  :onerror e in={ :if ([/file/get "flash" type] = "directory") do={ :set r "flash/cfm" } } do={}
  :set cfmMBv $r
  :return $r
}
:global cfmWrite do={
  :global cfmFileEx
  # Eine gelöschte Datei meldet /file/get u.U. noch, /file/set scheitert dann mit "no such item"
  # (Hardware 2026-10-03: zweimal $cfmPlan hintereinander, der zweite leert plan/ und schreibt neu)
  :if ([$cfmFileEx $1]) do={ :onerror e in={ /file/set $1 contents=$2 } do={ /file/add name=$1 contents=$2 } } else={ /file/add name=$1 contents=$2 }
}
:global cfmRead do={
  :local r ""
  :onerror e in={ :set r [/file/get $1 contents] } do={}
  :return $r
}
:global cfmJson do={
  :global cfmRead
  :local r ({})
  :local c [$cfmRead $1]
  :if ([:len $c] > 0) do={ :onerror e in={ :set r [:deserialize from=json $c] } do={} }
  :return $r
}
:global cfmNow do={ :return ([:tonsec [:timestamp]] / 1000000000) }
:global cfmEsc do={
  :local s [:tostr $1]
  :local o ""
  :for i from=0 to=([:len $s] - 1) do={
    :local ch [:pick $s $i]
    :if ($ch = "\"" or $ch = "\\" or $ch = "\$") do={ :set o ($o . "\\" . $ch) } else={ :set o ($o . $ch) }
  }
  :return $o
}
:global cfmPad do={
  # mindestens ein Leerzeichen als Trenner, auch wenn der Wert die Spalte füllt
  :local s ([:tostr $1] . " ")
  :while ([:len $s] < $2) do={ :set s ($s . " ") }
  :return $s
}
# mehrzeiligen Text zeilenweise ausgeben: Ein :put mit "\n" im Text bricht im SSH-Terminal nur mit
# Linefeed um (ohne Wagenrücklauf), die Folgezeilen stehen dann treppenförmig versetzt
:global cfmPutLines do={
  :local t [:tostr $1]
  :while ([:len $t] > 0) do={
    :local p [:find $t "\n"]
    :local l $t
    :if ([:typeof $p] = "nil") do={ :set t "" } else={ :set l [:pick $t 0 $p]; :set t [:pick $t ($p + 1) [:len $t]] }
    :if ([:len $l] > 0 and [:pick $l ([:len $l] - 1) [:len $l]] = "\r") do={ :set l [:pick $l 0 ([:len $l] - 1)] }
    :put $l
  }
}

# ---------- Daten laden (vom Manager selbst geschrieben -> vertrauenswürdig) ----------
:global cfmRings do={
  :global cfmJson; :global cfmMB
  :local r [$cfmJson ([$cfmMB] . "/meta/rings.dat")]
  :if ([:typeof ($r->"latest")] = "nothing") do={ :set ($r->"latest") 0 }
  :return $r
}
:global cfmInvLoad do={
  :global cfmMB; :global cfmInv
  :set cfmInv ({})
  :onerror e in={ /import file-name=([$cfmMB] . "/meta/inventory.rsc") verbose=no } do={ :log warning ("cfm: inventory.rsc: " . $e) }
  :return $cfmInv
}
:global cfmInvSave do={
  :global cfmWrite; :global cfmMB
  :local s "# cfm – Inventar (Manager-Metadaten, wirkt sofort). Auch von \$cfmEnroll geschrieben.\n# Key = Identity; serial, role (base immer; router,switch,ap,capsman,manager,manager-backup), ring 0-2, ip (MGMT)\n:global cfmInv {\n"
  :local sep ""
  :foreach n,d in=$1 do={
    :set s ($s . $sep . "  \"" . $n . "\"={\"serial\"=\"" . ($d->"serial") . "\";\"role\"=\"" . ($d->"role") . "\";\"ring\"=" . ($d->"ring") . ";\"ip\"=\"" . ($d->"ip") . "\"}")
    :set sep ";\n"
  }
  $cfmWrite ([$cfmMB] . "/meta/inventory.rsc") ($s . "\n}\n")
}
# Aufgenommen = Geräteschlüssel im Vault (wie bei den Manifesten). Platzhalter (SERIAL-…) und per
# $cfmRegister eingetragene, noch nicht aufgenommene Geräte haben keinen: Push, Secret-Push, Trust,
# Rekey, Collect, Auto-Promote und Upgrade lassen sie aus (TODO 28). $1 = Inventar-Eintrag
:global cfmEnrolled do={
  :global cfmVaultGet
  :local s [:tostr ($1->"serial")]
  :return ([:len $s] > 0 and [:len [$cfmVaultGet ("mac." . $s)]] > 0)
}
# CAPsMAN-Geräte (D45): alle mit Rolle capsman, ohne solche übergangsweise der Primary-Manager
# (Rolle manager) -> Liste {"n"=Name;"ip"=MGMT-IP}. Steht als Feld cm in jedem Manifest: Die Rolle
# ap setzt daraus caps-man-addresses/-names, cfmIsCapsman entscheidet damit über den Dienst.
:global cfmCapsmen do={
  :local r ({})
  :foreach rr in={",capsman,";",manager,"} do={
    :if ([:len $r] = 0) do={
      :foreach n,d in=$1 do={
        :if ((("," . [:tostr ($d->"role")] . ",") ~ $rr) and [:len [:tostr ($d->"ip")]] > 0) do={ :set ($r->[:len $r]) ({"n"=$n;"ip"=[:tostr ($d->"ip")]}) }
      }
    }
  }
  :return $r
}
# globale Daten (cfmG, cfmVlans, cfmWifi …) der Version ver (Default: neueste; 0 = work/)
:global cfmLoadData do={
  :global cfmMB; :global cfmRings; :global cfmApplyBusy
  # Nicht mitten in einen Apply des Agents auf diesem Gerät importieren: beide nutzen cfmG und die
  # Bibliothek global, der Apply verlöre die Werte aus dem Hostfile (Labor 2026-10-11). Warten,
  # solange er läuft (Sperre gesetzt und Job vorhanden), höchstens 120 s
  :local aw 0
  :while ($cfmApplyBusy = true and [:len [/system/script/job/find where script="cfm-agent"]] > 0 and $aw < 120) do={ :delay 1s; :set aw ($aw + 1) }
  :if ($aw >= 120) do={ :log warning "cfm: Daten geladen, obwohl der Agent noch anwendet (120 s gewartet)" }
  # Gegenrichtung: Ein Apply, der jetzt startet, wartet, solange cfmMgrData jünger als 30 s ist (der
  # Agent liest dieselben globalen Variablen). hold=yes: nicht freigeben, der Aufrufer importiert
  # danach noch Hostfiles und frischt den Zeitstempel selbst auf ($cfmCheck, $cfmShow)
  :global cfmMgrData; :set cfmMgrData ([:tonsec [:timestamp]] / 1000000000)
  :local b [$cfmMB]
  :local v $ver
  :if ([:len [:tostr $v]] = 0) do={ :set v ([$cfmRings]->"latest") }
  :local d ($b . "/archive/v" . $v)
  # ver=0: Arbeitsstand work/ bzw. dir=<verzeichnis> ($cfmPlan from=)
  :if ($v = 0) do={ :set d ($b . "/work"); :if ([:len [:tostr $dir]] > 0) do={ :set d ($b . "/" . $dir) } }
  # Zur Version gehörende Gerätebibliothek mitladen: Manager-Funktionen nutzen ihre Helfer
  # ($cfmNet, $cfmTarget). Global sind sie sonst erst nach einem Apply des Agents - direkt nach
  # Bootstrap oder Neustart fehlen sie, und RouterOS meldet den Aufruf einer unbekannten Funktion
  # nicht, sondern liefert stillschweigend "nothing" (siehe DECISIONS.md).
  :onerror e in={ /import file-name=($d . "/lib/lib.rsc") verbose=no } do={}
  :foreach f in={"global.rsc";"vlans.rsc";"profiles.rsc";"wifi.rsc";"wireguard.rsc"} do={ /import file-name=($d . "/" . $f) verbose=no }
  # leases.rsc (D62) ist optional: ältere Versionen im Archiv haben sie nicht
  :global cfmLeases; :set cfmLeases ({})
  :onerror e in={ /import file-name=($d . "/leases.rsc") verbose=no } do={}
  # mlag.rsc (D75) ebenso optional
  :global cfmMlag; :set cfmMlag ({})
  :onerror e in={ /import file-name=($d . "/mlag.rsc") verbose=no } do={}
  :if ($hold != "yes") do={ :set cfmMgrData 0 }
  :return $v
}

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

# ---------- SSH zu Geräten ----------
:global cfmExec do={
  :local r ({"exit-code"=255;"output"=""})
  :onerror e in={ :set r [/system/ssh-exec address=$ip user="cfm" command=$cmd as-value] } do={ :set ($r->"output") ("ssh-exec: " . $e) }
  :return $r
}

# ---------- Rolle / Primary ----------
:global cfmIsPrimary do={
  :global cfmMB; :global cfmG; :global cfmLoadData; :global cfmFileEx
  :if ([$cfmFileEx ([$cfmMB] . "/meta/PROMOTED")]) do={ :return true }
  :if ([:typeof $cfmG] != "array") do={ $cfmLoadData }
  :local p [:pick ($cfmG->"managers") 0]
  :return ([:len [/ip/address/find where address~("^" . $p . "/")]] > 0)
}

# ---------- Externe Sicherung (Git-Host per ssh-exec) ----------
:global cfmHook do={
  :global cfmG; :global cfmLoadData
  :if ([:typeof $cfmG] != "array") do={ $cfmLoadData }
  :local h ($cfmG->"hook")
  :if ([:len [:tostr ($h->"host")]] = 0) do={ :return "" }
  :local hv "-"; :if ([:len [:tostr $ver]] > 0) do={ :set hv ("v" . $ver) }
  :local hh "-"; :if ([:len [:tostr $host]] > 0) do={ :set hh $host }
  :onerror e in={
    :local r [/system/ssh-exec address=($h->"host") user=($h->"user") command=($ev . " " . $hv . " " . $hh) as-value]
    :log info ("cfm: Hook " . $ev . ": " . [:pick ($r->"output") 0 200])
  } do={ :log warning ("cfm: Hook " . $ev . " fehlgeschlagen: " . $e) }
  :return ""
}

# ---------- Manifeste (pro Gerät, mit MAC) ----------
# plan=<host>: nur für diesen Host ein Plan-Manifest aus dem Schnappschuss plan/ ($cfmPlan);
# role=<rollen>: dabei statt der Rollen aus dem Inventar (Probe eines Rollenwechsels)
# Welche Dateien ein Gerät bekommt, regelt $cfmMfWant aus lib/mgr-mf.rsc der Version, die es bekommt
# (D70): je Version einmal geladen. Versionen ohne die Datei baut die installierte Fassung (Skript
# cfm-mgr-mf), fehlt auch die, die der neuesten Version (Übergang vom Manager-Code vor D70).
:global cfmManifests do={
  :global cfmMB; :global cfmRings; :global cfmInvLoad; :global cfmVaultGet; :global cfmWrite
  :global cfmJson; :global cfmG; :global cfmLoadData; :global cfmCapsmen; :global cfmFileEx
  :local b [$cfmMB]
  :local rg [$cfmRings]
  :local pl [:len $plan]
  :if ($pl > 0) do={ $cfmLoadData ver=0 } else={ $cfmLoadData }
  # Gemeinsamer WireGuard-Schlüssel der Router (D84): öffentlicher Schlüssel in die Manifeste der Router;
  # erzeugt bzw. übernommen wird er nur beim echten Release, nicht im Probelauf
  :global cfmWg
  :local wgpub ""
  :if ([:typeof $cfmWg] = "array" and [:len ($cfmWg->"peers")] > 0) do={
    :if ($pl = 0) do={ :global cfmWgKey; :set wgpub [$cfmWgKey] } else={ :set wgpub [:tostr ([$cfmJson ($b . "/meta/vault.dat")]->"wgpub")] }
  }
  :local reap ([:tonsec [:totime ($cfmG->"reapply")]] / 1000000000)
  :local inv [$cfmInvLoad]
  :local cms [$cfmCapsmen $inv]
  # DNS-Namen der Geräte für die Router (D62): aufgenommene Geräte mit Namen aus Buchstaben, Ziffern, "-"
  :global cfmEnrolled
  :local dnsH ({})
  :foreach hn,hd in=$inv do={
    :if ([$cfmEnrolled $hd] and [:len [:tostr ($hd->"ip")]] > 0 and $hn ~ "^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\$") do={ :set ($dnsH->$hn) [:tostr ($hd->"ip")] }
  }
  :local ord [$cfmJson ($b . "/meta/upgrade.dat")]
  :local cnt 0
  # MACs der Router (D76): Die Filter isolierter VLANs erkennen das Gateway an ihnen (ein Bridge-Filter
  # kann IP-Adressen nicht zuverlässig prüfen). Nur, wenn ein VLAN isoliert ist - sonst bliebe jedes
  # Manifest gleich
  :global cfmVlans
  :local rmac ({})
  :local anyIso false
  :foreach vid,vv in=$cfmVlans do={ :if ([:tostr ($vv->"isolate")] = "yes") do={ :set anyIso true } }
  :if ($anyIso) do={
    :foreach rn,rd in=$inv do={
      :if (("," . [:tostr ($rd->"role")] . ",") ~ ",router,") do={
        :local rm ""
        :onerror e in={ :set rm [:tostr ([$cfmJson ($b . "/state/" . $rn . "/status.dat")]->"mac")] } do={}
        :if ([:len $rm] > 0) do={ :set ($rmac->[:len $rmac]) $rm } else={ :log warning ("cfm: isoliertes VLAN, aber keine MAC von Router " . $rn . " im Status") }
      }
    }
  }
  # Version je Gerät, Quellen sammeln (archive/vN bzw. plan)
  :local dv ({})
  :local srcs ({})
  :foreach name,d in=$inv do={
   :if ($pl = 0 or $plan = $name) do={
    :local ring [:tostr ($d->"ring")]
    :if ([:len $ring] = 0) do={ :set ring "2" }
    :local v ($rg->("r" . $ring))
    :if ($pl > 0) do={ :set v 0 }
    :if ([:len [:tostr $v]] > 0) do={
      :set ($dv->$name) ({$v;$ring})
      :if ($pl > 0) do={ :set ($srcs->"plan") 1 } else={ :set ($srcs->("archive/v" . $v)) 1 }
    }
   }
  }
  :foreach src,x in=$srcs do={
    # Manifest-Regeln dieser Version laden (D70)
    :local how ""
    :local mf ($b . "/" . $src . "/lib/mgr-mf.rsc")
    :if ([$cfmFileEx $mf]) do={
      :onerror e in={ /import file-name=$mf verbose=no; :set how $src } do={ :log warning ("cfm: Manifest-Regeln aus " . $src . " nicht geladen: " . $e) }
    }
    :if ([:len $how] = 0 and [:len [/system/script/find where name="cfm-mgr-mf"]] > 0) do={
      :onerror e in={ /system/script/run cfm-mgr-mf; :set how "installiert" } do={}
    }
    :if ([:len $how] = 0) do={
      :local lf ($b . "/archive/v" . ($rg->"latest") . "/lib/mgr-mf.rsc")
      :if ([$cfmFileEx $lf]) do={ :onerror e in={ /import file-name=$lf verbose=no; :set how "neueste" } do={} }
    }
    :global cfmMfWant
    :if ([:len $how] = 0 or [:typeof $cfmMfWant] = "nothing") do={
      :log warning ("cfm: keine Manifest-Regeln für " . $src . " (lib/mgr-mf.rsc) - deren Manifeste bleiben unverändert")
    } else={
     :local fx ([$cfmJson ($b . "/" . $src . "/index.dat")]->"files")
     :foreach name,vr in=$dv do={
      :local d ($inv->$name)
      :local v ($vr->0)
      :local ring ($vr->1)
      :local isrc ("archive/v" . $v)
      :if ($pl > 0) do={ :set isrc "plan" }
      :if ($isrc = $src) do={
       # Dateiname aus der Seriennummer: Die System-ID einer CHR kann "/" enthalten (TODO 42)
       :local sfn ""
       :for i from=0 to=([:len ($d->"serial")] - 1) do={ :local c [:pick ($d->"serial") $i]; :if ($c = "/") do={ :set c "_" }; :set sfn ($sfn . $c) }
       :local out ($b . "/live/m/" . $sfn . ".mf")
       :if ($pl > 0) do={ :set out ($b . "/plan/m/" . $sfn . ".mf") }
       :local key [$cfmVaultGet ("mac." . ($d->"serial"))]
       :if ([:len $key] > 0) do={
        :local rol [:tostr ($d->"role")]
        :if ($pl > 0 and [:len $role] > 0) do={ :set rol $role }
        :local want ({})
        :onerror e in={ :set want [$cfmMfWant name=$name role=$rol fx=$fx] } do={ :log warning ("cfm: " . $name . ": Manifest-Regeln aus " . $how . " fehlgeschlagen: " . $e) }
        :local fl ({})
        :local ok ([:len $want] > 0)
        :foreach w in=$want do={
          :local h ($fx->($w->0))
          :if ([:len $h] > 0) do={ :set ($fl->[:len $fl]) ({($w->0);$h;($w->1)}) } else={
            :if (($w->2) = 1) do={ :set ok false; :log warning ("cfm: " . $name . ": Pflichtdatei fehlt in " . $src . ": " . ($w->0)) }
          }
        }
        :if ($ok) do={
          :local m ({"v"=$v;"src"=$src;"name"=$name;"role"=$rol;"ring"=[:tonum $ring];"ip"=($d->"ip");"serial"=($d->"serial");"reapply"=$reap;"watchdog"=($cfmG->"watchdog");"cm"=$cms;"files"=$fl})
          :local rl ("," . $rol . ",")
          :if ($rl ~ ",router,") do={ :set ($m->"dns") $dnsH }
          :if ($rl ~ ",router," and [:len $wgpub] > 0) do={ :set ($m->"wgpub") $wgpub }
          :if ([:len $rmac] > 0) do={ :set ($m->"rmac") $rmac }
          # offener RouterOS-Auftrag ($cfmUpgrade); ändert den Manifest-Hash des Agents nicht
          :if ($pl = 0 and [:typeof ($ord->$name)] = "array") do={ :set ($m->"ros") ($ord->$name) }
          :local body [:serialize to=json $m]
          :local mac [:convert ($key . [:convert $body transform=sha512 to=hex]) transform=sha512 to=hex]
          $cfmWrite $out ($body . "\n# mac=" . $mac . "\n")
          :set cnt ($cnt + 1)
        }
       }
      }
     }
    }
  }
  :return $cnt
}

# work/-Dateien auf Größe (/file get liest nur ~60 KB) und Syntax (:parse) prüfen -> "" oder Liste
# dir=<verzeichnis>: statt work/ ($cfmPlan from=)
:global cfmParseWork do={
  :global cfmMB
  :local b [$cfmMB]
  :local w "work"
  :if ([:len [:tostr $dir]] > 0) do={ :set w $dir }
  :local bad ""
  :foreach f in=[/file/find where name~("^" . $b . "/" . $w . "/") and type!="directory"] do={
    :local n [/file/get $f name]
    :if ([/file/get $f size] > 60000) do={ :set bad ($bad . " " . $n . " (>60KB)") } else={
      :if ($n ~ "\\.rsc\$") do={ :onerror e in={ :local x [:parse [/file/get $f contents]] } do={ :set bad ($bad . " " . $n . " (" . $e . ")") } }
    }
  }
  :return $bad
}

# ---------- Release / Ringe ----------
:global cfmRelease do={
  :global cfmMB; :global cfmIsPrimary; :global cfmWrite; :global cfmRings; :global cfmManifests
  :global cfmHook; :global cfmPush; :global cfmNow; :global cfmParseWork; :global cfmCheck; :global cfmArchivePrune
  :local b [$cfmMB]
  :if (![$cfmIsPrimary]) do={ :error "nicht Primary: Backup-Manager ist read-only (\$cfmPromoteManager)" }
  :local bad [$cfmParseWork]
  :if ([:len $bad] > 0) do={ :error ("Release abgebrochen:" . $bad) }
  # inhaltliche Prüfung (mgr-check): Fehler stoppen das Release, force=yes übergeht sie.
  # Der Prüfer kommt aus work/ (TODO 21): Nach einem Framework-Update kennt der installierte die
  # neuen Kennzeichen noch nicht und hielte das erste Release auf. Lädt die neue Fassung nicht,
  # prüft die installierte.
  :onerror e in={ /import file-name=($b . "/work/lib/mgr-check.rsc") verbose=no } do={ :put ("Hinweis: Prüfer aus work/ nicht geladen (" . $e . "), es prüft der installierte") }
  :global cfmCheck
  :local ck [$cfmCheck]
  :foreach w in=($ck->"warn") do={ :put ("Warnung: " . $w) }
  :if ([:len ($ck->"err")] > 0) do={
    :foreach e in=($ck->"err") do={ :put ("Fehler: " . $e) }
    :if ($force != "yes") do={ :error ("Release abgebrochen (Prüfung): " . [:len ($ck->"err")] . " Fehler - beheben oder force=yes") }
    :put "force=yes: Release trotz Prüffehlern"
  }
  :local files [/file/find where name~("^" . $b . "/work/") and type!="directory"]
  :local rg [$cfmRings]
  :local v (($rg->"latest") + 1)
  :local idx ({})
  :foreach f in=$files do={
    :local n [/file/get $f name]
    :local rel [:pick $n ([:len $b] + 6) [:len $n]]
    :local c [/file/get $f contents]
    $cfmWrite ($b . "/archive/v" . $v . "/" . $rel) $c
    :set ($idx->$rel) [:convert $c transform=sha512 to=hex]
  }
  # rsc-check: erlaubt json-typ (date nur für Menschen, cfm liest es nicht zurück)
  :local ix ({"v"=$v;"msg"=[:tostr $msg];"date"=([/system/clock/get date] . " " . [/system/clock/get time]);"files"=$idx})
  $cfmWrite ($b . "/archive/v" . $v . "/index.dat") [:serialize to=json $ix]
  :local now [$cfmNow]
  :set ($rg->"latest") $v
  :foreach r in={"0";"1";"2"} do={
    :if ($r = "0" or [:typeof ($rg->("r" . $r))] = "nothing" or $all = "yes") do={ :set ($rg->("r" . $r)) $v; :set ($rg->("t" . $r)) $now }
  }
  $cfmWrite ($b . "/meta/rings.dat") [:serialize to=json $rg]
  :local n [$cfmManifests]
  :put ("Release v" . $v . " erstellt (" . [:len $idx] . " Dateien, " . $n . " Manifeste) -> Ring 0" . [:tostr $msg])
  :log info ("cfm: Release v" . $v . " " . [:tostr $msg])
  :local pr [$cfmArchivePrune]
  :if ($pr > 0) do={ :put ("Archiv: " . $pr . " alte Versionen gelöscht") }
  $cfmHook ev="release" ver=$v
  :if ($all = "yes") do={ $cfmPush } else={ $cfmPush ring=0 }
  :return $v
}

:global cfmPromote do={
  :global cfmMB; :global cfmRings; :global cfmWrite; :global cfmManifests; :global cfmHook
  :global cfmPush; :global cfmNow
  :local r [:tonum $ring]
  :if ($r < 1 or $r > 2) do={
    :local rg [$cfmRings]
    :set r 1
    :if (($rg->"r1") = ($rg->"r0")) do={ :set r 2 }
  }
  :local rg [$cfmRings]
  :local v ($rg->("r" . ($r - 1)))
  :set ($rg->("r" . $r)) $v
  :set ($rg->("t" . $r)) [$cfmNow]
  $cfmWrite ([$cfmMB] . "/meta/rings.dat") [:serialize to=json $rg]
  $cfmManifests
  :put ("Ring " . $r . " -> v" . $v)
  :log info ("cfm: Ring " . $r . " -> v" . $v)
  $cfmHook ev="promote" ver=$v host=("ring" . $r)
  $cfmPush ring=$r
}

:global cfmRollback do={
  :global cfmMB; :global cfmRelease; :global cfmWrite; :global cfmHook; :global cfmFileEx
  :local b [$cfmMB]
  :if (![$cfmFileEx ($b . "/archive/v" . $ver . "/index.dat")]) do={ :error ("Version v" . $ver . " nicht im Archiv") }
  # work/ sichern und durch den alten Stand ersetzen, dann normal releasen
  :foreach f in=[/file/find where name~("^" . $b . "/work/") and type!="directory"] do={ /file/remove $f }
  :foreach f in=[/file/find where name~("^" . $b . "/archive/v" . $ver . "/") and type!="directory"] do={
    :local n [/file/get $f name]
    :local rel [:pick $n ([:len ($b . "/archive/v" . $ver)] + 1) [:len $n]]
    :if ($rel != "index.dat") do={ $cfmWrite ($b . "/work/" . $rel) [/file/get $f contents] }
  }
  # force: ein alter, bewährter Stand soll nicht an neueren Prüfregeln scheitern
  :local v [$cfmRelease msg=(" Rollback auf v" . $ver) all=$all force="yes"]
  $cfmHook ev="rollback" ver=$v host=("from-v" . $ver)
}

# ---------- Push-Trigger ----------
:global cfmPush do={
  :global cfmInvLoad; :global cfmExec; :global cfmEnrolled
  :local c ":execute \"/system script run cfm-agent\""
  :if ($force = "yes") do={ :set c ":execute \":global cfmArg \\\"force\\\"; /system script run cfm-agent\"" }
  # nicht aufgenommene Geräte nie anstoßen: Unter der geplanten Adresse kann ein fremdes Gerät stehen
  :local skip ""
  :foreach name,d in=[$cfmInvLoad] do={
    :if (([:len $host] = 0 or $host = $name) and ([:len [:tostr $ring]] = 0 or [:tostr $ring] = [:tostr ($d->"ring")])) do={
      :if ([$cfmEnrolled $d]) do={
        :local r [$cfmExec ip=($d->"ip") cmd=$c]
        :if (($r->"exit-code") = 0) do={ :put ("Push -> " . $name) } else={ :put ("Push -> " . $name . " FEHLER " . ($r->"output")) }
      } else={ :set skip ($skip . " " . $name) }
    }
  }
  :if ([:len $skip] > 0) do={ :put ("kein Push (nicht aufgenommen):" . $skip) }
}

# ---------- Status ----------
:global cfmStatus do={
  :global cfmInvLoad; :global cfmRings; :global cfmJson; :global cfmMB; :global cfmPad; :global cfmNow
  :global cfmEnrolled
  :local b [$cfmMB]
  :local rg [$cfmRings]
  :local vj [$cfmJson ($b . "/meta/vault.dat")]
  :local now [$cfmNow]
  :put ("Releases: latest v" . ($rg->"latest") . "  Ring0 v" . ($rg->"r0") . "  Ring1 v" . ($rg->"r1") . "  Ring2 v" . ($rg->"r2") . "   Vault v" . [:tonum ($vj->"ver")])
  :local ord [$cfmJson ($b . "/meta/upgrade.dat")]
  # NAME-Spalte so breit wie der längste Name (mindestens 10)
  :local inv [$cfmInvLoad]
  :local nw 10
  :foreach n,x in=$inv do={ :if ([:len $n] >= $nw) do={ :set nw ([:len $n] + 1) } }
  :put ([$cfmPad "NAME" $nw] . [$cfmPad "RING" 5] . [$cfmPad "SOLL" 6] . [$cfmPad "IST" 6] . [$cfmPad "ERGEBNIS" 26] . [$cfmPad "SV" 4] . [$cfmPad "ROUTEROS" 16] . "ZULETZT")
  :foreach name,d in=$inv do={
    :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
    :local ros [:tostr ($s->"ros")]
    :set ros [:pick $ros 0 [:find ($ros . " ") " "]]
    :if ([:typeof ($ord->$name)] = "array") do={ :set ros ($ros . "->" . [:pick [:tostr ($ord->$name->"rv")] 1 99]) }
    :local sv [:tostr ($s->"sv")]
    :local p [:find $sv "sv="]
    :if ([:typeof $p] != "nil") do={ :set sv [:pick $sv ($p + 3) [:len $sv]] }
    :local age "-"
    :if ([:len [:tostr ($s->"seen")]] > 0) do={ :set age (($now - [:tonum ($s->"seen")]) / 60 . " min") }
    :local res [:tostr ($s->"res")]
    :if ([:len [:tostr ($s->"pending")]] > 0) do={ :set res ($res . " pend v" . ($s->"pending")) }
    # bad = zuletzt gescheiterte Version (der Agent wendet sie nicht erneut an). Liegt danach schon eine
    # neuere ok vor, ist sie Geschichte - nur anzeigen, solange sie nicht älter ist als IST oder SOLL ist.
    # Vorn, weil die Spalte nach 25 Zeichen endet (der Fehlertext in res ist meist länger)
    :local bv [:tonum ($s->"bad")]
    :local iv [:tonum ($s->"v")]; :if ([:typeof $iv] != "num") do={ :set iv 0 }
    :local sv0 [:tonum ($rg->("r" . ($d->"ring")))]; :if ([:typeof $sv0] != "num") do={ :set sv0 0 }
    :if ([:typeof $bv] = "num" and ($bv >= $iv or $bv = $sv0)) do={ :set res ("bad v" . $bv . " " . $res) }
    :if ([:len [:tostr ($s->"fwe")]] > 0) do={ :set res ($res . " fw " . ($s->"fwe") . "!") }
    :if ([:tostr ($s->"wfb")] = "1") do={ :set res ($res . " WLAN lokal") }
    :if (![$cfmEnrolled $d]) do={ :set res "nicht aufgenommen" }
    :put ([$cfmPad $name $nw] . [$cfmPad ($d->"ring") 5] . [$cfmPad ("v" . ($rg->("r" . ($d->"ring")))) 6] . [$cfmPad ("v" . [:tostr ($s->"v")]) 6] . [$cfmPad [:pick $res 0 25] 26] . [$cfmPad $sv 4] . [$cfmPad $ros 16] . $age)
  }
}

# ---------- Audit (Hand-Objekte auf einem Gerät) ----------
:global cfmAudit do={
  :global cfmInvLoad; :global cfmExec; :global cfmHook
  :local d ([$cfmInvLoad]->$host)
  :if ([:typeof $d] != "array") do={ :error ("unbekannter Host " . $host) }
  :local o $op; :if ([:len $o] = 0) do={ :set o "report" }
  :local s $sel; :if ([:len $s] = 0) do={ :set s "all" }
  :if ($o != "report" and [:len $sel] = 0) do={ :error "mark/purge braucht sel=all oder sel=A1,A3" }
  :local r [$cfmExec ip=($d->"ip") cmd=(":global cfmArg {\"mode\"=\"audit\";\"op\"=\"" . $o . "\";\"sel\"=\"" . $s . "\"}; /system script run cfm-agent")]
  :put ($r->"output")
  :global cfmWrite; :global cfmMB
  $cfmWrite ([$cfmMB] . "/state/" . $host . "/audit.txt") ($r->"output")
  $cfmHook ev="audit" host=$host
}

# ---------- Rückkanal: Status + Export bei den Geräten abholen ----------
# Geräte haben am Manager nur Lesezugriff; der Manager (User cfm auf dem Gerät)
# holt cfm/out/status.json und – wenn neu – cfm/out/export.rsc nach state/<name>/.
:global cfmCollect do={
  :global cfmInvLoad; :global cfmMB; :global cfmJson; :global cfmEnrolled; :global cfmFileEx
  :local b [$cfmMB]
  :local n 0
  :foreach name,d in=[$cfmInvLoad] do={
    :if (([:len $host] = 0 or $host = $name) and [:len [:tostr ($d->"ip")]] > 0 and [$cfmEnrolled $d]) do={
      :if ([:typeof ([/ping ($d->"ip") count=1 as-value]->"time")] = "time") do={
        :local sd ($b . "/state/" . $name)
        :local old [$cfmJson ($sd . "/status.dat")]
        :local got ""
        :foreach p in={"cfm/out";"flash/cfm/out"} do={
          :if ($got = "") do={
            :onerror e in={ /tool/fetch url=("sftp://" . ($d->"ip") . "/" . $p . "/status.json") user="cfm" dst-path=($sd . "/status.dat") as-value; :set got $p } do={}
          }
        }
        :if ($got != "") do={
          :set n ($n + 1)
          :local new [$cfmJson ($sd . "/status.dat")]
          :if ([:tostr ($new->"et")] != [:tostr ($old->"et")] or ![$cfmFileEx ($sd . "/export.rsc")]) do={
            :onerror e in={ /tool/fetch url=("sftp://" . ($d->"ip") . "/" . $got . "/export.rsc") user="cfm" dst-path=($sd . "/export.rsc") as-value } do={}
          }
        }
      }
    }
  }
  :return $n
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

# ---------- Archiv aufräumen (D27) ----------
# Behält die letzten archiveKeep Versionen (global.rsc, Standard 5) und alle Versionen, die ein
# Ring nutzt oder die ein Gerät meldet (angewendet, ausstehend, als fehlerhaft markiert).
:global cfmArchivePrune do={
  :global cfmMB; :global cfmRings; :global cfmInvLoad; :global cfmJson; :global cfmG
  :local b [$cfmMB]
  :local rg [$cfmRings]
  :local k [:tonum $keep]
  :if ([:typeof $k] != "num") do={ :set k [:tonum ($cfmG->"archiveKeep")] }
  :if ([:typeof $k] != "num") do={ :set k 5 }
  :if ($k < 1) do={ :set k 1 }
  :local used ({})
  :foreach r in={"r0";"r1";"r2";"latest"} do={ :set ($used->[:tostr ($rg->$r)]) 1 }
  :foreach name,d in=[$cfmInvLoad] do={
    :local s [$cfmJson ($b . "/state/" . $name . "/status.dat")]
    :foreach f in={"v";"pending";"bad";"target"} do={ :if ([:len [:tostr ($s->$f)]] > 0) do={ :set ($used->[:tostr ($s->$f)]) 1 } }
  }
  :local lim ([:tonum ($rg->"latest")] - $k)
  :local pre ($b . "/archive/v")
  :local n 0
  :foreach f in=[/file/find where name~("^" . $pre . "[0-9]+\$") and type="directory"] do={
    :local vs [:pick [/file/get $f name] [:len $pre] 99]
    :if ([:tonum $vs] <= $lim and [:typeof ($used->$vs)] = "nothing") do={
      :local dd ($pre . $vs)
      # index.dat zuerst: eine halb gelöschte Version gilt damit sofort als nicht vorhanden
      :onerror e in={ /file/remove [find where name=($dd . "/index.dat")] } do={}
      :foreach x in=[/file/find where name~("^" . $dd . "/") and type!="directory"] do={ /file/remove $x }
      :local ds [/file/find where name~("^" . $dd . "(/|\$)") and type="directory"]
      :for i from=([:len $ds] - 1) to=0 step=-1 do={ :onerror e in={ /file/remove [:pick $ds $i] } do={} }
      :set n ($n + 1)
    }
  }
  :if ($n > 0) do={ :log info ("cfm: Archiv: " . $n . " alte Versionen gelöscht (behalten: " . $k . " + genutzte)") }
  :return $n
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
