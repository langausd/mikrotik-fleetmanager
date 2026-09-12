# --- generischer Teil von cfm-bootstrap.rsc (wird von $cfmBootstrap angehängt) ---
# Erwartet die Locals: ip (x.x.x.x/nn), uplink (Port oder "*" = alle Ethernet-Ports),
#                      mv (MGMT-VLAN), gw, keys (PEM-Liste)
# Minimal: MGMT-VLAN erreichbar machen + User cfm mit den Manager-Schlüsseln.
# VLAN-Filtering bleibt aus – das schaltet erst die Rolle base scharf.
:local br "bridge"
:if ([:len [/interface/bridge/find where name=$br]] = 0) do={ /interface/bridge/add name=$br protocol-mode=rstp vlan-filtering=no }
:if ($uplink = "*") do={
  # Onboarding-Push: alle Ethernet-Ports in die Bridge – egal, wo das Kabel steckt
  :foreach i in=[/interface/ethernet/find] do={
    :local n [/interface/ethernet/get $i name]
    :if ([:len [/interface/bridge/port/find where interface=$n]] = 0) do={ /interface/bridge/port/add bridge=$br interface=$n }
  }
} else={
  :if ([:len [/interface/bridge/port/find where interface=$uplink]] = 0) do={ /interface/bridge/port/add bridge=$br interface=$uplink }
}
:local vif ("vlan" . $mv)
:if ([:len [/interface/vlan/find where name=$vif]] = 0) do={ /interface/vlan/add name=$vif interface=$br vlan-id=$mv }
:if ($uplink != "*" and [:len [/interface/bridge/vlan/find where vlan-ids=$mv]] = 0) do={ /interface/bridge/vlan/add bridge=$br vlan-ids=$mv tagged=($br . "," . $uplink) }
:if ([:len [/ip/address/find where interface=$vif]] = 0) do={ /ip/address/add address=$ip interface=$vif }
:if ([:len [/ip/route/find where dst-address="0.0.0.0/0" and gateway=$gw]] = 0) do={ /ip/route/add dst-address=0.0.0.0/0 gateway=$gw }
# Werks-Config eines Routers: MGMT-VLAN in die LAN-Liste, sonst blockiert dessen Firewall den Manager
:if ([:len [/interface/list/find where name="LAN"]] > 0 and [:len [/interface/list/member/find where list="LAN" and interface=$vif]] = 0) do={ /interface/list/member/add list=LAN interface=$vif }
# nach reset-configuration no-defaults fehlen auch die Log-Regeln
:if ([:len [/system/logging/find]] = 0) do={ :foreach t in={"info";"warning";"error";"critical"} do={ /system/logging/add topics=$t action=memory } }
:if ([:len [/user/find where name="cfm"]] = 0) do={
  /user/add name=cfm group=full comment="cfm-sys:user" password=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"]
}
/user/ssh-keys/remove [find where user=cfm]
:local i 0
:foreach k in=$keys do={
  :set i ($i + 1)
  /file/add name=("cfm-mgr" . $i . ".pem") contents=$k
  :delay 500ms
  /user/ssh-keys/import user=cfm public-key-file=("cfm-mgr" . $i . ".pem")
}
/ip/service/set [find where name=ssh and !dynamic] disabled=no
:local s ""
:onerror e in={ :set s [/system routerboard get serial-number] } do={}
:if ([:len $s] = 0) do={ :onerror e in={ :set s [/system/license/get system-id] } do={} }
:put ("cfm-Bootstrap fertig. MGMT " . $ip . " auf " . $vif . " über " . $uplink . ", Seriennummer " . $s)
:put "Jetzt am Manager: \$cfmEnroll name=<name> ip=<ip ohne /nn> role=<rolle> ring=<0-2>"
