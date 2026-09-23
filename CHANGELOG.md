# Changelog

All notable changes to claude-usage-on-icon will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Usage alerts.** "Set alert threshold..." in the tray/menu (e.g. 80) fires
  one notification the first time either window reaches it, and re-arms when
  that window resets; 0 turns it off. Shared `alert-config.json`
  (`{"threshold_pct": 80}`) on all platforms. Windows: balloon + InputBox;
  Linux: `notify-send` (skipped quietly if absent) + GTK spin-button dialog;
  macOS: `osascript` notification, with "already alerted" persisted to
  `alert-state.json` keyed by `resets_at` (the script re-runs fresh each poll,
  so it can't keep a flag in memory). Alert state machine tested on Linux and
  macOS logic (fires once, no repeats, re-fires after reset) and the Windows
  tray was run live with a crossing threshold. **Not verified:** the macOS
  "Set alert threshold..." dialog and SwiftBar's handling of the quoted plugin
  path in `bash=`, the Linux GTK dialog, and notify-send delivery (no
  macOS/GTK available here).
- **Legible, visibly animated tray icon (Windows/Linux).** Rendered the icon to
  PNG and looked at it at true tray size: the thin progress ring was
  indistinguishable noise, wasted margin shrank the badge, and the drop shadow
  smeared the digits - which is why it read as unreadable and "not animated".
  Now: usage is a solid pie wedge, the badge is near full-bleed, no shadow, and
  font size is fit to the text width (a fixed height ratio clipped "31" to "3").
  Windows also calls `SetProcessDPIAware()`: at 150% scaling `SmallIconSize`
  otherwise lies with 16x16 and Windows blurrily upscales, whereas the real
  size is 24x24. Verified by rendering easing frames (21% -> 44% -> 53%) that
  visibly differ.
- **One-command WSL+Windows install; a real `.exe` instead of a PowerShell
  command line.** `install-wsl.sh` now automatically drives
  `install-windows.ps1` on the Windows side too, via the same
  `cmd.exe`/`powershell.exe` interop the writer already uses to
  auto-detect the Windows home directory (`wslpath -w` for the UNC path,
  a few candidate `powershell.exe` locations checked in order). No more
  "now switch to a Windows terminal and run this command" step - one
  command from WSL does both halves. `--skip-windows` opts out for anyone
  who wants to do the Windows half separately, and a missing
  `powershell.exe` degrades to printing the manual instructions instead of
  failing.

  Separately, `install-windows.ps1` now compiles `ClaudeUsageOnIconTray.exe`
  from a small, auditable C# source (`install/ClaudeUsageOnIconTray.cs`,
  plain text, committed to this repo) using `csc.exe` - the C# compiler
  already built into every Windows 10/11 install as part of .NET Framework.
  No download, no binary in the repo, no extra runtime. That `.exe` replaces
  the previous `launcher.vbs`+`wscript.exe` indirection as the Startup-folder
  shortcut's target and as what "start the tray manually" instructions point
  to - the whole point being that starting or troubleshooting the tray is
  now a double-click, never a PowerShell command with `-ExecutionPolicy
  Bypass` in it. If `csc.exe` isn't found, the installer falls back to the
  previous PowerShell-only launcher automatically rather than failing.

  Both pieces were tested for real: the stub-based WSL orchestration tests
  (dry-run, `--force`, `--skip-windows`, a simulated Windows-side failure),
  the real compile via `csc.exe` and a real run of the resulting `.exe`
  (including its error path - a MessageBox, not a silent failure), and
  then the whole one-command flow for real against the live production
  Windows+WSL setup on the author's machine.
- **(Superseded by the pie-fill icon above.) Animated progress-ring icon on Windows and Linux:** the flat colored
  badge is now a badge + an animated progress ring around it, swept
  clockwise from 12 o'clock proportional to usage, with the percentage
  still as the center number. The ring eases toward a new value over
  ~1-1.5s (exponential ease-out) instead of jumping, and pulses (breathing
  brightness/thickness) while critical (>=90%) or over the limit. Driven by
  a separate ~12fps redraw timer that does no file I/O, so it's cheap; the
  existing 15s poll timer still owns reading the cache.
- **macOS: pie-glyph approximation, not true animation.** SwiftBar re-runs
  the plugin script on its refresh interval rather than staying resident,
  so there's no process to animate between polls. The plugin now shows a
  discrete pie glyph (○ ◔ ◑ ◕ ●) next to the percentage, colored the same as
  the level, updating each 15s refresh - the closest honest equivalent
  given the plugin model, documented as such rather than overclaimed.
- **Clicking the version menu item now opens the repo.** "Claude usage on
  icon v1.0.0" was previously a disabled label on Windows and Linux; it's
  now clickable and opens
  https://github.com/yasinnerten/claude-usage-on-icon (`Start-Process` /
  `xdg-open` / SwiftBar `href=` respectively).
- **Account name: investigated and dropped.** Captured the real, live
  status line JSON Claude Code sends (temporarily, then restored the
  original config) to check for an account/email field. There isn't one -
  the documented fields are session_id, session_name, model, workspace,
  cost, context_window, rate_limits, etc. Showing a real account identity
  would require reading `.credentials.json` or an undocumented API, both
  out of scope per this project's core principle. Decided with the owner
  not to substitute something else in its place (e.g. session_name or the
  OS username) rather than imply an account identity this project doesn't
  have.
