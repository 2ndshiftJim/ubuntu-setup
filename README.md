# machine-setup

Rerunnable setup for Ubuntu / WSL2-Ubuntu (x86_64).

```
git clone <this repo> ~/Shared_repos/machine-setup && cd ~/Shared_repos/machine-setup
cp local.env.example local.env      # optional, machine-specific values (gitignored)
./install.sh --dry-run              # preview
./install.sh
```

| Step | What it does |
|---|---|
| `dirs` | creates the `~/Opt`, `~/Tools`, `~/Apps`, ... layout |
| `apt` | installs `apt-packages.txt` (needs sudo) |
| `repos` | adds HashiCorp + Kubernetes apt repos; installs terraform, vault, kubectl |
| `releases` | downloads GitHub release binaries in `manifest/tools.psv` into `~/Opt/<name>-<version>`, verifies SHA-256, symlinks into `~/.local/bin` |
| `links` | `bat` -> `batcat`, `fd` -> `fdfind` |
| `dotfiles` | clones kickstart.nvim to `~/.config/nvim` (if absent), adds a bashrc snippet |

Options: `--steps dirs,releases`, `--only resvg,yazi`, `--dry-run`.
`OPT_DIR` and `BIN_DIR` env vars override install locations (useful for testing).

## Upgrading a tool
Edit its row in `manifest/tools.psv` (version, and the new SHA-256 from the release's published digest), rerun `./install.sh --steps releases`.

## Not covered (manual)
- A Nerd Font on the Windows side, selected in the terminal profile.
- `gh auth login`, `vault login`, and any credentials.
- A container runtime for `nerdctl` (containerd, rootless setup).

## Security notes
- Every download is checked against a pinned SHA-256 and fails hard on mismatch.
- Only pin hashes you verified; the tree-sitter row is a locally computed hash (no published digest).
- Keep internal URLs, tokens and company-specific values out of this repo; use `local.env`.
