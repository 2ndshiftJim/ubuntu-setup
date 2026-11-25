#!/usr/bin/env bash
# First-time setup wizard. Plain bash prompts, no extra dependencies.
#
#   ./setup.sh                run the wizard, then offer to run install.sh
#   ./setup.sh --config-only  only write local.env / profiles.local; do not install
#
# Walks through: choosing profiles (and creating a gitignored local one), choosing or
# creating an SSH key, per-machine values, writing local.env, then a dry-run and the real
# install.sh. Safe to rerun: existing answers are offered as defaults, unrelated lines in
# local.env are kept, and nothing is overwritten without asking.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$ROOT/lib.sh"

CONFIG_ONLY=0
while [ $# -gt 0 ]; do
  case $1 in
    --config-only) CONFIG_ONLY=1 ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

[ "$(id -u)" -ne 0 ] || die "run as your normal user, not root"
[ -t 0 ] || [ "$CONFIG_ONLY" = 1 ] || die "needs a terminal (sudo and ssh-keygen prompt for input)"

load_config
SSH_KEYS=${SSH_KEYS:-}; K8S_MINOR=${K8S_MINOR:-}; KICKSTART=${KICKSTART:-1}
LOCAL_ENV="$ROOT/local.env"

# ---------- prompt helpers ----------
ask() { # ask "prompt" "default" -> sets REPLY
  local p=$1 d=${2:-} line
  if [ -n "$d" ]; then read -r -p "$p [$d]: " line || die "no input"; REPLY=${line:-$d}
  else read -r -p "$p: " line || die "no input"; REPLY=$line; fi
}
yesno() { # yesno "prompt" y|n -> status 0 for yes
  local p=$1 d=${2:-n} line hint="y/N"
  [ "$d" = y ] && hint="Y/n"
  while true; do
    read -r -p "$p [$hint]: " line || die "no input"
    case ${line:-$d} in [Yy]*) return 0 ;; [Nn]*) return 1 ;; esac
  done
}
heading() { printf '\n== %s ==\n' "$*"; }

# ---------- 1. profiles ----------
profile_exists() { [ -d "$ROOT/profiles/$1" ] || [ -d "$ROOT/profiles.local/$1" ]; }

describe_profile() { # name -> short summary of what the profile contains
  local d out="" f
  for d in "$ROOT/profiles/$1" "$ROOT/profiles.local/$1"; do
    [ -d "$d" ] || continue
    for f in apt-packages.txt tools.psv repos.txt dirs.txt; do [ -f "$d/$f" ] && out+="${f%.*} "; done
  done
  echo "${out:-empty}"
}

