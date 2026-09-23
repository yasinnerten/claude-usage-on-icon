# Windows installation and usage

## Prerequisites

- Windows 10 or later
- PowerShell 5.1 or later (built-in on Windows 10+)
- Claude Code CLI running natively on Windows

## Installation

```powershell
git clone https://github.com/yasinnerten/claude-usage-on-icon.git
cd claude-usage-on-icon
powershell -NoProfile -ExecutionPolicy Bypass -File install/install-windows.ps1 -WithStartup
```

This will:
1. Back up `%USERPROFILE%\.claude\settings.json`
2. Merge the `statusLine` setting into `settings.json`
3. Copy `statusline.ps1` and `tray-windows.ps1` to `%USERPROFILE%\.claude\`
4. Create a Startup folder shortcut to launch the tray on boot

### What if installation fails?

**Script blocked by execution policy:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install/install-windows.ps1
```

**Settings.json is invalid JSON:**
Edit `%USERPROFILE%\.claude\settings.json` manually to fix it, then rerun the installer.

**Different Claude folder (custom CLAUDE_CONFIG_DIR):**
The installer will detect it automatically. If you set a custom path, the installer will use it.

## Running

After installation, restart Claude Code:
1. Close all Claude Code windows
2. Open Claude Code again
3. Send a message (you'll see the status line at the bottom)
4. Look for the tray icon in the bottom-right corner

The tray starts automatically if you used `-WithStartup`. To start it manually:
```powershell
powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\tray-windows.ps1"
```

## Troubleshooting

### No status line at the bottom

1. Check `%USERPROFILE%\.claude\settings.json` has the `statusLine` setting
2. Verify the path points to your `statusline.ps1` file
3. Check `%USERPROFILE%\.claude\usage-statusline.log` for errors

### No tray icon

1. Verify `tray-windows.ps1` exists in `%USERPROFILE%\.claude\`
2. Try running it manually (see "Running" section above)
3. Check Windows Event Viewer for PowerShell errors

### Tray shows `?` (no data)

1. Ensure Claude Code is signed in with a Pro/Max plan
2. Send a message in Claude Code
3. Wait 15 seconds for the tray to poll the cache

### Tray on old value after message

The cache file path might be wrong. Right-click the tray icon and select "Show details" to see the path. Verify it matches your `settings.json` path.

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install/install-windows.ps1 -Uninstall
```

This will:
1. Remove the Startup shortcut (if created)
2. Remove `statusLine` from `settings.json` (preserves other settings)
3. Remove `statusline.ps1` and `tray-windows.ps1` from `%USERPROFILE%\.claude\`

The backup of `settings.json` is preserved.

## Advanced: WSL integration

If you run Claude Code **inside WSL** but want the Windows tray, see [WSL installation](wsl.md).

## Advanced: Custom cache location

Set the `CLAUDE_USAGE_ICON_DIR` environment variable to override the cache location:
```powershell
$env:CLAUDE_USAGE_ICON_DIR = "C:\Custom\Path"
powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\tray-windows.ps1"
```

The Python writer on WSL respects this same variable for finding the Windows cache.
