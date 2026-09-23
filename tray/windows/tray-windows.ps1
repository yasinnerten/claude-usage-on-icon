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

function New-TrayIcon {
    param(
        [string]$text,
        [System.Drawing.Color]$bg,
        [double]$sweepPct = -1,   # -1 = no progress ring (e.g. "?" state); 0..100 draws the arc
        [double]$pulse = 0        # 0..1, brightens/thickens the arc for attention (critical/over-limit)
    )
    # Render at 4x and let GetHicon scale down - the extra resolution is what
    # makes the thin progress arc look smooth instead of jagged at 16px.
    $scale = 4
    $size  = [System.Windows.Forms.SystemInformation]::SmallIconSize
    $w = $size.Width * $scale
    $h = $size.Height * $scale

    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint  = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $margin = $w * 0.10
    $badgeSize = $w - (2 * $margin)
    $badge  = New-Object System.Drawing.RectangleF($margin, $margin, $badgeSize, $badgeSize)

    $lighter = [System.Drawing.Color]::FromArgb(255, [Math]::Min(255, $bg.R + 30), [Math]::Min(255, $bg.G + 30), [Math]::Min(255, $bg.B + 30))
    $bottomY = $h - $margin
    $gradTop = New-Object System.Drawing.PointF(0, $margin)
    $gradBottom = New-Object System.Drawing.PointF(0, $bottomY)
    $gradBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($gradTop, $gradBottom, $lighter, $bg)
    $g.FillEllipse($gradBrush, $badge)

    $ringPen = New-Object System.Drawing.Pen(([System.Drawing.Color]::FromArgb(90, 0, 0, 0)), ($w * 0.02))
    $g.DrawEllipse($ringPen, $badge)

    # The animated progress ring: a bright arc swept clockwise from 12 o'clock,
    # proportional to usage. It sits just outside the badge, on its own track,
    # so the arc's start/end are always visible even at 0% or 100%.
    if ($sweepPct -ge 0) {
        $ringMargin = $w * 0.035
        $trackSize = $w - (2 * $ringMargin)
        $track = New-Object System.Drawing.RectangleF($ringMargin, $ringMargin, $trackSize, $trackSize)
        $trackPen = New-Object System.Drawing.Pen(([System.Drawing.Color]::FromArgb(55, 128, 128, 128)), ($w * 0.055))
        $g.DrawEllipse($trackPen, $track)

        $sweep = [Math]::Min(359.999, [Math]::Max(0.001, 360.0 * ($sweepPct / 100.0)))
        $arcAlpha = [int](200 + 55 * $pulse)
        $arcColor = [System.Drawing.Color]::FromArgb($arcAlpha, 255, 255, 255)
        $arcPen = New-Object System.Drawing.Pen($arcColor, ($w * (0.055 + 0.01 * $pulse)))
        $arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $arcPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawArc($arcPen, $track, -90, $sweep)
        $arcPen.Dispose(); $trackPen.Dispose()
    }

    $fontPx = if ($text.Length -ge 3) { $h * 0.34 } else { $h * 0.46 }
    $font = New-Object System.Drawing.Font('Segoe UI', [single]$fontPx, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment     = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF(0, 0, $w, $h)
    # A soft 1px (at scale) dark shadow keeps the number legible over any
    # taskbar theme, light or dark, without a hard outline at this size.
    $shadowRect = New-Object System.Drawing.RectangleF(($w * 0.02), ($h * 0.02), $w, $h)
    $g.DrawString($text, $font, (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 0, 0, 0))), $shadowRect, $sf)
    $g.DrawString($text, $font, [System.Drawing.Brushes]::White, $rect, $sf)

    $small = New-Object System.Drawing.Bitmap($bmp, $size.Width, $size.Height)
    $hIcon = $small.GetHicon()
    $icon  = ([System.Drawing.Icon]::FromHandle($hIcon)).Clone()
    [void][ClaudeUsageIcon.Native]::DestroyIcon($hIcon)
    $sf.Dispose(); $font.Dispose(); $ringPen.Dispose(); $gradBrush.Dispose()
    $g.Dispose(); $bmp.Dispose(); $small.Dispose()
    return $icon
}

# ---------------- state + rendering ----------------
# The 15s poll only decides WHAT to show (target %, color, text). A separate,
# fast timer (Update-IconFrame) animates the displayed ring toward that target
# and pulses it under critical/over-limit conditions - so the icon eases into
# a new value instead of jumping, without re-reading the cache 8x/second.
$script:cache      = $null
$script:details    = 'No data yet. Send one message in Claude Code (signed in with a Pro/Max plan).'
$script:targetPct  = 0.0
$script:displayPct = 0.0
$script:centerText = '?'
$script:badgeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
$script:showRing   = $false
$script:pulseOn    = $false
$script:pulseT     = 0.0
$script:tip        = "v$TrayVersion Claude usage: no data yet"

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true

