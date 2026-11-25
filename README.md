# machine-setup

Rerunnable setup for Ubuntu / WSL2-Ubuntu (x86_64).

```
git clone <this repo> ~/Shared_repos/machine-setup && cd ~/Shared_repos/machine-setup
./setup.sh                          # guided first-time setup: profiles, SSH key, local.env, then install
```

Or by hand:
```
cp local.env.example local.env      # machine-specific values: PROFILES, SSH_KEYS, ... (gitignored)
./install.sh --dry-run              # preview
./install.sh
```

`setup.sh` is a plain-bash wizard (`--config-only` writes `local.env` and any new `profiles.local/` profile without installing). Rerunning it offers your current answers as defaults and keeps unrelated `local.env` lines.

| Step | What it does |
|---|---|
| `dirs` | creates `~/Opt` and `~/Shared_repos`, plus any `dirs.txt` from profiles |
| `apt` | installs `apt-packages.txt` plus profile lists (needs sudo) |
| `repos` | adds the vendor apt repos (HashiCorp, Kubernetes) that profiles request; skipped if none |
| `releases` | downloads GitHub release binaries in `manifest/tools.psv` and profile `tools.psv` files into `~/Opt/<name>-<version>`, verifies SHA-256, symlinks into `~/.local/bin` |
| `links` | `bat` -> `batcat`, `fd` -> `fdfind` |
| `dotfiles` | clones kickstart.nvim to `~/.config/nvim` (if absent), adds a bashrc snippet (PATH, zoxide, keychain loads the keys named in `SSH_KEYS`) |

Options: `--steps dirs,releases`, `--only resvg,yazi`, `--profile k8s,dev`, `--dry-run`.
`OPT_DIR` and `BIN_DIR` env vars override install locations (useful for testing).

## Per-machine setup
The base install is what every machine gets. Anything role-specific lives in a **profile** (`profiles/NAME/`, or gitignored `profiles.local/NAME/` for things you would not push); see `profiles/README.md`. Pick them per machine with `PROFILES="k8s,dev"` in `local.env` (or `--profile`). Other per-machine values in `local.env`: `SSH_KEYS` (key files keychain loads), `K8S_MINOR`, `KICKSTART=0`. The update scripts read `local.env` too, so they only check what that machine actually uses.

## Updating
```
scripts/check-updates.sh                 # what has a newer version (read-only, no sudo)
scripts/update-release.sh NAME           # bump one release binary: manifest row + install, rolls back on failure
bash scripts/apt-update.sh --all         # upgrade managed apt packages (sudo; or list package names)
```
In Claude Code, `/update-software` runs the check, warns about downsides (major bumps, very new releases, per-tool caveats in `manifest/update-notes.psv`), asks which updates to apply, and applies them.
Manual route: edit the row in `manifest/tools.psv` or the profile `tools.psv` that holds it (version, and the new SHA-256 from the release's published digest), rerun `./install.sh --steps releases`.

## Not covered (manual)
- A Nerd Font on the Windows side, selected in the terminal profile.
- Creating an SSH key (e.g. `ssh-keygen -t ed25519 -a 100 -f ~/.ssh/<name>`, with a passphrase), adding the public key to your Git host (GitHub, GitLab, ...), and listing `<name>` in `SSH_KEYS` in `local.env`. `setup.sh` can do the first and last parts for you (it prompts for the key name); adding the key to the host is manual. Key creation needs a real terminal for the passphrase prompt.
- Per-host key routing in `~/.ssh/config`. keychain only loads the keys in `SSH_KEYS` into the agent; if you use different keys for different hosts, add a `Host` block with `IdentityFile` and `IdentitiesOnly yes` per host so servers are not offered every loaded key.
- `gh auth login`, `vault login`, and any credentials.
- A container runtime for `nerdctl` (`k8s` profile): containerd, rootless setup.

## Security notes
- Every download is checked against a pinned SHA-256 and fails hard on mismatch.
- Only pin hashes you verified; the tree-sitter row is a locally computed hash (no published digest).
- Keep internal URLs, tokens and company-specific values out of this repo; use `local.env`.
