# install-windows.ps1
# Version: 1.0.0
# Windows installer for claude-usage-on-icon.
#
# Installs the tray (tray-windows.ps1) and the Windows-native writer (statusline.ps1).
# Use this even if Claude Code CLI runs inside WSL: the tray always runs on Windows,
# it just reads the cache the WSL writer creates instead (see install-wsl.sh).
#
# Usage:
#   install-windows.ps1                  # install, merge statusLine into settings.json
#   install-windows.ps1 -WithStartup     # also launch the tray on login
#   install-windows.ps1 -WhatIf          # show what would change, don't write anything
#   install-windows.ps1 -Force           # overwrite a different existing statusLine
#   install-windows.ps1 -Uninstall       # remove what we added
#   install-windows.ps1 -TrayOnly        # skip statusLine/statusline.ps1 (WSL+tray setups)

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$WithStartup,
    [switch]$Force,
    [switch]$Uninstall,
    [switch]$TrayOnly
)

$ErrorActionPreference = 'Stop'
$Version = '1.0.0'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$SettingsFile = Join-Path $ClaudeDir 'settings.json'
$StatuslineCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File $($ClaudeDir -replace '\\','/')/statusline.ps1"

$StartupDir = Join-Path ([Environment]::GetFolderPath('Startup')) ''
$ShortcutPath = Join-Path $StartupDir 'Claude usage on icon.lnk'
$LauncherPath = Join-Path $ClaudeDir 'launcher.vbs'
$TrayDest = Join-Path $ClaudeDir 'tray-windows.ps1'
$WriterDest = Join-Path $ClaudeDir 'statusline.ps1'

