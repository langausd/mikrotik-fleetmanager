#!/usr/bin/env python3
"""Baut aus cfm-editor.js und cfm-wlan.js die Lesezeichen (javascript:-URLs) und die Seite install.html.

Aufruf: tools/editor/build.py   -> tools/editor/install.html
install.html im Browser öffnen und die Links „cfm-Editor“ (D73) bzw. „cfm-WLAN“ (D77) in die
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
Der Browser merkt sich die Anmeldung bis zum Schließen, auch für cfm-WLAN.</li>
<li>Site-Datei links wählen, ändern, Strg+S. Dann „Prüfen“, „Diff zum Release“, „Probelauf“,
„Release (Ring 0)“; den Aufstieg der Ringe wie gewohnt per <code>$cfmPromote</code>.</li>
</ol>"""),
    ("cfm-wlan.js", "cfm-WLAN", """
<p>WLAN-Clients aller APs live und als Zeitleiste je Client – Roaming nachvollziehen (D77).</p>
<ol>
<li>WebFig des <b>CAPsMAN</b> öffnen (Gerät mit Rolle <code>capsman</code>, ohne sie der Manager).</li>
<li>Lesezeichen „cfm-WLAN“ anklicken und anmelden; ein User mit Leserecht genügt, das Lesezeichen
ändert nichts am Gerät.</li>
<li>Oben je AP die verbundenen Clients mit Signal, darunter die Zeitleiste (Farbe = AP, Linie =
Signal, ▼ = Wechsel) und die Ereignisse. Der Verlauf bleibt 24 h im Browser; Namen per Klick.</li>
</ol>"""),
]


def bookmarklet(src):
    # Zeilenumbrüche bleiben (als %0A), damit //-Kommentare an der Zeile enden
    return "javascript:" + urllib.parse.quote(src, safe="")


def main():
    teile, staende = [], []
    for datei, titel, text in TEILE:
        src = (HIER / datei).read_text(encoding="utf-8")
        stand = hashlib.sha256(src.encode()).hexdigest()[:12]
        # Stand ins Lesezeichen: eine neue Fassung ersetzt die alte in der WebFig-Seite
        url = bookmarklet(src.replace("'@@STAND@@'", "'" + stand + "'"))
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
