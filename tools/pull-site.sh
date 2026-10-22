#!/usr/bin/env bash
# Holt die Site-Daten vom Manager ins Overlay (D72): Der Manager führt sie (bearbeitet mit dem
# cfm-Editor, tools/editor/, oder per /file edit), das Overlay ist Sicherung und Referenz. Geholt werden die Dateien
# direkt in work/ (global.rsc, vlans.rsc, …, authorized_keys.<user>), work/hosts/ und
# meta/inventory.rsc; lib/, roles/ und web/ (Framework-Code) bleiben, wie sie sind.
#   tools/pull-site.sh admin@192.168.10.2 --overlay site [--port 22] [--base cfm] [--dry-run]
# Geänderte lokale Dateien bleiben als <datei>~ liegen (upload-seed.sh lädt sie nie hoch), Dateien
# nur im Overlay werden genannt, nicht gelöscht. --dry-run zeigt nur die Unterschiede.
set -euo pipefail
dest=${1:?Ziel user@host fehlt}; shift
port=22; overlay=""; base=cfm; dry=""
while [ $# -gt 0 ]; do case $1 in
  --port) port=$2; shift 2;; --overlay) overlay=$2; shift 2;; --base) base=$2; shift 2;;
  --dry-run) dry=1; shift;;
  *) echo "unbekannt: $1"; exit 1;; esac; done
[ -n "$overlay" ] || { echo "--overlay DIR fehlt (z.B. site)"; exit 1; }
[ -d "$overlay" ] || { echo "Overlay $overlay fehlt"; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
sf() { sftp -q -b - -P "$port" ${SFTP_OPTS:-} "$dest"; }
# Liste: RouterOS nennt bei "ls -1" den Pfad samt Verzeichnis; hosts/, lib/, roles/, web/ sind Verzeichnisse
if ! printf 'ls -1 %s/work\nls -1 %s/work/hosts\n' "$base" "$base" | sf > "$tmp/ls" 2>/dev/null; then
  echo "FEHLER: keine SFTP-Anmeldung per SSH-Key an $dest (Port $port) - siehe upload-seed.sh" >&2
  exit 1
fi
tr -d '\r' < "$tmp/ls" | grep -v '^sftp>' | sed "s|^/*$base/work/||" \
  | grep -vE '^(hosts|lib|roles|web)$' | grep -vE '(^|/)\.' | sort > "$tmp/liste" || true
[ -s "$tmp/liste" ] || { echo "FEHLER: keine Site-Dateien unter $dest:$base/work/ gefunden" >&2; exit 1; }
mkdir -p "$tmp/work/hosts" "$tmp/meta"
{ sed "s|.*|get $base/work/& $tmp/work/&|" "$tmp/liste"; echo "-get $base/meta/inventory.rsc $tmp/meta/inventory.rsc"; } \
  | sf >/dev/null 2>&1 || { echo "FEHLER beim Holen der Dateien" >&2; exit 1; }
neu=""; anders=""; gleich=0
while IFS= read -r f; do
  case $f in meta/*) src="$tmp/$f";; *) src="$tmp/work/$f";; esac
  [ -f "$src" ] || continue
  dst="$overlay/$f"
  if [ ! -f "$dst" ]; then neu="$neu $f"
  elif cmp -s "$src" "$dst"; then gleich=$((gleich + 1)); continue
  else anders="$anders $f"; [ -n "$dry" ] || cp -p "$dst" "$dst~"
  fi
  [ -n "$dry" ] || { mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"; }
done < <(cat "$tmp/liste"; echo "meta/inventory.rsc")
# nur im Overlay (auf dem Manager gelöscht oder nie hochgeladen)
nurlokal=""
for d in "$overlay"/*.rsc "$overlay"/authorized_keys.* "$overlay"/hosts/*; do
  [ -f "$d" ] || continue
  f=${d#"$overlay"/}
  case $f in *~|bootstrap*.rsc) continue;; esac
  grep -qxF "$f" "$tmp/liste" || nurlokal="$nurlokal $f"
done
pre=""; [ -n "$dry" ] && pre="(--dry-run) "
echo "${pre}$gleich Dateien unverändert"
if [ -n "$anders" ]; then echo "${pre}geändert auf dem Manager:$anders"; [ -n "$dry" ] || echo "  alte lokale Fassung jeweils als <datei>~"; fi
if [ -n "$neu" ]; then echo "${pre}neu vom Manager:$neu"; fi
if [ -n "$nurlokal" ]; then echo "nur im Overlay (nicht auf dem Manager):$nurlokal"; fi
