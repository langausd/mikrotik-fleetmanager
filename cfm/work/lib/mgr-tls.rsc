# ============================================================
# cfm lib/mgr-tls.rsc – Zertifikate einer öffentlichen CA für die Geräte (DS3.6, TODO 25)
# Ablauf (global.rsc tls): Jedes Gerät erzeugt Schlüssel und CSR selbst (lib/base.tls.rsc); $cfmCollect holt den
# CSR nach state/<name>/tls.csr. Ein Signer (tools/cert-signer/) liest die CSRs per SSH als User cfm-cert (nur
# ssh,read), lässt sie signieren und startet das Skript cfm-cert-pull. Das ruft $cfmTlsPull: Zertifikate von
# <tls.signer>/<name>.<domain>.pem holen, unter live/c/<serial>.pem ablegen, Manifeste neu schreiben (Feld "tls"
# mit dem Hash), betroffene Geräte anstoßen. Das Gerät nimmt ein Zertifikat nur, wenn es zu seinem Schlüssel passt.
#   $cfmTlsPull [host=<Gerät>] [all=yes]   holen (ohne all nur für Geräte mit offenem CSR)
#   $cfmTlsStatus                           Zustand je Gerät (Name, Resttage, offener CSR, Fehler)
# ============================================================

# Name im Zertifikat: <name klein>.<domain>
:global cfmTlsCn do={
  :global cfmLower; :global cfmG
  :return ([$cfmLower $1] . "." . [:tostr ($cfmG->"domain")])
}

:global cfmTlsPull do={
  :global cfmG; :global cfmInvLoad; :global cfmMB; :global cfmFileEx; :global cfmEnrolled; :global cfmWrite
  :global cfmManifests; :global cfmPush; :global cfmLoadData; :global cfmTlsCn; :global cfmHostName
  :local hn [$cfmHostName $host]; :local host $hn
  $cfmLoadData
  :local sg [:tostr ($cfmG->"tls"->"signer")]
  :if ([:len $sg] = 0) do={ :put "tls.signer ist leer (global.rsc) - nichts zu holen"; :return 0 }
  :while ([:pick $sg ([:len $sg] - 1) [:len $sg]] = "/") do={ :set sg [:pick $sg 0 ([:len $sg] - 1)] }
  :local b [$cfmMB]
  :if (![$cfmFileEx ($b . "/live/c")]) do={ :onerror e in={ /file/add name=($b . "/live/c") type=directory } do={} }
  :local ch ({})
  :local nn 0
  :foreach name,d in=[$cfmInvLoad] do={
    :if (([:len $host] = 0 or $host = $name) and [$cfmEnrolled $d]) do={
      :local sd ($b . "/state/" . $name)
      :if ($all = "yes" or [:len $host] > 0 or [$cfmFileEx ($sd . "/tls.csr")]) do={
        :set nn ($nn + 1)
        :local cn [$cfmTlsCn $name]
        :local tmp ($sd . "/tls.new")
        :local c ""
        :onerror e in={
          /tool/fetch url=($sg . "/" . $cn . ".pem") dst-path=$tmp as-value
          :delay 300ms
          :set c [/file/get $tmp contents]
        } do={ :put ("TLS " . $name . ": nichts vom Signer (" . $e . ")") }
        :onerror e in={ /file/remove $tmp } do={}
        :if ([:len $c] > 0 and !($c ~ "BEGIN CERTIFICATE")) do={ :put ("TLS " . $name . ": Antwort des Signers ist kein Zertifikat - verworfen"); :set c "" }
        :if ([:len $c] > 0) do={
          :local sfn ""
          :for i from=0 to=([:len ($d->"serial")] - 1) do={ :local x [:pick ($d->"serial") $i]; :if ($x = "/") do={ :set x "_" }; :set sfn ($sfn . $x) }
          :local lf ($b . "/live/c/" . $sfn . ".pem")
          :local old ""
          :if ([$cfmFileEx $lf]) do={ :onerror e in={ :set old [/file/get $lf contents] } do={} }
          :if ($old != $c) do={
            $cfmWrite $lf $c
            :set ($ch->$name) 1
            :put ("TLS " . $name . ": neues Zertifikat fuer " . $cn)
            :log info ("cfm: TLS - neues Zertifikat fuer " . $cn)
          } else={ :put ("TLS " . $name . ": unveraendert") }
        }
      }
    }
  }
  :if ([:len $ch] > 0) do={
    :put ("Manifeste: " . [$cfmManifests])
    :foreach n,x in=$ch do={ $cfmPush host=$n }
  }
  :if ($nn = 0) do={ :put "TLS: kein Geraet mit offenem CSR (all=yes holt fuer alle)" }
  :return [:len $ch]
}

