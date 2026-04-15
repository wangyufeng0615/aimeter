import Foundation

enum Pricing {
    struct Rate {
        let input: Double           // cost per token
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
        let inputTiered: Double?    // above 200K threshold
        let outputTiered: Double?
        let cacheWriteTiered: Double?
        let cacheReadTiered: Double?
    }

    // `internal` so @testable can cover the tier-boundary semantics directly.
    static let tieredThreshold = 200_000

    // Hardcoded fallback — matches LiteLLM pricing as of 2026-04.
    private static let defaultRates: [String: Rate] = [
        // Claude models
        "claude-opus-4-6": Rate(input: 5e-6, output: 25e-6, cacheRead: 0.5e-6, cacheWrite: 6.25e-6,
                                inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-opus-4-1": Rate(input: 15e-6, output: 75e-6, cacheRead: 1.5e-6, cacheWrite: 18.75e-6,
                                inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-sonnet-4-6": Rate(input: 3e-6, output: 15e-6, cacheRead: 0.3e-6, cacheWrite: 3.75e-6,
                                  inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-haiku-4-5": Rate(input: 1e-6, output: 5e-6, cacheRead: 0.1e-6, cacheWrite: 1.25e-6,
                                 inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        // OpenAI / Codex models
        "gpt-5.4": Rate(input: 2.5e-6, output: 15e-6, cacheRead: 0.25e-6, cacheWrite: 2.5e-6,
                        inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.4-mini": Rate(input: 0.75e-6, output: 4.5e-6, cacheRead: 0.075e-6, cacheWrite: 0.75e-6,
                             inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.4-nano": Rate(input: 0.2e-6, output: 1.25e-6, cacheRead: 0.02e-6, cacheWrite: 0.2e-6,
                             inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.4-pro": Rate(input: 30e-6, output: 180e-6, cacheRead: 3e-6, cacheWrite: 30e-6,
                            inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.3-codex": Rate(input: 1.75e-6, output: 14e-6, cacheRead: 0.175e-6, cacheWrite: 1.75e-6,
                              inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.2-codex": Rate(input: 1.75e-6, output: 14e-6, cacheRead: 0.175e-6, cacheWrite: 1.75e-6,
                              inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.1-codex": Rate(input: 1.25e-6, output: 10e-6, cacheRead: 0.125e-6, cacheWrite: 1.25e-6,
                              inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.1-codex-mini": Rate(input: 0.25e-6, output: 2e-6, cacheRead: 0.025e-6, cacheWrite: 0.25e-6,
                                   inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
    ]

    private static let lock = NSLock()
    private static var _rates: [String: Rate] = defaultRates
    private static var rates: [String: Rate] {
        get { lock.lock(); defer { lock.unlock() }; return _rates }
        set { lock.lock(); defer { lock.unlock() }; _rates = newValue }
    }

    private static var pricingLoaded = false
    private static let cacheFile: URL = {
        // Prefer ~/Library/Caches; fall back to ~/.claude/
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let dir = caches.appendingPathComponent("com.aimeter.app")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pricing.json")
    }()

    /// Call from background thread. Only fetches once per app lifecycle.
    static func loadFromLiteLLM() {
        guard !pricingLoaded else { return }
        pricingLoaded = true

        if let cached = readCache(), cached.age < 86400 {
            rates = mergeRates(cached.rates)
            return
        }
        if let fetched = fetchLiteLLM() {
            let merged = mergeRates(fetched)
            rates = merged
            writeCache(merged)
        } else if let cached = readCache() {
            rates = mergeRates(cached.rates)
        }
    }

    /// Merge fetched rates with defaults (so OpenAI models always have pricing)
    private static func mergeRates(_ fetched: [String: Rate]) -> [String: Rate] {
        var result = defaultRates
        for (k, v) in fetched { result[k] = v }
        return result
    }

    /// Full cost from input/output/cache breakdown (Claude JSONL data)
    static func cost(model: String, input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        guard let r = rates[modelFamily(model)] else { return 0 }
        return tiered(input, base: r.input, tier: r.inputTiered)
             + tiered(output, base: r.output, tier: r.outputTiered)
             + tiered(cacheWrite, base: r.cacheWrite, tier: r.cacheWriteTiered)
             + tiered(cacheRead, base: r.cacheRead, tier: r.cacheReadTiered)
    }

    /// Estimated cost from total tokens only (Codex SQLite — no input/output split).
    /// Uses blended rate: ~90% cached input, ~9% input, ~1% output.
    static func estimatedCost(model: String, totalTokens: Int) -> Double {
        guard let r = rates[modelFamily(model)], totalTokens > 0 else { return 0 }
        let blended = 0.90 * r.cacheRead + 0.09 * r.input + 0.01 * r.output
        return Double(totalTokens) * blended
    }

    // `internal` so @testable tests can verify the tier-boundary math.
    static func tiered(_ tokens: Int, base: Double, tier: Double?) -> Double {
        guard tokens > 0 else { return 0 }
        guard let tier, tokens > tieredThreshold else {
            return Double(tokens) * base
        }
        return Double(min(tokens, tieredThreshold)) * base
             + Double(tokens - tieredThreshold) * tier
    }

    /// Map model name to pricing key.
    static func modelFamily(_ model: String) -> String {
        let m = model.lowercased()
        // Claude
        if m.contains("opus-4-1") || m.contains("opus-4-20250514") { return "claude-opus-4-1" }
        if m.contains("opus")   { return "claude-opus-4-6" }
        if m.contains("sonnet") { return "claude-sonnet-4-6" }
        if m.contains("haiku")  { return "claude-haiku-4-5" }
        // OpenAI — match most specific first
        if m.contains("gpt-5.4-mini")   { return "gpt-5.4-mini" }
        if m.contains("gpt-5.4-nano")   { return "gpt-5.4-nano" }
        if m.contains("gpt-5.4-pro")    { return "gpt-5.4-pro" }
        if m.contains("5.1-codex-mini") { return "gpt-5.1-codex-mini" }
        if m.contains("5.1-codex-max")  { return "gpt-5.1-codex" }  // no separate pricing, use codex
        if m.contains("5.1-codex")      { return "gpt-5.1-codex" }
        if m.contains("5.2-codex")      { return "gpt-5.2-codex" }
        if m.contains("5.3-codex")      { return "gpt-5.3-codex" }
        if m.contains("gpt-5.4")        { return "gpt-5.4" }
        if m.contains("gpt-5")          { return "gpt-5.4" }  // fallback for unknown gpt-5.x
        return "claude-sonnet-4-6"  // ultimate fallback
    }

    static func shortenModelName(_ model: String) -> String {
        var name = model.replacingOccurrences(of: "claude-", with: "")
        if let range = name.range(of: #"-\d{8}.*$"#, options: .regularExpression) {
            name = String(name[..<range.lowerBound])
        }
        return name
    }

    // MARK: - LiteLLM fetch

    private static let maxResponseBytes = 4 * 1024 * 1024  // LiteLLM JSON is ~700KB; cap at 4MB

    private static func fetchLiteLLM() -> [String: Rate]? {
        guard let url = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")
        else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        var result: [String: Rate]? = nil
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { sem.signal() }
            // Validate HTTP status, content-type, and size
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data, data.count <= maxResponseBytes,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            // Filter out parsed rates with non-finite or unreasonable values
            let parsed = parseLiteLLM(json).filter { _, r in
                isSane(r.input) && isSane(r.output) &&
                isSane(r.cacheRead) && isSane(r.cacheWrite)
            }
            result = parsed.isEmpty ? nil : parsed
        }.resume()
        sem.wait()
        return result
    }

    /// Sanity check: must be finite, non-negative, and below $1/token (sanity ceiling)
    private static func isSane(_ v: Double) -> Bool {
        v.isFinite && v >= 0 && v < 0.01
    }

    static func parseLiteLLM(_ json: [String: Any]) -> [String: Rate] {
        var direct: [String: Rate] = [:]
        var fallback: [String: Rate] = [:]
        var directSource: [String: String] = [:]
        var fallbackSource: [String: String] = [:]

        for (key, value) in json {
            guard let info = value as? [String: Any] else { continue }
            let k = key.lowercased()
            guard let family = canonicalLiteLLMKey(k) else { continue }

            guard let inp = info["input_cost_per_token"] as? Double,
                  let out = info["output_cost_per_token"] as? Double
            else { continue }

            let rate = Rate(
                input: inp, output: out,
                cacheRead: info["cache_read_input_token_cost"] as? Double ?? inp * 0.1,
                cacheWrite: info["cache_creation_input_token_cost"] as? Double ?? inp,
                inputTiered: info["input_cost_per_token_above_200k_tokens"] as? Double
                    ?? info["input_cost_per_token_above_272k_tokens"] as? Double,
                outputTiered: info["output_cost_per_token_above_200k_tokens"] as? Double
                    ?? info["output_cost_per_token_above_272k_tokens"] as? Double,
                cacheWriteTiered: info["cache_creation_input_token_cost_above_200k_tokens"] as? Double
                    ?? info["cache_creation_input_token_cost_above_272k_tokens"] as? Double,
                cacheReadTiered: info["cache_read_input_token_cost_above_200k_tokens"] as? Double
                    ?? info["cache_read_input_token_cost_above_272k_tokens"] as? Double)

            // For Claude: prefer direct API over Bedrock/Azure
            let isDirect = k.hasPrefix("claude") || k.hasPrefix("gpt-")
            if isDirect {
                let current = directSource[family] ?? ""
                if current.isEmpty || shouldPreferLiteLLMKey(k, over: current, canonical: family) {
                    direct[family] = rate
                    directSource[family] = k
                }
            } else {
                let current = fallbackSource[family] ?? ""
                if current.isEmpty || shouldPreferLiteLLMKey(k, over: current, canonical: family) {
                    fallback[family] = rate
                    fallbackSource[family] = k
                }
            }
        }

        var result: [String: Rate] = [:]
        for fam in direct.keys { result[fam] = direct[fam] }
        for fam in fallback.keys where result[fam] == nil { result[fam] = fallback[fam] }
        return result
    }

    private static func canonicalLiteLLMKey(_ key: String) -> String? {
        if key == "claude-opus-4-6" || key.hasPrefix("claude-opus-4-6-")
            || key == "claude-opus-4-5" || key.hasPrefix("claude-opus-4-5-") {
            return "claude-opus-4-6"
        }
        if key == "claude-opus-4-1" || key.hasPrefix("claude-opus-4-1-")
            || key == "claude-opus-4-20250514" {
            return "claude-opus-4-1"
        }
        if key == "claude-sonnet-4-6" || key.hasPrefix("claude-sonnet-4-6-")
            || key == "claude-sonnet-4-5" || key.hasPrefix("claude-sonnet-4-5-")
            || key == "claude-sonnet-4-20250514" {
            return "claude-sonnet-4-6"
        }
        if key == "claude-haiku-4-5" || key.hasPrefix("claude-haiku-4-5-") {
            return "claude-haiku-4-5"
        }
        if key == "gpt-5.4-mini" || key.hasPrefix("gpt-5.4-mini-20") {
            return "gpt-5.4-mini"
        }
        if key == "gpt-5.4-nano" || key.hasPrefix("gpt-5.4-nano-20") {
            return "gpt-5.4-nano"
        }
        if key == "gpt-5.4-pro" || key.hasPrefix("gpt-5.4-pro-20") {
            return "gpt-5.4-pro"
        }
        if key == "gpt-5.4" || key.hasPrefix("gpt-5.4-20") {
            return "gpt-5.4"
        }
        if key == "gpt-5.3-codex" || key.hasPrefix("gpt-5.3-codex-20") {
            return "gpt-5.3-codex"
        }
        if key == "gpt-5.2-codex" || key.hasPrefix("gpt-5.2-codex-20") {
            return "gpt-5.2-codex"
        }
        if key == "gpt-5.1-codex-mini" || key.hasPrefix("gpt-5.1-codex-mini-20") {
            return "gpt-5.1-codex-mini"
        }
        if key == "gpt-5.1-codex" || key.hasPrefix("gpt-5.1-codex-20")
            || key == "gpt-5.1-codex-max" || key.hasPrefix("gpt-5.1-codex-max-20") {
            return "gpt-5.1-codex"
        }
        return nil
    }

    private static func shouldPreferLiteLLMKey(_ candidate: String, over current: String, canonical: String) -> Bool {
        if current.isEmpty { return true }
        if candidate == canonical && current != canonical { return true }
        if candidate != canonical && current == canonical { return false }

        let canonicalPrefix = canonical + "-"
        let candidateIsCanonicalVariant = candidate.hasPrefix(canonicalPrefix)
        let currentIsCanonicalVariant = current.hasPrefix(canonicalPrefix)

        if candidateIsCanonicalVariant != currentIsCanonicalVariant {
            return candidateIsCanonicalVariant
        }

        return candidate > current
    }

    // MARK: - Local cache

    private static func readCache() -> (rates: [String: Rate], age: TimeInterval)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
              let mod = attrs[.modificationDate] as? Date,
              let data = try? Data(contentsOf: cacheFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]]
        else { return nil }

