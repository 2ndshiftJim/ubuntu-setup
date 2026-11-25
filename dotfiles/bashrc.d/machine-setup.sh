# shellcheck shell=bash
# Sourced from ~/.bashrc by install.sh.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
# Machine-specific settings (SSH_KEYS, VAULT_ADDR, ...). Never committed.
[ -f "$HOME/.config/machine-setup/local.env" ] && . "$HOME/.config/machine-setup/local.env"
# Keep one ssh-agent across shells and load the keys named in SSH_KEYS (space-separated
# file names under ~/.ssh, set in local.env; nothing is loaded if unset). --noask: attach to
# the agent but never prompt (a hidden passphrase prompt inside $(...) hangs the shell).
# Keys are added on first use via AddKeysToAgent in ~/.ssh/config, or manually with ssh-add.
# Interactive shells only, and only if keychain and the key files exist.
case $- in
  *i*)
    if command -v keychain >/dev/null 2>&1 && [ -n "${SSH_KEYS:-}" ]; then
      _ms_keys=()
      for _ms_k in $SSH_KEYS; do [ -f "$HOME/.ssh/$_ms_k" ] && _ms_keys+=("$_ms_k"); done
      [ ${#_ms_keys[@]} -gt 0 ] && eval "$(keychain --eval --quiet --noask --agents ssh "${_ms_keys[@]}")"
      unset _ms_keys _ms_k
    fi
    ;;
esac
