#!/usr/bin/env python3
# tray-linux.py
# Version: 1.0.0
# Linux tray icon for Claude Code plan usage (GTK 3 + AppIndicator, stdlib + gi only).
#
# Reads ONLY <cache dir>/usage-cache.json, which statusline.py writes from the
# `rate_limits` data Claude Code already gives the status line.
#
# What it does NOT do: no network calls, no credential access. The only files
# it writes are two small temporary SVG icons under $XDG_RUNTIME_DIR (see
# ICON_PATHS below - alternated each animation frame, not accumulated).
#
# Cache dir resolution (must match the writer):
#   1. $CLAUDE_USAGE_ICON_DIR (explicit override)
#   2. $CLAUDE_CONFIG_DIR, else ~/.claude
#
# Requires: gir1.2-ayatanaappindicator3-0.1 (Debian/Ubuntu) or gir1.2-appindicator3-0.1.
# On GNOME, also install the AppIndicator Support extension.

import json
import math
import os
import sys
import time

TRAY_VERSION = "1.0.0"
KNOWN_SCHEMA = 1
POLL_SECONDS = 15
ANIM_INTERVAL_MS = 80
STALE_HOURS = 12
WARN_PCT = 70
CRIT_PCT = 90
REPO_URL = "https://github.com/yasinnerten/claude-usage-on-icon"

try:
    import gi

    gi.require_version("Gtk", "3.0")
    try:
        gi.require_version("AyatanaAppIndicator3", "0.1")
        from gi.repository import AyatanaAppIndicator3 as AppIndicator3
    except ValueError:
        gi.require_version("AppIndicator3", "0.1")
        from gi.repository import AppIndicator3
    from gi.repository import GLib, Gtk
except (ImportError, ValueError) as e:
    sys.stderr.write(
        "claude-usage-on-icon: missing GTK/AppIndicator bindings.\n"
        "Install with one of:\n"
        "  sudo apt-get install gir1.2-ayatanaappindicator3-0.1   # Debian/Ubuntu\n"
        "  sudo dnf install libappindicator-gtk3                  # Fedora/RHEL\n"
        "  sudo pacman -S libappindicator-gtk3                     # Arch\n"
        f"(underlying error: {e})\n"
    )
    sys.exit(1)


def resolve_cache_dir():
    override = os.environ.get("CLAUDE_USAGE_ICON_DIR")
    if override:
        return override
    claude_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    if claude_dir:
        return claude_dir
    return os.path.join(os.path.expanduser("~"), ".claude")


def icon_runtime_dir():
    base = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    d = os.path.join(base, "claude-usage-on-icon")
    os.makedirs(d, exist_ok=True)
    return d


CLAUDE_DIR = resolve_cache_dir()
CACHE_FILE = os.path.join(CLAUDE_DIR, "usage-cache.json")
ICON_DIR = icon_runtime_dir()
# Some StatusNotifierItem hosts don't reliably notice a same-path file change
# on rapid redraws; alternating between two paths forces a reload every frame.
ICON_PATHS = (os.path.join(ICON_DIR, "icon-a.svg"), os.path.join(ICON_DIR, "icon-b.svg"))

COLOR_OK = (0.12, 0.55, 0.27)
COLOR_WARN = (0.84, 0.55, 0.0)
COLOR_CRIT = (0.78, 0.16, 0.16)
COLOR_GREY = (0.47, 0.47, 0.47)
COLOR_SCHEMA_ERR = (0.63, 0.16, 0.63)


def read_cache():
    if not os.path.exists(CACHE_FILE):
        return None
    for _ in range(3):
        try:
            with open(CACHE_FILE, encoding="utf-8") as f:
                data = json.load(f)
            schema = data.get("schema", 1)
            if schema > KNOWN_SCHEMA:
                return {"schema_error": f"cache schema {schema} is newer than this tray (v{TRAY_VERSION}) understands"}
            return data
        except (OSError, json.JSONDecodeError):
            time.sleep(0.15)  # file being swapped; try again
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


