# statusline.ps1
# Version: 1.0.0
# Claude Code status line for Windows (Windows PowerShell 5.1 or PowerShell 7).
#
# What it does:
#   1. Reads the JSON that Claude Code pipes in on stdin.
#   2. Prints one status line: model, context %, 5-hour %, weekly %.
#   3. If the JSON contains `rate_limits`, saves that object to
#      <cache dir>\usage-cache.json for the tray script to read.
#
# What it does NOT do: no network calls, no credential access, no registry.
#
# Cache dir resolution (in order):
#   1. $env:CLAUDE_USAGE_ICON_DIR (explicit override)
#   2. $env:CLAUDE_CONFIG_DIR, else %USERPROFILE%\.claude
#
# Optional passthrough: set CLAUDE_USAGE_ICON_WRAP="<command>" to pipe the same
# stdin to that command and print its output instead of ours.

$ErrorActionPreference = 'Stop'
$StatuslineVersion = '1.0.0'
$Schema = 1

function Format-Reset([object]$epoch) {
    if ($null -eq $epoch) { return '' }
    try {
        $t = [DateTimeOffset]::FromUnixTimeSeconds([long]$epoch).LocalDateTime
        if ($t.Date -eq (Get-Date).Date) { return $t.ToString('HH:mm') }
        return $t.ToString('ddd HH:mm')
    } catch { return '' }
}

function Resolve-CacheDir {
    if ($env:CLAUDE_USAGE_ICON_DIR) { return $env:CLAUDE_USAGE_ICON_DIR }
    if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }
    return (Join-Path $env:USERPROFILE '.claude')
}

$rawInput = $null
try {
    $rawInput = $input | Out-String
    $data = $rawInput | ConvertFrom-Json
} catch {
    Write-Output 'statusline: could not parse input'
    exit 0
}

# ---- 1. Save rate_limits for the tray (only when Claude Code provided them)
$claudeDir = Resolve-CacheDir
if (-not (Test-Path -LiteralPath $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}
$cacheFile = Join-Path $claudeDir 'usage-cache.json'
$diagFile  = Join-Path $claudeDir 'usage-statusline.log'
$diag = 'no rate_limits in input (not a Pro/Max sign-in, or no response yet this session)'

if ($null -ne $data.rate_limits) {
    $tmp = "$cacheFile.$PID.tmp"
    try {
        $payload = [ordered]@{
            schema         = $Schema
            written_at     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            writer_version = $StatuslineVersion
            source         = 'windows'
            session_id     = $data.session_id
            rate_limits    = $data.rate_limits
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
    [System.IO.File]::WriteAllText($diagFile, ('{0}  v{1} (windows)  {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $StatuslineVersion, $diag))
} catch { }

# ---- 2. Optional passthrough: keep an existing custom status line
if ($env:CLAUDE_USAGE_ICON_WRAP) {
    try {
        $wrapped = $rawInput | & cmd.exe /c $env:CLAUDE_USAGE_ICON_WRAP
        Write-Output $wrapped
        exit 0
    } catch { }  # fall through to our own line if the wrapped command fails
}

# ---- 3. Print the status line (ASCII only, so it renders in any console code page)
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
