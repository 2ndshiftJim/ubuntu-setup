#!/usr/bin/env bash
# Report available updates for everything this repo installs. Read-only, needs no sudo.
#
#   scripts/check-updates.sh                 updates only, as TSV on stdout
#   scripts/check-updates.sh --all           include up-to-date rows
#   scripts/check-updates.sh --kind release  only release|apt|k8s
#   scripts/check-updates.sh --only a,b      only these names
#
# Columns: kind  name  current  latest  status  flags  newsha  link  notes
#   status: update | ok | error
#   flags:  comma list, informational warnings:
#     major-bump        major version changes (breaking changes likely)
#     pre1-minor        0.x minor bump (semver allows breaking changes)
#     fresh-<N>d        release published under 7 days ago (consider waiting)
#     security          apt update comes from a -security pocket
#     no-digest         release publishes no SHA-256; update-release.sh needs --compute-hash
#     asset-missing     latest release has no asset matching the manifest URL template
#     stale-apt-index   apt lists older than 24h; run `sudo apt update` for accurate apt rows
#   notes: per-tool caveats from manifest/update-notes.psv
# Unauthenticated GitHub API allows 60 requests/hour; set GITHUB_TOKEN to raise it.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib.sh
. "$ROOT/lib.sh"
load_config   # PROFILES, K8S_MINOR from local.env decide what is checked
APT_REPOS="$ROOT/scripts/apt-repos.sh"
mapfile -t MANIFESTS < <(manifest_files)
if [ -n "${NOTES:-}" ]; then NOTE_FILES=("$NOTES"); else mapfile -t NOTE_FILES < <(layer_files manifest/update-notes.psv update-notes.psv); fi

ALL=0 KIND="" ONLY=""
while [ $# -gt 0 ]; do
  case $1 in
    --all) ALL=1 ;;
    --kind) KIND=$2; shift ;;
    --only) ONLY=$2; shift ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

want_kind() { [ -z "$KIND" ] || [ "$KIND" = "$1" ]; }
want_name() { [ -z "$ONLY" ] || [[ ",$ONLY," == *",$1,"* ]]; }

api() { # GET a GitHub API path; token (if any) is sent only to api.github.com
  local -a auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsS --max-time 20 -H 'Accept: application/vnd.github+json' "${auth[@]}" "https://api.github.com/$1"
}

note_for() { awk -F'|' -v n="$1" '$1==n{print $2; exit}' "${NOTE_FILES[@]}" 2>/dev/null || true; }

newer() { # true if $2 sorts strictly after $1 by version order
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$2" ]
}

