#!/usr/bin/env python3
# statusline.py
# Version: 1.0.0
# Claude Code status line for Linux, WSL, and macOS (Python 3.8+ stdlib only).
#
# What it does:
#   1. Reads the JSON that Claude Code pipes in on stdin.
#   2. Prints one status line: model, context %, 5-hour %, weekly %.
#   3. If the JSON contains `rate_limits`, saves that object to
#      <cache dir>/usage-cache.json for the tray to read.
#
# What it does NOT do: no network calls, no credential access.
#
# Cache dir resolution (in order):
#   1. $CLAUDE_USAGE_ICON_DIR env var (explicit override)
#   2. On WSL: the Windows home dir (auto-detected), so the Windows tray can read it
#   3. $CLAUDE_CONFIG_DIR, else ~/.claude
#
# Optional passthrough: set CLAUDE_USAGE_ICON_WRAP="<command>" to pipe the same
# stdin to that command and print its output instead of ours (keeps your
# existing status line while this script still writes the cache).

import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime

VERSION = "1.0.0"
SCHEMA = 1

CMD_EXE_CANDIDATES = ("/mnt/c/Windows/System32/cmd.exe",)


def detect_source():
    if os.path.exists("/proc/sys/fs/binfmt_misc/WSLInterop"):
        return "wsl"
    try:
        with open("/proc/version", encoding="utf-8", errors="ignore") as f:
            if "microsoft" in f.read().lower():
                return "wsl"
    except OSError:
        pass
    if sys.platform == "darwin":
        return "macos"
    return "linux"


def _win_home_cache_file():
    return os.path.join(os.path.expanduser("~"), ".config", "claude-usage-on-icon", "win_home")


def _resolve_windows_home():
    cache_file = _win_home_cache_file()
    try:
        with open(cache_file, encoding="utf-8") as f:
            cached = f.read().strip()
        if cached and os.path.isdir(cached):
            return cached
    except OSError:
        pass

    cmd_exe = next((p for p in CMD_EXE_CANDIDATES if os.path.exists(p)), None)
    if cmd_exe is None:
        return None

    try:
        r = subprocess.run(
            [cmd_exe, "/c", "echo %USERPROFILE%"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        win_path = r.stdout.strip()
        if not win_path or win_path == "%USERPROFILE%":
            return None
        wp = subprocess.run(["wslpath", "-u", win_path], capture_output=True, text=True, timeout=5)
        wsl_path = wp.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None

    if not wsl_path or not os.path.isdir(wsl_path):
        return None

    try:
        os.makedirs(os.path.dirname(cache_file), exist_ok=True)
        with open(cache_file, "w", encoding="utf-8") as f:
            f.write(wsl_path)
    except OSError:
        pass  # caching is best-effort; a slow cmd.exe call next time is not fatal

    return wsl_path


def resolve_cache_dir(source):
    override = os.environ.get("CLAUDE_USAGE_ICON_DIR")
    if override:
        return override

    if source == "wsl":
        win_home = _resolve_windows_home()
        if win_home:
            return os.path.join(win_home, ".claude")

    claude_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    if claude_dir:
        return claude_dir
    return os.path.join(os.path.expanduser("~"), ".claude")


def fmt_reset(epoch):
    if epoch is None:
        return ""
    try:
        t = datetime.fromtimestamp(int(epoch))
    except (OSError, OverflowError, ValueError):
        return ""
    return t.strftime("%H:%M") if t.date() == datetime.now().date() else t.strftime("%a %H:%M")


def write_cache(cache_dir, diag_file, source, data, rl):
    cache_file = os.path.join(cache_dir, "usage-cache.json")
    payload = {
        "schema": SCHEMA,
        "written_at": int(time.time()),
        "writer_version": VERSION,
        "source": source,
        "session_id": data.get("session_id"),
        "rate_limits": rl,
    }
    try:
        os.makedirs(cache_dir, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=cache_dir, prefix="usage-cache.", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2)
            try:
                os.replace(tmp, cache_file)  # atomic on POSIX
            except OSError:
                # The Windows side may briefly hold the file open over /mnt/c.
                with open(cache_file, "w", encoding="utf-8") as f:
                    json.dump(payload, f, indent=2)
                os.remove(tmp)
        finally:
            if os.path.exists(tmp):
                os.remove(tmp)
        return "ok: cache written"
    except OSError as e:
        return f"write FAILED: {e}"


def main():
    try:
        raw = sys.stdin.read()
        data = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError):
        print("statusline: could not parse input")
        return 0

    source = detect_source()
    cache_dir = resolve_cache_dir(source)
    diag_file = os.path.join(cache_dir, "usage-statusline.log")

    rl = data.get("rate_limits")
    if rl:
        diag = write_cache(cache_dir, diag_file, source, data, rl)
    else:
        diag = "no rate_limits in input (not a Pro/Max sign-in, or no response yet this session)"

    try:
        os.makedirs(cache_dir, exist_ok=True)
        with open(diag_file, "w", encoding="utf-8") as f:
            f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S}  v{VERSION} ({source})  {diag}")
    except OSError:
        pass

    wrap_cmd = os.environ.get("CLAUDE_USAGE_ICON_WRAP")
    if wrap_cmd:
        try:
            r = subprocess.run(wrap_cmd, shell=True, input=raw, capture_output=True, text=True, timeout=10)
            print(r.stdout, end="")
            return 0
        except (OSError, subprocess.SubprocessError):
            pass  # fall through to our own line if the wrapped command fails

    parts = []
    model = (data.get("model") or {}).get("display_name")
    if model:
        parts.append(f"[{model}]")

    ctx = (data.get("context_window") or {}).get("used_percentage")
    if ctx is not None:
        parts.append(f"ctx {float(ctx):.0f}%")

    for key, label in (("five_hour", "5h"), ("seven_day", "week")):
        w = (rl or {}).get(key) or {}
        if w.get("used_percentage") is not None:
            parts.append(f"{label} {float(w['used_percentage']):.0f}% (resets {fmt_reset(w.get('resets_at'))})")

    print(" | ".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
