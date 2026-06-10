#!/usr/bin/env bash
#
#  macOS Cleanup Tool — Installer
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/Dheph/mac-clean/main/install.sh | bash
#
#  Downloads the tool, installs it to ~/.local/bin, and runs the
#  setup for alias and optional scheduled cleanup.
#

set -e

REPO_URL="https://github.com/Dheph/mac-clean"
RAW_URL="https://raw.githubusercontent.com/Dheph/mac-clean/main"
INSTALL_DIR="${HOME}/.local/share/mac-clean"
BIN_DIR="${HOME}/.local/bin"

echo ""
echo "  ┌─────────────────────────────────────────────┐"
echo "  │         macOS Cleanup Tool Installer         │"
echo "  └─────────────────────────────────────────────┘"
echo ""

# ── Check curl ────────────────────────────────────────────────
if ! command -v curl >/dev/null 2>&1; then
    echo "  ✗ curl is required. Install it first."
    exit 1
fi

# ── Create directories ───────────────────────────────────────
mkdir -p "$INSTALL_DIR" "$BIN_DIR"
echo "  • Using: $INSTALL_DIR"
echo ""

# ── Download ──────────────────────────────────────────────────
echo "  Downloading..."

for file in mac-cleanup.sh start.sh README.md; do
    echo "    $file"
    curl -fsSL "$RAW_URL/$file" -o "$INSTALL_DIR/$file" 2>/dev/null || {
        echo "  ✗ Failed to download $file"
        exit 1
    }
done

chmod +x "$INSTALL_DIR/mac-cleanup.sh"
chmod +x "$INSTALL_DIR/start.sh"

# ── Symlink to PATH ───────────────────────────────────────────
SYMLINK_PATH="${BIN_DIR}/mac-clean"
ln -sf "$INSTALL_DIR/mac-cleanup.sh" "$SYMLINK_PATH"
echo "  • Installed: $SYMLINK_PATH"

# ── Ensure bin dir is in PATH ─────────────────────────────────
case ":$PATH:" in
    *:"$BIN_DIR":*) ;;
    *)
        echo ""
        echo "  ⚠  $BIN_DIR is not in your PATH."
        echo "     Adding to shell config..."
        echo ""
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$HOME/.zshrc" 2>/dev/null || true
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$HOME/.bashrc" 2>/dev/null || true
        echo "  ✓ Added to PATH (for future terminals)."
        echo ""
        echo "  To use it now: export PATH=\"\$HOME/.local/bin:\$PATH\""
        ;;
esac

echo ""
echo "  ✓ Download complete!"
echo ""

# ── Run local setup ──────────────────────────────────────────
cd "$INSTALL_DIR"
bash start.sh

echo ""
echo "  ─────────────────────────────────────────────────"
echo "  To use 'mac-clean' in this terminal right now:"
echo ""
echo "    source ${HOME}/.zshrc"
echo ""
echo "  (New terminals will have it automatically.)"
echo "  ─────────────────────────────────────────────────"
echo ""
