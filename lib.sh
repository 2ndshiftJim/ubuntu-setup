#!/usr/bin/env bash
# shellcheck shell=bash
# Shared helpers. Sourced by install.sh and the scripts/ tools.

OPT_DIR="${OPT_DIR:-$HOME/Opt}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
DRY_RUN="${DRY_RUN:-0}"

LIB_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

log() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---- per-machine config and profiles -------------------------------------------------
# local.env (gitignored) holds machine-specific settings: PROFILES, SSH_KEYS, K8S_MINOR,
# KICKSTART, plus anything exported to shells. A PROFILES value already in the environment
# wins over local.env. Each profile is a directory under profiles/ (committed, generic) or
# profiles.local/ (gitignored, for anything you would not push) that layers extra
# apt-packages.txt, tools.psv, update-notes.psv, repos.txt, dirs.txt on top of the base.
load_config() {
  local had=${PROFILES+x} saved=${PROFILES:-}
  # shellcheck disable=SC1091
  if [ -f "$LIB_ROOT/local.env" ]; then . "$LIB_ROOT/local.env"; fi
  if [ -n "$had" ]; then PROFILES=$saved; fi
  PROFILES=${PROFILES:-}
  return 0
}

# Print the directory of each selected profile; die if one does not exist.
profile_dirs() {
  local p d found
  for p in ${PROFILES//,/ }; do
    [[ $p =~ ^[A-Za-z0-9._-]+$ ]] || die "bad profile name: $p"
    found=""
    for d in "$LIB_ROOT/profiles/$p" "$LIB_ROOT/profiles.local/$p"; do
      if [ -d "$d" ]; then echo "$d"; found=1; fi
    done
    [ -n "$found" ] || die "profile '$p' not found in profiles/ or profiles.local/"
  done
}

# layer_files BASE_RELPATH PROFILE_FILENAME -> existing files, base first, then each profile.
layer_files() {
  local d
  if [ -n "$1" ] && [ -f "$LIB_ROOT/$1" ]; then echo "$LIB_ROOT/$1"; fi
  while IFS= read -r d; do
    if [ -f "$d/$2" ]; then echo "$d/$2"; fi
  done < <(profile_dirs)
}

# Release manifests in effect. MANIFEST (env) overrides everything, for testing.
manifest_files() {
  if [ -n "${MANIFEST:-}" ]; then echo "$MANIFEST"; else layer_files manifest/tools.psv tools.psv; fi
}

# Vendor apt repos requested by the selected profiles (names from manifest/vendor-repos.psv).
vendor_repos() {
  local f
  while IFS= read -r f; do grep -vE '^\s*(#|$)' "$f" || true; done < <(layer_files "" repos.txt) | sort -u
}

# Every apt package this repo manages: base + profile lists + vendor-repo packages.
managed_apt_packages() {
  local f v
  while IFS= read -r f; do grep -vE '^\s*(#|$)' "$f" || true; done < <(layer_files apt-packages.txt apt-packages.txt)
  while IFS= read -r v; do
    awk -F'|' -v n="$v" '$1==n{print $2}' "$LIB_ROOT/manifest/vendor-repos.psv" | tr ' ' '\n'
  done < <(vendor_repos)
}

# True when every "src:link" pair already resolves to a file inside $1.
already_installed() {
  local dir=$1 links=$2 pair link target
  local -a pairs
  IFS=',' read -ra pairs <<<"$links"
  for pair in "${pairs[@]}"; do
    link=${pair#*:}
    target=$(readlink -f "$BIN_DIR/$link" 2>/dev/null || true)
    [[ $target == "$dir"/* && -x $target ]] || return 1
  done
}

# install_release NAME VERSION TYPE SHA256 URL_TEMPLATE LINKS
#   TYPE:  tar.gz | gz | zip | raw | appimage
#   LINKS: comma-separated "path/inside/install/dir:linkname" ({version} is substituted)
# Downloads to $OPT_DIR/NAME-VERSION, verifies SHA256 (fails hard on mismatch),
# extracts, and symlinks into $BIN_DIR. Safe to rerun.
install_release() {
  local name=$1 version=$2 type=$3 sha=$4 url_tpl=$5 links=$6
  local url=${url_tpl//\{version\}/$version}
  links=${links//\{version\}/$version}
  local dir=$OPT_DIR/$name-$version file=${url##*/}
  local -a pairs
  local pair

  [[ $sha =~ ^[0-9a-f]{64}$ ]] || die "$name: manifest sha256 is missing or malformed"
  [[ $url == https://* ]] || die "$name: URL must be https"

  if already_installed "$dir" "$links"; then
    log "$name $version already installed"
    return 0
  fi
  log "installing $name $version"
  if [ "$DRY_RUN" = 1 ]; then
    echo "[dry-run] download $url (sha256 $sha) -> $dir"
    return 0
  fi

  mkdir -p "$dir" "$BIN_DIR"
  (
    cd "$dir"
    if [ ! -f "$file" ]; then
      curl -fsSL -o "$file.part" "$url"
      mv "$file.part" "$file"
    fi
    if ! echo "$sha  $file" | sha256sum -c --quiet -; then
      rm -f "$file"
      echo "ERROR: checksum mismatch for $file" >&2
      exit 1
    fi
    case $type in
      tar.gz) tar -xzf "$file" ;;
      gz) gunzip -kf "$file" ;;   # single gzipped binary -> ${file%.gz}
      zip) unzip -q -o "$file" ;;
      raw) chmod 755 "$file" ;;
      appimage) chmod 755 "$file"; "./$file" --appimage-extract >/dev/null ;;
      *) echo "ERROR: unknown type $type" >&2; exit 1 ;;
    esac
  ) || die "$name: install failed"

  IFS=',' read -ra pairs <<<"$links"
  for pair in "${pairs[@]}"; do
    [ -e "$dir/${pair%%:*}" ] || die "$name: ${pair%%:*} not found after extraction"
    chmod +x "$dir/${pair%%:*}"
    ln -sfn "$dir/${pair%%:*}" "$BIN_DIR/${pair#*:}"
  done
}
