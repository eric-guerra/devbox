#!/usr/bin/env bash
# Installs devbox into ~/.local/share/devbox and links the CLI into ~/.local/bin.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${DEVBOX_INSTALL_DIR:-$HOME/.local/share/devbox}"
BIN="${DEVBOX_BIN_DIR:-$HOME/.local/bin}"

mkdir -p "$DEST" "$BIN"
cp -R "$SRC/bin" "$SRC/lib" "$SRC/templates" "$DEST/"
chmod +x "$DEST/bin/devbox"
ln -sf "$DEST/bin/devbox" "$BIN/devbox"
echo "installed devbox to $BIN/devbox"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "add $BIN to your PATH" ;; esac
