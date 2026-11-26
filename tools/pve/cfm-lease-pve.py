#!/usr/bin/env python3
"""cfm-lease-pve – Gäste eines Proxmox-Hosts als feste Lease in cfm eintragen (TODO 102, DN1.3).

Läuft auf dem PVE-Host als root. Für jeden Gast (VM oder Container) mit dem Tag aus TAG (Standard "cfm") liest es
Name, MAC und VLAN von net0 und ruft am Primary-Manager das Skript cfm-lease auf (User cfm-lease per SSH-Key,
global.rsc lease). Der Manager wählt die Adresse (erste freie außerhalb des DHCP-Pools), schreibt leases.rsc und gibt
ein Release heraus. Ist die Lease schon da (gleicher Name, VLAN und MAC), ändert er nichts.

Aufruf:
  cfm-lease-pve.py sweep              alle Gäste mit dem Tag (systemd-Timer cfm-lease-pve.timer)
  cfm-lease-pve.py hook               für var_post_install der Proxmox Community Scripts (Umgebung CTID, HN):
                                      setzt beim neuen Container den Tag und trägt ihn sofort ein
  cfm-lease-pve.py add <vmid>         einen Gast eintragen (auch ohne Tag)
  cfm-lease-pve.py sweep --probe      nur zeigen, was es täte (ruft den Manager nicht auf)
Konfiguration: /etc/cfm-lease-pve.conf (Shell-Format KEY=wert, siehe cfm-lease-pve.conf.example), Pfad per
CFM_LEASE_CONF. Exit-Code: 0 = alles eingetragen oder schon da, 1 = mindestens ein Fehler, 2 = Bedienfehler.

Der Name der Lease ist der VM-Name bzw. der Hostname des Containers, als DNS-Label (Buchstaben, Ziffern, "-",
höchstens 63 Zeichen). VLAN: tag= von net0, sonst VLAN_MAP (Bridge=VLAN) bzw. DEFAULT_VLAN. Container mit fester
IPv4 in net0 (ip=<Adresse>) werden übersprungen: Sie fragen nicht per DHCP.
"""
import json
import os
import re
import shlex
import socket
import subprocess
import sys

CONF = os.environ.get("CFM_LEASE_CONF", "/etc/cfm-lease-pve.conf")
DEFAULTS = {"MANAGER": "", "PORT": "22", "KEY": "/etc/cfm-lease-pve/id_ed25519", "KNOWN_HOSTS": "/etc/cfm-lease-pve/known_hosts",
            "TAG": "cfm", "DEFAULT_VLAN": "", "VLAN_MAP": "", "ACME": "no", "STATE": "/var/lib/cfm-lease-pve",
            "NODE": ""}


def load_conf(path=CONF):
    c = dict(DEFAULTS)
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                v = " ".join(shlex.split(v)) if v.strip() else ""
                c[k.strip()] = v
    return c