def render_icon_svg(text, rgb, sweep_pct, pulse, path):
    """sweep_pct: -1 for no ring (e.g. '?' state), else 0..100. pulse: 0..1."""
    r, g, b = rgb
    lighter = f"rgb({min(255, int(r * 255) + 30)},{min(255, int(g * 255) + 30)},{min(255, int(b * 255) + 30)})"
    base = f"rgb({int(r * 255)},{int(g * 255)},{int(b * 255)})"
    font_size = 30 if len(text) < 3 else 23

    ring_svg = ""
    if sweep_pct >= 0:
        cx, cy, radius = 32, 32, 27.5
        circumference = 2 * math.pi * radius
        arc_len = max(0.05, min(circumference - 0.05, circumference * (sweep_pct / 100.0)))
        arc_alpha = 0.78 + 0.22 * pulse
        stroke_w = 5.0 + 0.8 * pulse
        ring_svg = f"""
  <circle cx="{cx}" cy="{cy}" r="{radius}" fill="none" stroke="rgba(128,128,128,0.30)" stroke-width="4.5"/>
  <circle cx="{cx}" cy="{cy}" r="{radius}" fill="none" stroke="rgba(255,255,255,{arc_alpha:.2f})"
          stroke-width="{stroke_w:.1f}" stroke-linecap="round"
          stroke-dasharray="{arc_len:.2f} {circumference:.2f}"
          transform="rotate(-90 {cx} {cy})"/>"""

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{lighter}"/>
      <stop offset="100%" stop-color="{base}"/>
    </linearGradient>
  </defs>
  <circle cx="32" cy="32" r="21" fill="url(#g)" stroke="rgba(0,0,0,0.35)" stroke-width="1.5"/>{ring_svg}
  <text x="32.5" y="33.5" font-family="sans-serif" font-size="{font_size}" font-weight="bold"
        fill="rgba(0,0,0,0.35)" text-anchor="middle" dominant-baseline="central">{text}</text>
  <text x="32" y="32" font-family="sans-serif" font-size="{font_size}" font-weight="bold"
        fill="white" text-anchor="middle" dominant-baseline="central">{text}</text>
