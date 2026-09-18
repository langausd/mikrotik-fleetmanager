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
  "mgrTick"="10m";
  "ringSoak"={"30m";"2h"};
  "archiveKeep"=10;
  "pkgPath"="";
  "mgmtAccess"="mgmt";
  "mgmtExtra"={};
  "policy"={
    "mgmt"="*,*wan";
    "lan"="iot,guest,*wan";
    "iot"="*allow:iot-cloud";
    "guest"="*wan";
    "onboard"="*mtupdate"
  };
  "allow"={"iot-cloud"={"cloud.example.com";"203.0.113.10"}};
  "rosChannel"="stable";
  "rosMin"="7.22";
  "onboard"={"timeout"="60m";"mtHosts"={"upgrade.mikrotik.com";"download.mikrotik.com";"cdn.mikrotik.com"}};
  "users"={"netadmin"="full"};
  "adminUser"="disable";
  "services"={"ssh"=22;"winbox"=8291};
  "hook"={"host"="";"user"="cfm"}
}
# Erläuterungen:
#  managers   Fallback-Liste (Primary zuerst). Geräte ziehen per SFTP von hier.
#  mgrTick    Intervall des allgemeinen Manager-Ticks (Status, Ring-Aufstieg, Secret-Sync,
#             Updates, Netzplan, Hook, Vault-Backup). Das Onboarding hat einen eigenen, festen
#             1m-Tick und bleibt davon unberührt.
#  ringSoak   Wartezeit nach erfolgreichem Ring 0 -> 1 bzw. 1 -> 2. "manual" = nur per $cfmPromote.
#  archiveKeep  so viele Versionen bleiben im Archiv (plus alle, die Ringe/Geräte nutzen).
#  pkgPath    Ablage der RouterOS-Pakete für $cfmUpgrade, leer = <cfm>/pkg. Bei kleinem Flash
#             auf USB/NVMe legen, z.B. "usb1/cfm-pkg" (ca. 20 MB pro Architektur und Version).
#  policy     Zonen-Matrix: von-Zone = erlaubte Ziele: Zonen, "wan" = Internet, "*" = alles,
#             "mtupdate" = nur die MikroTik-Update-Server aus onboard.mtHosts,
#             "allow:<Liste>" = nur die Ziele einer Liste aus allow.
#             NAT nur mit Kennzeichen (D38): "*wan" = masquerade, "wan@192.0.2.5" = feste
#             NAT-Adresse (bei VRRP wandert sie mit dem Master); "wan" ohne Kennzeichen wird
#             geroutet, der Upstream-Router braucht dann eine Route zurück. Gilt auch für
#             "mtupdate" und "allow:…". Internet für eine Zone mit "*" per "*,*wan".
#             Zonen ohne "*" oder "wan": DNS-Anfragen an externe Server gehen an den Router.
#  allow      Freigabelisten für policy "allow:<Name>": Hostnamen (RouterOS löst sie
#             regelmäßig auf), IPs oder Netze.
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
