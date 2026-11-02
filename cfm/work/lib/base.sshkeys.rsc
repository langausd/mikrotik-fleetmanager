# ============================================================
# cfm lib/base.sshkeys.rsc – Feature-Modul der Rolle base (D104); base lädt es per $cfmFeat nur, wenn es für
# einen User aus users eine Datei authorized_keys.<user> gibt (das Manifest liefert es nur dann mit).
# Persönliche Admin-SSH-Keys je User (TODO 19, D65): work/authorized_keys.<user> im OpenSSH-Format,
# eine Zeile je Key "<typ> <base64> [kommentar]" (ssh-ed25519, ssh-rsa, sk-ssh-ed25519@openssh.com;
# keine OpenSSH-Optionen wie command=... davor; "#"-Zeilen und Leerzeilen zählen nicht).
# Gibt es die Datei für einen User aus global.rsc users, ist sie SEIN vollständiger Sollzustand:
# fehlende Keys legt base an, alle übrigen Keys dieses Users entfernt es (auch von Hand
# hinzugefügte). Entzug = Zeile löschen + $cfmRelease; alle Keys einer Person entziehen = Datei
# leeren (nur Kommentare) - eine gelöschte Datei lässt die Keys dagegen stehen: Ohne Datei bleiben
# die Keys eines Users unangetastet. Abgleich über den Fingerprint: Jeder Key wird angelegt
# (add key=, liefert fingerprint) und gleich wieder entfernt, wenn der User ihn schon hat - so gibt
# es nie einen Moment ohne Key. Scheitert ein Key, entfernt base für diesen User nichts (ein
# halber Sollzustand sperrt niemanden aus). Im Probelauf ist kein add möglich - Abgleich dort
# näherungsweise über den Kommentar (info). Das Passwort (Secret-Push) bleibt gesetzt, gilt mit Key
# aber nur noch für Winbox/WebFig: RouterOS lehnt SSH per Passwort ab, sobald der User einen Key
# hat (always-allow-password-login=no, TODO 29). Kein Ersatz für die ssh-keys der Rolle manager
# (cfm/cfmd-<name>) - die sind Maschinen-Identität, hier geht es um Menschen.
# ============================================================
:global cfmG; :global cfmDl; :global cfmDry; :global cfmStat
:global cfmLog; :global cfmWarn; :global cfmShowAll; :global cfmShowObj
:foreach u,grp in=($cfmG->"users") do={
  :local akf ($cfmDl . "/authorized_keys." . $u)
  # per Name statt /file/find (D59, auf dem Manager Hunderte Dateien); eine gelöschte Datei liefert
  # /file/get u.U. weiter als Eintrag ohne Namen
  :local akx false
  :onerror e in={ :set akx ([:len [/file/get $akf name]] > 0) } do={}
  :if ($akx and [:len [/user/find where name=$u]] > 0) do={
    :local lines ({})
    :local t ([/file/get $akf contents] . "\n")
    :while ([:len $t] > 0) do={
      :local p [:find $t "\n"]
      :local l [:pick $t 0 $p]
      :set t [:pick $t ($p + 1) [:len $t]]
      :if ([:len $l] > 0 and [:pick $l ([:len $l] - 1) [:len $l]] = "\r") do={ :set l [:pick $l 0 ([:len $l] - 1)] }
      :if ([:len $l] > 0 and [:pick $l 0 1] != "#") do={ :set ($lines->[:len $lines]) $l }
    }
    :if ($cfmShowAll = true) do={ $cfmShowObj m="/user/ssh-keys" k=("ak:" . $u) p=({"user"=$u;"keys"=[:len $lines]}) }
    :if ($cfmDry = true) do={
      # Kommentar = alles nach dem zweiten Feld; RouterOS legt ihn als info ab
      :local want ({})
      :foreach ln in=$lines do={
        :local c ""
        :local p1 [:find $ln " "]
        :if ([:typeof $p1] = "num") do={
          :local r [:pick $ln ($p1 + 1) [:len $ln]]
          :local p2 [:find $r " "]
          :if ([:typeof $p2] = "num") do={ :set c [:pick $r ($p2 + 1) [:len $r]] }
        }
        :set ($want->("i" . $c)) 1
      }
      :local have ({})
      :local nr 0
      :foreach id in=[/user/ssh-keys/find where user=$u] do={
        :local c ("i" . [:tostr [/user/ssh-keys/get $id info]])
        :set ($have->$c) 1
        :if ([:typeof ($want->$c)] = "nothing") do={ :set nr ($nr + 1) }
      }
      :local na 0
      :foreach c,x in=$want do={ :if ([:typeof ($have->$c)] = "nothing") do={ :set na ($na + 1) } }
      :if (($na + $nr) > 0) do={ $cfmLog ("Admin-SSH-Keys " . $u . ": " . $na . " neu, " . $nr . " entfernt (Abgleich im Probelauf ueber den Kommentar)") }
    } else={
      # vorhandene Keys nach Fingerprint; doppelte gleich entfernen
      :local have ({})
      :foreach id in=[/user/ssh-keys/find where user=$u] do={
        :local fp ("f" . [:tostr [/user/ssh-keys/get $id fingerprint]])
        :if ([:typeof ($have->$fp)] = "nothing") do={ :set ($have->$fp) $id } else={
          /user/ssh-keys/remove $id
          :set ($cfmStat->"rem") (($cfmStat->"rem") + 1)
          $cfmLog ("entfernt: /user/ssh-keys " . $u . " (doppelt)")
        }
      }
      :local keep ({})
      :local fail 0
      :local i 0
      :foreach ln in=$lines do={
        :set i ($i + 1)
        :onerror e in={
          :local nid [/user/ssh-keys/add user=$u key=$ln]
          :local fp ("f" . [:tostr [/user/ssh-keys/get $nid fingerprint]])
          :if ([:typeof ($have->$fp)] != "nothing" or [:typeof ($keep->$fp)] != "nothing") do={
            /user/ssh-keys/remove $nid
          } else={
            :set ($cfmStat->"add") (($cfmStat->"add") + 1)
            $cfmLog ("neu: /user/ssh-keys " . $u . " " . [:tostr [/user/ssh-keys/get $nid info]])
          }
          :set ($keep->$fp) 1
        } do={
          :set fail ($fail + 1)
          $cfmWarn ("authorized_keys." . $u . ": Key " . $i . " nicht angelegt: " . $e)
        }
      }
      :if ($fail > 0) do={
        $cfmWarn ("authorized_keys." . $u . ": " . $fail . " Key(s) fehlgeschlagen - vorhandene Keys bleiben stehen")
      } else={
        :foreach fp,id in=$have do={
          :if ([:typeof ($keep->$fp)] = "nothing") do={
            :local inf [:tostr [/user/ssh-keys/get $id info]]
            /user/ssh-keys/remove $id
            :set ($cfmStat->"rem") (($cfmStat->"rem") + 1)
            $cfmLog ("entfernt: /user/ssh-keys " . $u . " " . $inf)
          }
        }
      }
    }
  }
}
