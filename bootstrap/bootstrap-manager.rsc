# ============================================================
# cfm – Bootstrap des PRIMARY-Managers (einmalig)
# Voraussetzung: tools/upload-seed.sh hat cfm/work + cfm/meta hochgeladen, diese Datei liegt als
#                bootstrap-manager.rsc im Wurzelverzeichnis des Geräts.
# Ausführen:  /import bootstrap-manager.rsc   (als Admin)
#   clean="yes": Das Gerät setzt sich zuerst auf eine leere Config zurück (entfernt Werks- oder
#   CAPs-Config) und führt den Bootstrap nach dem Neustart selbst aus. User, Passwörter und
#   SSH-Schlüssel bleiben (keep-users). Die SSH-Sitzung bricht dabei ab; Fortschritt danach im
#   Log: /log print where message~"cfm: "
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
:local clean "yes"               ;# "yes" = vorher auf leere Config zurücksetzen (empfohlen),
                                 ;# "no" = auf der vorhandenen Config aufbauen (Reste: $cfmAudit)
:local post ""                   ;# optional: Befehle direkt nach dem Reset (zusätzlicher Zugang)
# -------------------
:local b "cfm"
:if ([:len [/file/find where name="flash" and type="directory"]] > 0) do={ :set b "flash/cfm" }
:if ([:len [/file/find where name=($b . "/work/lib/mgr-core.rsc")]] = 0) do={ :error ("Seed fehlt: " . $b . "/work/ hochladen (tools/upload-seed.sh)") }

# Ablauf mit clean="yes" in Stufen, erkannt an Markierungsdateien unter cfm/:
#   1 (du, per /import): Prüfungen, Reset mit run-after-reset=diese Datei.
#   2 (nach dem Neustart, als Systemnutzer *sys): post, MGMT-Zugang, User cfm mit Einmal-Passwort.
#     *sys hat keinen SSH-Schlüssel, ssh-exec und SFTP für den Selbst-Enroll scheitern; die Dienste
#     starten außerdem erst nach dem run-after-reset-Skript. Deshalb die Übergabe an cfm:
#   u (Scheduler cfm-bootstrap-2, als *sys, nach dem Hochfahren): lädt per SFTP mit dem
#     Einmal-Passwort eine .auto.rsc an 127.0.0.1 hoch. RouterOS führt sie als cfm aus; sie legt
#     die Markierung für Stufe 3 und den Scheduler cfm-bootstrap-3 an, der cfm gehört.
#   3 (Scheduler cfm-bootstrap-3, als cfm): der Bootstrap unten, wie mit clean="no" ("0").
:local me "bootstrap-manager.rsc"
:local m2 ($b . "/bootstrap-stufe2.txt")
:local mu ($b . "/bootstrap-uebergabe.txt")       ;# enthält das Einmal-Passwort von cfm
:local m3 ($b . "/bootstrap-stufe3.txt")
:local pwc "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
:local stage "0"
:if ($clean = "yes") do={ :set stage "1" }
:if ([:len [/file/find where name=$m2]] > 0) do={ :set stage "2" }
:if ([:len [/file/find where name=$mu]] > 0) do={ :set stage "u" }
:if ([:len [/file/find where name=$m3]] > 0) do={ :set stage "3" }

# MGMT erreichbar machen (wie bei jedem Gerät): in Stufe 2 und im Bootstrap
:local mgmt do={
  :local br "bridge"
  :if ([:len [/interface/bridge/find where name=$br]] = 0) do={ /interface/bridge/add name=$br protocol-mode=rstp vlan-filtering=no }
  :if ([:len [/interface/bridge/port/find where interface=$uplink]] = 0) do={ /interface/bridge/port/add bridge=$br interface=$uplink }
  :local vif ("vlan" . $mv)
  :if ([:len [/interface/vlan/find where name=$vif]] = 0) do={ /interface/vlan/add name=$vif interface=$br vlan-id=$mv }
  :if ([:len [/interface/bridge/vlan/find where vlan-ids=$mv]] = 0) do={ /interface/bridge/vlan/add bridge=$br vlan-ids=$mv tagged=($br . "," . $uplink) }
  :if ([:len [/ip/address/find where interface=$vif]] = 0) do={ /ip/address/add address=$ip interface=$vif }
  :if ([:len [/ip/route/find where dst-address="0.0.0.0/0" and gateway=$gw]] = 0) do={ /ip/route/add dst-address=0.0.0.0/0 gateway=$gw }
}

:if ($stage = "1") do={
  :if ([:len [/system/script/find where name="cfm-mgr"]] > 0) do={ :error "Gerät ist bereits Manager: kein Reset (für einen Neuaufbau erst von Hand zurücksetzen oder clean=no)" }
  :if ([:len [/file/find where name=$me]] = 0) do={ :error ("diese Datei muss als " . $me . " im Wurzelverzeichnis liegen") }
  :if ([:len [/user/find where name=$admin]] = 0) do={ :error ("User " . $admin . " fehlt: admin im Kopf anpassen") }
  # Reste eines abgebrochenen Bootstraps: Die Schlüssel von cfm passen danach nicht mehr sicher
  # zum Host-Key, Stufe 2 legt den User und der Bootstrap die Schlüssel neu an
  /user/ssh-keys/private/remove [find where user=cfm]
  /user/remove [find where name=cfm]
  /file/add name=$m2 contents="cfm: Bootstrap Stufe 2 nach dem Reset"
  :log warning "cfm: Bootstrap - Reset auf leere Config, danach läuft der Bootstrap automatisch weiter"
  :put "Reset auf leere Config: das Gerät startet neu und setzt den Bootstrap danach selbst fort."
  :put ("Danach per SSH über " . $ip . " am Uplink " . $uplink . "; Fortschritt im Log (cfm: ...).")
  :delay 2s
  # keep-users: User, Passwörter und SSH-Schlüssel bleiben, der Zugang geht nicht verloren
  /system/reset-configuration no-defaults=yes skip-backup=yes keep-users=yes run-after-reset=$me
  :error "cfm: Reset läuft"
}

