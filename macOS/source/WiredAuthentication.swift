import AppKit
import SystemConfiguration
import Darwin

struct WiredInterface: Equatable, Identifiable {
    let name: String
    let title: String
    let linked: Bool
    let hasAddress: Bool
    var id: String { name }
}

enum WiredSystem {
    static func interfaces() -> [WiredInterface] {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [] }
        let store = SCDynamicStoreCreate(nil, "CampusConnect" as CFString, nil, nil)
        return all.compactMap { interface in
            guard SCNetworkInterfaceGetInterfaceType(interface) == kSCNetworkInterfaceTypeEthernet,
                  let name = SCNetworkInterfaceGetBSDName(interface) as String? else { return nil }
            let link = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Interface/\(name)/Link" as CFString) as? [String: Any] }
            let title = (SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?) ?? name
            return WiredInterface(name: name, title: "\(title) (\(name))", linked: link?["Active"] as? Bool == true, hasAddress: hasAddress(name))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func hasAddress(_ name: String) -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return false }
        defer { freeifaddrs(list) }
        var item = list
        while let current = item {
            defer { item = current.pointee.ifa_next }
            guard String(cString: current.pointee.ifa_name) == name,
                  let address = current.pointee.ifa_addr else { continue }
            if address.pointee.sa_family == UInt8(AF_INET) {
                let value = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr.bigEndian
                if value != 0 && value >> 16 != 0xa9fe && value >> 24 != 127 { return true }
            }
            if address.pointee.sa_family == UInt8(AF_INET6) {
                let bytes = withUnsafeBytes(of: UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr) { Array($0) }
                if bytes.contains(where: { $0 != 0 }) && !(bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) && bytes != Array(repeating: 0, count: 15) + [1] { return true }
            }
        }
        return false
    }
    static func pppoeServices() -> [SCNetworkService] {
        guard let preferences = SCPreferencesCreate(nil, "CampusConnect" as CFString, nil),
              let all = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else { return [] }
        return all.filter { service in
            guard let interface = SCNetworkServiceGetInterface(service),
                  SCNetworkInterfaceGetInterfaceType(interface) == kSCNetworkInterfaceTypePPP,
                  let base = SCNetworkInterfaceGetInterface(interface) else { return false }
            return SCNetworkInterfaceGetInterfaceType(base) == kSCNetworkInterfaceTypeEthernet
        }
    }
    static func pppoeService(_ name: String) -> SCNetworkService? {
        let matches = pppoeServices().filter { SCNetworkServiceGetName($0) as String? == name }
        return matches.count == 1 ? matches[0] : nil
    }
    static func selected(_ profile: CampusProfile, from interfaces: [WiredInterface]) -> WiredInterface? {
        if profile.wiredAuth == .pppoe {
            guard let service = pppoeService(profile.broadbandName),
                  let interface = SCNetworkServiceGetInterface(service),
                  let base = SCNetworkInterfaceGetInterface(interface),
                  let name = SCNetworkInterfaceGetBSDName(base) as String? else { return nil }
            return interfaces.first { $0.name == name }
        }
        return select(name: profile.ethernetName, from: interfaces)
    }
    static func select(name: String, from interfaces: [WiredInterface]) -> WiredInterface? {
        if !name.isEmpty { return interfaces.first { $0.name == name } }
        return interfaces.first(where: { $0.linked }) ?? interfaces.first
    }
    static func connected(_ profile: CampusProfile) -> Bool {
        guard let selected = selected(profile, from: interfaces()), selected.linked else { return false }
        if profile.wiredAuth == .pppoe {
            guard let service = pppoeService(profile.broadbandName),
                  let serviceID = SCNetworkServiceGetServiceID(service),
                  let connection = SCNetworkConnectionCreateWithServiceID(nil, serviceID, nil, nil) else { return false }
            return SCNetworkConnectionGetStatus(connection) == .connected
        }
        return selected.hasAddress
    }
}

// Commands use an exact existing service and saved system credentials, never a shell.
@MainActor final class WiredAuthentication {
    private var process: Process?
    private var deadline: DispatchWorkItem?
    private var generation = 0
    static let networkSettings = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!
    func cancel() {
        generation += 1
        deadline?.cancel(); deadline = nil
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        process = nil
    }
    func prepare(_ profile: CampusProfile, manual: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        cancel()
        let expected = generation
        if profile.wiredAuth == .dot1x {
            // macOS owns EAP/certificates. Its Ethernet automatic-connection setting
            // starts the configured supplicant on link-up; manual login stays in Settings.
            if manual { NSWorkspace.shared.open(Self.networkSettings) }
            completion(.success("由 macOS 使用已有 802.1X 配置认证；请在网络设置中启用自动连接，需要时点按「连接」。"))
            return
        }
        if profile.wiredAuth == .client {
            let url = URL(fileURLWithPath: profile.authenticationClient)
            guard let bundle = Bundle(url: url), let executable = bundle.executableURL,
                  FileManager.default.isExecutableFile(atPath: executable.path) else {
                completion(.failure(AppError.message("学校客户端不存在或不是有效的 macOS 应用，请重新选择 .app。"))); return
            }
            if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }) {
                completion(.success("学校客户端已运行，正在检查实际联网状态。")); return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = manual; configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
                Task { @MainActor in
                    guard let self, self.generation == expected else { return }
                    completion(error.map { .failure($0) } ?? .success("学校客户端已打开，请在客户端完成登录。"))
                }
            }
            return
        }
        guard profile.wiredAuth == .pppoe, WiredSystem.pppoeService(profile.broadbandName) != nil else {
            completion(.failure(AppError.message("未找到唯一匹配的 PPPoE 服务，请先在 macOS 网络设置中创建服务、保存凭据并填写准确名称。"))); return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-connectpppoeservice", profile.broadbandName]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == expected else { return }
                self.deadline?.cancel(); self.deadline = nil; self.process = nil
                completion(result.terminationReason == .exit && result.terminationStatus == 0
                    ? .success("已向 macOS 提交 PPPoE 拨号请求，正在检查实际连接和联网状态。")
                    : .failure(AppError.message("macOS PPPoE 拨号请求失败，请检查系统中的服务、凭据和权限。")))
            }
        }
        do {
            self.process = process
            try process.run()
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.generation == expected else { return }
                self.cancel()
                completion(.failure(AppError.message("PPPoE 拨号请求超时，请检查系统网络设置。")))
            }
            deadline = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        } catch { self.process = nil; completion(.failure(error)) }
    }
}
