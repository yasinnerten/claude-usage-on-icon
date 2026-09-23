# statusline.ps1
# Version: (to be filled in by M1)
# Claude Code status line for Windows (Windows PowerShell 5.1 or PowerShell 7).
#
# PLACEHOLDER: See docs/how-it-works.md and PROJECT_PLAN.md (§5, Appendix A.1) for the reference implementation.
#
# What it should do:
#   1. Read JSON from stdin (Claude Code status line input)
#   2. Print one status line: [Model] | ctx 12% | 5h 31% (resets 14:45) | week 12% (resets Mon 04:52)
#   3. If rate_limits is present, write to usage-cache.json via temp file + atomic rename
#   4. Always write a diagnostic log line to usage-statusline.log
#
# Specs (from §5):
#   - Read all of stdin; on JSON parse failure, print "statusline: could not parse input" and exit 0
#   - Write cache only when rate_limits present (temp file in same dir, then atomic rename)
#   - PowerShell: use [IO.File]::Replace with fallback to Copy
#   - Print ASCII only, target < 150 ms
#   - No dependencies beyond PowerShell 5.1
#   - Optional: QUOTA_TRAY_WRAP env var for passthrough to another command

Write-Output "statusline.ps1: placeholder (M1 milestone)"
