# shellcheck shell=bash
# Sourced from ~/.bashrc by install.sh.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
# Machine-specific settings (e.g. VAULT_ADDR). Never committed.
[ -f "$HOME/.config/machine-setup/local.env" ] && . "$HOME/.config/machine-setup/local.env"
