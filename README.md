# quota-tray

**Plan-usage tray icon for Claude Code**

Show Claude Code's 5-hour and weekly plan usage persistently in your OS tray or menu bar, without opening the usage page.

## Core principle: no token, no network

Unlike existing tools that read your OAuth token and call undocumented APIs, quota-tray uses only:
- **Claude Code's official status line input** — already documented and available to your scripts
- **Local file reads only** — the cache file is read-only from the tray's perspective
- **No HTTP calls, no credentials, no private APIs**

See [how it works](docs/how-it-works.md) for the architecture.

---

## Quick start

**Choose your platform:**

### Windows (native)

```powershell
# Copy the installer and scripts
curl -o install-windows.ps1 https://github.com/<GITHUB_OWNER>/quota-tray/releases/download/v1.0.0/install-windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File install-windows.ps1 -WithStartup
```

Then:
1. Open Claude Code settings (⚙️ → settings.json)
2. Restart Claude Code
3. Send a message (status line will appear at the bottom)
4. Look for the tray icon in the bottom-right corner

### WSL (Ubuntu / Debian / other)

On WSL:
```bash
curl -o install-wsl.sh https://github.com/<GITHUB_OWNER>/quota-tray/releases/download/v1.0.0/install-wsl.sh
chmod +x install-wsl.sh
./install-wsl.sh
```

Then on Windows:
```powershell
# Run the Windows installer (same as above)
curl -o install-windows.ps1 https://github.com/<GITHUB_OWNER>/quota-tray/releases/download/v1.0.0/install-windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File install-windows.ps1 -WithStartup
```

The tray will appear on Windows and read from your WSL usage cache.

### Linux (GNOME / KDE / XFCE / Cinnamon)

```bash
curl -o install-linux.sh https://github.com/<GITHUB_OWNER>/quota-tray/releases/download/v1.0.0/install-linux.sh
chmod +x install-linux.sh
./install-linux.sh --autostart
```

Then restart Claude Code and send a message. The tray icon will appear in your notification area.

**Note:** GNOME requires the [AppIndicator extension](https://extensions.gnome.org/extension/615/appindicator-support/). KDE, XFCE, and Cinnamon work out of the box.

### macOS

```bash
curl -o install-macos.sh https://github.com/<GITHUB_OWNER>/quota-tray/releases/download/v1.0.0/install-macos.sh
chmod +x install-macos.sh
./install-macos.sh
```

Then:
1. Install [SwiftBar](https://swiftbar.app) or [BitBar](https://bitbar.com)
2. Restart Claude Code and send a message
3. The quota-tray plugin will appear in your menu bar

---

## What the icon means

| Icon | Meaning |
|---|---|
| Green circle with `%` | Good (< 70% used) |
| Amber circle with `%` | Caution (70–89% used) |
| Red circle with `%` | Critical (≥ 90% used) |
| Red circle with `!` | Over limit (≥ 100%) |
| Gray circle with `?` | No data (check status line is running) |
| Gray circle (faded) | Stale (no message in > 12 hours) |

**Hover** to see quick summary: `5h 31% @14:45 | wk 12% | 3m ago`

**Click** for full details: both windows, reset times, age, tray version, cache path.

---

## Limitations (by design)

1. **Updates only when Claude Code CLI responds.** The status line runs on every refresh, so usage from claude.ai web, the Claude desktop app, or other machines appears on your next CLI message.

2. **Desktop app and VS Code panel not supported.** The Claude desktop app (including its Code tab) and the VS Code extension panel don't run custom status lines. Only the CLI does.

3. **`rate_limits` appears after the first API response.** If you just signed in, send a message to see the first data point.

4. **Reset detection is eventual.** Once a window's `resets_at` time passes, the tray shows "reset" until Claude Code sends fresh data.

---

## Troubleshooting

**No custom status line?** → [Troubleshooting guide](docs/troubleshooting.md) (includes WSL checklist)

**Icon still shows `?`?** → Check `~/.claude/usage-statusline.log` for diagnostic messages

**Tray doesn't update?** → Ensure the tray version matches the writer version (see tray details)

---

## Uninstall

### Windows
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install-windows.ps1 -Uninstall
```

### WSL
```bash
./install-wsl.sh --uninstall
```

### Linux
```bash
./install-linux.sh --uninstall
```

### macOS
```bash
./install-macos.sh --uninstall
```

---

## How it works vs. other tools

| Aspect | quota-tray | Token-reading tools |
|---|---|---|
| **Reads tokens** | ❌ No | ✅ Yes (from .credentials.json) |
| **Makes HTTP calls** | ❌ No | ✅ Yes (calls /api/oauth/usage) |
| **Reads status line input** | ✅ Yes (official) | ❌ No |
| **Updates frequency** | Every CLI message | Periodic API polls |
| **Supported CLI platforms** | Windows / WSL / Linux / macOS | Often Windows-only |
| **Dependency risk** | Low (stdlib + UI frameworks) | Higher (HTTP client, token handling) |

Choose quota-tray if you prefer **transparency, simplicity, and minimal dependencies**. Token-reading tools may offer more frequent updates, but at the cost of credential access and unofficial API use.

---

## Support for API key and Bedrock sign-ins

API keys (Anthropic Bedrock, Vertex AI) and non-Pro/Max sign-ins **do not receive `rate_limits`** in the status line input, so quota-tray can't display them. Only **claude.ai Pro/Max** sign-ins are supported.

If you use an API key, consider:
- Running quota-tray for your Pro/Max claude.ai account on another machine
- Using the [official usage page](https://claude.ai/account/usage)

---

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for:
- The core principle (no tokens, no network, no undocumented APIs)
- Testing and regression-testing requirements
- Style and performance targets

---

## Security and privacy

- **Reads:** Claude Code's status line input and `usage-cache.json`
- **Writes:** `usage-cache.json`, diagnostic logs, and (on Linux) temporary icon files
- **Never:** network calls, credential access, registry modifications, elevation
- **Threat model:** Local process write attacks (acceptable; same-user trust boundary)

See [SECURITY.md](SECURITY.md) for details and how to report vulnerabilities.

---

## License

MIT © 2026 Ahmet Yasin Erten

---

## Disclaimer

**Unofficial.** Not affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic.

---

## Feedback

Found a bug? Have a feature idea? [Open an issue](https://github.com/<GITHUB_OWNER>/quota-tray/issues) and include:
- Your OS and Claude Code version (run `/status` in Claude Code)
- Where the CLI runs (Windows / WSL / Linux / macOS)
- The last few lines of `~/.claude/usage-statusline.log`
- (Optional) The contents of `~/.claude/usage-cache.json`

Thank you for using quota-tray!
