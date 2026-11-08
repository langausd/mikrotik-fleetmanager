#!/usr/bin/env bash
# Lädt die Vorlage (cfm/work + cfm/meta) auf den Primary-Manager.
# Danach ist der Manager die Source of Truth – dieses Verzeichnis nur noch Referenz (DG1.2). Die
# Site-Daten (global.rsc, vlans.rsc, … , hosts/, authorized_keys.<user>) pflegt der Manager selbst
# (z.B. im WebFig-Terminal per /file/edit); ein normaler Upload bringt nur den Framework-Code
# (lib/, roles/), tools/pull-site.sh holt die Site-Daten als Sicherung ins Overlay (DT2.2).
#   tools/upload-seed.sh admin@192.168.10.2 [--port 22] [--overlay DIR] [--base cfm] [--site]
#                        [--seed-inventory [--force]] [--bootstrap DATEI] [--all-features]
# --site:   auch die Site-Daten hochladen und damit die auf dem Manager ersetzen (vorher werden die
#           Dateien genannt, die dort anders sind). Ohne --site bleiben sie auf dem Manager unberührt.
# --overlay: Dateien aus DIR (gleiche Struktur wie cfm/work, plus meta/) überschreiben
#            die Vorlage, z.B. site/ (eigene Standortdaten, von Git ignoriert, anlegen mit
#            tools/new-site.py) oder tools/chr-lab/seed für das Testlabor. Hochgeladen werden
#            nur *.rsc (außer bootstrap*.rsc), authorized_keys.<user> und die Verzeichnisse
#            hosts/ roles/ lib/ meta/; Notizen wie STAND.md, BEFUNDE.md oder CSV-Listen bleiben lokal.
# --bootstrap: zusätzlich diese Bootstrap-Datei ins Wurzelverzeichnis des Geräts legen (nicht nach
#            work/ - dort landet nur, was an die Flotte verteilt wird). Ohne Pfad wird
#            <overlay>/bootstrap-manager.rsc genommen. Danach auf dem Gerät: /import <datei>.
# --seed-inventory: meta/inventory.rsc mit hochladen (nur beim allerersten Aufsetzen sinnvoll,
#            schließt --site ein).
#            Enthält das Inventar auf dem Gerät schon echte Seriennummern (also aufgenommene
#            Geräte), bricht das Skript ab - mit --force trotzdem überschreiben.
#            Ohne dieses Flag bleibt inventory.rsc auf dem Gerät unangetastet, weil es laut
#            eigenem Kopfkommentar "nicht versioniert, wirkt sofort" ist und von $cfmRegister/
#            $cfmEnroll live gepflegt wird – ein erneuter Upload würde echte Seriennummern/
#            Ringe wieder auf die lokale Vorlage zurücksetzen.
# Feature-Module (DG4.6, lib/<rolle>.<feature>.rsc): nur die hochladen, deren Feature die Site-Daten nutzen
#            (tools/feature-module.py); nicht gebrauchte entfernt das Skript auch auf dem Manager, sonst gingen sie
#            mit jedem Release an die Geräte. Maßgeblich sind die Site-Daten, die nach dem Upload dort gelten: die
#            des Managers, mit --site darüber die hochgeladenen. Schaltet die Site ein Feature später ein (z.B. im
#            cfm-Editor), lehnt $cfmCheck das Release ab, bis das Modul hochgeladen ist.
# --all-features: alle Feature-Module hochladen (Testlabor: es schaltet Features auf dem Manager ein).
# Vor dem Upload prüft tools/rsc-check.py alle hochzuladenden .rsc (auch die Bootstrap-Datei); bei einem
#            Fehler (z.B. Kommentar in einem Array-Literal) bricht das Skript ab, ohne etwas hochzuladen.
# --no-check: diese Prüfung überspringen.
set -euo pipefail
dest=${1:?Ziel user@host fehlt}; shift
port=22; overlay=""; base=cfm; seed_inventory=""; bootstrap=""; force=""; site=""; all_features=""; no_check=""
while [ $# -gt 0 ]; do case $1 in
  --port) port=$2; shift 2;; --overlay) overlay=$2; shift 2;; --base) base=$2; shift 2;;
  --seed-inventory) seed_inventory=1; site=1; shift;;
  --site) site=1; shift;;
  --force) force=1; shift;;
  --all-features) all_features=1; shift;;
  --no-check) no_check=1; shift;;
  # --bootstrap ohne Pfad: Datei aus dem Overlay nehmen (erst nach dem Parsen auflösbar)
  --bootstrap) if [ $# -ge 2 ] && [ -f "$2" ]; then bootstrap=$2; shift 2; else bootstrap="-"; shift; fi;;
  *) echo "unbekannt: $1"; exit 1;; esac; done
