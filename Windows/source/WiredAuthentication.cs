using System.Diagnostics;

namespace CampusConnect;

internal sealed record BroadbandEntry(string Name, string PhonebookPath);
internal sealed record SystemNetworkCommand(string Executable, string[] Arguments);

// Reuse the user's Windows network profiles; credentials and EAP certificates stay in Windows.
internal static class WiredAuthentication
{
    public static IReadOnlyList<BroadbandEntry> ReadBroadbandEntries()
    {
        var entries = new List<BroadbandEntry>();
        foreach (var directory in new[] { Environment.SpecialFolder.ApplicationData, Environment.SpecialFolder.CommonApplicationData }) {
            var file = Path.Combine(Environment.GetFolderPath(directory), "Microsoft", "Network", "Connections", "Pbk", "rasphone.pbk");
            try { if (File.Exists(file)) entries.AddRange(ParsePhonebook(File.ReadAllText(file), file)); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        }
        // Prefer the current user's entry if the same name also exists in the all-users phonebook.
        return entries.DistinctBy(e => e.Name, StringComparer.OrdinalIgnoreCase).ToArray();
    }

    internal static IReadOnlyList<BroadbandEntry> ParsePhonebook(string text, string file)
    {
        var result = new List<BroadbandEntry>();
        string? name = null;
        var broadband = false;
        void Add() { if (broadband && !string.IsNullOrWhiteSpace(name)) result.Add(new(name, file)); }
        foreach (var raw in text.Split('\n')) {
            var line = raw.Trim();
            if (line.StartsWith('[') && line.EndsWith(']')) {
                Add(); name = line[1..^1]; broadband = false;
            } else if (name is not null) {
                var pair = line.Split('=', 2);
                // RASET_Broadband = 5. Never dial a VPN or analog entry with a matching display name.
                if (pair.Length == 2 && pair[0].Trim().Equals("Type", StringComparison.OrdinalIgnoreCase))
                    broadband = pair[1].Trim() == "5";
            }
        }
        Add();
        return result;
    }

    internal static SystemNetworkCommand BuildCommand(CampusProfile profile, string interfaceName,
        IReadOnlyList<BroadbandEntry> entries, string systemDirectory)
    {
        if (!profile.IsWired || !profile.UsesSystemAuthentication)
            throw new InvalidOperationException("当前配置未选择有线系统认证。");
        if (profile.WiredAuth == "pppoe") {
            var entry = entries.FirstOrDefault(e => e.Name.Equals(profile.BroadbandName, StringComparison.OrdinalIgnoreCase))
                ?? throw new InvalidOperationException("未找到该 PPPoE 宽带连接。请先在 Windows 创建宽带连接、保存账号密码，再选择对应连接名称。");
            if (entry.Name.StartsWith('/') || entry.Name.Any(char.IsControl))
                throw new InvalidOperationException("宽带连接名称无效，请在 Windows 中重新命名该连接。");
            return new(Path.Combine(systemDirectory, "rasdial.exe"), [entry.Name, "/PHONEBOOK:" + entry.PhonebookPath]);
        }
        if (profile.WiredAuth == "dot1x") {
            if (string.IsNullOrWhiteSpace(interfaceName))
                throw new InvalidOperationException("请先选择需要认证的以太网接口。");
            return new(Path.Combine(systemDirectory, "netsh.exe"), ["lan", "reconnect", "interface=" + interfaceName]);
        }
        throw new InvalidOperationException("专用客户端通过已选程序启动。");
    }

    public static async Task<string> ConnectAsync(CampusProfile profile, string interfaceName, CancellationToken cancellationToken)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("系统认证需要 Windows。");
        cancellationToken.ThrowIfCancellationRequested();
        if (profile.WiredAuth == "client") {
            var file = profile.AuthenticationClient;
            if (!Path.IsPathFullyQualified(file) || !file.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) || !File.Exists(file))
                throw new InvalidOperationException("请先选择学校已安装的认证客户端 EXE 文件。");
            foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(file))) {
                using (process) {
                    try {
                        if (string.Equals(process.MainModule?.FileName, file, StringComparison.OrdinalIgnoreCase))
                            return "认证客户端已在运行，请在客户端内完成登录。";
                    } catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException) {
                        // Do not repeatedly start clients whose elevated process cannot be inspected.
                        return "检测到同名认证客户端，请先检查其窗口并完成登录。";
                    }
                }
            }
            cancellationToken.ThrowIfCancellationRequested();
            using var started = Process.Start(new ProcessStartInfo(file) { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(file)! });
            if (started is null) throw new InvalidOperationException("无法启动学校认证客户端。");
            return "学校认证客户端已打开，请在客户端内完成登录；助手将继续检查联网状态。";
        }
        var command = BuildCommand(profile, interfaceName, ReadBroadbandEntries(), Environment.SystemDirectory);
        var exitCode = await RunAsync(command, cancellationToken);
        if (exitCode != 0) throw new InvalidOperationException(profile.WiredAuth == "pppoe"
            ? $"Windows PPPoE 拨号失败（错误码 {exitCode}）。请检查系统保存的账号密码、网线及宽带连接设置。"
            : $"Windows 802.1X 认证请求失败（错误码 {exitCode}）。请检查以太网认证配置、Wired AutoConfig 服务和运行权限。");
        return profile.WiredAuth == "pppoe" ? "Windows 拨号已完成，正在检查实际联网状态。"
            : "已向所选以太网接口发起 802.1X 认证，正在检查实际联网状态。";
    }

    private static async Task<int> RunAsync(SystemNetworkCommand command, CancellationToken cancellationToken)
    {
        var start = new ProcessStartInfo(command.Executable) {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true
        };
        foreach (var argument in command.Arguments) start.ArgumentList.Add(argument);
        using var process = new Process { StartInfo = start };
        if (!process.Start()) throw new InvalidOperationException("无法启动 Windows 网络认证。");
        // No account or password is passed on a command line, logged, or sent to the UI.
        process.StandardInput.Close();
        var output = process.StandardOutput.ReadToEndAsync();
        var error = process.StandardError.ReadToEndAsync();
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(60));
        try { await process.WaitForExitAsync(deadline.Token); }
        catch (OperationCanceledException) {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { }
            await process.WaitForExitAsync();
            await Task.WhenAll(output, error);
            if (cancellationToken.IsCancellationRequested) throw;
            throw new TimeoutException("Windows 网络认证超时，请先检查系统连接设置后重试。");
        }
        await Task.WhenAll(output, error);
        return process.ExitCode;
    }
}
