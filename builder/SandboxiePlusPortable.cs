// Community launcher for the OFFICIAL portable Sandboxie Plus extraction.
// Does not install/uninstall any driver itself. SandMan's built-in portable mode handles that.
// Requires Windows .NET Framework 4.x. Source: Sandboxie Plus 1.18.8 design review.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class SandboxiePlusPortable
{
    static readonly string[] ConfigNames = { "Sandboxie.ini", "Sandboxie-Plus.ini" };
    static readonly object Gate = new object();
    static string root, app, data, settings;

    [STAThread]
    static int Main(string[] arguments)
    {
        root = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
        app = Path.Combine(root, @"App\SandboxiePlus");
        data = Path.Combine(root, "Data");
        settings = Path.Combine(data, "Settings");
        string sandman = Path.Combine(app, "SandMan.exe");
        try
        {
            if (!File.Exists(sandman) || !File.Exists(Path.Combine(app, "SbieDrv.sys")) ||
                !File.Exists(Path.Combine(app, "SbieSvc.exe")))
            {
                Alert("The package is incomplete. Extract the full ZIP before launching.");
                return 2;
            }
            // Never interfere with another Sandboxie installation or orphaned driver/service.
            if (IsServiceRegistered("SbieDrv") || IsServiceRegistered("SbieSvc"))
            {
                Alert("A Sandboxie driver/service is already registered on this PC.\n\n" +
                    "Do NOT run two installations together. If this is left over from a prior " +
                    "portable run, use Sandboxie Plus > Maintenance > Uninstall All " +
                    "or ask an administrator to inspect it. This launcher will NOT remove it.");
                return 3;
            }
            Directory.CreateDirectory(settings);
            Directory.CreateDirectory(Path.Combine(data, "Sandboxes"));
            Directory.CreateDirectory(Path.Combine(data, "Logs"));
            // Refuse startup if source already contains working INI files with newer data.
            foreach (string n in ConfigNames)
            {
                string working = Path.Combine(app, n);
                string saved = Path.Combine(settings, n);
                if (File.Exists(working))
                {
                    if (!File.Exists(saved) || File.GetLastWriteTimeUtc(working) > File.GetLastWriteTimeUtc(saved))
                        SaveCopy(working, saved); // crash recovery, never discard newer unsaved settings
                }
                if (!File.Exists(saved))
                    throw new IOException("Missing " + saved + ". Re-extract package without overwriting Data.");
            }
            ConfigureFileRootPath(Path.Combine(settings, "Sandboxie.ini"),
                Path.Combine(data, @"Sandboxes\%USER%\%SANDBOX%"));
            foreach (string n in ConfigNames)
                File.Copy(Path.Combine(settings, n), Path.Combine(app, n), true);

            var start = new ProcessStartInfo(sandman);
            start.WorkingDirectory = app;
            start.UseShellExecute = false;
            // SandMan can create additional programs. Redirect only its own temp/cache variables;
            // the official SandMan handles kernel driver + service setup and teardown.
            string tmp = Path.Combine(data, "Temp");
            Directory.CreateDirectory(tmp);
            start.EnvironmentVariables["TEMP"] = tmp;
            start.EnvironmentVariables["TMP"] = tmp;
            start.EnvironmentVariables["XDG_CACHE_HOME"] = Path.Combine(data, "Cache");
            Directory.CreateDirectory(Path.Combine(data, "Cache"));
            start.Arguments = QuoteArgs(arguments);

            using (var process = Process.Start(start))
            {
                if (process == null) throw new IOException("SandMan.exe could not be launched.");
                // Polling also captures config rewritten through rename/atomic replace and survives
                // file locks better than FileSystemWatcher alone. Use atomic copies to Data.
                while (!process.WaitForExit(1500))
                {
                    SyncConfiguration(false);
                }
                SyncConfiguration(true);
                // Allow some time for built-in driver/service removal; never force deletion.
                for (int i = 0; i < 10 && (IsServiceRegistered("SbieDrv") || IsServiceRegistered("SbieSvc")); i++)
                    Thread.Sleep(1000);
                if (IsServiceRegistered("SbieDrv") || IsServiceRegistered("SbieSvc"))
                {
                    Alert("Sandboxie closed but SbieDrv/SbieSvc is still registered.\n\n" +
                          "Do NOT update or move App. Close sandboxed programs and inspect " +
                          "Sandboxie maintenance/driver status. This launcher will not remove services.");
                    return 4;
                }
                // The actual persistent files are under Data. No working config remains under App.
                foreach (string n in ConfigNames)
                {
                    string working = Path.Combine(app, n);
                    if (File.Exists(working)) File.Delete(working);
                }
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            // Attempt to save config even when startup fails, if files exist.
            try { SyncConfiguration(true); } catch { }
            Alert("Portable launch failed:\n" + ex.Message + "\n\nDo not delete your Data folder.");
            return 1;
        }
    }

    static void Alert(string m) { MessageBox.Show(m, "Sandboxie Plus Portable", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
    static bool IsServiceRegistered(string name)
    {
        using (RegistryKey key = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\" + name))
            return key != null;
    }
    static void SyncConfiguration(bool force)
    {
        lock (Gate)
        {
            if (settings == null || app == null || !Directory.Exists(settings)) return;
            foreach (string n in ConfigNames)
            {
                string working = Path.Combine(app, n);
                string saved = Path.Combine(settings, n);
                if (!File.Exists(working)) continue;
                if (!force && File.Exists(saved) &&
                    File.GetLastWriteTimeUtc(working) <= File.GetLastWriteTimeUtc(saved)) continue;
                for (int attempt = 0; attempt < 3; attempt++)
                {
                    try { SaveCopy(working, saved); break; }
                    catch (IOException) { if (attempt == 2 && force) throw; Thread.Sleep(150); }
                }
            }
        }
    }
    static void SaveCopy(string source, string target)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(target));
        string tmp = target + ".sync-temp";
        File.Copy(source, tmp, true);
        if (File.Exists(target)) File.Replace(tmp, target, null, true);
        else File.Move(tmp, target);
    }
    static void ConfigureFileRootPath(string file, string path)
    {
        byte[] original = File.ReadAllBytes(file);
        Encoding enc = DetectEncoding(original);
        string content = original.Length == 0 ? "" : enc.GetString(original);
        if (content.Length > 0 && content[0] == '\uFEFF') content = content.Substring(1);
        // Official portable installer v1.18.8 ships EMPTY INIs intentionally.
        // Seed the minimum recognized config before the first SandMan launch.
        if (String.IsNullOrWhiteSpace(content))
            content = "[GlobalSettings]\r\n[UserSettings_Portable]\r\n";
        string replacement = "FileRootPath=" + path;
        var section = Regex.Match(content, @"(?im)^\[GlobalSettings\][ \t]*\r?$");
        if (!section.Success) throw new InvalidDataException("Missing [GlobalSettings] in Sandboxie.ini");
        int begin = section.Index + section.Length;
        var next = Regex.Match(content.Substring(begin), @"(?m)^\[[^\r\n]+\][ \t]*\r?$");
        int end = next.Success ? begin + next.Index : content.Length;
        string body = content.Substring(begin, end-begin);
        var setting = new Regex(@"(?im)^FileRootPath\s*=.*$");
        body = setting.IsMatch(body)
            ? setting.Replace(body, delegate(Match m) { return replacement; }, 1)
            : "\r\n" + replacement + "\r\n" + body.TrimStart('\r', '\n');
        string updated = content.Substring(0, begin) + body + content.Substring(end);
        if (updated != content) File.WriteAllText(file, updated, enc);
    }
    static Encoding DetectEncoding(byte[] b)
    {
        if (b.Length >= 2 && b[0] == 0xFF && b[1] == 0xFE) return Encoding.Unicode;
        if (b.Length >= 2 && b[0] == 0xFE && b[1] == 0xFF) return Encoding.BigEndianUnicode;
        if (b.Length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) return new UTF8Encoding(true);
        return Encoding.Unicode; // official Sandboxie.ini is UTF-16
    }
    static string QuoteArgs(string[] args)
    {
        if (args == null || args.Length == 0) return "";
        var sb = new StringBuilder();
        foreach (string arg in args)
        {
            if (sb.Length > 0) sb.Append(' ');
            sb.Append('"').Append(arg.Replace("\\", "\\\\").Replace("\"", "\\\"")).Append('"');
        }
        return sb.ToString();
    }
}
