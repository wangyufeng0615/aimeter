import Foundation

/// One shared Antigravity quota bucket. Antigravity reports the remaining
/// fraction per model; models that share a bucket report identical values.
struct QuotaPool: Equatable, Identifiable {
    let name: String
    let usedPct: Double
    let resetsAt: Date?

    var id: String { "\(name)|\(resetsAt?.timeIntervalSince1970 ?? 0)|\(usedPct)" }
}

struct AntigravityQuota: Equatable {
    let pools: [QuotaPool]
    let updatedAt: Date

    var headlinePct: Double? { pools.first?.usedPct }
}

/// Reads model quotas from the running Antigravity language server. The IDE
/// and CLI write their loopback port and per-launch CSRF token to
/// `daemon/hub_<port>.json`; only 127.0.0.1 is contacted and the token is
/// never persisted.
enum AntigravityQuotaReader {
    private struct Hub {
        let pid: Int32
        let httpPort: Int
        let csrfToken: String
        let modified: Date
    }

    static func read() -> AntigravityQuota? {
        read(daemonDirs: AppPaths.antigravityDaemonDirs, now: Date())
    }

    static func read(daemonDirs: [URL], now: Date) -> AntigravityQuota? {
        for hub in liveHubs(in: daemonDirs) {
            if let data = fetchUserStatus(hub), let quota = parse(data, now: now) {
                return quota
            }
        }
        return nil
    }

    static func parse(_ data: Data, now: Date) -> AntigravityQuota? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["userStatus"] as? [String: Any],
              let config = status["cascadeModelConfigData"] as? [String: Any],
              let models = config["clientModelConfigs"] as? [[String: Any]] else { return nil }

        struct Bucket {
            var names: [String] = []
            let usedPct: Double
            let resetsAt: Date?
        }
        var order: [String] = []
        var buckets: [String: Bucket] = [:]

        for model in models {
            guard let quota = model["quotaInfo"] as? [String: Any] else { continue }
            // proto3 JSON omits zero values: an exhausted bucket has no
            // remainingFraction but still carries its reset time.
            let remaining = (quota["remainingFraction"] as? NSNumber)?.doubleValue ?? 0
            let resetText = quota["resetTime"] as? String
            let key = "\(Int((remaining * 1_000_000).rounded()))|\(resetText ?? "")"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = Bucket(
                    usedPct: min(100, max(0, (1 - remaining) * 100)),
                    resetsAt: resetText.flatMap(parseDate)
                )
            }
            if let label = model["label"] as? String,
               let family = family(of: label),
               buckets[key]?.names.contains(family) == false {
                buckets[key]?.names.append(family)
            }
        }

        let pools = order.compactMap { key -> QuotaPool? in
            guard let bucket = buckets[key] else { return nil }
            let name = bucket.names.isEmpty ? "Antigravity" : bucket.names.joined(separator: "/")
            return QuotaPool(name: name, usedPct: bucket.usedPct, resetsAt: bucket.resetsAt)
        }
        guard !pools.isEmpty else { return nil }
        return AntigravityQuota(pools: pools, updatedAt: now)
    }

    /// "Gemini 4 Neon (High)" → "Gemini", "GPT-OSS 120B (Medium)" → "GPT".
    /// Orchestrator entries are routing aliases, not a model family.
    private static func family(of label: String) -> String? {
        guard let first = label.split(separator: " ").first,
              first != "Orchestrator" else { return nil }
        return first.split(separator: "-").first.map(String.init)
    }

    private static func liveHubs(in dirs: [URL]) -> [Hub] {
        let fm = FileManager.default
        var hubs: [Hub] = []
        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in files where url.lastPathComponent.hasPrefix("hub_") && url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pid = (json["pid"] as? NSNumber)?.int32Value,
                      let port = (json["httpPort"] as? NSNumber)?.intValue,
                      let token = json["csrfToken"] as? String,
                      port > 0, !token.isEmpty,
                      kill(pid, 0) == 0 || errno == EPERM else { continue }
                let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
                hubs.append(Hub(pid: pid, httpPort: port, csrfToken: token, modified: modified ?? .distantPast))
            }
        }
        return hubs.sorted { $0.modified > $1.modified }
    }

    private static func fetchUserStatus(_ hub: Hub) -> Data? {
        guard let url = URL(string: "http://127.0.0.1:\(hub.httpPort)/exa.language_server_pb.LanguageServerService/GetUserStatus") else {
            return nil
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(hub.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.httpBody = Data("{}".utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForResource = 4
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        session.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { result = data }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoBasic = ISO8601DateFormatter()

    private static func parseDate(_ value: String) -> Date? {
        isoFull.date(from: value) ?? isoBasic.date(from: value)
    }
}
