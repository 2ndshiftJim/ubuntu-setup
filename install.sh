#!/usr/bin/env bash
# Set up an Ubuntu / WSL2-Ubuntu machine. Safe to rerun.
#
#   ./install.sh                     run every step
#   ./install.sh --dry-run           print what would happen, change nothing
#   ./install.sh --steps dirs,releases
#   ./install.sh --only resvg,yazi   limit the releases step to these tools
#
# Steps (in order): dirs, apt, repos, releases, links, dotfiles
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$ROOT/lib.sh"

MANIFEST="${MANIFEST:-$ROOT/manifest/tools.psv}"
STEPS="dirs,apt,repos,releases,links,dotfiles"
ONLY=""

while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY_RUN=1 ;;
    --steps) STEPS=$2; shift ;;
    --only) ONLY=$2; shift ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done
export DRY_RUN OPT_DIR BIN_DIR

want() { [[ ",$STEPS," == *",$1,"* ]]; }

preflight() {
  [ "$(id -u)" -ne 0 ] || die "run as your normal user, not root (sudo is used where needed)"
  # shellcheck disable=SC1091
  . /etc/os-release
  [ "${ID:-}" = ubuntu ] || warn "untested on ${ID:-unknown}; this is written for Ubuntu"
  if grep -qi microsoft /proc/version 2>/dev/null; then log "WSL detected"; fi
  [ "$(uname -m)" = x86_64 ] || die "manifest only has x86_64 assets (found $(uname -m))"
}

step_dirs() {
  log "creating directory layout"
  [ "$DRY_RUN" = 1 ] && { echo "[dry-run] mkdir -p ~/{Opt,Tools,Apps,Configuration_management,Shared_repos,...}"; return; }
  cd "$HOME"
  mkdir -p Opt Tools/{claude,keeper,sysdig} Apps/template/{dev,prod} \
    Configuration_management/template/{dev,prod} Shared_repos
}

step_apt() {
  log "installing apt packages"
  local pkgs
  pkgs=$(grep -vE '^\s*(#|$)' "$ROOT/apt-packages.txt" | tr '\n' ' ')
  if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] sudo apt install -y $pkgs"; return; fi
  sudo apt update
  # shellcheck disable=SC2086
  sudo apt install -y $pkgs
}

step_repos() {
  log "configuring vendor apt repos (HashiCorp, Kubernetes)"
  if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] bash scripts/apt-repos.sh"; return; fi
  bash "$ROOT/scripts/apt-repos.sh"
}

step_releases() {
  log "installing release binaries from $MANIFEST"
  local name version type sha url links
  while IFS='|' read -r -u 3 name version type sha url links; do
    [[ -z $name || $name == \#* ]] && continue
    if [ -n "$ONLY" ] && [[ ",$ONLY," != *",$name,"* ]]; then continue; fi
    install_release "$name" "$version" "$type" "$sha" "$url" "$links"
  done 3<"$MANIFEST"
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
  if [ ! -e "$HOME/.config/nvim" ]; then
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
