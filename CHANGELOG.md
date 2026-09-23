# Changelog

All notable changes to claude-usage-on-icon will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Windows + WSL (M1) — implemented and live-validated:**
  - `writer/statusline.py`: cross-platform writer (Linux/WSL/macOS). Auto-detects WSL via
    `/proc/version` / `WSLInterop`, resolves the Windows home directory through `cmd.exe` +
    `wslpath` and caches it under `~/.config/claude-usage-on-icon/win_home` so the slow
    `cmd.exe` call only happens once. Writes schema v1 cache atomically (temp file + `os.replace`,
    with a copy-then-remove fallback). Optional `CLAUDE_USAGE_ICON_WRAP` passthrough.
  - `writer/statusline.ps1`: Windows-native writer, same schema and atomic-write behavior
    (`[IO.File]::Replace` with `[NullString]::Value`, falling back to `Copy` — regression
    guard for the historical "second write throws" bug).
  - `tray/windows/tray-windows.ps1`: WinForms `NotifyIcon` tray. Adds a schema-version guard
    (refuses to misrender a future cache format) and single-instance takeover: a second
    instance shows a dialog naming the running version instead of exiting silently.
  - `install/install-wsl.sh` and `install/install-windows.ps1`: idempotent installers that
    back up `settings.json`, merge the `statusLine` command in place (preserving `hooks` and
    every other key), warn instead of clobbering an unrelated existing `statusLine`, and
    support `--dry-run`/`-WhatIf`, `--uninstall`/`-Uninstall`, `--force`/`-Force`. The Windows
    installer also supports `-WithStartup` (creates a `launcher.vbs` + Startup-folder shortcut,
    so the tray starts on login with no console flash) and `-TrayOnly` (for WSL/Linux/macOS
    setups where only the tray runs on Windows).
  - **Validated live** on the author's Windows 11 + WSL Ubuntu machine: the real Claude Code
    CLI session picked up the new writer after installation and wrote live schema-v1 usage
    data to the real Windows cache; the real tray read it and rendered correctly; the
    duplicate-instance dialog and the atomic double-write path were both exercised for real.
- **Linux (M2) — implemented, syntax-checked, not yet run on a real display:**
  - `tray/linux/tray-linux.py`: GTK 3 + AyatanaAppIndicator3 (falls back to AppIndicator3),
    same schema/coloring/staleness rules as the Windows tray, SVG icon rendered into
    `$XDG_RUNTIME_DIR`.
  - `install/install-linux.sh`: checks for the GTK bindings and prints the exact
    apt/dnf/pacman package name if missing, same settings-merge and flag set as the WSL
    installer, plus `--autostart` (writes a `~/.config/autostart/*.desktop` entry).
  - Not validated against a real GNOME/KDE session in this environment (no GTK/display
    available); the settings-merge logic is shared with the already-validated WSL installer.
- **macOS (M3) — implemented, not yet run on real macOS:**
  - `tray/macos/swiftbar/claude-usage.15s.sh`: SwiftBar/xbar plugin (Python 3, no extra
    dependencies), reuses the same cache-reading and formatting logic as the Linux tray.
  - `install/install-macos.sh`: same settings-merge/flag set, copies the plugin into
    SwiftBar's plugin folder.
  - The macOS writer is `writer/statusline.py` (already cross-platform; detects `darwin` via
    `sys.platform`). `writer/statusline.jxa.js` remains a documented, unimplemented stretch
    goal for users who don't want a Python dependency.
- Test fixtures (`tests/fixtures/`) covering the full data, missing windows, garbage input,
  extra keys (`spend_limit`), over-100%, and non-ASCII-path scenarios from the test plan.
- Documentation: README, CONTRIBUTING, SECURITY, `docs/how-it-works.md`,
  `docs/troubleshooting.md`, and a per-platform guide for Windows, WSL, Linux, and macOS.
- CI workflow with lint, test, and a no-network security guard.

### Fixed
- `install-windows.ps1`: `Merge-StatusLine`'s informational `Write-Output` calls were being
  swallowed by `$ok = Merge-StatusLine ...` (PowerShell assignment captures the whole
  pipeline, not just `return`), so status messages never printed. Switched those calls to
  `Write-Host`. Caught by testing the real installer against the machine's real settings.json.
- `install-windows.ps1`: the Startup-shortcut launcher (`launcher.vbs`) was built via a
  PowerShell `-replace` that doubled every backslash in the path. Windows tolerated it, but
  the fix removes the unnecessary regex replace and uses the already-resolved path directly.

### Known gaps before a v1.0.0 tag
- No release zips yet — the Quick Start uses `git clone` since the installers resolve
  `writer/`/`tray/` relative to their own location (matching how the eventual release zip
  will bundle them together).
- Linux and macOS are implemented but not run on a real desktop/display in this environment.
- `-Force`/`--force` and `-TrayOnly` flags exist but aren't yet documented per-platform.

## Future versions

- **1.1.0:** Status line wrap option is already implemented (`CLAUDE_USAGE_ICON_WRAP`); needs docs.
- **1.2.0:** Configurable color thresholds (UI or settings)
- **2.0.0:** Native Swift macOS app, compiled C# Windows exe
