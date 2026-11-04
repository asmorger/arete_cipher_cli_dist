# arete_cipher_cli_dist

Distribution channel for [`arete_cipher_cli`](https://github.com/asmorger/arete_cipher_cli):
compiled, source-free release bundles (BEAM bytecode plus the `priv/` SQL and
chart runtime). The consuming machine never needs the source repository, a
Gleam toolchain, or any credential that can reach source.

## Installing (Arch Linux, including Arch WSL)

### 1. Dependencies

```sh
curl -fsSL https://raw.githubusercontent.com/asmorger/arete_cipher_cli_dist/main/install-deps.sh | bash
```

or clone this repo and run [`install-deps.sh`](./install-deps.sh) directly.
It installs `erlang-nox`, `github-cli`, `duckdb`, `git`, and `age` via
`pacman`, plus [`mise`](https://mise.jdx.dev/) (via `pacman` if packaged,
otherwise the upstream installer). It's safe to re-run.

Two things still need a human after it runs:

```sh
gh auth login   # any account that can read the repos you'll extract

# add to ~/.bashrc or ~/.zshrc, then open a new shell:
eval "$(mise activate bash)"   # or: mise activate zsh
```

### 2. The release

```sh
VERSION=v0.5.0   # see https://github.com/asmorger/arete_cipher_cli_dist/releases
gh release download "$VERSION" --repo asmorger/arete_cipher_cli_dist --pattern 'arete-cipher-cli-*'
sha256sum -c "arete-cipher-cli-$VERSION-erlang.tar.gz.sha256"

mkdir -p ~/.local/opt/arete-cipher-cli
tar -xzf "arete-cipher-cli-$VERSION-erlang.tar.gz" -C ~/.local/opt/arete-cipher-cli
```

Each release's notes state the Erlang/OTP major it was built with; the
machine's OTP must be that major or newer.

Run everything through the bundle's entrypoint, from any working directory —
snapshots (`data/`) and reports (`reports/`) land relative to where you run
(or your `--out`/`--reports-dir` flags), never inside the install directory:

```sh
alias arete='"$HOME"/.local/opt/arete-cipher-cli/entrypoint.sh run'

arete gh [owner/repo]
arete git <clone-path>
arete ado [owner/repo] [--org <url>] [--project <name>]
arete sync [--repo <owner/repo>]
arete report [owner/repo]
```

`[owner/repo]` is optional on `gh`, `ado`, and `report`: run from inside the
clone and it's derived from the working directory's `origin` remote. For
interactive DuckDB sessions, the views file ships inside the bundle at
`~/.local/opt/arete-cipher-cli/arete_cipher_cli/priv/sql/views.sql`.

### 3. Configuring `mise.toml` for unattended `sync`

`sync` runs gh, git, and ado extractions for the working directory's
repository in one stateless invocation (see the main repo's README for the
full contract). The author's layout is a `mise`-managed worktree per
repository: a project-level `mise.toml` carries the Azure DevOps identity as
plain env and the `ADO_PAT` credential as an age-encrypted secret, so
nothing sensitive sits in a shell profile or crontab.

**One-time setup, per machine:**

```sh
mkdir -p ~/.config/age
age-keygen -o ~/.config/age/key.txt
# Note the "Public key: age1..." line it prints - you'll need it below.
# If you lose it, recover it anytime with:
age-keygen -y ~/.config/age/key.txt
```

**Per worktree, once:**

```sh
cd ~/code/octo-hello   # the worktree to extract

mkdir -p secrets
# Paste the PAT at the prompt (no echo); replace age1... with your public key.
age -r age1... -o secrets/ado_pat.age
```

Create `mise.toml` at the worktree root:

```toml
[env]
ADO_ORG_URL = "https://dev.azure.com/acme"
ADO_PROJECT = "Web"
ADO_PAT = "{{ exec(command='age --decrypt -i ~/.config/age/key.txt secrets/ado_pat.age') }}"
```

`mise` won't evaluate a config it hasn't been told to trust:

```sh
mise trust
```

Verify the identity resolves before trusting it to cron:

```sh
mise exec -- env | grep ^ADO_
```

**Cron-ready invocation** — run from the worktree so both identity (via
mise's env) and the repository (via origin-remote derivation) are picked up
with no arguments at all:

```sh
# crontab, or a mise task
*/30 * * * * cd ~/code/octo-hello && mise exec -- arete sync
```

A stale or rejected `ADO_PAT` still lets the gh and git datasets refresh —
`sync` attempts every configured extraction independently and reports each
one's outcome; see the main repo's README for the full semantics.

If you keep several repositories this way, repeat step 3 per worktree; the
age keypair in `~/.config/age/key.txt` is shared across all of them.

## Notes

- `gh` needs whatever account can read the repositories you extract; the
  release download itself works with any authenticated account (this
  distribution repo is public).
- See the [source repository](https://github.com/asmorger/arete_cipher_cli)
  for the tool's full documentation: extraction windows, snapshot layout,
  analysis views, application segmentation, and report generation.
