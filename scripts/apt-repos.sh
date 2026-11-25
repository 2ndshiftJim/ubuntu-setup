#!/usr/bin/env bash
# Adds the HashiCorp and Kubernetes apt repos, then installs terraform, vault, kubectl.
# Keys are fetched over HTTPS; the HashiCorp key is checked against a pinned fingerprint.
set -euo pipefail

K8S_MINOR="v1.37"   # bump deliberately; kubectl is pinned to this minor-version repo

# Current HashiCorp Linux package signing key. Source of truth:
# https://www.hashicorp.com/en/trust/security
# (replaced the 798AEC65...E701 key on 2026-09-10). Re-check this if the script aborts.
HASHI_FPR="D55C0D1AC78A8D8126CB631CFC9CA96ACA026560"

sudo install -d -m 0755 /etc/apt/keyrings

# --- HashiCorp ---
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

# --- Kubernetes ---
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "Kubernetes key fingerprint (informational, not pinned):"
gpg --show-keys --with-colons /etc/apt/keyrings/kubernetes-apt-keyring.gpg | awk -F: '/^fpr/{print "  "$10}'
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

sudo apt update
sudo apt install -y terraform vault kubectl
