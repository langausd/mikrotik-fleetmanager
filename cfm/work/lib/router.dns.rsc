# ============================================================
# cfm lib/router.dns.rsc – Feature-Modul der Rolle router (D104): DNS aus dns.rsc (D101) und
# DNS-Selbstbedienung für Clients (D102). router.rsc lädt es per $cfmFeat nur mit dns.rsc; Upstreams, Cache,
# den Forwarder cfm-upstream und den Abbau ohne dns.rsc erledigt die Rolle selbst.
# Von der Rolle: cfmCtx->"dup" = Upstreams (dns.rsc servers, sonst wan.dns)
# ============================================================
:global cfmG; :global cfmDns; :global cfmDl; :global cfmCtx; :global cfmDry
:global cfmEnsure; :global cfmWarn
:local dup ($cfmCtx->"dup")

# Adlisten (hosts-Format, Aktualisierung alle 4 h durch RouterOS); Zertifikat gegen den eingebauten Speicher.
# ssl-verify bleibt beim Standard yes: RouterOS meldet es nur als no zurück, gesetzt wäre es bei jedem Lauf neu
:foreach u in=($cfmDns->"adlists") do={
  $cfmEnsure m="/ip/dns/adlist" k=("dnsal:" . $u) n=({"url"=$u}) p=({"url"=$u})
}
# Ausnahmen und Weiterleitungen sind FWD-Einträge mit match-subdomain (die Domain samt Subdomains). Ausnahmen
# gehen an den Forwarder cfm-upstream mit allen Upstreams (legt die Rolle an) - so trägt ein Ausfall des ersten
# sie nicht mit
:if ([:len $dup] > 0) do={
  :foreach a in=($cfmDns->"allow") do={
    $cfmEnsure m="/ip/dns/static" k=("dnsallow:" . $a) n=({"name"=$a;"type"="FWD"}) p=({"name"=$a;"type"="FWD";"forward-to"="cfm-upstream";"match-subdomain"="yes"})
  }
}
:foreach fd,fs in=($cfmDns->"forward") do={
  # Ziel: eine Adresse oder eine Liste (RouterOS: durch Komma getrennt)
  :local ft ""
  :foreach s in=[:toarray $fs] do={ :if ([:len $ft] > 0) do={ :set ft ($ft . ",") }; :set ft ($ft . [:tostr $s]) }
  $cfmEnsure m="/ip/dns/static" k=("dnsfwd:" . $fd) n=({"name"=$fd;"type"="FWD"}) p=({"name"=$fd;"type"="FWD";"forward-to"=$ft;"match-subdomain"="yes"})
}

# Abfrage-Log je Client: Topic dns ohne packet ("query from <Client>: #n <Name>" / "done query: #n … <Antwort>").
# log.memory = Zeilen im RAM-Puffer cfmdns (0/leer = aus), log.syslog = "yes" zusätzlich an den Syslog-Server
# (cfmremote aus base). Regeln ohne comment wie in base; topics kommen als Liste zurück
:local dlr do={
  :local r ({})
  :foreach i in=[/system/logging/find where action=$1] do={ :if ([:tostr [/system/logging/get $i topics]] = "dns;!packet") do={ :set ($r->[:len $r]) $i } }
  :return $r
}
:local dlm [:tonum ($cfmDns->"log"->"memory")]
:if ([:typeof $dlm] = "num" and $dlm > 0) do={
  $cfmEnsure m="/system/logging/action" k="log:dns" n=({"name"="cfmdns"}) p=({"name"="cfmdns";"target"="memory";"memory-lines"=[:tostr $dlm]})
  :if ([:len [$dlr "cfmdns"]] = 0 and $cfmDry != true) do={ /system/logging/add action="cfmdns" topics="dns,!packet" }
} else={
  # Regel vor der Aktion entfernen (die Aktion räumt die GC weg, eine Regel ohne Aktion bliebe ungültig stehen)
  :if ([:len [/system/logging/action/find where name="cfmdns"]] > 0 and $cfmDry != true) do={ /system/logging/remove [find where action="cfmdns"] }
}
:if ([:len [/system/logging/action/find where name="cfmremote"]] > 0) do={
  :local drs [$dlr "cfmremote"]
  :if ([:tostr ($cfmDns->"log"->"syslog")] = "yes") do={
    :if ([:len $drs] = 0 and $cfmDry != true) do={ /system/logging/add action="cfmremote" topics="dns,!packet" }
  } else={
    :if ([:len $drs] > 0 and $cfmDry != true) do={ :foreach i in=$drs do={ /system/logging/remove $i } }
  }
}

