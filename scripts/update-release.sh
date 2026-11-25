#!/usr/bin/env bash
# Update one release-binary tool in manifest/tools.psv to its latest release and install it.
#
#   scripts/update-release.sh NAME [--compute-hash] [--dry-run]
#
# Looks up the latest release via check-updates.sh, rewrites the manifest row's version and
# SHA-256, then runs `install.sh --steps releases --only NAME` (which verifies the hash).
# If the install fails, the manifest is restored. Old versions stay in $OPT_DIR for rollback.
#
#   --compute-hash  needed when the release publishes no digest: downloads the asset over
#                   HTTPS, hashes it locally, and records that in a manifest comment.
#   --dry-run       show the new row, change nothing.
# Honors MANIFEST, OPT_DIR and BIN_DIR env vars (for testing in a temp dir).
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="${MANIFEST:-$ROOT/manifest/tools.psv}"
export MANIFEST

NAME="" COMPUTE=0 DRY=0
while [ $# -gt 0 ]; do
  case $1 in
    --compute-hash) COMPUTE=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) echo "unknown argument: $1" >&2; exit 2 ;;
    *) [ -z "$NAME" ] || { echo "one tool at a time" >&2; exit 2; }; NAME=$1 ;;
  esac
  shift
done
[ -n "$NAME" ] || { echo "usage: update-release.sh NAME [--compute-hash] [--dry-run]" >&2; exit 2; }
[[ $NAME =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad tool name" >&2; exit 2; }

row=$(bash "$ROOT/scripts/check-updates.sh" --kind release --only "$NAME" | awk -F'\t' 'NR>1')
[ -n "$row" ] || { echo "$NAME: already at latest (or not in manifest)"; exit 0; }
IFS=$'\t' read -r _ _ cur latest status flags newsha link _ <<<"$row"
[ "$status" = update ] || { echo "$NAME: check failed ($flags)" >&2; exit 1; }
[[ $flags == *asset-missing* ]] && { echo "$NAME: latest release $latest has no matching asset; update the manifest URL by hand (see $link)" >&2; exit 1; }

# Manifest row for this tool (url template drives the download for --compute-hash).
mrow=$(awk -F'|' -v n="$NAME" '$1==n' "$MANIFEST")
url_tpl=$(cut -d'|' -f5 <<<"$mrow")
url=${url_tpl//\{version\}/$latest}
note=""
if [ -z "$newsha" ] || [ "$newsha" = "-" ]; then
  [ "$COMPUTE" = 1 ] || { echo "$NAME $latest publishes no SHA-256 digest. Re-run with --compute-hash to pin a locally computed hash (tell the user)." >&2; exit 1; }
  [[ $url == https://* ]] || { echo "refusing non-https url" >&2; exit 1; }
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --max-time 300 -o "$tmp/asset" "$url"
  newsha=$(sha256sum "$tmp/asset" | cut -d' ' -f1)
  note="# $NAME: release publishes no digest; this hash was computed locally on first download over HTTPS."
fi
[[ $newsha =~ ^[0-9a-f]{64}$ ]] || { echo "bad sha256 '$newsha'" >&2; exit 1; }

echo "$NAME: $cur -> $latest  (sha256 $newsha)"
echo "release notes: $link"
[ "$DRY" = 1 ] && { echo "[dry-run] no changes made"; exit 0; }

backup=$(mktemp); cp "$MANIFEST" "$backup"
out=$(mktemp)
awk -F'|' -v OFS='|' -v n="$NAME" -v v="$latest" -v s="$newsha" -v note="$note" '
  # drop a stale "# NAME: ... digest ..." comment; re-add below only if we computed the hash
  $0 ~ "^# " n ": .*digest" { next }
  $1 == n { if (note != "") print note; $2 = v; $4 = s }
  { print }' "$backup" >"$out"
cat "$out" >"$MANIFEST"; rm -f "$out"

if ! "$ROOT/install.sh" --steps releases --only "$NAME"; then
  cp "$backup" "$MANIFEST"; rm -f "$backup"
  echo "$NAME: install failed; manifest restored" >&2
  exit 1
fi
rm -f "$backup"
echo "$NAME updated to $latest. Previous version dir under \${OPT_DIR:-~/Opt} was left for rollback."
