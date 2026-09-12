# cm1 – Primary Config-Manager + CAPsMAN (Beispiel: RB5009 / hAP ax³)
# Rollen/IP/Ring stehen in meta/inventory.rsc, hier nur Gerätespezifika.
:global cfmHost {
  "ports"={"ether1"="trunk";"ether2"="trunk-ap";"ether3"="access:10"}
}
# Beispiel Daten-Override nur für dieses Gerät:
# :global cfmVlans; :set ($cfmVlans->"119"->"l3") "no"
