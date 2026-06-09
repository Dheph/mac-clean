# macOS Cleanup Tool

Interactive shell script to clean junk files and free disk space on macOS.

## Features

- **16 cleanup categories** — Trash, Caches, Logs, Xcode, Homebrew, Node.js, Python, Docker, and more
- **System Status Dashboard** — shows disk usage and memory before and after cleanup
- **Interactive menu** — select exactly what to clean, confirm each operation
- **Safe mode** — nothing is removed without confirmation
- **Final report** — shows exactly how much space was recovered
- **Scheduled cleanup** — optional weekly/bi-weekly/monthly schedule via launchd

## Quick Start

```bash
# 1. Run installer
source start.sh   # recommended — alias works immediately
# or: bash start.sh

# 2. Run the tool
mac-clean

# 3. Follow the interactive menu
```

## Scheduling

The installer can set up a **recurring cleanup routine** using macOS `launchd`:

| Option | When it runs |
|--------|-------------|
| Weekly | Every Monday at 10 AM |
| Bi-weekly | Every 14 days |
| Monthly | 1st of each month at 10 AM |

On schedule, a Terminal window opens automatically with the cleanup menu ready. Just type numbers and confirm — zero effort.

No extra processes running. No noticeable overhead. launchd sleeps until the scheduled time.

## Categories

| # | Category | Description |
|---|----------|-------------|
| 1 | Trash | User trash |
| 2 | System Caches | `/Library/Caches` |
| 3 | User Caches | `~/Library/Caches` |
| 4 | System Logs | `/Library/Logs`, `/var/log` |
| 5 | User Logs | `~/Library/Logs` |
| 6 | Temporary Files | `/tmp`, `/private/tmp` |
| 7 | Xcode DerivedData | Build artifacts and archives |
| 8 | Homebrew Cache | Brew download cache |
| 9 | Node.js Cache | npm, yarn, pnpm caches |
| 10 | Python Cache | pip cache |
| 11 | Docker Unused Data | Unused images, containers, volumes |
| 12 | Spotify Cache | Spotify cached audio |
| 13 | Time Machine Snapshots | Local TM snapshots |
| 14 | iOS Backups | Device backup files |
| 15 | Mail Downloads | Mail.app attachments |
| 16 | .DS_Store Files | Hidden metadata files |

## Requirements

- macOS (tested on Ventura / Sonoma / Sequoia)
- Bash 3.2+

## Project

```
mac-cleanup/
├── mac-cleanup.sh      # Main cleanup tool
├── start.sh            # Installer & scheduler
├── mac-cleanup.command  # Created by start.sh for Terminal scheduling
└── README.md
```

## License

MIT
