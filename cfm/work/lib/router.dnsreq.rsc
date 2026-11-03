# ============================================================
# cfm lib/router.dnsreq.rsc – Rumpf des Skripts cfm-dnsreq (Rolle router, DNS-Selbstbedienung DN3.2)
# Kein Import: lib/router.dns.rsc setzt davor ":local dur/deny/nu/site" (cfm-dns.js liest dur und deny
# daraus) und dahinter den Aufruf. Als Funktion, damit die Datei auch allein :parse besteht ($cfmRelease).
#  dur   Dauer einer Freischaltung in s     deny  Domains, die nie freigeschaltet werden (samt Subdomains)
#  nu    notify.url (leer = keine Meldung)  site  Name des Standorts für die Meldung
# Anfrage = Log-Eintrag "cfm-dnsreq: <Domain> <IP>" (Lesezeichen cfm-DNS per /execute). Erledigt ist sie,
# sobald die eigene Log-Zeile mit req=<id> dasteht. Freischaltung = FWD an cfm-upstream mit Kommentar
# dnsui:tmp:<Ablauf> <IP> (die GC fasst nur cfm: an); Meldung ev=dnsreq an notify.url (DU4.1)
# ============================================================
:local dnsreq do={
  :if ([:len [/system/script/job/find where script="cfm-dnsreq"]] < 2) do={
    :local now ([:tonsec [:timestamp]] / 1000000000)
    :local ident [/system/identity/get name]
    # abgelaufene Freischaltungen entfernen
    :foreach i in=[/ip/dns/static/find where comment~"^dnsui:tmp:"] do={
      :local c [:tostr [/ip/dns/static/get $i comment]]
      :local p [:find $c " " 10]
      :if ([:typeof $p] != "num") do={ :set p [:len $c] }
      :if ([:tonum [:pick $c 10 $p]] <= $now) do={
        :log info ("cfm: DNS-Freischaltung abgelaufen: " . [/ip/dns/static/get $i name])
        /ip/dns/static/remove $i
      }
    }
    # neue Anfragen aus dem Log
    :foreach i in=[/log/find where buffer=memory and message~"^cfm-dnsreq: "] do={
      :local id [:tostr $i]
      :set id [:pick $id 1 [:len $id]]
      :if ([:len [/log/find where buffer=memory and message~("cfm: DNS-Freischaltung .* req=" . $id . "\$")]] = 0) do={
        :local m [:tostr [/log/get $i message]]
        :local r [:pick $m 12 [:len $m]]
        :local d $r
        :local ip ""
        :local sp [:find $r " "]
        :if ([:typeof $sp] = "num") do={ :set d [:pick $r 0 $sp]; :set ip [:pick $r ($sp + 1) [:len $r]] }
        :if ([:typeof [:toip $ip]] != "ip") do={ :set ip "" }
        :if ([:pick $d ([:len $d] - 1)] = ".") do={ :set d [:pick $d 0 ([:len $d] - 1)] }
        :local res "allowed"
        :if ([:len $d] > 253 or !($d ~ "^[a-z0-9_]([a-z0-9_-]*[a-z0-9])?(\\.[a-z0-9_]([a-z0-9_-]*[a-z0-9])?)+\$")) do={ :set res "invalid"; :set d "?" }
        :if ($res = "allowed") do={
          :foreach x in=$deny do={
            :local lx [:len $x]
            :if ($d = $x or ([:len $d] > $lx and [:pick $d ([:len $d] - $lx - 1) [:len $d]] = ("." . $x))) do={ :set res "denied" }
          }
        }
        :local until 0
        :if ($res = "allowed") do={
          :set until ($now + $dur)
          :local ex [/ip/dns/static/find where name=$d and type="FWD"]
          :if ([:len $ex] > 0) do={
            :local c [:tostr [/ip/dns/static/get [:pick $ex 0] comment]]
            :if ($c ~ "^dnsui:tmp:") do={
              /ip/dns/static/set [:pick $ex 0] comment=("dnsui:tmp:" . $until . " " . $ip)
              :set res "extended"
            } else={ :set res "exists"; :set until 0 }
          } else={
            /ip/dns/static/add name=$d type=FWD forward-to=cfm-upstream match-subdomain=yes comment=("dnsui:tmp:" . $until . " " . $ip)
          }
        }
        # Log nur in ASCII (DU3.4)
        :local msg ("DNS-Freischaltung " . $d)
        :if ($res = "allowed" or $res = "extended") do={ :set msg ($msg . " fuer " . ($dur / 3600) . " h") }
        :if ($res = "exists") do={ :set msg ($msg . ": schon frei") }
        :if ($res = "denied") do={ :set msg ($msg . " abgelehnt (self.deny)") }
        :if ($res = "invalid") do={ :set msg ($msg . " abgelehnt (kein gueltiger Name)") }
        :if ([:len $ip] > 0) do={ :set msg ($msg . ", Client " . $ip) }
        :log info ("cfm: " . $msg . " req=" . $id)
        :if ([:len $nu] > 0 and $res != "invalid") do={
          :local t ($site . ": " . $ident . " - " . $msg)
          # Felder wie die Meldungen des Managers (DU4.1), Reihenfolge fest
          :local j ("{\"site\":\"" . $site . "\",\"host\":\"" . $ident . "\",\"ev\":\"dnsreq\",\"state\":\"once\",\"msg\":\"" . $msg . "\",\"text\":\"" . $t . "\",\"time\":\"" . [/system/clock/get date] . " " . [/system/clock/get time] . "\",\"level\":\"action\",\"device\":\"" . $ident . "\",\"message\":\"" . $t . "\",\"key\":\"dnsreq:" . $d . "\",\"domain\":\"" . $d . "\",\"client\":\"" . $ip . "\",\"result\":\"" . $res . "\",\"until\":" . $until . "}")
          :onerror e in={ /tool/fetch url=$nu http-method=post http-header-field="Content-Type: application/json" http-data=$j output=none } do={ :log warning ("cfm: DNS-Freischaltung: Meldung nicht zugestellt: " . $e) }
        }
      }
    }
  }
}
