---
layout: default
title: How it works
---

# How claude-usage-on-icon works

## Architecture overview

```
┌──────────────────────┐    stdin JSON     ┌─────────────────────┐   writes   ┌──────────────────────┐   reads (poll)   ┌──────────────┐
│ Claude Code CLI      │ ───────────────▶ │ status line script  │ ─────────▶ │ usage-cache.json      │ ◀─────────────── │ tray / menu  │
│ (Windows/Linux/WSL/  │                   │ (prints one line    │            │ (in the Claude folder │                  │ bar app      │
│  macOS)              │ ◀─── stdout ───── │  + saves cache)     │ ─────────▶ │  the tray watches)    │                  │              │
└──────────────────────┘   status text     └─────────────────────┘  diag log  └──────────────────────┘                  └──────────────┘
```

## The two components

### 1. Status line script (the "writer")

The status line script runs every time Claude Code refreshes:

1. **Reads** JSON from stdin (the status line input from Claude Code)
2. **Prints** a one-line status: `[Model] | ctx 12% | 5h 31% (resets 14:45) | week 12% (resets Mon 04:52)`
3. **Writes** `usage-cache.json` **only if** `rate_limits` is present in the input
4. **Logs** a diagnostic line to `usage-statusline.log` (one line, overwritten each run)

- **Speed:** < 150 ms target
- **Dependencies:** Python 3.8+ stdlib, PowerShell 5.1, or shell builtins
- **No network calls, no credential access**

### 2. Tray app / menu bar plugin (the "reader")

The tray app runs in the background and polls the cache:

1. **Polls** `usage-cache.json` every 15 seconds
2. **Renders** an icon with the 5-hour usage % (falling back to weekly if 5h is missing)
3. **Colors** the icon based on usage: green < 70%, amber 70–89%, red ≥ 90%, grey if stale (> 12h old)
4. **Shows** on hover: `v1.0.0 5h 31% @14:45 | wk 12% | 3m ago` (limited to 63 chars on Windows)
5. **Shows** on click: detailed window, "updated N ago", version, cache path, and stale hint
6. **Reads only**, writes nothing

## Data contract: `usage-cache.json`

The cache is the single source of truth. Both components must agree on its format:

```json
{
  "schema": 1,
  "written_at": 1790163932,
  "writer_version": "1.0.0",
  "source": "windows | wsl | linux | macos",
  "session_id": "…or null",
  "rate_limits": {
    "five_hour": { "used_percentage": 31, "resets_at": 1790167531 },
    "seven_day": { "used_percentage": 12, "resets_at": 1790563931 }
  }
}
```

**Rules:**
- `rate_limits` is copied **verbatim** from Claude Code's input
- Readers must tolerate extra keys (e.g., `spend_limit`) and missing windows
- `written_at` is Unix seconds (UTC)
- File encoding is UTF-8 **without BOM**
- Readers reject files with `schema > 1`, with a clear message
- The writer only writes when `rate_limits` is present (never partial files)

## Platform matrix

| Target | Writer | Cache location | Tray |
|---|---|---|---|
| **Windows** | `statusline.ps1` | `%USERPROFILE%\.claude\usage-cache.json` | `tray-windows.ps1` |
| **WSL → Windows tray** | `statusline.py` | Windows path via `/mnt/c/…` | `tray-windows.ps1` (on Windows) |
| **Linux** | `statusline.py` | `~/.claude/usage-cache.json` | `tray-linux.py` (GTK + AppIndicator) |
| **macOS** | `statusline.py` (or `statusline.jxa.js`) | `~/.claude/usage-cache.json` | SwiftBar/xbar plugin (v1) or native app (v2) |

## Installation flow

Each platform has an installer:
- **Windows:** `install-windows.ps1` – copies files, merges `statusLine` into `settings.json`, creates Startup shortcut
- **WSL:** `install-wsl.sh` – installs writer, prints Windows tray install command
- **Linux:** `install-linux.sh` – installs tray, autostart via `.desktop` file
- **macOS:** `install-macos.sh` – installs writer and SwiftBar plugin (v1) or app bundle (v2)

All installers:
- Back up `settings.json` before editing
- Are idempotent (can run multiple times safely)
- Support `--dry-run` or `-WhatIf` mode
- Support `--uninstall` to remove cleanly
