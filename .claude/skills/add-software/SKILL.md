---
name: add-software
description: Add new software to this machine-setup repo and install it on the current machine. Use when the user wants to install a tool; classifies the install origin (apt, official release binary, vendor apt repo, npm, pip/pipx, cargo, go install, other), puts it in the correct file, or works with the user to design a new section for an origin type the repo does not handle yet.
---

# add-software

Goal: every tool installed on this machine is also recorded in this repo so the next machine gets it. Read `CLAUDE.md` first for conventions and gotchas.

Input: the software name and, if given, a URL. If the user gave neither an origin nor a URL, find the project's official install docs (WebFetch/WebSearch) and use those, not third-party blog posts.

## 1. Classify the install origin

Check in this order and tell the user which you chose and why:

1. **Ubuntu apt** — `apt-cache policy <pkg>` shows a Candidate. Prefer this if the version is reasonably current (and for tools needing system integration or security updates). Beware renamed binaries (`batcat`, `fdfind`).
2. **Vendor apt repo** — the vendor documents an apt repository (HashiCorp, Kubernetes style). Only if the user wants it; it adds a third-party source on a work machine, so flag that.
3. **Official release binary** — GitHub/vendor release asset for `linux x86_64`. Prefer `musl`/static builds if glibc-compat is unclear. Check `ldd --version` if using gnu builds.
4. **Language package managers** — npm, pip/pipx, cargo, `go install`, etc.
5. **Other** — installer scripts (`curl | sh`), AppImage, snap, source build. Prefer a pinned, verifiable alternative; do not pipe remote scripts into a shell. If a script is the only option, download it, read it with the user, then run it.

Never invent an origin: confirm the package/asset exists before editing files.

## 1b. Base or profile?

Decide where the software belongs. **Base** (`apt-packages.txt`, `manifest/tools.psv`) is for tools every machine should get. Anything tied to a role or purpose (cloud/k8s, a language toolchain, a short-lived machine's job) goes in a **profile**: `profiles/NAME/` if it is generic enough to push, `profiles.local/NAME/` (gitignored) if not. Use the same file names inside the profile (`apt-packages.txt`, `tools.psv`, `update-notes.psv`, `repos.txt`). Ask the user if unsure, and create the profile (and mention adding it to `PROFILES` in `local.env`) if it does not exist yet. Where this skill below says `apt-packages.txt` or `manifest/tools.psv`, use the chosen layer's file. Test profile changes with `./install.sh --dry-run --profile NAME`.

## 2. Handle known origins

### apt (Ubuntu repos)
- Append the package to the chosen layer's `apt-packages.txt` under a fitting comment group.
- Install requires sudo, which this shell can't prompt for. Give the user: `sudo apt install -y <pkg>` to run in another terminal. Then verify with `dpkg -l <pkg>` and `command -v <binary>`; run `<binary> --version`.

### Vendor apt repo
- Extend `scripts/apt-repos.sh` following the existing pattern: fetch the key over HTTPS, **pin the fingerprint from the vendor's official page** (WebFetch it; confirm the current key, check for rotations), abort on mismatch, write a `signed-by` source file. Add the vendor to `manifest/vendor-repos.psv` (`vendor|packages`), add an `add_<vendor>` function plus a `case` arm in `scripts/apt-repos.sh`, and list the vendor in the owning profile's `repos.txt`.
- Show the user the script diff before they run it with sudo.

### Official release binary
1. Find the latest release and the right asset: `curl -s https://api.github.com/repos/OWNER/REPO/releases/latest` and parse with `python3 -I` (the `digest` field is the SHA-256). Pick `x86_64`/`amd64` Linux assets.
2. Download into a fresh directory (not the repo), and compute `sha256sum`. Compare to the published digest, or a vendor `SHA256SUMS` file. If nothing is published, say so explicitly and ask the user whether to pin a locally computed hash.
3. Inspect the archive (`tar -tzf`, `unzip -l`) to learn the binary's path. Choose a `type`: `tar.gz | gz | zip | raw | appimage`.
4. Add a row to the chosen layer's `tools.psv` (`manifest/tools.psv` for base): `name|version|type|sha256|url with {version}|path-in-dir:linkname[,more]`.
5. Test, never against the real install first: `OPT_DIR=$TMP/Opt BIN_DIR=$TMP/bin ./install.sh --steps releases --only <name>` (temp dir from the scratchpad), run the binary's version command. Then run for real: `./install.sh --steps releases --only <name>`.
6. Note caveats (e.g. needs a daemon, config, or auth the user must do manually).

## 3. Unhandled origin (npm, pip, cargo, go, ...)

Do **not** improvise a one-off install and walk away. Work with the user to add a section:

1. Tell the user this origin isn't handled yet and propose a design. Ask (AskUserQuestion) about the decisions that are theirs, e.g.:
   - Tooling: npm global vs per-prefix; `pipx` vs `pip --user`/venv; `cargo install --locked`; `go install pkg@version`.
   - Prerequisites the repo doesn't install yet (node via apt? NodeSource? mise?). Remember `npm` on this WSL may resolve to the Windows one under `/mnt/c`; require a Linux install.
   - Version pinning policy (exact versions, lockfile) and install prefix (keep user-level, under `~/.local` or `~/Opt`; no `sudo npm -g`/`sudo pip`).
2. Recommended shape, mirroring the existing pattern:
   - A manifest file, e.g. `manifest/npm-packages.txt` (`name@exact-version` per line), `pipx-packages.txt`, `cargo-crates.txt`, `go-tools.txt`.
   - A `step_<origin>` function in `install.sh`, registered in the step list, `--steps` docs, and the `for s in ...` loop; idempotent (skip if already at the pinned version) and honoring `DRY_RUN`.
   - Helper logic in `lib.sh` if it is reusable.
   - Prerequisite install added to `apt-packages.txt` or the manifest.
3. Show the user the plan and the diff, implement after agreement, test with `--dry-run` and in a temp prefix.
4. Install the requested software through the new step; verify with its version command.

## 4. Always, before finishing

- Update `README.md` (step table / "Not covered") and `CLAUDE.md` (layout / conventions / gotchas) if you added a file, step, or learned a new gotcha.
- Run `bash -n` on changed scripts and `./install.sh --dry-run`.
- Security check on what you added: no credentials, tokens, or internal URLs; hashes/fingerprints came from official sources; HTTPS only.
- Summarize: origin chosen, files changed, version installed, how it was verified, anything unverified or left for the user (sudo commands, auth, fonts).
- Do not commit or push unless the user asks.
