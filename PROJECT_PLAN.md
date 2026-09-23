# Project plan: Claude Code usage tray (open source, MIT)

> **Who this is for:** an agent (or developer) building the public GitHub repo.
> Everything needed is in this file: goals, rules, architecture, the data contract, per-platform specs, bugs already found and fixed, tests, CI, release, and the working reference code (Appendix A).
>
> **Status:** the Windows tray plus the WSL and Windows status line scripts already work on the author's machine (Windows 11 + WSL Ubuntu). The Linux-native and macOS parts are new work.

---

## 0. Decisions for the owner before publishing

| # | Decision | Recommendation |
|---|---|---|
| D1 | **Project name.** Anthropic's trademark guidelines restrict using "Claude"/"Anthropic" in a product's own name or logo. Plain-text descriptions such as "for Claude Code" are generally fine. | Use a neutral name plus a descriptive tagline, e.g. **`quota-tray`**, subtitled "Plan-usage tray icon for Claude Code". No Anthropic logo or Claude mark in icons. |
| D2 | **Copyright holder** in `LICENSE` | Confirm whether this is personal (`Yasin Erten`) or employer-owned. If it was written on work time or equipment, check the employer's IP policy first. |
| D3 | **GitHub account/org** that hosts the repo | Owner's choice |
| D4 | **macOS approach** (see §6.4) | v1: a SwiftBar/xbar plugin, which is a script and easy to review. v2: a native Swift menubar app. |

The agent building the repo should put placeholders (`<PROJECT_NAME>`, `<COPYRIGHT_HOLDER>`, `<GITHUB_OWNER>`) where D1–D3 apply and must not guess.

---

## 1. Goal

Show Claude Code's **5-hour** and **weekly** plan usage persistently in the OS tray or menu bar, without opening the usage page.

### Core principle (non-negotiable)

**No credentials, no network, no undocumented APIs.**

Most existing tray tools read the OAuth token in `~/.claude/.credentials.json` and call an undocumented endpoint (`/api/oauth/usage`). This project does neither. It uses the **officially documented status line input** only:

- Claude Code pipes JSON to the configured `statusLine` command on stdin.
- For claude.ai Pro/Max sign-ins, that JSON contains `rate_limits.five_hour` and `rate_limits.seven_day`, each with `used_percentage` (0–100) and `resets_at` (Unix epoch seconds).
- Docs: https://code.claude.com/docs/en/statusline

This is the project's selling point. It must be stated at the top of the README and kept true in every component. Any PR that adds network calls or credential reads is out of scope and should be rejected.

### Non-goals

