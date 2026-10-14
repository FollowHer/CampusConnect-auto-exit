import Foundation

enum JoinMode: String, Codable, CaseIterable, Identifiable {
    case open, personal, enterprise
    var id: String { rawValue }
    var title: String {
        switch self { case .open: return "开放网络"; case .personal: return "Wi-Fi 密码"; case .enterprise: return "企业账号（802.1X）" }
    }
}

struct CampusProfile: Codable, Equatable {
    var ssid = "HNPI-STU"
    var joinMode: JoinMode = .open
    var wifiUsername = ""
    var portalEnabled = true
    var portalURL = "http://192.168.0.123"
    var username = ""
    var userSelector = ""
    var passwordSelector = ""
    var submitSelector = ""
    var autoSubmit = true
    var automatic = false

    enum CodingKeys: String, CodingKey {
        case ssid, joinMode, wifiUsername, portalEnabled, portalURL, username
        case userSelector, passwordSelector, submitSelector, autoSubmit, automatic
    }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ssid = try values.decodeIfPresent(String.self, forKey: .ssid) ?? "HNPI-STU"
        joinMode = try values.decodeIfPresent(JoinMode.self, forKey: .joinMode) ?? .open
        wifiUsername = try values.decodeIfPresent(String.self, forKey: .wifiUsername) ?? ""
        portalEnabled = try values.decodeIfPresent(Bool.self, forKey: .portalEnabled) ?? true
        portalURL = try values.decodeIfPresent(String.self, forKey: .portalURL) ?? "http://192.168.0.123"
        username = try values.decodeIfPresent(String.self, forKey: .username) ?? ""
        userSelector = try values.decodeIfPresent(String.self, forKey: .userSelector) ?? ""
        passwordSelector = try values.decodeIfPresent(String.self, forKey: .passwordSelector) ?? ""
        submitSelector = try values.decodeIfPresent(String.self, forKey: .submitSelector) ?? ""
        autoSubmit = try values.decodeIfPresent(Bool.self, forKey: .autoSubmit) ?? true
        automatic = try values.decodeIfPresent(Bool.self, forKey: .automatic) ?? false
    }

    var validPortalURL: URL? {
        guard let url = URL(string: portalURL), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    func validate() throws {
        guard !ssid.isEmpty, ssid.utf8.count <= 32 else { throw AppError.message("请输入正确的 Wi-Fi 名称（最多 32 字节）。") }
        if joinMode == .enterprise && wifiUsername.isEmpty { throw AppError.message("企业认证需要 Wi-Fi 用户名。") }
        if portalEnabled && !portalURL.isEmpty && validPortalURL == nil { throw AppError.message("认证地址需要以 http:// 或 https:// 开头。") }
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

struct Secrets: Codable, Equatable {
    var wifi = ""
    var portal = ""
}

struct LocalConfiguration: Codable {
    var profile: CampusProfile
    var credentials: [String: Secrets] = [:]
}

enum LocalStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CampusConnect", isDirectory: true)
    }
    static func load(directory: URL = directory) throws -> LocalConfiguration {
        let file = directory.appendingPathComponent("configuration.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            let legacy = UserDefaults.standard.data(forKey: "campus.profile")
                .flatMap { try? JSONDecoder().decode(CampusProfile.self, from: $0) } ?? CampusProfile()
            return LocalConfiguration(profile: legacy)
        }
        return try JSONDecoder().decode(LocalConfiguration.self, from: Data(contentsOf: file))
    }
    static func read(_ ssid: String, _ kind: String, directory: URL = directory) throws -> String {
        let secrets = try load(directory: directory).credentials[ssid] ?? Secrets()
        return kind == "wifi" ? secrets.wifi : secrets.portal
    }
    static func save(profile: CampusProfile, secrets: Secrets? = nil, directory: URL = directory) throws {
        var configuration = try load(directory: directory)
        configuration.profile = profile
        if let secrets { configuration.credentials[profile.ssid] = secrets }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let file = directory.appendingPathComponent("configuration.json")
        try data.write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

struct AutoPolicy {
    var lastAttempt = Date.distantPast
    var failures = 0
    func shouldJoin(enabled: Bool, target: String, current: String?, visible: [String], busy: Bool, now: Date) -> Bool {
        enabled && !target.isEmpty && current != target && visible.contains(target) && !busy && now.timeIntervalSince(lastAttempt) >= 60
    }
    mutating func begin(at date: Date) { lastAttempt = date }
    mutating func success() { failures = 0 }
    mutating func fail() { if failures < Int.max { failures += 1 } }
    mutating func reset() { failures = 0; lastAttempt = .distantPast }
}

enum InternetStatus: String { case online, captive, unavailable }
enum ProbeOutcome { case success, captive, unavailable }

enum InternetEvidence {
    static func classify(status: Int, body: String, expectedBody: String, sameEndpoint: Bool) -> ProbeOutcome {
        if !sameEndpoint || (300..<400).contains(status) { return .captive }
        guard status == 200 else { return .unavailable }
        return body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == expectedBody.lowercased() ? .success : .captive
    }
    static func combine(_ probes: [ProbeOutcome]) -> InternetStatus {
        if probes.contains(where: { $0 == .captive }) { return .captive }
        return probes.count == 2 && probes.allSatisfy { $0 == .success } ? .online : .unavailable
    }
}

struct PortalRecovery {
    private(set) var failures = 0
    private(set) var attempts = 0
    private(set) var lastAttempt = Date.distantPast
    private(set) var state: InternetStatus = .unavailable
    var retryDelay: TimeInterval { min(300, 60 * pow(2, Double(max(0, attempts - 1)))) }
    mutating func observe(_ result: InternetStatus) {
        if result == .online { reset(); state = .online }
        else { state = result; failures = min(2, failures + 1) }
    }
    func shouldAuthenticate(enabled: Bool, portalEnabled: Bool, now: Date) -> Bool {
        enabled && portalEnabled && state != .online && ((attempts == 0 && failures == 0) || state == .captive || failures >= 2)
            && now.timeIntervalSince(lastAttempt) >= retryDelay
    }
    mutating func begin(at now: Date) { lastAttempt = now; attempts = min(4, attempts + 1) }
    mutating func reset() { self = PortalRecovery() }
}

enum PortalScript {
    static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host?.lowercased() else { return nil }
        let port = url.port
        let defaultPort = scheme == "https" ? 443 : 80
        let formattedHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(scheme)://\(formattedHost)\(port != nil && port != defaultPort ? ":\(port!)" : "")"
    }
    static func build(profile: CampusProfile, password: String) throws -> String {
        guard let url = profile.validPortalURL, let origin = origin(url) else { throw AppError.message("请先保存认证地址。") }
        let payload: [String: Any] = ["origin": origin, "username": profile.username, "password": password,
                                    "userSelector": profile.userSelector, "passwordSelector": profile.passwordSelector,
                                    "submitSelector": profile.submitSelector, "submit": profile.autoSubmit]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        // Credentials are supplied to the current page only after native SSID + origin checks.
        return """
        (() => {
          const cfg = \(json);
          if (location.origin !== cfg.origin) return 'wrong-origin';
          if (window.__campusSubmitted) return 'already-submitted';
          if (document.readyState === 'loading') return 'waiting-ready';
          const ready = window.__campusReady;
          if (ready && (ready.failed || !ready.pageInfo || !ready.getServices)) return 'waiting-ready';
          const visible = e => e && !e.disabled && e.getClientRects().length > 0;
          const editable = e => e instanceof HTMLInputElement && !e.disabled && !e.readOnly;
          let user, pass, submit, portalUser, portalPass, portalButton;
          const tipFor = input => input === portalUser ? document.querySelector('#username_tip') :
            input === portalPass ? document.querySelector('#pwd_tip') : null;
          const available = input => editable(input) && (visible(input) ||
            (portalButton && visible(tipFor(input))));
          try {
            // Ruijie ePortal displays readonly tips over hidden real inputs. Its login
            // control is an image-only anchor, so text/button heuristics cannot find it.
            portalUser = document.querySelector('#username');
            portalPass = document.querySelector('#pwd');
            portalButton = document.querySelector('#loginLink');
            if (!editable(portalUser) || portalUser.type !== 'text' ||
                !editable(portalPass) || portalPass.type !== 'password' || !portalButton) {
              portalUser = portalPass = portalButton = null;
            }
            // Unknown ePortal variants retain full-load behavior; only inspected initialization is accelerated.
            if (portalButton && !ready && document.readyState !== 'complete') return 'waiting-ready';
            pass = cfg.passwordSelector ? document.querySelector(cfg.passwordSelector) :
              portalPass || [...document.querySelectorAll('input[type="password"]')].find(e => editable(e) && visible(e));
            const root = pass && pass.form ? pass.form : document;
            user = cfg.userSelector ? document.querySelector(cfg.userSelector) : portalUser ||
              [...root.querySelectorAll('input:not([type="password"]):not([type="hidden"]):not([type="checkbox"]):not([type="radio"]):not([type="submit"]):not([type="button"])')]
              .filter(e => editable(e) && visible(e)).find(e => /user|account|student|phone|login|学号|账号|手机/i.test([e.name,e.id,e.placeholder,e.autocomplete].join(' ')));
            if (!user && !cfg.userSelector) user = [...root.querySelectorAll('input[type="text"],input[type="tel"],input[type="email"],input:not([type])')].find(e => editable(e) && visible(e));
            submit = cfg.submitSelector ? document.querySelector(cfg.submitSelector) : portalButton ||
              [...root.querySelectorAll('button,input[type="submit"],input[type="button"],a,[role="button"]')].filter(visible)
                .find(e => e.type === 'submit' || /^(登录|登陆|认证|连接|login|log in|sign in|connect)(\\s*(login|登录|登陆))?$/i.test((e.innerText || e.value || '').trim()));
          } catch (_) { return 'invalid-selector'; }
          if (!available(user) || !available(pass)) return 'missing-fields';
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
          for (const [input, value] of [[user,cfg.username],[pass,cfg.password]]) {
            if (!visible(input)) {
              const tip = tipFor(input);
              if (visible(tip)) {
                tip.focus();
                // Background WebViews may not deliver native focus. Invoke the school's
                // own reveal handlers without taking OS focus or changing its DOM styles.
                if (!visible(input) && visible(tip)) tip.dispatchEvent(new FocusEvent('focus'));
                if (!visible(input) && visible(tip)) tip.dispatchEvent(new FocusEvent('focusin', {bubbles:true}));
                if (!visible(input) && visible(tip)) tip.click();
              }
            }
            if (!editable(input) || !visible(input)) return 'missing-fields';
            setter.call(input, value);
            input.dispatchEvent(new Event('input', {bubbles:true}));
            input.dispatchEvent(new Event('change', {bubbles:true}));
          }
          // School handlers can reject/reset a value; never report success or submit it.
          if (!editable(user) || !editable(pass) || !visible(user) || !visible(pass) ||
              user.value !== cfg.username || pass.value !== cfg.password) return 'missing-fields';
          if (!cfg.submit) return 'filled';
          if (!visible(submit)) return 'missing-submit';
          if (portalButton && /doauthen/.test(submit.getAttribute('onclick') || '') &&
              typeof window.doauthen !== 'function') return 'waiting-ready';
          // Captchas and extra operator fields need the user's input; don't burn a login attempt.
          if (portalButton && ['#validCode','#operatorUserId','#operatorPwd'].some(selector => {
            const input = document.querySelector(selector);
            return visible(input) && !input.value.trim();
          })) return 'manual-required';
          window.__campusSubmitted = true;
          submit.click();
          return 'submitted';
        })()
        """
    }
}
