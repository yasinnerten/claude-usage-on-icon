#!/bin/bash
# install-wsl.sh
# Version: 1.0.0
# WSL installer for claude-usage-on-icon's writer AND, automatically, the
# Windows tray (see install-windows.ps1) - one command instead of two.
#
# What it does:
#   - Copies writer/statusline.py to $CLAUDE_CONFIG_DIR (or ~/.claude)
#   - Backs up settings.json, then merges the statusLine command in (preserves other keys)
#   - Warns instead of overwriting if a different statusLine is already configured
#   - Then, unless --skip-windows is passed, drives install-windows.ps1 on the
#     Windows side too, via the same cmd.exe/powershell.exe interop the
#     writer already uses to auto-detect the Windows home directory - no
#     manual "switch to a Windows terminal" step needed.
#
# No network calls, no credential access. Safe to run more than once (idempotent).

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
DEST_WRITER="$CLAUDE_DIR/statusline.py"
STATUSLINE_CMD="python3 $DEST_WRITER"

PWSH_CANDIDATES=(
    "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    "/mnt/c/Windows/Sysnative/WindowsPowerShell/v1.0/powershell.exe"
)

DRY_RUN=0
UNINSTALL=0
FORCE=0
SKIP_WINDOWS=0

usage() {
    cat <<EOF
claude-usage-on-icon WSL installer v$VERSION

Usage: $0 [--dry-run] [--uninstall] [--force] [--skip-windows]

  --dry-run       Show what would change, without writing anything
  --uninstall     Remove the writer and the statusLine entry we added
  --force         Overwrite an existing, different statusLine command
  --skip-windows  Install the WSL writer only; don't also drive the Windows
                  tray installer (e.g. if you'll install it separately, or
                  aren't using the Windows tray at all)
EOF
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --force) FORCE=1 ;;
        --skip-windows) SKIP_WINDOWS=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $arg" >&2; usage; exit 1 ;;
    esac
done

is_wsl() {
    [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] && return 0
    grep -qi microsoft /proc/version 2>/dev/null
}

find_powershell() {
    for c in "${PWSH_CANDIDATES[@]}"; do
        if [ -x "$c" ]; then
            printf '%s' "$c"
            return 0
        fi
    done
    if command -v powershell.exe >/dev/null 2>&1; then
        command -v powershell.exe
        return 0
    fi
    return 1
}

print_banner() {
    echo "claude-usage-on-icon WSL installer v$VERSION"
    echo "--------------------------------------------"
    if [ "$UNINSTALL" = "1" ]; then
        echo "This will REMOVE what a previous install added:"
        echo "  - delete: $DEST_WRITER"
        echo "  - edit:   $SETTINGS (only removes our statusLine entry; other keys untouched)"
    else
        echo "This will read/write only these locations, as the current user (no elevation):"
        echo "  - write: $DEST_WRITER                 (the writer script itself)"
        echo "  - write: $CLAUDE_DIR/usage-cache.json   (created on the next Claude Code message)"
        echo "  - write: $CLAUDE_DIR/usage-statusline.log"
        echo "  - later, only if you set one from the tray menu: $CLAUDE_DIR/alert-config.json (your alert threshold)"
        echo "  - edit:  $SETTINGS  (backed up first, other keys preserved)"
        echo "  - read:  ~/.config/claude-usage-on-icon/win_home  (cached Windows-home lookup)"
        if [ "$SKIP_WINDOWS" != "1" ] && is_wsl; then
            echo "  - Also runs install-windows.ps1 on the Windows side (via the same"
            echo "    cmd.exe/powershell.exe interop the writer uses), which prints its own"
            echo "    banner for what IT touches before doing anything. Pass --skip-windows"
            echo "    to do only the WSL half."
        fi
    fi
    echo "No network calls. No credentials, tokens, or keychains are read. No sudo/elevation."
    echo "--------------------------------------------"
    echo
}
print_banner

if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 is required (Ubuntu ships it by default)." >&2
    exit 1
fi

if [ "$UNINSTALL" = "1" ]; then
    python3 - "$SETTINGS" "$STATUSLINE_CMD" <<'PYEOF'
import json, os, sys
settings_path, our_cmd = sys.argv[1], sys.argv[2]
if not os.path.exists(settings_path):
    print("no settings.json found; nothing to undo")
    sys.exit(0)
with open(settings_path, encoding="utf-8") as f:
    data = json.load(f)
current = (data.get("statusLine") or {}).get("command")
if current == our_cmd:
    del data["statusLine"]
    tmp = settings_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, settings_path)
    print(f"removed statusLine entry from {settings_path}")
else:
    print("statusLine command doesn't match ours; leaving settings.json untouched")
PYEOF
    rm -f "$DEST_WRITER"
    echo "removed $DEST_WRITER (if it existed)"
    exit 0
fi

SRC_WRITER="$(cd "$SCRIPT_DIR/.." && pwd)/writer/statusline.py"
if [ ! -f "$SRC_WRITER" ]; then
    echo "error: cannot find writer/statusline.py next to this installer" >&2
    exit 1
fi

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
if [ "$rc" != "0" ]; then
    exit "$rc"
fi

if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] would copy $SRC_WRITER -> $DEST_WRITER"
else
    cp "$SRC_WRITER" "$DEST_WRITER"
    chmod +x "$DEST_WRITER"
    echo "installed writer -> $DEST_WRITER"
fi

manual_windows_instructions() {
    echo
    echo "Next step: on Windows, run install-windows.ps1 to install the tray icon."
    echo "It reads the cache this WSL writer creates (Windows home is auto-detected)."
    echo "  powershell -NoProfile -ExecutionPolicy Bypass -File install/install-windows.ps1 -WithStartup"
}

if [ "$SKIP_WINDOWS" = "1" ]; then
    manual_windows_instructions
    exit 0
fi

if ! is_wsl; then
    # Not actually WSL (e.g. run by mistake on native Linux); nothing on the
    # Windows side to drive.
    exit 0
fi

PWSH="$(find_powershell)" || {
    echo
    echo "note: could not find powershell.exe to automatically install the Windows tray."
    manual_windows_instructions
    exit 0
}

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WIN_INSTALLER_UNC="$(wslpath -w "$REPO_ROOT/install/install-windows.ps1")"

echo
if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] Windows side (install-windows.ps1 -WhatIf):"
else
    echo "Installing the Windows tray automatically..."
fi
echo "-----------------------------------------------"
WIN_ARGS=(-WithStartup)
[ "$FORCE" = "1" ] && WIN_ARGS+=(-Force)
[ "$DRY_RUN" = "1" ] && WIN_ARGS+=(-WhatIf)
if "$PWSH" -NoProfile -ExecutionPolicy Bypass -File "$WIN_INSTALLER_UNC" "${WIN_ARGS[@]}"; then
    echo "-----------------------------------------------"
    [ "$DRY_RUN" != "1" ] && echo "Windows tray installed and started."
else
    rc=$?
    echo "-----------------------------------------------"
    echo "note: the Windows installer exited with an error (see its output above)."
    manual_windows_instructions
    exit "$rc"
fi