:global cfmTlsStatus do={
  :global cfmInvLoad; :global cfmMB; :global cfmJson; :global cfmPad; :global cfmFileEx; :global cfmEnrolled
  :local b [$cfmMB]
  :put ([$cfmPad "Geraet" 12] . [$cfmPad "Name" 28] . [$cfmPad "Tage" 6] . [$cfmPad "Zustand" 9] . "CSR am Manager / Fehler")
  :foreach name,d in=[$cfmInvLoad] do={
    :if ([$cfmEnrolled $d]) do={
      :local t ([$cfmJson ($b . "/state/" . $name . "/status.dat")]->"tls")
      :local cs "-"
      :if ([$cfmFileEx ($b . "/state/" . $name . "/tls.csr")]) do={ :set cs "ja" }
      :if ([:typeof $t] = "array") do={
        :local dd [:tostr ($t->"d")]
        :if ($dd = "-1") do={ :set dd "-" }
        :put ([$cfmPad $name 12] . [$cfmPad [:tostr ($t->"cn")] 28] . [$cfmPad $dd 6] . [$cfmPad [:tostr ($t->"st")] 9] . $cs . " " . [:tostr ($t->"e")])
      } else={ :put ([$cfmPad $name 12] . "(kein TLS-Status - Agent ohne DS3.6 oder tls aus)") }
    }
  }
}

# Prüfung für $cfmCheck (w=<work-Verzeichnis>) -> {"err"=…;"warn"=…}
:global cfmCheckTls do={
  :global cfmG
  :local err ({}); :local warn ({})
  :local t ($cfmG->"tls")
  :if ([:typeof $t] = "nothing") do={ :return ({"err"=$err;"warn"=$warn}) }
  :if ([:typeof $t] != "array") do={ :set ($err->[:len $err]) "global.rsc: tls muss ein Array sein ({\"signer\"=…})"; :return ({"err"=$err;"warn"=$warn}) }
  :local sg [:tostr ($t->"signer")]
  :if ([:len $sg] = 0) do={
    :if ([:len $t] > 0) do={ :set ($warn->[:len $warn]) "global.rsc: tls ohne signer - Zertifikate sind aus" }
    :return ({"err"=$err;"warn"=$warn})
  }
  :if (!($sg ~ "^https?://")) do={ :set ($err->[:len $err]) ("global.rsc: tls signer " . $sg . " ist keine http(s)-URL") }
  :local dom [:tostr ($cfmG->"domain")]
  :if ([:len $dom] = 0 or !($dom ~ "[.]")) do={ :set ($warn->[:len $warn]) ("global.rsc: tls: domain " . $dom . " ist keine öffentliche Domain - eine öffentliche CA stellt dafür nichts aus") }
  :if ([:len ($t->"from")] = 0) do={ :set ($warn->[:len $warn]) "global.rsc: tls ohne from - der Signer kann die CSRs nicht lesen (kein User cfm-cert)" }
  :foreach a in=($t->"from") do={
    :local ip [:tostr $a]
    :if ([:typeof [:find $ip "/"]] != "nil") do={ :set ip [:pick $ip 0 [:find $ip "/"]] }
    :if ([:typeof [:toip $ip]] != "ip") do={ :set ($err->[:len $err]) ("global.rsc: tls from: " . $a . " ist keine IPv4-Adresse/kein Netz") }
  }
  :local sv ($t->"services")
  :if ([:typeof $sv] = "nothing") do={ :set sv {"www-ssl";"api-ssl"} }
  :foreach x in=$sv do={
    :if ($x != "www-ssl" and $x != "api-ssl") do={ :set ($err->[:len $err]) ("global.rsc: tls services: " . $x . " (nur www-ssl, api-ssl)") } else={
      :if ([:typeof ($cfmG->"services"->$x)] = "nothing") do={ :set ($warn->[:len $warn]) ("global.rsc: tls services nennt " . $x . ", services aber nicht - der Dienst bleibt aus") }
    }
  }
  :local ok false
  :onerror e in={ :set ok ([:len [/file/get ($w . "/authorized_keys.cfm-cert") name]] > 0) } do={}
  :if (!$ok and [:len ($t->"from")] > 0) do={ :set ($warn->[:len $warn]) "tls: authorized_keys.cfm-cert fehlt in work/ - der Signer kann sich nicht anmelden" }
  :return ({"err"=$err;"warn"=$warn})
}
