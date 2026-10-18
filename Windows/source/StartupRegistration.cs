using Microsoft.Win32;
using System.Runtime.Versioning;

namespace CampusConnect;

[SupportedOSPlatform("windows")]
internal sealed class StartupRegistration(string executablePath,
    string keyPath = @"Software\Microsoft\Windows\CurrentVersion\Run")
{
    internal const string ValueName = "CampusConnect.Windows";
    internal string Command => $"\"{executablePath}\" --startup";

    public bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(keyPath);
        return string.Equals(key?.GetValue(ValueName) as string, Command, StringComparison.OrdinalIgnoreCase);
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled) {
            if (Command.Length > 260 || executablePath.Contains('"'))
                throw new InvalidOperationException("安装路径太长或包含无效字符，无法设置开机自启。请安装到较短的路径。");
            using var key = Registry.CurrentUser.CreateSubKey(keyPath, writable: true)
                ?? throw new InvalidOperationException("无法写入当前用户的启动项。");
            key.SetValue(ValueName, Command, RegistryValueKind.String);
        } else {
            using var key = Registry.CurrentUser.OpenSubKey(keyPath, writable: true);
            key?.DeleteValue(ValueName, throwOnMissingValue: false);
        }
        if (IsEnabled() != enabled) throw new IOException("启动项未能保存，请检查 Windows 权限。");
    }
}
