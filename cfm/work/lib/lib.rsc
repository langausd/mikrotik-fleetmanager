# ============================================================
# cfm lib/lib.rsc – Reconciler-Bibliothek (Geräteseite)
# Wird vom Agent bei jedem Apply als erstes importiert und definiert
# globale Funktionen für die Rollen-Templates. Der WLAN-Teil (CAPsMAN, lokale WLAN-Profile der
# APs) steht in lib/lib-wifi.rsc und kommt nur zu den Rollen ap, capsman und manager (D68).
#
# Kommentar-Konvention an RouterOS-Objekten:
#   "cfm:<key> [text]"  verwaltet: wird angelegt/angeglichen, verwaist -> entfernt
#   "cfm-override .."   manuell und bewusst behalten (per Audit markiert)
#   "cfm-sys:<key>"     framework-intern (Onboarding), kein GC, nicht im Audit
#   (kein Präfix)       lokal/Hand angelegt: nie angefasst, im Audit gelistet
#
# Probelauf ($cfmPlan am Manager): Der Agent setzt :global cfmDry true. cfmRun führt dann
# kein add/set/remove aus, cfmLog/cfmWarn sammeln die Meldungen in cfmPlanOut (= der Plan).
# Direkte Befehle in Rollen/Hostfiles deshalb nur mit  :if ($cfmDry != true) do={ ... }
#
# RouterOS-Syntaxfallen (auf 7.24 verifiziert) – für eigene Templates wichtig:
#  * Funktionen als Anweisung OHNE eckige Klammern aufrufen. Eine Zeile, die
#    mit "[" beginnt, liest RouterOS u.U. als Fortsetzung der vorigen Anweisung
#    ("expected end of command"):
#      $cfmEnsure m="/interface/bridge" k="br" p=({"name"="bridge"})
#  * Array-Literale in Aufrufen in runde Klammern setzen: p=({...})
#  * Ein leeres Array direkt nach :global/:local ({} oder {\n}) liest RouterOS als Codeblock -
#    Syntaxfehler beim /import. ({}) schreiben (tools/rsc-check.py: leeres-array).
#  * Ein String-Literal mit Escape (\n, \", \$) direkt als Argument einer eigenen Funktion ist ein
#    Syntaxfehler (positionell und k="…", Konsole wie /import, 7.24.5; eingebaute Befehle wie :pick
#    sind nicht betroffen). In runde Klammern setzen oder vorher in eine Local legen:
#      $cfmWrite "x.json" ("{\"a\":1}")      (tools/rsc-check.py: escape-argument)
#  * /import ... verbose=yes führt Zeilen einzeln aus -> Locals gehen verloren.
#  * :return innerhalb von :onerror ... in={} verlässt die Funktion nicht –
#    Ergebnis in ein Flag schreiben und am Ende zurückgeben.
#  * Fehlertexte aus :onerror nie per = vergleichen: RouterOS 7.24.4 hängt an
#    :error "x" noch " (:error; line N)" an -> per ~ "^x" prüfen.
#  * Kein Operator !~ ("cannot invert string") -> !($x ~ "re") schreiben.
#  * :parse prüft keine Parameternamen. Ob eine Version einen Parameter kennt, zeigt ein set gegen
#    eine ID, die es nicht gibt: "no such item" = bekannt, "bad parameter" = unbekannt.
#  * Neue Felder lieber am Eigenschafts-Array von get erkennen ([:typeof ($a->"feld")] = "nothing"
#    heißt unbekannt) als an der Versionsnummer. get auf [find name=..] scheitert, wenn es den
#    Namen auch dynamisch gibt (z.B. /ip/service ssh) -> "and !dynamic" bzw. [:pick .. 0].
#  * Globale Namen hier nicht doppelt zu mgr-*.rsc vergeben: Der Manager importiert
#    diese Datei ebenfalls und überschreibt damit gleichnamige Manager-Befehle.
#  * Weitere Eigenheiten (Dateiendungen, Vergleiche): docs/DECISIONS.md
# ============================================================

