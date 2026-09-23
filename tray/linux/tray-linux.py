#!/usr/bin/env python3
# tray-linux.py
# Version: (to be filled in by M1)
# Linux tray icon for Claude Code plan usage.
#
# PLACEHOLDER: See PROJECT_PLAN.md (§6.3) for the reference implementation.
#
# What it should do:
#   - Poll usage-cache.json every 15 s
#   - Draw SVG/PNG icon with 5-hour % (fallback to weekly if 5h missing)
#   - Color: green < 70%, amber 70-89%, red >= 90%, grey if stale (> 12h) or no data
#   - Show tooltip and detail popup
#   - Menu: version label, Show details, Refresh now, Open .claude folder, Exit
#   - Single instance check
#   - No network, no credential access, minimal writes (temp icon only)
#
# Tech stack:
#   - Python 3 + gi (GTK bindings)
#   - AyatanaAppIndicator3 (Ubuntu/Debian) or AppIndicator3 (fallback)
#   - SVG/PNG rendering into $XDG_RUNTIME_DIR (temporary)
#   - No third-party pip packages (stdlib + system gi only)

import sys
print("tray-linux.py: placeholder (M1 milestone)", file=sys.stderr)
sys.exit(0)
