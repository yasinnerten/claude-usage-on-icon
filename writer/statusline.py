#!/usr/bin/env python3
# statusline.py
# Version: (to be filled in by M1)
# Claude Code status line for Linux, WSL, and macOS
#
# PLACEHOLDER: See docs/how-it-works.md and PROJECT_PLAN.md (§5, Appendix A.3) for the reference implementation.
#
# What it should do:
#   1. Read JSON from stdin (Claude Code status line input)
#   2. Print one status line: [Model] | ctx 12% | 5h 31% (resets 14:45) | week 12% (resets Mon 04:52)
#   3. If rate_limits is present, write to usage-cache.json via temp file + atomic rename
#   4. Always write a diagnostic log line to usage-statusline.log
#
# Specs (from §5):
#   - Read all of stdin; on JSON parse failure, print "statusline: could not parse input" and exit 0
#   - Write cache only when rate_limits present (temp file + os.replace)
#   - For WSL: auto-detect Windows home via wslpath and /proc/version
#   - Print ASCII only, target < 150 ms
#   - No dependencies beyond Python 3.8+ stdlib
#   - Optional: QUOTA_TRAY_WRAP env var for passthrough to another command

import sys
print("statusline.py: placeholder (M1 milestone)", file=sys.stderr)
sys.exit(0)
