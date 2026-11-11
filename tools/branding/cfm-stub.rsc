# cfm-Stub (DO1.8): Default-Config im Branding-Paket, läuft nach jedem Reset (Reset-Taster, reset-configuration ohne
# no-defaults, Netinstall mit -r). Ziel: Das Gerät ist im Onboarding-VLAN 88 (DO1.4) per DHCP und unter 192.168.88.1
# erreichbar, der Manager meldet sich als admin mit dem Onboarding-Schlüssel an (ssh-exec) - kein Aufkleber-Passwort.
# Grenze von RouterOS: 2 Minuten Laufzeit. Kein WLAN, keine Firewall (das Onboarding-VLAN ist isoliert); Stufe 2 des
# Pushs (DO1.5) ersetzt alles durch den gerätespezifischen Bootstrap (reset-configuration no-defaults=yes überspringt
# diesen Stub, run-after-reset führt den Bootstrap aus).
# Vor dem Bau: @ONBKEY@ durch den öffentlichen Onboarding-Schlüssel ersetzen (ssh-ed25519 AAAA... cfm-onboard),
# siehe docs/NETINSTALL.md, offene Frage O3. Werks-Passwort bleibt ($defconfPassword), wird nicht gebraucht.
:delay 5s
/system/identity/set name="cfm-new"
# alle Ethernet-Ports in eine Bridge (wie die Werks-Config); ohne VLAN-Filter: VLAN 88 kommt am Onboarding-Port untagged an
:if ([:len [/interface/bridge/find where name="bridge"]] = 0) do={ /interface/bridge/add name=bridge }
:foreach i in=[/interface/ethernet/find] do={
  :local n [/interface/ethernet/get $i name]
  :if ([:len [/interface/bridge/port/find where interface=$n]] = 0) do={ :onerror e in={ /interface/bridge/port/add bridge=bridge interface=$n } do={} }
}
# Werksadresse und DHCP-Client nebeneinander (DO1.6: der Manager findet das Gerät über beides)
:if ([:len [/ip/address/find where address="192.168.88.1/24"]] = 0) do={ /ip/address/add address=192.168.88.1/24 interface=bridge }
:if ([:len [/ip/dhcp-client/find where interface=bridge]] = 0) do={ /ip/dhcp-client/add interface=bridge disabled=no add-default-route=yes use-peer-dns=yes }
# Onboarding-Schlüssel für admin (die Datei muss für /user/ssh-keys/import existieren)
:onerror e in={ /file/remove [find where name="cfm-onboard.pub"] } do={}
/file/add name=cfm-onboard.pub contents="@ONBKEY@"
:delay 1s
:onerror e in={ /user/ssh-keys/import public-key-file=cfm-onboard.pub user=admin } do={ :log warning ("cfm-stub: Schluessel nicht importiert: " . $e) }
# nur SSH (und Winbox fuer den Notfall vor Ort); Rest aus
/ip/service/set [find where name="ssh"] disabled=no
/ip/service/set [find where name!="ssh" and name!="winbox"] disabled=yes
:onerror e in={ /ip/ssh/set known-hosts-validation=no } do={}
/system/note/set show-at-login=yes note="cfm: Geraet im Onboarding-Zustand (Branding-Stub). Aufnahme: \$cfmRegister + \$cfmOnboard am Manager."
:log info "cfm-stub: Onboarding-Zustand hergestellt (DHCP in VLAN 88, 192.168.88.1, Schluessel fuer admin)"
