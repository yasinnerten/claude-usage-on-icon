# tray-windows.ps1
# Version: (to be filled in by M1)
# Windows tray icon for Claude Code plan usage (Windows PowerShell 5.1).
#
# PLACEHOLDER: See PROJECT_PLAN.md (§6.2, Appendix A.2) for the reference implementation.
#
# What it should do:
#   - Poll usage-cache.json every 15 s
#   - Draw icon with 5-hour % (fallback to weekly if 5h missing)
#   - Color: green < 70%, amber 70-89%, red >= 90%, grey if stale (> 12h) or no data
#   - Hover text: "v1.0.0 5h 31% @14:45 | wk 12% | 3m ago" (max 63 chars)
#   - Click shows details: windows with %, reset times, "updated N ago", version, cache path
#   - Menu: version label, Show details, Refresh now, Open .claude folder, Exit
#   - Single instance (mutex, no silent exit)
#   - No network, no credential access, no writes
#
# Tech stack:
#   - NotifyIcon from WinForms
#   - GDI+ for drawing icons
#   - DestroyIcon P/Invoke to avoid handle leaks
#   - Local\ named mutex for single-instance
#   - Forms.Timer for polling

Write-Output "tray-windows.ps1: placeholder (M1 milestone)"