# Verwaltete Menüs in Abhängigkeitsreihenfolge (GC läuft rückwärts)
:global cfmMenus {
  "/interface/bonding";"/interface/bridge";"/interface/bridge/port";"/interface/vlan";"/interface/bridge/vlan";
  "/interface/vrrp";"/interface/list";"/interface/list/member";
  "/ip/address";"/routing/table";"/ip/route";"/ip/pool";"/ip/dhcp-server";"/ip/dhcp-server/network";
  "/ip/dhcp-server/lease";"/ip/dhcp-client";
  "/interface/bridge/filter";"/ip/firewall/address-list";"/ip/firewall/filter";"/ip/firewall/mangle";"/ip/firewall/nat";"/ipv6/firewall/filter";"/ip/dns/static";
  "/interface/wifi/channel";"/interface/wifi/security";"/interface/wifi/security/multi-passphrase";
  "/interface/wifi/datapath";
  "/interface/wifi/steering";"/interface/wifi/access-list";"/interface/wifi/configuration";"/interface/wifi/provisioning";
  "/system/logging/action";"/system/logging";"/user/group";"/user";
  "/system/script";"/system/scheduler";"/tool/netwatch"
}

# Probelauf: cfmDry=true (setzt der Agent), Meldungen landen dann in cfmPlanOut statt im Log
:global cfmDry
:global cfmPlanOut
# Soll-Objekte anzeigen ($cfmShow objects=yes, D61): im Probelauf zusätzlich cfmShowAll=true - jedes
# Objekt, das $cfmEnsure/$cfmBlock/$cfmSet verlangt, landet (Werte gekürzt) in cfmShowOut
:global cfmShowAll
:global cfmShowOut
:global cfmShowObj do={
  :global cfmShowOut; :global cfmShort
  :local s ""
  :foreach kk,vv in=$p do={ :if ($kk != "comment") do={ :set s ($s . " " . $kk . "=" . [$cfmShort $vv]) } }
  :if ([:len $s] > 200) do={ :set s ([:pick $s 0 200] . " …") }
  :set cfmShowOut ($cfmShowOut . $m . " " . $k . ":" . $s . "\n")
}
:global cfmLog do={
  :global cfmDry; :global cfmPlanOut
  :if ($cfmDry = true) do={ :set cfmPlanOut ($cfmPlanOut . $1 . "\n") } else={ :log info ("cfm: " . $1) }
}
:global cfmWarn do={
  :global cfmDry; :global cfmPlanOut
  :if ($cfmDry = true) do={ :set cfmPlanOut ($cfmPlanOut . "WARNUNG " . $1 . "\n") } else={ :log warning ("cfm: " . $1) }
}

# Wert für die Probelauf-Ausgabe kürzen: Skript-Quelltexte (z.B. neue Manager-Module) sprengten
# sonst plan.txt – /file/set scheitert mit "maximum message size exceeded"
:global cfmShort do={
  :local v [:tostr $1]
  :if ([:len $v] > 120) do={ :return ([:pick $v 0 80] . "... (" . [:len $v] . " Zeichen)") }
  :return $v
}

# Kommando auf Menüpfad ausführen. $1="/menu/verb", P=Props-Array, I=Item-ID
# Werte werden als Variablen übergeben -> kein Quoting/Escaping nötig.
:global cfmRun do={
  # Probelauf: nichts ändern, nur lesen
  :global cfmDry
  :if ($cfmDry = true and $1 ~ "/(add|set|remove)\$") do={ :return "*dry" }
  :local c ""
  :if ([:typeof $P] = "array") do={
    :foreach k,v in=$P do={ :set c ($c . " " . $k . "=(\$P->\"" . $k . "\")") }
  }
  :local code (":return [" . $1)
  :if ([:typeof $I] != "nothing") do={ :set code ($code . " \$I") }
  :set code ($code . $c . "]")
  :local f
  :onerror e in={ :set f [:parse $code] } do={ :error ($e . " IN: " . $code) }
  :local r
  :onerror e in={ :set r [$f P=$P I=$I] } do={ :error ($e . " IN: " . $code . " P=" . [:pick [:tostr $P] 0 200]) }
  :return $r
}

# IDs per natürlichem Schlüssel finden. $1=Menü, N={"prop"=wert;...}
# !dynamic ist Pflicht: dynamische Objekte (z.B. vom Switch-Chip gelernte
# /interface/bridge/vlan-Einträge, sobald viele Ports gleichzeitig eine neue PVID
# bekommen) darf $cfmEnsure nie übernehmen - ein "set" darauf scheitert mit
# RouterOS-Fehler "can not change dynamic".
:global cfmIds do={
  :local w ""
  :foreach k,v in=$N do={ :set w ($w . " and " . $k . "=(\$N->\"" . $k . "\")") }
  :local code (":return [" . $1 . "/find where !dynamic" . $w . "]")
  :local f
  :onerror e in={ :set f [:parse $code] } do={ :error ($e . " IN: " . $code) }
  :return [$f N=$N]
}

