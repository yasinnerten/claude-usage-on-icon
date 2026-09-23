# Security and Privacy

## What claude-usage-on-icon reads and writes

**Reads:**
- stdin from Claude Code (the status line input, containing usage percentages and reset times)
- `~/.claude/usage-cache.json` (the cache written by the status line script)

**Writes:**
- `~/.claude/usage-cache.json` (usage data only: percentages, reset times, session ID)
- `~/.claude/usage-statusline.log` (diagnostic log: one line, overwritten each run)
- Installer backups of `settings.json` (if modifying the status line configuration)
- Autostart entry (Linux: `~/.config/autostart/claude-usage-on-icon.desktop`; optional, user-prompted)
- (Linux/macOS tray only) Temporary icons in `$XDG_RUNTIME_DIR/<project>/` (not included in cache)

## What claude-usage-on-icon does NOT do

- **No network calls** (no update checks, no telemetry, no API calls)
- **No credential access** (no `.credentials.json`, no keychains, no tokens)
- **No elevation or admin privileges** (no sudo, no UAC, no setuid)
- **No registry modifications** (Windows: only creates a plain-text autostart shortcut)

## Data in the cache

The cache contains:
- `written_at`: Unix timestamp (when the data was written)
- `rate_limits.five_hour.used_percentage`: 0–100
- `rate_limits.five_hour.resets_at`: Unix timestamp
- `rate_limits.seven_day.used_percentage`: 0–100
- `rate_limits.seven_day.resets_at`: Unix timestamp
- `session_id`: Session identifier or null

**NOT included:**
- Current working directory
- Transcript paths
- Model names
- Any other metadata from the status line input

## Setup-time disclosure

Every installer (`install-wsl.sh`, `install-windows.ps1`, `install-linux.sh`,
`install-macos.sh`) prints a banner **before making any change** listing the
exact files/folders it will read or write, and states plainly that it makes
no network calls and requests no elevation. This runs on every invocation,
not just `--dry-run`/`-WhatIf`, so what the installer is about to touch is
visible even when it's run non-interactively.

## Repository audit

The repository itself (not just the installed scripts) was audited for
accidentally committed sensitive data: real usernames, absolute paths from a
real machine, emails, tokens, or secrets. None were found — `tests/fixtures/`
contains only synthetic data (e.g. `session_id: "abc123def456"`), and
`.gitignore` excludes runtime artifacts (`usage-cache.json`,
`usage-statusline.log`, `settings.json.bak.*`, the cached `win_home` lookup)
as a defensive measure in case a test run ever points inside the checkout.

## Watermark / branding

The tray, the Linux tray, and the macOS plugin each show a static
"yasinnerten.com" line (a menu item or, on macOS, a `href=` link) crediting
the author. It is plain text/a plain link opened by the OS's own browser
launcher when clicked — it does not phone out on its own, embed a tracking
pixel, or run on a timer. It costs nothing extra in the "no network"
guarantee: nothing loads until you deliberately click it.

## Threat model

**In scope (acceptable):**
- Another local process writes a fake cache and misleads the tray display
  - *Mitigation:* Document as acceptable (same-user trust boundary)
  - *Future:* File permissions could restrict write access to the Claude user only

**Out of scope:**
- Remote attacks (no network = no remote vulnerability surface)
- Privilege escalation (no elevation requested)
- Credential theft (no credentials stored or accessed)

## Reporting vulnerabilities

If you discover a security issue, please report it privately via **GitHub private advisories** rather than opening a public issue.

1. Go to **Security** tab → **Advisories** → **Report a vulnerability**
2. Describe the issue, impact, and (optionally) a fix
3. Do not disclose the vulnerability publicly until a patch is released

Thank you for helping keep claude-usage-on-icon secure.
