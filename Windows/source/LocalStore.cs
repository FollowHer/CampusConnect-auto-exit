using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CampusConnect;

internal static class LocalStore
{
    public static string DirectoryPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CampusConnect");
    private static string FilePath => Path.Combine(DirectoryPath, "configuration.json");
    private sealed record Configuration(CampusProfile Profile, string ProtectedPassword);
    public static (CampusProfile Profile, string Password) Load()
    {
        if (!File.Exists(FilePath)) return (new(), "");
        var config = JsonSerializer.Deserialize<Configuration>(File.ReadAllText(FilePath))
            ?? throw new InvalidDataException("配置文件为空。");
        config.Profile.Validate();
        var password = string.IsNullOrEmpty(config.ProtectedPassword) ? "" : Encoding.UTF8.GetString(
            ProtectedData.Unprotect(Convert.FromBase64String(config.ProtectedPassword), null, DataProtectionScope.CurrentUser));
        return (config.Profile, password);
    }
    public static void Save(CampusProfile profile, string password)
    {
        profile.Validate();
        Directory.CreateDirectory(DirectoryPath);
        var protectedPassword = string.IsNullOrEmpty(password) ? "" : Convert.ToBase64String(
            ProtectedData.Protect(Encoding.UTF8.GetBytes(password), null, DataProtectionScope.CurrentUser));
        var temporary = Path.Combine(DirectoryPath, $"configuration-{Guid.NewGuid():N}.tmp");
        try {
            File.WriteAllText(temporary, JsonSerializer.Serialize(new Configuration(profile, protectedPassword),
                new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, FilePath, true);
        } finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
