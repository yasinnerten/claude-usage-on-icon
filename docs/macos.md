---
layout: default
title: macOS
---

# macOS installation and usage

## Prerequisites

- macOS 12 (Monterey) or later
- Python 3 (included with Xcode Command Line Tools, or via Homebrew)
- Claude Code CLI running natively on macOS
- **For v1:** SwiftBar or BitBar

## Installation (v1: SwiftBar plugin)

### Step 1: Install SwiftBar

Download and install [SwiftBar](https://swiftbar.app) (or [BitBar](https://bitbar.com), the older but compatible alternative).

### Step 2: Install claude-usage-on-icon

```bash
git clone https://github.com/yasinnerten/claude-usage-on-icon.git
cd claude-usage-on-icon
./install/install-macos.sh
```

This will:
1. Copy `statusline.py` to `~/.claude/`
2. Merge the `statusLine` setting into `~/.claude/settings.json`
3. Copy the SwiftBar plugin to `~/Library/Application Support/SwiftBar/Plugins/`

### Step 3: Launch

1. **Restart Claude Code** (close and reopen)
2. **Send a message** (you'll see the status line at the bottom)
3. **Open SwiftBar** and look for the claude-usage-on-icon icon in your menu bar

The plugin runs every 15 seconds to poll the cache.

## Running

The tray starts automatically when SwiftBar launches (usually on login). To start it manually:

```bash
open /Applications/SwiftBar.app
```

## Troubleshooting

### No status line in Claude Code

1. Check `~/.claude/settings.json` has `statusLine` pointing to `~/.claude/statusline.py`
2. Verify Python path: `which python3`
3. Check the log: `cat ~/.claude/usage-statusline.log`

### No menu bar icon

1. Verify SwiftBar is running: `ps aux | grep SwiftBar`
2. Check SwiftBar preferences → Plugins, ensure claude-usage-on-icon plugin is enabled
3. Verify plugin file exists: `ls ~/Library/Application\ Support/SwiftBar/Plugins/claude-usage-on-icon.*`

### Menu bar icon shows `?`

1. Ensure Claude Code is signed in with a Pro/Max plan
2. Send a message in Claude Code
3. SwiftBar checks the cache every 15 seconds

### SwiftBar shows red dot instead of icon

This usually means the plugin is crashing. Right-click the SwiftBar icon → "Plugin Console" and look for errors.

### Python not found

macOS doesn't ship Python with Xcode CLT by default anymore. Install via Homebrew:

```bash
brew install python3
```

Then verify: `which python3`

## Uninstall

```bash
./install/install-macos.sh --uninstall
```

This will:
1. Remove the plugin from SwiftBar
2. Remove `statusLine` from `~/.claude/settings.json`
3. Remove `statusline.py` from `~/.claude/`

## Alternative: osascript (no Python required)

macOS ships with JavaScript support via `osascript -l JavaScript`. An alternative `statusline.jxa.js` is available that doesn't require Python:

```bash
# Use this if you don't want to install Python
cp ~/.claude/statusline.jxa.js ~/.claude/statusline.js
# Update settings.json to use statusline.js instead
```

## Advanced (v2): Native Swift app

A native Swift menubar app is planned for v2. It will:
- Not require SwiftBar or BitBar
- Ship as a notarized `.app` bundle
- Have the same functionality as the plugin

For now, SwiftBar v1 is the recommended approach.

## Advanced: custom cache location

Set `CLAUDE_USAGE_ICON_DIR` to use a different cache path:

```bash
CLAUDE_USAGE_ICON_DIR=/custom/path statusline.py < /tmp/claude-status.json
```

Both the writer and plugin respect this variable.