- **Repository sensitive-data audit:** searched every tracked file for real
  usernames, absolute paths from a real machine, emails, tokens, or secrets.
  None found. Added defensive `.gitignore` entries for this project's own
  runtime artifacts (`usage-cache.json`, `usage-statusline.log`,
  `settings.json.bak.*`, the cached `win_home` lookup) in case a test run
  ever points inside the checkout. See `SECURITY.md` for the full writeup.
- **Setup-time permission disclosure:** every installer now prints a banner,
  before touching anything, listing the exact files/folders it will read or
  write and restating the no-network/no-elevation guarantee. Runs on every
  invocation, not just `--dry-run`/`-WhatIf`.
- **Tray UI polish and watermark:** the Windows tray, Linux tray, and macOS
  SwiftBar plugin all got a subtle gradient + border on the icon (was a flat
  fill), and a "yasinnerten.com" credit — a menu item on Windows/Linux that
  opens the browser, an `href=` link on macOS. Static text/link only; it does
  not run on a timer or phone out on its own.
- **GitHub Pages site built from `docs/`:** `docs/_config.yml` (Jekyll,
  `jekyll-theme-cayman` theme, `jekyll-relative-links` plugin so the existing
  relative `.md` links between guides resolve correctly) and `docs/index.md`
  as the landing page. `.github/workflows/pages.yml` builds and deploys it on
  every push to `docs/**`. **Requires a one-time manual step:** repo Settings
  → Pages → Build and deployment → Source: "GitHub Actions" (cannot be set
  via a commit).
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
- **Testing mistake, corrected immediately:** while validating the new
  `.exe`-based Startup shortcut against an "isolated" test directory (via
  `CLAUDE_CONFIG_DIR`), the Startup-folder shortcut itself isn't
  isolatable that way - there's exactly one per-user Startup folder -
  so the test run overwrote the real production shortcut to point at a
  temp path, and a subsequent cleanup step then deleted it outright.
  Caught immediately after by checking the real shortcut's target;
  fixed by re-running the real installer for real (no override) to
  restore it, this time pointing at the newly-compiled real `.exe`, and
  verified the tray was running again before moving on. Noted here as a
  reminder that a global, per-user resource like this can't be sandboxed
  by an env var the way a cache directory can.
- `.github/workflows/ci.yml`: the version-stamp check's `grep`/`sed` only
  matched `# Version: ` (Python/PowerShell/shell comment style), so it
  silently ignored the new `.cs` file's `// Version: ` line - and, once
  fixed to match both, correctly caught a real pre-existing gap:
  `statusline.jxa.js` still carries its M0 placeholder
  ("to be filled in by M1") since it was never implemented. Extended the
  pattern to match either comment style, and excluded that one
  intentionally-still-a-placeholder file by name with a comment
  explaining why, rather than papering over it with a fake version.
- `tray-windows.ps1`: `New-TrayIcon`'s ring-drawing code threw
  `[System.Object[]] does not contain a method named 'op_Multiply'` (then,
  after a first fix, `op_Subtraction`) at runtime. Cause: writing
  arithmetic like `$w - 2 * $margin` directly inside a
  `New-Object Type($a, $b, $c)`-style argument list - PowerShell's parser
  mishandles mixed operators there. Fixed by precomputing every such
  expression into its own variable before the constructor call. Caught by
  actually invoking `New-TrayIcon` for all five icon states (normal,
  critical/pulsing, over-limit, no-data, 0%) rather than assuming the
  syntax check (which passed) meant the code worked at runtime.
- `tray-linux.py`: splitting icon rendering into a separate animation tick
  (for the same reason as the Windows change above) initially left the
  tray tooltip hardcoded to a static "claude-usage-on-icon v1.0.0" instead
  of the useful "5h 31% | wk 12% | 3m ago" summary the 15s poll computes.
  Fixed by storing that string on `self.tooltip` and having the animation
  tick read it back, instead of composing its own.
- `install-windows.ps1`: `Merge-StatusLine`'s informational `Write-Output` calls were being
  swallowed by `$ok = Merge-StatusLine ...` (PowerShell assignment captures the whole
  pipeline, not just `return`), so status messages never printed. Switched those calls to
  `Write-Host`. Caught by testing the real installer against the machine's real settings.json.
- `install-windows.ps1`: the Startup-shortcut launcher (`launcher.vbs`) was built via a
  PowerShell `-replace` that doubled every backslash in the path. Windows tolerated it, but
  the fix removes the unnecessary regex replace and uses the already-resolved path directly.
- `.github/workflows/ci.yml`: the `actions/checkout@<sha>` and `actions/setup-python@<sha>`
  pins were **fabricated, non-existent commit SHAs** (confirmed via the GitHub API - a fetch
  against the checkout SHA returned 422). These would have made CI fail outright on the very
  first run. Replaced with verified real SHAs for the actual `v4`/`v5` tags. A lesson for any
  future SHA-pinning: verify against the API, don't guess a SHA that merely looks plausible.
- `.github/workflows/ci.yml`: `- name: Security: no-network guard` is invalid YAML (an
  unquoted second colon in a scalar), which would have failed to parse. Quoted the string.
  Caught by actually parsing every workflow/config YAML file with a real parser instead of
  eyeballing it - the same check that later caught the fabricated SHAs.
- `install-macos.sh`: the new disclosure banner's own text ("no ... Keychain access") tripped
  the no-network guard's `Keychain` pattern - a false positive from the guard reading its own
  negation. Reworded to "password-manager access" rather than special-casing the line.

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
