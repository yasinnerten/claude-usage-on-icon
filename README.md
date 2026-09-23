# claude-usage-on-icon

**Plan-usage tray icon for Claude Code**

Show Claude Code's 5-hour and weekly plan usage persistently in your OS tray or menu bar, without opening the usage page.

## Core principle: no token, no network

Unlike existing tools that read your OAuth token and call undocumented APIs, claude-usage-on-icon uses only:
- **Claude Code's official status line input** — already documented and available to your scripts
- **Local file reads only** — the cache file is read-only from the tray's perspective
- **No HTTP calls, no credentials, no private APIs**

See [how it works](docs/how-it-works.md) for the architecture.

---

## Quick start

> **Pre-release note:** no `v1.0.0` tag exists yet, so there's no downloadable release zip. Clone the repo for now — each installer resolves the writer/tray scripts relative to its own location, so it must be run from inside the checkout. Once tagged, a release zip per platform (installer + scripts already together) will let you skip the clone.

```bash
git clone https://github.com/yasinnerten/claude-usage-on-icon.git
cd claude-usage-on-icon
```

**Choose your platform:**

### Windows (native)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install/install-windows.ps1 -WithStartup
```

Then:
1. Restart Claude Code
2. Send a message (the status line will appear at the bottom)
3. Look for the tray icon in the bottom-right corner

### WSL (Ubuntu / Debian / other)

On WSL, inside the cloned repo:
```bash
./install/install-wsl.sh
```

Then on Windows, inside the same repo (accessible from Windows at `\\wsl.localhost\<distro>\...`, or clone it separately on the Windows side):
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install/install-windows.ps1 -WithStartup
```

The tray runs on Windows and reads the cache your WSL writer creates (the Windows home directory is auto-detected — no manual path needed).

### Linux (GNOME / KDE / XFCE / Cinnamon)

```bash
./install/install-linux.sh --autostart
```

Then restart Claude Code and send a message. The tray icon will appear in your notification area.

**Note:** GNOME requires the [AppIndicator extension](https://extensions.gnome.org/extension/615/appindicator-support/). KDE, XFCE, and Cinnamon work out of the box. Requires `gir1.2-ayatanaappindicator3-0.1` (or your distro's equivalent) — the installer tells you the exact package if it's missing.

### macOS

```bash
./install/install-macos.sh
```

Then:
1. Install [SwiftBar](https://swiftbar.app) or [BitBar](https://bitbar.com) if you haven't already
2. Refresh SwiftBar's plugins, restart Claude Code, and send a message
3. The claude-usage-on-icon plugin will appear in your menu bar

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
powershell -NoProfile -ExecutionPolicy Bypass -File install/install-windows.ps1 -Uninstall
```

### WSL
```bash
./install/install-wsl.sh --uninstall
```

### Linux
```bash
./install/install-linux.sh --uninstall
```

### macOS
```bash
./install/install-macos.sh --uninstall
```

---

## How it works vs. other tools

| Aspect | claude-usage-on-icon | Token-reading tools |
|---|---|---|
| **Reads tokens** | ❌ No | ✅ Yes (from .credentials.json) |
| **Makes HTTP calls** | ❌ No | ✅ Yes (calls /api/oauth/usage) |
| **Reads status line input** | ✅ Yes (official) | ❌ No |
| **Updates frequency** | Every CLI message | Periodic API polls |
| **Supported CLI platforms** | Windows / WSL / Linux / macOS | Often Windows-only |
| **Dependency risk** | Low (stdlib + UI frameworks) | Higher (HTTP client, token handling) |

Choose claude-usage-on-icon if you prefer **transparency, simplicity, and minimal dependencies**. Token-reading tools may offer more frequent updates, but at the cost of credential access and unofficial API use.

---

## Support for API key and Bedrock sign-ins

API keys (Anthropic Bedrock, Vertex AI) and non-Pro/Max sign-ins **do not receive `rate_limits`** in the status line input, so claude-usage-on-icon can't display them. Only **claude.ai Pro/Max** sign-ins are supported.

If you use an API key, consider:
- Running claude-usage-on-icon for your Pro/Max claude.ai account on another machine
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

Found a bug? Have a feature idea? [Open an issue](https://github.com/yasinnerten/claude-usage-on-icon/issues) and include:
- Your OS and Claude Code version (run `/status` in Claude Code)
- Where the CLI runs (Windows / WSL / Linux / macOS)
- The last few lines of `~/.claude/usage-statusline.log`
- (Optional) The contents of `~/.claude/usage-cache.json`

Thank you for using claude-usage-on-icon!
