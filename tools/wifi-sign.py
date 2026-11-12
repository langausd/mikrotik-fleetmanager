#!/usr/bin/env python3
"""wifi-sign.py – WLAN-Schild als A4-PDF: QR-Code, SSID und Passphrase, zweisprachig (de/en).

Wofür: Ein Schild fürs Gäste-WLAN (oder jede andere SSID) zum Aushängen. Der QR-Code nutzt das übliche
Format für WLAN-Zugänge (WIFI:T:…;S:…;P:…;;) – iOS und Android verbinden sich direkt aus der Kamera.

  tools/wifi-sign.py --overlay site-b --ssid guest --manager netadmin@192.168.10.1
  tools/wifi-sign.py --overlay site-b --ssid guest -o ~/Schilder/gast.pdf   # Passphrase abfragen
  echo -n 'geheim' | tools/wifi-sign.py --name Demo-Gast --passphrase-stdin

Die SSID kommt aus wifi.rsc des Overlays ("ssids" -> <Schlüssel> -> "ssid", Verschlüsselung aus "sec" bzw.
"defaults"). Die Passphrase liegt nur im Vault des Managers (cfm:psk.<Schlüssel>): mit --manager liest das
Tool sie per SSH (/ppp/secret, braucht einen Admin mit Lese- und sensitive-Rechten), sonst fragt es verdeckt.
Sie landet nur im PDF – das Tool schreibt es mit Rechten 0600; nicht ins Repo legen.

Braucht segno (QR) und pycairo (PDF): Debian/Ubuntu `sudo apt install python3-segno python3-cairo`.
"""
import argparse
import getpass
import os
import re
import subprocess
import sys

A4 = (595.276, 841.89)  # Punkte (1/72 Zoll)
MM = 72 / 25.4

TEXT = {
    "title": ("Gäste-WLAN", "Guest Wi-Fi"),
    "wlan": ("WLAN", "Wi-Fi"),
    "ssid": ("Netzwerk", "Network"),
    "pass": ("Passwort", "Password"),
    "scan": ("QR-Code mit der Kamera scannen", "Scan the QR code with your camera"),
}


def parse_wifi(path):
    """Liest aus wifi.rsc die Felder "defaults" und "ssids" (je SSID-Schlüssel ein Dict)."""
    with open(path, encoding="utf-8") as f:
        txt = f.read()
    # Kommentarzeilen weg, sonst stören Beispiele wie "ppsk"={"test"=…}
    txt = "\n".join(l for l in txt.splitlines() if not l.lstrip().startswith("#"))
    pairs = lambda s: dict(re.findall(r'"([A-Za-z0-9_]+)"\s*=\s*"([^"]*)"', s))
    d = re.search(r'"defaults"\s*=\s*\{([^{}]*)\}', txt)
    defaults = pairs(d.group(1)) if d else {}
    m = re.search(r'"ssids"\s*=\s*\{', txt)
    ssids = {}
    if m:
        i, depth, start = m.end(), 1, m.end()
        while i < len(txt) and depth:
            depth += {"{": 1, "}": -1}.get(txt[i], 0)
            i += 1
        for key, body in re.findall(r'"([A-Za-z0-9_-]+)"\s*=\s*\{([^{}]*)\}', txt[start:i - 1]):
            ssids[key] = pairs(body)
    return defaults, ssids


def auth_type(sec):
    """WIFI-QR "T:": WPA für WPA2 (auch gemischt mit WPA3), SAE nur bei reinem WPA3, nopass ohne Schlüssel."""
    s = (sec or "").lower()
    if not s or s == "none":
        return "nopass"
    if "wpa3" in s and "wpa2" not in s and "wpa-" not in s:
        return "SAE"
    return "WPA"


def esc(s):
    """Sonderzeichen im WIFI-QR mit Backslash maskieren: \\ ; , : \""""
    return re.sub(r'([\\;,:"])', r"\\\1", s)


