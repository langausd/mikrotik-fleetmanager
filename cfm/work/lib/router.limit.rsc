# ============================================================
# cfm lib/router.limit.rsc – Feature-Modul der Rolle router (D104); router.rsc lädt es per $cfmFeat nur, wenn ein
# VLAN limit oder limitClient trägt. Ohne räumt die GC Queues und Queue-Typen weg.
# Bandbreitenlimit je VLAN (D97): "limit" für das ganze Netz, "limitClient" je Client (Download/Upload aus
# Sicht der Clients). Eine Simple Queue je VLAN mit dem Netz als target (aller Verkehr des Netzes); PCQ
# teilt unter den Clients gleich auf, mit limitClient über eigene Queue-Typen mit pcq-rate (ohne comment,
# Schlüssel = Name). max-limit liest RouterOS als Upload/Download und in eigener Schreibweise zurück.
# Fasttrack umgeht die Queues: Zurück an die Rolle geht cfmCtx->"limNets" (Netze mit Limit), ihr Firewall-Block
# nimmt sie vom Fasttrack aus
# ============================================================
:global cfmVlans; :global cfmCtx
:global cfmEnsure; :global cfmNet; :global cfmLimit
# bit/s in der Schreibweise, die RouterOS zurückliest (größte Einheit, die glatt teilt: 1500000 = "1500k")
:local rateFmt do={
  :local n [:tonum $1]
  :if ($n = 0) do={ :return "0" }
  :foreach de in={{1000000000000;"T"};{1000000000;"G"};{1000000;"M"};{1000;"k"}} do={
    :if ($n % ($de->0) = 0) do={ :return ([:tostr ($n / ($de->0))] . ($de->1)) }
  }
  :return [:tostr $n]
}
:local limNets ({})
:foreach vid,v in=$cfmVlans do={
  :local lt [$cfmLimit ($v->"limit")]
  :local lc [$cfmLimit ($v->"limitClient")]
  :local nn [$cfmNet $vid]
  :if ([:tostr ($v->"l3")] != "no" and [:len ($nn->"net")] > 0 and ([:typeof $lt] = "array" or [:typeof $lc] = "array")) do={
    :local qd "pcq-download-default"
    :local qu "pcq-upload-default"
    :if ([:typeof $lc] = "array") do={
      :set qd ("cfm-pcq" . $vid . "-down")
      :set qu ("cfm-pcq" . $vid . "-up")
      $cfmEnsure m="/queue/type" k=$qd p=({"name"=$qd;"kind"="pcq";"pcq-classifier"="dst-address";"pcq-rate"=($lc->"d")})
      $cfmEnsure m="/queue/type" k=$qu p=({"name"=$qu;"kind"="pcq";"pcq-classifier"="src-address";"pcq-rate"=($lc->"u")})
    }
    :local ml "0/0"
    :if ([:typeof $lt] = "array") do={ :set ml ([$rateFmt ($lt->"u")] . "/" . [$rateFmt ($lt->"d")]) }
    :local qn ("vlan" . $vid)
    $cfmEnsure m="/queue/simple" k=("q:" . $vid) n=({"name"=$qn}) p=({"name"=$qn;"target"=($nn->"net");"max-limit"=$ml;"queue"=($qu . "/" . $qd)}) x=($v->"name")
    :set ($limNets->[:len $limNets]) ($nn->"net")
  }
}
:set ($cfmCtx->"limNets") $limNets