# Ist-Wert ($1) und Soll-Wert ($2) typgerecht vergleichen
:global cfmSame do={
  :local t [:typeof $1]
  :if ($t = "bool") do={
    :local d false
    :if ([:typeof $2] = "bool") do={ :set d $2 } else={ :set d ($2 = "yes" or $2 = "true") }
    :return ($1 = $d)
  }
  :if ($t = "time" and [:len $2] > 0) do={ :return ($1 = [:totime $2]) }
  :if ($t = "num" and [:len $2] > 0) do={ :return ($1 = [:tonum $2]) }
  :if ($t = "array" or [:typeof $2] = "array" or ([:typeof $2] = "str" and $2 ~ ",")) do={
    # als Mengen vergleichen; negierte Einträge ("!local" bei Policies) ignorieren
    :local a ({}); :local b ({})
    :foreach e in=[:toarray $1] do={ :if ([:pick [:tostr $e] 0 1] != "!") do={ :set ($a->[:tostr $e]) 1 } }
    :foreach e in=[:toarray $2] do={ :if ([:pick [:tostr $e] 0 1] != "!") do={ :set ($b->[:tostr $e]) 1 } }
    :return ([:tostr $a] = [:tostr $b])
  }
  :local a [:tostr $1]
  :local b [:tostr $2]
  # Hostadresse: Adresslisten und Firewall-Regeln speichern x.x.x.x/32 (IPv6 /128) ohne Präfix
  :if ($a != $b and [:typeof [:find $a "/"]] = "nil" and $b ~ "/(32|128)\$") do={ :set b [:pick $b 0 [:find $b "/"]] }
  # Zahl als Text: RouterOS liefert z.B. die Bridge-Priorität als "0xe000" - "0xE000" oder 57344 im
  # Hostfile sind derselbe Wert (TODO 27)
  :local nre "^(0[xX][0-9a-fA-F]+|[0-9]+)\$"
  :if ($a != $b and $a ~ $nre and $b ~ $nre) do={ :return ([:tonum $a] = [:tonum $b]) }
  # Dauer als Text: manche Menüs (z.B. /interface/wifi/steering transition-time) liefern "1m30s" für "90s"
  :local tre "^([0-9]+[wdhms])+\$"
  :if ($a != $b and $a ~ $tre and $b ~ $tre) do={ :return ([:totime $a] = [:totime $b]) }
  :return ($a = $b)
}

# MAC-Adresse in Großbuchstaben: RouterOS meldet sie so, $cfmSame vergleicht Text (sonst erschiene
# eine klein geschriebene MAC aus leases.rsc bei jedem Apply als Änderung, vgl. TODO 27)
:global cfmMacUp do={
  :local r ""
  :local s [:tostr $1]
  :for i from=0 to=([:len $s] - 1) do={
    :local c [:pick $s $i]
    :local p [:find "abcdef" $c]
    :if ([:typeof $p] = "num") do={ :set c [:pick "ABCDEF" $p] }
    :set r ($r . $c)
  }
  :return $r
}

# Mitglieder einer Menge {key=1|0} als Liste
:global cfmKeys do={
  :local r ({})
  :foreach k,v in=$1 do={ :if ($v = 1) do={ :set ($r->[:len $r]) $k } }
  :return $r
}

# Rolle aktiv? ($1 = Rollenname, bezogen auf das aktuelle Manifest)
:global cfmHas do={
  :global cfmMf
  :return ((("," . ($cfmMf->"role") . ",") ~ ("," . $1 . ",")) or ($1 = "base"))
}

# Ist dieses Gerät CAPsMAN? (D45) Rolle capsman oder im Manifest-Feld cm genannt – das setzt der
# Manager: alle Geräte mit Rolle capsman, ohne solche übergangsweise der Primary-Manager. Fehlt cm
# (Manifest von einem Manager vor D45), gilt die alte Regel: Rolle manager = CAPsMAN.
:global cfmIsCapsman do={
  :global cfmMf
  :local rl ("," . [:tostr ($cfmMf->"role")] . ",")
  :if ($rl ~ ",capsman,") do={ :return true }
  :if ([:typeof ($cfmMf->"cm")] != "array") do={ :return ($rl ~ ",manager,") }
  :local r false
  :foreach c in=($cfmMf->"cm") do={ :if ([:tostr ($c->"n")] = [:tostr ($cfmMf->"name")]) do={ :set r true } }
  :return $r
}

