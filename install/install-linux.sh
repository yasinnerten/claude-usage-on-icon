#!/bin/bash
# install-linux.sh
# Version: (to be filled in by M1)
# Linux installer for quota-tray.
#
# PLACEHOLDER: See PROJECT_PLAN.md (§6.3) for the full spec.
#
# What it should do:
#   - Check for required GTK packages (gir1.2-ayatanaappindicator3-0.1)
#   - If missing, print exact apt/dnf/pacman commands and exit 1
#   - Copy statusline.py and tray-linux.py to ~/.claude/
#   - Merge statusLine into ~/.claude/settings.json (preserve other keys)
#   - Create ~/.config/autostart/quota-tray.desktop (if --autostart flag)
#   - Support --uninstall and --dry-run flags
#   - Be idempotent (safe to run multiple times)

echo "install-linux.sh: placeholder (M1 milestone)"
