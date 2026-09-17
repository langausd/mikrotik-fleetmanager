#!/usr/bin/env python3
"""new-site – eine lokale Site (Overlay für tools/upload-seed.sh) aus den Beispieldaten anlegen.

Kopiert die neutralen Beispieldaten aus cfm/work und cfm/meta in ein neues Verzeichnis, setzt
Manager-Name, Uplink, Admin-User und mgmtExtra ein und legt dazu an:
  CHECKLISTE.md          was vor dem Einsatz zu prüfen und zu ergänzen ist
  bootstrap-manager.rsc  bootstrap/bootstrap-manager.rsc mit ausgefülltem Kopf
Beide lädt tools/upload-seed.sh nicht mit hoch.

Aufruf:
  tools/new-site.py site-lab
  tools/new-site.py site-lab --name cm-lab --uplink ether2 --user netadmin --mgmt-extra 192.168.10.100/32
Verzeichnisse site/ und site-*/ im Repo ignoriert Git.
"""
import argparse
import datetime
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, "cfm", "work")
DATA = ["global.rsc", "vlans.rsc", "profiles.rsc", "wifi.rsc", "wireguard.rsc"]


def read(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def write(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as fh:
        fh.write(s)


def sub1(s, pattern, repl, what):
    s2, n = re.subn(pattern, repl, s, count=1, flags=re.M)
    if n != 1:
        sys.exit(f"new-site: {what} nicht gefunden (Beispieldaten geändert?)")
    return s2


def find(pattern, s, what):
    m = re.search(pattern, s, re.M)
    if not m:
        sys.exit(f"new-site: {what} nicht gefunden (Beispieldaten geändert?)")
    return m.group(1)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Lokale Site aus den Beispieldaten anlegen (Overlay für upload-seed.sh).")
    ap.add_argument("ziel", help="neues Verzeichnis, z.B. site-lab")
    ap.add_argument("--name", help="Name des Primary-Managers (Standard: wie in den Beispieldaten)")
    ap.add_argument("--uplink", default="ether1", help="Port des Managers mit dem MGMT-VLAN, getaggt (Standard: ether1)")
    ap.add_argument("--user", help="Admin-Benutzer statt dem aus den Beispieldaten")
    ap.add_argument("--mgmt-extra", action="append", default=[], metavar="CIDR",
                    help="Netz/Host mit Management-Zugriff, z.B. dein Admin-PC (mehrfach möglich)")
    ap.add_argument("--force", action="store_true", help="auch in ein vorhandenes, nicht leeres Verzeichnis schreiben")
    a = ap.parse_args(argv)

    ziel = os.path.abspath(a.ziel)
    if os.path.exists(ziel) and os.listdir(ziel) and not a.force:
        sys.exit(f"new-site: {a.ziel} existiert und ist nicht leer (--force zum Überschreiben)")
    for n in a.mgmt_extra:
        if not re.fullmatch(r"\d{1,3}(\.\d{1,3}){3}(/\d{1,2})?", n):
            sys.exit(f"new-site: --mgmt-extra {n}: erwartet a.b.c.d oder a.b.c.d/nn")

    # Beispieldaten lesen
    g = read(os.path.join(WORK, "global.rsc"))
    inv = read(os.path.join(ROOT, "cfm", "meta", "inventory.rsc"))
    mv = find(r'"mgmtVlan"=(\d+);', g, "mgmtVlan")
    ip = find(r'"managers"=\{"([\d.]+)"', g, "managers")
    old = find(r'^\s*"([^"]+)"=\{[^}]*"ip"="' + re.escape(ip) + '"', inv, "Manager im Inventar")
    role = find(r'^\s*"' + re.escape(old) + r'"=\{[^}]*"role"="([^"]+)"', inv, "Rolle des Managers")
    user = find(r'"users"=\{"([^"]+)"=', g, "users")
    vl = read(os.path.join(WORK, "vlans.rsc"))
    ventry = find(r'^\s*"' + mv + r'"=\{([^}]*)\}', vl, f"VLAN {mv} in vlans.rsc")
    gwhost = re.search(r'"gw"=(\d+)', ventry)
    gw = ".".join(ip.split(".")[:3] + [gwhost.group(1) if gwhost else "1"])
    name = a.name or old
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", name):
        sys.exit(f"new-site: --name {name}: nur Buchstaben, Ziffern, - und _")

    # Daten kopieren
    os.makedirs(ziel, exist_ok=True)
    for f in DATA:
        shutil.copy(os.path.join(WORK, f), os.path.join(ziel, f))
    shutil.copytree(os.path.join(WORK, "hosts"), os.path.join(ziel, "hosts"), dirs_exist_ok=True)
    write(os.path.join(ziel, "meta", "inventory.rsc"), inv)

    # Manager-Name: Inventar-Schlüssel, Hostfile, Verweise in den Daten
    if name != old:
        os.replace(os.path.join(ziel, "hosts", old + ".rsc"), os.path.join(ziel, "hosts", name + ".rsc"))
        word = re.compile(r"(?<![A-Za-z0-9_-])" + re.escape(old) + r"(?![A-Za-z0-9_-])")
        for d, _, fs in os.walk(ziel):
            for f in fs:
                if f.endswith(".rsc"):
                    p = os.path.join(d, f)
                    write(p, word.sub(name, read(p)))
    # Manager-Hostfile: nur der Uplink als Trunk (Ports, die es nicht gibt, ließen den Apply scheitern)
    hp = os.path.join(ziel, "hosts", name + ".rsc")
    write(hp, sub1(read(hp), r'"ports"=\{[^}]*\}', f'"ports"={{"{a.uplink}"="trunk"}}', "ports im Manager-Hostfile"))
    # global.rsc: Admin-User, mgmtExtra
    gp = os.path.join(ziel, "global.rsc")
    s = read(gp)
    if a.user:
        s = sub1(s, r'"users"=\{"[^"]+"=', f'"users"={{"{a.user}"=', "users")
        user = a.user
    if a.mgmt_extra:
        s = sub1(s, r'"mgmtExtra"=\{[^}]*\}', '"mgmtExtra"={' + ";".join(f'"{n}"' for n in a.mgmt_extra) + "}", "mgmtExtra")
    write(gp, s)

    # bootstrap-manager.rsc mit ausgefülltem Kopf
    b = read(os.path.join(ROOT, "bootstrap", "bootstrap-manager.rsc"))
    for key, val in (("myname", f'"{name}"'), ("ip", f'"{ip}/24"'), ("uplink", f'"{a.uplink}"'), ("mv", mv),
                     ("gw", f'"{gw}"'), ("role", f'"{role}"')):
        b = sub1(b, r'^(:local ' + key + r' )(?:"[^"]*"|\d+)', r"\g<1>" + val.replace("\\", "\\\\"), f"{key} im Bootstrap-Kopf")
    heute = datetime.date.today().isoformat()
    write(os.path.join(ziel, "bootstrap-manager.rsc"),
          f"# Kopf ausgefüllt von tools/new-site.py für {os.path.basename(ziel)} am {heute}\n" + b)

    # Checkliste
    geraete = re.findall(r'^\s*"([^"]+)"=\{', read(os.path.join(ziel, "meta", "inventory.rsc")), re.M)
    extra = ", ".join(a.mgmt_extra) if a.mgmt_extra else "leer – ohne Eintrag erreichst du die Geräte nur aus dem MGMT-VLAN"
    rel = os.path.relpath(ziel, ROOT) if ziel.startswith(ROOT + os.sep) else ziel
    write(os.path.join(ziel, "CHECKLISTE.md"), f"""# Checkliste für die Site {os.path.basename(ziel)}

Angelegt am {heute} mit `tools/new-site.py` aus den neutralen Beispieldaten. `CHECKLISTE.md` und
`bootstrap-manager.rsc` lädt `tools/upload-seed.sh` nicht mit hoch.

## Werte dieser Site

| | |
|---|---|
| MGMT-VLAN | {mv} (Netz {".".join(ip.split(".")[:3])}.0/24, Gateway {gw}) |
| Primary-Manager | {name}, {ip}, Uplink `{a.uplink}` (MGMT-VLAN getaggt), Rolle `{role}` |
| Admin-Benutzer | `{user}` (Passwort nur per `$cfmSecret key=user.{user} value=…`) |
| mgmtExtra | {extra} |
| Geräte im Inventar | {", ".join(geraete)} |

## Vor dem Einsatz

- [ ] **Adressen:** Passt das Beispielnetz? Sonst in `global.rsc` `mgmtVlan`, `managers`, `ntp`, `dns`,
      `syslog`, in `vlans.rsc` die VLANs und in `meta/inventory.rsc` die `ip`-Werte ändern (und den
      Kopf von `bootstrap-manager.rsc`).
- [ ] **Zugang:** `mgmtExtra` in `global.rsc` enthält deinen Admin-PC oder dessen Netz. Nicht-Router
      verwerfen alles andere.
- [ ] **Gateway** {gw} im MGMT-VLAN vorhanden (Default-Route, DNS und NTP der Geräte), bis ein
      cfm-Router es übernimmt.
- [ ] **Inventar:** nur die Geräte des Tests behalten, Namen, Rollen, Ringe und MGMT-IPs anpassen.
      Seriennummern trägt die Aufnahme ein.
- [ ] **Hostfiles** in `hosts/`: je Gerät eins, Uplink immer mit Trunk-Profil, nur Ports, die es auf
      dem Gerät gibt. `hosts/{name}.rsc` enthält nur den Uplink `{a.uplink}`.
- [ ] **WLAN** in `wifi.rsc`: Land, SSIDs (im Test eigene Namen), Kanäle.
- [ ] **Optional:** `wireguard.rsc` (Fernzugang, nur mit Rolle `router`, Admin-Guide 8.8) und
      `authorized_keys` (persönliche SSH-Keys, Admin-Guide Kapitel 4).
- [ ] **Prüfen:** `tools/rsc-check.py {rel}` ohne Fund.

## Manager aufsetzen

- [ ] Seed hochladen (beim ersten Mal mit Inventar):
      `tools/upload-seed.sh admin@<aktuelle-IP> --overlay {rel} --seed-inventory`
- [ ] `{rel}/bootstrap-manager.rsc` als `bootstrap-manager.rsc` ins Wurzelverzeichnis des Managers
      laden, Kopf kontrollieren, `/import bootstrap-manager.rsc` (Reset auf leere Config, danach
      im Log `cfm: Primary-Manager bereit`)
- [ ] Secrets: `$cfmSecret key=user.{user} value=…`, `key=psk.<ssid>` je SSID, `key=vaultpw`
- [ ] `$cfmStatus`: {name} ok mit v1

## Geräte aufnehmen (Admin-Guide Abschnitt 7)

- [ ] manuell: `$cfmBootstrap`, Datei aufs Gerät, `/import cfm-bootstrap.rsc`, dann
      `$cfmEnroll name=<n> ip=<MGMT-IP> role=<rolle> ring=<r>`
- [ ] automatisch: `$cfmRegister name=<n> serial=<SN> ip=<MGMT-IP> role=<rolle> ring=<r> pw="<Aufkleber>"`,
      `$cfmOnboard sw=<switch> port=<port> name=<n>`
""")

    # Prüfen und Hinweise
    rc = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "rsc-check.py"), ziel])
    if ziel.startswith(ROOT + os.sep):
        ign = subprocess.run(["git", "-C", ROOT, "check-ignore", "-q", ziel]).returncode == 0
        if not ign:
            print(f"new-site: ACHTUNG, {rel} wird von Git nicht ignoriert – Namen site/ oder site-*/ verwenden",
                  file=sys.stderr)
    print(f"new-site: {rel} angelegt ({len(geraete)} Geräte im Inventar). Weiter mit {rel}/CHECKLISTE.md")
    return rc.returncode


if __name__ == "__main__":
    sys.exit(main())
