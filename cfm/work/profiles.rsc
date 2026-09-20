# ============================================================
# cfm – Port-Profile. Nutzung im Hostfile: ports={"ether2"="access:40";"ether1"="trunk"}
#  tag     tagged VLANs: "*" = alle, Zonen- oder VID-Liste, "!x" schließt aus
#          (z.B. "*,!guest" oder "mgmt,lan,101")
#  untag   untagged VLAN (PVID); "arg" = Argument nach dem Doppelpunkt
#  edge    "yes" für Endgeräte-Ports (schnelles Forwarding, BPDU-Guard)
#  bridge  "no" = Port gehört nicht zur Bridge (z.B. WAN)
#  disabled "yes" = Port abschalten
# vport = wie access, aber ohne edge/BPDU-Guard: für Karten virtueller Maschinen. Die Bridge des
#         Virtualisierungshosts reicht BPDUs aus dem Switch-Netz durch, BPDU-Guard würde den Port
#         abschalten, sobald irgendwo im Netz RSTP spricht.
# Kommentare gehören in diesen Kopf, NICHT zwischen die Zeilen des Arrays - dort scheitert der
# Import mit "syntax error".
# ============================================================
:global cfmProfiles {
  "trunk"={"tag"="*"};
  "trunk-ap"={"tag"="mgmt,lan,iot,guest"};
  "access"={"untag"="arg";"edge"="yes"};
  "vport"={"untag"="arg"};
  "hybrid"={"untag"="arg";"tag"="*"};
  "wan"={"bridge"="no"};
  "off"={"bridge"="no";"disabled"="yes"}
}