function Merge-StatusLine {
    param([bool]$WhatIfMode)

    $data = [ordered]@{}
    if (Test-Path -LiteralPath $SettingsFile) {
        $raw = Get-Content -LiteralPath $SettingsFile -Raw
        try {
            $parsed = $raw | ConvertFrom-Json
        } catch {
            throw "settings.json is not valid JSON ($SettingsFile). Fix it manually, then re-run this installer."
        }
        $parsed.PSObject.Properties | ForEach-Object { $data[$_.Name] = $_.Value }
    }

    $existing = $null
    if ($data.Contains('statusLine') -and $null -ne $data['statusLine']) {
        $existing = $data['statusLine'].command
    }

    $oursAlready = $existing -eq $StatuslineCmd
    $looksLikeOurs = $existing -and ($existing -match 'statusline\.ps1' -or $existing -match 'statusline-usage')

    if ($existing -and -not $oursAlready -and -not $looksLikeOurs -and -not $Force) {
        Write-Warning "An existing statusLine command is already configured:`n  $existing"
        Write-Warning "Not overwriting automatically. Re-run with -Force to replace it, or set"
        Write-Warning "CLAUDE_USAGE_ICON_WRAP as an env var pointing to that command so our writer keeps it too."
        return $false
    }

    if ($oursAlready) {
        Write-Host "statusLine is already configured for claude-usage-on-icon (nothing to change)"
        return $true
    }

    if ($WhatIfMode) {
        Write-Host "[WhatIf] would set statusLine.command to: $StatuslineCmd"
        return $true
    }

    if (Test-Path -LiteralPath $SettingsFile) {
        $backup = "$SettingsFile.bak.$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
        Copy-Item -LiteralPath $SettingsFile -Destination $backup
        Write-Host "backed up $SettingsFile -> $backup"
    }

    $data['statusLine'] = [ordered]@{ type = 'command'; command = $StatuslineCmd }
    $json = $data | ConvertTo-Json -Depth 10
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    [System.IO.File]::WriteAllText($SettingsFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "updated $SettingsFile"
    return $true
}

function Remove-StatusLine {
    if (-not (Test-Path -LiteralPath $SettingsFile)) {
        Write-Output "no settings.json found; nothing to undo"
        return
    }
    $parsed = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
    $data = [ordered]@{}
    $parsed.PSObject.Properties | ForEach-Object { $data[$_.Name] = $_.Value }

    $current = $null
    if ($data.Contains('statusLine') -and $null -ne $data['statusLine']) {
        $current = $data['statusLine'].command
    }

    if ($current -eq $StatuslineCmd) {
        $data.Remove('statusLine')
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($SettingsFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Output "removed statusLine entry from $SettingsFile"
    } else {
        Write-Output "statusLine command doesn't match ours; leaving settings.json untouched"
    }
}

function New-StartupShortcut {
    $vbs = @"
Set objShell = CreateObject("WScript.Shell")
scriptPath = "$TrayDest"
objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptPath & """", 0, False
"@
    [System.IO.File]::WriteAllText($LauncherPath, $vbs, (New-Object System.Text.ASCIIEncoding))

    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = 'wscript.exe'
    $shortcut.Arguments = "`"$LauncherPath`""
    $shortcut.Description = "Claude usage on icon tray v$Version"
    $shortcut.Save()
    Write-Output "created Startup shortcut: $ShortcutPath"
}

function Remove-StartupShortcut {
    if (Test-Path -LiteralPath $ShortcutPath) {
        Remove-Item -LiteralPath $ShortcutPath -Force
        Write-Output "removed Startup shortcut: $ShortcutPath"
    }
    if (Test-Path -LiteralPath $LauncherPath) {
        Remove-Item -LiteralPath $LauncherPath -Force
        Write-Output "removed $LauncherPath"
    }
}

# ---------------- main ----------------

if ($Uninstall) {
    Remove-StatusLine
    Remove-StartupShortcut
    foreach ($f in @($TrayDest, $WriterDest)) {
        if (Test-Path -LiteralPath $f) {
            Remove-Item -LiteralPath $f -Force
            Write-Output "removed $f"
        }
    }
    Write-Output "Uninstall complete. Backups of settings.json were left in place."
    exit 0
}

$whatIfMode = -not $PSCmdlet.ShouldProcess($ClaudeDir, 'Install claude-usage-on-icon')

if (-not $whatIfMode) {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
}

$srcTray = Join-Path $RepoRoot 'tray/windows/tray-windows.ps1'
$srcWriter = Join-Path $RepoRoot 'writer/statusline.ps1'
foreach ($p in @($srcTray, $srcWriter)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "cannot find $p next to this installer (run install-windows.ps1 from inside the repo's install/ folder)"
    }
}

if ($whatIfMode) {
    Write-Output "[WhatIf] would copy $srcTray -> $TrayDest"
} else {
    Copy-Item -LiteralPath $srcTray -Destination $TrayDest -Force
    Unblock-File -LiteralPath $TrayDest
    Write-Output "installed tray -> $TrayDest"
}

if (-not $TrayOnly) {
    if ($whatIfMode) {
        Write-Output "[WhatIf] would copy $srcWriter -> $WriterDest"
    } else {
        Copy-Item -LiteralPath $srcWriter -Destination $WriterDest -Force
        Unblock-File -LiteralPath $WriterDest
        Write-Output "installed writer -> $WriterDest"
    }
    $ok = Merge-StatusLine -WhatIfMode:$whatIfMode
    if (-not $ok) { exit 1 }
} else {
    Write-Output "Skipping writer/statusLine setup (-TrayOnly): assuming a WSL/Linux/macOS writer feeds this cache."
}

if ($WithStartup -and -not $whatIfMode) {
    New-StartupShortcut
    Write-Output "Starting the tray now..."
    Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$TrayDest`"" -WindowStyle Hidden
} elseif ($WithStartup) {
    Write-Output "[WhatIf] would create a Startup shortcut and launch the tray"
}

if (-not $whatIfMode) {
    Write-Output ""
    Write-Output "Done. If the tray isn't already running, start it with:"
    Write-Output "  powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$TrayDest`""
}
