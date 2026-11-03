# ============================================================
# cfm lib/base.snmp.rsc – Feature-Modul der Rolle base (DG4.6): SNMPv3 nur lesend für LibreNMS (TODO 54, DU4.3)
# base lädt es per $cfmFeat nur mit snmp.from in global.rsc. authPriv, nur von snmp.from (die MGMT-Adresse
# des Servers; der input-Block lässt das MGMT-Netz ohnehin durch). Passwörter NUR im Vault (snmp.auth,
# snmp.priv), per Secret-Push; bis dahin Zufallswerte. Die Standard-Community public (v1/v2c ohne Passwort, von
# überall) lässt sich nicht löschen, sie wird abgeschaltet. Ohne snmp räumt die GC die Community weg, /snmp
# selbst bleibt unangetastet.
# ============================================================
:global cfmG; :global cfmHost; :global cfmDry
:global cfmEnsure; :global cfmSet; :global cfmLog
:local snmp ($cfmG->"snmp")
:local su [:tostr ($snmp->"user")]
:if ([:len $su] = 0) do={ :set su "librenms" }
:local sa [:tostr ($snmp->"auth")]
:if ([:len $sa] = 0) do={ :set sa "SHA256" }
# RouterOS liest Hostadressen als x.x.x.x/32 zurück
:local sf ({})
:foreach a in=($snmp->"from") do={
  :local x [:tostr $a]
  :if ([:typeof [:find $x "/"]] = "nil") do={ :set x ($x . "/32") }
  :set ($sf->[:len $sf]) $x
}
:local loc [:tostr ($cfmHost->"location")]
:if ([:len $loc] = 0) do={ :set loc [:tostr ($snmp->"location")] }
:local rc "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
# Neu angelegt (erster Rollout, anderer user) trägt sie Zufallspasswörter: Secret-Push anfordern (SV 0)
:if ([:len [/snmp/community/find where name=$su]] = 0 and $cfmDry != true) do={
  :onerror e in={ /ppp/secret/set [find where name="cfm:key"] comment="cfm-sys:key sv=0" } do={}
  $cfmLog ("SNMP-Community " . $su . " neu - Secret-Push angefordert")
}
$cfmEnsure m="/snmp/community" k=("snmp:" . $su) n=({"name"=$su}) p=({"name"=$su;"addresses"=$sf;"security"="private";"authentication-protocol"=$sa;"encryption-protocol"="AES";"read-access"="yes";"write-access"="no"}) a=({"authentication-password"=[:rndstr length=32 from=$rc];"encryption-password"=[:rndstr length=32 from=$rc]})
$cfmSet m="/snmp/community" n=({"default"=true}) p=({"disabled"="yes"})
$cfmSet m="/snmp" p=({"enabled"="yes";"contact"=[:tostr ($snmp->"contact")];"location"=$loc})