# Index "key -> id" aller cfm-getaggten Objekte eines Menüs (einmal pro Lauf)
:global cfmIndex do={
  :global cfmIdx; :global cfmSeen; :global cfmMenus; :global cfmDry
  :if ([:typeof ($cfmIdx->$1)] = "array") do={ :return true }
  # doppelt getaggte Objekte entfernen (im Probelauf nur überspringen: D=true)
  :local code (":local r ({}); :foreach i in=[" . $1 . "/find where comment~\"^cfm:\"] do={ :local c [:tostr [" . $1 . "/get \$i comment]]; :local s [:find \$c \" \"]; :if ([:typeof \$s] = \"nil\") do={ :set s [:len \$c] }; :local k [:pick \$c 4 \$s]; :if ([:typeof (\$r->\$k)] = \"nothing\") do={ :set (\$r->\$k) \$i } else={ :if (!\$D) do={ " . $1 . "/remove \$i } } }; :return \$r")
  :local f
  :onerror e in={ :set f [:parse $code] } do={ :error ($e . " IN(index): " . $code) }
  :set ($cfmIdx->$1) [$f D=($cfmDry = true)]
  :set ($cfmSeen->$1) ({})
  :if ([:typeof [:find $cfmMenus $1]] = "nil") do={ :set cfmMenus ($cfmMenus, $1) }
  :return true
}

# Neuen Lauf beginnen: Indizes aller bekannten Menüs aufbauen, Zähler nullen
:global cfmBegin do={
  :global cfmIdx; :global cfmSeen; :global cfmStat; :global cfmMenus; :global cfmIndex
  :set cfmIdx ({}); :set cfmSeen ({})
  :set cfmStat {"add"=0;"set"=0;"rem"=0;"skip"=0}
  :foreach m in=$cfmMenus do={ :onerror e in={ $cfmIndex $m } do={} }
  :return true
}

# Objekt sicherstellen.
#  m=Menü  k=Schlüssel (-> comment "cfm:<k>")  p=Soll-Props
#  n=natürlicher Schlüssel zum Übernehmen vorhandener Objekte (optional)
#  a=Props nur beim Anlegen (optional)  x=Kommentar-Zusatztext (optional)
:global cfmEnsure do={
  :global cfmIndex; :global cfmIdx; :global cfmSeen; :global cfmRun; :global cfmIds
  :global cfmSame; :global cfmStat; :global cfmLog; :global cfmDry; :global cfmShort
  $cfmIndex $m
  :local tag ("cfm:" . $k)
  :if ([:len $x] > 0) do={ :set tag ($tag . " " . $x) }
  :set ($cfmSeen->$m->$k) 1
  :global cfmShowAll
  :if ($cfmShowAll = true) do={ :global cfmShowObj; $cfmShowObj m=$m k=$k p=$p }
  :local id ($cfmIdx->$m->$k)
  :if ([:typeof $id] = "nothing" and [:typeof $n] = "array") do={
    :local ids [$cfmIds $m N=$n]
    :if ([:len $ids] > 0) do={
      :local cid [:pick $ids 0]
      :local cur [$cfmRun ($m . "/get") I=$cid]
      :if ([:tostr ($cur->"comment")] ~ "^cfm-override") do={
        :set ($cfmStat->"skip") (($cfmStat->"skip") + 1)
        $cfmLog ("override respektiert: " . $m . " " . $k)
        :return $cid
      }
      :set id $cid
      # trug es bisher einen anderen cfm-Schlüssel (z.B. umbenannte Lease), den alten aus dem Index nehmen -
      # sonst entfernt $cfmPrune am Ende dasselbe Objekt als verwaist
      :local oc [:tostr ($cur->"comment")]
      :if ($oc ~ "^cfm:") do={
        :local os [:find $oc " "]
        :if ([:typeof $os] = "nil") do={ :set os [:len $oc] }
        :local ok [:pick $oc 4 $os]
        :if ($ok != $k and ($cfmIdx->$m->$ok) = $cid) do={ :set ($cfmIdx->$m->$ok) }
      }
      $cfmLog ("übernommen: " . $m . " " . $k)
    }
  }
  :if ([:typeof $id] = "nothing") do={
    :local pp $p
    :if ([:typeof $a] = "array") do={ :foreach kk,vv in=$a do={ :set ($pp->$kk) $vv } }
    :set ($pp->"comment") $tag
    :set id [$cfmRun ($m . "/add") P=$pp]
    :set ($cfmIdx->$m->$k) $id
    :set ($cfmStat->"add") (($cfmStat->"add") + 1)
    $cfmLog ("neu: " . $m . " " . $k)
    :return $id
  }
  :local cur [$cfmRun ($m . "/get") I=$id]
  :local ch ({})
  :foreach kk,vv in=$p do={ :if (![$cfmSame ($cur->$kk) $vv]) do={ :set ($ch->$kk) $vv } }
  :if ([:tostr ($cur->"comment")] != $tag) do={ :set ($ch->"comment") $tag }
  :if ([:len $ch] > 0) do={
    $cfmRun ($m . "/set") I=$id P=$ch
    :set ($cfmStat->"set") (($cfmStat->"set") + 1)
    :local s ""
    :foreach kk,vv in=$ch do={ :set s ($s . " " . $kk); :if ($cfmDry = true) do={ :set s ($s . "=" . [$cfmShort $vv]) } }
    $cfmLog ("geändert: " . $m . " " . $k . ":" . $s)
  }
  :set ($cfmIdx->$m->$k) $id
  :return $id
}

