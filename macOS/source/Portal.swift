import AppKit
import SwiftUI
import WebKit
import Network

final class PortalController: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var message = "连接校园网后，在这里完成上网认证。"
    @Published var address = ""
    @Published var loading = false
    var requiresInteraction = false
    var onSubmission: (() -> Void)?
    var onAuthentication: (() -> Void)?
    private var profile: CampusProfile?
    private var password = ""
    private var generation = 0
    private var submitted = false
    private var filled = false
    private var fillingGeneration: Int?
    private var preparing = false
    private let fillWiFi = WiFiService()
    private let campusProxy = CampusProxy()

    override init() {
        let config = WKWebViewConfiguration()
        // An isolated browser session keeps campus authentication separate from Safari.
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func open(profile: CampusProfile, password: String, discoveryHost: String? = nil) {
        generation += 1
        let expected = generation
        preparing = true
        webView.stopLoading()
        fillWiFi.readCurrent { [weak self] ssid in
            guard let self, expected == self.generation else { return }
            guard ssid == profile.ssid else {
                self.preparing = false; self.message = "请先连接 \(profile.ssid)，再打开认证页。"; return
            }
            self.load(profile: profile, password: password, discoveryHost: discoveryHost)
        }
    }
    private func load(profile: CampusProfile, password: String, discoveryHost: String?) {
        requiresInteraction = !profile.autoSubmit
        submitted = false; filled = false
        self.profile = profile; self.password = password
        let url = profile.validPortalURL ?? URL(string: "http://captive.apple.com/hotspot-detect.html")!
        webView.configuration.userContentController.removeAllUserScripts()
        if let origin = PortalScript.origin(url),
           let resource = Bundle.main.url(forResource: "PortalBootstrap", withExtension: "js"),
           let bootstrap = try? String(contentsOf: resource, encoding: .utf8),
           let json = try? JSONSerialization.data(withJSONObject: origin, options: [.fragmentsAllowed]) {
            let script = bootstrap.replacingOccurrences(of: "/*CAMPUS_ORIGIN*/", with: String(decoding: json, as: UTF8.self))
            webView.configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        loading = true
        message = profile.validPortalURL == nil ? "正在探测认证页…" : "正在打开校园网认证页…"
        let expected = generation
        guard let host = url.host else { message = "认证地址无效。"; return }
        let extra = discoveryHost.map { Set([$0]) } ?? []
        campusProxy.start(host: host, additionalHosts: extra) { [weak self] result in
            guard let self, expected == self.generation else { return }
            switch result {
            case .success(let port):
                self.webView.configuration.websiteDataStore.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!))]
                self.preparing = false
                self.webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
            case .failure(let error): self.loading = false; self.message = "校园直连初始化失败：\(error.localizedDescription)"
            }
        }
    }

    func stop() {
        generation += 1
        profile = nil; password = ""; submitted = false; filled = false; requiresInteraction = false
        webView.stopLoading(); loading = false
        campusProxy.stop()
        message = "认证已暂停。"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, ["http", "https", "about"].contains(url.scheme?.lowercased() ?? "") else {
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { generation += 1; loading = true }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { startFilling() }
    private func startFilling() {
        guard !preparing, fillingGeneration != generation, !submitted, !filled else { return }
        fillingGeneration = generation
        attemptFill(generation: generation, attempt: 0)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        address = webView.url?.absoluteString ?? ""
        guard !preparing, let profile else { return }
        if let allowed = profile.validPortalURL, let current = webView.url,
           PortalScript.origin(current) == PortalScript.origin(allowed), current.path == "/eportal/success.jsp" {
            let expected = generation
            fillWiFi.readCurrent { [weak self] ssid in
                guard let self, expected == self.generation, ssid == profile.ssid else { return }
                self.submitted = true; self.filled = true; self.password = ""
                self.message = "学校认证页面已确认登录成功。"
                self.onAuthentication?()
            }
            return
        }
        guard profile.validPortalURL != nil else {
            message = "请确认下方页面是学校认证页，再使用当前地址保存配置。"; return
        }
        if submitted { message = "已提交账号密码，请查看页面结果。"; return }
        startFilling()
    }

    private func attemptFill(generation expected: Int, attempt: Int) {
        guard expected == generation, !submitted, !filled, let profile else { return }
        fillWiFi.readCurrent { [weak self] currentSSID in
            guard let self, expected == self.generation, !self.submitted, !self.filled else { return }
            guard currentSSID == profile.ssid else { self.message = "校园网已断开，暂停填写。"; return }
            self.evaluateFill(profile: profile, expected: expected, attempt: attempt)
        }
    }
    private func evaluateFill(profile: CampusProfile, expected: Int, attempt: Int) {
        guard let allowed = profile.validPortalURL, let current = webView.url,
              PortalScript.origin(allowed) == PortalScript.origin(current) else {
            message = "页面地址与保存的认证地址不同，请确认后更新地址。"; return
        }
        guard !profile.username.isEmpty, !password.isEmpty else {
            message = "请在校园网设置中保存学号 / 账号和密码。"; return
        }
        do {
            let script = try PortalScript.build(profile: profile, password: password)
            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self, expected == self.generation else { return }
                let status = result as? String
                if PortalFillRetry.shouldRetry(result: status, scriptFailed: error != nil, attempt: attempt) {
                    self.message = status == "waiting-submit" ? "账号密码已填写，正在等待学校页面处理登录…" : "正在等待认证页面就绪…"
                    DispatchQueue.main.asyncAfter(deadline: .now() + PortalFillRetry.delay) { [weak self] in
                        self?.attemptFill(generation: expected, attempt: attempt + 1)
                    }
                    return
                }
                if error != nil {
                    self.requiresInteraction = true; self.filled = true; self.password = ""
                    self.message = "页面脚本暂未就绪，请点击立即认证重试，或在页面手动登录。"; return
                }
                switch status {
                case "submitted", "already-submitted":
                    self.submitted = true; self.password = ""
                    self.message = "已填写并提交，正在检查是否可以上网…"; self.onSubmission?()
                case "filled": self.requiresInteraction = true; self.filled = true; self.password = ""; self.message = "账号密码已填写，请在页面点击登录。"
                case "missing-submit": self.requiresInteraction = true; self.filled = true; self.password = ""; self.message = "账号密码已填写，未识别登录按钮，请手动点击或设置按钮选择器。"
                case "manual-required": self.requiresInteraction = true; self.filled = true; self.password = ""; self.message = "学校要求验证码或运营商信息，请在认证页补充。"
                case "waiting-submit", "submission-unconfirmed":
                    self.requiresInteraction = true; self.filled = true; self.password = ""
                    self.message = "学校页面尚未确认提交，请查看页面提示；可点击立即认证重试或手动登录。"
                case "waiting-ready": self.requiresInteraction = true; self.filled = true; self.password = ""; self.message = "学校认证参数尚未就绪，请检查页面后重试。"
                case "invalid-selector": self.requiresInteraction = true; self.message = "高级设置中的 CSS 选择器无效，请修正。"
                case "wrong-origin": self.requiresInteraction = true; self.message = "认证地址不匹配，已暂停填写。"
                default: self.requiresInteraction = true; self.message = "未识别登录表单，请手动操作，或在高级设置中指定输入框。"
                }
            }
        } catch { message = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false; message = "认证页打不开：\(error.localizedDescription)"
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loading = false; message = "页面加载失败：\(error.localizedDescription)"
    }
}

struct PortalWebView: NSViewRepresentable {
    let controller: PortalController
    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
