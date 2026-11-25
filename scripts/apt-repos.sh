#!/usr/bin/env bash
# Adds vendor apt repos and installs their packages (needs sudo).
#
#   bash scripts/apt-repos.sh [hashicorp] [kubernetes]
#
# With no arguments, uses the vendors listed in repos.txt of the selected profiles
# (PROFILES in local.env). Packages per vendor come from manifest/vendor-repos.psv.
# Keys are fetched over HTTPS; the HashiCorp key is checked against a pinned fingerprint.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib.sh
. "$ROOT/lib.sh"
load_config

# Default Kubernetes minor stream; override per machine with K8S_MINOR in local.env.
# Bump deliberately; kubectl is pinned to this minor-version repo, and should stay within
# one minor of your clusters.
K8S_DEFAULT_MINOR="v1.37"
K8S_MINOR="${K8S_MINOR:-$K8S_DEFAULT_MINOR}"

# Current HashiCorp Linux package signing key. Source of truth:
# https://www.hashicorp.com/en/trust/security
# (replaced the 798AEC65...E701 key on 2026-09-10). Re-check this if the script aborts.
HASHI_FPR="D55C0D1AC78A8D8126CB631CFC9CA96ACA026560"

if [ $# -gt 0 ]; then vendors=("$@"); else mapfile -t vendors < <(vendor_repos); fi
[ ${#vendors[@]} -gt 0 ] || { echo "no vendor repos requested (pass names or set PROFILES); nothing to do"; exit 0; }

sudo install -d -m 0755 /etc/apt/keyrings

add_hashicorp() {
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  actual=$(gpg --show-keys --with-colons /usr/share/keyrings/hashicorp-archive-keyring.gpg | awk -F: '/^fpr/{print $10; exit}')
  echo "HashiCorp key fingerprint: $actual"
  if [ "$actual" != "$HASHI_FPR" ]; then
    echo "FINGERPRINT MISMATCH (expected $HASHI_FPR) - aborting" >&2
    sudo rm -f /usr/share/keyrings/hashicorp-archive-keyring.gpg
    exit 1
  fi
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
}

add_kubernetes() {
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "Kubernetes key fingerprint (informational, not pinned):"
  gpg --show-keys --with-colons /etc/apt/keyrings/kubernetes-apt-keyring.gpg | awk -F: '/^fpr/{print "  "$10}'
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
}

pkgs=()
for v in "${vendors[@]}"; do
  case $v in
    hashicorp) add_hashicorp ;;
    kubernetes) add_kubernetes ;;
    *) echo "unknown vendor repo: $v" >&2; exit 1 ;;
  esac
  read -ra p < <(awk -F'|' -v n="$v" '$1==n{print $2}' "$ROOT/manifest/vendor-repos.psv") || true
  pkgs+=("${p[@]}")
done

sudo apt update
sudo apt install -y "${pkgs[@]}"
