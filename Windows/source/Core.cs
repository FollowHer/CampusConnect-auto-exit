using System.Text;
using System.Text.Json;

namespace CampusConnect;

public sealed record CampusProfile
{
    public string Ssid { get; init; } = "HNPI-STU";
    [System.Text.Json.Serialization.JsonIgnore]
    public bool IsWired => string.IsNullOrWhiteSpace(Ssid);
    public bool MatchesNetwork(string? currentSsid, bool wiredAvailable)
        => IsWired ? wiredAvailable : currentSsid == Ssid;
    public bool UseSavedWifiProfile { get; init; }
    public bool PortalEnabled { get; init; } = true;
    public string PortalUrl { get; init; } = "http://192.168.0.123";
    public string Username { get; init; } = "";
    public string ServiceOption { get; init; } = "";
    public string UserSelector { get; init; } = "";
    public string PasswordSelector { get; init; } = "";
    public string SubmitSelector { get; init; } = "";
    public bool AutoSubmit { get; init; } = true;
    public bool Automatic { get; init; }

    public static string? Origin(string address)
    {
        if (!Uri.TryCreate(address, UriKind.Absolute, out var uri) ||
            (uri.Scheme != "http" && uri.Scheme != "https") ||
            string.IsNullOrEmpty(uri.Host) || !string.IsNullOrEmpty(uri.UserInfo)) return null;
        return uri.GetLeftPart(UriPartial.Authority).ToLowerInvariant();
    }

    public void Validate()
    {
        if (!IsWired && Encoding.UTF8.GetByteCount(Ssid) > 32)
            throw new InvalidOperationException("Wi-Fi 名称最多为 32 字节；有线模式请留空。");
        if (PortalEnabled && Origin(PortalUrl) is null)
            throw new InvalidOperationException("请输入 http:// 或 https:// 开头的认证地址，不能在地址中包含账号密码。");
    }
}

public sealed class AutoPolicy
{
    public DateTimeOffset LastAttempt { get; private set; } = DateTimeOffset.MinValue;
    public bool ShouldJoin(bool enabled, string target, string? current, IEnumerable<string> visible, bool busy, DateTimeOffset now)
        => enabled && target.Length > 0 && current != target && visible.Contains(target, StringComparer.Ordinal)
            && !busy && now - LastAttempt >= TimeSpan.FromSeconds(60);
    public void Begin(DateTimeOffset now) => LastAttempt = now;
    public void Reset() { LastAttempt = DateTimeOffset.MinValue; }
}

public enum InternetStatus { Online, Unavailable }
public sealed class PortalRecovery
{
    public int Failures { get; private set; }
    public int Attempts { get; private set; }
    public DateTimeOffset LastAttempt { get; private set; } = DateTimeOffset.MinValue;
    public InternetStatus State { get; private set; } = InternetStatus.Unavailable;
    public TimeSpan RetryDelay => TimeSpan.FromSeconds(Math.Min(300, 60 * Math.Pow(2, Math.Max(0, Attempts - 1))));
    public void Observe(InternetStatus result)
    {
        if (result == InternetStatus.Online) Reset();
        else Failures = Math.Min(2, Failures + 1);
        State = result;
    }
    public bool ShouldAuthenticate(bool enabled, bool portalEnabled, DateTimeOffset now)
        => enabled && portalEnabled && State != InternetStatus.Online && ((Attempts == 0 && Failures == 0) || Failures >= 1)
            && now - LastAttempt >= RetryDelay;
    public void Begin(DateTimeOffset now) { LastAttempt = now; Attempts = Math.Min(4, Attempts + 1); }
    public void Reset() { Failures = 0; Attempts = 0; LastAttempt = DateTimeOffset.MinValue; State = InternetStatus.Unavailable; }
}

public static class PortalScript
{
    public static string Build(CampusProfile profile, string password, bool statusOnly = false)
    {
        var origin = CampusProfile.Origin(profile.PortalUrl) ?? throw new InvalidOperationException("认证地址无效。");
        var payload = JsonSerializer.Serialize(new {
            origin, username = profile.Username, password, serviceOption = profile.ServiceOption, userSelector = profile.UserSelector,
            passwordSelector = profile.PasswordSelector, submitSelector = profile.SubmitSelector, submit = profile.AutoSubmit, confirmSubmit = true, statusOnly
        });
        using var stream = typeof(PortalScript).Assembly.GetManifestResourceStream("CampusConnect.PortalTemplate.js")
            ?? throw new InvalidOperationException("缺少认证脚本。");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd().Replace("/*CAMPUS_CONFIG*/", payload, StringComparison.Ordinal);
    }
}
