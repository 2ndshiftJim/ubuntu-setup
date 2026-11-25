# shellcheck shell=bash
# Sourced from ~/.bashrc by install.sh.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
# Keep one ssh-agent across shells; prompts for the key passphrase once per boot.
# Interactive shells only, and only if keychain and the key exist.
case $- in
  *i*)
    if command -v keychain >/dev/null 2>&1 && [ -f "$HOME/.ssh/id_ed25519_github_personal" ]; then
      eval "$(keychain --eval --quiet --agents ssh id_ed25519_github_personal)"
    fi
    ;;
esac
# Machine-specific settings (e.g. VAULT_ADDR). Never committed.
[ -f "$HOME/.config/machine-setup/local.env" ] && . "$HOME/.config/machine-setup/local.env"
