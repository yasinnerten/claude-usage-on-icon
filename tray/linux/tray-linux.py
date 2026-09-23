#!/usr/bin/env python3
# tray-linux.py
# Version: 1.0.0
# Linux tray icon for Claude Code plan usage (GTK 3 + AppIndicator, stdlib + gi only).
#
# Reads ONLY <cache dir>/usage-cache.json, which statusline.py writes from the
# `rate_limits` data Claude Code already gives the status line.
#
# What it does NOT do: no network calls, no credential access. The only files
# it writes are alert-config.json (only when you set an alert threshold) and
# two small temporary SVG icons under $XDG_RUNTIME_DIR (see ICON_PATHS below -
# alternated each animation frame, not accumulated).
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
ALERT_CONFIG_FILE = os.path.join(CLAUDE_DIR, "alert-config.json")
ICON_DIR = icon_runtime_dir()
# Some StatusNotifierItem hosts don't reliably notice a same-path file change
# on rapid redraws; alternating between two paths forces a reload every frame.
ICON_PATHS = (os.path.join(ICON_DIR, "icon-a.svg"), os.path.join(ICON_DIR, "icon-b.svg"))

COLOR_OK = (0.12, 0.55, 0.27)
COLOR_WARN = (0.84, 0.55, 0.0)
COLOR_CRIT = (0.78, 0.16, 0.16)
COLOR_GREY = (0.47, 0.47, 0.47)
COLOR_SCHEMA_ERR = (0.63, 0.16, 0.63)


def read_alert_threshold():
    # Shared JSON config, also read/written by the Windows tray and macOS
    # plugin - same schema everywhere: {"threshold_pct": 80}, 0/missing = off.
    if not os.path.exists(ALERT_CONFIG_FILE):
        return 0.0
    try:
        with open(ALERT_CONFIG_FILE, encoding="utf-8") as f:
            cfg = json.load(f)
        return float(cfg.get("threshold_pct") or 0)
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        return 0.0


def save_alert_threshold(pct):
    try:
        os.makedirs(CLAUDE_DIR, exist_ok=True)
        with open(ALERT_CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump({"threshold_pct": pct}, f)
    except OSError:
        pass


def send_notification(title, text):
    import shutil
    import subprocess

    notify_send = shutil.which("notify-send")
    if not notify_send:
        return  # no libnotify on this system; fail quietly, not a crash
    try:
        subprocess.Popen([notify_send, "--urgency=normal", "--app-name=claude-usage-on-icon", title, text])
    except OSError:
        pass


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


def _pie_path(cx, cy, radius, sweep_deg):
    sweep_deg = min(359.9, max(0.5, sweep_deg))
    angle_rad = math.radians(sweep_deg)
    end_x = cx + radius * math.sin(angle_rad)
    end_y = cy - radius * math.cos(angle_rad)
    large_arc = 1 if sweep_deg > 180 else 0
    return f"M {cx},{cy} L {cx},{cy - radius} A {radius},{radius} 0 {large_arc},1 {end_x:.2f},{end_y:.2f} Z"


def render_icon_svg(text, rgb, sweep_pct, pulse, path):
    """sweep_pct: -1 for a plain filled circle (e.g. '?' state), else 0..100
    for a pie-fill wedge. pulse: 0..1.

    Usage is drawn as a filled pie wedge (like a clock face filling in), not
    a thin outline ring: a thin stroke risks disappearing once this SVG is
    rasterized down to the ~16-24px the tray actually displays, but a large
    solid-color region survives that rasterization easily - which is what
    actually makes the animation visible at tray size.
    """
    r, g, b = rgb
    cx, cy, radius = 32, 32, 29
    font_size = 40 if len(text) < 2 else 30

    if sweep_pct >= 0:
        track = f"rgb({int(r * 255 * 0.35 + 40)},{int(g * 255 * 0.35 + 40)},{int(b * 255 * 0.35 + 40)})"
        boost = int(25 * pulse)
        fill = f"rgb({min(255, int(r * 255) + boost)},{min(255, int(g * 255) + boost)},{min(255, int(b * 255) + boost)})"
        sweep_deg = 360.0 * (sweep_pct / 100.0)
        badge_svg = f'<circle cx="{cx}" cy="{cy}" r="{radius}" fill="{track}"/>'
        if sweep_pct > 0:
            badge_svg += f'<path d="{_pie_path(cx, cy, radius, sweep_deg)}" fill="{fill}"/>'
    else:
        base = f"rgb({int(r * 255)},{int(g * 255)},{int(b * 255)})"
        badge_svg = f'<circle cx="{cx}" cy="{cy}" r="{radius}" fill="{base}"/>'

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
  {badge_svg}
  <circle cx="{cx}" cy="{cy}" r="{radius}" fill="none" stroke="rgba(0,0,0,0.35)" stroke-width="2"/>
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

        self.alert_threshold = read_alert_threshold()
        self.alerted_five_hour = False
        self.alerted_seven_day = False

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
        self.alert_item = Gtk.MenuItem(label="Set alert threshold...")
        self.alert_item.connect("activate", self.show_alert_prompt)
        self.menu.append(self.alert_item)
        self._update_alert_menu_label()

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

    def _update_alert_menu_label(self):
        if self.alert_threshold > 0:
            self.alert_item.set_label(f"Set alert threshold... (currently {int(self.alert_threshold)}%)")
        else:
            self.alert_item.set_label("Set alert threshold... (currently off)")

    def show_alert_prompt(self, _):
        dialog = Gtk.Dialog(title="Claude usage alert threshold", transient_for=None, flags=0)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OK, Gtk.ResponseType.OK)

        box = dialog.get_content_area()
        label = Gtk.Label(label="Notify me when either window's usage reaches (0 = off):")
        label.set_margin_start(10)
        label.set_margin_end(10)
        label.set_margin_top(10)
        box.add(label)

        adjustment = Gtk.Adjustment(value=self.alert_threshold, lower=0, upper=100, step_increment=5)
        spin = Gtk.SpinButton(adjustment=adjustment, numeric=True)
        spin.set_margin_start(10)
        spin.set_margin_end(10)
        spin.set_margin_bottom(10)
        box.add(spin)

        dialog.show_all()
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            pct = float(spin.get_value())
            self.alert_threshold = pct
            self.alerted_five_hour = False
            self.alerted_seven_day = False
            save_alert_threshold(pct)
            self._update_alert_menu_label()
        dialog.destroy()

    def _test_alert_window(self, label, window, already_alerted_attr):
        # Fires a notification the first time a window crosses the configured
        # threshold, and arms it again once that window resets (usage only
        # ever climbs within a window, so no need to re-arm on a mere dip).
        if window is None or self.alert_threshold <= 0:
            return
        if window["is_reset"]:
            setattr(self, already_alerted_attr, False)
            return
        if window["pct"] >= self.alert_threshold and not getattr(self, already_alerted_attr):
            setattr(self, already_alerted_attr, True)
            send_notification(
                "Claude usage alert",
                f"{label} usage reached {window['pct']:.0f}% (alert set at {int(self.alert_threshold)}%)",
            )

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

        if not stale:
            self._test_alert_window("5-hour", fh, "alerted_five_hour")
            self._test_alert_window("Weekly", wk, "alerted_seven_day")

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