# DNS-Selbstbedienung (D102, dns.rsc self): Clients aus self.zones sehen im Lesezeichen cfm-DNS (WebFig des
# Gateways, User self.user der Gruppe cfm-dns: read,api,rest-api - ohne password) ihre Abfragen und schalten eine
# gesperrte Domain für self.hours frei. Anfrage = Log-Eintrag "cfm-dnsreq: <Domain> <IP>" per /execute, danach
# /system/script/run cfm-dnsreq (dont-require-permissions: der User selbst darf nichts schreiben; ein :global aus
# /execute käme im Skript nicht an). Den Rumpf des Skripts liefert lib/router.dnsreq.rsc, davor stehen die
# Einstellungen als Locals. Der Scheduler (1 min) räumt abgelaufene Einträge weg und holt verpasste Anfragen nach.
# dnsui:perm (vom Admin im Lesezeichen) bleibt stehen, bis es in allow steht. Die WebFig-Freigabe aus den Zonen
# setzen base (Dienst www) und router.rsc (Firewall)
:local dself ($cfmDns->"self")
:if ([:typeof $dself] = "array" and [:len ($dself->"zones")] > 0 and [:len $dup] > 0) do={
  :local su [:tostr ($dself->"user")]
  :if ([:len $su] = 0) do={ :set su "dns" }
  :local sh [:tonum ($dself->"hours")]
  :if ([:typeof $sh] != "num" or $sh < 1) do={ :set sh 2 }
  # Werte landen im Skripttext: Anführungszeichen, Backslash und $ fallen weg ($cfmCheck prüft die Namen)
  :local san do={ :local o ""; :for i from=0 to=([:len $1] - 1) do={ :local ch [:pick $1 $i]; :if ($ch != "\"" and $ch != "\\" and $ch != "\$") do={ :set o ($o . $ch) } }; :return $o }
  :local dl ""
  :foreach x in=($dself->"deny") do={ :if ([:len $dl] > 0) do={ :set dl ($dl . ";") }; :set dl ($dl . "\"" . [$san [:tostr $x]] . "\"") }
  :local site [:tostr ($cfmG->"notify"->"site")]
  :if ([:len $site] = 0) do={ :set site [:tostr ($cfmG->"domain")] }
  :local body ""
  :onerror e in={ :set body [/file/get ($cfmDl . "/lib/router.dnsreq.rsc") contents] } do={}
  :if ([:len $body] = 0) do={ :error "lib/router.dnsreq.rsc fehlt im Manifest (D104)" }
  :local src "# cfm (Rolle router, D102): DNS-Selbstbedienung - Anfragen aus dem Log freischalten, Ablauf aufraeumen. Jeder Apply schreibt es neu\n"
  :set src ($src . ":local dur " . ($sh * 3600) . "\n:local deny ({" . $dl . "})\n")
  :set src ($src . ":local nu \"" . [$san [:tostr ($cfmG->"notify"->"url")]] . "\"\n:local site \"" . [$san $site] . "\"\n")
  :set src ($src . $body . "\n\$dnsreq dur=\$dur deny=\$deny nu=\$nu site=\$site\n")
  $cfmEnsure m="/user/group" k="grp:dns" n=({"name"="cfm-dns"}) p=({"name"="cfm-dns";"policy"="read,api,rest-api"})
  # Passwort per Secret-Push aus dem Vault (user.<self.user>), bis dahin abgeschaltet
  $cfmEnsure m="/user" k=("user:" . $su) n=({"name"=$su}) p=({"name"=$su;"group"="cfm-dns"}) a=({"password"=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"];"disabled"="yes"})
  $cfmEnsure m="/system/script" k="sys:dnsreq" n=({"name"="cfm-dnsreq"}) p=({"name"="cfm-dnsreq";"source"=$src;"policy"="read,write,test";"dont-require-permissions"="yes"})
  $cfmEnsure m="/system/scheduler" k="sys:dnsreq" n=({"name"="cfm-dnsreq"}) p=({"name"="cfm-dnsreq";"interval"="1m";"start-time"="startup";"on-event"="/system/script/run cfm-dnsreq";"policy"="read,write,test"})
  :local pm ""
  :foreach i in=[/ip/dns/static/find where comment~"^dnsui:perm"] do={ :set pm ($pm . " " . [/ip/dns/static/get $i name]) }
  :if ([:len $pm] > 0) do={ $cfmWarn ("dauerhafte Freischaltungen aus der DNS-Selbstbedienung (dnsui:perm) nach dns.rsc allow uebernehmen:" . $pm) }
} else={
  # ohne Selbstbedienung: User, Gruppe, Skript und Scheduler räumt die GC weg; befristete Freischaltungen
  # liefen sonst nie ab
  :if ($cfmDry != true) do={ /ip/dns/static/remove [find where comment~"^dnsui:tmp:"] }
}
