---
layout: default
title: Linux
---

# Linux installation and usage

## Prerequisites

- Ubuntu 20.04+, Debian 11+, or other modern Linux distro
- GTK 3 and AppIndicator support (`gir1.2-ayatanaappindicator3-0.1` on Debian/Ubuntu)
- Python 3.8+ (usually pre-installed)
- Claude Code CLI running natively on Linux

## Installation

```bash
git clone https://github.com/yasinnerten/claude-usage-on-icon.git
cd claude-usage-on-icon
./install/install-linux.sh --autostart
```

This will:
1. Check for required GTK packages
2. Copy `statusline.py` and `tray-linux.py` to `~/.claude/`
3. Merge the `statusLine` setting into `~/.claude/settings.json`
4. Create `~/.config/autostart/claude-usage-on-icon.desktop` for automatic startup

### Missing dependencies?

The installer will tell you which package to install. On Ubuntu/Debian:

```bash
sudo apt-get install gir1.2-ayatanaappindicator3-0.1
```

On Fedora/RHEL:
```bash
sudo dnf install libappindicator-gtk3
```

On Arch:
```bash
sudo pacman -S libappindicator-gtk3
```

## GNOME: Enable AppIndicator extension

The tray relies on AppIndicator. On GNOME, you may need to enable the extension:

1. Install: [AppIndicator Support](https://extensions.gnome.org/extension/615/appindicator-support/)
2. Refresh GNOME Extensions
3. Restart the tray app

KDE, XFCE, and Cinnamon support AppIndicator out of the box.

## Running

After installation, restart Claude Code:
1. Close Claude Code
2. Open Claude Code again
3. Send a message (you'll see the status line at the bottom)
4. The tray icon should appear in your notification area

If you used `--autostart`, the tray starts automatically on login.

To start it manually:
```bash
~/.claude/tray-linux.py
```

## Troubleshooting

### No AppIndicator extension (GNOME)

Install the [AppIndicator extension](https://extensions.gnome.org/extension/615/appindicator-support/) and enable it. Then restart the tray:

```bash
pkill tray-linux.py
~/.claude/tray-linux.py &
```

### No status line at the bottom

1. Check `~/.claude/settings.json` has `statusLine` set to `~/.claude/statusline.py`
2. Verify the Python path: `which python3`
3. Check `~/.claude/usage-statusline.log` for errors

### No tray icon

1. Try running manually: `~/.claude/tray-linux.py`
2. Check console output for GTK or AppIndicator errors
3. Verify `gir1.2-ayatanaappindicator3-0.1` is installed: `apt list --installed 2>/dev/null | grep appindicator`

### Tray shows `?` (no data)

1. Ensure Claude Code is signed in with a Pro/Max plan
2. Send a message in Claude Code
3. Wait 15 seconds for the tray to poll the cache

## Uninstall

```bash
./install/install-linux.sh --uninstall
```

This will:
1. Remove the autostart entry
2. Remove `statusLine` from `~/.claude/settings.json`
3. Remove the scripts from `~/.claude/`

## Advanced: custom cache location

Set `CLAUDE_USAGE_ICON_DIR` to use a different cache path:

```bash
CLAUDE_USAGE_ICON_DIR=/custom/path tray-linux.py
```

Both the writer and tray respect this environment variable.

## Advanced: running without autostart

Install without autostart:
```bash
./install/install-linux.sh
```

Then start manually each session:
```bash
~/.claude/tray-linux.py &
```

Or add to your shell profile:
```bash
# ~/.bashrc or ~/.zshrc
~/.claude/tray-linux.py &
```