- Reading `.credentials.json`, keychain entries or tokens
- Any HTTP call (including update checks in v1)
- Estimating usage from transcripts (`~/.claude/projects/*.jsonl`)
- Supporting API-key, Bedrock or Vertex sign-ins (they don't receive `rate_limits`; say so clearly in the README)
- Telemetry of any kind

### Known, documented limitations (put these in the README)

1. The tray updates only when Claude Code **CLI** gets a response (the status line only runs then). Usage from claude.ai web, the Claude desktop app or other machines shows up after the next CLI message.
2. The **Claude desktop app** (including its Code tab) and, as far as we could verify, the **VS Code extension panel** do not run custom status lines, so they don't feed the tray.
3. `rate_limits` appears only after the first API response in a session, and only for Pro/Max claude.ai sign-ins.
4. Claude Code drops a window from the JSON once its `resets_at` passes. The tray shows "reset" until fresh data arrives.

---

## 2. Architecture

Two components, joined by one JSON file:

```
┌──────────────────────┐    stdin JSON     ┌─────────────────────┐   writes   ┌──────────────────────┐   reads (poll)   ┌──────────────┐
│ Claude Code CLI      │ ───────────────▶ │ status line script  │ ─────────▶ │ usage-cache.json      │ ◀─────────────── │ tray / menu  │
│ (Windows/Linux/WSL/  │                   │ (prints one line    │            │ (in the Claude folder │                  │ bar app      │
│  macOS)              │ ◀─── stdout ───── │  + saves cache)     │ ─────────▶ │  the tray watches)    │                  │              │
└──────────────────────┘   status text     └─────────────────────┘  diag log  └──────────────────────┘                  └──────────────┘
```

- **Status line script (the "writer")**: runs per Claude Code refresh. It prints a one-line status, atomically writes `usage-cache.json` if `rate_limits` is present, and overwrites a one-line `usage-statusline.log` every run.
- **Tray app (the "reader")**: polls the cache every 15 s, draws an icon with the 5-hour %, colours it, and shows details on hover and click. It reads one file and writes nothing.

### Platform matrix

| Target | Claude Code runs in | Writer | Writer's settings file | Cache location | Tray |
|---|---|---|---|---|---|
| **Windows** | Windows (native CLI) | `statusline.ps1` (PowerShell 5.1+) | `%USERPROFILE%\.claude\settings.json` | `%USERPROFILE%\.claude\usage-cache.json` | `tray-windows.ps1` |
| **WSL → Windows tray** | WSL (Ubuntu etc.) | `statusline.py` (python3 stdlib) | **WSL** `~/.claude/settings.json` | Windows path via `/mnt/c/Users/<win-user>/.claude/usage-cache.json` | `tray-windows.ps1` (on Windows) |
| **Linux** | Linux | `statusline.py` | `~/.claude/settings.json` | `~/.claude/usage-cache.json` | `tray-linux.py` |
| **macOS** | macOS | `statusline.py` (or `statusline.sh`) | `~/.claude/settings.json` | `~/.claude/usage-cache.json` | SwiftBar/xbar plugin (v1), Swift app (v2) |

One Python writer covers Linux, WSL and macOS. The only difference is where it writes (§4).

---

## 3. Data contract: `usage-cache.json` (schema v1)

```json
{
  "schema": 1,
  "written_at": 1790163932,
  "writer_version": "1.0.0",
  "source": "windows | wsl | linux | macos",
  "session_id": "…or null",
  "rate_limits": {
    "five_hour": { "used_percentage": 31, "resets_at": 1790167531 },
    "seven_day": { "used_percentage": 12, "resets_at": 1790563931 }
  }
}
```

Rules:

- `rate_limits` is copied **verbatim** from Claude Code's input. Readers must tolerate extra keys (such as `spend_limit`) and missing windows.
- `written_at` is Unix seconds (UTC). Readers use it for "updated N min ago" and staleness.
- The writer only writes when `rate_limits` is present. It never writes an empty or partial file (temp file + atomic rename).
- File encoding is UTF-8 **without BOM**.
- Readers must reject files whose `schema` is greater than they know, with a clear message, and treat a missing `schema` as 1. The current reference code writes `version` instead of `schema`/`writer_version`; rename these during the port.

`usage-statusline.log` is one line, overwritten each run, never appended:
`2026-09-23 13:45:32  v1.0.0 (wsl)  ok: cache written` | `no rate_limits in input (…)` | `write FAILED: <message>`

---

## 4. Path resolution (writer and reader must agree)

**Claude config dir** = `$CLAUDE_CONFIG_DIR` if set, else `~/.claude` (Windows: `%USERPROFILE%\.claude`).

**Cache dir**, in order of precedence:

1. `QUOTA_TRAY_DIR` env var (rename to match D1). An explicit override.
2. **Auto-detect WSL** (writer only): if `/proc/sys/fs/binfmt_misc/WSLInterop` exists or `/proc/version` contains `microsoft`, resolve the Windows home with `wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')"` and use `<that>/.claude`. Cache the result in `~/.config/<project>/win_home` so `cmd.exe` isn't spawned on every status line refresh, because it's slow.
3. Otherwise, the Claude config dir.

The reference script hard-codes `/mnt/c/Users/localUser/.claude`. **This must be replaced by (1)+(2)**. Keep the env override so power users can pin it.

The tray shows the resolved cache path in its details view. This was essential for debugging (see §8).

---

## 5. Writer spec (status line)

Both `statusline.ps1` and `statusline.py` must:

1. Read all of stdin and parse JSON. On failure, print `statusline: could not parse input` and exit 0 (never a non-zero exit).
2. If `rate_limits` is present, write the cache via temp file in the **same directory**, then atomic rename:
   - PowerShell: `[IO.File]::Replace(tmp, dest, [NullString]::Value)` with fallback `[IO.File]::Copy(tmp, dest, $true)` (see bugs B1, B2). Use `Move` if dest doesn't exist.
   - Python: `os.replace`, with a plain-overwrite fallback on `OSError` (the Windows side may hold the file open over `/mnt/c`).
3. Always overwrite the one-line diag log.
4. Print **ASCII only**: `[Model] | ctx 12% | 5h 31% (resets 14:45) | week 12% (resets Mon 04:52)`. Show the reset time as `HH:mm` if today, else `ddd HH:mm`, in local time.
5. Be fast (target < 150 ms) and have no dependencies beyond PowerShell 5.1 or the Python 3.8+ stdlib.
6. Optional passthrough: env var `QUOTA_TRAY_WRAP="<other command>"`. If set, pipe the same stdin to that command and print its output instead of our line. This lets users keep an existing custom status line (a common ask). Stretch goal for v1.1.

---

## 6. Tray specs

### 6.1 Common behaviour (all platforms)

- Poll the cache every 15 s, **re-reading the content every tick** (don't gate on file mtime; see B3).
- The icon shows the 5-hour % as an integer (fall back to weekly if 5h is missing). `!` at ≥ 100, `?` if there's no data.
- Colour is the **worse** of 5h/weekly: green < 70, amber 70–89, red ≥ 90, grey if there's no data or `written_at` is older than 12 h. Make thresholds configurable.
- A window whose `resets_at` has passed shows as `reset` / 0% until new data arrives.
- Hover text: `v1.0.0 5h 31% @14:45 | wk 12% | 3m ago` (Windows limit is 63 characters; truncate).
- Click shows details: both windows with % and reset time, "updated N ago", tray version, **resolved cache path**, and a stale hint.
- Menu items: disabled version label · Show details · Refresh now · Open folder · Exit.
- Single instance. If an instance is already running, **don't exit silently** (see B4): either tell the old instance to quit and take over, or show a notification "already running (vX), use its menu to exit".
- It writes nothing, reads nothing but the cache, and makes no network calls.

### 6.2 Windows: `tray-windows.ps1`

Working reference code is in Appendix A. Stack: Windows PowerShell 5.1, WinForms `NotifyIcon`, GDI+ icon drawn at `SystemInformation.SmallIconSize`, `DestroyIcon` P/Invoke to avoid handle leaks, `Local\` named mutex, `Forms.Timer`.

Improvements for the repo:

- Single-instance takeover (B4).
- `install-windows.ps1`: copies files, runs `Unblock-File`, **merges** `statusLine` into settings.json (backup first, preserve other keys such as `hooks`), and optionally creates a Startup-folder shortcut. Must support `-WhatIf` and `-Uninstall`.
- Launch without a console flash: a `.vbs` launcher (`CreateObject("WScript.Shell").Run "powershell … -File …", 0`) or `conhost --headless`. Document the choice.
- Optional v2: a compiled single-exe C# version built with `csc.exe` from .NET Framework (no runtime install), published with a SHA256. Keep the `.ps1` as the auditable default.

### 6.3 Linux: `tray-linux.py`

- Stack: python3 + GTK via `gi` using **AyatanaAppIndicator3** (Ubuntu/Debian `gir1.2-ayatanaappindicator3-0.1`). Fall back to `AppIndicator3`. Draw the icon as SVG/PNG into `$XDG_RUNTIME_DIR/<project>/` (the only file it writes, and it's temporary; note this as the one exception to "writes nothing").
- GNOME needs the AppIndicator extension; say so in the README. KDE, XFCE and Cinnamon work out of the box.
- Autostart: `~/.config/autostart/<project>.desktop` via the installer.
- No third-party pip packages. If `gi` is missing, print the exact apt/dnf/pacman package names and exit 1.
- Wayland: AppIndicator works over StatusNotifierItem. Test on GNOME Wayland and KDE Plasma 6.

### 6.4 macOS

- **v1: SwiftBar/xbar plugin** `quota-tray.15s.sh` (or `.py`). It reads the cache and prints `31% | color=green` plus a dropdown with details. Pros: ~50 reviewable lines, no signing. Con: needs SwiftBar or xbar installed.
- **v2: native Swift menubar app** (`NSStatusItem`, `LSUIElement=YES`, polling timer, no network entitlements, sandboxed with read access to `~/.claude/usage-cache.json` via a security-scoped bookmark or unsandboxed with a clear statement). Distribute as source + a notarized build only if the owner has an Apple Developer ID. Otherwise build-from-source instructions.
- The writer is the same `statusline.py`. macOS ships `python3` only with the Xcode CLT, so also provide `statusline.sh` using `/usr/bin/plutil`, or `osascript -l JavaScript` for JSON, to avoid a Python dependency. Pick one and document it. Recommendation: ship a JXA version (`osascript -l JavaScript`, always present).

---

## 7. Repository layout

```
<project>/
├── LICENSE                       # MIT, <COPYRIGHT_HOLDER>, 2026
├── README.md                     # principle first, platform picker, limitations, FAQ
├── SECURITY.md                   # threat model + how to report
├── CONTRIBUTING.md               # "no network / no credentials" rule, style, tests
├── CHANGELOG.md                  # Keep a Changelog, SemVer
├── docs/
│   ├── how-it-works.md           # architecture diagram, data contract (§3)
│   ├── windows.md  wsl.md  linux.md  macos.md
│   └── troubleshooting.md        # the decision table from §8
├── writer/
│   ├── statusline.ps1            # Windows native
│   ├── statusline.py             # Linux / WSL / macOS (stdlib only)
│   └── statusline.jxa.js         # macOS without python (optional)
├── tray/
│   ├── windows/tray-windows.ps1  (+ launcher.vbs)
│   ├── linux/tray-linux.py       (+ quota-tray.desktop)
│   └── macos/swiftbar/quota-tray.15s.sh   (v2: macos/app/ Swift package)
├── install/
│   ├── install-windows.ps1       # -WhatIf, -Uninstall, -WithStartup
│   ├── install-wsl.sh            # WSL writer + prints the Windows tray install command
│   ├── install-linux.sh          # --dry-run, --uninstall, --autostart
│   └── install-macos.sh
├── tests/
│   ├── fixtures/*.json           # sample status line inputs (§9)
│   ├── test_statusline_py.py     # pytest
│   ├── statusline.Tests.ps1      # Pester 5
│   └── test_tray_logic.py / tray.Tests.ps1   # pure-function tests
└── .github/
    ├── workflows/ci.yml
    ├── workflows/release.yml
    ├── ISSUE_TEMPLATE/bug_report.yml   # asks for: OS, where CLI runs, diag log line, cache content
    └── dependabot.yml                  # actions only
```

Installers must be **idempotent**, **back up** `settings.json` before editing, **merge** rather than overwrite (keep `hooks` etc.), refuse to proceed if `settings.json` isn't valid JSON, and warn when a different `statusLine` already exists (offer the wrap option from §5.6).

---

## 8. Lessons learned (bugs already hit; make sure none come back)

| ID | Symptom | Cause | Fix / rule |
|---|---|---|---|
| B1 | Cache never updated after the first write (silently) | PowerShell turns `$null` passed to a .NET `string` param into `""`; `File.Replace(tmp, dest, "")` throws | Use `[NullString]::Value`. Never swallow write errors: log them to the diag file. |
| B2 | Possible replace failures on OneDrive-redirected or locked folders | `File.Replace` restrictions | Fall back to `File.Copy(tmp, dest, overwrite)` |
| B3 | Tray stuck on an old value although the file changed | Tray only re-read when `LastWriteTimeUtc` changed; `ReplaceFile` can keep the old file's metadata | Re-read content every tick (the file is tiny) |
| B4 | "New version doesn't take effect" | Single-instance mutex made the new copy **exit silently** while an old hidden copy kept running | Takeover or visible "already running" notice. Show the version in menu and tooltip. |
| B5 | Tray stuck at 42% forever | Manual test command wrote fake data (`resets_at` 2033) and the real writer never ran | Test fixtures must write to a **temp** dir, never the real cache. Installer offers `--selftest` that uses a temp dir. Tray shows `source`/`session_id` in details. |
| B6 | Windows settings edited but nothing happened | User runs Claude Code CLI **in WSL**, which reads WSL `~/.claude/settings.json` | The installer asks where the CLI runs. Troubleshooting doc leads with this. WSL auto-detect in the writer. |
| B7 | Expected updates from the desktop app / VS Code panel | Those surfaces don't run custom status lines | Document it (limitation 2) |
| B8 | Git Bash eats backslashes in `statusLine.command` on Windows | Claude Code runs status line commands via Git Bash when present | Always write forward-slash paths in settings.json |
| B9 | `NotifyIcon.Text` throws | .NET Framework limits it to 63 chars | Truncate |
| B10 | Script blocked from running | Mark-of-the-web / execution policy | `Unblock-File` in installer. `-ExecutionPolicy Bypass` per-process only (never change system policy). |

### Troubleshooting decision table (goes in `docs/troubleshooting.md`)

| What you see | Meaning | Action |
|---|---|---|
| No custom line at the bottom of Claude Code | Writer not running | Check which settings.json this CLI reads (WSL vs Windows), restart the CLI, run `/status` |
| Line shows `[Model] \| ctx …` but no `5h` | No `rate_limits` | Pro/Max claude.ai sign-in? At least one response sent? |
| Log says `write FAILED` | Permission/path issue | Check the cache dir exists and is writable; check `QUOTA_TRAY_DIR` |
| Log `ok`, tray old value | Tray reading another path, or an old tray instance | Compare the path in tray details with the log location; check the version in the tray menu |
| Cache has `resets_at` far in the future and `session_id: null` | Test data | Delete the cache, send a real message |

---

## 9. Testing

**Fixtures** (`tests/fixtures/`): `full.json` (both windows), `five_hour_only.json`, `no_rate_limits.json`, `with_spend_limit.json`, `null_context.json`, `garbage.txt`, `unicode_cwd.json` (non-ASCII path, e.g. `C:\Users\Jürgen`), `over_100.json`.

**Writer tests** (pytest + Pester; run each writer against every fixture into a temp dir):
- stdout matches expected line; exit code always 0
- cache written only when `rate_limits` present; content equals input `rate_limits`; valid UTF-8 without BOM
- second write replaces the first (regression B1)
- unwritable dir → diag says `write FAILED`, stdout still printed
- no leftover `*.tmp` files
- WSL path resolution: mock `/proc/version`, `cmd.exe` and `wslpath`
- runtime < 150 ms (soft check)

**Tray logic tests**: keep rendering-independent functions (`Get-Window`, `Format-Age`, `Format-When`, colour selection, tooltip truncation, stale detection, reset detection) pure and unit-tested. This is how the reference code was tested (extracting functions via the PowerShell AST).

**Static checks**: PSScriptAnalyzer, ruff, shellcheck, and a **"no network" guard** in CI that fails if sources contain `Invoke-WebRequest`, `Invoke-RestMethod`, `Net.WebClient`, `HttpClient`, `urllib`, `requests`, `socket`, `http.client`, `curl`, `wget`, `URLSession`, or the strings `.credentials`, `oauth`, `Keychain`, `security find-`. Allow-list false positives explicitly in the workflow.

**Manual QA matrix before each release**: Windows 11 (native CLI), Windows 10, WSL Ubuntu 24.04 → Windows tray, Ubuntu 24.04 GNOME (with extension), KDE Plasma 6, macOS 14/15 with SwiftBar. Checklist: fresh install, reinstall over existing, uninstall restores settings, tray updates within 15 s of a CLI response, reset rollover, stale grey after 12 h (fake `written_at`), second tray launch behaviour.

---

## 10. CI/CD

`ci.yml` (on PR and push):
- `windows-latest`: Pester for PS writer and tray logic, PSScriptAnalyzer, **PowerShell 5.1 and 7** both
- `ubuntu-latest`: pytest (Python 3.8 and 3.12), ruff, shellcheck, the no-network guard
- `macos-latest`: run the writer and SwiftBar plugin against fixtures (v2: `swift build`)
- Pin actions by commit SHA. `permissions: contents: read`.

`release.yml` (on tag `v*`):
- Zip per platform (`<project>-windows.zip`, `-linux.tar.gz`, `-macos.zip`) containing the scripts plus the installer
- `SHA256SUMS` file, and GitHub artifact attestations (`actions/attest-build-provenance`)
- Release notes from CHANGELOG
- No binaries in v1 (scripts only), which sidesteps code signing

Versioning: SemVer. One version for the whole repo, stamped into every script header (`# Version: x.y.z`), the tray menu and the diag log. A CI check verifies all stamps match the tag.

---

## 11. Security and privacy (goes in `SECURITY.md`)

- **Reads:** stdin from Claude Code (writer); `usage-cache.json` (tray).
- **Writes:** `usage-cache.json`, `usage-statusline.log`, installer backups of `settings.json`, autostart entry (opt-in). Linux tray: a temp icon in `$XDG_RUNTIME_DIR`.
- **Never:** network, credentials, registry writes (the Startup shortcut is a plain file), elevation/admin.
- The cache contains only usage percentages, reset times and the session ID. The status line input also contains `cwd` and `transcript_path`; **don't** copy those into the cache.
- Threat model: another local process could write a fake cache and mislead the display. That's acceptable (same-user trust boundary); document it.
- Vulnerability reporting via GitHub private advisories.

---

## 12. README outline

1. One-line pitch + screenshot/GIF per platform
2. **"No token, no network"**: 3 bullets explaining how it works (link to the official status line docs)
3. "Where does your Claude Code CLI run?" → Windows / WSL / Linux / macOS install sections (one command + manual steps each)
4. What the icon means (colours, `?`, `!`, grey)
5. Limitations (§1)
6. Troubleshooting (link)
7. Uninstall
8. Comparison with token-reading tools (neutral, factual; no naming and shaming)
9. Disclaimer: "Unofficial. Not affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic."
10. License (MIT)

---

## 13. Work plan (milestones)

| Milestone | Scope | Done when |
|---|---|---|
| **M0 Scaffold** | Repo, LICENSE (placeholders), README skeleton, CONTRIBUTING, SECURITY, issue template, CI with lint + no-network guard | CI green on an empty-ish repo |
| **M1 Windows + WSL (port the working code)** | Move Appendix A code into `writer/` and `tray/windows/`. Apply schema v1 (§3), path resolution (§4, remove the hard-coded user), B4 takeover, installers for Windows and WSL, Pester/pytest fixtures | Fresh Windows + WSL machine: install → message → tray updates. All B1–B10 regression tests pass. |
| **M2 Linux** | `tray-linux.py`, `install-linux.sh`, autostart | Works on GNOME (extension) + KDE |
| **M3 macOS v1** | SwiftBar plugin, macOS writer choice (python or JXA), `install-macos.sh` | Works on macOS 14/15 |
| **M4 Release 1.0.0** | Docs per platform, screenshots, CHANGELOG, `release.yml`, SHA256SUMS, attestations | Tag `v1.0.0` published |
| **M5 (later)** | Status line wrap/passthrough (§5.6), compiled Windows exe, native macOS app, configurable thresholds UI, i18n | — |

### Working flow for the building agent

1. Read this whole file. Create the repo scaffold (M0) with placeholders for D1–D3. Don't invent names or owners.
2. Port Appendix A into the layout **without behaviour changes first**, commit, then apply §3/§4/B4 changes as separate commits (reviewable history).
3. Write tests alongside each component. Every bug in §8 gets a regression test before the fix is considered done.
4. Build Linux, then macOS, each behind its own PR.
5. Keep the no-network guard green at all times. If a feature seems to need network or credentials, stop and ask the owner.
6. Hand the owner a checklist for decisions D1–D4, the manual QA matrix (§9), and the release steps before tagging `v1.0.0`.

---

## Appendix A: Working reference code (v1.2.0 / v1.3.0, verified on the author's machine)

Port this as the starting point. Known things to change are in §3, §4 and §8 (B4). The WSL writer hard-codes `/mnt/c/Users/localUser/.claude`, which must become auto-detected.

### A.1 `statusline-usage.ps1`

```powershell
# statusline-usage.ps1
# Version: 1.2.0
# Claude Code status line for Windows (Windows PowerShell 5.1 or PowerShell 7).
#
# What it does:
#   1. Reads the JSON that Claude Code pipes in on stdin.
#   2. Prints one status line: model, context %, 5-hour %, weekly %.
#   3. If the JSON contains `rate_limits`, saves that object to
#      <Claude config dir>\usage-cache.json for the tray script to read.
#
# What it does NOT do: no network calls, no credential access, no registry.
# Claude config dir = $env:CLAUDE_CONFIG_DIR if set, else %USERPROFILE%\.claude

$ErrorActionPreference = 'Stop'
$StatuslineVersion = '1.2.0'

function Format-Reset([object]$epoch) {
    if ($null -eq $epoch) { return '' }
    try {
        $t = [DateTimeOffset]::FromUnixTimeSeconds([long]$epoch).LocalDateTime
        if ($t.Date -eq (Get-Date).Date) { return $t.ToString('HH:mm') }
        return $t.ToString('ddd HH:mm')
    } catch { return '' }
}

try {
    $raw  = $input | Out-String
    $data = $raw | ConvertFrom-Json
} catch {
    Write-Output 'statusline: could not parse input'
    exit 0
}

# ---- 1. Save rate_limits for the tray (only when Claude Code provided them)
$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$cacheFile = Join-Path $claudeDir 'usage-cache.json'

$diagFile  = Join-Path $claudeDir 'usage-statusline.log'
$diag = 'no rate_limits in input (not a Pro/Max sign-in, or no response yet this session)'

if ($null -ne $data.rate_limits) {
    $tmp = "$cacheFile.$PID.tmp"
    try {
        $payload = [ordered]@{
            written_at  = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            version     = $StatuslineVersion
            session_id  = $data.session_id
            rate_limits = $data.rate_limits
        } | ConvertTo-Json -Depth 5

        # Write to a temp file, then swap it in, so the tray never reads a half-written file.
        [System.IO.File]::WriteAllText($tmp, $payload, (New-Object System.Text.UTF8Encoding($false)))
        if (-not (Test-Path -LiteralPath $cacheFile)) {
            [System.IO.File]::Move($tmp, $cacheFile)
        } else {
            try {
                # [NullString]::Value = a real null; plain $null would become "" and throw.
                [System.IO.File]::Replace($tmp, $cacheFile, [NullString]::Value)
            } catch {
                # Replace can fail on some folders (e.g. OneDrive-redirected) or while the
                # tray is reading; fall back to a plain overwrite.
                [System.IO.File]::Copy($tmp, $cacheFile, $true)
                Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
            }
        }
        $diag = 'ok: cache written'
    } catch {
        $diag = "write FAILED: $($_.Exception.Message)"
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }
}

# One-line diagnostic, overwritten on every run (never grows). Safe to delete.
try {
    [System.IO.File]::WriteAllText($diagFile, ('{0}  v{1}  {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $StatuslineVersion, $diag))
} catch { }

# ---- 2. Print the status line (ASCII only, so it renders in any console code page)
$parts = @()

$model = $data.model.display_name
if ($model) { $parts += "[$model]" }

$ctx = $data.context_window.used_percentage
if ($null -ne $ctx) { $parts += ('ctx {0:N0}%' -f [double]$ctx) }

$fh = $data.rate_limits.five_hour
if ($null -ne $fh -and $null -ne $fh.used_percentage) {
    $parts += ('5h {0:N0}% (resets {1})' -f [double]$fh.used_percentage, (Format-Reset $fh.resets_at))
}

$wk = $data.rate_limits.seven_day
if ($null -ne $wk -and $null -ne $wk.used_percentage) {
    $parts += ('week {0:N0}% (resets {1})' -f [double]$wk.used_percentage, (Format-Reset $wk.resets_at))
}

Write-Output ($parts -join ' | ')
```

### A.2 `usage-tray.ps1`

```powershell
# usage-tray.ps1
# Version: 1.2.0
# Windows tray icon for Claude Code plan usage (Windows PowerShell 5.1).
#
# Reads ONLY <Claude config dir>\usage-cache.json, which statusline-usage.ps1
# writes from the `rate_limits` data Claude Code already gives the status line.
#
# What it does NOT do: no network calls, no credential access, no registry,
# writes no files. Everything it knows comes from that one JSON file.
#
# Claude config dir = $env:CLAUDE_CONFIG_DIR if set, else %USERPROFILE%\.claude
#
# Run:  powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\usage-tray.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace ClaudeTray -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool DestroyIcon(System.IntPtr hIcon);
'@

$TrayVersion = '1.2.0'

# ---------------- settings ----------------
$PollSeconds = 15     # how often to re-check the file (local read only)
$StaleHours  = 12     # older than this -> grey icon
$WarnPct     = 70     # amber from here
$CritPct     = 90     # red from here

$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$cacheFile = Join-Path $claudeDir 'usage-cache.json'

# ---------------- single instance ----------------
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\ClaudeUsageTray', [ref]$created)
if (-not $created) { exit 0 }

# ---------------- helpers ----------------
function ConvertFrom-Epoch([object]$s) {
    if ($null -eq $s) { return $null }
    return [DateTimeOffset]::FromUnixTimeSeconds([long]$s).LocalDateTime
}

function Format-When([object]$dt) {
    if ($null -eq $dt) { return '?' }
    if ($dt.Date -eq (Get-Date).Date) { return $dt.ToString('HH:mm') }
    return $dt.ToString('ddd HH:mm')
}

function Format-Age([TimeSpan]$ts) {
    if ($ts.TotalMinutes -lt 1) { return 'just now' }
    if ($ts.TotalHours   -lt 1) { return ('{0}m ago' -f [int][math]::Floor($ts.TotalMinutes)) }
    if ($ts.TotalDays    -lt 1) { return ('{0}h ago' -f [int][math]::Floor($ts.TotalHours)) }
    return ('{0}d ago' -f [int][math]::Floor($ts.TotalDays))
}

# One window (five_hour / seven_day) -> @{ Pct; Reset; IsReset }
function Get-Window($obj) {
    if ($null -eq $obj -or $null -eq $obj.used_percentage) { return $null }
    $reset = ConvertFrom-Epoch $obj.resets_at
    $isReset = ($null -ne $reset -and (Get-Date) -ge $reset)
    $pct = if ($isReset) { 0 } else { [double]$obj.used_percentage }
    return @{ Pct = $pct; Reset = $reset; IsReset = $isReset }
}

function Read-Cache {
    if (-not (Test-Path -LiteralPath $cacheFile)) { return $null }
    for ($i = 0; $i -lt 3; $i++) {
        try { return ([System.IO.File]::ReadAllText($cacheFile) | ConvertFrom-Json) }
        catch { Start-Sleep -Milliseconds 150 }   # file being swapped; try again
    }
    return $null
}

function New-TrayIcon([string]$text, [System.Drawing.Color]$bg) {
    $size = [System.Windows.Forms.SystemInformation]::SmallIconSize
    $bmp  = New-Object System.Drawing.Bitmap($size.Width, $size.Height)
    $g    = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $brush = New-Object System.Drawing.SolidBrush($bg)
    $g.FillEllipse($brush, 0, 0, $size.Width - 1, $size.Height - 1)

    $fontPx = if ($text.Length -ge 3) { $size.Height * 0.42 } else { $size.Height * 0.58 }
    $font = New-Object System.Drawing.Font('Segoe UI', [single]$fontPx, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment     = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF(0, 0, $size.Width, $size.Height)
    $g.DrawString($text, $font, [System.Drawing.Brushes]::White, $rect, $sf)

    $hIcon = $bmp.GetHicon()
    $icon  = ([System.Drawing.Icon]::FromHandle($hIcon)).Clone()
    [void][ClaudeTray.Native]::DestroyIcon($hIcon)
    $sf.Dispose(); $font.Dispose(); $brush.Dispose(); $g.Dispose(); $bmp.Dispose()
    return $icon
}

# ---------------- state + rendering ----------------
$script:lastWrite = [DateTime]::MinValue
$script:cache     = $null
$script:details   = 'No data yet. Send one message in Claude Code (signed in with a Pro/Max plan).'

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true

function Update-Tray {
    # Re-read every tick (tiny local file). Don't rely on the file's timestamp:
    # File.Replace on Windows can keep the old file's metadata.
    $c = Read-Cache
    if ($null -ne $c) { $script:cache = $c }

    $c = $script:cache
    if ($null -eq $c -or $null -eq $c.rate_limits) {
        $icon = New-TrayIcon '?' ([System.Drawing.Color]::FromArgb(120, 120, 120))
        $tip  = "v$TrayVersion Claude usage: no data yet"
    } else {
        $fh  = Get-Window $c.rate_limits.five_hour
        $wk  = Get-Window $c.rate_limits.seven_day
        $age = (Get-Date).ToUniversalTime() - [DateTimeOffset]::FromUnixTimeSeconds([long]$c.written_at).UtcDateTime
        $stale = $age.TotalHours -ge $StaleHours

        $worst = 0
        foreach ($w in @($fh, $wk)) { if ($null -ne $w -and $w.Pct -gt $worst) { $worst = $w.Pct } }

        $color = if ($stale)                { [System.Drawing.Color]::FromArgb(120, 120, 120) }
                 elseif ($worst -ge $CritPct) { [System.Drawing.Color]::FromArgb(200, 40, 40) }
                 elseif ($worst -ge $WarnPct) { [System.Drawing.Color]::FromArgb(215, 140, 0) }
                 else                         { [System.Drawing.Color]::FromArgb(30, 140, 70) }

        # Icon number = 5-hour %, falling back to weekly if 5h is missing.
        $main = if ($null -ne $fh) { $fh } else { $wk }
        $num  = if ($null -eq $main) { '-' } elseif ($main.Pct -ge 100) { '!' } else { '{0:N0}' -f $main.Pct }
        $icon = New-TrayIcon $num $color

        $fhTxt = if ($null -eq $fh) { 'n/a' } elseif ($fh.IsReset) { 'reset' } else { '{0:N0}% @{1}' -f $fh.Pct, (Format-When $fh.Reset) }
        $wkTxt = if ($null -eq $wk) { 'n/a' } elseif ($wk.IsReset) { 'reset' } else { '{0:N0}%' -f $wk.Pct }
        $tip   = "v$TrayVersion 5h $fhTxt | wk $wkTxt | $(Format-Age $age)"

        $lines = @()
        if ($null -ne $fh) {
            if ($fh.IsReset) { $lines += "5-hour: window reset at $(Format-When $fh.Reset) (new % after your next message)" }
            else             { $lines += ('5-hour: {0:N1}% used, resets {1}' -f $fh.Pct, (Format-When $fh.Reset)) }
        }
        if ($null -ne $wk) {
            if ($wk.IsReset) { $lines += "Weekly: window reset at $(Format-When $wk.Reset)" }
            else             { $lines += ('Weekly: {0:N1}% used, resets {1}' -f $wk.Pct, (Format-When $wk.Reset)) }
        }
        $lines += "Updated $(Format-Age $age) (from Claude Code status line)"
        $lines += "Tray v$TrayVersion | file: $cacheFile"
        if ($stale) { $lines += 'Stale: open Claude Code and send a message to refresh.' }
        $script:details = $lines -join "`n"
    }

    # NotifyIcon.Text is limited to 63 characters on .NET Framework.
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
    $old = $notify.Icon
    $notify.Icon = $icon
    $notify.Text = $tip
    if ($null -ne $old) { $old.Dispose() }
}

function Show-Details {
    $notify.BalloonTipTitle = "Claude Code usage (v$TrayVersion)"
    $notify.BalloonTipText  = $script:details
    $notify.ShowBalloonTip(8000)
}

# ---------------- menu ----------------
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$verItem = $menu.Items.Add("Claude usage tray v$TrayVersion")
$verItem.Enabled = $false
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Show details', $null, { Show-Details })
[void]$menu.Items.Add('Refresh now',  $null, { $script:lastWrite = [DateTime]::MinValue; Update-Tray })
[void]$menu.Items.Add('Open .claude folder', $null, { Start-Process explorer.exe -ArgumentList "`"$claudeDir`"" })
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Exit', $null, {
    $timer.Stop()
    $notify.Visible = $false
    $notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$notify.ContextMenuStrip = $menu
$notify.add_MouseClick({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-Details }
})

# ---------------- run ----------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $PollSeconds * 1000
$timer.add_Tick({ try { Update-Tray } catch { } })
$timer.Start()

Update-Tray
[System.Windows.Forms.Application]::Run()

$mutex.ReleaseMutex()
$mutex.Dispose()
```

### A.3 `statusline-usage.py`

```python
#!/usr/bin/env python3
# statusline-usage.py
# Version: 1.3.0
# Claude Code status line for Claude Code running inside WSL.
#
# Same job as statusline-usage.ps1, but for the Linux side:
#   1. Reads the JSON Claude Code pipes in on stdin.
#   2. Prints one status line: model, context %, 5-hour %, weekly %.
#   3. If `rate_limits` is present, saves it to the WINDOWS Claude folder
#      (/mnt/c/Users/<you>/.claude/usage-cache.json) so the Windows tray can read it.
#
# No network, no credentials, standard library only (python3 ships with Ubuntu).
# Set WIN_CLAUDE_DIR if your Windows Claude folder is somewhere else.

import json, os, sys, tempfile, time
from datetime import datetime

VERSION = "1.3.0"
WIN_CLAUDE_DIR = os.environ.get("WIN_CLAUDE_DIR", "/mnt/c/Users/localUser/.claude")
CACHE = os.path.join(WIN_CLAUDE_DIR, "usage-cache.json")
DIAG = os.path.join(WIN_CLAUDE_DIR, "usage-statusline.log")


def fmt_reset(epoch):
    try:
        t = datetime.fromtimestamp(int(epoch))
    except Exception:
        return ""
    return t.strftime("%H:%M") if t.date() == datetime.now().date() else t.strftime("%a %H:%M")


try:
    data = json.load(sys.stdin)
except Exception:
    print("statusline: could not parse input")
    sys.exit(0)

rl = data.get("rate_limits")
diag = "no rate_limits in input (not a Pro/Max sign-in, or no response yet this session)"

if rl:
    payload = {
        "written_at": int(time.time()),
        "version": VERSION,
        "source": "wsl",
        "session_id": data.get("session_id"),
        "rate_limits": rl,
    }
    try:
        fd, tmp = tempfile.mkstemp(dir=WIN_CLAUDE_DIR, prefix="usage-cache.", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)
        try:
            os.replace(tmp, CACHE)          # atomic swap
        except OSError:
            # Windows side may briefly hold the file open; fall back to overwrite.
            with open(CACHE, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2)
            os.remove(tmp)
        diag = "ok: cache written"
    except Exception as e:
        diag = f"write FAILED: {e}"

try:
    with open(DIAG, "w", encoding="utf-8") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S}  v{VERSION} (wsl)  {diag}")
except Exception:
    pass

parts = []
model = (data.get("model") or {}).get("display_name")
if model:
    parts.append(f"[{model}]")
ctx = (data.get("context_window") or {}).get("used_percentage")
if ctx is not None:
    parts.append(f"ctx {float(ctx):.0f}%")
for key, label in (("five_hour", "5h"), ("seven_day", "week")):
    w = (rl or {}).get(key) or {}
    if w.get("used_percentage") is not None:
        parts.append(f"{label} {float(w['used_percentage']):.0f}% (resets {fmt_reset(w.get('resets_at'))})")
print(" | ".join(parts))
```

