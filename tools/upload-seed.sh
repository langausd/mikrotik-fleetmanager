#!/usr/bin/env bash
# Lädt die Vorlage (cfm/work + cfm/meta) einmalig auf den Primary-Manager.
# Danach ist der Manager die Source of Truth – dieses Verzeichnis nur noch Referenz.
#   tools/upload-seed.sh admin@192.168.10.2 [--port 22] [--overlay DIR] [--base cfm]
#                        [--seed-inventory] [--bootstrap DATEI]
# --overlay: Dateien aus DIR (gleiche Struktur wie cfm/work, plus meta/) überschreiben
#            die Vorlage, z.B. site/ (eigene Standortdaten, von Git ignoriert, anlegen mit
#            tools/new-site.py) oder tools/chr-lab/seed für das Testlabor. Hochgeladen werden
#            nur *.rsc (außer bootstrap*.rsc), authorized_keys und die Verzeichnisse
#            hosts/ roles/ lib/ meta/; Notizen wie CHECKLISTE.md oder CSV-Listen bleiben lokal.
# --bootstrap: zusätzlich diese Bootstrap-Datei ins Wurzelverzeichnis des Geräts legen (nicht nach
#            work/ - dort landet nur, was an die Flotte verteilt wird). Ohne Pfad wird
#            <overlay>/bootstrap-manager.rsc genommen. Danach auf dem Gerät: /import <datei>.
# --seed-inventory: meta/inventory.rsc mit hochladen (nur beim allerersten Aufsetzen sinnvoll).
#            Ohne dieses Flag bleibt inventory.rsc auf dem Gerät unangetastet, weil es laut
#            eigenem Kopfkommentar "nicht versioniert, wirkt sofort" ist und von $cfmRegister/
#            $cfmEnroll live gepflegt wird – ein erneuter Upload würde echte Seriennummern/
#            Ringe wieder auf die lokale Vorlage zurücksetzen.
set -euo pipefail
dest=${1:?Ziel user@host fehlt}; shift
port=22; overlay=""; base=cfm; seed_inventory=""; bootstrap=""
while [ $# -gt 0 ]; do case $1 in
  --port) port=$2; shift 2;; --overlay) overlay=$2; shift 2;; --base) base=$2; shift 2;;
  --seed-inventory) seed_inventory=1; shift;;
  # --bootstrap ohne Pfad: Datei aus dem Overlay nehmen (erst nach dem Parsen auflösbar)
  --bootstrap) if [ $# -ge 2 ] && [ -f "$2" ]; then bootstrap=$2; shift 2; else bootstrap="-"; shift; fi;;
  *) echo "unbekannt: $1"; exit 1;; esac; done
if [ "$bootstrap" = "-" ]; then
  [ -n "$overlay" ] || { echo "--bootstrap ohne Pfad braucht --overlay"; exit 1; }
  bootstrap="$overlay/bootstrap-manager.rsc"
fi
if [ -n "$bootstrap" ] && [ ! -f "$bootstrap" ]; then echo "Bootstrap-Datei fehlt: $bootstrap"; exit 1; fi
root=$(cd "$(dirname "$0")/.." && pwd)
stage=$(mktemp -d); trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/work" "$stage/meta"
cp -r "$root/cfm/work/." "$stage/work/"; cp -r "$root/cfm/meta/." "$stage/meta/"
if [ -n "$overlay" ]; then
  [ -d "$overlay/meta" ] && cp -r "$overlay/meta/." "$stage/meta/"
  skipped=""
  for d in "$overlay"/*; do
    n=$(basename "$d")
    case $n in
      meta) ;;
      hosts|roles|lib) [ -d "$d" ] && cp -r "$d" "$stage/work/" ;;
      # die per --bootstrap gewählte Datei geht separat ins Wurzelverzeichnis, nicht nach work/
      bootstrap*.rsc) { [ -n "$bootstrap" ] && cmp -s "$d" "$bootstrap"; } || skipped="$skipped $n" ;;
      *.rsc|authorized_keys) [ -f "$d" ] && cp "$d" "$stage/work/" ;;
      *) skipped="$skipped $n" ;;
    esac
  done
  [ -n "$skipped" ] && echo "nicht hochgeladen (nur lokal):$skipped"
fi
if [ -z "$seed_inventory" ] && [ -f "$stage/meta/inventory.rsc" ]; then
  rm -f "$stage/meta/inventory.rsc"
  echo "meta/inventory.rsc nicht hochgeladen (lebt auf dem Gerät, siehe --seed-inventory)"
fi
# Verzeichnisse in einem Batch anlegen (idempotent, Fehler hier sind unkritisch/meist "exists").
mkbatch=$(mktemp); trap 'rm -rf "$stage" "$mkbatch"' EXIT
echo "-mkdir $base" > "$mkbatch"
(cd "$stage" && find . -mindepth 1 -type d | sed "s|^\./|-mkdir $base/|") >> "$mkbatch"
sftp -q -b "$mkbatch" -P "$port" ${SFTP_OPTS:-} "$dest" >/dev/null

# Dateien einzeln hochladen (nicht als ein großes Batch-Kommando): ein Batch-`put` schlägt hier
# gelegentlich lautlos fehl (Datei bleibt auf dem Gerät beim alten Stand, sftp meldet trotzdem
# Erfolg) - pro Datei eine eigene Sitzung mit Wiederholung ist zuverlässiger. Aus einer Datei statt
# einer Pipe gelesen, damit die Schleife nicht in einer Subshell läuft (n/failed blieben sonst
# nach der Schleife auf ihrem Ausgangswert).
filelist=$(mktemp); trap 'rm -rf "$stage" "$mkbatch" "$filelist"' EXIT
(cd "$stage" && find . -type f | sed 's|^\./||') > "$filelist"
n=0; failed=""
while IFS= read -r f; do
  ok=0
  for attempt in 1 2 3; do
    if printf 'put %s %s\n' "$stage/$f" "$base/$f" | sftp -P "$port" ${SFTP_OPTS:-} "$dest" >/dev/null 2>&1; then
      ok=1; break
    fi
  done
  if [ "$ok" = 1 ]; then
    n=$((n + 1))
  else
    echo "FEHLER beim Hochladen (3 Versuche): $f" >&2
    failed="$failed $f"
  fi
done < "$filelist"
total=$(wc -l < "$filelist")
if [ -n "$failed" ]; then
  echo "Seed unvollständig hochgeladen nach $dest:$base/ ($n von $total Dateien) - erneut versuchen" >&2
  exit 1
fi
echo "Seed hochgeladen nach $dest:$base/ ($total Dateien)"
if [ -n "$bootstrap" ]; then
  bn=$(basename "$bootstrap")
  case $bn in
    *.auto.rsc) echo "FEHLER: $bn würde beim Hochladen sofort ausgeführt - umbenennen" >&2; exit 1;;
  esac
  ok=0
  for attempt in 1 2 3; do
    if printf 'put %s %s\n' "$bootstrap" "$bn" | sftp -P "$port" ${SFTP_OPTS:-} "$dest" >/dev/null 2>&1; then
      ok=1; break
    fi
  done
  [ "$ok" = 1 ] || { echo "FEHLER beim Hochladen (3 Versuche): $bn" >&2; exit 1; }
  echo "Bootstrap hochgeladen: $bn (Wurzelverzeichnis)"
  echo "Nächster Schritt auf dem Gerät: Kopf prüfen, dann /import $bn"
else
  echo "Nächster Schritt am Manager: bootstrap/bootstrap-manager.rsc anpassen, hochladen, /import"
fi
