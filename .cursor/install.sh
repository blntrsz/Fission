#!/usr/bin/env bash
# Idempotent Cloud Agent bootstrap for the Fission repository on Linux.
#
# The Desktop and Mobile apps require Xcode and only build on macOS. On Linux we
# provision the toolchain needed for the parts that are portable: the FissionCore
# Swift package (built/tested with the swift.org toolchain + GRDB), SwiftLint, and
# the flue TypeScript agent project.
set -euo pipefail

SWIFT_VERSION="6.1.2"

echo "==> Installing system packages for the Swift toolchain and GRDB (SQLite)"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
  binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
  libncurses-dev libncurses6 libpython3-dev libsqlite3-0 libsqlite3-dev \
  libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata unzip zlib1g-dev

echo "==> Ensuring mise is installed"
if ! command -v mise >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/mise" ]; then
  curl -fsSL https://mise.run | sh
fi
export PATH="$HOME/.local/bin:$PATH"

echo "==> Installing repo-pinned tools (swiftlint, watchexec) from mise.toml"
mise install

echo "==> Installing Swift ${SWIFT_VERSION} (not pinned in mise.toml; macOS uses Xcode's swift)"
mise use -g "swift@${SWIFT_VERSION}"
mise reshim

echo "==> Making mise-managed tools available in non-interactive shells"
SHIM_LINE='export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"'
for profile in "$HOME/.bashrc" "$HOME/.profile"; do
  touch "$profile"
  grep -qF "$HOME/.local/share/mise/shims" "$profile" || printf '\n%s\n' "$SHIM_LINE" >> "$profile"
done

echo "==> Resolving FissionCore Swift package dependencies"
mise exec -- swift package --package-path Packages/Core resolve

echo "==> Installing flue (TypeScript) dependencies"
if [ -d flue ]; then
  ( cd flue && npm install )
fi

echo "==> Bootstrap complete"
mise exec -- swift --version
