# machine-setup

Rerunnable bash automation that sets up Ubuntu / WSL2-Ubuntu (x86_64) work machines. Target is the user's own work-issued laptop; the repo is meant to be pushed to a personal GitHub account.

## Layout
- `install.sh` — entry point. Steps in order: `dirs, apt, repos, releases, links, dotfiles`. Flags: `--dry-run`, `--steps a,b`, `--only tool,tool`.
- `lib.sh` — `install_release NAME VERSION TYPE SHA256 URL LINKS` (types: `tar.gz | gz | zip | raw | appimage`). Verifies the hash, fails hard on mismatch, installs to `$OPT_DIR/NAME-VERSION`, symlinks into `$BIN_DIR`. `OPT_DIR`/`BIN_DIR` env vars override `~/Opt` and `~/.local/bin` for testing.
- `manifest/tools.psv` — pipe-delimited release-binary manifest (one tool per row, pinned version + SHA-256).
- `apt-packages.txt` — packages from Ubuntu's own repos.
- `scripts/apt-repos.sh` — third-party apt repos (HashiCorp, Kubernetes) with key handling.
- `dotfiles/` — bashrc snippet (PATH, zoxide, keychain to persist the ssh-agent and load the GitHub key, optional `local.env`); kickstart.nvim is cloned by the `dotfiles` step.
- `.claude/skills/add-software/SKILL.md` — procedure for adding new software (use `/add-software`).

## Conventions
- Install layout: versioned directory under `~/Opt`, symlink into `~/.local/bin`. Upgrading = change the manifest row and rerun.
- Prefer Ubuntu apt when the package exists and is recent; otherwise official release binaries; vendor apt repos only for HashiCorp/Kubernetes (user's decision).
- Every download is verified against a pinned SHA-256. Use the digest GitHub publishes for the asset. If none exists, compute it locally, say so in a manifest comment, and tell the user.
- Scripts must be idempotent and rerunnable. Use `set -euo pipefail`. Never read from stdin inside the manifest loop (it uses fd 3).

## Security rules
- No credentials, tokens, internal URLs, hostnames, Vault addresses or company-specific values in the repo. Machine-specific values go in the gitignored `local.env`.
- Key fingerprints in `apt-repos.sh` are pinned from the vendor's official page. If one mismatches, abort and re-verify against the vendor's site; never just update it to whatever was downloaded.
- Don't commit or push unless the user asks.

## Environment gotchas (learned the hard way)
- Claude Code's shell has no TTY: `sudo` cannot prompt. Give the user the exact sudo command (or a script to read first) to run in another terminal, then verify afterwards.
- The GitHub SSH key is passphrase-protected and unlocked by keychain in the user's own terminals. Claude Code's shell has no ssh-agent or TTY, so Claude can commit but cannot `git push`; the user pushes from their own terminal. Verify a push afterwards with `git ls-remote https://github.com/<user>/<repo>.git` (public repo, no auth needed).
- Debian/Ubuntu rename some binaries: `bat`→`batcat`, `fd`→`fdfind`. The `links` step handles this.
- Ubuntu 26.04 has no `libfuse2`: AppImages are extracted (`--appimage-extract`), not mounted.
- `gh release download` demands auth even for public repos; use `curl` with the direct release URL.
- Ubuntu's apt `neovim` is too old for current kickstart; neovim comes from the release manifest.
- WSL puts Windows binaries on PATH (e.g. a Rancher Desktop `kubectl` under `/mnt/c`); check `command -v` resolves to the Linux one.
- Nerd Fonts must be installed on the Windows side; not automatable from WSL.

## Testing
Test release changes with `OPT_DIR=$TMP/Opt BIN_DIR=$TMP/bin ./install.sh --steps releases [--only name]` using a temp dir, plus `./install.sh --dry-run`. `apt`/`repos` steps need sudo; test them on a disposable WSL instance, not by guessing.
