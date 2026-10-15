import AppKit
import WebKit

// Offline tests use invented credentials and inline pages; no school requests.
@main struct WebKitTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do { try await Runner().run(); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            fputs("FAIL: native WebKit test timed out\n", stderr); exit(1)
        }
        app.run()
    }
}

@MainActor final class Runner: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    var navigation: CheckedContinuation<Void, Error>?
    var checks = 0
    let fixture = """
    <html><body>
    <input id="username_tip" readonly value="Username"><input id="username" type="text" style="display:none">
    <input id="pwd_tip" readonly value="Password"><input id="pwd" type="password" style="display:none">
    <a id="loginLink" tabindex="-1" onclick="doauthen()"><div style="width:275px;height:54px;background:blue"></div></a>
    <script>
    window.loginCalls=0; window.handlerCalls=0;
    window.AuthInterFace={login(){loginCalls++}};
    function doauthen(){handlerCalls++;AuthInterFace.login()}
    for(const id of ['username','pwd']){
      const input=document.getElementById(id),tip=document.getElementById(id+'_tip');
      tip.onfocus=()=>{input.style.display='';input.focus();tip.style.display='none'};
      input.onblur=()=>{if(!input.value){input.style.display='none';tip.style.display=''}};
    }
    </script></body></html>
    """
    func expect(_ value: Bool, _ message: String) throws {
        checks += 1
        if !value { throw AppError.message(message) }
    }
    func load() async throws {
        view.navigationDelegate = self
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigation = continuation
            view.loadHTMLString(fixture, baseURL: URL(string: "http://portal.test/eportal/index.jsp"))
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.navigation?.resume(); self.navigation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.navigation?.resume(throwing: error); self.navigation = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.navigation?.resume(throwing: error); self.navigation = nil
    }
    @discardableResult func js(_ script: String) async throws -> Any {
        try await view.evaluateJavaScript(script) ?? NSNull()
    }
    func fill(submit: Bool = true, origin: String = "http://portal.test", service: String = "") async throws -> String {
        var profile = CampusProfile()
        profile.serviceOption = service
        profile.portalURL = origin; profile.username = "dummy-user"; profile.autoSubmit = submit
        return try await js(PortalScript.build(profile: profile, password: "dummy-password")) as? String ?? "nil"
    }
    func pump(service: String = "") async throws -> String {
        var result = ""
        for _ in 0..<20 {
            result = try await fill(service: service)
            if !["waiting-submit", "waiting-ready"].contains(result) { return result }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return result
    }
    func run() async throws {
        try await load()
        // Simulate a first programmatic click that never reaches the school's handler.
        try await js("document.getElementById('loginLink').click=()=>{}; true")
        let first = try await fill()
        try expect(first != "submitted", "a lost first click must not be reported as submitted")
        let recovered = try await pump()
        try expect(recovered == "submitted", "lost click recovers through the existing page event")
        try expect(try await js("loginCalls") as? Int == 1, "exactly one school login after recovery")
        try expect(try await fill() == "already-submitted", "successful submission is deduplicated")
        try expect(try await js("loginCalls") as? Int == 1, "no repeated credential request")

        try await load()
        try expect(try await fill() == "waiting-submit", "fill and submit occur on separate turns")
        try expect(try await js("loginCalls") as? Int == 0, "first turn only fills and prepares")
        try expect(try await pump() == "submitted", "normal native WebKit submission")
        try expect(try await js("handlerCalls") as? Int == 1, "normal handler invoked once")

        try await load()
        try await js("doauthen=function(){handlerCalls++;setTimeout(()=>AuthInterFace.login(),300)}; true")
        let asyncResult = try await pump()
        try expect(["submitted", "already-submitted"].contains(asyncResult), "wait for asynchronous school handoff")
        try expect(try await js("handlerCalls") as? Int == 1, "asynchronous handler is never clicked twice")

        try await load()
        try await js("doauthen=function(){handlerCalls++;document.body.dataset.validation='manual-required'}; true")
        _ = try await fill(); _ = try await fill()
        try await js("window.__campusSubmitAttempt.startedAt-=10000")
        try expect(try await fill() == "submission-unconfirmed", "page validation does not falsely count as submitted")
        try expect(try await js("handlerCalls") as? Int == 1, "do not repeat a handler that already ran")
        try expect(try await js("loginCalls") as? Int == 0, "validation does not send credentials")

        try await load()
        try await js("window.doauthen=undefined; true")
        try expect(try await fill() == "waiting-ready", "wait for a late login handler")
        try await js("window.doauthen=function(){handlerCalls++;AuthInterFace.login()}; true")
        try expect(try await pump() == "submitted", "late handler can complete first login")

        try await load()
        try await js("doauthen=function(){handlerCalls++;throw Error('fixture not ready')}; true")
        try expect(try await pump() == "submission-unconfirmed", "school handler exception does not report submission")
        try expect(try await js("loginCalls") as? Int == 0, "failed handler sends no request")
        try expect(try await fill() == "submission-unconfirmed", "failed handler is not repeatedly activated")

        try await load()
        try await js("AuthInterFace.login=function(){throw Error('fixture login failed')}; true")
        try expect(try await pump() == "submission-unconfirmed", "synchronous login failure is not reported as submitted")

        try await load()
        try await js("document.body.insertAdjacentHTML('beforeend','<input id=validCode>'); true")
        try expect(try await fill() == "manual-required", "captcha retains manual interaction")
        try expect(try await js("loginCalls") as? Int == 0, "no login with empty captcha")

        try await load()
        try await js("document.getElementById('loginLink').disabled=true")
        try expect(try await fill() == "missing-submit", "disabled button is not activated")
        try await js("document.getElementById('loginLink').disabled=false")
        try expect(try await pump() == "submitted", "button enabling resumes first submission")

        try await load()
        try expect(try await fill(submit:false) == "filled", "manual-only setting is respected")
        try expect(try await js("loginCalls") as? Int == 0, "manual-only never clicks")
        try await load()
        try expect(try await fill(origin:"http://other.test") == "wrong-origin", "origin guard retained")
        try expect(try await js("document.getElementById('pwd').value") as? String == "", "foreign origin receives no password")
        // Real WebKit verifies service selection before the two-stage ePortal submit.
        try await load()
        try await js("""
          document.body.insertAdjacentHTML('beforeend', '<input id="net_access_type" type="hidden"><div id="serviceShowHideTop"><span id="selectDisname">请选择服务</span></div><div id="serviceShowHide" style="display:none"><div id="bch_service_0"><div><div id="_service_0">联通接入服务</div></div></div></div>');
          window.serviceClicks=0;window.menuOpens=0;
          document.getElementById('serviceShowHideTop').onclick=()=>{menuOpens++;document.getElementById('serviceShowHide').style.display='block'};
          document.getElementById('bch_service_0').onclick=()=>{serviceClicks++;document.getElementById('net_access_type').value='unicom';document.getElementById('selectDisname').textContent='联通接入服务';document.getElementById('serviceShowHide').style.display='none'};
          true
        """)
        try expect(try await pump(service:"联通接入服务") == "submitted", "ePortal service selected before submit")
        try expect(try await js("document.getElementById('net_access_type').value") as? String == "unicom", "school service handler updates internal value")
        try expect(try await js("serviceClicks") as? Int == 1, "service handler invoked once")
        try expect(try await js("loginCalls") as? Int == 1, "service selection preserves confirmed one-time login")

        try await load()
        try await js("document.body.insertAdjacentHTML('beforeend','<select id=service><option value=empty>请选择服务</option><option value=unicom>联通接入服务</option></select>');true")
        try expect(try await fill(submit:false,service:"  联通接入服务  ") == "filled", "native select accepts exact trimmed display name")
        try expect(try await js("document.getElementById('service').value") as? String == "unicom", "native service selected")
        try expect(try await js("loginCalls") as? Int == 0, "manual mode does not login after selection")
        try expect(try await fill(service:"不存在") == "missing-service", "wrong service stops login")
        try expect(try await js("loginCalls") as? Int == 0, "missing service never submits default")

        try await load()
        try await js("document.body.insertAdjacentHTML('beforeend','<select id=service><option value=empty>请选择服务</option></select>');true")
        try expect(try await fill(service:"联通接入服务") == "missing-service", "wait for delayed service")
        try await js("document.getElementById('service').add(new Option('联通接入服务','unicom'));true")
        try expect(try await pump(service:"联通接入服务") == "submitted", "delayed option resumes login")

        try await load()
        try expect(try await fill(service:"联通接入服务") == "missing-service", "configured service without control requires attention")
        try expect(try await pump() == "submitted", "blank service supports pages without service selector")
        // A blue focused button with both activation events lost still uses
        // the school's own validation/login function, exactly once.
        try await load()
        try await js("const b=document.getElementById('loginLink');b.click=()=>{};b.dispatchEvent=()=>true;true")
        try expect(try await pump() == "submitted", "lost activation falls back to school handler")
        try expect(try await js("handlerCalls") as? Int == 1, "fallback invokes handler once")
        try expect(try await js("loginCalls") as? Int == 1, "fallback sends one request")
        var statusProfile = CampusProfile()
        statusProfile.portalURL = "http://portal.test"
        let statusScript = try PortalScript.build(profile: statusProfile, password: "", statusOnly: true)
        try expect(try await js(statusScript) as? String == "awaiting-authentication", "request alone is not successful authentication")
        try await load()
        try await js("AuthInterFace.login=function(...args){loginCalls++;window.reply=args.at(-1)};doauthen=function(){handlerCalls++;AuthInterFace.login('dummy',function(r){window.originalResult=r.result;return 42})};true")
        _ = try await pump()
        try expect(try await js(statusScript) as? String == "awaiting-authentication", "wait for response")
        try expect(try await js("reply({result:'success'})") as? Int == 42, "original callback return preserved")
        try expect(try await js(statusScript) as? String == "authenticated", "school response confirms authentication")
        try expect(try await js("originalResult") as? String == "success", "original callback still runs")
        try await load()
        try await js("AuthInterFace.login=function(...args){loginCalls++;window.reply=args.at(-1)};doauthen=function(){handlerCalls++;AuthInterFace.login('dummy',function(r){window.originalResult=r.result})};true")
        _ = try await pump()
        try await js("reply({result:'fail'});true")
        try expect(try await js(statusScript) as? String == "authentication-rejected", "rejection is not success")
        try expect(try await fill() == "authentication-rejected", "rejection never resubmits")
        try expect(try await js("loginCalls") as? Int == 1, "rejection has one request")
        print("PASS: \(checks) native WKWebView checks (first click, handler readiness, asynchronous handoff, deduplication, manual mode, origin and service selection).")
    }
}
