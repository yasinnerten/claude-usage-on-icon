# Security and Privacy

## What quota-tray reads and writes

**Reads:**
- stdin from Claude Code (the status line input, containing usage percentages and reset times)
- `~/.claude/usage-cache.json` (the cache written by the status line script)

**Writes:**
- `~/.claude/usage-cache.json` (usage data only: percentages, reset times, session ID)
- `~/.claude/usage-statusline.log` (diagnostic log: one line, overwritten each run)
- Installer backups of `settings.json` (if modifying the status line configuration)
- Autostart entry (Linux: `~/.config/autostart/quota-tray.desktop`; optional, user-prompted)
- (Linux/macOS tray only) Temporary icons in `$XDG_RUNTIME_DIR/<project>/` (not included in cache)

## What quota-tray does NOT do

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

Thank you for helping keep quota-tray secure.
