#!/usr/bin/env python3
"""rsc-check – RouterOS-Skripte (.rsc) statisch auf bekannte Fallen prüfen.

Die Regeln stammen aus den im CHR-Labor verifizierten RouterOS-Eigenheiten (docs/DECISIONS.md).
Sie ergänzen den Syntaxcheck (:parse in $cfmRelease) um Fehler, die erst beim echten /import
oder erst auf bestimmten Geräten auftreten.

Aufruf:
  tools/rsc-check.py              alle von Git verwalteten .rsc-Dateien und cfm/work/
  tools/rsc-check.py <pfad> …     Dateien oder Verzeichnisse, z.B. site/
  tools/rsc-check.py --staged     gestagte Dateien, Stand im Index (Pre-Commit-Hook)
  tools/rsc-check.py --regeln     Regeln auflisten

Ausnahme für eine Zeile: Kommentar in der Zeile darüber oder am Zeilenende (;#)
  # rsc-check: erlaubt <regel>[,<regel>]
Exit-Code 1 bei Fehlern; Hinweise ändern ihn nicht.
"""
import argparse
import os
import re
import subprocess
import sys
from collections import namedtuple

Finding = namedtuple("Finding", "path line level rule text")
FEHLER, HINWEIS = "FEHLER", "HINWEIS"

REGELN = {
    "klammer-anfang": "Anweisung beginnt am Zeilenanfang mit '[': RouterOS liest die Zeile u.U. als "
                      "Fortsetzung der vorigen. Funktion ohne Klammern aufrufen ($f …).",
    "escape-argument": "\\\" in einem String, der direkt Funktionsargument ist, bricht /import "
                       "(:parse akzeptiert es). Den String vorher in eine Local legen.",
    "return-onerror": ":return in :onerror … in={} verlässt die Funktion nicht. Ergebnis über ein "
                      "Flag setzen und nach dem Block zurückgeben.",
    "geraetemenue": "geräteabhängiges Menü in Slash-Schreibweise: Fehlt es (z.B. auf CHR/x86), ist das "
                    "ein Syntaxfehler, den :onerror nicht fängt. Leerzeichen-Schreibweise "
                    "(/system routerboard …) oder :parse verwenden.",
    "array-klammern": "Array-Literal als Funktionsargument ohne runde Klammern: p=({…}) schreiben.",
    "kommentar-im-array": "Kommentarzeile innerhalb eines Array-Literals: /import scheitert mit "
                          "\"syntax error\". Kommentar über das Array setzen.",
    "import-verbose": "/import … verbose=yes führt Zeilen einzeln aus, Locals gehen verloren: "
                      "verbose=no verwenden.",
    "syntax": "Klammern oder Anführungszeichen nicht ausgeglichen.",
    "dateigroesse": "RouterOS liest per /file get nur ca. 60 KB; $cfmRelease weist größere Dateien "
                    "unter work/ ab.",
    "dotfile": "Dateien mit führendem Punkt erscheinen nicht in /file und fehlen damit im Release.",
}

# Menüs, die es nur auf bestimmten Geräten oder mit Zusatzpaketen gibt
GERAETEMENUES = re.compile(r"^/(system/routerboard|system/gps|interface/ethernet/switch|"
                           r"interface/ethernet/poe|interface/wireless|interface/lte|interface/w60g)(/|$)")
GROESSE_MAX = 60000        # wie cfmParseWork in cfm/work/lib/mgr-core.rsc
GROESSE_HINWEIS = 50000
ERLAUBT = re.compile(r"rsc-check:\s*erlaubt\s+([\w,-]+)")
IMPORT = ("/import", ":import", "import")


def tokenize(text):
    """Zerlegt ein Skript in Tokens (Art, Wert, Zeile, String enthält \\").

    Arten: W (Wort), STR, NL (Zeilenende), ; [ ] ( ) { }. Kommentare (# am Anfang einer Anweisung)
    kommen getrennt als (Zeile, Text) zurück, nicht abgeschlossene Strings als Zeilennummern."""
    toks, comments, unclosed = [], [], []
    i, n, line = 0, len(text), 1
    stmt_pos = True                          # hier darf ein Kommentar beginnen
    while i < n:
        c = text[i]
        if c == "\\" and text.startswith("\n", i + 1):      # Zeilenfortsetzung
            i, line = i + 2, line + 1
            continue
        if c == "\\" and text.startswith("\r\n", i + 1):
            i, line = i + 3, line + 1
            continue
        if c in " \t\r":
            i += 1
            continue
        if c == "\n":
            toks.append(("NL", c, line, False))
            i, line, stmt_pos = i + 1, line + 1, True
            continue
        if c == "#" and stmt_pos:
            j = text.find("\n", i)
            j = n if j < 0 else j
            comments.append((line, text[i:j]))
            i = j
            continue
        if c == '"':
            start, j, esc = line, i + 1, False
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n:
                    esc = esc or text[j + 1] == '"'
                    line += text[j + 1] == "\n"
                    j += 2
                    continue
                line += text[j] == "\n"
                j += 1
            if j >= n:
                unclosed.append(start)
                break
            toks.append(("STR", text[i + 1:j], start, esc))
            i, stmt_pos = j + 1, False
            continue
        if c in "[](){};":
            toks.append((c, c, line, False))
            i, stmt_pos = i + 1, c in ";{"
            continue
        j = i + 1
        while j < n and text[j] not in " \t\r\n[](){};\"":
            if text[j] == "\\" and text.startswith("\n", j + 1):
                break
            j += 1
        toks.append(("W", text[i:j], line, False))
        i, stmt_pos = j, False
    return toks, comments, unclosed


