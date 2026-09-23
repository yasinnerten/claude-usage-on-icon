# WSL installation and usage

Running Claude Code inside WSL and want the Windows tray? This guide covers both sides.

## Prerequisites

- Windows 10 or later with WSL2
- Ubuntu, Debian, or another Linux distro in WSL
- Python 3 (usually pre-installed in WSL)
- Claude Code CLI installed and running **inside WSL**

## Setup

### Step 1: Install the writer on WSL

Inside your WSL terminal:

```bash
curl -o install-wsl.sh https://github.com/<GITHUB_OWNER>/quota-tray/releases/download/v1.0.0/install-wsl.sh
chmod +x install-wsl.sh
./install-wsl.sh
```

This will:
1. Copy `statusline.py` to `~/.claude/` (inside WSL)
2. Merge the `statusLine` setting into `~/.claude/settings.json` (WSL side)
3. Print instructions for the Windows tray installation

The writer will auto-detect the Windows home directory and write the cache to `/mnt/c/Users/<username>/.claude/usage-cache.json` (accessible from Windows).

### Step 2: Install the tray on Windows

On the Windows side, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install-windows.ps1 -WithStartup
```

This installs the Windows tray, which reads from the cache the WSL writer creates.

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
export QUOTA_TRAY_DIR="/mnt/c/Users/<your-username>/.claude"
```

Or cache it:
```bash
mkdir -p ~/.config/quota-tray
echo "/mnt/c/Users/<your-username>/.claude" > ~/.config/quota-tray/win_home
```

### Windows tray doesn't see the cache

Verify the paths match:
1. Check WSL log: `cat ~/.claude/usage-statusline.log`
2. Verify cache exists: `ls /mnt/c/Users/<username>/.claude/usage-cache.json`
3. On Windows, right-click tray → "Show details" and check the path

If paths differ, set `QUOTA_TRAY_DIR` on both sides (WSL and Windows) to the same location.

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

### WSL side
```bash
./install-wsl.sh --uninstall
```

### Windows side
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install-windows.ps1 -Uninstall
```

## Advanced: custom Windows path

If your Windows home isn't at the default location (e.g., external drive), set:

```bash
export QUOTA_TRAY_DIR="/mnt/d/My Drive/Users/yasin/.claude"
```

Both the WSL writer and Windows tray respect `QUOTA_TRAY_DIR` (when set).
