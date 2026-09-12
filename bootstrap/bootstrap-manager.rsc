# ============================================================
# cfm – Bootstrap des PRIMARY-Managers (einmalig)
# Voraussetzung: tools/upload-seed.sh hat cfm/work + cfm/meta hochgeladen.
# Ausführen:  /import bootstrap-manager.rsc   (als Admin)
# Danach:     Secrets setzen ($cfmSecret ...), weitere Geräte bootstrappen/enrollen.
# ============================================================
# ---- anpassen ----
:local myname "cm1"              ;# Name dieses Managers im Inventar
:local ip "192.168.10.2/24"      ;# MGMT-IP = managers[0] aus global.rsc
:local uplink "ether1"           ;# Port, über den das MGMT-VLAN (tagged) kommt
:local mv 10                     ;# MGMT-VLAN
:local gw "192.168.10.1"         ;# Gateway im MGMT-VLAN
:local admin "admin"             ;# dein Admin-User (bekommt den Manager-Key für ssh-exec)
:local role "manager"            ;# ggf. "switch,manager" oder "router,manager"
# -------------------
:local b "cfm"
:if ([:len [/file/find where name="flash" and type="directory"]] > 0) do={ :set b "flash/cfm" }
:if ([:len [/file/find where name=($b . "/work/lib/manager.rsc")]] = 0) do={ :error ("Seed fehlt: " . $b . "/work/ hochladen (tools/upload-seed.sh)") }

# 1) MGMT erreichbar machen (wie bei jedem Gerät)
:local br "bridge"
:if ([:len [/interface/bridge/find where name=$br]] = 0) do={ /interface/bridge/add name=$br protocol-mode=rstp vlan-filtering=no }
:if ([:len [/interface/bridge/port/find where interface=$uplink]] = 0) do={ /interface/bridge/port/add bridge=$br interface=$uplink }
:local vif ("vlan" . $mv)
:if ([:len [/interface/vlan/find where name=$vif]] = 0) do={ /interface/vlan/add name=$vif interface=$br vlan-id=$mv }
:if ([:len [/interface/bridge/vlan/find where vlan-ids=$mv]] = 0) do={ /interface/bridge/vlan/add bridge=$br vlan-ids=$mv tagged=($br . "," . $uplink) }
:if ([:len [/ip/address/find where interface=$vif]] = 0) do={ /ip/address/add address=$ip interface=$vif }
:if ([:len [/ip/route/find where dst-address="0.0.0.0/0" and gateway=$gw]] = 0) do={ /ip/route/add dst-address=0.0.0.0/0 gateway=$gw }

# 2) User cfm + Manager-Schlüssel (ed25519-Host-Key = Identität des Managers)
:if ([:len [/user/find where name="cfm"]] = 0) do={
  /user/add name=cfm group=full comment="cfm-sys:user" password=[:rndstr length=40 from="abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"]
}
:if ([:len [/user/group/find where name="cfm-dev"]] = 0) do={ /user/group/add name=cfm-dev policy=ssh,ftp,read comment="cfm-sys:grp" }
:if ([:len [/user/ssh-keys/private/find where user=cfm]] = 0) do={
  /ip/ssh/set host-key-type=ed25519
  /ip/ssh/regenerate-host-key
  :delay 1s
  :foreach u in={"cfm";$admin} do={
    /ip/ssh/export-host-key key-file-prefix=cfm-id
    :delay 1s
    /user/ssh-keys/private/import user=$u private-key-file=cfm-id_ed25519.pem
    :delay 500ms
  }
}
/ip/ssh/export-host-key key-file-prefix=cfm-id
:delay 1s
:local pub [/file/get cfm-id_ed25519_pub.pem contents]
/user/ssh-keys/remove [find where user=cfm]
/user/ssh-keys/import user=cfm public-key-file=cfm-id_ed25519_pub.pem
/file/remove [find where name~"^cfm-id"]
:foreach d in={"work";"meta";"meta/keys";"live";"live/m";"archive";"state";"vault"} do={
  :if ([:len [/file/find where name=($b . "/" . $d)]] = 0) do={ /file/add name=($b . "/" . $d) type=directory }
}
/file/add name=($b . "/meta/keys/" . $myname . ".pem") contents=$pub

# 3) Manager-Funktionen laden, erstes Release, sich selbst enrollen
:if ([:len [/system/script/find where name="cfm-mgr"]] = 0) do={ /system/script/add name=cfm-mgr comment="cfm-sys:mgr" policy=ftp,reboot,read,write,policy,test,password,sensitive source="" }
/system/script/set [find where name="cfm-mgr"] source=[/file/get ($b . "/work/lib/manager.rsc") contents]
/system/script/run cfm-mgr
:global cfmRelease; :global cfmEnroll
$cfmRelease msg=" initial"
$cfmEnroll name=$myname ip=[:pick $ip 0 [:find $ip "/"]] role=$role ring=2
:put "Primary-Manager bereit. Nächste Schritte:"
:put "  \$cfmSecret key=user.<admin> value=...   \$cfmSecret key=psk.main value=...   \$cfmSecret key=vaultpw value=..."
:put "  \$cfmBootstrap  -> cfm/cfm-bootstrap.rsc für neue Geräte"
