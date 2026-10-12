import Foundation
import JavaScriptCore

@main struct Tests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() throws {
        let localDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("work/storage-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: localDirectory) }
        var storedProfile = CampusProfile()
        storedProfile.username = "test-account"
        let secrets = Secrets(wifi: "test-wifi", portal: "test-portal")
        try LocalStore.save(profile: storedProfile, secrets: secrets, directory: localDirectory)
        let reloaded = try LocalStore.load(directory: localDirectory)
        expect(reloaded.profile == storedProfile, "local account and settings persist")
        expect(reloaded.credentials[storedProfile.ssid] == secrets, "local passwords persist")
        let filePermissions = try FileManager.default.attributesOfItem(atPath: localDirectory.appendingPathComponent("configuration.json").path)[.posixPermissions] as? NSNumber
        expect(filePermissions?.intValue == 0o600, "credential file owner-only permissions")
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: localDirectory.path)[.posixPermissions] as? NSNumber
        expect(directoryPermissions?.intValue == 0o700, "credential directory owner-only permissions")
        storedProfile.portalURL = "http://192.168.0.123/login"
        try LocalStore.save(profile: storedProfile, directory: localDirectory)
        let preserved = try LocalStore.read(storedProfile.ssid, "portal", directory: localDirectory)
        expect(preserved == secrets.portal, "settings updates retain stored passwords")
        let preservedProfile = try LocalStore.load(directory: localDirectory).profile
        expect(!preservedProfile.automatic, "local storage preserves paused automation")
        var profile = CampusProfile()
        try profile.validate()
        expect(profile.ssid == "HNPI-STU", "target SSID default")
        expect(profile.validPortalURL?.host == "192.168.0.123", "portal URL default")
        profile.portalURL = "javascript:alert(1)"
        expect(profile.validPortalURL == nil, "reject non-web URL")
        profile.portalURL = "https://a:b@example.com"
        expect(profile.validPortalURL == nil, "reject embedded credentials")
        profile.portalURL = "http://192.168.0.123"
        expect(PortalScript.origin(URL(string: "http://example.com:80/login")!) == "http://example.com", "normalize default port")
        expect(PortalScript.origin(URL(string: "https://example.com:8443/login")!) == "https://example.com:8443", "retain distinct port")

        var policy = AutoPolicy()
        let now = Date()
        expect(policy.shouldJoin(enabled: true, target: "HNPI-STU", current: "Home", visible: ["HNPI-STU"], busy: false, now: now), "connect visible exact target")
        expect(!policy.shouldJoin(enabled: true, target: "HNPI-STU", current: nil, visible: ["HNPI-STU-fake"], busy: false, now: now), "no substring match")
        expect(!policy.shouldJoin(enabled: false, target: "HNPI-STU", current: nil, visible: ["HNPI-STU"], busy: false, now: now), "pause toggle")
        expect(!policy.shouldJoin(enabled: true, target: "HNPI-STU", current: "HNPI-STU", visible: ["HNPI-STU"], busy: false, now: now), "don't reconnect connected target")
        policy.begin(at: now)
        expect(!policy.shouldJoin(enabled: true, target: "HNPI-STU", current: nil, visible: ["HNPI-STU"], busy: false, now: now.addingTimeInterval(59)), "retry cooldown")
        expect(policy.shouldJoin(enabled: true, target: "HNPI-STU", current: nil, visible: ["HNPI-STU"], busy: false, now: now.addingTimeInterval(61)), "retry after cooldown")
        policy.fail(); policy.fail(); policy.fail()
        expect(policy.suspended, "stop after three failures")
        policy.reset()
        expect(!policy.suspended, "manual retry resets suspension")

