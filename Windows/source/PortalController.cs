using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace CampusConnect;

internal sealed class PortalController
{
    public WebView2 View { get; } = new() { Dock = DockStyle.Fill };
    public event Action<string>? Status;
    public event Action? Submitted;
    public event Action? AddressChanged;
    public bool IsActive { get; private set; }
    public bool RequiresInteraction { get; private set; }
    public string Address => View.CoreWebView2?.Source is { } source && source != "about:blank" ? source : "";
    private CampusProfile? profile;
    private string password = "";
    private int generation;
    private bool finished;
    private int fillingGeneration = -1;
    private string? bootstrapId;
    private Task? initialization;
    private readonly Func<Task<CoreWebView2Environment>> getEnvironment;

    public PortalController(Func<Task<CoreWebView2Environment>> getEnvironment) => this.getEnvironment = getEnvironment;

    private async Task InitializeAsync()
    {
        // Reuse the already initialized browser runtime; the school's browser
        // still has its own settings and cannot access the application's bridge.
        var environment = await getEnvironment();
        var options = environment.CreateCoreWebView2ControllerOptions();
        options.IsInPrivateModeEnabled = true;
        await View.EnsureCoreWebView2Async(environment, options);
        View.CoreWebView2.Settings.IsPasswordAutosaveEnabled = false;
        View.CoreWebView2.Settings.IsGeneralAutofillEnabled = false;
        View.CoreWebView2.Settings.IsWebMessageEnabled = false;
        View.CoreWebView2.Settings.AreHostObjectsAllowed = false;
        View.CoreWebView2.SourceChanged += (_, _) => AddressChanged?.Invoke();
        View.CoreWebView2.NewWindowRequested += (_, e) => { e.Handled = true; Status?.Invoke("认证页请求打开新窗口，请在系统浏览器中手动处理。"); };
        View.CoreWebView2.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
        View.CoreWebView2.DownloadStarting += (_, e) => e.Cancel = true;
        View.CoreWebView2.NavigationStarting += (_, e) => {
            generation++;
            if (e.Uri != "about:blank" && CampusProfile.Origin(e.Uri) is null) e.Cancel = true;
            if (profile != null && CampusProfile.Origin(e.Uri) != CampusProfile.Origin(profile.PortalUrl))
                Status?.Invoke("页面地址已改变，暂停自动填写；确认学校网址后在设置中更新。");
        };
        View.CoreWebView2.ContentLoading += async (_, _) => await TryFillAsync();
        View.CoreWebView2.DOMContentLoaded += async (_, _) => await TryFillAsync();
        View.CoreWebView2.NavigationCompleted += async (_, e) => {
            if (profile is null) return;
            if (!e.IsSuccess) { Status?.Invoke($"认证页加载失败：{e.WebErrorStatus}。可先断开 VPN 后重试。"); return; }
            await TryFillAsync();
        };
    }

