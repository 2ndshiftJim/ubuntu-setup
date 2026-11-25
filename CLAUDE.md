# machine-setup

Rerunnable bash automation that sets up Ubuntu / WSL2-Ubuntu (x86_64) work machines. Target is the user's own work-issued laptop; the repo is meant to be pushed to a personal Git account (GitHub, GitLab, ...).

## Layout
- `install.sh` — entry point. Steps in order: `dirs, apt, repos, releases, links, dotfiles`. Flags: `--dry-run`, `--steps a,b`, `--only tool,tool`, `--profile a,b`.
- `setup.sh` — interactive first-time wizard (plain bash, no gum): picks profiles, can create a gitignored `profiles.local/NAME` (dirs + apt packages), picks/creates the SSH key, writes `local.env` (keeps unmanaged lines), then runs `install.sh`. `--config-only` skips the install. Keep it in sync when adding a new `local.env` setting.
- `lib.sh` — `install_release NAME VERSION TYPE SHA256 URL LINKS` (types: `tar.gz | gz | zip | raw | appimage`). Verifies the hash, fails hard on mismatch, installs to `$OPT_DIR/NAME-VERSION`, symlinks into `$BIN_DIR`. `OPT_DIR`/`BIN_DIR` env vars override `~/Opt` and `~/.local/bin` for testing.
- `manifest/tools.psv` — pipe-delimited release-binary manifest (one tool per row, pinned version + SHA-256). Base only: tools every machine gets.
- `apt-packages.txt` — base packages from Ubuntu's own repos.
- `profiles/NAME/` (committed, generic) and `profiles.local/NAME/` (gitignored) — role-specific layers: optional `apt-packages.txt`, `tools.psv`, `update-notes.psv`, `repos.txt` (vendor apt repo names), `dirs.txt`. Selected by `PROFILES` in `local.env` or `--profile`. See `profiles/README.md`. Put role-specific software in a profile, not the base.
- `lib.sh` also has `load_config`, `layer_files`, `manifest_files`, `vendor_repos`, `managed_apt_packages`; every script uses these so base + profile layers resolve the same way everywhere. Tool names must be unique across layers.
- `scripts/apt-repos.sh [vendor...]` — third-party apt repos (HashiCorp, Kubernetes) with key handling; vendor→package map is `manifest/vendor-repos.psv`. Which vendors a machine gets comes from profile `repos.txt`.
- `dotfiles/` — bashrc snippet (PATH, zoxide, keychain to persist the ssh-agent and load the keys named in `SSH_KEYS`, `local.env`); kickstart.nvim is cloned by the `dotfiles` step.
- `.claude/skills/add-software/SKILL.md` — procedure for adding new software (use `/add-software`).
- `.claude/skills/update-software/SKILL.md` — check everything for updates, warn about downsides, ask which to apply, apply (use `/update-software`).
- `scripts/check-updates.sh` — read-only TSV report of available updates (release manifest via GitHub latest release, apt via `apt list --upgradable`, next Kubernetes minor stream). Emits risk flags and joins `manifest/update-notes.psv` caveats.
- `scripts/update-release.sh NAME [--compute-hash] [--dry-run]` — bumps one manifest row (version + digest), installs, restores the manifest if the install fails.
- `scripts/apt-update.sh PKG...|--all` — sudo wrapper that only upgrades managed apt packages; run by the user in their own terminal.
- `manifest/update-notes.psv` (and profile `update-notes.psv`) — per-tool upgrade caveats shown by the update check. Add a row when you learn a downside, in the layer that owns the tool.

## Conventions
- Install layout: versioned directory under `~/Opt`, symlink into `~/.local/bin`. Upgrading = change the manifest row and rerun.
- Prefer Ubuntu apt when the package exists and is recent; otherwise official release binaries; vendor apt repos only for HashiCorp/Kubernetes (user's decision).
- Every download is verified against a pinned SHA-256. Use the digest GitHub publishes for the asset. If none exists, compute it locally, say so in a manifest comment, and tell the user.
- Scripts must be idempotent and rerunnable. Use `set -euo pipefail`. Never read from stdin inside the manifest loop (it uses fd 3).

## Security rules
- No credentials, tokens, internal URLs, hostnames, Vault addresses or company-specific values in the repo. Machine-specific values go in the gitignored `local.env` (`PROFILES`, `SSH_KEYS`, `K8S_MINOR`, `KICKSTART`, ...) or a gitignored `profiles.local/` profile. Don't hardcode key names, cluster versions or role-specific tools in base files.
- Key fingerprints in `apt-repos.sh` are pinned from the vendor's official page. If one mismatches, abort and re-verify against the vendor's site; never just update it to whatever was downloaded.
- Don't commit or push unless the user asks.

## Environment gotchas (learned the hard way)
- Claude Code's shell has no TTY: `sudo` cannot prompt. Give the user the exact sudo command (or a script to read first) to run in another terminal, then verify afterwards.
- The user's SSH key(s) for their Git host (GitHub, GitLab, ...; file names in `SSH_KEYS` in `local.env`, nothing is hardcoded) are passphrase-protected and unlocked by keychain in the user's own terminals. Claude Code's shell has no ssh-agent or TTY, so Claude can commit but cannot `git push`; the user pushes from their own terminal. Verify a push afterwards with `git ls-remote` over HTTPS on the repo's public URL (no auth needed if the repo is public). The repo never calls a Git host over SSH itself; downloads and the kickstart clone use HTTPS. `~/.ssh/config` is not managed (per-host `IdentityFile` routing is the user's job).
- Debian/Ubuntu rename some binaries: `bat`→`batcat`, `fd`→`fdfind`. The `links` step handles this.
- Ubuntu 26.04 has no `libfuse2`: AppImages are extracted (`--appimage-extract`), not mounted.
- `gh release download` demands auth even for public repos; use `curl` with the direct release URL.
- Ubuntu's apt `neovim` is too old for current kickstart; neovim comes from the release manifest.
- WSL puts Windows binaries on PATH (e.g. a Rancher Desktop `kubectl` under `/mnt/c`); check `command -v` resolves to the Linux one.
- Nerd Fonts must be installed on the Windows side; not automatable from WSL.

## Testing
Test release changes with `OPT_DIR=$TMP/Opt BIN_DIR=$TMP/bin ./install.sh --steps releases [--only name]` using a temp dir, plus `./install.sh --dry-run`. `apt`/`repos` steps need sudo; test them on a disposable WSL instance, not by guessing.

## Agent skills

### Issue tracker

GitHub Issues on `2ndshiftJim/ubuntu-setup` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
