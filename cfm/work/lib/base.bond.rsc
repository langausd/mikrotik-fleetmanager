# ============================================================
# cfm lib/base.bond.rsc – Feature-Modul der Rolle base (DG4.6): Bonds (DP2.1) und MLAG (DP2.2). base lädt es per
# $cfmFeat nur mit bonds im Hostfile oder als Knoten eines Paars in mlag.rsc. Bonds, die es nicht mehr geben
# soll, entfernt base selbst vorher (auch ohne Modul); MLAG an der Bridge setzt base am Ende.
#  Hostfile bonds={"bond1"={"slaves"="sfp1,sfp2";"mode"="802.3ad"|"active-backup";"hash"=…;"primary"=…}},
#  das Profil steht wie bei jedem Port unter ports ("bond1"="trunk"). Ist das Gerät Knoten eines Paars
#  in mlag.rsc, kommen der Peer-Bond peer-<Paar> (alle VLANs getaggt) und die MLAG-Bonds (mlag-id,
#  Profil aus mlag.rsc) dazu. Die Slaves verlassen die Bridge: Unten bei den Ports wären sie sonst belegt.
# Von der Rolle: cfmCtx->"ml" = MLAG-Paar dieses Geräts ($cfmMlagOf); zurück: cfmCtx->"slv" = {Slave=Bond},
# cfmCtx->"bspec" = {Bond=Port-Profil} der MLAG-Bonds
# ============================================================
:global cfmHost; :global cfmCtx; :global cfmIdx; :global cfmDry
:global cfmEnsure; :global cfmSet; :global cfmLog; :global cfmIds; :global cfmRun
:local ml ($cfmCtx->"ml")
:local bonds ({})
:local bspec ({})
:foreach bn,b in=($cfmHost->"bonds") do={
  :local md [:tostr ($b->"mode")]
  :if ([:len $md] = 0) do={ :set md "802.3ad" }
  :local hs [:tostr ($b->"hash")]
  :if ([:len $hs] = 0) do={ :set hs "layer-2-and-3" }
  :local bp ({"name"=$bn;"slaves"=[:toarray ($b->"slaves")];"mode"=$md;"lacp-rate"="1sec";"transmit-hash-policy"=$hs})
  :if ([:len [:tostr ($b->"primary")]] > 0) do={ :set ($bp->"primary") [:tostr ($b->"primary")] }
  :set ($bonds->$bn) $bp
}
:if ([:len $ml] > 0) do={
  :set ($bonds->($ml->"peer")) ({"name"=($ml->"peer");"slaves"=[:toarray ($ml->"peerSlaves")];"mode"="802.3ad";"lacp-rate"="1sec";"transmit-hash-policy"="layer-2-and-3"})
  :set ($bspec->($ml->"peer")) "*mlag-peer"
  :foreach bn,b in=($ml->"bonds") do={
    :set ($bonds->$bn) ({"name"=$bn;"slaves"=[:toarray ($b->"slaves")];"mode"="802.3ad";"lacp-rate"="1sec";"transmit-hash-policy"="layer-2-and-3";"mlag-id"=($b->"id")})
    :set ($bspec->$bn) ($b->"profile")
  }
}
:local slv ({})
:foreach bn,b in=$bonds do={ :foreach x in=($b->"slaves") do={ :set ($slv->[:tostr $x]) $bn } }
:foreach x,bn in=$slv do={
  :foreach pid in=[/interface/bridge/port/find where interface=$x and !dynamic] do={
    :if ($cfmDry != true) do={ /interface/bridge/port/remove $pid }
    $cfmLog ("Port " . $x . " aus der Bridge genommen (Slave von " . $bn . ")")
  }
  :set ($cfmIdx->"/interface/bridge/port"->("bp:" . $x))
  :if ([:len [/interface/ethernet/find where name=$x]] > 0) do={ $cfmSet m="/interface/ethernet" n=({"name"=$x}) p=({"disabled"="no"}) }
}
:foreach bn,b in=$bonds do={ $cfmEnsure m="/interface/bonding" k=("bond:" . $bn) n=({"name"=$bn}) p=$b }
# MLAG verträgt kein L3-Hardware-Offloading (MikroTik-Doku): wie bei der Rolle router (DR1.2) aus
:if ([:len $ml] > 0) do={
  :local sws ({})
  :onerror e in={ :set sws [$cfmIds "/interface/ethernet/switch" N=({})] } do={ :set sws ({}) }
  :foreach sw in=$sws do={
    :local sc [$cfmRun "/interface/ethernet/switch/get" I=$sw]
    :if ([:typeof ($sc->"l3-hw-offloading")] != "nothing") do={ $cfmSet m="/interface/ethernet/switch" n=({"name"=($sc->"name")}) p=({"l3-hw-offloading"="no"}) }
  }
}
:set ($cfmCtx->"slv") $slv
:set ($cfmCtx->"bspec") $bspec
