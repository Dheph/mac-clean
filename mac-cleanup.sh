#!/usr/bin/env bash

# ══════════════════════════════════════════════════════════════
#  macOS Cleanup Tool v1.0
#  Interactive, safe cleanup script for macOS
# ══════════════════════════════════════════════════════════════

export LC_ALL=C
export LANG=C

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Responsive Box Drawing ────────────────────────────────────

box_w() {
    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    local w=$((cols - 4))
    [ "$w" -lt 46 ] && w=46
    echo "$w"
}

box_hr() {
    local ch="$1" n="${2:-}" i
    if [ -z "$n" ]; then
        n=$(box_w)
        n=$((n - 2))
    fi
    for ((i=0; i<n; i++)); do printf "%s" "$ch"; done
}

box_top() {
    local title="${1:-}" w inner left right
    w=$(box_w)
    inner=$((w - 2))
    if [ -n "$title" ]; then
        local tlen
        tlen=$(echo "$title" | awk '{print length}')
        left=$(((inner - tlen - 2) / 2))
        right=$((inner - tlen - 2 - left))
        echo -ne "  ${CYAN}╔${NC}$(box_hr ═ "$left")${NC} ${CYAN}${BOLD}${title}${NC} ${CYAN}$(box_hr ═ "$right")${NC}${CYAN}╗${NC}\n"
    else
        echo -e "  ${CYAN}╔$(box_hr ═)╗${NC}"
    fi
}

box_bot() {
    echo -e "  ${CYAN}╚$(box_hr ═)╝${NC}"
}

box_sep() {
    echo -e "  ${CYAN}╠$(box_hr ═)╣${NC}"
}

box_empty() {
    echo -e "  ${CYAN}║$(box_hr ' ')║${NC}"
}

box_line() {
    local content="$1" w clean tlen
    w=$(box_w)
    local inner=$((w - 2))
    clean=$(echo "$content" | sed 's/\x1b\[[0-9;]*m//g')
    tlen=$(echo "$clean" | awk '{print length}')
    local pad=$((inner - tlen))
    [ "$pad" -lt 0 ] && pad=0
    echo -e "  ${CYAN}║${NC}${content}$(printf '%*s' "$pad" '')${CYAN}║${NC}"
}

# ── Global Variables ─────────────────────────────────────────
TOTAL_FREED=0
BEFORE_DISK_AVAIL=""
AFTER_DISK_AVAIL=""
BEFORE_MEM_USED=""
AFTER_MEM_USED=""
CATEGORIES_CLEANED=()
CATEGORIES_SKIPPED=()
CATEGORIES_FREED=()

