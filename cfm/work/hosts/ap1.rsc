# ap1 – Access Point (Beispiel: cAP ax), Uplink ether1, ether2 für ein Endgerät
# WLAN-Kanal-Pinning für diesen AP gehört nach wifi.rsc -> radios (der CAPsMAN rendert).
:global cfmHost {
  "ports"={"ether1"="trunk-ap";"ether2"="access:20"}
}
