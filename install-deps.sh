#!/usr/bin/env bash
# Installs everything arete_cipher_cli needs on an Arch Linux (WSL or bare
# metal) machine, except the release tarball itself and `gh auth login`
# (both need a human). Safe to re-run.
#
# Installs:
#   - erlang-nox, github-cli, duckdb, git, age (official pacman packages)
#   - mise (https://mise.jdx.dev/), for the env/secrets workflow documented
#     in this repo's README - via pacman if available, else the upstream
#     installer script
#
# Usage:
#   ./install-deps.sh
set -euo pipefail

fail() {
  echo "install-deps.sh: $*" >&2
  exit 1
}

command -v pacman >/dev/null 2>&1 \
  || fail "pacman not found - this script targets Arch Linux (including Arch WSL)"

echo "==> Installing erlang-nox, github-cli, duckdb, git, age via pacman"
sudo pacman -S --needed --noconfirm erlang-nox github-cli duckdb git age

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

==> Dependencies installed. Two things still need a human:

1. Authenticate gh (any account that can read the repos you'll extract):
     gh auth login

2. Activate mise in your shell, if you haven't already. Add one of these
   to your shell rc and open a new shell:
     eval "$(mise activate bash)"   # ~/.bashrc
     eval "$(mise activate zsh)"    # ~/.zshrc

See this repo's README for installing the arete_cipher_cli release itself
and for setting up mise.toml with the Azure DevOps identity and an
age-encrypted ADO_PAT.
EOF
