#!/usr/bin/env python3
"""Baut aus cfm-editor.js das Lesezeichen (javascript:-URL) und die Seite install.html (D73).

Aufruf: tools/editor/build.py   -> tools/editor/install.html
install.html im Browser öffnen und den Link „cfm-Editor“ in die Lesezeichen-Leiste ziehen. Der
ganze Editor steckt im Lesezeichen; nach einer Änderung an cfm-editor.js neu bauen und das
Lesezeichen ersetzen.
"""
import hashlib
import html
import pathlib
import urllib.parse

HIER = pathlib.Path(__file__).resolve().parent


def bookmarklet(src):
    # Zeilenumbrüche bleiben (als %0A), damit //-Kommentare an der Zeile enden
    return "javascript:" + urllib.parse.quote(src, safe="")


def main():
    src = (HIER / "cfm-editor.js").read_text(encoding="utf-8")
    url = bookmarklet(src)
    stand = hashlib.sha256(src.encode()).hexdigest()[:12]
    seite = f"""<!doctype html>
<html lang="de"><meta charset="utf-8"><title>cfm-Editor installieren</title>
<style>body{{font:15px/1.5 system-ui,sans-serif;max-width:720px;margin:40px auto;padding:0 16px;color:#1d2321}}
a.bm{{display:inline-block;padding:8px 16px;background:#13534b;color:#fff;border-radius:6px;text-decoration:none;font-weight:600}}
code{{background:#eef1ef;padding:1px 4px;border-radius:3px}}</style>
<h1>cfm-Editor</h1>
<p>Den Knopf in die Lesezeichen-Leiste ziehen (oder per Rechtsklick als Lesezeichen speichern):</p>
<p><a class="bm" href="{html.escape(url, quote=True)}">cfm-Editor</a></p>
<ol>
<li>WebFig des Managers öffnen und anmelden (z.B. <code>http://192.168.10.2/webfig/</code>).</li>
<li>Lesezeichen „cfm-Editor“ anklicken, mit einem RouterOS-User der Gruppe full anmelden (REST-API).</li>
<li>Site-Datei links wählen, ändern, Strg+S. Dann „Prüfen“, „Diff zum Release“, „Probelauf“,
„Release (Ring 0)“; den Aufstieg der Ringe wie gewohnt per <code>$cfmPromote</code>.</li>
</ol>
<p>Voraussetzung: Dienst <code>www</code> (später <code>www-ssl</code>) auf dem Manager, siehe
<code>services</code> in <code>global.rsc</code>. Das Lesezeichen lädt nichts aus dem Netz.
Stand {stand}, {len(url)} Zeichen.</p>
</html>
"""
    (HIER / "install.html").write_text(seite, encoding="utf-8")
    print(f"install.html geschrieben (Stand {stand}, Lesezeichen {len(url)} Zeichen)")


if __name__ == "__main__":
    main()
