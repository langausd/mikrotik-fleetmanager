#!/usr/bin/env python3
"""Baut aus cfm-editor.js und cfm-monitor.js die Fassungen für die Geräte und die Seite install.html.

Aufruf: tools/editor/build.py   -> cfm/work/web/*.js und tools/editor/install.html
Das Lade-Lesezeichen „cfm“ (cfm-loader.js, D91) wird einmal in die Lesezeichen-Leiste gezogen und startet
die Fassung vom Gerät (cfm/work/web/, kommt mit tools/upload-seed.sh und dem Release). Nach einer Änderung
an einer .js-Datei neu bauen, hochladen und releasen - am Lesezeichen ändert sich nichts. Die vollständigen
Lesezeichen „cfm-Editor“ (D73) und „cfm-Monitor“ (D77, D81) bleiben als Rückfall (Gerät ohne web/).
"""
import hashlib
import html
import pathlib
import urllib.parse

HIER = pathlib.Path(__file__).resolve().parent
WEB = HIER.parent.parent / "cfm" / "work" / "web"

TEILE = [
    ("cfm-editor.js", "cfm-Editor", """
<p>Site-Daten des Managers im Browser bearbeiten, prüfen, Probelauf, Release (D73).</p>
<ol>
<li>WebFig des Managers öffnen und anmelden (z.B. <code>http://192.168.10.2/webfig/</code>).</li>
<li>Lesezeichen „cfm-Editor“ anklicken, mit einem RouterOS-User der Gruppe full anmelden (REST-API).
Der Browser merkt sich die Anmeldung bis zum Schließen, auch für cfm-Monitor.</li>
<li>Site-Datei links wählen, ändern, Strg+S. Dann „Prüfen“, „Diff zum Release“, „Probelauf“,
„Release (Ring 0)“; den Aufstieg der Ringe wie gewohnt per <code>$cfmPromote</code>.</li>
</ol>"""),
    ("cfm-monitor.js", "cfm-Monitor", """
<p>Zwei Reiter (D77, D81; früher „cfm-WLAN“): <b>WLAN</b> zeigt die Clients aller APs live und als
Zeitleiste je Client – Roaming nachvollziehen. <b>Suche</b> findet Geräte nach MAC, IP, Name, Port, AP,
SSID oder Signal (<code>$cfmFind</code>).</p>
<ol>
<li>WLAN: WebFig des <b>CAPsMAN</b> öffnen (Gerät mit Rolle <code>capsman</code>, ohne sie der Manager),
Lesezeichen anklicken und anmelden; ein User mit Leserecht genügt, die Ansicht ändert nichts am Gerät.</li>
<li>Suche: WebFig des <b>Managers</b> öffnen, Lesezeichen anklicken, mit einem User der Gruppe full
anmelden. Klick auf Gerät, Port, AP, SSID oder VLAN in der Tabelle sucht danach.</li>
<li>Ist der Manager zugleich CAPsMAN, gehen beide Reiter an derselben Stelle. Der WLAN-Verlauf bleibt
24 h im Browser; Namen per Klick.</li>
</ol>"""),
]


# Firefox nimmt Lesezeichen bis 65 536 Zeichen an (cfm-Monitor hatte 2026-10-16 so 73 700 und ließ sich
# nicht installieren). Deshalb: Kommentarzeilen, Einrückung und Leerzeilen fallen weg (die .js-Dateien haben
# keine mehrzeiligen Strings, in denen das zählt - CSS-Zeilen beginnen nie mit //), und Zeichen, die in
# einer URL erlaubt sind, bleiben unkodiert. Zeilenumbrüche bleiben (als %0A), damit //-Kommentare am
# Zeilenende enden.
GRENZE = 60000
SICHER = "!$&'()*+,;=:@/?~-._"


def schrumpfen(src):
    zeilen = (z.strip() for z in src.split("\n"))
    return "\n".join(z for z in zeilen if z and not z.startswith("//"))