class Frame:
    """Eine offene Klammer: block {…} (Anweisungen), paren (…), bracket […]."""

    def __init__(self, kind, line, onerr, data=False):
        self.kind, self.line = kind, line
        self.onerr = onerr     # liegt in :onerror … in={} (bis zu einem Funktionsrumpf)
        self.data = data       # Array-Literal (Ausdruck), kein Anweisungsblock
        self.call = False      # bracket: [$f …]
        self.new_stmt()

    def new_stmt(self):
        self.first = True      # nächstes Token beginnt die Anweisung bzw. den Klammerinhalt
        self.prev = None       # voriges Token auf dieser Ebene
        self.words = []        # Wörter der laufenden Anweisung (block)
        self.stmt_call = False  # Anweisung ist ein Funktionsaufruf $f …


def check_rsc(path, text):
    toks, comments, unclosed = tokenize(text)
    out = []

    def add(line, rule, level=FEHLER):
        out.append(Finding(path, line, level, rule, REGELN[rule]))

    for line in unclosed:
        add(line, "syntax")
    stack = [Frame("block", 1, False)]
    daten = []                 # Zeilenbereiche offener Array-Literale
    line_start = True
    for kind, val, line, esc in toks:
        fr = stack[-1]
        if kind == "NL":
            if fr.kind == "block":
                fr.new_stmt()
            line_start = True
            continue
        at_line_start, line_start = line_start, False
        if kind == ";":
            if fr.kind == "block":
                fr.new_stmt()
            continue
        direct = (fr.kind == "bracket" and fr.call) or (fr.kind == "block" and fr.stmt_call)
        if kind == "STR":
            if direct and esc:
                add(line, "escape-argument")
        elif kind == "W":
            if fr.first:
                if fr.kind == "block":
                    fr.stmt_call = val.startswith("$")
                    if val == ":return" and fr.onerr:
                        add(line, "return-onerror")
                elif fr.kind == "bracket":
                    fr.call = val.startswith("$")
            if fr.kind == "block":
                fr.words.append(val)
            if GERAETEMENUES.match(val):
                add(line, "geraetemenue")
            if val.lower() == "verbose=yes" and any(w in IMPORT for w in fr.words):
                add(line, "import-verbose")
        elif kind in "([{":
            if kind == "[" and fr.kind == "block" and fr.first and at_line_start:
                add(line, "klammer-anfang")
            onerr = fr.onerr
            data = False
            if kind == "{":
                pw = fr.prev[1] if fr.prev and fr.prev[0] == "W" else ""
                if direct and pw.endswith("="):
                    add(line, "array-klammern")
                if pw == "in=" and fr.words[:1] == [":onerror"]:
                    onerr = True
                elif pw == "do=" and fr.words[:1] in ([":global"], [":local"]):
                    onerr = False                   # Funktionsrumpf
                # Anweisungen stehen in do={…}, else={…}, :onerror … in={…} und in einem Block
                # am Anweisungsanfang; alles andere ist ein Array-Literal, und darin verträgt
                # RouterOS keine Kommentarzeilen.
                stmt = pw in ("do=", "else=") or (pw == "in=" and fr.words[:1] == [":onerror"])
                data = not (stmt or (fr.kind == "block" and fr.first))
            fr.first, fr.prev = False, (kind, val)
            stack.append(Frame({"(": "paren", "[": "bracket", "{": "block"}[kind], line, onerr, data))
            continue
        else:                                   # ) ] }
            want = {")": "paren", "]": "bracket", "}": "block"}[kind]
            if len(stack) == 1 or fr.kind != want:
                add(line, "syntax")
                if not any(f.kind == want for f in stack[1:]):
                    continue                    # überzählige Klammer ignorieren
                while stack[-1].kind != want:
                    stack.pop()
            if stack[-1].data:
                daten.append((stack[-1].line, line))
            stack.pop()
            fr = stack[-1]
        fr.first, fr.prev = False, (kind, val)
    letzte = toks[-1][2] if toks else 1
    for fr in stack[1:]:
        add(fr.line, "syntax")
        if fr.data:
            daten.append((fr.line, letzte))
    for line, _txt in comments:
        if any(a <= line < e for a, e in daten):
            add(line, "kommentar-im-array")

    erlaubt = {}
    for line, txt in comments:
        m = ERLAUBT.search(txt)
        if m:
            erlaubt.setdefault(line, set()).update(m.group(1).split(","))
    out = [f for f in out if f.rule not in erlaubt.get(f.line, set()) | erlaubt.get(f.line - 1, set())]
    return sorted(set(out), key=lambda f: (f.line, f.rule))


