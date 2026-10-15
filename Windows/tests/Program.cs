using CampusConnect;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Xml.Linq;

var checks = 0;
void Expect(bool condition, string message) { checks++; if (!condition) throw new Exception("FAIL: " + message); }
void Invalid(CampusProfile profile) {
    try { profile.Validate(); } catch (InvalidOperationException) { checks++; return; }
    throw new Exception("Invalid profile accepted.");
}
var profile = new CampusProfile(); profile.Validate();
Expect(profile.ServiceOption == "", "service selection defaults to blank");
var serviceProfile = JsonSerializer.Deserialize<CampusProfile>(JsonSerializer.Serialize(profile with { ServiceOption = "联通接入服务" }))!;
Expect(serviceProfile.ServiceOption == "联通接入服务", "service selection survives configuration round trip");
Expect(!profile.Automatic, "automation off for first launch");

// Previous API/browser selections are ignored on upgrade, preserving the web form settings.
foreach (var oldMethod in new[] { "direct", "browser" }) {
    var legacy = JsonSerializer.Deserialize<CampusProfile>(JsonSerializer.Serialize(new {
        Ssid = "HNPI-STU", Username = "kept-account", PortalUrl = "http://192.0.2.1/eportal/",
        LoginMethod = oldMethod, ServiceName = "legacy-service", AutoSubmit = false,
        Automatic = true, UserSelector = "#username", PasswordSelector = "#pwd"
    }))!;
    legacy.Validate();
    Expect(legacy.Username == "kept-account" && legacy.PortalUrl == "http://192.0.2.1/eportal/", "upgrade preserves account and portal");
    Expect(legacy.Automatic && !legacy.AutoSubmit && legacy.PasswordSelector == "#pwd", "upgrade preserves automation and browser settings");
    using var migrated = JsonDocument.Parse(JsonSerializer.Serialize(legacy));
    Expect(!migrated.RootElement.TryGetProperty("LoginMethod", out _) && !migrated.RootElement.TryGetProperty("ServiceName", out _), "saving drops obsolete API settings");
    Expect(PortalScript.Build(legacy, "dummy-secret").Contains("dummy-secret"), "upgraded configuration builds browser authentication script");
}

Invalid(profile with { Ssid = "" });
Invalid(profile with { Ssid = new string('网', 11) });
Invalid(profile with { PortalUrl = "javascript:alert(1)" });
Invalid(profile with { PortalUrl = "https://user:secret@example.com" });
Expect(CampusProfile.Origin("http://EXAMPLE.com:80/a") == "http://example.com", "default port normalization");
Expect(CampusProfile.Origin("https://example.com:8443/a") == "https://example.com:8443", "port retained");
Expect(CampusProfile.Origin("http://[::1]/") == "http://[::1]", "IPv6 origin");
var policy = new AutoPolicy(); var now = DateTimeOffset.UtcNow;
Expect(policy.ShouldJoin(true, "HNPI-STU", "Home", ["HNPI-STU"], false, now), "visible target");
Expect(!policy.ShouldJoin(true, "HNPI-STU", null, ["HNPI-STU-fake"], false, now), "exact SSID");
Expect(!policy.ShouldJoin(false, "HNPI-STU", null, ["HNPI-STU"], false, now), "pause");
Expect(!policy.ShouldJoin(true, "HNPI-STU", "HNPI-STU", ["HNPI-STU"], false, now), "already connected");
Expect(!policy.ShouldJoin(true, "HNPI-STU", null, ["HNPI-STU"], true, now), "busy guard");
policy.Begin(now);
Expect(!policy.ShouldJoin(true, "HNPI-STU", null, ["HNPI-STU"], false, now.AddSeconds(59)), "cooldown");
Expect(policy.ShouldJoin(true, "HNPI-STU", null, ["HNPI-STU"], false, now.AddSeconds(61)), "retry interval");
for (var i = 1; i <= 1000; i++) {
    policy.Fail();
    var retryAt = now.AddSeconds(60 * i);
    Expect(policy.ShouldJoin(true, "HNPI-STU", null, ["HNPI-STU"], false, retryAt), "Wi-Fi retries without a failure limit");
    policy.Begin(retryAt);
}
policy.Reset(); Expect(policy.ShouldJoin(true, "HNPI-STU", null, ["HNPI-STU"], false, now), "reset allows immediate connection");
var special = "校<&\"园";
var xml = XDocument.Parse(WifiService.OpenProfileXml(special));
XNamespace ns = "http://www.microsoft.com/networking/WLAN/profile/v1";
Expect(xml.Descendants(ns + "SSID").Single().Element(ns + "name")!.Value == special, "SSID XML escaping");
Expect(xml.Root!.Element(ns + "connectionMode")!.Value == "manual", "OS cannot autoconnect behind pause toggle");
Expect(Marshal.SizeOf<WifiService.Ssid>() == 36, "native SSID ABI");
Expect(Marshal.SizeOf<WifiService.InterfaceInfo>() == 532, "native interface ABI");
Expect(Marshal.SizeOf<WifiService.AvailableNetwork>() == 628, "native network ABI");
Expect(Marshal.SizeOf<WifiService.Association>() == 68, "native association ABI");
Expect(Marshal.SizeOf<WifiService.ConnectionAttributes>() == 604, "native connection ABI");
var secret = "test'\\\"\n</script>";
var script = PortalScript.Build(profile with { Username = secret, ServiceOption = secret }, secret);
var payload = script.Split("const cfg = ")[1].Split(';')[0];
using var json = JsonDocument.Parse(payload);
Expect(json.RootElement.GetProperty("password").GetString() == secret, "credential JSON escaping");
Expect(json.RootElement.GetProperty("serviceOption").GetString() == secret, "service option JSON escaping");
Expect(!script.Contains("/*CAMPUS_CONFIG*/"), "embedded resource substituted");
if (args.Length == 1) File.WriteAllText(args[0], script);

