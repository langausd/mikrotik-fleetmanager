#!/usr/bin/python3
"""certbot --manual-auth-hook fuer acme-dns.

Zugangsdaten je Domain in accounts.json (Format wie acme-dns-certbot-joohoi):
  {"name.example.org": {"username": ..., "password": ..., "fulldomain": ..., "subdomain": ..., "allowfrom": [...]}}
Neue Namen registriert:  acme-dns-auth.py --register <name> [allowfrom-cidr ...]
Mit ACMEDNS_ACCOUNT=<schluessel> nimmt der Hook dieses Konto statt des Domainnamens - so teilen sich
viele Namen ein Konto (cfm-cert-signer.py, DS3.6: alle Geraete einer Flotte zeigen per CNAME auf dieselbe
Subdomain; der Signer arbeitet die Namen nacheinander ab, acme-dns haelt je Subdomain zwei TXT-Werte).
"""
import json, os, sys, urllib.request

API = os.environ.get("ACMEDNS_URL", "http://127.0.0.1")
STORE = "/etc/letsencrypt/acme-dns/accounts.json"

def load():
    try:
        with open(STORE) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

def save(d):
    tmp = STORE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(d, f, indent=2, sort_keys=True)
    os.replace(tmp, STORE)

def post(path, body, headers=None):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", **(headers or {})})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)

def register(name, allow):
    d = load()
    if name in d:
        acc = d[name]
    else:
        acc = post("/register", {"allowfrom": allow} if allow else {})
        d[name] = acc
        save(d)
    print("_acme-challenge.%s.  CNAME  %s." % (name, acc["fulldomain"]))

def auth():
    name = os.environ["CERTBOT_DOMAIN"]
    if name.startswith("*."):
        name = name[2:]
    acc = load().get(os.environ.get("ACMEDNS_ACCOUNT") or name)
    if not acc:
        sys.exit("acme-dns-auth: kein Konto fuer %s - erst --register %s" % (name, name))
    post("/update", {"subdomain": acc["subdomain"], "txt": os.environ["CERTBOT_VALIDATION"]},
         {"X-Api-User": acc["username"], "X-Api-Key": acc["password"]})

if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--register":
        register(sys.argv[2], sys.argv[3:])
    else:
        auth()