def check_file(path, data):
    """Prüft eine Datei: Inhalt (.rsc), Größe und Name (unter cfm/work/)."""
    p = path.replace(os.sep, "/")
    work = "/cfm/work/" in "/" + p
    out = []
    if work and os.path.basename(p).startswith("."):
        out.append(Finding(path, 1, FEHLER, "dotfile", REGELN["dotfile"]))
    if work or p.endswith(".rsc"):
        if len(data) > GROESSE_MAX:
            out.append(Finding(path, 1, FEHLER, "dateigroesse", REGELN["dateigroesse"]))
        elif len(data) > GROESSE_HINWEIS:
            out.append(Finding(path, 1, HINWEIS, "dateigroesse", REGELN["dateigroesse"]))
    if p.endswith(".rsc"):
        out += check_rsc(path, data.decode("utf-8", "replace"))
    return out


def relevant(p):
    return p.endswith(".rsc") or p.startswith("cfm/work/")


def git(root, *args):
    return subprocess.run(["git", "-C", root, *args], capture_output=True, check=True).stdout


def files_from_git(root, staged):
    if staged:
        names = git(root, "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z").split(b"\0")
    else:
        names = git(root, "ls-files", "-z").split(b"\0")
    for name in filter(None, names):
        p = name.decode()
        if not relevant(p):
            continue
        if staged:
            yield p, git(root, "show", ":" + p)
        elif os.path.isfile(os.path.join(root, p)):
            with open(os.path.join(root, p), "rb") as fh:
                yield p, fh.read()


def files_from_paths(paths):
    def emacs(name):                          # Sicherungs-, Auto-Save- und Sperrdateien
        return name.endswith("~") or name.startswith(".#") or (name.startswith("#") and name.endswith("#"))

    def want(p):
        return p.endswith(".rsc") or "/cfm/work/" in "/" + p.replace(os.sep, "/")

    for arg in paths:
        if os.path.isdir(arg):
            cands = [os.path.join(d, f) for d, _, fs in os.walk(arg) for f in sorted(fs)]
        else:
            cands = [arg]
        for p in cands:
            if emacs(os.path.basename(p)) or not os.path.isfile(p) or not want(p):
                continue
            with open(p, "rb") as fh:
                yield os.path.relpath(p), fh.read()


def main(argv=None):
    ap = argparse.ArgumentParser(description="RouterOS-Skripte (.rsc) statisch auf bekannte Fallen prüfen.",
                                 epilog="Ausnahme: # rsc-check: erlaubt <regel> in der Zeile darüber.")
    ap.add_argument("pfade", nargs="*", help="Dateien oder Verzeichnisse (Standard: alle Git-Dateien)")
    ap.add_argument("--staged", action="store_true", help="gestagte Dateien prüfen (Pre-Commit-Hook)")
    ap.add_argument("--regeln", action="store_true", help="Regeln auflisten")
    a = ap.parse_args(argv)
    if a.regeln:
        for rule, text in REGELN.items():
            print(f"{rule:16} {text}")
        return 0
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if a.pfade:
        files = list(files_from_paths(a.pfade))
    else:
        try:
            files = list(files_from_git(root, a.staged))
        except (OSError, subprocess.CalledProcessError) as e:
            print(f"rsc-check: git nicht verwendbar ({e}); Pfade angeben", file=sys.stderr)
            return 2
    findings = [f for p, data in files for f in check_file(p, data)]
    for f in sorted(findings, key=lambda f: (f.path, f.line, f.rule)):
        print(f"{f.path}:{f.line}: {f.level} [{f.rule}] {f.text}")
    nf = sum(f.level == FEHLER for f in findings)
    nh = len(findings) - nf
    if files or not a.staged:
        print(f"rsc-check: {len(files)} Dateien geprüft, {nf} Fehler, {nh} Hinweise", file=sys.stderr)
    if nf and a.staged:
        print("rsc-check: Commit abgebrochen (Ausnahme: # rsc-check: erlaubt <regel>; "
              "übergehen: git commit --no-verify)", file=sys.stderr)
    return 1 if nf else 0


if __name__ == "__main__":
    sys.exit(main())