        var result: [String: Rate] = [:]
        for (family, p) in json {
            result[family] = Rate(
                input: p["input"] ?? 0, output: p["output"] ?? 0,
                cacheRead: p["cacheRead"] ?? 0, cacheWrite: p["cacheWrite"] ?? 0,
                inputTiered: p["inputTiered"], outputTiered: p["outputTiered"],
                cacheWriteTiered: p["cacheWriteTiered"], cacheReadTiered: p["cacheReadTiered"])
        }
        return result.isEmpty ? nil : (result, -mod.timeIntervalSinceNow)
    }

    private static func writeCache(_ rates: [String: Rate]) {
        var json: [String: [String: Double]] = [:]
        for (family, r) in rates {
            var d: [String: Double] = [
                "input": r.input, "output": r.output,
                "cacheRead": r.cacheRead, "cacheWrite": r.cacheWrite
            ]
            if let v = r.inputTiered { d["inputTiered"] = v }
            if let v = r.outputTiered { d["outputTiered"] = v }
            if let v = r.cacheWriteTiered { d["cacheWriteTiered"] = v }
            if let v = r.cacheReadTiered { d["cacheReadTiered"] = v }
            json[family] = d
        }
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            try? data.write(to: cacheFile, options: .atomic)
        }
    }
}