Expect(DesktopBridge.IsTrustedSource("https://campusconnect-ui.invalid/"), "trust exact embedded UI");
Expect(!DesktopBridge.IsTrustedSource("http://campusconnect-ui.invalid/"), "reject insecure UI origin");
Expect(!DesktopBridge.IsTrustedSource("https://campusconnect-ui.invalid.evil/"), "reject lookalike host");
Expect(!DesktopBridge.IsTrustedSource("https://campusconnect-ui.invalid/?redirect=school"), "reject extra UI URL");
Expect(!DesktopBridge.IsTrustedSource("http://192.168.0.123/"), "school page cannot issue native UI commands");
Expect(!DesktopBridge.IsTrustedSource(null), "missing message origin rejected");
using var rect = JsonDocument.Parse("""{"x":244,"y":220,"width":792,"height":476,"viewportWidth":1060,"viewportHeight":760}""");
var scaled = DesktopBridge.ScaleBounds(rect.RootElement, 1325, 950);
Expect(scaled == (305, 275, 990, 595), "portal bounds scale to Windows 125 percent DPI");
using var invalidRect = JsonDocument.Parse("""{"x":-10,"y":0,"width":100,"height":100,"viewportWidth":1060,"viewportHeight":760}""");
Expect(DesktopBridge.ScaleBounds(invalidRect.RootElement, 1060, 760) is null, "reject offscreen browser bounds");
using var missingRect = JsonDocument.Parse("{}");
Expect(DesktopBridge.ScaleBounds(missingRect.RootElement, 1060, 760) is null, "reject missing browser bounds");

if (OperatingSystem.IsWindows()) {
    // Use an isolated HKCU key: tests must never enable the real logon application.
    var testKey = @"Software\CampusConnect.StartupTests\" + Guid.NewGuid().ToString("N");
    try {
        var startup = new StartupRegistration(@"C:\含空格 Test\CampusConnect.exe", testKey);
        Expect(!startup.IsEnabled(), "startup defaults off");
        startup.SetEnabled(true);
        using (var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(testKey))
            Expect((string?)key!.GetValue(StartupRegistration.ValueName) == "\"C:\\含空格 Test\\CampusConnect.exe\" --startup", "quoted startup path and tray flag");
        Expect(startup.IsEnabled(), "startup enabled");
        startup.SetEnabled(true);
        startup.SetEnabled(false);
        startup.SetEnabled(false);
        Expect(!startup.IsEnabled(), "startup removed idempotently");
        using (var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(testKey)) key.SetValue("OtherApp", "unchanged");
        startup.SetEnabled(true); startup.SetEnabled(false);
        using (var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(testKey))
            Expect((string?)key!.GetValue("OtherApp") == "unchanged", "preserve unrelated startup entries");
        try { new StartupRegistration(new string('x', 261), testKey).SetEnabled(true); throw new Exception("Long path accepted"); }
        catch (InvalidOperationException) { checks++; }
    } finally { if (OperatingSystem.IsWindows()) Microsoft.Win32.Registry.CurrentUser.DeleteSubKeyTree(testKey, false); }
} else Console.WriteLine("SKIP: Windows startup registry integration (requires Windows).");