semver_flags() { # current latest -> prints "major-bump" / "pre1-minor" when applicable
  local c=${1#*:} l=${2#*:}
  local cmaj=${c%%.*} lmaj=${l%%.*}
  c=${c%%[-+~]*}; l=${l%%[-+~]*}
  if [ "$cmaj" != "$lmaj" ]; then echo major-bump
  elif [ "$cmaj" = 0 ]; then
    local cmin=${c#*.}; cmin=${cmin%%.*}; local lmin=${l#*.}; lmin=${lmin%%.*}
    [ "$cmin" != "$lmin" ] && echo pre1-minor
  fi
  return 0
}

emit() { # kind name current latest status flags newsha link
  local kind=$1 name=$2 cur=$3 lat=$4 status=$5 flags=$6 sha=$7 link=$8
  if [ "$status" = ok ] && [ "$ALL" != 1 ]; then return 0; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$kind" "$name" "$cur" "$lat" "$status" "${flags:--}" "${sha:--}" "${link:--}" "$(note_for "$name")"
}

join_flags() { local IFS=,; echo "$*"; }

# ---------- release binaries ----------
check_releases() {
  local name version type sha url links re='^https://github\.com/([^/]+)/([^/]+)/releases/download/(v?)\{version\}/(.+)$'
  while IFS='|' read -r -u 3 name version type sha url links; do
    [[ -z $name || $name == \#* ]] && continue
    want_name "$name" || continue
    if [[ ! $url =~ $re ]]; then
      emit release "$name" "$version" "?" error "non-github-url" "" ""; continue
    fi
    local owner=${BASH_REMATCH[1]} repo=${BASH_REMATCH[2]} prefix=${BASH_REMATCH[3]} tpl=${BASH_REMATCH[4]}
    local json
    if ! json=$(api "repos/$owner/$repo/releases/latest"); then
      emit release "$name" "$version" "?" error "api-failed(rate-limit?)" "" ""; continue
    fi
    local tag latest published
    tag=$(jq -r '.tag_name' <<<"$json")
    latest=${tag#"$prefix"}
    published=$(jq -r '.published_at // empty' <<<"$json")
    local link="https://github.com/$owner/$repo/releases/tag/$tag"
    if ! newer "$version" "$latest"; then
      emit release "$name" "$version" "$latest" ok "" "" "$link"; continue
    fi
    local -a flags=()
    local f; f=$(semver_flags "$version" "$latest"); [ -n "$f" ] && flags+=("$f")
    if [ -n "$published" ]; then
      local age=$(( ( $(date +%s) - $(date -d "$published" +%s) ) / 86400 ))
      [ "$age" -lt 7 ] && flags+=("fresh-${age}d")
    fi
    local asset=${tpl//\{version\}/$latest} digest
    if ! jq -e --arg n "$asset" '.assets[] | select(.name==$n)' >/dev/null <<<"$json"; then
      flags+=(asset-missing); digest=""
    else
      digest=$(jq -r --arg n "$asset" '.assets[] | select(.name==$n) | .digest // ""' <<<"$json")
      digest=${digest#sha256:}
      [ -z "$digest" ] && flags+=(no-digest)
    fi
    emit release "$name" "$version" "$latest" update "$(join_flags "${flags[@]}")" "$digest" "$link"
  done 3< <(cat "${MANIFESTS[@]}")
}

# ---------- apt (Ubuntu + vendor repos; managed_apt_packages is in lib.sh) ----------
check_apt() {
  local -a extra=()
  local stamp=/var/lib/apt/periodic/update-stamp
  if [ -f "$stamp" ] && [ $(( $(date +%s) - $(stat -c %Y "$stamp") )) -gt 86400 ]; then
    extra+=(stale-apt-index)
  fi
  local managed; managed=$(managed_apt_packages | sort -u)
  local line pkg suite new old
  while IFS= read -r line; do
    # format: pkg/suite[,suite] NEWVER ARCH [upgradable from: OLDVER]
    [[ $line == */* ]] || continue
    pkg=${line%%/*}
    grep -qxF "$pkg" <<<"$managed" || continue
    want_name "$pkg" || continue
    suite=${line#*/}; suite=${suite%% *}
    new=$(awk '{print $2}' <<<"$line")
    old=${line##*upgradable from: }; old=${old%]}
    local -a flags=("${extra[@]}")
    local f; f=$(semver_flags "$old" "$new"); [ -n "$f" ] && flags+=("$f")
    [[ $suite == *-security* ]] && flags+=(security)
    emit apt "$pkg" "$old" "$new" update "$(join_flags "${flags[@]}")" "" ""
  done < <(apt list --upgradable 2>/dev/null)
  if [ "$ALL" = 1 ]; then
    local up; up=$(apt list --upgradable 2>/dev/null | cut -d/ -f1)
    while IFS= read -r pkg; do
      grep -qxF "$pkg" <<<"$up" && continue
      want_name "$pkg" || continue
      local v; v=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)
      [ -n "$v" ] && emit apt "$pkg" "$v" "$v" ok "" "" ""
    done <<<"$managed"
  fi
}

# ---------- Kubernetes apt repo minor stream ----------
check_k8s() {
  want_name kubectl || return 0
  vendor_repos | grep -qx kubernetes || return 0   # only machines whose profiles use the k8s repo
  local cur next major minor
  cur=${K8S_MINOR:-$(sed -n 's/^K8S_DEFAULT_MINOR="\(v[0-9.]*\)".*/\1/p' "$APT_REPOS")}
  [ -n "$cur" ] || return 0
  major=${cur#v}; major=${major%%.*}; minor=${cur##*.}
  next="v$major.$((minor + 1))"
  if curl -fsI --max-time 20 "https://pkgs.k8s.io/core:/stable:/$next/deb/Release.key" >/dev/null 2>&1; then
    emit k8s kubectl-minor "$cur" "$next" update "minor-stream" "" "https://kubernetes.io/releases/"
  elif [ "$ALL" = 1 ]; then
    emit k8s kubectl-minor "$cur" "$cur" ok "" "" ""
  fi
}

printf 'kind\tname\tcurrent\tlatest\tstatus\tflags\tnewsha\tlink\tnotes\n'
want_kind release && check_releases
want_kind apt && check_apt
want_kind k8s && check_k8s
exit 0
