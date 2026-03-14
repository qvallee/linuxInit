#!/usr/bin/env bash
set -euo pipefail

if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  SUDO=""
fi

if command -v apt-get >/dev/null 2>&1; then
  $SUDO apt-get update
  $SUDO apt-get install -y build-essential curl
elif command -v dnf >/dev/null 2>&1; then
  $SUDO dnf install -y gcc gcc-c++ make curl
elif command -v yum >/dev/null 2>&1; then
  $SUDO yum install -y gcc gcc-c++ make curl
else
  echo "No supported package manager found"
  exit 1
fi

curl https://sh.rustup.rs -sSf | sh -s -- -y

source "$HOME/.cargo/env"

"$HOME/.cargo/bin/rustup" default stable

if ! grep -q 'source "$HOME/.cargo/env"' "$HOME/.bash_profile" 2>/dev/null; then
  echo 'source "$HOME/.cargo/env"' >> "$HOME/.bash_profile"
fi

rustc --version
cargo --version

echo "Rust install finished."
