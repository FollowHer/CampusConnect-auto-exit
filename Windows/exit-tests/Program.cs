using System.Reflection;
using CampusConnect;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        var type = typeof(CampusProfile).Assembly.GetType("CampusConnect.MainForm", throwOnError: true)!;
        const BindingFlags flags = BindingFlags.NonPublic | BindingFlags.Instance;
        var saved = type.GetField("saved", flags)!;
        var generation = type.GetField("generation", flags)!;
        var tryExit = type.GetMethod("TryExitAfterConnected", flags)!;
        var exit = type.GetMethod("ExitApplication", flags)!;
        var checks = 0;
        void Expect(bool condition, string message) { checks++; if (!condition) throw new Exception(message); }
        foreach (var wired in new[] { false, true })
        foreach (var enabled in new[] { false, true })
        foreach (var settings in new[] { false, true })
        foreach (var connected in new[] { false, true })
        foreach (var fresh in new[] { false, true })
        foreach (var result in new[] { InternetStatus.Unavailable, InternetStatus.Online }) {
            using var form = (Form)Activator.CreateInstance(type, new object?[] { null, false, settings })!;
            _ = form.Handle;
            saved.SetValue(form, new CampusProfile { Ssid = wired ? "" : "HNPI-STU", ExitAfterConnected = enabled });
            generation.SetValue(form, 7);
            var shouldExit = enabled && !settings && connected && fresh && result == InternetStatus.Online;
            var didExit = (bool)tryExit.Invoke(form, new object[] { fresh ? 7 : 6, connected, result })!;
            Expect(didExit == shouldExit, "Exit decision must require enabled + target connected + current generation + internet online.");
            Expect(form.IsDisposed == shouldExit, "Successful auto exit must dispose the window instead of hiding it.");
            if (shouldExit) {
                var shell = (Control)type.GetField("shell", flags)!.GetValue(form)!;
                var portal = type.GetField("portal", flags)!.GetValue(form)!;
                var view = (Control)portal.GetType().GetProperty("View")!.GetValue(portal)!;
                Expect(shell.IsDisposed && view.IsDisposed, "Both WebView controls must be disposed.");
                Expect(!(bool)tryExit.Invoke(form, new object[] { 7, true, result })!, "Auto exit must be idempotent.");
            } else exit.Invoke(form, null);
            Expect(form.IsDisposed, "Explicit exit must dispose all test forms.");
        }
        // A regular close must still retain the original tray behavior when auto exit is not requested.
        using (var form = (Form)Activator.CreateInstance(type, new object?[] { null, false, false })!) {
            _ = form.Handle;
            form.Close();
            Expect(!form.IsDisposed, "Window close keeps the tray session alive.");
            exit.Invoke(form, null);
            Expect(form.IsDisposed, "Explicit exit bypasses close-to-tray.");
        }
        // Exercise the same exit with a running WinForms message loop and initialized WebView2.
        // Mark configuration as loaded so the UI ready message never starts real network work.
        using (var liveForm = (Form)Activator.CreateInstance(type, new object?[] { "unused-verification-path", true, false })!) {
            saved.SetValue(liveForm, new CampusProfile { ExitAfterConnected = true });
            type.GetField("configurationLoaded", flags)!.SetValue(liveForm, true);
            using var watcher = new System.Windows.Forms.Timer { Interval = 50 };
            var deadline = DateTime.UtcNow.AddSeconds(25);
            bool liveExit = false;
            Exception? failure = null;
            watcher.Tick += (_, _) => {
                try {
                    if ((bool)type.GetField("uiReady", flags)!.GetValue(liveForm)!) {
                        watcher.Stop();
                        liveExit = (bool)tryExit.Invoke(liveForm, new object[] { 0, true, InternetStatus.Online })!;
                    } else if (DateTime.UtcNow >= deadline) {
                        watcher.Stop();
                        failure = new Exception("WebView2 initialization timed out.");
                        exit.Invoke(liveForm, null);
                    }
                } catch (Exception ex) { watcher.Stop(); failure = ex; exit.Invoke(liveForm, null); }
            };
            watcher.Start();
            Application.Run(liveForm);
            if (failure is not null) throw failure;
            Expect(liveExit && liveForm.IsDisposed, "Online confirmation must end the live application message loop.");
            var shell = (Control)type.GetField("shell", flags)!.GetValue(liveForm)!;
            var portal = type.GetField("portal", flags)!.GetValue(liveForm)!;
            var view = (Control)portal.GetType().GetProperty("View")!.GetValue(portal)!;
            Expect(shell.IsDisposed && view.IsDisposed, "Initialized WebViews must be disposed on automatic exit.");
        }
        Console.WriteLine($"PASS: {checks} Windows lifecycle assertions (64 network/settings combinations + live WebView2 exit).");
    }
}
