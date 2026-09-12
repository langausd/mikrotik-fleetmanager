# cfm Onboarding Stufe 2 – vom Manager als cfm-go.auto.rsc hochgeladen und sofort ausgeführt:
# Konfiguration komplett leeren (keine Werks-Firewall/-DHCP-Reste) und nach dem Neustart genau
# den gerätespezifischen Bootstrap ausführen. @PATH@ ersetzt der Manager.
/system/reset-configuration no-defaults=yes skip-backup=yes run-after-reset="@PATH@"