# Props setzen ohne Tagging: Singleton-Menü (ohne n) oder alle Treffer von n.
# Für eingebaute Objekte (Identity, DNS, IP-Services, Ethernet-Ports, ...)
:global cfmSet do={
  :global cfmRun; :global cfmIds; :global cfmSame; :global cfmStat; :global cfmLog; :global cfmDry; :global cfmShort
  :global cfmShowAll
  :if ($cfmShowAll = true) do={
    :global cfmShowObj
    :local sk "(set)"
    :if ([:typeof $n] = "array") do={ :set sk ("(set " . [:tostr $n] . ")") }
    $cfmShowObj m=$m k=$sk p=$p
  }
  :local ids ({"-"})
  :if ([:typeof $n] = "array") do={ :set ids [$cfmIds $m N=$n] }
  :foreach id in=$ids do={
    :local cur
    :if ([:typeof $id] = "str") do={ :set cur [$cfmRun ($m . "/get")] } else={ :set cur [$cfmRun ($m . "/get") I=$id] }
    :local ch ({})
    :foreach kk,vv in=$p do={ :if (![$cfmSame ($cur->$kk) $vv]) do={ :set ($ch->$kk) $vv } }
    :if ([:len $ch] > 0) do={
      :if ([:typeof $id] = "str") do={ $cfmRun ($m . "/set") P=$ch } else={ $cfmRun ($m . "/set") I=$id P=$ch }
      :set ($cfmStat->"set") (($cfmStat->"set") + 1)
      :local s ""
      :foreach kk,vv in=$ch do={ :set s ($s . " " . $kk); :if ($cfmDry = true) do={ :set s ($s . "=" . [$cfmShort $vv]) } }
      $cfmLog ("gesetzt: " . $m . ":" . $s)
    }
  }
  :return [:len $ids]
}

