# Troubleshooting quota-tray

## Common issues and solutions

| What you see | Likely cause | Solution |
|---|---|---|
| **No custom line at the bottom of Claude Code** | Writer not running, or settings.json not configured | Check which `settings.json` your Claude Code CLI reads (WSL vs Windows), restart Claude Code, run `/status` in the editor |
| **Line shows `[Model] \| ctx …` but no `5h` or `week`** | No `rate_limits` data | Are you signed in with a Pro/Max plan? Have you sent at least one message this session? |
| **Tray shows `?` (no data)** | Cache doesn't exist or is empty | Check that the status line ran (see above), then wait 15 seconds for the tray to poll |
| **Tray shows old value after you sent a message** | Multiple possible causes | Compare the cache path shown in tray details with the path in the log; check the tray version in the menu |
| **Log says `write FAILED: Permission denied`** | Cache directory not writable | Ensure `~/.claude/` exists and is writable; check `QUOTA_TRAY_DIR` env var if set |
| **Cache has `resets_at` far in the future (e.g., year 2033) and `session_id: null`** | Test data left in cache | Delete `~/.claude/usage-cache.json` and send a real message |

## Decision table: where is Claude Code running?

This is the #1 source of confusion, especially on Windows + WSL.

```
┌─────────────────────────────────────────────────────────────────┐
│ Windows Native vs WSL: which settings.json does your CLI read?  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Run this command in Claude Code and look at the path:           │
│                                                                 │
│   /status                                                       │
│                                                                 │
│ If you see C:\Users\<name>\.claude or %USERPROFILE%\.claude:   │
│   → You're running the WINDOWS CLI (native)                    │
│   → Install writer and tray on WINDOWS side                    │
│   → Run: install-windows.ps1                                   │
│                                                                 │
│ If you see /home/<name>/.claude or ~/. claude:                 │
│   → You're running the CLI inside WSL (Ubuntu/Debian/etc)      │
│   → Install writer on WSL side, tray on WINDOWS side           │
│   → Run: install-wsl.sh (on WSL)                               │
│   → Then: install-windows.ps1 (on Windows)                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Platform-specific checklist

### Windows (native)

- [ ] Claude Code is running as a Windows (native) CLI
- [ ] `settings.json` is in `%USERPROFILE%\.claude\`
- [ ] `install-windows.ps1` was run (not `install-wsl.sh`)
- [ ] PowerShell execution policy allows running scripts:
  - Try running the tray manually: `powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\tray-windows.ps1"`
  - If it works, the policy is fine; if not, add the script to Unblock-File or adjust policy
- [ ] Check the diagnostic log: `type %USERPROFILE%\.claude\usage-statusline.log`

### WSL (Ubuntu / Debian / other)

- [ ] Claude Code CLI is running **inside WSL** (not Windows)
- [ ] `~/.claude/` exists inside WSL
- [ ] `install-wsl.sh` was run (installs the writer in WSL)
- [ ] `install-windows.ps1` was also run (installs the Windows tray)
- [ ] WSL can reach the Windows home directory:
  - Run: `ls /mnt/c/Users/$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/.claude`
  - If this fails, the auto-detect won't work; set `QUOTA_TRAY_DIR` manually
- [ ] Check the WSL diagnostic log: `cat ~/.claude/usage-statusline.log`
- [ ] Check the Windows tray version and cache path (right-click tray icon → Show details)

### Linux (GTK + AppIndicator)

- [ ] Claude Code CLI is running on Linux (native)
- [ ] `~/.claude/` exists and is writable
- [ ] `install-linux.sh` was run
- [ ] Required package installed: `gir1.2-ayatanaappindicator3-0.1` (Debian/Ubuntu) or equivalent for your distro
- [ ] For GNOME: AppIndicator extension is enabled
- [ ] Autostart is enabled (optional):
  - Check: `cat ~/.config/autostart/quota-tray.desktop`
  - If not present, run: `install-linux.sh --autostart`
- [ ] Check the diagnostic log: `cat ~/.claude/usage-statusline.log`

### macOS

- [ ] Claude Code CLI is running on macOS
- [ ] `~/.claude/` exists and is writable
- [ ] **v1 (SwiftBar/xbar plugin):**
  - [ ] SwiftBar or xbar is installed
  - [ ] Plugin is copied to the plugins directory
  - [ ] Plugin runs every 15 seconds (check SwiftBar/xbar menu)
  - [ ] Check the diagnostic log: `cat ~/.claude/usage-statusline.log`
- [ ] **v2 (native app):**
  - [ ] App is installed and running
  - [ ] App has read permission for `~/.claude/`
  - [ ] Check Console.app for any errors

## Enabling debug output

For more detailed troubleshooting, check:

1. **Status line log** (all platforms):
   ```bash
   # Windows
   type %USERPROFILE%\.claude\usage-statusline.log
   
   # Linux / macOS / WSL
   cat ~/.claude/usage-statusline.log
   ```

2. **Cache contents:**
   ```bash
   # All platforms
   cat ~/.claude/usage-cache.json  # or use jq for pretty-print
   ```

3. **Tray debug** (platform-specific):
   - Windows: Check Event Viewer for PowerShell errors, or run tray manually to see output
   - Linux: Check AppIndicator/StatusNotifier logs in `journalctl -f`
   - macOS: Check Console.app for plugin or app errors

## Still stuck?

Open an issue with:
- Your OS and Claude Code version
- Where your CLI runs (output of `/status`)
- The diagnostic log line
- The cache file contents (if it exists)
- A description of what you expected vs. what you see

We're here to help!