:if ($stage = "2") do={
  /file/remove [find where name=$m2]
  :log info "cfm: Bootstrap Stufe 2 nach dem Reset"
  :delay 10s
  # Ein Fehler bricht ein run-after-reset-Skript ab (Log: "error while running run-after-reset
  # script"), deshalb ist alles abgesichert; ein Fehler in post gibt nur eine Warnung
  :if ([:len $post] > 0) do={
    :onerror e in={ :local pf [:parse $post]; $pf; :log info "cfm: Bootstrap - post erledigt" } do={ :log warning ("cfm: Bootstrap - post fehlgeschlagen: " . $e) }
  }
  :onerror e in={
    $mgmt uplink=$uplink mv=$mv ip=$ip gw=$gw
    :local pw [:rndstr length=40 from=$pwc]
    /user/add name=cfm group=full comment="cfm-sys:user" password=$pw
    /file/add name=$mu contents=$pw
    /system/scheduler/add name=cfm-bootstrap-2 interval=15s on-event=("/import " . $me)
    :log info "cfm: Bootstrap - Übergabe an cfm folgt nach dem Hochfahren"
  } do={ :log error ("cfm: Bootstrap Stufe 2 fehlgeschlagen: " . $e) }
}

:if ($stage = "u") do={
  :local pw [/file/get [find where name=$mu] contents]
  /file/add name="cfm-uebergabe.rsc" contents=("/file/add name=\"" . $m3 . "\" contents=\"cfm: Bootstrap Stufe 3\"\n/system/scheduler/add name=cfm-bootstrap-3 interval=10s on-event=\"/import " . $me . "\"\n")
  :delay 1s
  :onerror e in={
    /tool/fetch upload=yes url="sftp://127.0.0.1/cfm-uebergabe.auto.rsc" src-path="cfm-uebergabe.rsc" user=cfm password=$pw
    :delay 2s
    :if ([:len [/system/scheduler/find where name="cfm-bootstrap-3"]] = 0) do={ :error "Scheduler cfm-bootstrap-3 fehlt" }
    /file/remove [find where name=$mu]
    /system/scheduler/remove [find where name="cfm-bootstrap-2"]
    :log info "cfm: Bootstrap - Übergabe an cfm erfolgt"
  } do={ :log info ("cfm: Bootstrap - Übergabe an cfm noch nicht möglich: " . $e) }
  /file/remove [find where name~"^cfm-uebergabe"]
}

:if ($stage = "3") do={
  /file/remove [find where name=$m3]
  /system/scheduler/remove [find where name="cfm-bootstrap-3"]
  /user/set [find where name=cfm] password=[:rndstr length=40 from=$pwc]
  :log info "cfm: Bootstrap Stufe 3 als cfm"
}

:if ($stage = "0" or $stage = "3") do={
  :onerror err in={
    # 1) MGMT erreichbar machen
    $mgmt uplink=$uplink mv=$mv ip=$ip gw=$gw

    # 2) User cfm + Manager-Schlüssel (ed25519-Host-Key = Identität des Managers)
    :if ([:len [/user/find where name="cfm"]] = 0) do={
      /user/add name=cfm group=full comment="cfm-sys:user" password=[:rndstr length=40 from=$pwc]
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

    # 3) Manager-Funktionen laden (je Modul lib/mgr-*.rsc ein Skript cfm-mgr-<modul>, das Skript
    #    cfm-mgr lädt alle), erstes Release, sich selbst enrollen
    :foreach f in=[/file/find where name~("^" . $b . "/work/lib/mgr-.*[.]rsc\$")] do={
      :local fn [/file/get $f name]
      :local s ("cfm-mgr-" . [:pick $fn ([:find $fn "lib/mgr-"] + 8) ([:len $fn] - 4)])
      :if ([:len [/system/script/find where name=$s]] = 0) do={ /system/script/add name=$s comment="cfm-sys:mgr" policy=ftp,reboot,read,write,policy,test,password,sensitive source="" }
      /system/script/set [find where name=$s] source=[/file/get $f contents]
    }
    :if ([:len [/system/script/find where name="cfm-mgr"]] = 0) do={ /system/script/add name=cfm-mgr comment="cfm-sys:mgr" policy=ftp,reboot,read,write,policy,test,password,sensitive source="" }
    /system/script/set [find where name="cfm-mgr"] source=":foreach s in=[/system/script/find where name~\"^cfm-mgr-\"] do={ /system/script/run \$s }"
    /system/script/run cfm-mgr
    :global cfmRelease; :global cfmEnroll
    $cfmRelease msg=" initial"
    $cfmEnroll name=$myname ip=[:pick $ip 0 [:find $ip "/"]] role=$role ring=2
  } do={
    :log error ("cfm: Bootstrap fehlgeschlagen: " . $err)
    :error ("Bootstrap fehlgeschlagen: " . $err)
  }
  :log info "cfm: Primary-Manager bereit"
  :put "Primary-Manager bereit. Nächste Schritte:"
  :put "  \$cfmSecret key=user.<admin> value=...   \$cfmSecret key=psk.main value=...   \$cfmSecret key=vaultpw value=..."
  :put "  \$cfmBootstrap  -> cfm/cfm-bootstrap.rsc für neue Geräte"
}
