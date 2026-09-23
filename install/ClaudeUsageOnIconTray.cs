// ClaudeUsageOnIconTray.cs
// Version: 1.0.0
//
// A tiny, auditable launcher, compiled locally (by install-windows.ps1, via
// the csc.exe already built into every Windows install - no download, no
// binary committed to this repo) into ClaudeUsageOnIconTray.exe.
//
// All it does: resolve the same cache-dir path the writer/tray already use,
// then start tray-windows.ps1 hidden. That's it - no cache reads, no network,
// no file writes of its own. This exists only so starting the tray is a real
// double-clickable .exe (also the Startup-shortcut target) instead of a
// PowerShell command line with -ExecutionPolicy Bypass in it.
//
// Compiled with /target:winexe, so it has no console window of its own.

using System;
using System.Diagnostics;
using System.IO;

internal static class ClaudeUsageOnIconTray
{
    private static void Main()
    {
        string claudeDir = Environment.GetEnvironmentVariable("CLAUDE_USAGE_ICON_DIR");
        if (string.IsNullOrEmpty(claudeDir))
        {
            claudeDir = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
        }
        if (string.IsNullOrEmpty(claudeDir))
        {
            string userProfile = Environment.GetEnvironmentVariable("USERPROFILE");
            claudeDir = Path.Combine(userProfile, ".claude");
        }

        string scriptPath = Path.Combine(claudeDir, "tray-windows.ps1");
        if (!File.Exists(scriptPath))
        {
            MessageBoxHelper.Show(
                "Could not find tray-windows.ps1 at:\n" + scriptPath +
                "\n\nRe-run install-windows.ps1 to reinstall it.");
            return;
        }

        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        };

        try
        {
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            MessageBoxHelper.Show("Failed to start the tray:\n" + ex.Message);
        }
    }
}

// A minimal P/Invoke MessageBox wrapper so this stays a single .cs file with
// no extra assembly reference (System.Windows.Forms would work too, but this
// keeps the compile command simpler).
internal static class MessageBoxHelper
{
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern int MessageBox(IntPtr hWnd, string text, string caption, uint type);

    public static void Show(string text)
    {
        MessageBox(IntPtr.Zero, text, "Claude usage on icon", 0);
    }
}
