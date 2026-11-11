# cfm CAPs-Mode-Skript (DO1.8): ersetzt MikroTiks caps-mode-script im Branding-Paket. Der Reset-Taster (~10 s halten
# beim Einschalten) setzt PoE-Geraete damit in den Onboarding-Zustand wie cfm-stub.rsc - gleicher Inhalt, nur dass
# die Radios als CAP an bleiben duerfen (stoert nicht, der Bootstrap raeumt sie ab). Vor dem Bau @ONBKEY@ ersetzen.
:delay 5s
/system/identity/set name="cfm-new"
:if ([:len [/interface/bridge/find where name="bridge"]] = 0) do={ /interface/bridge/add name=bridge }
:foreach i in=[/interface/ethernet/find] do={
  :local n [/interface/ethernet/get $i name]
  :if ([:len [/interface/bridge/port/find where interface=$n]] = 0) do={ :onerror e in={ /interface/bridge/port/add bridge=bridge interface=$n } do={} }
}
:if ([:len [/ip/address/find where address="192.168.88.1/24"]] = 0) do={ /ip/address/add address=192.168.88.1/24 interface=bridge }
:if ([:len [/ip/dhcp-client/find where interface=bridge]] = 0) do={ /ip/dhcp-client/add interface=bridge disabled=no add-default-route=yes use-peer-dns=yes }
:onerror e in={ /file/remove [find where name="cfm-onboard.pub"] } do={}
/file/add name=cfm-onboard.pub contents="@ONBKEY@"
:delay 1s
:onerror e in={ /user/ssh-keys/import public-key-file=cfm-onboard.pub user=admin } do={ :log warning ("cfm-stub: Schluessel nicht importiert: " . $e) }
/ip/service/set [find where name="ssh"] disabled=no
/ip/service/set [find where name!="ssh" and name!="winbox"] disabled=yes
:onerror e in={ /ip/ssh/set known-hosts-validation=no } do={}
:onerror e in={ /interface/wifi/cap/set enabled=yes discovery-interfaces=bridge } do={}
:log info "cfm-stub (CAP-Modus): Onboarding-Zustand hergestellt"