# Reihenfolge-sensitiver Regelblock (Firewall, NAT, Provisioning).
#  m=Menü k=Block-Schlüssel l=Liste von Props-Arrays (Reihenfolge = Priorität)
# Unveränderte Signatur -> nichts tun. Sonst neuen Block VOR dem alten
# einfügen und danach den alten löschen (nie ein Moment ohne Regeln).
:global cfmBlock do={
  :global cfmIndex; :global cfmIdx; :global cfmSeen; :global cfmRun; :global cfmStat; :global cfmLog
  :global cfmShowAll
  :if ($cfmShowAll = true) do={
    :global cfmShowObj
    :local j 0
    :foreach r in=$l do={ $cfmShowObj m=$m k=($k . ":" . [:pick [:tostr (100 + $j)] 1 3]) p=$r; :set j ($j + 1) }
  }
  $cfmIndex $m
  :local sig [:convert [:tostr $l] transform=md5 to=hex]
  :local pre ($k . ":")
  :local old ({})
  :local oldSig ""
  :foreach kk,id in=($cfmIdx->$m) do={
    :if ([:pick $kk 0 [:len $pre]] = $pre) do={
      :set ($old->$kk) $id
      :if ($kk = ($pre . "00")) do={
        :local c [:tostr ([$cfmRun ($m . "/get") I=$id]->"comment")]
        :local s [:find $c "sig="]
        :if ([:typeof $s] != "nil") do={ :set oldSig [:pick $c ($s + 4) [:len $c]] }
      }
    }
  }
  :if (([:len $old] = [:len $l] and $oldSig = $sig) or ([:len $old] = 0 and [:len $l] = 0)) do={
    :foreach kk,id in=$old do={ :set ($cfmSeen->$m->$kk) 1 }
    :return false
  }
  :local before
  :if ([:len $old] > 0) do={ :set before ($old->($pre . "00")) } else={
    :local all ({})
    :onerror e in={ :local ff [:parse (":return [" . $m . "/find where !dynamic]")]; :set all [$ff] } do={
      :local ff [:parse (":return [" . $m . "/find]")]; :set all [$ff] }
    :if ([:len $all] > 0) do={ :set before [:pick $all 0] }
  }
  :local j 0
  :foreach r in=$l do={
    :local key ($pre . [:pick [:tostr (100 + $j)] 1 3])
    :local pp $r
    :set ($pp->"comment") ("cfm:" . $key)
    :if ($j = 0) do={ :set ($pp->"comment") ("cfm:" . $key . " sig=" . $sig) }
    :if ([:typeof $before] != "nothing") do={ :set ($pp->"place-before") $before }
    :if ([:typeof ($pp->"disabled")] = "nothing") do={ :set ($pp->"disabled") "no" }
    :local nid [$cfmRun ($m . "/add") P=$pp]
    :set ($cfmIdx->$m->$key) $nid
    :set ($cfmSeen->$m->$key) 1
    :set j ($j + 1)
  }
  :foreach kk,id in=$old do={
    $cfmRun ($m . "/remove") I=$id
    :if ([:typeof ($cfmSeen->$m->$kk)] = "nothing") do={ :set ($cfmIdx->$m->$kk) }
  }
  :set ($cfmStat->"add") (($cfmStat->"add") + [:len $l])
  :set ($cfmStat->"rem") (($cfmStat->"rem") + [:len $old])
  $cfmLog ("Regelblock " . $m . " " . $k . " neu aufgebaut (" . [:len $l] . " Einträge)")
  :return true
}

# Verwaiste cfm-Objekte entfernen (alle bekannten Menüs, rückwärts)
:global cfmPrune do={
  :global cfmMenus; :global cfmIdx; :global cfmSeen; :global cfmRun; :global cfmStat
  :global cfmLog; :global cfmWarn
  :for i from=([:len $cfmMenus] - 1) to=0 step=-1 do={
    :local m [:pick $cfmMenus $i]
    :if ([:typeof ($cfmIdx->$m)] = "array") do={
      :foreach k,id in=($cfmIdx->$m) do={
        :if ([:typeof ($cfmSeen->$m->$k)] = "nothing") do={
          :onerror e in={
            $cfmRun ($m . "/remove") I=$id
            :set ($cfmStat->"rem") (($cfmStat->"rem") + 1)
            $cfmLog ("entfernt: " . $m . " " . $k)
          } do={ $cfmWarn ("entfernen fehlgeschlagen: " . $m . " " . $k . ": " . $e) }
        }
      }
    }
  }
  :return true
}

# ---------- Daten-Helfer für Rollen ----------

# Adressdaten eines VLANs: {"net";"addr";"pfx";"gw"} (leer, wenn kein Subnetz)
:global cfmNet do={
  :global cfmVlans
  :local v ($cfmVlans->[:tostr $1])
  :local net [:tostr ($v->"net")]
  :if ([:len $net] = 0) do={
    :if ([:tonum $1] > 255) do={ :return ({}) }
    :set net ("192.168." . $1 . ".0/24")
  }
  :local s [:find $net "/"]
  :local a [:toip [:pick $net 0 $s]]
  :local g ($v->"gw")
  :if ([:len $g] = 0) do={ :set g 1 }
  :return {"net"=$net;"addr"=$a;"pfx"=[:pick $net ($s + 1) [:len $net]];"gw"=($a + [:tonum $g])}
}

