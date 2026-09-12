# ============================================================
# cfm – globale Parameter (alle Geräte)
# Bearbeiten auf dem Manager in cfm/work/, wirksam nach $cfmRelease
# ============================================================
:global cfmG {
  "mgmtVlan"=10;
  "managers"={"192.168.10.2";"192.168.10.3"};
  "mgrPath"="cfm";
  "domain"="lan";
  "tz"="Europe/Berlin";
  "ntp"="192.168.10.1";
  "dns"="192.168.10.1";
  "syslog"="192.168.10.2";
  "interval"="15m";
  "reapply"="1d";
  "watchdog"="5m";
  "ringSoak"={"30m";"2h"};
  "archiveKeep"=10;
  "pkgPath"="";
  "mgmtAccess"="mgmt";
  "mgmtExtra"={};
  "policy"={
    "mgmt"="*";
    "lan"="iot,guest,wan";
    "iot"="wan";
    "guest"="wan";
    "onboard"="mtupdate"
  };
  "rosChannel"="stable";
  "rosMin"="7.20";
  "onboard"={"timeout"="60m";"mtHosts"={"upgrade.mikrotik.com";"download.mikrotik.com";"cdn.mikrotik.com"}};
  "users"={"netadmin"="full"};
  "adminUser"="disable";
  "services"={"ssh"=22;"winbox"=8291};
  "hook"={"host"="";"user"="cfm"}
}
# Erläuterungen:
#  managers   Fallback-Liste (Primary zuerst). Geräte ziehen per SFTP von hier.
#  ringSoak   Wartezeit nach erfolgreichem Ring 0 -> 1 bzw. 1 -> 2. "manual" = nur per $cfmPromote.
#  archiveKeep  so viele Versionen bleiben im Archiv (plus alle, die Ringe/Geräte nutzen).
#  pkgPath    Ablage der RouterOS-Pakete für $cfmUpgrade, leer = <cfm>/pkg. Bei kleinem Flash
#             auf USB/NVMe legen, z.B. "usb1/cfm-pkg" (ca. 20 MB pro Architektur und Version).
#  policy     Zonen-Matrix: von-Zone = erlaubte Ziel-Zonen ("wan" = Internet, "*" = alles,
#             "mtupdate" = nur die MikroTik-Update-Server aus onboard.mtHosts).
#  rosChannel Update-Kanal beim Onboarding; rosMin = Mindestversion (sonst Abbruch).
#  onboard    timeout = maximale Dauer einer Onboarding-Sitzung (Port fällt danach zurück).
#  mgmtAccess Zonen, aus denen Geräte-Management (SSH/Winbox) erlaubt ist.
#  mgmtExtra  zusätzliche Netze/Hosts mit Management-Zugriff, z.B. {"192.168.20.10/32"}
#             (Admin-PC, Git-Host für die externe Sicherung)
#  users      Admin-Benutzer -> Gruppe. Passwörter NUR im Vault (cfm:user.<name>), per Secret-Push.
#  adminUser  "disable" = Werks-User admin abschalten, sobald auf dem Gerät ein User aus users
#             aktiv ist (Passwort angekommen); "keep" = admin nicht anfassen.
#  services   aktive IP-Services, alle anderen werden deaktiviert.
#  hook       Git-Host für externe Sicherung (leer = aus).
