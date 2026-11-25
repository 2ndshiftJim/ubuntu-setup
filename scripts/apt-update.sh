#!/usr/bin/env bash
# Upgrade specific managed apt packages (only upgrades; never installs new or removes).
# Needs sudo and a TTY, so run it in your own terminal:
#
#   bash scripts/apt-update.sh PKG [PKG...]
#   bash scripts/apt-update.sh --all      every managed package that has an update
#
# "Managed" = listed in apt-packages.txt or installed by scripts/apt-repos.sh.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
managed=$( { grep -vE '^\s*(#|$)' "$ROOT/apt-packages.txt"
             sed -n 's/^sudo apt install -y //p' "$ROOT/scripts/apt-repos.sh" | tr ' ' '\n'; } | sort -u)

[ $# -gt 0 ] || { sed -n '2,9p' "${BASH_SOURCE[0]}"; exit 2; }
if [ "$1" = --all ]; then
  mapfile -t pkgs < <(bash "$ROOT/scripts/check-updates.sh" --kind apt | awk -F'\t' 'NR>1{print $2}')
else
  pkgs=("$@")
fi
[ ${#pkgs[@]} -gt 0 ] || { echo "nothing to upgrade"; exit 0; }

for p in "${pkgs[@]}"; do
  grep -qxF -- "$p" <<<"$managed" || { echo "'$p' is not a managed package; refusing" >&2; exit 1; }
done

sudo apt update
sudo apt install --only-upgrade -y "${pkgs[@]}"
echo "--- installed versions ---"
dpkg-query -W -f='${Package}\t${Version}\n' "${pkgs[@]}"
