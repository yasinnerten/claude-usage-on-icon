#!/bin/bash
# install-linux.sh
# Version: 1.0.0
# Linux installer for claude-usage-on-icon.
#
# What it does:
#   - Checks for GTK/AppIndicator bindings (prints the exact package to install if missing)
#   - Copies writer/statusline.py and tray/linux/tray-linux.py to $CLAUDE_CONFIG_DIR (or ~/.claude)
#   - Backs up settings.json, then merges the statusLine command in (preserves other keys)
#   - Optionally creates ~/.config/autostart/claude-usage-on-icon.desktop
#
# No network calls, no credential access. Safe to run more than once (idempotent).

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
DEST_WRITER="$CLAUDE_DIR/statusline.py"
DEST_TRAY="$CLAUDE_DIR/tray-linux.py"
STATUSLINE_CMD="python3 $DEST_WRITER"
AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/claude-usage-on-icon.desktop"

DRY_RUN=0
UNINSTALL=0
FORCE=0
AUTOSTART=0

usage() {
    cat <<EOF
claude-usage-on-icon Linux installer v$VERSION

Usage: $0 [--dry-run] [--uninstall] [--force] [--autostart]

  --dry-run     Show what would change, without writing anything
  --uninstall   Remove everything this installer added
  --force       Overwrite an existing, different statusLine command
  --autostart   Launch the tray automatically on login
EOF
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --force) FORCE=1 ;;
        --autostart) AUTOSTART=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $arg" >&2; usage; exit 1 ;;
    esac
done

print_banner() {
    echo "claude-usage-on-icon Linux installer v$VERSION"
    echo "-----------------------------------------------"
    if [ "$UNINSTALL" = "1" ]; then
        echo "This will REMOVE what a previous install added:"
        echo "  - delete: $DEST_WRITER, $DEST_TRAY"
        echo "  - delete: $AUTOSTART_FILE (if present)"
        echo "  - edit:   $SETTINGS (only removes our statusLine entry; other keys untouched)"
    else
        echo "This will read/write only these locations, as the current user (no elevation, no sudo):"
        echo "  - write: $DEST_WRITER, $DEST_TRAY"
        echo "  - write: $CLAUDE_DIR/usage-cache.json   (created on the next Claude Code message)"
        echo "  - write: $CLAUDE_DIR/usage-statusline.log"
        echo "  - later, only if you set one from the tray menu: $CLAUDE_DIR/alert-config.json (your alert threshold)"
        echo "  - write: $ICON_RUNTIME_NOTE"
        echo "  - edit:  $SETTINGS  (backed up first, other keys preserved)"
        if [ "$AUTOSTART" = "1" ]; then
            echo "  - write: $AUTOSTART_FILE  (launches the tray on login)"
        fi
    fi
    echo "No network calls. No credentials, tokens, or keychains are read."
    echo "-----------------------------------------------"
    echo
}
ICON_RUNTIME_NOTE="\${XDG_RUNTIME_DIR:-/tmp}/claude-usage-on-icon/icon.svg  (temporary, redrawn each refresh)"
print_banner

if [ "$UNINSTALL" = "1" ]; then
    if [ -f "$SETTINGS" ]; then
        python3 - "$SETTINGS" "$STATUSLINE_CMD" <<'PYEOF'
import json, os, sys
settings_path, our_cmd = sys.argv[1], sys.argv[2]
with open(settings_path, encoding="utf-8") as f:
    data = json.load(f)
if (data.get("statusLine") or {}).get("command") == our_cmd:
    del data["statusLine"]
    tmp = settings_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, settings_path)
    print(f"removed statusLine entry from {settings_path}")
else:
    print("statusLine command doesn't match ours; leaving settings.json untouched")
PYEOF
    fi
    rm -f "$DEST_WRITER" "$DEST_TRAY" "$AUTOSTART_FILE"
    echo "removed writer, tray, and autostart entry (if they existed)"
    exit 0
fi

# ---- check GTK/AppIndicator bindings ----
if ! python3 -c "
import gi
gi.require_version('Gtk', '3.0')
try:
    gi.require_version('AyatanaAppIndicator3', '0.1')
