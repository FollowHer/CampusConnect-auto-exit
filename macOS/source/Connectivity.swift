import Foundation

// A dedicated loopback proxy binds both probes to physical Wi-Fi using Network.framework.
// It never falls back to the system proxy, VPN, or another network interface.
enum Connectivity {
    static let probes = [
        (URL(string: "http://www.msftconnecttest.com/connecttest.txt")!, "Microsoft Connect Test"),
        (URL(string: "https://www.apple.com/library/test/success.html")!, "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>")
    ]
    static func check(completion: @escaping (InternetStatus) -> Void) {
        let proxy = CampusProxy()
        proxy.start(host: "www.msftconnecttest.com", additionalHosts: ["www.apple.com"]) { result in
            guard case .success(let port) = result else { proxy.stop(); completion(.unavailable); return }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 6
            config.timeoutIntervalForResource = 8
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
            config.httpShouldSetCookies = false
            config.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": Int(port),
                "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": Int(port), "ExceptionsList": [], "ExcludeSimpleHostnames": 0]
            let session = URLSession(configuration: config, delegate: NoProbeRedirects(), delegateQueue: nil)
            Task {
                let result = await withTaskGroup(of: ProbeOutcome.self) { group in
                    for (url, expectedBody) in probes {
                        group.addTask {
                            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                            components.queryItems = [URLQueryItem(name: "campus_probe", value: UUID().uuidString)]
                            var request = URLRequest(url: components.url!)
                            request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
                            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
                            do {
                                let (data, response) = try await session.data(for: request)
                                guard let http = response as? HTTPURLResponse, data.count <= 4096 else { return .unavailable }
                                return InternetEvidence.classify(status: http.statusCode, body: String(decoding: data, as: UTF8.self),
                                    expectedBody: expectedBody, sameEndpoint: http.url == request.url)
                            } catch { return .unavailable }
                        }
                    }
                    var outcomes: [ProbeOutcome] = []
                    for await outcome in group { outcomes.append(outcome) }
                    return InternetEvidence.combine(outcomes)
                }
                session.invalidateAndCancel(); proxy.stop()
                DispatchQueue.main.async { completion(result) }
            }
        }
    }
}
private final class NoProbeRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
