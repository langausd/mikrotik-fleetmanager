# ============================================================
# cfm lib/base.tls.rsc – Feature-Modul der Rolle base (DG4.6): Zertifikate einer öffentlichen CA (DS3.6, TODO 25)
# Lädt der Agent bei jedem Lauf (nicht nur beim Apply), wenn das Manifest "tls" enthält:
#   :set st [$cfmTls tls=($mf->"tls") st=$st key=<Geräteschlüssel> mgr=<Manager>]
# tls = {"cn"=<name>.<domain>;"f"=<Pfad am Manager>;"h"=<SHA-512 des bereitliegenden Zertifikats>;"r"=<Tage>;"s"=<Dienste>}
#  1. Liegt ein neues Zertifikat bereit (h), laden, Hash prüfen, Kette und dann den Schlüssel (tls.key) importieren.
#     Nur wenn der Import ein Zertifikat für cn MIT privatem Schlüssel ergibt, geht es an die Dienste und heißt
#     cfm-tls; die Kette heißt cfm-tls-ca-<skid>. Sonst wird der Import verworfen, das alte bleibt aktiv.
#  2. Fehlt ein gültiges Zertifikat für cn oder gilt es weniger als r Tage: neuen Schlüssel und CSR erzeugen
#     (Passphrase = Geräteschlüssel). Der CSR liegt in <cfm>/out/tls.csr, der Manager holt ihn mit dem Status;
#     der verschlüsselte Schlüssel bleibt bis zum Import in <cfm>/tls.key auf dem Gerät.
# Status für den Manager: st->"tls" = {"cn";"d"=Resttage (-1 = keins);"st"=ok|csr|err;"e"=Fehler}, st->"csr" = MD5 des CSR.
# ============================================================
:global cfmTls do={
  :global cfmFetch; :global cfmWrite; :global cfmDir
  :local d $cfmDir
  :local s $st
  :local cn [:tostr ($tls->"cn")]
  :local rn [:tonum ($tls->"r")]
  :if ([:typeof $rn] != "num" or $rn < 1) do={ :set rn 30 }
  :local err ""
  # neuer Schlüssel nötig (der vorhandene passt nicht oder fehlt)
  :local renew false
  # Passphrase für den Schlüssel: der Geräteschlüssel (nur hier bekannt), gekürzt
  :local pw [:pick $key 0 32]
  :local fex do={ :local r false; :onerror e in={ :set r ([:len [/file/get $1 name]] > 0) } do={}; :return $r }

  # --- 1. bereitliegendes Zertifikat übernehmen ---
  :local h [:tostr ($tls->"h")]
  :if ([:len $h] > 0 and $h != [:tostr ($s->"tlsh")]) do={
    :set ($s->"tlsh") $h
    :if (![$fex ($d . "/tls.key")]) do={
      :set err "Zertifikat bereit, aber kein Schluessel (tls.key) - neuer CSR"
      :set renew true
    } else={
      :local cf ($d . "/tls.crt")
      :local got ""
      :if ([$cfmFetch r=($tls->"f") l=$cf prefer=$mgr] != "") do={
        :delay 300ms
        :onerror e in={ :set got [/file/get $cf contents] } do={}
      }
      :if ([:convert $got transform=sha512 to=hex] != $h) do={
        :set err "Zertifikat nicht geladen oder Hash falsch"
        :set ($s->"tlsh")
        :onerror e in={ /file/remove $cf } do={}
      } else={
        :local before ({})
        :foreach i in=[/certificate/find] do={ :set ($before->[:tostr $i]) 1 }
        :onerror e in={
          /certificate/import file-name=$cf passphrase=""
          /certificate/import file-name=($d . "/tls.key") passphrase=$pw
        } do={ :set err ("Import: " . $e) }
        :local leaf ""
        :local news ({})
        :foreach i in=[/certificate/find] do={
          :if ([:typeof ($before->[:tostr $i])] = "nothing") do={
            :set ($news->[:len $news]) $i
            :local g [/certificate/get $i]
            :if ([:tostr ($g->"common-name")] = $cn and ($g->"private-key") = true) do={ :set leaf $i }
          }
        }
        :if ([:len [:tostr $leaf]] = 0) do={
          :if ([:len $err] = 0) do={ :set err "Zertifikat passt nicht zum Schluessel oder Namen - verworfen" }
          :set renew true
          :foreach i in=$news do={ :onerror e in={ /certificate/remove $i } do={} }
        } else={
          # an die Dienste, dann das alte weg und umbenennen (der Dienst verweist auf die ID)
          :foreach sv in=($tls->"s") do={
            :onerror e in={ /ip/service/set [find where name=$sv and !dynamic] certificate=$leaf } do={}
          }
          /certificate/remove [find where name="cfm-tls"]
          /certificate/set $leaf name="cfm-tls" trusted=no
          :local la [:tostr [/certificate/get $leaf akid]]
          :foreach i in=$news do={
            :if ($i != $leaf) do={
              :local sk [:tostr [/certificate/get $i skid]]
              :local nm ("cfm-tls-ca-" . [:pick $sk 0 8])
              :if ([:len [/certificate/find where name=$nm]] > 0) do={ /certificate/remove $i } else={ /certificate/set $i name=$nm trusted=no }
            }
          }
          # Kette früherer Zertifikate: nur behalten, was das neue (oder dessen Zwischenzertifikat) braucht
          :local keep ({})
          :foreach i in=[/certificate/find where name~"^cfm-tls-ca-"] do={
            :if ([:tostr [/certificate/get $i skid]] = $la) do={
              :set ($keep->[:tostr $i]) 1
              :local a2 [:tostr [/certificate/get $i akid]]
              :foreach j in=[/certificate/find where name~"^cfm-tls-ca-"] do={ :if ([:tostr [/certificate/get $j skid]] = $a2) do={ :set ($keep->[:tostr $j]) 1 } }
            }
          }
          :foreach i in=[/certificate/find where name~"^cfm-tls-ca-"] do={ :if ([:typeof ($keep->[:tostr $i])] = "nothing") do={ /certificate/remove $i } }
          :log info ("cfm: TLS-Zertifikat fuer " . $cn . " uebernommen (gueltig bis " . [:tostr [/certificate/get $leaf invalid-after]] . ")")
          :onerror e in={ /file/remove ($d . "/out/tls.csr") } do={}
          :set ($s->"csr")
        }
        :onerror e in={ /file/remove $cf } do={}
        :onerror e in={ /file/remove ($d . "/tls.key") } do={}
      }
    }
  }

  # --- 2. Zustand des aktuellen Zertifikats ---
  :local left -1
  :local cur [/certificate/find where name="cfm-tls"]
  :if ([:len $cur] > 0) do={
    :local g [/certificate/get ($cur->0)]
    :if ([:tostr ($g->"common-name")] = $cn and ($g->"private-key") = true) do={
      :set left 0
      :onerror e in={ :set left ([:tonsec ($g->"expires-after")] / 86400000000000) } do={}
      :if ($left < 0) do={ :set left 0 }
    }
  }

  # --- 3. CSR, wenn nötig ---
  :if ($left < $rn) do={
    :local have ([$fex ($d . "/out/tls.csr")] and [$fex ($d . "/tls.key")] and [:tostr ($s->"tlscn")] = $cn and !$renew)
    :if (!$have) do={
      :onerror e in={
        /certificate/remove [find where name="cfm-tls-req"]
        :foreach f in={"certificate-request.pem";"certificate-request_key.pem"} do={ :onerror e2 in={ /file/remove $f } do={} }
        /certificate/add name="cfm-tls-req" common-name=$cn subject-alt-name=("DNS:" . $cn) key-size=2048 key-usage=digital-signature,key-encipherment,tls-server days-valid=90
        /certificate/create-certificate-request template="cfm-tls-req" key-passphrase=$pw
        :local w 0
        :while ($w < 20 and !([$fex "certificate-request.pem"] and [$fex "certificate-request_key.pem"])) do={ :delay 500ms; :set w ($w + 1) }
        :delay 500ms
        :local csr [/file/get "certificate-request.pem" contents]
        :local kc [/file/get "certificate-request_key.pem" contents]
        :if ([:len $csr] < 100 or [:len $kc] < 100) do={ :error "CSR oder Schluessel leer" }
        $cfmWrite ($d . "/tls.key") $kc
        $cfmWrite ($d . "/out/tls.csr") $csr
        :set ($s->"csr") [:convert $csr transform=md5 to=hex]
        :set ($s->"tlscn") $cn
        :log info ("cfm: TLS - neuer Schluessel und CSR fuer " . $cn)
      } do={ :set err ("CSR: " . $e) }
      /certificate/remove [find where name="cfm-tls-req"]
      :foreach f in={"certificate-request.pem";"certificate-request_key.pem"} do={ :onerror e2 in={ /file/remove $f } do={} }
    }
  } else={
    :if ([:len [:tostr ($s->"csr")]] > 0) do={
      :onerror e in={ /file/remove ($d . "/out/tls.csr") } do={}
      :set ($s->"csr")
    }
  }
  :local stt "ok"
  :if ($left < $rn) do={ :set stt "csr" }
  :if ([:len $err] > 0) do={ :set stt "err"; :log warning ("cfm: TLS " . $cn . ": " . $err) }
  :set ($s->"tls") ({"cn"=$cn;"d"=$left;"st"=$stt;"e"=$err})
  :return $s
}
