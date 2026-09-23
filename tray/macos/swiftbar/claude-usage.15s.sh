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
# What it does NOT do: no network calls, no credential access. Its only
# writes are alert-config.json (when you set a threshold) and alert-state.json
# (so an alert fires once per window), both next to the cache.
#
# Cache dir resolution (must match the writer):
#   1. $CLAUDE_USAGE_ICON_DIR (explicit override)
#   2. $CLAUDE_CONFIG_DIR, else ~/.claude

import json
import os
import subprocess
import sys
import time

TRAY_VERSION = "1.0.0"
KNOWN_SCHEMA = 1
STALE_HOURS = 12
WARN_PCT = 70
CRIT_PCT = 90
REPO_URL = "https://github.com/yasinnerten/claude-usage-on-icon"

# SwiftBar re-runs this script on a fixed interval (the ".15s." in the
# filename) rather than staying resident, so there's no way to animate a
# smooth transition or pulse between refreshes the way the Windows/Linux
# tray does. This pie glyph is the closest still-honest equivalent: a
# discrete, at-a-glance ring that updates each poll.
PIE_GLYPHS = ("○", "◔", "◑", "◕", "●")  # ○ ◔ ◑ ◕ ●


def pie_glyph(pct):
    idx = min(4, max(0, int(pct / 20)))
    return PIE_GLYPHS[idx]


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
ALERT_CONFIG_FILE = os.path.join(CLAUDE_DIR, "alert-config.json")
# Unlike the Windows/Linux tray (a resident process that can just keep an
# "already alerted" flag in memory), this script re-executes fresh every
# poll, so "have we already notified for the current window" has to be
# written to disk to survive between runs.
ALERT_STATE_FILE = os.path.join(CLAUDE_DIR, "alert-state.json")


def read_alert_threshold():
    # Shared JSON config, also read/written by the Windows tray and Linux
    # tray - same schema everywhere: {"threshold_pct": 80}, 0/missing = off.
    if not os.path.exists(ALERT_CONFIG_FILE):
        return 0.0
    try:
        with open(ALERT_CONFIG_FILE, encoding="utf-8") as f:
            cfg = json.load(f)
        return float(cfg.get("threshold_pct") or 0)
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        return 0.0


def read_alert_state():
    if not os.path.exists(ALERT_STATE_FILE):
        return {}
    try:
        with open(ALERT_STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}


def save_alert_state(state):
    try:
        with open(ALERT_STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(state, f)
    except OSError:
        pass


def send_notification(title, text):
    try:
        subprocess.Popen(["osascript", "-e", f'display notification "{text}" with title "{title}"'])
    except OSError:
        pass


def check_alert(key, window, threshold, state):
    # "Already notified for this window" is keyed by resets_at rather than a
    # plain boolean: once the real reset happens, resets_at changes to a new
    # future value, so the stored one no longer matches and a fresh crossing
    # can notify again - no separate "is_reset" branch needed.
    if window is None or threshold <= 0 or window["is_reset"]:
        return
    resets_at = window["reset_epoch"]
    if window["pct"] >= threshold and state.get(key) != resets_at:
        send_notification("Claude usage alert", f"{key} usage reached {window['pct']:.0f}% (alert set at {int(threshold)}%)")
        state[key] = resets_at


def prompt_and_save_threshold():
    # Invoked from the dropdown menu via `--set-threshold`. Runs the dialog
    # from Python (not AppleScript embedded in SwiftBar params) to avoid
    # fragile multi-layer quoting.
    current = read_alert_threshold()
    default = str(int(current)) if current > 0 else "80"
    script = (
        'text returned of (display dialog "Notify me when either window reaches this '
        f'percent used (0 = off):" default answer "{default}")'
    )
    try:
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.SubprocessError):
        return
    if r.returncode != 0:  # user pressed Cancel
        return
    try:
        pct = max(0.0, min(100.0, float(r.stdout.strip())))
    except ValueError:
        return
    try:
        os.makedirs(CLAUDE_DIR, exist_ok=True)
        with open(ALERT_CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump({"threshold_pct": pct}, f)
        if os.path.exists(ALERT_STATE_FILE):
            os.remove(ALERT_STATE_FILE)  # re-arm alerts under the new threshold
    except OSError:
        pass


def alert_menu_line():
    threshold = read_alert_threshold()
    label = f"Set alert threshold... (currently {int(threshold)}%)" if threshold > 0 else "Set alert threshold... (currently off)"
    script = os.path.abspath(__file__)
    return f'{label} | bash="{script}" param1=--set-threshold terminal=false refresh=true'


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
    if "--set-threshold" in sys.argv:
        prompt_and_save_threshold()
        return
    cache = read_cache()

    if cache and cache.get("schema_error"):
        print("! | color=purple")
        print(f"Claude usage on icon v{TRAY_VERSION} | href={REPO_URL}")
        print("---")
        print(cache["schema_error"])
        print(alert_menu_line())
        return

    rate_limits = (cache or {}).get("rate_limits")
    if not cache or not rate_limits:
        print("? | color=gray")
        print(f"Claude usage on icon v{TRAY_VERSION} | href={REPO_URL}")
        print("---")
        print("No data yet")
        print("Send one message in Claude Code (signed in with a Pro/Max plan)")
        print("---")
        print(alert_menu_line())
        return

    fh = get_window(rate_limits.get("five_hour"))
    wk = get_window(rate_limits.get("seven_day"))
    age_seconds = time.time() - cache.get("written_at", 0)
    stale = age_seconds >= STALE_HOURS * 3600

    threshold = read_alert_threshold()
    if not stale and threshold > 0:
        state = read_alert_state()
        before = dict(state)
        check_alert("five_hour", fh, threshold, state)
        check_alert("seven_day", wk, threshold, state)
        if state != before:
            save_alert_state(state)

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
        glyph = PIE_GLYPHS[0]
    elif main_window["pct"] >= 100:
        label = "!"
        glyph = PIE_GLYPHS[-1]
    else:
        label = f"{main_window['pct']:.0f}%"
        glyph = pie_glyph(main_window["pct"])

    print(f"{glyph} {label} | color={color}")
    print(f"Claude usage on icon v{TRAY_VERSION} | href={REPO_URL}")
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
    print(alert_menu_line())
    print("yasinnerten.com | href=https://yasinnerten.com")


if __name__ == "__main__":
    main()
