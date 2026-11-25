#!/usr/bin/env bash
# Set up an Ubuntu / WSL2-Ubuntu machine. Safe to rerun.
#
#   ./install.sh                     run every step
#   ./install.sh --dry-run           print what would happen, change nothing
#   ./install.sh --steps dirs,releases
#   ./install.sh --only resvg,yazi   limit the releases step to these tools
#   ./install.sh --profile k8s,dev   add profiles (profiles/NAME) on top of the base
#
# Profiles can also be set with PROFILES=... in local.env (gitignored); --profile overrides it.
# Steps (in order): dirs, apt, repos, releases, links, dotfiles
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$ROOT/lib.sh"

load_config
STEPS="dirs,apt,repos,releases,links,dotfiles"
ONLY=""

while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY_RUN=1 ;;
    --steps) STEPS=$2; shift ;;
    --only) ONLY=$2; shift ;;
    --profile|--profiles) PROFILES=$2; shift ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done
export DRY_RUN OPT_DIR BIN_DIR PROFILES

want() { [[ ",$STEPS," == *",$1,"* ]]; }

preflight() {
  [ "$(id -u)" -ne 0 ] || die "run as your normal user, not root (sudo is used where needed)"
  # shellcheck disable=SC1091
  . /etc/os-release
  [ "${ID:-}" = ubuntu ] || warn "untested on ${ID:-unknown}; this is written for Ubuntu"
  if grep -qi microsoft /proc/version 2>/dev/null; then log "WSL detected"; fi
  profile_dirs >/dev/null   # fail early on an unknown profile
  log "profiles: ${PROFILES:-(base only)}"
  [ "$(uname -m)" = x86_64 ] || die "manifest only has x86_64 assets (found $(uname -m))"
}

step_dirs() {
  log "creating directory layout"
  local -a dirs=(Opt Shared_repos)
  local f d
  while IFS= read -r f; do
    while IFS= read -r d; do
      [[ $d == /* || $d == *..* ]] && die "dirs.txt entries must be relative to \$HOME without '..': $d"
      dirs+=("$d")
    done < <(grep -vE '^\s*(#|$)' "$f" || true)
  done < <(layer_files "" dirs.txt)
  if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] mkdir -p (under ~) ${dirs[*]}"; return; fi
  (cd "$HOME" && mkdir -p "${dirs[@]}")
}

step_apt() {
  log "installing apt packages"
  local pkgs f
  pkgs=$(while IFS= read -r f; do grep -vE '^\s*(#|$)' "$f" || true; done \
           < <(layer_files apt-packages.txt apt-packages.txt) | sort -u | tr '\n' ' ')
  if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] sudo apt install -y $pkgs"; return; fi
  sudo apt update
  # shellcheck disable=SC2086
  sudo apt install -y $pkgs
}

step_repos() {
  local vendors; vendors=$(vendor_repos | tr '\n' ' ')
  if [ -z "${vendors// /}" ]; then log "no vendor apt repos requested by profiles; skipping"; return; fi
  log "configuring vendor apt repos: $vendors"
  if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] bash scripts/apt-repos.sh $vendors"; return; fi
  # shellcheck disable=SC2086
  bash "$ROOT/scripts/apt-repos.sh" $vendors
}

step_releases() {
  local -a files; mapfile -t files < <(manifest_files)
  log "installing release binaries from ${#files[@]} manifest file(s)"
  local name version type sha url links seen=","
  while IFS='|' read -r -u 3 name version type sha url links; do
    [[ -z $name || $name == \#* ]] && continue
    [[ $seen == *",$name,"* ]] && die "tool '$name' is defined in more than one manifest layer"
    seen+="$name,"
    if [ -n "$ONLY" ] && [[ ",$ONLY," != *",$name,"* ]]; then continue; fi
    install_release "$name" "$version" "$type" "$sha" "$url" "$links"
  done 3< <(cat "${files[@]}")
}

step_links() {
  # Ubuntu renames these binaries to avoid package conflicts.
  log "linking Debian-renamed binaries (bat, fd)"
  [ "$DRY_RUN" = 1 ] && { echo "[dry-run] ln -s batcat/fdfind into $BIN_DIR"; return; }
  mkdir -p "$BIN_DIR"
  [ -x /usr/bin/batcat ] && ln -sfn /usr/bin/batcat "$BIN_DIR/bat"
  [ -x /usr/bin/fdfind ] && ln -sfn /usr/bin/fdfind "$BIN_DIR/fd"
  return 0
}

step_dotfiles() {
  log "installing dotfiles"
  if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] kickstart.nvim -> ~/.config/nvim; bashrc snippet"; return; fi
  if [ "${KICKSTART:-1}" = 0 ]; then
    log "KICKSTART=0; skipping kickstart.nvim"
  elif [ ! -e "$HOME/.config/nvim" ]; then
    git clone --depth 1 https://github.com/nvim-lua/kickstart.nvim.git "$HOME/.config/nvim"
  else
    log "~/.config/nvim exists; leaving it alone"
  fi
  local cfg="$HOME/.config/machine-setup"
  mkdir -p "$cfg"
  cp "$ROOT/dotfiles/bashrc.d/machine-setup.sh" "$cfg/bashrc.sh"
  # Machine-specific values (gitignored) live in local.env, never in the repo.
  [ -f "$ROOT/local.env" ] && cp "$ROOT/local.env" "$cfg/local.env"
  touch "$HOME/.bashrc"
  grep -qF 'machine-setup/bashrc.sh' "$HOME/.bashrc" || \
    printf '\n# machine-setup\n[ -f "$HOME/.config/machine-setup/bashrc.sh" ] && . "$HOME/.config/machine-setup/bashrc.sh"\n' >> "$HOME/.bashrc"
}

preflight
for s in dirs apt repos releases links dotfiles; do
  want "$s" && "step_$s"
done
log "done"
