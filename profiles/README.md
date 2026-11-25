# Profiles

A profile layers extra things on the base install for a machine with a specific purpose.
Select them in `local.env` (`PROFILES="k8s,dev"`) or per run (`./install.sh --profile k8s`).
The scripts in `scripts/` read `local.env` too, so update checks cover exactly what the
machine uses.

Profiles live in `profiles/NAME/` (committed; keep them generic) or `profiles.local/NAME/`
(gitignored; for anything you would not push). Every file is optional:

| File | Format | Layered onto |
|---|---|---|
| `apt-packages.txt` | one package per line | `apt-packages.txt` |
| `tools.psv` | release-binary rows | `manifest/tools.psv` (names must be unique across layers) |
| `update-notes.psv` | `name\|caveat` | `manifest/update-notes.psv` |
| `repos.txt` | vendor apt repo names (`hashicorp`, `kubernetes`) | none (base has no vendor repos) |
| `dirs.txt` | directories under `$HOME` | `Opt` and `Shared_repos` |

Included: `k8s` (HashiCorp + Kubernetes repos, nerdctl, talosctl) and `dev` (Go, glab).
Company- or employee-specific layouts (for example a `work` profile whose `dirs.txt` lists
your `Tools/` subdirectories) belong in a gitignored `profiles.local/NAME/`.