# Policy-Ziel zerlegen (D38): "*wan" = mit masquerade, "wan@192.0.2.5" = src-nat auf feste Adresse,
# "wan" = geroutet ohne NAT -> {"t"=Ziel;"nat"=""|"masq"|Adresse|"invalid" (beides angegeben)}
:global cfmTarget do={
  :local t [:tostr $1]
  :local nat ""
  :if ([:len $t] > 1 and [:pick $t 0 1] = "*") do={ :set nat "masq"; :set t [:pick $t 1 [:len $t]] }
  :local at [:find $t "@"]
  :if ([:typeof $at] != "nil") do={
    :if ($nat = "masq") do={ :set nat "invalid" } else={ :set nat [:pick $t ($at + 1) [:len $t]] }
    :set t [:pick $t 0 $at]
  }
  :return {"t"=$t;"nat"=$nat}
}

# VLAN-Menge aus Spezifikation ("*", Zonen, VIDs, "!x" = ohne) -> {vid=1|0}
:global cfmVids do={
  :global cfmVlans
  :local r ({})
  :foreach t in=[:toarray $1] do={
    :local val 1
    :if ([:pick $t 0 1] = "!") do={ :set val 0; :set t [:pick $t 1 [:len $t]] }
    :foreach vid,v in=$cfmVlans do={
      :if ($t = "*" or $t = $vid or $t = ($v->"zone")) do={ :set ($r->$vid) $val }
    }
  }
  :return $r
}

# Port-Profil auflösen: "name[:arg]" -> {"tag";"untag";"bridge";"edge";"disabled";"frame"}
:global cfmProfile do={
  :global cfmProfiles; :global cfmVids
  :local name $1; :local arg ""
  :local s [:find $1 ":"]
  :if ([:typeof $s] != "nil") do={ :set name [:pick $1 0 $s]; :set arg [:pick $1 ($s + 1) [:len $1]] }
  :local pr ($cfmProfiles->$name)
  :if ([:typeof $pr] != "array") do={ :error ("unbekanntes Port-Profil: " . $1) }
  :local u [:tostr ($pr->"untag")]
  :if ($u = "arg") do={ :set u $arg }
  :local tg ({})
  :if ([:len ($pr->"tag")] > 0) do={ :set tg [$cfmVids ($pr->"tag")] }
  :if ([:len $u] > 0) do={ :set ($tg->$u) 0 }
  :local fr "admit-all"
  :if ([:len $u] = 0) do={ :set fr "admit-only-vlan-tagged" }
  :if ([:len $u] > 0 and [:len ($pr->"tag")] = 0) do={ :set fr "admit-only-untagged-and-priority-tagged" }
  :local br ([:tostr ($pr->"bridge")] != "no")
  :local dis ([:tostr ($pr->"disabled")] = "yes")
  :local ed [:tostr ($pr->"edge")]
  :if ([:len $ed] = 0) do={ :set ed "auto" }
  :return {"tag"=$tg;"untag"=$u;"bridge"=$br;"edge"=$ed;"disabled"=$dis;"frame"=$fr}
}

# Eintrag einer Freigabeliste (global.rsc allow, D39) zerlegen: "ziel" oder "ziel:tcp/443,8883" (Ports je
# Eintrag, D76) -> {"h"=Ziel;"p"=Protokoll|"";"d"=Ports|"";"l"=Adressliste}. $1 = Listenname, $2 = Eintrag.
# Einträge ohne Ports bleiben in cfm-allow-<Liste>, mit Ports je Kombination eine eigene Liste
:global cfmAllowEntry do={
  :local e [:tostr $2]
  :local r ({"h"=$e;"p"="";"d"="";"l"=("cfm-allow-" . $1)})
  :local c -1
  :for i from=0 to=([:len $e] - 1) do={ :if ([:pick $e $i] = ":") do={ :set c $i } }
  :if ($c > 0) do={
    :local sp [:pick $e ($c + 1) [:len $e]]
    :if ($sp ~ "^(tcp|udp)/[0-9][0-9,-]*\$") do={
      :local sl [:find $sp "/"]
      :local pr [:pick $sp 0 $sl]
      :local pt [:pick $sp ($sl + 1) [:len $sp]]
      :local tag ""
      :for i from=0 to=([:len $pt] - 1) do={ :local ch [:pick $pt $i]; :if ($ch = ",") do={ :set ch "_" }; :set tag ($tag . $ch) }
      :set r ({"h"=[:pick $e 0 $c];"p"=$pr;"d"=$pt;"l"=("cfm-allow-" . $1 . "-" . $pr . $tag)})
    }
  }
  :return $r
}

