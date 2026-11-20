#!/usr/bin/env bash
# Installs everything arete_cipher_cli needs on an Arch Linux (WSL or bare
# metal) machine, except the release tarball itself and `gh auth login`
# (both need a human). Safe to re-run.
#
# Installs:
#   - Erlang/OTP as the split packages the bundle needs, plus github-cli, git,
#     age and postgresql (official pacman packages)
#   - duckdb, pinned to an exact version from the Arch Linux Archive,
#     because arete_cipher_cli accepts one DuckDB line and refuses others
#   - mise (https://mise.jdx.dev/), for the env/secrets workflow documented
#     in this repo's README - via pacman if available, else the upstream
#     installer script
#
# Usage:
#   ./install-deps.sh
#   DUCKDB_FREEZE=no ./install-deps.sh   # pin the version, leave pacman.conf alone
set -euo pipefail

# The DuckDB arete_cipher_cli is verified against. Moving the pin means
# editing these lines, after running the tool's suite against the new version:
# see ADR-0014 in the main repository. The pkgrel is part of the Arch
# Archive's filename, so both numbers are needed to build the URL.
DUCKDB_PIN="${DUCKDB_PIN:-1.5.6}"
DUCKDB_PKGREL="${DUCKDB_PKGREL:-1}"
DUCKDB_FREEZE="${DUCKDB_FREEZE:-yes}"

fail() {
  echo "install-deps.sh: $*" >&2
  exit 1
}

command -v pacman >/dev/null 2>&1 \
  || fail "pacman not found - this script targets Arch Linux (including Arch WSL)"

# Erlang is named as the split packages the bundle uses. Arch no longer has
# erlang-nox: on 2026-11-20 `pacman -S erlang-nox` answered "target not
# found", and the erlang meta-package would also pull in erlang-wx and its GUI
# libraries. These are the OTP applications the CLI (inets, ssl) and the page
# (asn1, compiler, crypto, mnesia, public_key, runtime_tools, sasl, ssl) name,
# read from their .app and .rel files. postgresql is for the serving page.
ERLANG_PKGS="erlang-core erlang-asn1 erlang-public_key erlang-ssl erlang-inets erlang-mnesia erlang-runtime_tools erlang-sasl"

echo "==> Installing Erlang/OTP, github-cli, git, age, postgresql via pacman"
# shellcheck disable=SC2086
sudo pacman -S --needed --noconfirm $ERLANG_PKGS github-cli git age postgresql

# DuckDB is pinned rather than installed with `pacman -S`, which would take
# whatever `extra` currently holds. arete_cipher_cli accepts the 1.5 line and
# refuses anything else by name before writing a report, so a routine
# `pacman -Syu` that moves duckdb to 2.0 stops the tool working. As of
# 2026-11-19 `extra` has 1.5.6 and `extra-testing` already has 2.0.0, so this
# is a dated problem and not a hypothetical one.
#
# Re-running this script re-pins, so it also repairs a machine that has
# already drifted past the supported line.
duckdb_minor() {
  command -v duckdb >/dev/null 2>&1 || return 1
  duckdb --version 2>/dev/null \
    | sed -n 's/^v\{0,1\}\([0-9]\{1,\}\.[0-9]\{1,\}\).*/\1/p'
}

want_minor="${DUCKDB_PIN%.*}"
have_minor="$(duckdb_minor || true)"

if [ "$have_minor" = "$want_minor" ]; then
  echo "==> duckdb $(duckdb --version) is in the supported $want_minor line"
else
  if [ -n "$have_minor" ]; then
    echo "==> duckdb $have_minor is outside the supported $want_minor line; re-pinning"
  else
    echo "==> Installing duckdb $DUCKDB_PIN (pinned)"
  fi
  pkg="duckdb-$DUCKDB_PIN-$DUCKDB_PKGREL-x86_64.pkg.tar.zst"
  sudo pacman -U --noconfirm \
    "https://archive.archlinux.org/packages/d/duckdb/$pkg" \
    || fail "could not install $pkg from the Arch Archive.
    Check which versions exist: https://archive.archlinux.org/packages/d/duckdb/
    If this one has been dropped, move the pin at the top of this script -
    but run arete_cipher_cli's test suite against the new version first."
