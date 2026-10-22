import AppKit
import Foundation

@main struct LifecycleTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            checks += 1
            if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        for wired in [false, true] {
            for enabled in [false, true] {
                for settings in [false, true] {
                    for connected in [false, true] {
                        for fresh in [false, true] {
                            for result in [InternetStatus.online, .unavailable] {
                                autoreleasepool {
                                    var profile = CampusProfile()
                                    profile.ssid = wired ? "" : "HNPI-STU"
                                    profile.exitAfterConnected = enabled
                                    var terminations = 0
                                    let model = AppModel(preview: true, initialProfile: profile, settingsSession: settings,
                                                         terminateApplication: { terminations += 1 })
                                    model.handleInternetResult(result, expectedGeneration: fresh ? 0 : -1,
                                                               expectedSSID: profile.ssid, connected: connected)
                                    let shouldExit = enabled && !settings && connected && fresh && result == .online
                                    expect(terminations == (shouldExit ? 1 : 0), "exit requires current target + online + enabled + non-settings session")
                                    expect(model.isExiting == shouldExit, "exit state reflects the applied result")
                                    if settings { expect(model.page == .settings, "settings launch opens settings") }
                                    if shouldExit {
                                        expect(!model.portal.loading, "exit stops portal loading")
                                        model.quit()
                                        expect(terminations == 1, "exit is idempotent")
                                        model.handleInternetResult(.online, expectedGeneration: 0, expectedSSID: profile.ssid, connected: true)
                                        expect(terminations == 1, "late callbacks cannot repeat termination")
                                    } else { model.quit() }
                                }
                            }
                        }
                    }
                }
            }
        }
        var profile = CampusProfile()
        profile.exitAfterConnected = true
        var terminations = 0
        let model = AppModel(preview: true, initialProfile: profile, settingsSession: false,
                             terminateApplication: { terminations += 1 })
        model.handleInternetResult(.online, expectedGeneration: 0, expectedSSID: "different-network", connected: true)
        expect(terminations == 0 && model.internet == nil, "a different saved network cannot trigger exit")
        model.quit()
        print("PASS: \(checks) macOS lifecycle assertions (64 combinations; no campus network requests).")
    }
}