function Update-Tray {
    # Re-read every tick (tiny local file). Don't rely on the file's timestamp:
    # File.Replace on Windows can keep the old file's metadata.
    $c = Read-Cache
    if ($null -ne $c) { $script:cache = $c }

    $c = $script:cache
    if ($null -ne $c -and $null -ne $c.SchemaError) {
        $script:centerText = '!'
        $script:badgeColor = [System.Drawing.Color]::FromArgb(160, 40, 160)
        $script:targetPct  = 0.0
        $script:showRing   = $false
        $script:pulseOn    = $false
        $script:tip  = "v$TrayVersion $($c.SchemaError)"
        $script:details = $c.SchemaError
    }
    elseif ($null -eq $c -or $null -eq $c.rate_limits) {
        $script:centerText = '?'
        $script:badgeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
        $script:targetPct  = 0.0
        $script:showRing   = $false
        $script:pulseOn    = $false
        $script:tip  = "v$TrayVersion Claude usage: no data yet"
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

        $script:centerText = $num
        $script:badgeColor = $color
        $script:targetPct  = if ($null -eq $main) { 0.0 } else { [Math]::Min(100.0, $main.Pct) }
        $script:showRing   = ($null -ne $main) -and (-not $stale)
        $script:pulseOn    = (-not $stale) -and (($worst -ge $CritPct) -or ($null -ne $main -and $main.Pct -ge 100))

        $fhTxt = if ($null -eq $fh) { 'n/a' } elseif ($fh.IsReset) { 'reset' } else { '{0:N0}% @{1}' -f $fh.Pct, (Format-When $fh.Reset) }
        $wkTxt = if ($null -eq $wk) { 'n/a' } elseif ($wk.IsReset) { 'reset' } else { '{0:N0}%' -f $wk.Pct }
        $script:tip = "v$TrayVersion 5h $fhTxt | wk $wkTxt | $(Format-Age $age)"

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
        $lines += "claude-usage-on-icon - yasinnerten.com"
        $script:details = $lines -join "`n"
    }

    # NotifyIcon.Text is limited to 63 characters on .NET Framework.
    $tipText = $script:tip
    if ($tipText.Length -gt 63) { $tipText = $tipText.Substring(0, 63) }
    $notify.Text = $tipText
}

function Update-IconFrame {
    # Ease the displayed ring toward the target percentage (exponential
    # ease-out): fast at first, settling in over ~15-20 frames (~1.2-1.6s
    # at the 80ms interval below) instead of jumping straight to the new
    # value. Snap once close enough so the animation timer can stay cheap.
    $delta = $script:targetPct - $script:displayPct
    if ([Math]::Abs($delta) -lt 0.15) {
        $script:displayPct = $script:targetPct
    } else {
        $script:displayPct += $delta * 0.35
    }

    $pulse = 0.0
    if ($script:pulseOn) {
        $script:pulseT += 0.22
        $pulse = (0.5 + 0.5 * [Math]::Sin($script:pulseT))
    } else {
        $script:pulseT = 0.0
    }

    $sweep = if ($script:showRing) { $script:displayPct } else { -1 }
    $icon = New-TrayIcon $script:centerText $script:badgeColor $sweep $pulse
    $old = $notify.Icon
    $notify.Icon = $icon
    if ($null -ne $old) { $old.Dispose() }
}

function Show-Details {
    $notify.BalloonTipTitle = "Claude usage on icon (v$TrayVersion)"
    $notify.BalloonTipText  = $script:details
    $notify.ShowBalloonTip(8000)
}

$RepoUrl = 'https://github.com/yasinnerten/claude-usage-on-icon'

# ---------------- menu ----------------
$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add("Claude usage on icon v$TrayVersion", $null, { Start-Process $RepoUrl })
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Show details', $null, { Show-Details })
[void]$menu.Items.Add('Refresh now',  $null, { Update-Tray })
[void]$menu.Items.Add('Open .claude folder', $null, { Start-Process explorer.exe -ArgumentList "`"$claudeDir`"" })
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('yasinnerten.com', $null, { Start-Process 'https://yasinnerten.com' })
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Exit', $null, {
    $timer.Stop()
    $animTimer.Stop()
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
# Poll timer: re-reads the cache file every 15s (the only I/O; cheap).
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $PollSeconds * 1000
$timer.add_Tick({ try { Update-Tray } catch { } })
$timer.Start()

# Animation timer: redraws the icon at ~12fps, easing the ring toward
# whatever Update-Tray last set as the target and pulsing it when critical.
# No file I/O here, so 12fps on a 16px icon is negligible CPU.
$animTimer = New-Object System.Windows.Forms.Timer
$animTimer.Interval = 80
$animTimer.add_Tick({ try { Update-IconFrame } catch { } })
$animTimer.Start()

Update-Tray
Update-IconFrame
[System.Windows.Forms.Application]::Run()

$mutex.ReleaseMutex()
$mutex.Dispose()