def bookmarklet(src):
    return "javascript:" + urllib.parse.quote(schrumpfen(src), safe=SICHER)


def main():
    teile, staende = [], []
    WEB.mkdir(exist_ok=True)
    for datei, titel, text in TEILE:
        src = (HIER / datei).read_text(encoding="utf-8")
        stand = hashlib.sha256(src.encode()).hexdigest()[:12]
        # Stand ins Lesezeichen: eine neue Fassung ersetzt die alte in der WebFig-Seite
        src = src.replace("'@@STAND@@'", "'" + stand + "'")
        url = bookmarklet(src)
        if len(url) > GRENZE:
            raise SystemExit(f"{titel}: Lesezeichen mit {len(url)} Zeichen zu lang (Grenze {GRENZE}, Firefox 65 536)")
        # Fassung fürs Gerät (D91): RouterOS liest per /file get nur ca. 60 KB ($cfmParseWork)
        geraet = f"// {datei} {stand} - erzeugt von tools/editor/build.py, nicht von Hand ändern\n" + schrumpfen(src) + "\n"
        if len(geraet.encode()) > GRENZE:
            raise SystemExit(f"{titel}: web/{datei} mit {len(geraet.encode())} Bytes zu groß (Grenze {GRENZE})")
        (WEB / datei).write_text(geraet, encoding="utf-8")
        staende.append(f"{titel} {stand}, {len(url)} Zeichen")
        teile.append(f"""<h3>{titel}</h3>{text}
<p><a class="bm2" href="{html.escape(url, quote=True)}">{titel}</a></p>""")
    lader = bookmarklet((HIER / "cfm-loader.js").read_text(encoding="utf-8"))
    seite = f"""<!doctype html>
<html lang="de"><meta charset="utf-8"><title>cfm-Lesezeichen installieren</title>
<style>body{{font:15px/1.5 system-ui,sans-serif;max-width:720px;margin:40px auto;padding:0 16px;color:#1d2321}}
a.bm,a.bm2{{display:inline-block;padding:8px 16px;background:#13534b;color:#fff;border-radius:6px;text-decoration:none;font-weight:600}}
a.bm2{{background:#5f6b6d}}
code{{background:#eef1ef;padding:1px 4px;border-radius:3px}}</style>
<h1>cfm-Lesezeichen für WebFig</h1>
<p>Den Knopf in die Lesezeichen-Leiste ziehen (oder per Rechtsklick als Lesezeichen speichern).</p>
<h2>cfm</h2>
<p>Ein Lesezeichen für beide, einmal anlegen (D91): WebFig des Geräts öffnen, „cfm“ anklicken, anmelden.
Es startet cfm-Editor oder cfm-Monitor in der Fassung, die auf dem Gerät liegt – neue Fassungen kommen mit
dem Framework-Update (<code>upload-seed.sh</code>, Release), das Lesezeichen bleibt.</p>
<p><a class="bm" href="{html.escape(lader, quote=True)}">cfm</a></p>
<h2>Vollständige Lesezeichen (Rückfall)</h2>
<p>Für ein Gerät mit einem Framework-Stand vor D91 (ohne <code>web/</code>). Der ganze Code steckt im
Lesezeichen; nach einer neuen Fassung hier neu ziehen und das alte ersetzen.</p>
{"".join(teile)}
<p>Voraussetzung: Dienst <code>www</code> (später <code>www-ssl</code>) auf dem Gerät, siehe
<code>services</code> in <code>global.rsc</code>. Die Lesezeichen laden nichts aus dem Netz.
Stand: {"; ".join(staende)}.</p>
</html>
"""
    (HIER / "install.html").write_text(seite, encoding="utf-8")
    print("install.html und cfm/work/web/ geschrieben (" + "; ".join(staende) + ")")


if __name__ == "__main__":
    main()