if [ "$bootstrap" = "-" ]; then
  [ -n "$overlay" ] || { echo "--bootstrap ohne Pfad braucht --overlay"; exit 1; }
  bootstrap="$overlay/bootstrap-manager.rsc"
fi
if [ -n "$bootstrap" ] && [ ! -f "$bootstrap" ]; then echo "Bootstrap-Datei fehlt: $bootstrap"; exit 1; fi
root=$(cd "$(dirname "$0")/.." && pwd)
# Anmeldung vorab prüfen: Batch-SFTP (-b) fragt kein Passwort ab und meldet ohne passenden SSH-Key nur
# "Connection closed" (TODO 29)
probe_err=$(echo "pwd" | sftp -q -b - -P "$port" ${SFTP_OPTS:-} "$dest" 2>&1 >/dev/null) || {
  echo "FEHLER: keine SFTP-Anmeldung per SSH-Key an $dest (Port $port) möglich." >&2
  echo "  sftp: $(printf '%s' "$probe_err" | tail -1)" >&2
  echo "  Das Skript braucht einen SSH-Key (Batch-SFTP fragt kein Passwort ab):" >&2
  echo "  Public Key auf dem Gerät hinterlegen (/user/ssh-keys/import user=<user> public-key-file=<datei>)," >&2
  echo "  ssh-agent laden oder den Key per SFTP_OPTS=\"-i <key>\" angeben. Test: ssh -p $port $dest" >&2
  exit 1
}
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
      # Editor-Sicherungen (z.B. authorized_keys.alice~) nie hochladen
      *~|\#*\#) skipped="$skipped $n" ;;
      # die gemeinsame authorized_keys gilt seit DS3.3 nicht mehr ($cfmCheck lehnt sie ab)
      authorized_keys) skipped="$skipped $n"; echo "authorized_keys nicht hochgeladen: Keys je Person in authorized_keys.<user> (DS3.3)" >&2 ;;
      *.rsc|authorized_keys.*) [ -f "$d" ] && cp "$d" "$stage/work/" ;;
      *) skipped="$skipped $n" ;;
    esac
  done
  [ -n "$skipped" ] && echo "nicht hochgeladen (nur lokal):$skipped"
fi
# Editor-Sicherungen auch in hosts/, roles/, lib/ (z.B. sw1.rsc~ von tools/pull-site.sh) nie hochladen
find "$stage" -type f \( -name '*~' -o -name '#*#' -o -name '.#*' \) -delete
# Vorlage über ein gepflegtes Inventar zu legen wirft echte Seriennummern weg; die Geräte finden
# ihr Manifest dann nicht mehr (es liegt unter der Seriennummer).
if [ -n "$seed_inventory" ] && [ -z "$force" ]; then
  remote=$(mktemp)
  if printf 'get %s/meta/inventory.rsc %s\n' "$base" "$remote" | sftp -P "$port" ${SFTP_OPTS:-} "$dest" >/dev/null 2>&1 && [ -s "$remote" ]; then
    # "|| true": ohne Treffer liefert grep 1, und set -e/pipefail bräche das Skript sonst ab
    echte=$(grep -o '"serial"="[^"]*"' "$remote" | sed 's/.*="\(.*\)"/\1/' | grep -vE '^(SERIAL-.*)?$' | head -3 | tr '\n' ' ' || true)
    if [ -n "$echte" ]; then
      rm -f "$remote"
      echo "ABBRUCH: $dest:$base/meta/inventory.rsc enthält echte Seriennummern ($echte...)." >&2
      echo "Ein Upload der Vorlage würde sie überschreiben, die Geräte fänden ihr Manifest nicht mehr." >&2
      echo "Ohne --seed-inventory hochladen (Inventar bleibt unangetastet) oder --force erzwingen." >&2
      exit 1
    fi
  fi
  rm -f "$remote"