except ValueError:
    gi.require_version('AppIndicator3', '0.1')
" >/dev/null 2>&1; then
    echo "error: missing GTK/AppIndicator bindings. Install one of:" >&2
    echo "  sudo apt-get install gir1.2-ayatanaappindicator3-0.1   # Debian/Ubuntu" >&2
    echo "  sudo dnf install libappindicator-gtk3                  # Fedora/RHEL" >&2
    echo "  sudo pacman -S libappindicator-gtk3                     # Arch" >&2
    echo "Then re-run this installer." >&2
    exit 1
fi

SRC_WRITER="$(cd "$SCRIPT_DIR/.." && pwd)/writer/statusline.py"
SRC_TRAY="$(cd "$SCRIPT_DIR/.." && pwd)/tray/linux/tray-linux.py"
for f in "$SRC_WRITER" "$SRC_TRAY"; do
    if [ ! -f "$f" ]; then
        echo "error: cannot find $f next to this installer" >&2
        exit 1
    fi
done

mkdir -p "$CLAUDE_DIR"

if [ -f "$SETTINGS" ] && ! python3 -c "import json; json.load(open('$SETTINGS'))" 2>/dev/null; then
    echo "error: $SETTINGS is not valid JSON. Fix it manually, then re-run this installer." >&2
    exit 1
fi

set +e
python3 - "$SETTINGS" "$STATUSLINE_CMD" "$DRY_RUN" "$FORCE" <<'PYEOF'
import json, os, sys, shutil, time

settings_path, cmd, dry_run, force = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4] == "1"

data = {}
if os.path.exists(settings_path):
    with open(settings_path, encoding="utf-8") as f:
        data = json.load(f)

existing = (data.get("statusLine") or {}).get("command")
ours_already = existing == cmd
looks_like_ours = existing and ("statusline.py" in existing or "statusline-usage" in existing)

if existing and not ours_already and not looks_like_ours and not force:
    print(f"warning: an existing statusLine command is already configured:\n  {existing}")
    print("Not overwriting automatically.")
    print(f"Re-run with --force to replace it, or set CLAUDE_USAGE_ICON_WRAP=\"{existing}\"")
    print("as an environment variable before Claude Code runs, so our writer keeps your existing status line too.")
    sys.exit(3)

if ours_already:
    print("statusLine is already configured for claude-usage-on-icon (nothing to change)")
    sys.exit(0)

if dry_run:
    print(f"[dry-run] would set statusLine.command to: {cmd}")
    sys.exit(0)

if os.path.exists(settings_path):
    backup = f"{settings_path}.bak.{int(time.time())}"
    shutil.copy2(settings_path, backup)
    print(f"backed up {settings_path} -> {backup}")

data["statusLine"] = {"type": "command", "command": cmd}

tmp = settings_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, settings_path)
print(f"updated {settings_path}")
PYEOF
rc=$?
set -e

if [ "$rc" = "3" ]; then
    exit 1
fi
if [ "$DRY_RUN" = "1" ] || [ "$rc" != "0" ]; then
    exit "$rc"
fi

cp "$SRC_WRITER" "$DEST_WRITER"
cp "$SRC_TRAY" "$DEST_TRAY"
chmod +x "$DEST_WRITER" "$DEST_TRAY"
echo "installed writer -> $DEST_WRITER"
echo "installed tray -> $DEST_TRAY"

if [ "$AUTOSTART" = "1" ]; then
    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Claude usage on icon
Exec=$DEST_TRAY
Icon=utilities-system-monitor
X-GNOME-Autostart-enabled=true
Comment=Shows Claude Code plan usage in the tray
EOF
    echo "created autostart entry -> $AUTOSTART_FILE"
fi

echo
echo "Done. Start the tray now with:"
echo "  $DEST_TRAY &"
echo
echo "GNOME users: install the AppIndicator Support extension if the icon doesn't appear:"
echo "  https://extensions.gnome.org/extension/615/appindicator-support/"
