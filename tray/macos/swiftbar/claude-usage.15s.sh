#!/usr/bin/env python3
# claude-usage.15s.sh
# Version: 1.0.0
# SwiftBar/xbar plugin for Claude Code plan usage (macOS menu bar).
#
# SwiftBar identifies the plugin's interpreter from the shebang line, not the
# extension; the ".15s." in the filename sets SwiftBar's 15-second refresh
# interval to match the writer's poll assumption.
#
# Reads ONLY <cache dir>/usage-cache.json, which statusline.py writes from the
# `rate_limits` data Claude Code already gives the status line.
#
# What it does NOT do: no network calls, no credential access, no writes.
#
# Cache dir resolution (must match the writer):
#   1. $CLAUDE_USAGE_ICON_DIR (explicit override)
#   2. $CLAUDE_CONFIG_DIR, else ~/.claude

import json
import os
import time

TRAY_VERSION = "1.0.0"
KNOWN_SCHEMA = 1
STALE_HOURS = 12
WARN_PCT = 70
CRIT_PCT = 90


def resolve_cache_dir():
    override = os.environ.get("CLAUDE_USAGE_ICON_DIR")
    if override:
        return override
    claude_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    if claude_dir:
        return claude_dir
    return os.path.join(os.path.expanduser("~"), ".claude")


CLAUDE_DIR = resolve_cache_dir()
CACHE_FILE = os.path.join(CLAUDE_DIR, "usage-cache.json")


def read_cache():
    if not os.path.exists(CACHE_FILE):
        return None
    for _ in range(3):
        try:
            with open(CACHE_FILE, encoding="utf-8") as f:
                data = json.load(f)
            schema = data.get("schema", 1)
            if schema > KNOWN_SCHEMA:
                return {"schema_error": f"cache schema {schema} is newer than this plugin (v{TRAY_VERSION}) understands"}
            return data
        except (OSError, json.JSONDecodeError):
            time.sleep(0.15)
    return None


def get_window(obj):
    if not obj or obj.get("used_percentage") is None:
        return None
    reset_epoch = obj.get("resets_at")
    is_reset = reset_epoch is not None and time.time() >= reset_epoch
    pct = 0.0 if is_reset else float(obj["used_percentage"])
    return {"pct": pct, "reset_epoch": reset_epoch, "is_reset": is_reset}


def format_when(reset_epoch):
    if reset_epoch is None:
        return "?"
    t = time.localtime(reset_epoch)
    now = time.localtime()
    if t.tm_yday == now.tm_yday and t.tm_year == now.tm_year:
        return time.strftime("%H:%M", t)
    return time.strftime("%a %H:%M", t)


def format_age(seconds):
    if seconds < 60:
        return "just now"
    if seconds < 3600:
        return f"{int(seconds // 60)}m ago"
    if seconds < 86400:
        return f"{int(seconds // 3600)}h ago"
    return f"{int(seconds // 86400)}d ago"


def main():
    cache = read_cache()

    if cache and cache.get("schema_error"):
        print("! | color=purple")
        print("---")
        print(cache["schema_error"])
        return

    rate_limits = (cache or {}).get("rate_limits")
    if not cache or not rate_limits:
        print("? | color=gray")
        print("---")
        print("No data yet")
        print("Send one message in Claude Code (signed in with a Pro/Max plan)")
        return

    fh = get_window(rate_limits.get("five_hour"))
    wk = get_window(rate_limits.get("seven_day"))
    age_seconds = time.time() - cache.get("written_at", 0)
    stale = age_seconds >= STALE_HOURS * 3600

    worst = max((w["pct"] for w in (fh, wk) if w), default=0)
    if stale:
        color = "gray"
    elif worst >= CRIT_PCT:
        color = "red"
    elif worst >= WARN_PCT:
        color = "orange"
    else:
        color = "green"

    main_window = fh or wk
    if main_window is None:
        label = "-"
    elif main_window["pct"] >= 100:
        label = "!"
    else:
        label = f"{main_window['pct']:.0f}%"

    print(f"{label} | color={color}")
    print("---")

    if fh is not None:
        if fh["is_reset"]:
            print(f"5-hour: window reset at {format_when(fh['reset_epoch'])} (new % after your next message)")
        else:
            print(f"5-hour: {fh['pct']:.1f}% used, resets {format_when(fh['reset_epoch'])}")
    if wk is not None:
        if wk["is_reset"]:
            print(f"Weekly: window reset at {format_when(wk['reset_epoch'])}")
        else:
            print(f"Weekly: {wk['pct']:.1f}% used, resets {format_when(wk['reset_epoch'])}")

    print(f"Updated {format_age(age_seconds)} (from Claude Code status line)")
    print(f"Source: {cache.get('source')} | schema {cache.get('schema')} | writer v{cache.get('writer_version')}")
    print(f"Plugin v{TRAY_VERSION} | file: {CACHE_FILE}")
    if stale:
        print("Stale: open Claude Code and send a message to refresh.")
    print("---")
    print("Open .claude folder | bash=/usr/bin/open param1=" + CLAUDE_DIR + " terminal=false")


if __name__ == "__main__":
    main()