    public async Task OpenAsync(CampusProfile saved, string secret, bool discover = false)
    {
        Stop(clearView: false);
        var expected = generation;
        initialization ??= InitializeAsync();
        try { await initialization; }
        catch { initialization = null; throw; }
        if (expected != generation) return;
        var current = await WifiService.ReadCurrentAsync(saved.Ssid);
        if (expected != generation || View.IsDisposed) return;
        if (current != saved.Ssid) throw new InvalidOperationException("请先连接已设置的校园 Wi-Fi，再打开认证页。");
        saved.Validate();
        profile = discover ? saved with { PortalUrl = "http://www.msftconnecttest.com/redirect", Username = "", AutoSubmit = false } : saved;
        password = discover ? "" : secret; RequiresInteraction = !saved.AutoSubmit;
        if (bootstrapId != null) View.CoreWebView2.RemoveScriptToExecuteOnDocumentCreated(bootstrapId);
        using var stream = typeof(PortalController).Assembly.GetManifestResourceStream("CampusConnect.PortalBootstrap.js")!;
        using var reader = new StreamReader(stream);
        var bootstrap = reader.ReadToEnd().Replace("/*CAMPUS_ORIGIN*/", JsonSerializer.Serialize(CampusProfile.Origin(profile.PortalUrl)));
        bootstrapId = await View.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(bootstrap);
        if (expected != generation || profile is null) return;
        IsActive = true;
        View.CoreWebView2.Navigate(profile.PortalUrl);
        Status?.Invoke(discover ? "正在探测认证地址，请确认学校页面后使用当前地址。" : "正在打开校园认证页…");
    }
    public void ConfirmInternetAccess() => RequiresInteraction = false;
    public void Stop(bool clearView = true)
    {
        generation++;
        profile = null; password = ""; finished = false;
        IsActive = false; RequiresInteraction = false;
        if (View.CoreWebView2 is not null) {
            View.CoreWebView2.Stop();
            if (clearView) View.CoreWebView2.Navigate("about:blank");
        }
    }
    private async Task TryFillAsync()
    {
        var expected = generation;
        if (!IsActive || fillingGeneration == expected || finished || profile is null) return;
        fillingGeneration = expected;
        try { await FillAsync(expected); }
        catch (Exception ex) { if (expected == generation) Status?.Invoke("自动填写失败：" + ex.Message); }
        finally { if (fillingGeneration == expected) fillingGeneration = -1; }
    }
    private async Task FillAsync(int expected)
    {
        for (var attempt = 0; attempt <= 80; attempt++) {
            if (expected != generation || finished || profile is null) return;
            var activeProfile = profile;
            var current = await WifiService.ReadCurrentAsync(activeProfile.Ssid);
            if (expected != generation || finished || View.IsDisposed) return;
            if (current != activeProfile.Ssid) { Stop(); Status?.Invoke("校园网已断开，停止自动填写。"); return; }
            if (CampusProfile.Origin(View.CoreWebView2.Source) != CampusProfile.Origin(profile.PortalUrl)) {
                Status?.Invoke("当前页面与保存的认证地址不同，请核实后更新设置。"); return;
            }
            if (profile.Username.Length == 0 || password.Length == 0) {
                RequiresInteraction = true; Status?.Invoke("请在设置中填写上网账号密码，或直接在网页中手动登录。"); return;
            }
            var result = JsonSerializer.Deserialize<string>(await View.CoreWebView2.ExecuteScriptAsync(PortalScript.Build(profile, password)));
            if (expected != generation) return;
            switch (result) {
                case "submitted": case "already-submitted":
                    finished = true; password = "";
                    Status?.Invoke("已提交一次，请查看学校网页结果；不会自动重复提交密码。"); Submitted?.Invoke(); return;
                case "waiting-ready" when attempt < 80:
                case "missing-submit" when attempt < 80: await Task.Delay(150); continue;
                case "filled":
                    RequiresInteraction = true; finished = true; password = ""; Status?.Invoke("账号密码已填写，请在网页中手动点击登录。"); return;
                case "missing-submit":
                    RequiresInteraction = true; finished = true; password = ""; Status?.Invoke("账号密码已填写，未识别可用的认证按钮，请手动点击或检查按钮选择器。"); return;
                case "missing-fields" when attempt < 80: await Task.Delay(150); continue;
                case "manual-required": RequiresInteraction = true; finished = true; password = ""; Status?.Invoke("学校要求验证码或运营商信息，请在认证页补充。"); return;
                case "waiting-ready": finished = true; password = ""; Status?.Invoke("学校认证参数尚未就绪，请检查页面后重试。"); return;
                case "invalid-selector": RequiresInteraction = true; Status?.Invoke("CSS 选择器无效，请修改高级设置。"); return;
                case "wrong-origin": RequiresInteraction = true; Status?.Invoke("认证地址不匹配，已阻止填写。"); return;
                default: RequiresInteraction = true; Status?.Invoke("未识别登录表单，请手动登录或设置 CSS 选择器。"); return;
            }
        }
    }
}