# ── Config ─────────────────────────────────────────────────────
resolve_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -L "$source" ]; do
        local target
        target=$(readlink "$source" 2>/dev/null || echo "")
        if [ -z "$target" ]; then break; fi
        if [[ "$target" != /* ]]; then
            source="$(cd "$(dirname "$source")" && pwd)/$target"
        else
            source="$target"
        fi
    done
    cd "$(dirname "$source")" && pwd
}
SCRIPT_DIR="$(resolve_script_dir)"
CONFIG_DIR="$HOME/.config/mac-cleanup"
CONFIG_FILE="$CONFIG_DIR/config"

read_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE" 2>/dev/null
        return 0
    fi
    SCHEDULE_TYPE=""
    SCHEDULE_DAY=""
    SCHEDULE_HOUR=""
    SCHEDULE_MINUTE=""
    SCHEDULE_CREATED=""
    return 1
}

days_until_next_run() {
    local type="${SCHEDULE_TYPE:-}" day="${SCHEDULE_DAY:-1}"
    local hour="${SCHEDULE_HOUR:-0}" min="${SCHEDULE_MINUTE:-0}"
    local created="${SCHEDULE_CREATED:-0}"

    if [ -z "$type" ]; then return; fi

    case "$type" in
        weekly)
            local now now_day
            now=$(date +%s)
            now_day=$(date +%u)
            local target=$day
            local diff=$(( (target - now_day + 7) % 7 ))
            [ "$diff" -eq 0 ] && diff=7
            local next_epoch=$(( now + diff * 86400 ))
            echo "$(( (next_epoch - now) / 86400 ))"
            ;;
        biweekly)
            local interval=$(( 14 * 86400 ))
            local now
            now=$(date +%s)
            [ "$created" -eq 0 ] && { echo "?"; return; }
            local elapsed=$(( now - created ))
            local periods=$(( elapsed / interval ))
            local next_epoch=$(( created + (periods + 1) * interval ))
            echo "$(( (next_epoch - now) / 86400 ))"
            ;;
        monthly)
            local now now_day
            now=$(date +%s)
            now_day=$(date +%d)
            now_day=$((10#$now_day))
            target=$day
            if [ "$now_day" -le "$target" ]; then
                echo "$(( target - now_day ))"
            else
                local days_in_month
                days_in_month=$(cal "$(date +%m)" "$(date +%Y)" 2>/dev/null | awk 'NF {days=$NF} END {print days}')
                echo "$(( days_in_month - now_day + target ))"
            fi
            ;;
    esac
}

schedule_type_name() {
    case "${SCHEDULE_TYPE:-}" in
        weekly)   echo "Every $(day_name ${SCHEDULE_DAY:-1}) at ${SCHEDULE_HOUR:-10}:00" ;;
        biweekly) echo "Every 14 days" ;;
        monthly)  echo "Every month on day ${SCHEDULE_DAY:-1} at ${SCHEDULE_HOUR:-10}:00" ;;
        *)        echo "Not configured" ;;
    esac
}

day_name() {
    case "$1" in
        1) echo "Monday" ;; 2) echo "Tuesday" ;; 3) echo "Wednesday" ;;
        4) echo "Thursday" ;; 5) echo "Friday" ;; 6) echo "Saturday" ;; 7) echo "Sunday" ;;
        *) echo "Day $1" ;;
    esac
}

# ── Schedule Helpers ──────────────────────────────────────────

PLIST_LABEL="com.mac-cleanup.schedule"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

write_plist() {
    local cmd_file="$1" interval="$2" weekday="${3:-}"
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
        1|weekly)
            local day="${weekday:-1}"
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
        2|biweekly)
            cat >> "$PLIST_PATH" <<- EOF
    <key>StartInterval</key>
    <integer>1209600</integer>
EOF
            ;;
        3|monthly)
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
    rm -f "$PLIST_PATH" "$CONFIG_FILE"
}

setup_schedule() {
    local interval="$1" weekday="${2:-}"
    local cmd_file="$SCRIPT_DIR/mac-cleanup.command"

    if [ ! -f "$cmd_file" ]; then
        cat > "$cmd_file" <<- EOF
#!/usr/bin/env bash
cd "\$(dirname "\$0")"
exec ./mac-cleanup.sh
EOF
        chmod +x "$cmd_file"
    fi

    mkdir -p "$CONFIG_DIR"

    case "$interval" in
        1|weekly)
            local wd="${weekday:-1}"
            cat > "$CONFIG_FILE" <<- EOF
SCHEDULE_TYPE=weekly
SCHEDULE_DAY=$wd
SCHEDULE_HOUR=10
SCHEDULE_MINUTE=0
SCHEDULE_CREATED=$(date +%s)
EOF
            write_plist "$cmd_file" weekly "$wd"
            ;;
        2|biweekly)
            cat > "$CONFIG_FILE" <<- EOF
SCHEDULE_TYPE=biweekly
SCHEDULE_CREATED=$(date +%s)
EOF
            write_plist "$cmd_file" biweekly
            ;;
        3|monthly)
            cat > "$CONFIG_FILE" <<- EOF
SCHEDULE_TYPE=monthly
SCHEDULE_DAY=1
SCHEDULE_HOUR=10
SCHEDULE_MINUTE=0
SCHEDULE_CREATED=$(date +%s)
EOF
            write_plist "$cmd_file" monthly
            ;;
    esac

    load_plist
}

# ── Helper Functions ──────────────────────────────────────────

safe_int() {
    local val="$1"
    val="${val//[^0-9]/}"
    echo "${val:-0}"
}

format_size() {
    local bytes
    bytes=$(safe_int "$1")
    if [ "$bytes" -eq 0 ]; then
        echo "0 B"
    elif [ "$bytes" -lt 1024 ]; then
        echo "${bytes} B"
    elif [ "$bytes" -lt 1048576 ]; then
        awk "BEGIN {printf \"%.1f KB\", ${bytes}/1024}"
    elif [ "$bytes" -lt 1073741824 ]; then
        awk "BEGIN {printf \"%.1f MB\", ${bytes}/1048576}"
    else
        awk "BEGIN {printf \"%.2f GB\", ${bytes}/1073741824}"
    fi
}

get_dir_size() {
    local dir="$1"
    if [ ! -e "$dir" ]; then
        echo 0
        return
    fi
    local size
    size=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
    size=$(safe_int "$size")
    echo "$size"
}

get_dir_size_human() {
    local kb
    kb=$(get_dir_size "$1")
    format_size "$((kb * 1024))"
}

get_file_count() {
    local dir="$1"
    if [ ! -e "$dir" ]; then
        echo 0
        return
    fi
    local count
    count=$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')
    count=$(safe_int "$count")
    echo "$count"
}

get_disk_info() {
    df -k / 2>/dev/null | awk 'NR==2 || NR==1 {print $2, $3, $4}' | tail -1
}

get_disk_available() {
    df -k / 2>/dev/null | awk 'END {print $4}'
}

get_memory_used_gb() {
    local total_mem page_size
    total_mem=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    total_mem=$(safe_int "$total_mem")
    page_size=$(safe_int "$page_size")

    if [ "$total_mem" -eq 0 ] || [ "$page_size" -eq 0 ]; then
        echo "0.0"
        return
    fi

    local vm_stats
    vm_stats=$(vm_stat 2>/dev/null)

    local pages_active pages_wired
    pages_active=$(echo "$vm_stats" | awk '/Pages active/ {gsub(/[^0-9]/,"",$NF); print $NF}')
    pages_wired=$(echo "$vm_stats" | awk '/wired/{if($2=="wired" && $3=="down:") {gsub(/[^0-9]/,"",$NF); print $NF}}' )
    pages_active=$(safe_int "$pages_active")
    pages_wired=$(safe_int "$pages_wired")

    local used_bytes=$(( (pages_active + pages_wired) * page_size ))

    awk "BEGIN {printf \"%.1f\", ${used_bytes}/1073741824}" 2>/dev/null || echo "0.0"
}

get_total_memory_gb() {
    local total_mem
    total_mem=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    total_mem=$(safe_int "$total_mem")
    if [ "$total_mem" -eq 0 ]; then
        echo "0.0"
        return
    fi
    awk "BEGIN {printf \"%.1f\", ${total_mem}/1073741824}" 2>/dev/null || echo "0.0"
}

# ── Category Definitions ──────────────────────────────────────

get_trash_size() {
    local total=0 s
    s=$(get_dir_size "$HOME/.Trash")
    total=$((total + s))
    echo "$total"
}

clean_trash() {
    rm -rf "${HOME}/.Trash/"* 2>/dev/null || true
    sudo rm -rf "/.Trashes/"* 2>/dev/null || true
}

get_system_caches_size() {
    get_dir_size "/Library/Caches"
}

clean_system_caches() {
    sudo rm -rf /Library/Caches/* 2>/dev/null || true
}

get_user_caches_size() {
    local total=0 s
    s=$(get_dir_size "$HOME/Library/Caches")
    total=$((total + s))
    echo "$total"
}

clean_user_caches() {
    rm -rf "${HOME}/Library/Caches/"* 2>/dev/null || true
}

get_system_logs_size() {
    local total=0 s
    s=$(get_dir_size "/Library/Logs")
    total=$((total + s))
    s=$(get_dir_size "/var/log")
    total=$((total + s))
    echo "$total"
}

clean_system_logs() {
    sudo rm -rf /Library/Logs/* 2>/dev/null || true
    sudo rm -rf /var/log/*.log.* 2>/dev/null || true
    sudo rm -rf /var/log/asl/*.asl 2>/dev/null || true
}

get_user_logs_size() {
    get_dir_size "$HOME/Library/Logs"
}

clean_user_logs() {
    rm -rf "${HOME}/Library/Logs/"* 2>/dev/null || true
}

get_temp_files_size() {
    local total=0 s
    s=$(get_dir_size "/tmp")
    total=$((total + s))
    s=$(get_dir_size "/private/tmp")
    total=$((total + s))
    s=$(get_dir_size "$HOME/Library/TemporaryItems")
    total=$((total + s))
    echo "$total"
}

clean_temp_files() {
    sudo rm -rf /tmp/* 2>/dev/null || true
    sudo rm -rf /private/tmp/* 2>/dev/null || true
    rm -rf "${HOME}/Library/TemporaryItems/"* 2>/dev/null || true
}

get_xcode_size() {
    local total=0 s
    s=$(get_dir_size "$HOME/Library/Developer/Xcode/DerivedData")
    total=$((total + s))
    s=$(get_dir_size "$HOME/Library/Developer/Xcode/Archives")
    total=$((total + s))
    s=$(get_dir_size "$HOME/Library/Developer/Xcode/iOS Device Logs")
    total=$((total + s))
    echo "$total"
}

clean_xcode() {
    rm -rf "${HOME}/Library/Developer/Xcode/DerivedData/"* 2>/dev/null || true
    rm -rf "${HOME}/Library/Developer/Xcode/Archives/"* 2>/dev/null || true
    rm -rf "${HOME}/Library/Developer/Xcode/iOS Device Logs/"* 2>/dev/null || true
}

get_homebrew_size() {
    if ! command -v brew >/dev/null 2>&1; then
        echo 0
        return
    fi
    get_dir_size "$HOME/Library/Caches/Homebrew"
}

clean_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        brew cleanup --prune=all 2>/dev/null || true
        rm -rf "${HOME}/Library/Caches/Homebrew/"* 2>/dev/null || true
    fi
}

get_node_size() {
    local total=0 s
    s=$(get_dir_size "$HOME/.npm/_cacache")
    total=$((total + s))
    s=$(get_dir_size "$HOME/.cache/yarn")
    total=$((total + s))
    s=$(get_dir_size "$HOME/.cache/pnpm")
    total=$((total + s))
    echo "$total"
}

clean_node() {
    rm -rf "${HOME}/.npm/_cacache" 2>/dev/null || true
    rm -rf "${HOME}/.cache/yarn" 2>/dev/null || true
    rm -rf "${HOME}/.cache/pnpm" 2>/dev/null || true
}

get_python_size() {
    get_dir_size "$HOME/Library/Caches/pip"
}

clean_python() {
    rm -rf "${HOME}/Library/Caches/pip" 2>/dev/null || true
}

get_docker_size() {
    if ! command -v docker >/dev/null 2>&1; then
        echo 0
        return
    fi
    if ! docker info >/dev/null 2>&1; then
        echo 0
        return
    fi
    echo 0
}

clean_docker() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        docker system prune -af --volumes 2>/dev/null || true
    fi
}

get_spotify_size() {
    get_dir_size "$HOME/Library/Caches/com.spotify.client"
}

clean_spotify() {
    rm -rf "${HOME}/Library/Caches/com.spotify.client" 2>/dev/null || true
}

get_tm_snapshots_size() {
    local count
    count=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple" || true)
    count=$(safe_int "$count")
    echo "$((count * 1024))"
}

clean_tm_snapshots() {
    local snapshots
    snapshots=$(tmutil listlocalsnapshots / 2>/dev/null | grep "com.apple" || true)
    if [ -z "$snapshots" ]; then
        return
    fi
    for snapshot in $snapshots; do
        local snap_date
        snap_date=$(echo "$snapshot" | sed 's/.*com\.apple\.TimeMachine\.//')
        sudo tmutil deletelocalsnapshots "$snap_date" 2>/dev/null || true
    done
}

get_ios_backups_size() {
    get_dir_size "$HOME/Library/Application Support/MobileSync/Backup"
}

clean_ios_backups() {
    local backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
    if [ ! -d "$backup_dir" ]; then
        return
    fi
    echo ""
    echo -e "  ${CYAN}Available iOS Backups:${NC}"
    local i=1
    for backup in "$backup_dir"/*; do
        if [ -d "$backup" ]; then
            local size
            size=$(get_dir_size_human "$backup")
            local name
            name=$(defaults read "$backup/Info" "Display Name" 2>/dev/null || echo "Unknown")
            local date
            date=$(defaults read "$backup/Info" "Last Modified Date" 2>/dev/null || echo "Unknown")
            echo -e "  ${YELLOW}$i)${NC} $name ($size) - $date"
            i=$((i + 1))
        fi
    done
    echo ""
    read -rp "  Delete all backups? [y/N]: " confirm
    if echo "$confirm" | grep -qi "^y"; then
        rm -rf "$backup_dir"/* 2>/dev/null || true
    else
        CATEGORIES_SKIPPED+=("iOS Backups")
        return 1
    fi
}

get_mail_downloads_size() {
    get_dir_size "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
}

clean_mail_downloads() {
    rm -rf "${HOME}/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/"* 2>/dev/null || true
}

get_ds_store_size() {
    local count
    count=$(find "$HOME" -maxdepth 5 -name ".DS_Store" -type f 2>/dev/null | wc -l | tr -d ' ')
    count=$(safe_int "$count")
    echo "$((count * 4))"
}

clean_ds_store() {
    find "$HOME" -maxdepth 5 -name ".DS_Store" -type f -delete 2>/dev/null || true
}

# ── Category Table ────────────────────────────────────────────

CAT_NAMES=(
    "Trash"
    "System Caches"
    "User Caches"
    "System Logs"
    "User Logs"
    "Temporary Files"
    "Xcode DerivedData"
    "Homebrew Cache"
    "Node.js Cache"
    "Python Cache"
    "Docker Unused Data"
    "Spotify Cache"
    "Time Machine Snapshots"
    "iOS Backups"
    "Mail Downloads"
    ".DS_Store Files"
)

CAT_PATHS=(
    "~/.Trash"
    "/Library/Caches"
    "~/Library/Caches"
    "/Library/Logs, /var/log"
    "~/Library/Logs"
    "/tmp, /private/tmp"
    "~/Library/Developer/Xcode/DerivedData"
    "~/Library/Caches/Homebrew"
    "~/.npm, ~/.cache/yarn, ~/.cache/pnpm"
    "~/Library/Caches/pip"
    "docker system prune"
    "~/Library/Caches/com.spotify.client"
    "tmutil listlocalsnapshots"
    "~/Library/Application Support/MobileSync/Backup"
    "~/Library/Containers/com.apple.mail/.../Mail Downloads"
    "~ (recursive .DS_Store)"
)

CAT_SUDO=("partial" "yes" "no" "yes" "no" "partial" "no" "no" "no" "no" "no" "no" "yes" "no" "no" "no")

CAT_SIZE_CACHE=()

# ── Scan All Categories ──────────────────────────────────────

scan_categories() {
    echo -e "  ${DIM}Scanning categories...${NC}\n"

    CAT_SIZE_CACHE[0]=$(get_trash_size)
    CAT_SIZE_CACHE[1]=$(get_system_caches_size)
    CAT_SIZE_CACHE[2]=$(get_user_caches_size)
    CAT_SIZE_CACHE[3]=$(get_system_logs_size)
    CAT_SIZE_CACHE[4]=$(get_user_logs_size)
    CAT_SIZE_CACHE[5]=$(get_temp_files_size)
    CAT_SIZE_CACHE[6]=$(get_xcode_size)
    CAT_SIZE_CACHE[7]=$(get_homebrew_size)
    CAT_SIZE_CACHE[8]=$(get_node_size)
    CAT_SIZE_CACHE[9]=$(get_python_size)
    CAT_SIZE_CACHE[10]=$(get_docker_size)
    CAT_SIZE_CACHE[11]=$(get_spotify_size)
    CAT_SIZE_CACHE[12]=$(get_tm_snapshots_size)
    CAT_SIZE_CACHE[13]=$(get_ios_backups_size)
    CAT_SIZE_CACHE[14]=$(get_mail_downloads_size)
    CAT_SIZE_CACHE[15]=$(get_ds_store_size)

    local total_junk=0 i
    for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        total_junk=$((total_junk + ${CAT_SIZE_CACHE[$i]:-0}))
    done

    echo -e "  ${GREEN}Scan complete!${NC} Total junk found: ${BOLD}$(format_size $((total_junk * 1024)))${NC}\n"
}

# ── Print System Status ──────────────────────────────────────

print_system_status() {
    local disk_info disk_total_kb disk_used_kb disk_avail_kb
    local disk_total_gb disk_used_gb disk_avail_gb disk_pct
    local mem_total mem_used mem_free

    disk_info=$(get_disk_info)
    disk_total_kb=$(echo "$disk_info" | awk '{print $1}')
    disk_used_kb=$(echo "$disk_info" | awk '{print $2}')
    disk_avail_kb=$(echo "$disk_info" | awk '{print $3}')

    disk_total_kb=$(safe_int "$disk_total_kb")
    disk_used_kb=$(safe_int "$disk_used_kb")
    disk_avail_kb=$(safe_int "$disk_avail_kb")

    if [ "$disk_total_kb" -eq 0 ]; then
        disk_total_gb="N/A"
        disk_used_gb="N/A"
        disk_avail_gb="N/A"
        disk_pct="N/A"
    else
        disk_total_gb=$(awk "BEGIN {printf \"%.1f\", ${disk_total_kb}/1048576}")
        disk_used_gb=$(awk "BEGIN {printf \"%.1f\", ${disk_used_kb}/1048576}")
        disk_avail_gb=$(awk "BEGIN {printf \"%.1f\", ${disk_avail_kb}/1048576}")
        disk_pct=$(awk "BEGIN {printf \"%.1f\", ${disk_used_kb}*100/${disk_total_kb}}")
    fi

    mem_total=$(get_total_memory_gb)
    mem_used=$(get_memory_used_gb)
    mem_free=$(awk "BEGIN {printf \"%.1f\", ${mem_total} - ${mem_used}}" 2>/dev/null || echo "0.0")

    BEFORE_DISK_AVAIL="$disk_avail_gb"
    BEFORE_MEM_USED="$mem_used"

    echo ""
    box_top "System Status"
    box_empty
    box_line "  ${BOLD}Disk Total:${NC}      ${disk_total_gb} GB"
    box_line "  ${BOLD}Disk Used:${NC}       ${disk_used_gb} GB (${disk_pct}%)"
    box_line "  ${BOLD}Disk Available:${NC}  ${disk_avail_gb} GB"
    box_empty
    box_line "  ${BOLD}Memory Total:${NC}    ${mem_total} GB"
    box_line "  ${BOLD}Memory Used:${NC}     ${mem_used} GB"
    box_line "  ${BOLD}Memory Free:${NC}     ${mem_free} GB"
    box_empty
    box_bot
}

# ── Print Menu ────────────────────────────────────────────────

print_menu() {
    echo ""
    echo -e "  ${BOLD}Select categories to clean (comma-separated numbers):${NC}"
    echo ""

    local j size_bytes size_str sudo_badge num dots_count dots
    local i
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
        j=$((i - 1))
        size_bytes=$(( ${CAT_SIZE_CACHE[$j]:-0} * 1024 ))
        size_str=$(format_size "$size_bytes")

        sudo_badge=""
        if [ "${CAT_SUDO[$j]}" = "yes" ]; then
            sudo_badge=" ${DIM}[sudo]${NC}"
        elif [ "${CAT_SUDO[$j]}" = "partial" ]; then
            sudo_badge=" ${DIM}[partial sudo]${NC}"
        fi

        if [ "$i" -lt 10 ]; then
            num=" $i"
        else
            num="$i"
        fi

        dots_count=$(( 30 - ${#CAT_NAMES[$j]} ))
        dots=$(printf '%*s' "$dots_count" | tr ' ' '.')

        echo -e "  ${YELLOW}[${num}]${NC} ${CAT_NAMES[$j]} ${DIM}${dots}${NC} ${size_str}${sudo_badge}"
    done

    echo ""
    echo -e "  ${GREEN}[A]${NC} Select All    ${RED}[N]${NC} None    ${BOLD}[Q]${NC} Quit"
    echo ""
}

# ── Clean a Single Category ──────────────────────────────────

clean_category() {
    local idx=$1
    local arr_idx=$((idx - 1))
    local cat_name="${CAT_NAMES[$arr_idx]}"
    local cat_path="${CAT_PATHS[$arr_idx]}"
    local size_kb="${CAT_SIZE_CACHE[$arr_idx]:-0}"
    size_kb=$(safe_int "$size_kb")
    local sudo_req="${CAT_SUDO[$arr_idx]}"
    local size_str
    size_str=$(format_size "$((size_kb * 1024))")

    if [ "$size_kb" -eq 0 ]; then
        echo -e "\n  ${DIM}Skipping ${cat_name}: nothing to clean.${NC}"
        CATEGORIES_SKIPPED+=("$cat_name (empty)")
        return
    fi

    echo ""
    box_top "Cleaning: ${cat_name}"
    box_empty
    box_line "  ${BOLD}Path:${NC}    ${cat_path}"
    box_line "  ${BOLD}Size:${NC}    ${size_str}"
    if [ "$sudo_req" = "yes" ]; then
        box_line "  ${BOLD}Requires:${NC} sudo"
    elif [ "$sudo_req" = "partial" ]; then
        box_line "  ${BOLD}Requires:${NC} sudo (partial)"
    fi
    box_empty
    echo -e "  ${CYAN}║${NC}  Proceed? ${BOLD}[y/N]${NC}: \c"

    read -r confirm
    if ! echo "$confirm" | grep -qi "^y"; then
        box_empty
        box_line "  ${YELLOW}Skipped.${NC}"
        box_bot
        CATEGORIES_SKIPPED+=("$cat_name")
        return
    fi

    box_empty

    local before_size="$size_kb"

    case "$idx" in
        1)  clean_trash ;;
        2)  clean_system_caches ;;
        3)  clean_user_caches ;;
        4)  clean_system_logs ;;
        5)  clean_user_logs ;;
        6)  clean_temp_files ;;
        7)  clean_xcode ;;
        8)  clean_homebrew ;;
        9)  clean_node ;;
        10) clean_python ;;
        11) clean_docker ;;
        12) clean_spotify ;;
        13) clean_tm_snapshots ;;
        14) clean_ios_backups || return 0 ;;
        15) clean_mail_downloads ;;
        16) clean_ds_store ;;
    esac

    local freed_bytes=$((before_size * 1024))
    local freed_str
    freed_str=$(format_size "$freed_bytes")

    TOTAL_FREED=$((TOTAL_FREED + freed_bytes))

    CATEGORIES_CLEANED+=("$cat_name")
    CATEGORIES_FREED+=("$freed_str")

    echo ""
    box_line "  ${GREEN}✓ Cleaned: ${freed_str} freed${NC}"
    box_bot
}

# ── Print Final Report ────────────────────────────────────────

print_final_report() {
    local after_disk_kb
    after_disk_kb=$(get_disk_available)
    after_disk_kb=$(safe_int "$after_disk_kb")
    AFTER_DISK_AVAIL=$(awk "BEGIN {printf \"%.1f\", ${after_disk_kb}/1048576}" 2>/dev/null || echo "0.0")
    AFTER_MEM_USED=$(get_memory_used_gb)

    local disk_before="$BEFORE_DISK_AVAIL"
    local disk_after="$AFTER_DISK_AVAIL"
    local disk_recovered
    disk_recovered=$(awk "BEGIN {printf \"%.1f\", ${disk_after} - ${disk_before}}" 2>/dev/null || echo "0.0")

    echo ""
    box_top "Cleanup Report"
    box_sep
    box_empty
    box_line "  ${BOLD}DISK${NC}"
    box_line "  ├── Before:        ${disk_before} GB available"
    box_line "  ├── After:         ${disk_after} GB available"

    local sign=""
    local color="${GREEN}"
    local rec_val
    rec_val=$(awk "BEGIN { print (${disk_after} - ${disk_before}) }" 2>/dev/null || echo "0.0")
    if awk "BEGIN { exit (${rec_val} >= 0) }" 2>/dev/null; then
        color="${RED}"
    fi
    box_line "  └── Recovered:     ${color}${disk_recovered} GB${NC}"

    box_empty
    box_line "  ${BOLD}MEMORY${NC}"
    box_line "  ├── Before:        ${BEFORE_MEM_USED} GB used"
    box_line "  └── After:         ${AFTER_MEM_USED} GB used"
    box_empty
    box_line "  ${BOLD}BREAKDOWN${NC}"

    local i=0 freed dots_count dots
    for cat in "${CATEGORIES_CLEANED[@]}"; do
        freed="${CATEGORIES_FREED[$i]}"
        dots_count=$(( 28 - ${#cat} ))
        dots=$(printf '%*s' "$dots_count" | tr ' ' '.')
        box_line "  ├── ${GREEN}[✓]${NC} ${cat} ${DIM}${dots}${NC} ${freed}"
        i=$((i + 1))
    done

    for cat in "${CATEGORIES_SKIPPED[@]}"; do
        dots_count=$(( 28 - ${#cat} ))
        dots=$(printf '%*s' "$dots_count" | tr ' ' '.')
        box_line "  ├── ${DIM}[—]${NC} ${cat} ${dots} ${DIM}skipped${NC}"
    done

    local total_str
    total_str=$(format_size "$TOTAL_FREED")

    box_empty
    box_line "  ${BOLD}Total Freed: ${total_str}${NC}"
    box_empty
    box_bot
    echo ""
}

show_header() {
    box_top "M A C   C L E A N"
    echo ""
    echo -e "  ${DIM}Commands:${NC}"
    echo -e "    ${BOLD}mac-clean${NC}         Run interactive cleanup"
    echo -e "    ${BOLD}mac-clean help${NC}    Show help & category info"
    echo -e "    ${BOLD}mac-clean setup${NC}   Manage scheduled cleanup"
    echo ""
}

show_help() {
    clear
    show_header
    echo -e "  ${BOLD}ABOUT${NC}"
    echo -e "  macOS Cleanup Tool — safely removes junk files"
    echo -e "  to free disk space. Every action is confirmed"
    echo -e "  before deletion. Nothing runs without your OK."
    echo ""
    echo -e "  ${BOLD}CATEGORIES${NC}"
    echo ""
    printf "  %-2s  %-20s %s\n" " #" "Category" "Description"
    printf "  %-2s  %-20s %s\n" "---" "--------------------" "------------------------------"
    printf "  %-2s  %-20s %s\n" " 1" "Trash" "User trash"
    printf "  %-2s  %-20s %s\n" " 2" "System Caches" "/Library/Caches"
    printf "  %-2s  %-20s %s\n" " 3" "User Caches" "~/Library/Caches"
    printf "  %-2s  %-20s %s\n" " 4" "System Logs" "/Library/Logs, /var/log"
    printf "  %-2s  %-20s %s\n" " 5" "User Logs" "~/Library/Logs"
    printf "  %-2s  %-20s %s\n" " 6" "Temporary Files" "/tmp, /private/tmp"
    printf "  %-2s  %-20s %s\n" " 7" "Xcode DerivedData" "Build artifacts"
    printf "  %-2s  %-20s %s\n" " 8" "Homebrew Cache" "Brew download cache"
    printf "  %-2s  %-20s %s\n" " 9" "Node.js Cache" "npm, yarn, pnpm"
    printf "  %-2s  %-20s %s\n" "10" "Python Cache" "pip cache"
    printf "  %-2s  %-20s %s\n" "11" "Docker Unused" "Images, containers, volumes"
    printf "  %-2s  %-20s %s\n" "12" "Spotify Cache" "Cached audio"
    printf "  %-2s  %-20s %s\n" "13" "Time Machine" "Local snapshots"
    printf "  %-2s  %-20s %s\n" "14" "iOS Backups" "Device backups"
    printf "  %-2s  %-20s %s\n" "15" "Mail Downloads" "Mail attachments"
    printf "  %-2s  %-20s %s\n" "16" ".DS_Store" "Hidden metadata files"
    echo ""
    echo -e "  ${BOLD}SCHEDULED CLEANUP${NC}"
    echo -e "  Run ${BOLD}mac-clean setup${NC} to see your schedule,"
    echo -e "  change frequency, or remove it."
    echo ""
    echo -e "  ${BOLD}ALIAS${NC}"
    echo -e "  Run ${BOLD}source start.sh${NC} from the project folder"
    echo -e "  to install the ${DIM}mac-clean${NC} alias and schedule."
    echo ""
}

setup_menu() {
    clear
    show_header
    echo -e "  ${BOLD}SCHEDULED CLEANUP${NC}"
    echo ""

    read_config
    local plist="$HOME/Library/LaunchAgents/com.mac-cleanup.schedule.plist"

    if [ -n "$SCHEDULE_TYPE" ] && [ -f "$plist" ]; then
        local remaining
        remaining=$(days_until_next_run)
        echo -e "  Status:  ${GREEN}Active${NC}"
        echo -e "  Schedule: $(schedule_type_name)"
        [ -n "$remaining" ] && echo -e "  Next:    ~${remaining} day(s)"
        echo ""
        echo -e "  ${BOLD}[1]${NC} Change schedule"
        echo -e "  ${BOLD}[2]${NC} Remove schedule"
        echo -e "  ${BOLD}[3]${NC} Cancel"
        echo ""
        read -rp "  Choice [1-3]: " opt
        case "$opt" in
            1)
                echo ""
                echo "    ${BOLD}[1]${NC} Weekly (every Monday)"
                echo "    ${BOLD}[2]${NC} Every 2 weeks"
                echo "    ${BOLD}[3]${NC} Monthly (1st of month)"
                echo "    ${BOLD}[4]${NC} Cancel"
                echo ""
                read -rp "    Interval [1-4]: " new_sched
                case "$new_sched" in
                    1)
                        read -rp "    Weekday [1=Mon-7=Sun, default=1]: " wd
                        setup_schedule 1 "${wd:-1}"
                        echo -e "  ${GREEN}✓${NC} Schedule updated!"
                        ;;
                    2)
                        setup_schedule 2
                        echo -e "  ${GREEN}✓${NC} Schedule updated!"
                        ;;
                    3)
                        setup_schedule 3
                        echo -e "  ${GREEN}✓${NC} Schedule updated!"
                        ;;
                    *)
                        echo "  No changes."
                        ;;
                esac
                ;;
            2)
                unload_plist
                echo -e "  ${GREEN}✓${NC} Schedule removed."
                ;;
            *)
                echo "  No changes."
                ;;
        esac
    else
        echo -e "  Status:  ${DIM}Not configured${NC}"
        echo ""
        echo -e "  ${BOLD}[1]${NC} Weekly (every Monday)"
        echo -e "  ${BOLD}[2]${NC} Every 2 weeks"
        echo -e "  ${BOLD}[3]${NC} Monthly (1st of month)"
        echo -e "  ${BOLD}[4]${NC} Cancel"
        echo ""
        read -rp "  Choice [1-4]: " new_sched
        case "$new_sched" in
            1)
                read -rp "  Weekday [1=Mon-7=Sun, default=1]: " wd
                setup_schedule 1 "${wd:-1}"
                echo -e "  ${GREEN}✓${NC} Schedule created!"
                ;;
            2)
                setup_schedule 2
                echo -e "  ${GREEN}✓${NC} Schedule created!"
                ;;
            3)
                setup_schedule 3
                echo -e "  ${GREEN}✓${NC} Schedule created!"
                ;;
            *)
                echo "  No changes."
                ;;
        esac
    fi
    echo ""
}

# ── Main ──────────────────────────────────────────────────────

main() {
    case "${1:-}" in
        help|--help|-h)
            show_help
            exit 0
            ;;
        setup)
            setup_menu
            exit 0
            ;;
    esac

    clear
    show_header

    print_system_status
    echo ""

    scan_categories

    print_menu

    read -rp "  Enter choice: " choice

    choice=$(echo "$choice" | tr -d ' ')

    if echo "$choice" | grep -qi "^q$"; then
        echo -e "\n  ${DIM}Bye!${NC}\n"
        exit 0
    fi

    local indices=()

    if echo "$choice" | grep -qi "^a$"; then
        for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
            indices+=("$i")
        done
    elif echo "$choice" | grep -qi "^n$"; then
        echo -e "\n  ${DIM}Nothing selected. Bye!${NC}\n"
        exit 0
    else
        local old_ifs="$IFS"
        IFS=','
        for num in $choice; do
            if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le 16 ] 2>/dev/null; then
                indices+=("$num")
            fi
        done
        IFS="$old_ifs"
    fi

    if [ ${#indices[@]} -eq 0 ]; then
        echo -e "\n  ${RED}No valid categories selected.${NC}\n"
        exit 1
    fi

    local cat_word
    if [ "${#indices[@]}" -gt 1 ]; then
        cat_word="categories"
    else
        cat_word="category"
    fi
    echo -e "\n  ${BOLD}Will clean ${#indices[@]} ${cat_word}...${NC}"

    for idx in "${indices[@]}"; do
        clean_category "$idx"
    done

    print_final_report
}

main "$@"