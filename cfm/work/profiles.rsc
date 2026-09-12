# ============================================================
# cfm – Port-Profile. Nutzung im Hostfile: ports={"ether2"="access:40";"ether1"="trunk"}
#  tag     tagged VLANs: "*" = alle, Zonen- oder VID-Liste, "!x" schließt aus
#          (z.B. "*,!guest" oder "mgmt,lan,101")
#  untag   untagged VLAN (PVID); "arg" = Argument nach dem Doppelpunkt
#  edge    "yes" für Endgeräte-Ports (schnelles Forwarding, BPDU-Guard)
#  bridge  "no" = Port gehört nicht zur Bridge (z.B. WAN)
#  disabled "yes" = Port abschalten
# ============================================================
:global cfmProfiles {
  "trunk"={"tag"="*"};
  "trunk-ap"={"tag"="mgmt,lan,iot,guest"};
  "access"={"untag"="arg";"edge"="yes"};
  "hybrid"={"untag"="arg";"tag"="*"};
  "wan"={"bridge"="no"};
  "off"={"bridge"="no";"disabled"="yes"}
}
