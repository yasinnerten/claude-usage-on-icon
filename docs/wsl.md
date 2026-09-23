---
layout: default
title: WSL
---

# WSL installation and usage

Running Claude Code inside WSL and want the Windows tray? This guide covers both sides.

## Prerequisites

- Windows 10 or later with WSL2
- Ubuntu, Debian, or another Linux distro in WSL
- Python 3 (usually pre-installed in WSL)
- Claude Code CLI installed and running **inside WSL**

## Setup

**One command, run inside WSL — it installs both sides:**

```bash
git clone https://github.com/yasinnerten/claude-usage-on-icon.git
cd claude-usage-on-icon
./install/install-wsl.sh
```

This will:
1. Copy `statusline.py` to `~/.claude/` (inside WSL) and merge the `statusLine` setting into `~/.claude/settings.json`
2. **Automatically drive `install-windows.ps1` on the Windows side too**, via the same `cmd.exe`/`powershell.exe` interop the writer already uses to auto-detect the Windows home directory — no manual "switch to a Windows terminal" step, and no PowerShell command for you to type yourself. That step:
   - Compiles a small, auditable C# source file (`install/ClaudeUsageOnIconTray.cs`) into a real `ClaudeUsageOnIconTray.exe`, using the C# compiler already built into every Windows install (`csc.exe` — no download, no binary committed to this repo)
   - Installs the tray and creates a Startup entry pointing straight at that `.exe` — starting the tray from then on is a double-click, not a PowerShell command with `-ExecutionPolicy Bypass` in it
   - Starts the tray immediately
3. Print its own disclosure banner for what the Windows side touches, same as the WSL side's banner, before doing anything

The writer auto-detects the Windows home directory and writes the cache to `/mnt/c/Users/<username>/.claude/usage-cache.json` (accessible from Windows) — no manual path needed on either side.

**If you'd rather do the Windows half yourself** (or `install-wsl.sh` couldn't find `powershell.exe`, which it prints clearly if so), pass `--skip-windows` and follow the manual instructions it prints:

```bash
./install/install-wsl.sh --skip-windows
```

```powershell
# on Windows, inside the same repo (accessible from WSL at \\wsl.localhost\<distro>\...,
# or clone it separately on the Windows side)
powershell -NoProfile -ExecutionPolicy Bypass -File install/install-windows.ps1 -WithStartup
```

## Verify it works

1. **Restart Claude Code inside WSL**
2. **Send a message** (you'll see the status line at the bottom)
3. **Wait 15 seconds** for the Windows tray to poll the cache
4. **Look for the tray icon** in the bottom-right corner of Windows

Check the diagnostic log:
```bash
# WSL side
cat ~/.claude/usage-statusline.log
```

## Troubleshooting

### WSL writer can't find Windows home

The writer tries to auto-detect `USERPROFILE` by querying `cmd.exe`. If that fails:

```bash
# Set manually
export CLAUDE_USAGE_ICON_DIR="/mnt/c/Users/<your-username>/.claude"
```

Or cache it:
```bash
mkdir -p ~/.config/claude-usage-on-icon
echo "/mnt/c/Users/<your-username>/.claude" > ~/.config/claude-usage-on-icon/win_home
```

### Windows tray doesn't see the cache

Verify the paths match:
1. Check WSL log: `cat ~/.claude/usage-statusline.log`
2. Verify cache exists: `ls /mnt/c/Users/<username>/.claude/usage-cache.json`
3. On Windows, right-click tray → "Show details" and check the path

If paths differ, set `CLAUDE_USAGE_ICON_DIR` on both sides (WSL and Windows) to the same location.

### No status line in Claude Code (WSL)

1. Check WSL `settings.json`: `cat ~/.claude/settings.json | jq .statusLine`
2. Verify `statusline.py` exists: `ls ~/.claude/statusline.py`
3. Check the log: `cat ~/.claude/usage-statusline.log`

### Tray shows `?` (no data)

The cache might not be getting written. In WSL, run:
```bash
cat ~/.claude/usage-statusline.log
```

Look for `write FAILED` or `no rate_limits`. If it says `ok: cache written`, check the Windows tray path (might be reading elsewhere).

## Uninstall

Unlike install, `--uninstall` does **not** automatically drive the Windows side too — it only removes what's on the WSL half, so it can't accidentally reach across and remove a Windows tray you might be using independently.

### WSL side
```bash
./install/install-wsl.sh --uninstall
```

### Windows side
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install/install-windows.ps1 -Uninstall
```

## Advanced: custom Windows path

If your Windows home isn't at the default location (e.g., external drive), set:

```bash
export CLAUDE_USAGE_ICON_DIR="/mnt/d/My Drive/Users/yasin/.claude"
```

Both the WSL writer and Windows tray respect `CLAUDE_USAGE_ICON_DIR` (when set).
