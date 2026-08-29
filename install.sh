#!/usr/bin/env bash
set -e

# Dynamically resolve paths for universal compatibility across any machine/user
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
EXTENSIONS_DIR="$XDG_DATA_HOME/gnome-shell/extensions"
UUID="forcequit@schirelli.github.io"
TARGET_DIR="$EXTENSIONS_DIR/$UUID"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== ForceQuit Extension Installer ==="
echo "Installing extension for user: ${USER:-$(whoami)}"
echo "Target path: $TARGET_DIR"

# Ensure target directory exists
mkdir -p "$TARGET_DIR"

# Compile schemas
if [ -d "$SCRIPT_DIR/schemas" ]; then
    glib-compile-schemas "$SCRIPT_DIR/schemas"
fi

# Copy extension files
cp -f "$SCRIPT_DIR/metadata.json" "$TARGET_DIR/"
cp -f "$SCRIPT_DIR/extension.js" "$TARGET_DIR/"
[ -f "$SCRIPT_DIR/prefs.js" ] && cp -f "$SCRIPT_DIR/prefs.js" "$TARGET_DIR/"
[ -f "$SCRIPT_DIR/stylesheet.css" ] && cp -f "$SCRIPT_DIR/stylesheet.css" "$TARGET_DIR/"
[ -f "$SCRIPT_DIR/icon.png" ] && cp -f "$SCRIPT_DIR/icon.png" "$TARGET_DIR/"
[ -f "$SCRIPT_DIR/icon.svg" ] && cp -f "$SCRIPT_DIR/icon.svg" "$TARGET_DIR/"
if [ -d "$SCRIPT_DIR/icons" ]; then
    cp -r "$SCRIPT_DIR/icons" "$TARGET_DIR/"
fi
if [ -d "$SCRIPT_DIR/schemas" ]; then
    cp -r "$SCRIPT_DIR/schemas" "$TARGET_DIR/"
fi

echo "Files successfully installed to $TARGET_DIR."

# Try enabling via gnome-extensions CLI
if command -v gnome-extensions >/dev/null 2>&1; then
    echo "Enabling extension ($UUID)..."
    gnome-extensions enable "$UUID" 2>/dev/null || true
fi

echo ""
echo "IMPORTANT: Why does GNOME Shell require a reload for new extensions?"
echo "GNOME Shell scans extension directories at startup. Once loaded, you need to reload GNOME Shell for it to discover newly added extension folders:"
echo ""
echo "  - On Wayland: Log out and log back in (or restart your session)."
echo "  - On X11: Press Alt+F2, type 'r', and press Enter."
echo ""
echo "After reloading, 'forcequit@schirelli.github.io' will appear in 'gnome-extensions list'!"