# MLAG-Paar eines Geräts ($1 = Name) aus mlag.rsc (D75): ({}) oder {"pair";"partner";"primary" (bool);
# "peer" (Name des Peer-Bonds);"peerSlaves";"stp";"fallback";"initDelay";"bonds"={Name={"id";"slaves";"profile"}}}.
# Ports: Text = auf beiden Knoten gleich, Array = je Knoten ({"sw1"="ether1";"sw2"="ether3"})
:global cfmMlagOf do={
  :global cfmMlag
  :local r ({})
  :local pk do={ :if ([:typeof $1] = "array") do={ :return [:tostr ($1->$2)] }; :return [:tostr $1] }
  :if ([:typeof $cfmMlag] != "array") do={ :return $r }
  :foreach pn,p in=$cfmMlag do={
    :local nodes [:toarray ($p->"nodes")]
    :if ([:typeof [:find $nodes $1]] != "nil") do={
      :local other ""
      :foreach n in=$nodes do={ :if ($n != $1) do={ :set other $n } }
      :local bs ({})
      :foreach bn,b in=($p->"bonds") do={ :set ($bs->$bn) ({"id"=[:tonum ($b->"id")];"slaves"=[$pk ($b->"ports") $1];"profile"=[:tostr ($b->"profile")]}) }
      :set r ({"pair"=$pn;"partner"=$other;"primary"=([:tostr ($p->"primary")] = $1);"peer"=("peer-" . $pn);"peerSlaves"=[$pk ($p->"peer") $1];"stp"=[:tostr ($p->"stpPrio")];"fallback"=[:tostr ($p->"lacpFallback")];"initDelay"=[:tostr ($p->"initDelay")];"bonds"=$bs})
    }
  }
  :return $r
}

# ---------- Audit: von Hand angelegte Objekte ----------
# op=report|mark|purge  sel="all" oder "A1,A7"  -> Report-Text
# Eigener Name, nicht $cfmAudit: Den Manager-Befehl gleichen Namens (mgr-core) würde jeder Import
# dieser Datei überschreiben, und $cfmLoadData importiert sie bei fast jedem Manager-Befehl.
:global cfmAuditDev do={
  :global cfmMenus; :global cfmRun; :global cfmLog
  :local sa ({})
  :foreach s in=[:toarray $sel] do={ :set ($sa->$s) 1 }
  :local all ($sel = "all")
  :local out ""; :local n 0
  :local skipNames {"read"=1;"write"=1;"full"=1}
  # von base verwaltet, aber ohne cfm-Tag: Syslog-Einträge (hAP lehnt dort "comment" ab) und der
  # Werks-User admin (abgeschaltet oder bewusst behalten, D25) - keine Fehlalarme
  :local skipLog "cfmremote"
  :foreach m in=$cfmMenus do={
    :onerror e in={
      :local ff [:parse (":return [" . $m . "/find]")]
      :foreach id in=[$ff] do={
        :local g [$cfmRun ($m . "/get") I=$id]
        :local c [:tostr ($g->"comment")]
        :if (!($c ~ "^cfm") and ($g->"dynamic") != true and ($g->"default") != true and ($g->"builtin") != true and !($m = "/user/group" and ($skipNames->($g->"name")) = 1) and !($m = "/system/logging" and [:tostr ($g->"action")] = $skipLog) and !($m = "/user" and ($g->"name") = "admin")) do={
          :set n ($n + 1)
          :local ref ("A" . $n)
          :local sum ""
          :foreach key in={"name";"chain";"action";"address";"interface";"bridge";"vlan-ids";"dst-address";"gateway";"list";"ssid";"host";"src-address";"out-interface"} do={
            :if ([:len ($g->$key)] > 0) do={ :set sum ($sum . " " . $key . "=" . [:tostr ($g->$key)]) }
          }
          :local act ""
          :if (($op = "mark" or $op = "purge") and ($all or ($sa->$ref) = 1)) do={
            :onerror e2 in={
              :if ($op = "mark") do={
                :local pc {"comment"=("cfm-override " . $c)}
                $cfmRun ($m . "/set") I=$id P=$pc
                :set act " -> override"
              } else={
                $cfmRun ($m . "/remove") I=$id
                :set act " -> entfernt"
              }
            } do={ :set act (" -> FEHLER " . $e2) }
            $cfmLog ("audit " . $op . " " . $ref . " " . $m . $sum)
          }
          :set out ($out . $ref . " " . $m . $sum . $act . "\n")
        }
      }
    } do={}
  }
  :return ($out . "# " . $n . " unverwaltete Objekte (ohne cfm-Tag/override)\n")
}
