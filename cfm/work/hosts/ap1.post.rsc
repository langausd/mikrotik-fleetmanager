# ap1.post.rsc – freie Befehle NACH allen Rollen, nur für ap1.
# Idempotent schreiben (wird bei jedem Apply ausgeführt). Mit cfmEnsure
# angelegte Objekte werden verwaltet (inkl. Aufräumen), direkte Befehle nicht.
:global cfmSet; :global cfmEnsure
$cfmSet m="/system/leds/settings" p=({"all-leds-off"="never"})
# Beispiel: zusätzlicher statischer DNS-Eintrag nur auf diesem Gerät
# $cfmEnsure m="/ip/dns/static" k="post:dns:printer" p=({"name"="printer.internal";"address"="192.168.20.20"})
