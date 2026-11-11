# ============================================================
# cfm lib/router.ddns.rsc – Rumpf des Skripts cfm-ddns (Rolle router, DynDNS DR4.4, DG4.6): Update nach dem
# dyndns2-Protokoll. Kein Import: roles/router.rsc setzt davor ":local url/name/ipUrl/wgV/dns" und dahinter den
# Aufruf. Als Funktion, damit die Datei auch allein :parse besteht ($cfmRelease).
#  url    Update-URL des Anbieters ohne hostname/myip (z.B. https://update.dedyn.io/nic/update)
#  name   der eigene DynDNS-Name       ipUrl  liefert die eigene öffentliche Adresse (Standard https://api.ipify.org)
#  wgV    WAN-VLAN bei VRRP (leer = Einzelrouter: immer)   dns  Upstream für die Kontrolle des Namens
# Ablauf je Lauf (Scheduler, Standard alle 5 min): nur als Master des WAN-VLANs; eigene Adresse per ipUrl holen;
# den Namen über den Upstream auflösen (nicht über den eigenen DNS: Cache, Weiterleitungen); nur bei Abweichung oder
# einmal täglich GET url?hostname=<name>&myip=<ip> mit HTTP-Basic "user:passwort" aus /ppp/secret cfm:ddns (Vault
# ddns.auth, Secret-Push). Antwort good/nochg = ok, sonst Warnung. Merker im RAM (cfmDdnsT/cfmDdnsIp): nach einem
# Neustart sendet das Skript einmal. Kein :return in :onerror (RouterOS-Eigenheit) - Ergebnis über Flags.
# ============================================================
:local ddns do={
  :global cfmDdnsT; :global cfmDdnsIp
  :local go true
  :if ([:len $wgV] > 0) do={
    :set go false
    :local vi [/interface/vrrp/find where name=("vrrp" . $wgV)]
    :if ([:len $vi] > 0) do={ :if ([:tostr [/interface/vrrp/get [:pick $vi 0] running]] = "true") do={ :set go true } }
  }
  :local cred ""
  :if ($go) do={
    :onerror e in={ :set cred [/ppp/secret/get [find where name="cfm:ddns"] password] } do={}
    :if ([:len $cred] = 0) do={ :log warning "cfm-ddns: kein Zugang (Vault ddns.auth, \$cfmSecretPush)"; :set go false }
  }
  :local ip ""
  :if ($go) do={
    :local raw ""
    :onerror e in={ :set raw [:tostr ([/tool/fetch url=$ipUrl output=user as-value]->"data")] } do={ :log warning ("cfm-ddns: eigene Adresse nicht ermittelt (" . $ipUrl . "): " . $e) }
    :if ([:len $raw] > 0) do={ :for i from=0 to=([:len $raw] - 1) do={ :local ch [:pick $raw $i]; :if ($ch ~ "[0-9.]") do={ :set ip ($ip . $ch) } } }
    :if ([:typeof [:toip $ip]] != "ip") do={ :if ([:len $raw] > 0) do={ :log warning ("cfm-ddns: keine IPv4-Adresse von " . $ipUrl) }; :set go false }
  }
  :local ok false
  :if ($go) do={
    :local cur ""
    :onerror e in={ :if ([:len $dns] > 0) do={ :set cur [:tostr [:resolve domain-name=$name server=$dns]] } else={ :set cur [:tostr [:resolve domain-name=$name]] } } do={}
    :local now ([:tonsec [:timestamp]] / 1000000000)
    :local day true
    :if ([:typeof $cfmDdnsT] = "num") do={ :if (($now - $cfmDdnsT) < 86400 and $now >= $cfmDdnsT) do={ :set day false } }
    :if ($cur = $ip and [:tostr $cfmDdnsIp] = $ip and !$day) do={ :set ok true } else={
      :local u $cred; :local p ""
      :local c [:find $cred ":"]
      :if ([:typeof $c] != "nil") do={ :set u [:pick $cred 0 $c]; :set p [:pick $cred ($c + 1) [:len $cred]] }
      :local sep "?"
      :if ([:typeof [:find $url "?"]] != "nil") do={ :set sep "&" }
      :local full ($url . $sep . "hostname=" . $name . "&myip=" . $ip)
      :local ans ""
      :onerror e in={ :set ans [:tostr ([/tool/fetch url=$full user=$u password=$p output=user as-value http-header-field="User-Agent: cfm-ddns/1"]->"data")] } do={ :log warning ("cfm-ddns: Update " . $name . " fehlgeschlagen: " . $e); :set ans "" }
      :set ans [:pick $ans 0 40]
      :if ($ans ~ "^(good|nochg)") do={
        :set cfmDdnsT $now; :set cfmDdnsIp $ip; :set ok true
        :if ($cur != $ip) do={ :log info ("cfm-ddns: " . $name . " -> " . $ip . " (" . $ans . ")") }
      } else={ :if ([:len $ans] > 0) do={ :log warning ("cfm-ddns: Anbieter antwortet \"" . $ans . "\" fuer " . $name) } }
    }
  }
  :return $ok
}
