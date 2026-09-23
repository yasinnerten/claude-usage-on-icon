# tray-windows.ps1
# Version: 1.0.0
# Windows tray icon for Claude Code plan usage (Windows PowerShell 5.1).
#
# Reads ONLY <cache dir>\usage-cache.json, which statusline.ps1 (or the WSL/Linux/
# macOS statusline.py) writes from the `rate_limits` data Claude Code already
# gives the status line.
#
# What it does NOT do: no network calls, no credential access, no registry,
# writes no files. Everything it knows comes from that one JSON file.
#
# Cache dir resolution (must match the writer):
#   1. $env:CLAUDE_USAGE_ICON_DIR (explicit override)
#   2. $env:CLAUDE_CONFIG_DIR, else %USERPROFILE%\.claude
#
# Run:  powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\tray-windows.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace ClaudeUsageIcon -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool DestroyIcon(System.IntPtr hIcon);
'@

$TrayVersion = '1.0.0'
$KnownSchema = 1

# ---------------- settings ----------------
$PollSeconds = 15     # how often to re-check the file (local read only)
$StaleHours  = 12     # older than this -> grey icon
$WarnPct     = 70     # amber from here
$CritPct     = 90     # red from here

function Resolve-CacheDir {
    if ($env:CLAUDE_USAGE_ICON_DIR) { return $env:CLAUDE_USAGE_ICON_DIR }
    if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }
    return (Join-Path $env:USERPROFILE '.claude')
}

$claudeDir = Resolve-CacheDir
$cacheFile = Join-Path $claudeDir 'usage-cache.json'

# ---------------- single instance (B4: never exit silently) ----------------
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\ClaudeUsageOnIconTray', [ref]$created)
if (-not $created) {
    [System.Windows.Forms.MessageBox]::Show(
        "Claude usage tray v$TrayVersion is already running.`n`nUse its tray icon menu to exit it first if you want to start a different version.",
        'Claude usage on icon',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    exit 0
}

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
        try {
            $c = [System.IO.File]::ReadAllText($cacheFile) | ConvertFrom-Json
            if ($null -ne $c.schema -and [int]$c.schema -gt $KnownSchema) {
                return @{ SchemaError = "cache schema $($c.schema) is newer than this tray (v$TrayVersion) understands; update the tray" }
            }
            return $c
        }
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
    [void][ClaudeUsageIcon.Native]::DestroyIcon($hIcon)
    $sf.Dispose(); $font.Dispose(); $brush.Dispose(); $g.Dispose(); $bmp.Dispose()
    return $icon
}

# ---------------- state + rendering ----------------
$script:cache   = $null
$script:details = 'No data yet. Send one message in Claude Code (signed in with a Pro/Max plan).'

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true

function Update-Tray {
    # Re-read every tick (tiny local file). Don't rely on the file's timestamp:
    # File.Replace on Windows can keep the old file's metadata.
    $c = Read-Cache
    if ($null -ne $c) { $script:cache = $c }

    $c = $script:cache
    if ($null -ne $c -and $null -ne $c.SchemaError) {
        $icon = New-TrayIcon '!' ([System.Drawing.Color]::FromArgb(160, 40, 160))
        $tip  = "v$TrayVersion $($c.SchemaError)"
        $script:details = $c.SchemaError
    }
    elseif ($null -eq $c -or $null -eq $c.rate_limits) {
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
        $lines += "Source: $($c.source) | schema $($c.schema) | writer v$($c.writer_version)"
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
    $notify.BalloonTipTitle = "Claude usage on icon (v$TrayVersion)"
    $notify.BalloonTipText  = $script:details
    $notify.ShowBalloonTip(8000)
}

# ---------------- menu ----------------
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$verItem = $menu.Items.Add("Claude usage on icon v$TrayVersion")
$verItem.Enabled = $false
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Show details', $null, { Show-Details })
[void]$menu.Items.Add('Refresh now',  $null, { Update-Tray })
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