def run(cmd, inp=None):
    p = subprocess.run(cmd, input=inp, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def parse_kv(s):
    """'virtio=02:00:00:..,bridge=vmbr0,tag=30' -> dict (das erste Feld ohne = wird 'model')."""
    d = {}
    for part in s.split(","):
        if "=" in part:
            k, v = part.split("=", 1)
            d[k.strip()] = v.strip()
    return d


def parse_config(text):
    """Ausgabe von 'qm config' / 'pct config' -> dict."""
    d = {}
    for line in text.splitlines():
        if ":" in line and not line.startswith("#"):
            k, v = line.split(":", 1)
            d[k.strip()] = v.strip()
    return d


MODELS = ("virtio", "e1000", "e1000e", "rtl8139", "vmxnet3", "ne2k_pci", "pcnet", "i82551", "i82557b", "i82559er")


def guest_net(kind, cfg):
    """-> (mac, bridge, tag, static_ip) aus net0."""
    n = parse_kv(cfg.get("net0", ""))
    mac = ""
    if kind == "lxc":
        mac = n.get("hwaddr", "")
    else:
        for m in MODELS:
            if m in n:
                mac = n[m]
                break
        mac = mac or n.get("macaddr", "")
    ip = n.get("ip", "") if kind == "lxc" else ""
    static = ip if ip and ip not in ("dhcp", "manual") else ""
    return mac.upper(), n.get("bridge", ""), n.get("tag", ""), static


def lease_name(s):
    s = re.sub(r"[^A-Za-z0-9-]+", "-", s or "").strip("-")
    s = re.sub(r"-{2,}", "-", s)[:63].strip("-")
    return s


def guest_tags(cfg):
    return [t for t in re.split(r"[;, ]+", cfg.get("tags", "")) if t]


def vlan_for(c, bridge, tag):
    if tag:
        return tag
    for pair in c.get("VLAN_MAP", "").split():
        if "=" in pair:
            b, v = pair.split("=", 1)
            if b == bridge:
                return v
    return c.get("DEFAULT_VLAN", "")


def node_name(c):
    return c.get("NODE") or socket.gethostname().split(".")[0]


def list_guests(c):
    """-> [(kind, vmid)] dieses Knotens."""
    out = []
    for kind in ("qemu", "lxc"):
        rc, so, se = run(["pvesh", "get", "/nodes/%s/%s" % (node_name(c), kind), "--output-format", "json"])
        if rc != 0:
            print("Fehler: pvesh %s: %s" % (kind, se.strip()), file=sys.stderr)
            continue
        for g in json.loads(so or "[]"):
            out.append(("lxc" if kind == "lxc" else "qemu", str(g.get("vmid"))))
    return sorted(out, key=lambda x: int(x[1]))


def guest_config(kind, vmid):
    rc, so, se = run(["pct" if kind == "lxc" else "qm", "config", vmid])
    if rc != 0:
        raise RuntimeError("%s config %s: %s" % ("pct" if kind == "lxc" else "qm", vmid, se.strip()))
    return parse_config(so)


def plan_guest(c, kind, vmid, cfg):
    """-> (args, grund): args = Text für $cfmLeaseArg oder None, grund = warum nicht."""
    mac, bridge, tag, static = guest_net(kind, cfg)
    name = lease_name(cfg.get("hostname") if kind == "lxc" else cfg.get("name"))
    if not cfg.get("net0"):
        return None, "kein net0"
    if static:
        return None, "feste Adresse %s in net0" % static
    if not name:
        return None, "kein Name"
    if not re.match(r"^([0-9A-F]{2}:){5}[0-9A-F]{2}$", mac):
        return None, "keine MAC in net0"
    vlan = vlan_for(c, bridge, tag)
    if not re.match(r"^[0-9]+$", vlan or ""):
        return None, "kein VLAN (tag= in net0, VLAN_MAP oder DEFAULT_VLAN)"
    a = "add name=%s vlan=%s mac=%s" % (name, vlan, mac)
    if c.get("ACME") == "yes":
        a += " acme=yes"
    return a, ""


def state_file(c, vmid):
    return os.path.join(c["STATE"], "%s.done" % vmid)


def remote(c, args):
    """cfm-lease am Manager aufrufen -> (ok, Ausgabezeilen)."""
    if not c.get("MANAGER"):
        return False, ["MANAGER fehlt in %s" % CONF]
    cmd = ":global cfmLeaseArg \"%s\"; /system script run cfm-lease" % args
    ssh = ["ssh", "-p", c["PORT"], "-i", c["KEY"], "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
           "-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=%s" % c["KNOWN_HOSTS"], c["MANAGER"], cmd]
    rc, so, se = run(ssh)
    lines = [l.rstrip("\r") for l in (so + se).splitlines() if l.strip()]
    ok = any(l.startswith("ERGEBNIS ok") for l in lines)
    return ok, lines


def do_guest(c, kind, vmid, cfg, probe=False, force=False):
    args, why = plan_guest(c, kind, vmid, cfg)
    if not args:
        print("%s: übersprungen (%s)" % (vmid, why))
        return True
    sf = state_file(c, vmid)
    if not force and os.path.exists(sf) and open(sf).read().strip() == args:
        return True
    if probe:
        print("%s: würde eintragen: %s" % (vmid, args))
        return True
    ok, lines = remote(c, args)
    for l in lines:
        if l.startswith(("LEASE", "RELEASE", "CNAME", "ERGEBNIS", "Warnung", "Hinweis")):
            print("%s: %s" % (vmid, l))
    if ok:
        os.makedirs(c["STATE"], exist_ok=True)
        with open(sf, "w") as f:
            f.write(args + "\n")
    elif not lines:
        print("%s: keine Antwort vom Manager" % vmid)
    return ok


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    probe = "--probe" in argv
    force = "--force" in argv
    argv = [a for a in argv if a not in ("--probe", "--force")]
    if not argv or argv[0] not in ("sweep", "hook", "add"):
        print(__doc__.split("Konfiguration:")[0], file=sys.stderr)
        return 2
    c = load_conf()
    ok = True
    if argv[0] == "sweep":
        for kind, vmid in list_guests(c):
            try:
                cfg = guest_config(kind, vmid)
            except RuntimeError as e:
                print("Fehler: %s" % e, file=sys.stderr)
                ok = False
                continue
            if c["TAG"] in guest_tags(cfg):
                ok = do_guest(c, kind, vmid, cfg, probe, force) and ok
    elif argv[0] == "hook":
        vmid = os.environ.get("CTID", "")
        if not re.match(r"^[0-9]+$", vmid):
            print("hook: CTID fehlt (var_post_install der Community Scripts)", file=sys.stderr)
            return 2
        cfg = guest_config("lxc", vmid)
        tags = guest_tags(cfg)
        if c["TAG"] not in tags and not probe:
            run(["pct", "set", vmid, "--tags", ";".join(tags + [c["TAG"]])])
        ok = do_guest(c, "lxc", vmid, cfg, probe, force)
    else:
        if len(argv) < 2 or not re.match(r"^[0-9]+$", argv[1]):
            print("add <vmid>", file=sys.stderr)
            return 2
        vmid = argv[1]
        kind = next((k for k, v in list_guests(c) if v == vmid), None)
        if not kind:
            print("Gast %s nicht auf diesem Knoten" % vmid, file=sys.stderr)
            return 2
        ok = do_guest(c, kind, vmid, guest_config(kind, vmid), probe, force)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
