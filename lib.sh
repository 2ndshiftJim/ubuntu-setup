#!/usr/bin/env bash
# shellcheck shell=bash
# Shared helpers. Sourced by install.sh.

OPT_DIR="${OPT_DIR:-$HOME/Opt}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
DRY_RUN="${DRY_RUN:-0}"

log() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

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
