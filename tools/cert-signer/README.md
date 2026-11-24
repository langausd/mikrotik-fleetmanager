# Signer für Gerätezertifikate (`tools/cert-signer/`, DS3.6)

Der Signer signiert die CSRs der cfm-Geräte bei einer öffentlichen CA (Let's Encrypt per DNS-01 über
[acme-dns](https://github.com/joohoi/acme-dns)) und stößt die Manager an. Er läuft auf einem Linux-Host, am
einfachsten auf dem acme-dns-Server selbst. Schlüssel sieht er nie – die erzeugt jedes Gerät selbst. Hintergrund:
DS3.6 in [DECISIONS](../../docs/DECISIONS.md), Admin-Guide 8.20.

| Datei | Zweck |
|---|---|
| `cfm-cert-signer.py` | liest je Manager `state/<gerät>/tls.csr` (SSH als `cfm-cert`), prüft und signiert neue CSRs, legt `<outdir>/<name>.<domain>.pem` ab, startet `cfm-cert-pull` |
| `acme-dns-auth.py` | certbot-Hook für acme-dns; `--register <schlüssel> [cidr …]` legt ein Konto an, `ACMEDNS_ACCOUNT` wählt es für alle Namen |
| `cfm-cert-signer.example.json` | Beispielkonfiguration (`/etc/cfm-cert-signer.json`) |
| `cfm-cert-signer.service`, `.timer` | Lauf alle 10 Minuten |
| `cfm-cert-http.service` | liefert `/srv/cfm-certs` per HTTP auf Port 8080 aus (nur öffentliche Zertifikate) |

## Einrichten (Debian, certbot und acme-dns laufen schon)

```bash
apt install certbot openssh-client python3
install -m 755 cfm-cert-signer.py /usr/local/sbin/
install -d -m 700 /etc/letsencrypt/acme-dns /etc/cfm-cert-signer
install -m 700 acme-dns-auth.py /etc/letsencrypt/acme-dns/
install -d -m 755 /srv/cfm-certs; install -d -m 700 /var/lib/cfm-cert-signer

# ein acme-dns-Konto für alle Geräte (Updates nur von hier) - druckt das CNAME-Ziel
/etc/letsencrypt/acme-dns/acme-dns-auth.py --register cfm-mikrotik 127.0.0.1/32

# SSH-Key für den Lesezugang am Manager; der öffentliche Teil kommt nach work/authorized_keys.cfm-cert
ssh-keygen -t ed25519 -N "" -C cfm-cert-signer -f /etc/cfm-cert-signer/id_ed25519

cp cfm-cert-signer.example.json /etc/cfm-cert-signer.json   # managers, domains, cname_target anpassen
install -m 644 cfm-cert-*.service cfm-cert-signer.timer /etc/systemd/system/
systemctl daemon-reload; systemctl enable --now cfm-cert-http.service cfm-cert-signer.timer
```

Danach:

* **DNS:** je Gerät `_acme-challenge.<name>.<domain> CNAME <cname_target>` (dasselbe Ziel für alle). Ein Gerät, das
  neu dazukommt, braucht nur diesen Eintrag – keine neue Registrierung. `cfm-cert-signer.py -c … --cnames` gibt die
  Zeilen für alle bekannten Namen aus.
* **Firewall des Signers:** Port 8080 nur für die Manager öffnen; die acme-dns-API nur für localhost bzw. die Hosts mit
  eigenem Client.
* **Manager:** `tls` in `global.rsc` (Admin-Guide 8.20), `authorized_keys.cfm-cert`, Release.
* **Erster Test:** `cfm-cert-signer.py -c /etc/cfm-cert-signer.json --dry-run` liest die CSRs und nennt, was er
  signieren würde. Mit `"staging": true` zuerst gegen die Staging-Umgebung von Let's Encrypt (Browser vertrauen
  diesen Zertifikaten nicht, die Geräte nehmen sie trotzdem – gut zum Prüfen des Ablaufs).

## Was der Signer prüft

* CSR-Signatur gültig, CN unter einer der `domains`, keine weiteren Namen im SAN.
* Ein CSR mit schon signiertem öffentlichem Schlüssel wird nicht noch einmal signiert (`state`); `--force <CN>`
  erzwingt es. Die Erneuerung löst das Gerät aus (neuer Schlüssel, `tls.renew` in `global.rsc`).
* Das ausgestellte Zertifikat muss zum öffentlichen Schlüssel des CSR passen, sonst wird es verworfen.

Let's Encrypt begrenzt neue Zertifikate je registrierter Domain (50 je Woche) und gleiche Namensmengen (5 je Woche) –
für eine Flotte von 5–20 Geräten weit genug, aber kein Grund, `--force` in einer Schleife laufen zu lassen.

## Labor

`tools/chr-lab/e2e.sh` Schritt 14n nutzt `"mode": "testca"`: eine Test-CA mit Zwischenzertifikat (openssl) statt
certbot, sonst derselbe Ablauf (SSH über den Forward von cm1, HTTP auf dem Host).
