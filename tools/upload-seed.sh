#!/usr/bin/env bash
# Lädt die Vorlage (cfm/work + cfm/meta) einmalig auf den Primary-Manager.
# Danach ist der Manager die Source of Truth – dieses Verzeichnis nur noch Referenz.
#   tools/upload-seed.sh admin@192.168.10.2 [--port 22] [--overlay DIR] [--base cfm]
# --overlay: Dateien aus DIR (gleiche Struktur wie cfm/work, plus meta/) überschreiben
#            die Vorlage, z.B. tools/chr-lab/seed für das Testlabor.
set -euo pipefail
dest=${1:?Ziel user@host fehlt}; shift
port=22; overlay=""; base=cfm
while [ $# -gt 0 ]; do case $1 in
  --port) port=$2; shift 2;; --overlay) overlay=$2; shift 2;; --base) base=$2; shift 2;;
  *) echo "unbekannt: $1"; exit 1;; esac; done
root=$(cd "$(dirname "$0")/.." && pwd)
stage=$(mktemp -d); trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/work" "$stage/meta"
cp -r "$root/cfm/work/." "$stage/work/"; cp -r "$root/cfm/meta/." "$stage/meta/"
if [ -n "$overlay" ]; then
  [ -d "$overlay/meta" ] && cp -r "$overlay/meta/." "$stage/meta/"
  for d in "$overlay"/*; do [ "$(basename "$d")" = meta ] || cp -r "$d" "$stage/work/"; done
fi
batch=$(mktemp); trap 'rm -rf "$stage" "$batch"' EXIT
echo "-mkdir $base" > "$batch"
(cd "$stage" && find . -mindepth 1 -type d | sed "s|^\./|-mkdir $base/|") >> "$batch"
(cd "$stage" && find . -type f | sed 's|^\./||' | while read -r f; do echo "put $stage/$f $base/$f"; done) >> "$batch"
sftp -q -b "$batch" -P "$port" ${SFTP_OPTS:-} "$dest" >/dev/null
echo "Seed hochgeladen nach $dest:$base/ ($(cd "$stage" && find . -type f | wc -l) Dateien)"
echo "Nächster Schritt am Manager: bootstrap/bootstrap-manager.rsc anpassen, hochladen, /import"
