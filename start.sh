#!/usr/bin/env bash

# ══════════════════════════════════════════════════════════════
#  macOS Cleanup Tool — Installer
#  Detects your shell and adds the `mac-clean` alias
# ══════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/mac-cleanup.sh"

ALIAS_LINE="alias mac-clean='\"$CLEANUP_SCRIPT\"'"

detect_shell_config() {
    local shell_name
    shell_name=$(basename "$SHELL" 2>/dev/null || echo "unknown")

    case "$shell_name" in
        zsh)
            echo "$HOME/.zshrc"
            ;;
        bash)
            if [ -f "$HOME/.bash_profile" ]; then
                echo "$HOME/.bash_profile"
            elif [ -f "$HOME/.bashrc" ]; then
                echo "$HOME/.bashrc"
            else
                echo "$HOME/.bash_profile"
            fi
            ;;
        fish)
            echo "$HOME/.config/fish/config.fish"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

config_path=$(detect_shell_config)
shell_name=$(basename "$SHELL" 2>/dev/null || echo "unknown")

echo ""
echo "  macOS Cleanup Tool — Installer"
echo "  ─────────────────────────────"
echo ""
echo "  Detected shell: $shell_name"

if [ "$config_path" = "unknown" ]; then
    echo "  Unsupported shell: $shell_name"
    echo "  Add the following alias manually to your shell config:"
    echo ""
    echo "    $ALIAS_LINE"
    echo ""
    exit 1
fi

echo "  Config file:   $config_path"

if [ ! -f "$config_path" ]; then
    echo "  Creating $config_path..."
    touch "$config_path"
fi

if grep -q "alias mac-clean=" "$config_path" 2>/dev/null; then
    echo ""
    echo "  Alias 'mac-clean' already exists in $config_path"
    echo "  Skipping."
else
    echo ""
    echo "  Adding alias to $config_path..."
    echo "" >> "$config_path"
    echo "# macOS Cleanup Tool" >> "$config_path"
    echo "$ALIAS_LINE" >> "$config_path"
    echo "  Done!"
fi

echo ""
echo "  ──────────────────────────────────────────────────────"
echo "  To use it now, run:"
echo ""
echo "    source $config_path"
echo ""
echo "  Then simply type:"
echo ""
echo "    mac-clean"
echo ""
echo "  ──────────────────────────────────────────────────────"
echo ""