        var recovery = PortalRecovery()
        recovery.observe(.online)
        expect(!recovery.shouldAuthenticate(enabled: true, portalEnabled: true, now: now), "online does not reauthenticate")
        recovery.observe(.captive)
        expect(recovery.shouldAuthenticate(enabled: true, portalEnabled: true, now: now), "same SSID expired authentication recovers")
        recovery.begin(at: now)
        expect(!recovery.shouldAuthenticate(enabled: true, portalEnabled: true, now: now.addingTimeInterval(20)), "no duplicate submissions every heartbeat")
        expect(recovery.shouldAuthenticate(enabled: true, portalEnabled: true, now: now.addingTimeInterval(60)), "retry after cooldown")
        recovery.begin(at: now.addingTimeInterval(60))
        expect(!recovery.shouldAuthenticate(enabled: true, portalEnabled: true, now: now.addingTimeInterval(120)), "second retry backs off")
        expect(recovery.shouldAuthenticate(enabled: true, portalEnabled: true, now: now.addingTimeInterval(180)), "backoff expires")
        expect(!recovery.shouldAuthenticate(enabled: false, portalEnabled: true, now: now.addingTimeInterval(1000)), "pause blocks recovery")
        expect(!recovery.shouldAuthenticate(enabled: true, portalEnabled: false, now: now.addingTimeInterval(1000)), "disabled portal blocks recovery")
        recovery.observe(.online)
        expect(recovery.attempts == 0, "internet success resets attempts")
        recovery.observe(.unavailable)
        expect(!recovery.shouldAuthenticate(enabled: true, portalEnabled: true, now: now), "single timeout does not disrupt authentication")
        recovery.observe(.unavailable)
        expect(recovery.shouldAuthenticate(enabled: true, portalEnabled: true, now: now), "repeated failures recover")
        expect(InternetEvidence.classify(status: 200, body: "<html>Login</html>", expectedBody: "Microsoft Connect Test", sameEndpoint: true) == .captive, "HTTP 200 login is not internet")
        expect(InternetEvidence.classify(status: 302, body: "", expectedBody: "Microsoft Connect Test", sameEndpoint: true) == .captive, "redirect is captive")
        expect(InternetEvidence.classify(status: 204, body: "Microsoft Connect Test", expectedBody: "Microsoft Connect Test", sameEndpoint: true) != .success, "strict status")
        expect(InternetEvidence.classify(status: 200, body: "Microsoft Connect Test", expectedBody: "Microsoft Connect Test", sameEndpoint: false) == .captive, "changed endpoint cannot pass")
        expect(InternetEvidence.combine([.success, .unavailable]) != .online, "one whitelisted endpoint is insufficient")
        expect(InternetEvidence.combine([.success, .success]) == .online, "both probes confirm internet")
        expect(InternetEvidence.combine([.success, .captive]) == .captive, "captive evidence beats one successful probe")

        profile.username = "test-account'\\\"\n"
        let password = "test'\\\"\n</script>"
        profile.autoSubmit = true
        let script = try PortalScript.build(profile: profile, password: password)
        let context = JSContext()!
        context.evaluateScript("""
          var clicks = 0;
          var window = {};
          var location = {origin:'http://192.168.0.123'};
          var Event = function(name, opts) { this.type = name; };
          class HTMLInputElement {
            constructor(name,type) {this.name=name;this.type=type;this.disabled=false;this.form=null;this._value='';}
            get value(){return this._value;}
            set value(v){this._value=v;}
            getClientRects(){return [1];}
            dispatchEvent(e){}
          }
          var user = new HTMLInputElement('username','text');
          var pass = new HTMLInputElement('password','password');
          var submit = {type:'submit',disabled:false,getClientRects(){return [1]},click(){clicks++}};
          var document = {
            querySelectorAll(s){if(s==='input[type="password"]')return [pass]; if(s.startsWith('button'))return [submit];return [user];},
            querySelector(s){if(s==='[')throw Error('selector');if(s==='#username')return user;return null;}
          };
        """)
        expect(context.exception == nil, "mock browser setup")
        expect(context.evaluateScript(script)?.toString() == "submitted", "fill and submit form")
        expect(context.evaluateScript("user.value")?.toString() == profile.username, "preserve account escaping")
        expect(context.evaluateScript("pass.value")?.toString() == password, "preserve password escaping")
        expect(context.evaluateScript(script)?.toString() == "already-submitted", "prevent duplicate submission")
        expect(context.evaluateScript("clicks")?.toInt32() == 1, "one submission only")
        context.evaluateScript("window={};location.origin='http://unrelated.local';user.value='';pass.value=''")
        expect(context.evaluateScript(script)?.toString() == "wrong-origin", "reject unrelated origin")
        expect(context.evaluateScript("pass.value")?.toString() == "", "no credentials on wrong origin")
        context.evaluateScript("location.origin='http://192.168.0.123'")
        profile.userSelector = "["
        let invalidScript = try PortalScript.build(profile: profile, password: password)
        expect(context.evaluateScript(invalidScript)?.toString() == "invalid-selector", "reject invalid selector")
        profile.userSelector = ""; profile.autoSubmit = false
        let manualScript = try PortalScript.build(profile: profile, password: password)
        expect(context.evaluateScript(manualScript)?.toString() == "filled", "manual submit mode")
        expect(context.evaluateScript("clicks")?.toInt32() == 1, "manual mode doesn't click")
        profile.autoSubmit = true
        context.evaluateScript("window={};submit.type='button';submit.innerText='连接 Login'")
        let bilingualScript = try PortalScript.build(profile: profile, password: password)
        expect(context.evaluateScript(bilingualScript)?.toString() == "submitted", "recognize campus bilingual login button")
        expect(context.evaluateScript("clicks")?.toInt32() == 2, "click bilingual login once")
        print("PASS: \(checks) checks (profile, connection policy, real JavaScript execution).")
    }
}
