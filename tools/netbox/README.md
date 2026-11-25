# NetBox Custom Script „cfm-Abgleich“

Startet den Abgleich (TODO 55, DT2.3, Admin-Guide 8.21) aus NetBox heraus: *Anpassen → Skripte → cfm-Abgleich*,
Site wählen, ausführen. Das Ergebnis steht im Job-Log (je Befund eine Zeile: Fehler = Abweichung, Warnung = Hinweis)
und als Bericht in der Ausgabe. Es ändert nichts, weder in NetBox noch in cfm.

So arbeitet es:

* Den **Plan** liest das Skript direkt aus der Datenbank (ORM), es braucht kein API-Token.
* **Soll und Ist** holt `netbox-abgleich.py` per SSH vom Primary-Manager, als User `cfm-netbox`. Der darf nur lesen
  (Gruppe `ssh,read`) und genau ein Skript starten: `cfm-netbox-run`. Das wertet die Site-Daten aus (`$cfmNetbox`,
  letztes Release) und gibt die Dateien als Text aus. Der User selbst darf weder SFTP (Policy `ftp` = Schreibrecht)
  noch `/file/read`; das Skript läuft mit den Rechten seines Eigentümers.
* Läuft unter NetBox 3.7 bis 4.6. Der SSH-Client (`ssh`) muss im Container vorhanden sein.

## Einrichten

**1. Im NetBox-Container** (als root; der Worker läuft als User `netbox`, bei Docker-Images oft `unit`):

```bash
mkdir -p /opt/cfm
cp netbox-abgleich.py /opt/cfm/              # aus tools/ dieses Repos, bei jedem Framework-Update mit erneuern
ssh-keygen -t ed25519 -N "" -C cfm-netbox@netbox -f /opt/cfm/cfm-netbox.key
touch /opt/cfm/known_hosts
chown -R netbox:netbox /opt/cfm && chmod 600 /opt/cfm/cfm-netbox.key
cat /opt/cfm/cfm-netbox.key.pub              # -> authorized_keys.cfm-netbox (Schritt 2)
```

`/etc/cfm-netbox.json`, ein Eintrag je Site (Slug in NetBox) mit ihrem Primary-Manager:

```json
{"tool": "/opt/cfm/netbox-abgleich.py", "key": "/opt/cfm/cfm-netbox.key", "known_hosts": "/opt/cfm/known_hosts",
 "sites": {"<slug>": {"manager": "cfm-netbox@192.168.10.2", "port": 22, "vlan_group": null}}}
```

Bei `manager` trägst du die Adresse ein, unter der der Container den Manager erreicht. Liegt der Manager an einem
anderen Standort, ist das z.B. die Adresse auf der Kopplung. Die Ablage (`cfm` oder `flash/cfm`) kennt der Manager.
`vlan_group` gibst du an, wenn die VLANs in NetBox in einer VLAN-Gruppe statt an der Site hängen.

**2. In cfm** (Site-Daten, z.B. im cfm-Editor):

* `global.rsc`: `"netbox"={"from"={"<IP des Containers>/32"}}`
* Den öffentlichen Schlüssel aus Schritt 1 als Datei `authorized_keys.cfm-netbox` nach `work/` legen
  (`upload-seed.sh --site` lädt sie aus dem Overlay mit hoch).
* `$cfmCheck`, dann `$cfmRelease`. Hat der Primary-Manager die Version angewendet, gibt es dort den User `cfm-netbox`,
  das Skript `cfm-netbox-run` und die SSH-Freigabe für die Adresse.

**3. Von Hand testen** (im Container, als der User des Workers):

```bash
sudo -u netbox ssh -i /opt/cfm/cfm-netbox.key -o UserKnownHostsFile=/opt/cfm/known_hosts \
  -o StrictHostKeyChecking=accept-new cfm-netbox@<manager> '/system script run cfm-netbox-run'
# -> CFMNB=<Anzahl Geräte>, danach die Dateien (##CFMF …)
sudo -u netbox python3 /opt/cfm/netbox-abgleich.py --netbox … --site <slug> --token-file … \
  --manager cfm-netbox@<manager> --lesend --key /opt/cfm/cfm-netbox.key    # optional, mit API-Token
```

**4. Skript in NetBox laden:** `cfm_abgleich.py` aus diesem Verzeichnis.

* NetBox 4.x: *Anpassen → Skripte → + Hinzufügen*, Datei hochladen.
* NetBox 3.7: Datei nach `SCRIPTS_ROOT` kopieren, Standard `/opt/netbox/netbox/scripts/`.

Ein anderer Ort für die Einstellungen geht über die Umgebungsvariable `CFM_NETBOX_CONFIG` des Workers.

## Fehler

| Meldung | Ursache |
|---|---|
| `Site <slug> fehlt in /etc/cfm-netbox.json` | Eintrag unter `sites` fehlt oder der Slug ist anders |
| `cfm-netbox-run auf …: keine Ausgabe` | `global.rsc netbox` fehlt oder das Release ist auf dem Manager noch nicht angewendet |
| `SSH zu …: Permission denied` | `authorized_keys.cfm-netbox` fehlt, falscher Schlüssel, oder die Adresse steht nicht in `netbox.from` |
| `SSH zu …: Connection timed out` | Weg zum Manager (Routing, Firewall außerhalb von cfm) |

Tests: `tools/netbox/cfm_abgleich-test.py`. Sie prüfen, dass die Abbildung der NetBox-Objekte denselben Plan
ergibt wie der REST-Weg. Im Labor: `e2e.sh` Schritt 14o (User, Skript, Ausgabe der Dateien gleich SFTP, Abgleich mit
`--lesend`).
