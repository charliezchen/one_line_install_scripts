#!/usr/bin/env sh
set -eu

# Minimal-impact installer for OpenAI Codex CLI on Linux
# Installs to: ~/.local/bin/codex
# Requires: curl or wget, tar
# Supports: x86_64, aarch64/arm64

INSTALL_DIR="${HOME}/.local/bin"
TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT INT TERM

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)
    asset="codex-x86_64-unknown-linux-musl.tar.gz"
    bin_in_tar="codex-x86_64-unknown-linux-musl"
    ;;
  aarch64|arm64)
    asset="codex-aarch64-unknown-linux-musl.tar.gz"
    bin_in_tar="codex-aarch64-unknown-linux-musl"
    ;;
  *)
    echo "Unsupported architecture: $arch" >&2
    exit 1
    ;;
esac

url="https://github.com/openai/codex/releases/latest/download/${asset}"

mkdir -p "$INSTALL_DIR"

archive="$TMPDIR/$asset"

if command -v curl >/dev/null 2>&1; then
  curl -fL "$url" -o "$archive"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$archive" "$url"
else
  echo "Need curl or wget to download Codex." >&2
  exit 1
fi

tar -xzf "$archive" -C "$TMPDIR"

install -m 0755 "$TMPDIR/$bin_in_tar" "$INSTALL_DIR/codex"

cat <<EOF
Installed: $INSTALL_DIR/codex

Run it with:
  $INSTALL_DIR/codex

If "~/.local/bin" is already on your PATH, you can just run:
  codex
EOF