fi
# Site-Daten (DT2.2): Dateien direkt in work/ und hosts/. Ohne --site bleiben sie auf dem Manager, wie
# sie sind; mit --site nennen, welche dort anders sind und ersetzt werden.
if [ -z "$site" ]; then
  find "$stage/work" -maxdepth 1 -type f -delete
  rm -rf "$stage/work/hosts"
  echo "Site-Daten nicht hochgeladen (führt der Manager; --site lädt sie hoch, tools/pull-site.sh holt sie)"
elif [ -z "$seed_inventory" ]; then
  # Mit Overlay sind die Hostfiles der Vorlage (Labor: hosts/ap1.rsc, cm1.rsc …) nie Site-Daten - sie landeten
  # sonst auf dem Manager und in jedem Release (gefunden 2026-11-08 auf einem Standort). Dateien direkt in work/,
  # die das Overlay nicht hat, ergänzt die Vorlage weiter (meist leere Vorgaben wie mlag.rsc) - genannt.
  if [ -n "$overlay" ]; then
    for f in "$stage/work/hosts"/*; do
      [ -f "$f" ] && [ ! -f "$overlay/hosts/$(basename "$f")" ] && rm -f "$f"
    done
    ergaenzt=""
    for f in "$stage/work"/*; do
      [ -f "$f" ] && [ ! -f "$overlay/$(basename "$f")" ] && ergaenzt="$ergaenzt $(basename "$f")"
    done
    [ -n "$ergaenzt" ] && echo "--site: aus der Vorlage ergänzt (nicht im Overlay):$ergaenzt"
  fi
  remote=$(mktemp -d)
  (cd "$stage/work" && { find . -maxdepth 1 -type f; find ./hosts -type f 2>/dev/null; }) | sed 's|^\./||' | sort > "$remote/liste"
  mkdir -p "$remote/hosts"
  sed "s|.*|-get $base/work/& $remote/&|" "$remote/liste" | sftp -q -b - -P "$port" ${SFTP_OPTS:-} "$dest" >/dev/null 2>&1 || true
  anders=""; neu=""
  while IFS= read -r f; do
    if [ ! -f "$remote/$f" ]; then neu="$neu $f"; elif ! cmp -s "$remote/$f" "$stage/work/$f"; then anders="$anders $f"; fi
  done < "$remote/liste"
  rm -rf "$remote"
  if [ -n "$anders" ]; then echo "--site ersetzt auf dem Manager (dort anders):$anders"; fi
  if [ -n "$neu" ]; then echo "--site legt auf dem Manager neu an:$neu"; fi
fi
# Feature-Module (DG4.6): Site-Daten des Managers holen (wie tools/pull-site.sh), mit --site die hochgeladenen
# darüberlegen, dann entscheidet tools/feature-module.py. Im Zweifel (keine Site-Daten, kein python3) alle.
feat_unused=""; feat_weg=""
if [ -z "$all_features" ]; then
  sd=$(mktemp -d); trap 'rm -rf "$stage" "$sd"' EXIT
  sf() { sftp -q -b - -P "$port" ${SFTP_OPTS:-} "$dest"; }
  mkdir -p "$sd/work/hosts"
  # "-ls": ein fehlendes Verzeichnis bricht den Batch nicht ab; RouterOS nennt den Pfad samt Verzeichnis
  printf -- '-ls -1 %s/work\n-ls -1 %s/work/hosts\n-ls -1 %s/work/lib\n' "$base" "$base" "$base" | sf > "$sd/ls" 2>/dev/null || true
  tr -d '\r' < "$sd/ls" | grep -v '^sftp>' | sed "s|^/*$base/work/||" > "$sd/alle" || true
  grep -E '^lib/[a-z-]+\.[a-z0-9-]+\.rsc$' "$sd/alle" | sort > "$sd/lib-remote" || true
  grep -vE '^(hosts|lib|roles|web)$|^lib/|(^|/)\.' "$sd/alle" | grep -vE '/$' | sort > "$sd/liste" || true
  if [ -s "$sd/liste" ]; then sed "s|.*|-get $base/work/& $sd/work/&|" "$sd/liste" | sf >/dev/null 2>&1 || true; fi
  if [ -n "$site" ]; then
    find "$stage/work" -maxdepth 1 -type f -exec cp {} "$sd/work/" \;
    if [ -d "$stage/work/hosts" ]; then cp -r "$stage/work/hosts/." "$sd/work/hosts/"; fi
  fi
  if [ ! -f "$sd/work/global.rsc" ]; then
    echo "Feature-Module: keine Site-Daten auf dem Manager (und kein --site) - alle hochgeladen"
  elif ! command -v python3 >/dev/null; then
    echo "Feature-Module: python3 fehlt - alle hochgeladen" >&2
  elif ! feat_unused=$(python3 "$root/tools/feature-module.py" "$sd/work" "$stage/work/lib" 2>&1); then
    echo "Feature-Module: Prüfung fehlgeschlagen ($feat_unused) - alle hochgeladen" >&2; feat_unused=""
  fi
  for m in $feat_unused; do
    rm -f "$stage/work/$m"
    if grep -qxF "$m" "$sd/lib-remote"; then feat_weg="$feat_weg $m"; fi
  done
  if [ -n "$feat_unused" ]; then
    echo "Feature-Module nicht hochgeladen (die Site nutzt sie nicht):$(for m in $feat_unused; do m=${m#lib/}; printf ' %s' "${m%.rsc}"; done)"
  fi
  rm -rf "$sd"; trap 'rm -rf "$stage"' EXIT
fi
if [ -z "$seed_inventory" ] && [ -f "$stage/meta/inventory.rsc" ]; then
  rm -f "$stage/meta/inventory.rsc"
  echo "meta/inventory.rsc nicht hochgeladen (lebt auf dem Gerät, siehe --seed-inventory)"
fi
# Statische Prüfung (tools/rsc-check.py) des Stands, der hochgeht: Fehler wie ein Kommentar in einem Array-Literal
# fielen sonst erst bei $cfmCheck auf dem Manager auf (Hostfile, 2026-11-06). Hinweise brechen nicht ab.
if [ -z "$no_check" ]; then
  if ! command -v python3 >/dev/null; then
    echo "rsc-check: python3 fehlt - nicht geprüft" >&2
  else
    bs=""; [ -n "$bootstrap" ] && bs=$(cd "$(dirname "$bootstrap")" && pwd)/$(basename "$bootstrap")
    if ! rc_out=$(cd "$stage" && python3 "$root/tools/rsc-check.py" work meta ${bs:+"$bs"} 2>&1); then
      printf '%s\n' "$rc_out" | grep -v ' HINWEIS ' >&2 || true
      echo "ABBRUCH: rsc-check meldet Fehler (siehe oben) - nichts hochgeladen. --no-check überspringt die Prüfung." >&2
      exit 1
    fi
  fi
fi
# Verzeichnisse in einem Batch anlegen (idempotent). Für ein schon vorhandenes Verzeichnis meldet
# der SFTP-Server von RouterOS 'remote mkdir "…": Unknown status' (mit CR am Zeilenende) statt
# "already exists" - diese Zeilen ausblenden, andere Meldungen bleiben sichtbar.
mkbatch=$(mktemp); trap 'rm -rf "$stage" "$mkbatch"' EXIT
echo "-mkdir $base" > "$mkbatch"
(cd "$stage" && find . -mindepth 1 -type d | sed "s|^\./|-mkdir $base/|") >> "$mkbatch"
{ sftp -q -b "$mkbatch" -P "$port" ${SFTP_OPTS:-} "$dest" 2>&1 >/dev/null | tr -d '\r' | grep -v '^remote mkdir ".*": Unknown status$' >&2; } || true

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
# nicht gebrauchte Feature-Module auch auf dem Manager entfernen (erst nach einem vollständigen Upload)
if [ -n "$feat_weg" ]; then
  if for m in $feat_weg; do echo "rm $base/work/$m"; done | sftp -q -b - -P "$port" ${SFTP_OPTS:-} "$dest" >/dev/null 2>&1; then
    echo "Feature-Module auf dem Manager entfernt:$(for m in $feat_weg; do m=${m#lib/}; printf ' %s' "${m%.rsc}"; done)"
  else
    echo "WARNUNG: nicht gebrauchte Feature-Module auf dem Manager nicht entfernt:$feat_weg" >&2
  fi
fi
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
  echo "Nächster Schritt am Manager: /system script run cfm-mgr, dann \$cfmDiff und \$cfmRelease msg=\"…\""
  echo "(Ersteinrichtung: Bootstrap mit --bootstrap hochladen, dann /import bootstrap-manager.rsc)"
fi