create_local_profile() {
  local name
  while true; do
    ask "New profile name (letters, digits, . _ -)" ""
    name=$REPLY
    [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "  invalid name"; continue; }
    if profile_exists "$name"; then echo "  '$name' already exists; pick another name or select it from the list"; continue; fi
    break
  done
  local dir="$ROOT/profiles.local/$name" line
  local -a dirs=() pkgs=()
  echo "Directories to create under \$HOME (relative paths such as Tools/foo; blank line to finish):"
  while true; do
    read -r -p "  dir: " line || die "no input"
    [ -z "$line" ] && break
    if [[ $line == /* || $line == *..* || ! $line =~ ^[A-Za-z0-9._/-]+$ ]]; then echo "  rejected (relative path, letters/digits/._-/ only)"; continue; fi
    dirs+=("${line%/}")
  done
  echo "Extra apt packages from Ubuntu's repos (blank line to finish):"
  while true; do
    read -r -p "  package: " line || die "no input"
    [ -z "$line" ] && break
    [[ $line =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || { echo "  rejected (not a valid package name)"; continue; }
    pkgs+=("$line")
  done
  mkdir -p "$dir"
  if [ ${#dirs[@]} -gt 0 ]; then printf '%s\n' "${dirs[@]}" >"$dir/dirs.txt"; fi
  if [ ${#pkgs[@]} -gt 0 ]; then printf '%s\n' "${pkgs[@]}" >"$dir/apt-packages.txt"; fi
  echo "  wrote profiles.local/$name (gitignored). Edit it later to add tools.psv or repos.txt."
  NEW_PROFILE=$name
}

choose_profiles() {
  heading "Profiles"
  echo "The base install is the same everywhere; profiles add role-specific extras."
  local -a avail=()
  local d n
  while IFS= read -r n; do avail+=("$n"); done < <(
    for d in "$ROOT"/profiles/*/ "$ROOT"/profiles.local/*/; do [ -d "$d" ] && basename "$d"; done | sort -u)
  local i=1
  if [ ${#avail[@]} -eq 0 ]; then echo "(no profiles defined yet)"; fi
  for n in "${avail[@]}"; do
    printf '  %d) %-12s %s\n' "$i" "$n" "$(describe_profile "$n")"; i=$((i + 1))
  done
  local cur=${PROFILES:-}
  local -a chosen=()
  if [ ${#avail[@]} -gt 0 ]; then
    while true; do
      ask "Numbers or names to enable (space/comma separated, 'none' for base only)" "${cur:-none}"
      chosen=(); local ok=1 tok
      if [ "$REPLY" != none ]; then
        for tok in ${REPLY//,/ }; do
          if [[ $tok =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le ${#avail[@]} ]; then chosen+=("${avail[$((tok - 1))]}")
          elif profile_exists "$tok"; then chosen+=("$tok")
          else echo "  unknown profile: $tok"; ok=0; fi
        done
      fi
      [ "$ok" = 1 ] && break
    done
  fi
  while yesno "Create a new local (gitignored) profile, e.g. for company-specific directories?" n; do
    NEW_PROFILE=""; create_local_profile
    [ -n "$NEW_PROFILE" ] && chosen+=("$NEW_PROFILE")
  done
  local IFS=,
  PROFILES="${chosen[*]:-}"
}

# ---------- 2. SSH key ----------
choose_ssh_keys() {
  heading "SSH key"
  echo "keychain keeps one ssh-agent across shells and attaches the keys you pick here."
  local -a keys=()
  local f
  for f in "$HOME"/.ssh/*.pub; do [ -f "$f" ] && [ -f "${f%.pub}" ] && keys+=("$(basename "${f%.pub}")"); done
  local i=1 k
  for k in "${keys[@]}"; do printf '  %d) %s\n' "$i" "$k"; i=$((i + 1)); done
  printf '  n) create a new key\n'
  local -a chosen=()
  while true; do
    ask "Keys to load (numbers/names, 'n' for new, 'none' for no key)" "${SSH_KEYS:-none}"
    chosen=(); local ok=1 tok
    if [ "$REPLY" != none ]; then
      for tok in ${REPLY//,/ }; do
        if [ "$tok" = n ]; then chosen+=("@new")
        elif [[ $tok =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le ${#keys[@]} ]; then chosen+=("${keys[$((tok - 1))]}")
        elif [[ $tok =~ ^[A-Za-z0-9._-]+$ ]]; then chosen+=("$tok")   # may be created later; warn below
        else echo "  invalid: $tok"; ok=0; fi
      done
    fi
    [ "$ok" = 1 ] && break
  done
  local -a final=()
  for k in "${chosen[@]}"; do
    if [ "$k" = @new ]; then
      create_ssh_key && final+=("$NEW_KEY")
    else
      [ -f "$HOME/.ssh/$k" ] || warn "$HOME/.ssh/$k does not exist yet; it is skipped until the file exists"
      final+=("$k")
    fi
  done
  SSH_KEYS="${final[*]:-}"
}

create_ssh_key() {
  [ -t 0 ] || { warn "no terminal; cannot create a key here"; return 1; }
  command -v ssh-keygen >/dev/null || { warn "ssh-keygen missing (install openssh-client)"; return 1; }
  local name
  while true; do
    ask "Key file name under ~/.ssh (e.g. id_ed25519_<purpose>)" ""
    name=$REPLY
    [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "  invalid name"; continue; }
    [ ! -e "$HOME/.ssh/$name" ] || { echo "  ~/.ssh/$name already exists"; continue; }
    break
  done
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  echo "ssh-keygen will ask for a passphrase. Use one."
  ssh-keygen -t ed25519 -a 100 -f "$HOME/.ssh/$name" || { warn "ssh-keygen failed"; return 1; }
  echo
  echo "Public key (add it to your Git host, e.g. GitHub or GitLab > Settings > SSH keys):"
  cat "$HOME/.ssh/$name.pub"
  read -r -p "Press Enter once it is added to your Git host... " _ || true
  NEW_KEY=$name
}

# ---------- 3. other per-machine values ----------
choose_misc() {
  heading "Other settings"
  if vendor_repos_selected | grep -qx kubernetes; then
    local def
    def=$(sed -n 's/^K8S_DEFAULT_MINOR="\(v[0-9.]*\)".*/\1/p' "$ROOT/scripts/apt-repos.sh")
    echo "Your profiles use the Kubernetes apt repo; kubectl should be within one minor of your clusters."
    while true; do
      ask "Kubernetes minor stream" "${K8S_MINOR:-$def}"
      [[ $REPLY =~ ^v[0-9]+\.[0-9]+$ ]] && break
      echo "  expected something like v1.37"
    done
    if [ "$REPLY" = "$def" ] && [ -z "$K8S_MINOR" ]; then K8S_MINOR=""; else K8S_MINOR=$REPLY; fi
  fi
  if yesno "Clone kickstart.nvim to ~/.config/nvim (skipped if it already exists)?" "$([ "$KICKSTART" = 0 ] && echo n || echo y)"; then
    KICKSTART=1
  else
    KICKSTART=0
  fi
}

vendor_repos_selected() { # vendor repos for the PROFILES chosen so far
  PROFILES="$PROFILES" vendor_repos
}

# ---------- 4. write local.env ----------
write_local_env() {
  heading "Summary"
  printf '  PROFILES   = %s\n  SSH_KEYS   = %s\n  K8S_MINOR  = %s\n  KICKSTART  = %s\n' \
    "${PROFILES:-(base only)}" "${SSH_KEYS:-(none)}" "${K8S_MINOR:-(repo default)}" "$KICKSTART"
  if [ -f "$LOCAL_ENV" ]; then
    echo "  existing local.env found; managed values will be replaced, other lines kept."
  fi
  yesno "Write $LOCAL_ENV?" y || { echo "Not written."; return 1; }
  local tmp; tmp=$(mktemp)
  {
    echo "# This machine only. Gitignored; never commit."
    echo "# Written by setup.sh; safe to edit by hand."
    echo "PROFILES=\"${PROFILES}\""
    echo "SSH_KEYS=\"${SSH_KEYS}\""
    [ -n "$K8S_MINOR" ] && echo "K8S_MINOR=\"${K8S_MINOR}\""
    [ "$KICKSTART" = 0 ] && echo "KICKSTART=0"
    if [ -f "$LOCAL_ENV" ]; then
      local rest
      rest=$(grep -vE '^(export[[:space:]]+)?(PROFILES|SSH_KEYS|K8S_MINOR|KICKSTART)=|^# This machine only|^# Written by setup.sh' "$LOCAL_ENV" | sed '/./,$!d' || true)
      [ -n "$rest" ] && { echo; echo "$rest"; }
    fi
  } >"$tmp"
  cat "$tmp" >"$LOCAL_ENV"; rm -f "$tmp"; chmod 600 "$LOCAL_ENV"
  echo "Wrote $LOCAL_ENV"
}

# ---------- 5. install ----------
run_install() {
  heading "Install"
  local m=()
  command -v git >/dev/null || m+=(git)
  command -v curl >/dev/null || m+=(curl)
  if [ ${#m[@]} -gt 0 ]; then
    echo "Missing prerequisites: ${m[*]}"
    yesno "Install them with sudo apt now?" y && { sudo apt update && sudo apt install -y "${m[@]}"; }
  fi
  echo "Preview (changes nothing):"
  "$ROOT/install.sh" --dry-run
  echo
  yesno "Run the real install now? (sudo will ask for your password)" y || { echo "Skipped. Run ./install.sh when ready."; return 0; }
  "$ROOT/install.sh"
}

post_notes() {
  heading "Still manual"
  cat <<'EOF'
  - Open a new terminal so the bashrc snippet and keychain take effect.
  - Nerd Font: install it on the Windows side and select it in your terminal profile.
  - Credentials: gh auth login (and vault login, etc. if you use them).
  - Check that `command -v kubectl npm` resolve to Linux binaries, not /mnt/c ones.
EOF
}

# ---------- main ----------
echo "machine-setup first-time wizard (Ctrl-C to abort; nothing is changed until you confirm)."
[ "$(uname -m)" = x86_64 ] || die "x86_64 only (found $(uname -m))"
NEW_PROFILE="" NEW_KEY=""
choose_profiles
choose_ssh_keys
choose_misc
write_local_env || exit 0
if [ "$CONFIG_ONLY" = 1 ]; then echo "--config-only: skipping install."; exit 0; fi
run_install
post_notes
