# cfm Onboarding Stufe 1 (Probe) – vom Manager als cfm-probe.auto.rsc hochgeladen und sofort
# ausgeführt. Meldet Seriennummer/Modell/Version in cfm-probe.txt, prüft den Update-Kanal und
# installiert ein Update (das Gerät startet dann neu und wird erneut geprüft).
# Platzhalter @GW@ (Gateway im Onboarding-VLAN) und @CH@ (Kanal) ersetzt der Manager.
:local s
:onerror e in={ :set s [/system routerboard get serial-number] } do={}
:if ([:len $s] = 0) do={ :onerror e in={ :set s [/system/license/get system-id] } do={} }
:if ([:len $s] = 0) do={ :onerror e in={ :set s [/system/license/get software-id] } do={} }
:local fl "no"
:if ([:len [/file/find where name="flash" and type="directory"]] > 0) do={ :set fl "yes" }
:if ([:len [/ip/route/find where dst-address="0.0.0.0/0"]] = 0) do={ :onerror e in={ /ip/route/add gateway="@GW@" comment="cfm-onboard" } do={} }
:onerror e in={ /ip/dns/set servers="@GW@" } do={}
:local up "none"
:onerror e in={
  /system/package/update/set channel="@CH@"
  /system/package/update/check-for-updates once as-value
  :delay 5s
  :local u [/system/package/update/get]
  :if ([:len [:tostr ($u->"latest-version")]] > 0 and ($u->"latest-version") != ($u->"installed-version")) do={ :set up ($u->"latest-version") }
  :if (($u->"status") ~ "ERROR") do={ :set up ("error " . ($u->"status")) }
} do={ :set up ("error " . $e) }
:onerror e in={ /file/remove [find where name="cfm-probe.txt"] } do={}
/file/add name=cfm-probe.txt contents=("serial=" . $s . "\nmodel=" . [/system/resource/get board-name] . "\nver=" . [/system/resource/get version] . "\nflash=" . $fl . "\nupdate=" . $up . "\n")
:if ($up ~ "^[0-9]") do={ :delay 2s; /system/package/update/install }