def qr_payload(ssid, passphrase, typ, hidden=False):
    p = "WIFI:T:%s;S:%s;" % (typ, esc(ssid))
    if typ != "nopass":
        p += "P:%s;" % esc(passphrase)
    if hidden:
        p += "H:true;"
    return p + ";"


def from_manager(target, key, port=None):
    """Passphrase aus dem Vault des Managers (deaktiviertes /ppp secret cfm:psk.<key>) per SSH."""
    cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
    if port:
        cmd += ["-p", str(port)]
    name = "cfm:psk." + key
    cmd += [target, ':local i [/ppp/secret/find where name="%s"]; :if ([:len $i] = 0) do={ :put "P-" } else={ :put ("P=" . [/ppp/secret/get $i password]) }' % name]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    for line in out.stdout.replace("\r", "").splitlines():
        if line.startswith("P="):
            return line[2:]
        if line.startswith("P-"):
            sys.exit("Vault: %s fehlt auf dem Manager ($cfmSecret key=psk.%s value=…)" % (name, key))
    sys.exit("Passphrase nicht gelesen (ssh %s): %s" % (target, (out.stderr or out.stdout).strip()[:200]))


def fit(ctx, text, family, weight, max_w, size):
    """Größte Schrift <= size, bei der text in max_w passt."""
    import cairo
    ctx.select_font_face(family, cairo.FONT_SLANT_NORMAL, weight)
    while size > 6:
        ctx.set_font_size(size)
        if ctx.text_extents(text).x_advance <= max_w:
            break
        size -= 0.5
    return size


def centered(ctx, text, y, family, weight, size, max_w, rgb=(0, 0, 0)):
    import cairo
    size = fit(ctx, text, family, weight, max_w, size)
    ctx.set_source_rgb(*rgb)
    ext = ctx.text_extents(text)
    ctx.move_to((A4[0] - ext.x_advance) / 2, y)
    ctx.show_text(text)
    return size


def wrap_mono(text, per_line):
    return [text[i:i + per_line] for i in range(0, len(text), per_line)] or [""]


def render(out, ssid, passphrase, typ, title=None, hint=None, hidden=False):
    import cairo
    import segno
    qr = segno.make(qr_payload(ssid, passphrase, typ, hidden), error="m", micro=False)
    surf = cairo.PDFSurface(out, *A4)
    surf.set_metadata(cairo.PDF_METADATA_TITLE, "WLAN %s" % ssid)
    ctx = cairo.Context(surf)
    W = A4[0]
    margin = 18 * MM
    max_w = W - 2 * margin
    sans, mono = "DejaVu Sans", "DejaVu Sans Mono"
    bold, normal = cairo.FONT_WEIGHT_BOLD, cairo.FONT_WEIGHT_NORMAL
    grey = (0.35, 0.35, 0.35)

    y = margin + 16 * MM
    t_de, t_en = title.split("|", 1) if title and "|" in title else ((title, title) if title else TEXT["title"])
    centered(ctx, t_de, y, sans, bold, 40, max_w)
    y += 13 * MM
    if t_en != t_de:
        centered(ctx, t_en, y, sans, normal, 26, max_w, grey)
    y += 10 * MM

    # QR-Code: Module als Rechtecke, Ruhezone 4 Module (in der Matrix nicht enthalten)
    side = 120 * MM
    n = len(qr.matrix)
    mod = side / (n + 8)
    x0 = (W - side) / 2
    ctx.set_source_rgb(0, 0, 0)
    for r, row in enumerate(qr.matrix):
        for c, v in enumerate(row):
            if v:
                ctx.rectangle(x0 + (c + 4) * mod, y + (r + 4) * mod, mod + 0.01, mod + 0.01)
    ctx.fill()
    y += side + 2 * MM
    centered(ctx, "%s · %s" % TEXT["scan"], y, sans, normal, 11, max_w, grey)
    y += 14 * MM

    def label(key, yy):
        centered(ctx, "%s / %s" % TEXT[key], yy, sans, normal, 13, max_w, grey)

    label("ssid", y)
    y += 12 * MM
    centered(ctx, ssid, y, sans, bold, 30, max_w)
    y += 16 * MM
    if typ != "nopass":
        label("pass", y)
        y += 12 * MM
        # Monospace: 0/O und l/1 unterscheidbar; lange Passphrasen umbrechen statt zu klein setzen
        lines = wrap_mono(passphrase, 24)
        size = min(fit(ctx, l, mono, bold, max_w, 28) for l in lines)
        for l in lines:
            ctx.select_font_face(mono, cairo.FONT_SLANT_NORMAL, bold)
            ctx.set_font_size(size)
            ctx.set_source_rgb(0, 0, 0)
            ext = ctx.text_extents(lines[0])
            ctx.move_to((W - ext.x_advance) / 2, y)
            ctx.show_text(l)
            y += size * 1.3
    if hint:
        centered(ctx, hint, A4[1] - margin, sans, normal, 12, max_w, grey)
    surf.finish()


