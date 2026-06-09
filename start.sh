#!/usr/bin/env bash

# ══════════════════════════════════════════════════════════════
#  macOS Cleanup Tool — Installer & Scheduler
#  Usage:
#    source start.sh   (recommended — applies alias immediately)
#    bash start.sh     (alias available in new terminals)
# ══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/mac-cleanup.sh"
ALIAS_LINE="alias mac-clean='$CLEANUP_SCRIPT'"
PLIST_LABEL="com.mac-cleanup.schedule"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

# ── Detect Shell Config ──────────────────────────────────────

detect_config() {
    local name
    name=$(basename "$SHELL" 2>/dev/null || echo "unknown")
    case "$name" in
        zsh)   echo "$HOME/.zshrc" ;;
        bash)
            [ -f "$HOME/.bash_profile" ] && echo "$HOME/.bash_profile" || echo "$HOME/.bashrc"
            ;;
        fish)  echo "$HOME/.config/fish/config.fish" ;;
        *)     echo "unknown" ;;
    esac
}

install_alias() {
    local cfg="$1"
    sed -i '' '/^alias mac-clean=/d' "$cfg" 2>/dev/null
    echo "# macOS Cleanup Tool" >> "$cfg"
    echo "$ALIAS_LINE" >> "$cfg"
}

# ── Launchd Plist ────────────────────────────────────────────

create_command_file() {
    local cmd="$SCRIPT_DIR/mac-cleanup.command"
    cat > "$cmd" <<- EOF
#!/usr/bin/env bash
cd "$(dirname "\$0")"
exec ./mac-cleanup.sh
EOF
    chmod +x "$cmd"
    echo "$cmd"
}

create_plist() {
    local cmd_file="$1"
    local interval="$2"  # "weekly", "biweekly", "monthly"

    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$PLIST_PATH" <<- EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>$cmd_file</string>
    </array>
EOF

    case "$interval" in
        weekly)
            local day="${3:-1}"  # default Monday
            cat >> "$PLIST_PATH" <<- EOF
    <key>StartCalendarInterval</key>
    <array>
        <dict>
            <key>Weekday</key>
            <integer>$day</integer>
            <key>Hour</key>
            <integer>10</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
    </array>
EOF
            ;;
        biweekly)
            cat >> "$PLIST_PATH" <<- EOF
    <key>StartInterval</key>
    <integer>1209600</integer>
EOF
            ;;
        monthly)
            cat >> "$PLIST_PATH" <<- EOF
    <key>StartCalendarInterval</key>
    <array>
        <dict>
            <key>Day</key>
            <integer>1</integer>
            <key>Hour</key>
            <integer>10</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
    </array>
EOF
            ;;
    esac

    cat >> "$PLIST_PATH" <<- EOF
    <key>StandardOutPath</key>
    <string>/tmp/$PLIST_LABEL.stdout</string>
    <key>StandardErrorPath</key>
    <string>/tmp/$PLIST_LABEL.stderr</string>
</dict>
</plist>
EOF

    chmod 644 "$PLIST_PATH"
}

load_plist() {
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    launchctl load "$PLIST_PATH" 2>/dev/null
}

unload_plist() {
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
}

# ── Main ──────────────────────────────────────────────────────

echo ""
echo "  ┌─────────────────────────────────────────────┐"
echo "  │         macOS Cleanup Tool Installer         │"
echo "  └─────────────────────────────────────────────┘"
echo ""

config_path=$(detect_config)
shell_name=$(basename "$SHELL" 2>/dev/null || echo "?")

if [ "$config_path" = "unknown" ]; then
    echo "  Shell: $shell_name (unsupported)"
    echo "  Add this alias manually:"
    echo "    $ALIAS_LINE"
    echo ""
    exit 1
fi

# ── Install Alias ─────────────────────────────────────────────
echo "  Shell:       $shell_name"
echo "  Config:      $config_path"
echo "  Script:      $CLEANUP_SCRIPT"
echo ""

install_alias "$config_path"
echo "  ✓ Alias 'mac-clean' installed."

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo ""
    echo "  ─────────────────────────────────────────────────"
    echo "  Next step — apply alias to this terminal:"
    echo ""
    echo "    source $config_path"
    echo ""
    echo "  Then run: mac-clean"
    echo "  ─────────────────────────────────────────────────"
else
    eval "$ALIAS_LINE"
    echo "  ✓ Alias active in this terminal."
    echo "  Run: mac-clean"
fi

# ── Scheduling ────────────────────────────────────────────────
echo ""

SCHEDULE_EXISTS=false
if [ -f "$PLIST_PATH" ] && launchctl list "$PLIST_LABEL" &>/dev/null 2>&1; then
    SCHEDULE_EXISTS=true
fi

if [ "$SCHEDULE_EXISTS" = true ]; then
    echo "  ⏰ Scheduled cleanup is active."
    read -rp "  Remove schedule? [y/N]: " remove_sched
    if echo "$remove_sched" | grep -qi "^y"; then
        unload_plist
        echo "  ✓ Schedule removed."
    else
        echo "  Keeping current schedule."
    fi
else
    echo "  ⏰ Set up automatic cleanup?"
    echo "     Opens Terminal on schedule so you can clean with one click."
    echo ""
    echo "    [1] Weekly       (every Monday at 10 AM)"
    echo "    [2] Every 2 weeks"
    echo "    [3] Monthly      (1st of each month at 10 AM)"
    echo "    [4] No schedule"
    echo ""
    read -rp "  Choose [1-4]: " sched_choice

    case "$sched_choice" in
        1)
            read -rp "  Weekday [1=Mon-7=Sun, default=1]: " weekday
            weekday="${weekday:-1}"
            cmd_file=$(create_command_file)
            create_plist "$cmd_file" "weekly" "$weekday"
            load_plist
            echo "  ✓ Scheduled: every $([ "$weekday" = "1" ] && echo "Monday" || echo "weekday $weekday") at 10 AM."
            ;;
        2)
            cmd_file=$(create_command_file)
            create_plist "$cmd_file" "biweekly"
            load_plist
            echo "  ✓ Scheduled: every 2 weeks."
            ;;
        3)
            cmd_file=$(create_command_file)
            create_plist "$cmd_file" "monthly"
            load_plist
            echo "  ✓ Scheduled: 1st of each month at 10 AM."
            ;;
        *)
            echo "  No schedule configured."
            ;;
    esac
fi

echo ""
echo "  Done!"
echo ""