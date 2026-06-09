# macOS Cleanup Tool

Interactive shell script to clean up junk files and free disk space on macOS.

## Features

- **16 cleanup categories** — Trash, Caches, Logs, Xcode, Homebrew, Node.js, Python, Docker, and more
- **System Status Dashboard** — shows disk usage and memory before and after cleanup
- **Interactive menu** — select exactly what to clean, confirm each operation
- **Safe mode** — nothing is removed without confirmation
- **Final report** — shows exactly how much space was recovered

## Quick Start

```bash
# Clone or download, then:
chmod +x mac-cleanup.sh
./mac-cleanup.sh
```

Or run the installer to add the `mac-clean` alias:

```bash
chmod +x start.sh
./start.sh
```

After running the installer, reload your shell config and type:

```bash
mac-clean
```

## Categories

| # | Category | Description |
|---|----------|-------------|
| 1 | Trash | User and system trash |
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
- Bash 3.2+ (ships with macOS)

## License

MIT