def main(argv=None):
    ap = argparse.ArgumentParser(description="WLAN-Schild als A4-PDF (QR-Code, SSID, Passphrase, de/en)")
    ap.add_argument("--overlay", help="Site-Overlay mit wifi.rsc (z.B. site-b)")
    ap.add_argument("--ssid", default="guest", help='SSID-Schlüssel in wifi.rsc "ssids" (Standard guest)')
    ap.add_argument("--name", help="SSID direkt angeben (statt aus wifi.rsc)")
    ap.add_argument("--sec", help='Verschlüsselung wie in wifi.rsc, z.B. "wpa2-psk,wpa3-psk" (Standard aus wifi.rsc)')
    ap.add_argument("--manager", help="user@host des Managers: Passphrase per SSH aus dem Vault")
    ap.add_argument("--port", type=int, help="SSH-Port des Managers")
    ap.add_argument("--passphrase-stdin", action="store_true", help="Passphrase von stdin lesen")
    ap.add_argument("--title", help='Überschrift, zweisprachig mit "|", z.B. "Gäste-WLAN|Guest Wi-Fi"')
    ap.add_argument("--hint", help="Zeile am unteren Rand, z.B. Gültigkeit oder Ansprechpartner")
    ap.add_argument("--hidden", action="store_true", help="SSID wird nicht ausgestrahlt (H:true im QR-Code)")
    ap.add_argument("-o", "--out", help="Ziel-PDF (Standard: wlan-<SSID>.pdf im aktuellen Verzeichnis)")
    a = ap.parse_args(argv)

    ssid, sec = a.name, a.sec
    if a.overlay:
        defaults, ssids = parse_wifi(os.path.join(a.overlay, "wifi.rsc"))
        if a.ssid not in ssids:
            sys.exit("wifi.rsc: SSID-Schlüssel %s fehlt (vorhanden: %s)" % (a.ssid, ", ".join(sorted(ssids)) or "keiner"))
        ssid = ssid or ssids[a.ssid].get("ssid")
        sec = sec or ssids[a.ssid].get("sec") or defaults.get("sec")
    if not ssid:
        sys.exit("SSID fehlt: --overlay <site> [--ssid <schlüssel>] oder --name <SSID>")
    typ = auth_type(sec or "wpa2-psk")

    pw = ""
    if typ != "nopass":
        if a.passphrase_stdin:
            pw = sys.stdin.read().rstrip("\r\n")
        elif a.manager:
            pw = from_manager(a.manager, a.ssid, a.port)
        else:
            pw = getpass.getpass("Passphrase für %s: " % ssid)
        if not pw:
            sys.exit("Passphrase leer")

    try:
        import cairo  # noqa: F401
        import segno  # noqa: F401
    except ImportError as e:
        sys.exit("%s – Debian/Ubuntu: sudo apt install python3-segno python3-cairo" % e)
    out = a.out or "wlan-%s.pdf" % re.sub(r"[^A-Za-z0-9_.-]", "_", ssid)
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.close(fd)
    render(out, ssid, pw, typ, a.title, a.hint, a.hidden)
    print("%s: %s (%s), Passphrase im PDF – nicht ins Repo legen" % (out, ssid, typ))


if __name__ == "__main__":
    main()