</svg>"""
    with open(path, "w", encoding="utf-8") as f:
        f.write(svg)
    return path


class UsageTray:
    def __init__(self):
        self._icon_toggle = 0
        self.indicator = AppIndicator3.Indicator.new(
            "claude-usage-on-icon",
            render_icon_svg("?", COLOR_GREY, -1, 0, ICON_PATHS[0]),
            AppIndicator3.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        self.details_text = "No data yet. Send one message in Claude Code (signed in with a Pro/Max plan)."

        # Animation state: the 15s poll (self.update) only decides WHAT to
        # show (target %, color, text); a separate fast tick eases the ring
        # toward it and pulses under critical/over-limit conditions.
        self.target_pct = 0.0
        self.display_pct = 0.0
        self.center_text = "?"
        self.badge_color = COLOR_GREY
        self.show_ring = False
        self.pulse_on = False
        self.pulse_t = 0.0
        self.tooltip = f"claude-usage-on-icon v{TRAY_VERSION}"

        self.menu = Gtk.Menu()
        self.version_item = Gtk.MenuItem(label=f"Claude usage on icon v{TRAY_VERSION}")
        self.version_item.connect("activate", self.open_repo)
        self.menu.append(self.version_item)
        self.menu.append(Gtk.SeparatorMenuItem())

        details_item = Gtk.MenuItem(label="Show details")
        details_item.connect("activate", self.show_details)
        self.menu.append(details_item)

        refresh_item = Gtk.MenuItem(label="Refresh now")
        refresh_item.connect("activate", lambda _: self.update())
        self.menu.append(refresh_item)

        open_item = Gtk.MenuItem(label="Open .claude folder")
        open_item.connect("activate", self.open_folder)
        self.menu.append(open_item)

        self.menu.append(Gtk.SeparatorMenuItem())
        website_item = Gtk.MenuItem(label="yasinnerten.com")
        website_item.connect("activate", self.open_website)
        self.menu.append(website_item)

        self.menu.append(Gtk.SeparatorMenuItem())
        exit_item = Gtk.MenuItem(label="Exit")
        exit_item.connect("activate", lambda _: Gtk.main_quit())
        self.menu.append(exit_item)

        self.menu.show_all()
        self.indicator.set_menu(self.menu)

        self.update()
        self.animate_frame()
        GLib.timeout_add_seconds(POLL_SECONDS, self._poll_tick)
        GLib.timeout_add(ANIM_INTERVAL_MS, self._anim_tick)

    def _poll_tick(self):
        self.update()
        return True  # keep the timeout running

    def _anim_tick(self):
        self.animate_frame()
        return True

    def open_folder(self, _):
        import subprocess

        subprocess.Popen(["xdg-open", CLAUDE_DIR])

    def open_website(self, _):
        import subprocess

        subprocess.Popen(["xdg-open", "https://yasinnerten.com"])

    def open_repo(self, _):
        import subprocess

        subprocess.Popen(["xdg-open", REPO_URL])

    def show_details(self, _):
        dialog = Gtk.MessageDialog(
            transient_for=None,
            flags=0,
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.OK,
            text="Claude usage on icon",
        )
        dialog.format_secondary_text(self.details_text)
        dialog.run()
        dialog.destroy()

    def animate_frame(self):
        delta = self.target_pct - self.display_pct
        if abs(delta) < 0.15:
            self.display_pct = self.target_pct
        else:
            self.display_pct += delta * 0.35

        pulse = 0.0
        if self.pulse_on:
            self.pulse_t += 0.22
            pulse = 0.5 + 0.5 * math.sin(self.pulse_t)
        else:
            self.pulse_t = 0.0

        sweep = self.display_pct if self.show_ring else -1
        path = ICON_PATHS[self._icon_toggle]
        self._icon_toggle = 1 - self._icon_toggle
        render_icon_svg(self.center_text, self.badge_color, sweep, pulse, path)
        self.indicator.set_icon_full(path, self.tooltip)

    def update(self):
        cache = read_cache()

        if cache and cache.get("schema_error"):
            self.center_text = "!"
            self.badge_color = COLOR_SCHEMA_ERR
            self.target_pct = 0.0
            self.show_ring = False
            self.pulse_on = False
            self.tooltip = f"claude-usage-on-icon v{TRAY_VERSION} - schema error"
            self.details_text = cache["schema_error"]
            return

        rate_limits = (cache or {}).get("rate_limits")
        if not cache or not rate_limits:
            self.center_text = "?"
            self.badge_color = COLOR_GREY
            self.target_pct = 0.0
            self.show_ring = False
            self.pulse_on = False
            self.tooltip = f"v{TRAY_VERSION} Claude usage: no data yet"
            return

        fh = get_window(rate_limits.get("five_hour"))
        wk = get_window(rate_limits.get("seven_day"))
        age_seconds = time.time() - cache.get("written_at", 0)
        stale = age_seconds >= STALE_HOURS * 3600

        worst = max((w["pct"] for w in (fh, wk) if w), default=0)
        if stale:
            color = COLOR_GREY
        elif worst >= CRIT_PCT:
            color = COLOR_CRIT
        elif worst >= WARN_PCT:
            color = COLOR_WARN
        else:
            color = COLOR_OK

        main = fh or wk
        if main is None:
            num = "-"
        elif main["pct"] >= 100:
            num = "!"
        else:
            num = f"{main['pct']:.0f}"

        self.center_text = num
        self.badge_color = color
        self.target_pct = 0.0 if main is None else min(100.0, main["pct"])
        self.show_ring = (main is not None) and not stale
        self.pulse_on = (not stale) and (worst >= CRIT_PCT or (main is not None and main["pct"] >= 100))

        fh_txt = "n/a" if fh is None else ("reset" if fh["is_reset"] else f"{fh['pct']:.0f}% @{format_when(fh['reset_epoch'])}")
        wk_txt = "n/a" if wk is None else ("reset" if wk["is_reset"] else f"{wk['pct']:.0f}%")
        self.tooltip = f"v{TRAY_VERSION} 5h {fh_txt} | wk {wk_txt} | {format_age(age_seconds)}"

        lines = []
        if fh is not None:
            if fh["is_reset"]:
                lines.append(f"5-hour: window reset at {format_when(fh['reset_epoch'])} (new % after your next message)")
            else:
                lines.append(f"5-hour: {fh['pct']:.1f}% used, resets {format_when(fh['reset_epoch'])}")
        if wk is not None:
            if wk["is_reset"]:
                lines.append(f"Weekly: window reset at {format_when(wk['reset_epoch'])}")
            else:
                lines.append(f"Weekly: {wk['pct']:.1f}% used, resets {format_when(wk['reset_epoch'])}")
        lines.append(f"Updated {format_age(age_seconds)} (from Claude Code status line)")
        lines.append(f"Source: {cache.get('source')} | schema {cache.get('schema')} | writer v{cache.get('writer_version')}")
        lines.append(f"Tray v{TRAY_VERSION} | file: {CACHE_FILE}")
        if stale:
            lines.append("Stale: open Claude Code and send a message to refresh.")
        lines.append("claude-usage-on-icon - yasinnerten.com")
        self.details_text = "\n".join(lines)


def main():
    UsageTray()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