// Regression: unchanged SSID must not latch a formerly successful authentication forever.
var recovery = new PortalRecovery();
Expect(recovery.ShouldAuthenticate(true, true, now), "first authentication starts before probes or timer ticks");
Expect(!recovery.ShouldAuthenticate(false, true, now), "startup respects pause");
Expect(!recovery.ShouldAuthenticate(true, false, now), "startup respects disabled portal");
recovery.Observe(InternetStatus.Online);
Expect(!recovery.ShouldAuthenticate(true, true, now), "online does not reauthenticate");
recovery.Observe(InternetStatus.Captive);
Expect(recovery.ShouldAuthenticate(true, true, now), "expired authentication on same SSID recovers");
recovery.Begin(now);
Expect(!recovery.ShouldAuthenticate(true, true, now.AddSeconds(20)), "no repeated submission every heartbeat");
Expect(recovery.ShouldAuthenticate(true, true, now.AddSeconds(60)), "retry after cooldown");
recovery.Begin(now.AddSeconds(60));
Expect(!recovery.ShouldAuthenticate(true, true, now.AddSeconds(120)), "second attempt uses longer backoff");
Expect(recovery.ShouldAuthenticate(true, true, now.AddSeconds(180)), "second backoff expires");
Expect(!recovery.ShouldAuthenticate(false, true, now.AddHours(1)), "pause prevents authentication");
Expect(!recovery.ShouldAuthenticate(true, false, now.AddHours(1)), "disabled portal prevents authentication");
recovery.Observe(InternetStatus.Online);
Expect(recovery.Attempts == 0 && !recovery.ShouldAuthenticate(true, true, now.AddHours(1)), "internet recovery resets attempts");
recovery.Observe(InternetStatus.Unavailable);
Expect(!recovery.ShouldAuthenticate(true, true, now), "one timeout does not disrupt login");
recovery.Observe(InternetStatus.Unavailable);
Expect(recovery.ShouldAuthenticate(true, true, now), "repeated failures trigger recovery");
var authenticationTime = now;
for (var i = 0; i < 1000; i++) {
    Expect(recovery.ShouldAuthenticate(true, true, authenticationTime), "authentication retries indefinitely");
    recovery.Begin(authenticationTime);
    recovery.Observe(InternetStatus.Unavailable);
    authenticationTime += recovery.RetryDelay;
}
recovery.Reset();
Expect(recovery.ShouldAuthenticate(true, true, now), "new connection resets first authentication delay");
Expect(InternetEvidence.Classify(200, "<html>Login</html>", "Microsoft Connect Test", true) == ProbeOutcome.Captive, "HTTP 200 portal is not internet");
Expect(InternetEvidence.Classify(302, "", "Microsoft Connect Test", true) == ProbeOutcome.Captive, "redirect is captive");
Expect(InternetEvidence.Classify(204, "Microsoft Connect Test", "Microsoft Connect Test", true) != ProbeOutcome.Success, "require exact status");
Expect(InternetEvidence.Classify(200, "Microsoft Connect Test", "Microsoft Connect Test", false) == ProbeOutcome.Captive, "changed endpoint cannot pass");
Expect(InternetEvidence.Combine(ProbeOutcome.Success, ProbeOutcome.Unavailable) != InternetStatus.Online, "one whitelisted probe is insufficient");
Expect(await Connectivity.CheckAsync(null) == InternetStatus.Unavailable, "missing campus adapter cannot use Ethernet or VPN");
var responses = new Dictionary<string, (int Status, string Body)>();
foreach (var probe in Connectivity.Probes) responses[new Uri(probe.Url).Host] = (200, probe.Body);
var probeRequests = new List<Uri>();
using (var client = new HttpClient(new ProbeHandler(request => {
    probeRequests.Add(request.RequestUri!);
    Expect(request.Headers.CacheControl?.NoCache == true && request.Headers.CacheControl.NoStore, "uncached network evidence");
    var response = responses[request.RequestUri!.Host];
    return new HttpResponseMessage((System.Net.HttpStatusCode)response.Status) { Content = new StringContent(response.Body), RequestMessage = request };
}))) {
    Expect(await Connectivity.CheckWithClientAsync(client) == InternetStatus.Online, "both strict responses confirm internet");
    responses["www.msftconnecttest.com"] = (200, "<html>login required</html>");
    Expect(await Connectivity.CheckWithClientAsync(client) == InternetStatus.Captive, "authentication expires while secure probe still passes");
    responses["www.msftconnecttest.com"] = (302, "");
    Expect(await Connectivity.CheckWithClientAsync(client) == InternetStatus.Captive, "redirect detection in HTTP pipeline");
    responses["www.msftconnecttest.com"] = (503, ""); responses["www.apple.com"] = (503, "");
    Expect(await Connectivity.CheckWithClientAsync(client) == InternetStatus.Unavailable, "outage remains unverified");
    foreach (var probe in Connectivity.Probes) responses[new Uri(probe.Url).Host] = (200, probe.Body);
    Expect(await Connectivity.CheckWithClientAsync(client) == InternetStatus.Online, "restored authentication passes again");
}
Expect(probeRequests.All(uri => uri.Query.Contains("campus_probe=")) && probeRequests.Select(uri => uri.Query).Distinct().Count() == probeRequests.Count, "fresh challenge for every request");


Console.WriteLine($"PASS: {checks} checks (validation, retry policy, native ABI, XML, credentials).");

sealed class ProbeHandler(Func<HttpRequestMessage, HttpResponseMessage> reply) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        => Task.FromResult(reply(request));
}
