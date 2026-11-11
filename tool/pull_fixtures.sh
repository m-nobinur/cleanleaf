#!/usr/bin/env bash
# Pull only photos taken after the shot-list start from the phone, downscale to
# 1600 px, number them f001.jpg.. in capture order. Read-only on the phone.
# Env overrides (for offline testing): ADB, SRC, EPOCH_FILE, OUT. Pass --force to
# overwrite an existing set (renumbering invalidates labels.json).
set -euo pipefail

MAIN=/Users/nobin/Work/beenwise/cleanleaf
ADB=${ADB:-adb}
SRC=${SRC:-/sdcard/DCIM/Camera}
EPOCH_FILE=${EPOCH_FILE:-$MAIN/.local/orchestration/shotlist-start.epoch}
OUT=${OUT:-$MAIN/.local/fixtures/detection}
LONG_SIDE=1600

if [ "${1:-}" != "--force" ] && compgen -G "$OUT/f*.jpg" >/dev/null; then
  echo "$OUT already holds fixtures; renumbering would break labels.json. Use --force." >&2
  exit 1
fi

epoch=$(tr -d '[:space:]' <"$EPOCH_FILE")
mkdir -p "$OUT"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# "<mtime> <path>" per photo, newer than the epoch, oldest first.
$ADB shell "for f in $SRC/*; do stat -c '%Y %n' \"\$f\"; done" 2>/dev/null |
  tr -d '\r' |
  awk -v e="$epoch" '$1 > e && tolower($0) ~ /\.jpe?g$/' |
  sort -n -k1,1 -k2 >"$tmp/list"

n=0
while IFS= read -r line; do
  path=${line#* }
  n=$((n + 1))
  name=$(printf 'f%03d.jpg' "$n")
  $ADB pull "$path" "$tmp/raw.jpg" >/dev/null </dev/null
  sips -Z "$LONG_SIDE" -s format jpeg -s formatOptions 90 "$tmp/raw.jpg" --out "$OUT/$name" >/dev/null
  echo "$name <- $path"
done <"$tmp/list"

[ "$n" -gt 0 ] || { echo "no photos newer than epoch $epoch in $SRC" >&2; exit 1; }
# sips keeps the EXIF orientation tag over sideways pixels; make them upright.
dart run "$(dirname "$0")/upright_jpegs.dart" "$OUT"
echo "pulled $n photo(s) into $OUT"
