# ============================================================
# cfm lib/base.portsw.rsc – Rumpf der Skripte cfm-port-<name>-normal/-alt/-toggle (umschaltbarer Port, DP1.4)
# Kein Import: roles/base.rsc setzt davor die Locals und dahinter den Aufruf (wie lib/capsman.ssid.rsc). Als
# Funktion, damit die Datei allein :parse besteht ($cfmRelease).
#  st  "normal" | "alt" | "toggle"   nm  Name aus portSwitch (a-z0-9)   p  Port   br  Bridge
#  sf  Zustandsdatei <cfm>/port-<name>.txt   hw  Bridge-Ports kennen "hw" (Switch-Chip)
#  c   {"normal"={...};"alt"={...}} je Zustand: pv (PVID), ft (frame-types), ed (edge), bg (bpdu-guard),
#      tg (getaggte VIDs, Komma-Liste), ut (ungetaggte VID oder ""), iso (reiner Access-Port eines isolierten
#      VLANs, DP3.1), spec (Profil fürs Log)
# Ändert nur diesen Port: Bridge-Port, seine Einträge in den Bridge-VLANs (cfm:bv:<VID>) und ggf. cfm-iso, trennt
# danach den Link für 3 s (neue DHCP-Adresse am Gerät). Der nächste Apply übernimmt den Zustand aus der Datei (ein
# Release schaltet nicht zurück).
# ============================================================
:local portsw do={
  :local s $st
  :if ($s = "toggle") do={
    :local cur ""
    :onerror e in={ :set cur [:tostr [/file/get $sf contents]] } do={}
    :set s "alt"
    :if ($cur = "alt") do={ :set s "normal" }
  }
  :local x ($c->$s)
  :local bp [/interface/bridge/port/find where interface=$p and !dynamic]
  :if ([:len $bp] = 0) do={ :log warning ("cfm: Port " . $p . " ist kein Bridge-Port - nicht umgeschaltet"); :return false }
  # erst Rahmen/Edge, dann die VLAN-Tabelle, zuletzt die neue PVID
  /interface/bridge/port/set $bp frame-types=($x->"ft") edge=($x->"ed") bpdu-guard=($x->"bg")
  :local tg ({})
  :foreach v in=[:toarray ($x->"tg")] do={ :set ($tg->[:tostr $v]) 1 }
  :local ut [:tostr ($x->"ut")]
  :local seen ({})
  :foreach bv in=[/interface/bridge/vlan/find where bridge=$br and !dynamic and comment~"^cfm:bv:"] do={
    :local cm [:tostr [/interface/bridge/vlan/get $bv comment]]
    :local vid [:pick $cm 7 [:len $cm]]
    :set ($seen->$vid) 1
    :local ot [/interface/bridge/vlan/get $bv tagged]
    :local ou [/interface/bridge/vlan/get $bv untagged]
    :local nt ({}); :local nu ({})
    :foreach i in=$ot do={ :if ([:tostr $i] != $p) do={ :set nt ($nt , [:tostr $i]) } }
    :foreach i in=$ou do={ :if ([:tostr $i] != $p) do={ :set nu ($nu , [:tostr $i]) } }
    :if ([:typeof ($tg->$vid)] != "nothing") do={ :set nt ($nt , $p) }
    :if ($vid = $ut) do={ :set nu ($nu , $p) }
    :if ([:len $nt] != [:len $ot] or [:len $nu] != [:len $ou]) do={ /interface/bridge/vlan/set $bv tagged=$nt untagged=$nu }
  }
  # VLAN ohne Eintrag auf diesem Gerät (nur am Port gebraucht): anlegen, der nächste Apply übernimmt ihn
  :foreach vid,m in=$tg do={ :if ([:typeof ($seen->$vid)] = "nothing") do={ /interface/bridge/vlan/add bridge=$br vlan-ids=[:tonum $vid] tagged=$p comment=("cfm:bv:" . $vid) } }
  :if ([:len $ut] > 0 and [:typeof ($seen->$ut)] = "nothing") do={ /interface/bridge/vlan/add bridge=$br vlan-ids=[:tonum $ut] untagged=$p comment=("cfm:bv:" . $ut) }
  :local pv 1
  :if ([:len $ut] > 0) do={ :set pv [:tonum $ut] }
  /interface/bridge/port/set $bp pvid=$pv
  # isoliertes VLAN (DP3.1): Client-Port in cfm-iso, Verkehr über die CPU (hw=no); sonst wieder heraus
  :local mi [/interface/list/member/find where list="cfm-iso" and interface=$p and !dynamic]
  :if ($x->"iso") do={
    :if ([:len $mi] = 0 and [:len [/interface/list/find where name="cfm-iso"]] > 0) do={ /interface/list/member/add list="cfm-iso" interface=$p comment=("cfm:ilm:ISO:" . $p) }
    :if ($hw) do={ /interface/bridge/port/set $bp hw=no }
  } else={
    :if ([:len $mi] > 0) do={
      /interface/list/member/remove $mi
      :if ($hw) do={ /interface/bridge/port/set $bp hw=yes }
    }
  }
  # Link kurz trennen: Das Gerät am Port merkt den Wechsel und holt per DHCP eine Adresse im neuen VLAN (sonst
  # behielte es die alte bis zum Ablauf der Lease); zugleich sichtbare Rückmeldung (Port-LED, Netzwerk-Symbol)
  :onerror e in={ /interface/disable [find where name=$p]; :delay 3s; /interface/enable [find where name=$p] } do={}
  :onerror e in={ /file/set $sf contents=$s } do={ /file/add name=$sf contents=$s }
  :log info ("cfm: Port " . $p . " (" . $nm . ") auf " . $s . ": " . ($x->"spec"))
  :return true
}
