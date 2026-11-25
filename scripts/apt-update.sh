#!/usr/bin/env bash
# Upgrade specific managed apt packages (only upgrades; never installs new or removes).
# Needs sudo and a TTY, so run it in your own terminal:
#
#   bash scripts/apt-update.sh PKG [PKG...]
#   bash scripts/apt-update.sh --all      every managed package that has an update
#
# "Managed" = listed in apt-packages.txt (base or a selected profile) or installed from a
# vendor repo the profiles request (manifest/vendor-repos.psv).
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib.sh
. "$ROOT/lib.sh"
load_config
managed=$(managed_apt_packages | sort -u)

[ $# -gt 0 ] || { sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 2; }
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
