#!/usr/bin/env bash

# ══════════════════════════════════════════════════════════════
#  macOS Cleanup Tool — Installer
#  Detects your shell and adds the `mac-clean` alias
#  Usage: source start.sh   (recomended — applies immediately)
#         bash start.sh     (alias available in future sessions)
# ══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/mac-cleanup.sh"
ALIAS_LINE="alias mac-clean='$CLEANUP_SCRIPT'"

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

add_alias_to_config() {
    local config_path="$1"
    if [ ! -f "$config_path" ]; then
        touch "$config_path" 2>/dev/null || return 1
    fi
    echo "" >> "$config_path"
    echo "# macOS Cleanup Tool" >> "$config_path"
    echo "$ALIAS_LINE" >> "$config_path"
    return 0
}

# ── Detect shell ──────────────────────────────────────────────
config_path=$(detect_shell_config)
shell_name=$(basename "$SHELL" 2>/dev/null || echo "unknown")

echo ""
echo "  macOS Cleanup Tool — Installer"
echo "  ─────────────────────────────"
echo "  Shell:         $shell_name"
echo "  Config file:   $config_path"
echo "  Script path:   $CLEANUP_SCRIPT"
echo ""

# ── Unsupported shell? ────────────────────────────────────────
if [ "$config_path" = "unknown" ]; then
    echo "  Unsupported shell: $shell_name"
    echo "  Add this alias manually:"
    echo ""
    echo "    $ALIAS_LINE"
    echo ""
    exit 1
fi

# ── Already installed? ────────────────────────────────────────
if grep -q "alias mac-clean=" "$config_path" 2>/dev/null; then
    sed -i '' '/^alias mac-clean=/d' "$config_path"
    echo "  ✓ Updated alias in $config_path"
    if add_alias_to_config "$config_path"; then
        echo "  ✓ Alias rewritten in $config_path"
    fi
else
    if add_alias_to_config "$config_path"; then
        echo "  ✓ Alias added to $config_path"
    else
        echo "  ✗ Failed to write to $config_path"
        exit 1
    fi
fi

# ── If sourced, apply alias to current shell ──────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo ""
    echo "  ════════════════════════════════════════════════════"
    echo "  Done! To use it right now in this terminal, run:"
    echo ""
    echo "    eval \"$ALIAS_LINE\""
    echo ""
    echo "  Or reload your config:"
    echo ""
    echo "    source $config_path"
    echo ""
    echo "  From new terminals it will be available automatically."
    echo "  ════════════════════════════════════════════════════"
    echo ""
else
    eval "$ALIAS_LINE"
    echo "  ✓ Alias 'mac-clean' applied to this terminal session"
    echo ""
    echo "    mac-clean"
    echo ""
fi