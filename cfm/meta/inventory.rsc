# ============================================================
# cfm – Inventar (Manager-Metadaten, NICHT versioniert, wirkt sofort)
# Key = Identity (= Name des Hostfiles hosts/<name>.rsc)
#  serial  RouterBoard-Seriennummer (CHR/x86: Software-ID). Gerätetausch = hier ändern
#          + $cfmEnroll name=<name> ip=<aktuelle IP> auf dem Manager.
#  role    base ist immer aktiv; weitere: router, switch, ap, manager, manager-backup
#          (Kombinationen per Komma, z.B. "router,manager")
#  ring    Rollout-Ring 0 (Canary) .. 2
#  ip      MGMT-IP (VLAN mgmtVlan), /24
# Wird von $cfmEnroll automatisch ergänzt/aktualisiert.
# ============================================================
:global cfmInv {
  "cm1"={"serial"="SERIAL-CM1";"role"="switch,manager";"ring"=2;"ip"="192.168.10.2"};
  "cm2"={"serial"="SERIAL-CM2";"role"="switch,manager-backup";"ring"=0;"ip"="192.168.10.3"};
  "rtr1"={"serial"="SERIAL-RTR1";"role"="router";"ring"=2;"ip"="192.168.10.251"};
  "sw1"={"serial"="SERIAL-SW1";"role"="switch";"ring"=1;"ip"="192.168.10.21"};
  "ap1"={"serial"="SERIAL-AP1";"role"="ap";"ring"=0;"ip"="192.168.10.31"};
  "ap2"={"serial"="SERIAL-AP2";"role"="ap";"ring"=1;"ip"="192.168.10.32"}
}
