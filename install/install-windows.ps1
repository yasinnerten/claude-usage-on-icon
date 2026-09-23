# install-windows.ps1
# Version: (to be filled in by M1)
# Windows installer for quota-tray.
#
# PLACEHOLDER: See PROJECT_PLAN.md (§6.2) for the full spec.
#
# What it should do:
#   - Accept flags: -WhatIf, -Uninstall, -WithStartup
#   - Back up settings.json before editing
#   - Merge statusLine into settings.json (preserve other keys like hooks)
#   - Copy statusline.ps1 and tray-windows.ps1 to ~/.claude/
#   - Run Unblock-File on scripts
#   - Optionally create Startup folder shortcut
#   - For -Uninstall: remove shortcut, remove statusLine, remove scripts
#   - Be idempotent (safe to run multiple times)

Write-Output "install-windows.ps1: placeholder (M1 milestone)"