fi

# A pin a system upgrade can undo is not a pin. IgnorePkg is what stops
# `pacman -Syu` moving it, so it is added once, marked so it can be found,
# and skipped entirely with DUCKDB_FREEZE=no.
if [ "$DUCKDB_FREEZE" = yes ]; then
  # Matched on a whole word, so an unrelated `IgnorePkg = duckdb-extras`
  # does not read as duckdb already being held back. Both forms were tried
  # against realistic lines; the looser one gave a false positive there and
  # on `myduckdb`, which would have skipped the freeze silently.
  ignore_re='^[[:space:]]*IgnorePkg[[:space:]]*=([[:space:]]*|.*[[:space:]])duckdb([[:space:]]|$)'
  if grep -qE "$ignore_re" /etc/pacman.conf; then
    echo "==> pacman.conf already holds duckdb back from upgrades"
  else
    echo "==> Holding duckdb back from pacman upgrades (IgnorePkg in /etc/pacman.conf)"
    printf '\n# arete_cipher_cli: pinned DuckDB line. Remove this to let pacman\n# upgrade duckdb again - and expect the tool to refuse the new version\n# until its own pin moves to match.\nIgnorePkg = duckdb\n' \
      | sudo tee -a /etc/pacman.conf >/dev/null
  fi
else
  echo "==> DUCKDB_FREEZE=no: not touching pacman.conf."
  echo "    A later 'pacman -Syu' may move duckdb off the supported line."
fi

# Prove the engine will satisfy the tool rather than trusting the version
# number. The second check is the one a version cannot answer: every figure
# placed on a contributor's clock needs DuckDB's timezone database, which on
# some builds is a separate extension loaded on demand, and arete_cipher_cli
# refuses a run that cannot resolve a named zone.
echo "==> Verifying the engine"
echo "    version:   $(duckdb --version)"
if duckdb -c "SELECT now() AT TIME ZONE 'America/Chicago'" >/dev/null 2>&1; then
  echo "    timezones: a named zone resolves"
else
  {
    echo "    timezones: FAILED - this duckdb cannot resolve a named zone."
    echo "               arete_cipher_cli will refuse to report on it. Try:"
    echo "                 duckdb -c 'FORCE INSTALL icu'"
    echo "               then run this script again."
  } >&2
  fail "duckdb cannot resolve a named timezone"
fi

if command -v mise >/dev/null 2>&1; then
  echo "==> mise already installed ($(mise --version))"
elif sudo pacman -S --needed --noconfirm mise 2>/dev/null; then
  echo "==> Installed mise via pacman"
else
  echo "==> mise is not packaged here; installing via the upstream script"
  curl -fsSL https://mise.run | sh
  echo "    Installed to ~/.local/bin - make sure that's on PATH."
fi

cat <<'EOF'

==> Dependencies installed. Two things still need a human, and a third if
    you will run the serving page:

1. Authenticate gh (any account that can read the repos you'll extract):
     gh auth login

2. Activate mise in your shell, if you haven't already. Add one of these
   to your shell rc and open a new shell:
     eval "$(mise activate bash)"   # ~/.bashrc
     eval "$(mise activate zsh)"    # ~/.zshrc

3. For the serving page only: initialise and start PostgreSQL, and create
   the role and database it uses. See "Running the page" in this repo's
   README.

See this repo's README for installing the arete_cipher_cli release itself
and for setting up mise.toml with the Azure DevOps identity and an
age-encrypted ADO_PAT.

Note on DuckDB: it is pinned to an exact version and held back from
`pacman -Syu` via IgnorePkg in /etc/pacman.conf. arete_cipher_cli accepts
one DuckDB line and refuses any other by name, so an unpinned upgrade
stops it working. Re-run this script to re-pin a machine that drifted.
EOF
