# ============================================================
# Rolle capsman – wifi-CAPsMAN für alle APs (D45)
#  Rendert die komplette CAPsMAN-Konfiguration aus wifi.rsc (SSIDs, Security, PPSK, Kanal-Pools,
#  Pinning, Provisioning) und schaltet den Dienst im MGMT-VLAN ein. Die Passphrasen kommen per
#  Secret-Push aus dem Vault. Unabhängig vom Config-Manager: Der CAPsMAN gehört auf ein Gerät,
#  das nicht an einer VM hängt. Umzug = Rolle im Inventar verschieben (z.B. $cfmEnroll … role=),
#  die APs folgen über das Manifest (Adressen, Namen, Zertifikate – Rolle ap).
#  Ohne Gerät mit dieser Rolle bleibt der Primary-Manager CAPsMAN (Übergang, $cfmCheck warnt).
# ============================================================
:global cfmCapsmanOn
$cfmCapsmanOn
