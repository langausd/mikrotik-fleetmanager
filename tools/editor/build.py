#!/usr/bin/env python3
"""Baut aus cfm-editor.js und cfm-monitor.js die Lesezeichen (javascript:-URLs) und die Seite install.html.

Aufruf: tools/editor/build.py   -> tools/editor/install.html
install.html im Browser öffnen und die Links „cfm-Editor“ (D73) bzw. „cfm-Monitor“ (D77, D81) in die
Lesezeichen-Leiste ziehen. Alles steckt im Lesezeichen; nach einer Änderung an einer .js-Datei neu
bauen und das Lesezeichen ersetzen.
"""
import hashlib
import html
import pathlib
import urllib.parse

HIER = pathlib.Path(__file__).resolve().parent

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
    for datei, titel, text in TEILE:
        src = (HIER / datei).read_text(encoding="utf-8")
        stand = hashlib.sha256(src.encode()).hexdigest()[:12]
        # Stand ins Lesezeichen: eine neue Fassung ersetzt die alte in der WebFig-Seite
        url = bookmarklet(src.replace("'@@STAND@@'", "'" + stand + "'"))
        if len(url) > GRENZE:
            raise SystemExit(f"{titel}: Lesezeichen mit {len(url)} Zeichen zu lang (Grenze {GRENZE}, Firefox 65 536)")
        staende.append(f"{titel} {stand}, {len(url)} Zeichen")
        teile.append(f"""<h2>{titel}</h2>{text}
<p><a class="bm" href="{html.escape(url, quote=True)}">{titel}</a></p>""")
    seite = f"""<!doctype html>
<html lang="de"><meta charset="utf-8"><title>cfm-Lesezeichen installieren</title>
<style>body{{font:15px/1.5 system-ui,sans-serif;max-width:720px;margin:40px auto;padding:0 16px;color:#1d2321}}
a.bm{{display:inline-block;padding:8px 16px;background:#13534b;color:#fff;border-radius:6px;text-decoration:none;font-weight:600}}
code{{background:#eef1ef;padding:1px 4px;border-radius:3px}}</style>
<h1>cfm-Lesezeichen für WebFig</h1>
<p>Den Knopf in die Lesezeichen-Leiste ziehen (oder per Rechtsklick als Lesezeichen speichern).</p>
{"".join(teile)}
<p>Voraussetzung: Dienst <code>www</code> (später <code>www-ssl</code>) auf dem Gerät, siehe
<code>services</code> in <code>global.rsc</code>. Die Lesezeichen laden nichts aus dem Netz.
Stand: {"; ".join(staende)}.</p>
</html>
"""
    (HIER / "install.html").write_text(seite, encoding="utf-8")
    print("install.html geschrieben (" + "; ".join(staende) + ")")


if __name__ == "__main__":
    main()
