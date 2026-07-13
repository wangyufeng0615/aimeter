import Foundation

enum Pricing {
    struct Rate {
        let input: Double           // cost per token
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
        let cacheWrite1h: Double
        let inputTiered: Double?    // above 200K threshold
        let outputTiered: Double?
        let cacheWriteTiered: Double?
        let cacheReadTiered: Double?
        let cacheWrite1hTiered: Double?
        let longContextThreshold: Int?

        init(input: Double, output: Double, cacheRead: Double, cacheWrite: Double,
             cacheWrite1h: Double? = nil, inputTiered: Double?, outputTiered: Double?,
             cacheWriteTiered: Double?, cacheReadTiered: Double?,
             cacheWrite1hTiered: Double? = nil, longContextThreshold: Int? = nil) {
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
            self.cacheWrite1h = cacheWrite1h ?? cacheWrite
            self.inputTiered = inputTiered
            self.outputTiered = outputTiered
            self.cacheWriteTiered = cacheWriteTiered
            self.cacheReadTiered = cacheReadTiered
            self.cacheWrite1hTiered = cacheWrite1hTiered
            self.longContextThreshold = longContextThreshold
        }
    }

    // Hardcoded fallback — verified against provider pricing as of 2026-07.
    private static let baseDefaultRates: [String: Rate] = [
        // Claude models
        "claude-fable-5": Rate(input: 10e-6, output: 50e-6, cacheRead: 1e-6,
                               cacheWrite: 12.5e-6, cacheWrite1h: 20e-6,
                               inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-mythos-5": Rate(input: 10e-6, output: 50e-6, cacheRead: 1e-6,
                                cacheWrite: 12.5e-6, cacheWrite1h: 20e-6,
                                inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-opus-4-8": Rate(input: 5e-6, output: 25e-6, cacheRead: 0.5e-6,
                                cacheWrite: 6.25e-6, cacheWrite1h: 10e-6,
                                inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-opus-4-8-fast": Rate(input: 10e-6, output: 50e-6, cacheRead: 1e-6,
                                     cacheWrite: 12.5e-6, cacheWrite1h: 20e-6,
                                     inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-opus-4-7": Rate(input: 5e-6, output: 25e-6, cacheRead: 0.5e-6,
                                cacheWrite: 6.25e-6, cacheWrite1h: 10e-6,
                                inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-opus-4-7-fast": Rate(input: 30e-6, output: 150e-6, cacheRead: 3e-6,
                                     cacheWrite: 37.5e-6, cacheWrite1h: 60e-6,
                                     inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-opus-4-6": Rate(input: 5e-6, output: 25e-6, cacheRead: 0.5e-6,
                                cacheWrite: 6.25e-6, cacheWrite1h: 10e-6,
                                inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-opus-4-1": Rate(input: 15e-6, output: 75e-6, cacheRead: 1.5e-6,
                                cacheWrite: 18.75e-6, cacheWrite1h: 30e-6,
                                inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        // Introductory pricing through 2026-08-31; the daily LiteLLM refresh
        // takes precedence when Anthropic moves it to standard $3/$15 pricing.
        "claude-sonnet-5": Rate(input: 2e-6, output: 10e-6, cacheRead: 0.2e-6,
                                 cacheWrite: 2.5e-6, cacheWrite1h: 4e-6,
                                 inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-sonnet-4-6": Rate(input: 3e-6, output: 15e-6, cacheRead: 0.3e-6,
                                  cacheWrite: 3.75e-6, cacheWrite1h: 6e-6,
                                  inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-haiku-4-5": Rate(input: 1e-6, output: 5e-6, cacheRead: 0.1e-6,
                                 cacheWrite: 1.25e-6, cacheWrite1h: 2e-6,
                                 inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        // OpenAI / Codex models
        "gpt-5.4": Rate(input: 2.5e-6, output: 15e-6, cacheRead: 0.25e-6, cacheWrite: 2.5e-6,
                        inputTiered: 5e-6, outputTiered: 22.5e-6,
                        cacheWriteTiered: 5e-6, cacheReadTiered: 0.5e-6,
                        longContextThreshold: 272_000),
        "gpt-5.4-mini": Rate(input: 0.75e-6, output: 4.5e-6, cacheRead: 0.075e-6, cacheWrite: 0.75e-6,
                             inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.4-nano": Rate(input: 0.2e-6, output: 1.25e-6, cacheRead: 0.02e-6, cacheWrite: 0.2e-6,
                             inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.4-pro": Rate(input: 30e-6, output: 180e-6, cacheRead: 30e-6, cacheWrite: 30e-6,
                            inputTiered: 60e-6, outputTiered: 270e-6,
                            cacheWriteTiered: 60e-6, cacheReadTiered: 60e-6,
                            longContextThreshold: 272_000),
        "gpt-5.5": Rate(input: 5e-6, output: 30e-6, cacheRead: 0.5e-6, cacheWrite: 5e-6,
                        inputTiered: 10e-6, outputTiered: 45e-6,
                        cacheWriteTiered: 10e-6, cacheReadTiered: 1e-6,
                        longContextThreshold: 272_000),
        "gpt-5.5-pro": Rate(input: 30e-6, output: 180e-6, cacheRead: 30e-6, cacheWrite: 30e-6,
                            inputTiered: nil, outputTiered: nil,
                            cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.6-sol": Rate(input: 5e-6, output: 30e-6, cacheRead: 0.5e-6, cacheWrite: 6.25e-6,
                            inputTiered: 10e-6, outputTiered: 45e-6,
                            cacheWriteTiered: 12.5e-6, cacheReadTiered: 1e-6,
                            longContextThreshold: 272_000),
        "gpt-5.6-terra": Rate(input: 2.5e-6, output: 15e-6, cacheRead: 0.25e-6, cacheWrite: 3.125e-6,
                              inputTiered: 5e-6, outputTiered: 22.5e-6,
                              cacheWriteTiered: 6.25e-6, cacheReadTiered: 0.5e-6,
                              longContextThreshold: 272_000),
        "gpt-5.6-luna": Rate(input: 1e-6, output: 6e-6, cacheRead: 0.1e-6, cacheWrite: 1.25e-6,
                             inputTiered: 2e-6, outputTiered: 9e-6,
                             cacheWriteTiered: 2.5e-6, cacheReadTiered: 0.2e-6,
                             longContextThreshold: 272_000),
        "gpt-5.3-codex": Rate(input: 1.75e-6, output: 14e-6, cacheRead: 0.175e-6, cacheWrite: 1.75e-6,
                              inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.2-codex": Rate(input: 1.75e-6, output: 14e-6, cacheRead: 0.175e-6, cacheWrite: 1.75e-6,
                              inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.1-codex": Rate(input: 1.25e-6, output: 10e-6, cacheRead: 0.125e-6, cacheWrite: 1.25e-6,
                              inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "gpt-5.1-codex-mini": Rate(input: 0.25e-6, output: 2e-6, cacheRead: 0.025e-6, cacheWrite: 0.25e-6,
                                   inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
    ]

    private static var defaultRates: [String: Rate] {
        var result = baseDefaultRates
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let standardPricingStart = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 1
        ))!
        if Date() >= standardPricingStart {
            result["claude-sonnet-5"] = Rate(
                input: 3e-6, output: 15e-6, cacheRead: 0.3e-6,
                cacheWrite: 3.75e-6, cacheWrite1h: 6e-6,
                inputTiered: nil, outputTiered: nil,
                cacheWriteTiered: nil, cacheReadTiered: nil
            )
        }
        return result
    }

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
        for (k, v) in fetched { result[k] = normalizedRate(v, family: k) }
        return result
    }

    /// Keep provider-documented invariants authoritative when LiteLLM or an
    /// older on-disk cache still contains stale values.
    private static func normalizedRate(_ rate: Rate, family: String) -> Rate {
        let fallback = defaultRates[family]
        let proWithoutCacheDiscount = family == "gpt-5.4-pro" || family == "gpt-5.5-pro"
        let noPublishedLongContextPremium = family == "gpt-5.5-pro"
        return Rate(
            input: rate.input,
            output: rate.output,
            cacheRead: proWithoutCacheDiscount ? rate.input : rate.cacheRead,
            cacheWrite: rate.cacheWrite,
            cacheWrite1h: rate.cacheWrite1h,
            inputTiered: noPublishedLongContextPremium ? nil : (rate.inputTiered ?? fallback?.inputTiered),
            outputTiered: noPublishedLongContextPremium ? nil : (rate.outputTiered ?? fallback?.outputTiered),
            cacheWriteTiered: noPublishedLongContextPremium
                ? nil : (rate.cacheWriteTiered ?? fallback?.cacheWriteTiered),
            cacheReadTiered: proWithoutCacheDiscount
                ? (noPublishedLongContextPremium ? nil : (rate.inputTiered ?? fallback?.inputTiered))
                : (rate.cacheReadTiered ?? fallback?.cacheReadTiered),
            cacheWrite1hTiered: noPublishedLongContextPremium
                ? nil : (rate.cacheWrite1hTiered ?? fallback?.cacheWrite1hTiered),
            longContextThreshold: noPublishedLongContextPremium
                ? nil : (rate.longContextThreshold ?? fallback?.longContextThreshold)
        )
    }

    /// Full cost from input/output/cache breakdown (Claude JSONL data)
    static func cost(model: String, speed: String? = nil, inferenceGeo: String? = nil,
                     input: Int, output: Int, cacheWrite: Int,
                     cacheWrite1h: Int = 0, cacheRead: Int) -> Double {
        let family = modelFamily(model)
        let billingFamily = billingFamily(family, speed: speed)
        guard let r = rates[billingFamily] ?? rates[family] else { return 0 }
        let promptTokens = [input, cacheWrite, cacheWrite1h, cacheRead]
            .reduce(0) { $0 + max(0, $1) }
        let usesLongContextPricing = r.longContextThreshold.map { promptTokens > $0 } ?? false

        func price(_ tokens: Int, base: Double, premium: Double?) -> Double {
            guard tokens > 0 else { return 0 }
            let unitPrice = usesLongContextPricing ? (premium ?? base) : base
            return Double(tokens) * unitPrice
        }

        let subtotal = price(input, base: r.input, premium: r.inputTiered)
            + price(output, base: r.output, premium: r.outputTiered)
            + price(cacheWrite, base: r.cacheWrite, premium: r.cacheWriteTiered)
            + price(cacheWrite1h, base: r.cacheWrite1h, premium: r.cacheWrite1hTiered)
            + price(cacheRead, base: r.cacheRead, premium: r.cacheReadTiered)
        return subtotal * geographyMultiplier(family: family, inferenceGeo: inferenceGeo)
    }

    static func hasRate(model: String, speed: String? = nil) -> Bool {
        let family = modelFamily(model)
        let billingFamily = billingFamily(family, speed: speed)
        return rates[billingFamily] != nil || rates[family] != nil
    }

    /// Map model name to pricing key.
    static func modelFamily(_ model: String) -> String {
        let m = model.lowercased()
        // Claude
        if m.contains("fable-5") { return "claude-fable-5" }
        if m.contains("mythos-5") { return "claude-mythos-5" }
        if m.contains("opus-4-8") { return "claude-opus-4-8" }
        if m.contains("opus-4-7") { return "claude-opus-4-7" }
        if m.contains("opus-4-1") || m.contains("opus-4-20250514") { return "claude-opus-4-1" }
        if m.contains("opus-4-6") || m.contains("opus-4-5") { return "claude-opus-4-6" }
        if m.contains("sonnet-5") { return "claude-sonnet-5" }
        if m.contains("sonnet-4-6") || m.contains("sonnet-4-5")
            || m.contains("sonnet-4-20250514") { return "claude-sonnet-4-6" }
        if m.contains("haiku-4-5") { return "claude-haiku-4-5" }
        // OpenAI — match most specific first
        if m.contains("gpt-5.6-sol-pro") { return "unknown" }
        if m.contains("gpt-5.6-terra")   { return "gpt-5.6-terra" }
        if m.contains("gpt-5.6-luna")    { return "gpt-5.6-luna" }
        if m.contains("gpt-5.6-sol")     { return "gpt-5.6-sol" }
        if m == "gpt-5.6" || m.hasSuffix("/gpt-5.6")
            || m.range(of: #"gpt-5\.6-20\d{6}$"#, options: .regularExpression) != nil {
            return "gpt-5.6-sol"
        }
        if m.contains("gpt-5.4-mini")   { return "gpt-5.4-mini" }
        if m.contains("gpt-5.4-nano")   { return "gpt-5.4-nano" }
        if m.contains("gpt-5.4-pro")    { return "gpt-5.4-pro" }
        if m.contains("gpt-5.5-pro")    { return "gpt-5.5-pro" }
        if m.contains("gpt-5.5")        { return "gpt-5.5" }
        if m.contains("5.1-codex-mini") { return "gpt-5.1-codex-mini" }
        if m.contains("5.1-codex-max")  { return "gpt-5.1-codex" }  // no separate pricing, use codex
        if m.contains("5.1-codex")      { return "gpt-5.1-codex" }
        if m.contains("5.2-codex")      { return "gpt-5.2-codex" }
        if m.contains("5.3-codex")      { return "gpt-5.3-codex" }
        if m.contains("gpt-5.4")        { return "gpt-5.4" }
        return "unknown"
    }

    private static func billingFamily(_ family: String, speed: String?) -> String {
        guard speed?.lowercased() == "fast" else { return family }
        switch family {
        case "claude-opus-4-8", "claude-opus-4-7":
            return "\(family)-fast"
        default:
            return family
        }
    }

    private static func geographyMultiplier(family: String, inferenceGeo: String?) -> Double {
        guard inferenceGeo?.lowercased() == "us" else { return 1 }
        switch family {
        case "claude-fable-5", "claude-mythos-5", "claude-opus-4-8",
             "claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-5",
             "claude-sonnet-4-6":
            return 1.1
        default:
            return 1
        }
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
                isSane(r.cacheRead) && isSane(r.cacheWrite) && isSane(r.cacheWrite1h)
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

            let has272KPricing = info["input_cost_per_token_above_272k_tokens"] != nil
                || info["output_cost_per_token_above_272k_tokens"] != nil
                || info["cache_read_input_token_cost_above_272k_tokens"] != nil
                || info["cache_creation_input_token_cost_above_272k_tokens"] != nil
            let has200KPricing = info["input_cost_per_token_above_200k_tokens"] != nil
                || info["output_cost_per_token_above_200k_tokens"] != nil
                || info["cache_read_input_token_cost_above_200k_tokens"] != nil
                || info["cache_creation_input_token_cost_above_200k_tokens"] != nil

            let rate = normalizedRate(Rate(
                input: inp, output: out,
                cacheRead: info["cache_read_input_token_cost"] as? Double
                    ?? defaultRates[family]?.cacheRead ?? inp,
                cacheWrite: info["cache_creation_input_token_cost"] as? Double
                    ?? defaultRates[family]?.cacheWrite ?? inp,
                cacheWrite1h: info["cache_creation_input_token_cost_above_1hr"] as? Double
                    ?? info["cache_creation_input_token_cost_1h"] as? Double,
                inputTiered: info["input_cost_per_token_above_200k_tokens"] as? Double
                    ?? info["input_cost_per_token_above_272k_tokens"] as? Double,
                outputTiered: info["output_cost_per_token_above_200k_tokens"] as? Double
                    ?? info["output_cost_per_token_above_272k_tokens"] as? Double,
                cacheWriteTiered: info["cache_creation_input_token_cost_above_200k_tokens"] as? Double
                    ?? info["cache_creation_input_token_cost_above_272k_tokens"] as? Double,
                cacheReadTiered: info["cache_read_input_token_cost_above_200k_tokens"] as? Double
                    ?? info["cache_read_input_token_cost_above_272k_tokens"] as? Double,
                cacheWrite1hTiered: info["cache_creation_input_token_cost_above_1hr_above_200k_tokens"] as? Double
                    ?? info["cache_creation_input_token_cost_above_1hr_above_272k_tokens"] as? Double,
                longContextThreshold: has272KPricing ? 272_000 : (has200KPricing ? 200_000 : nil)
            ), family: family)

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
        if key == "claude-fable-5" || key.hasPrefix("claude-fable-5-")
            || key.hasSuffix("/claude-fable-5") || key.contains(".claude-fable-5")
            || key == "vertex_ai/claude-fable-5@default" {
            return "claude-fable-5"
        }
        if key == "claude-mythos-5" || key.hasPrefix("claude-mythos-5-")
            || key.hasSuffix("/claude-mythos-5") || key.contains(".claude-mythos-5")
            || key == "vertex_ai/claude-mythos-5@default" {
            return "claude-mythos-5"
        }
        if key == "claude-opus-4-8-fast" || key.hasPrefix("claude-opus-4-8-fast-") {
            return "claude-opus-4-8-fast"
        }
        if key == "claude-opus-4-7-fast" || key.hasPrefix("claude-opus-4-7-fast-") {
            return "claude-opus-4-7-fast"
        }
        if key == "claude-opus-4-8" || key.hasPrefix("claude-opus-4-8-20")
            || key.hasSuffix("/claude-opus-4-8") || key.contains(".claude-opus-4-8")
            || key == "vertex_ai/claude-opus-4-8@default" {
            return "claude-opus-4-8"
        }
        if key == "claude-opus-4-7" || key.hasPrefix("claude-opus-4-7-20")
            || key.hasSuffix("/claude-opus-4-7") || key.contains(".claude-opus-4-7")
            || key == "vertex_ai/claude-opus-4-7@default" {
            return "claude-opus-4-7"
        }
        if key == "claude-opus-4-6" || key.hasPrefix("claude-opus-4-6-")
            || key == "claude-opus-4-5" || key.hasPrefix("claude-opus-4-5-") {
            return "claude-opus-4-6"
        }
        if key == "claude-opus-4-1" || key.hasPrefix("claude-opus-4-1-")
            || key == "claude-opus-4-20250514" {
            return "claude-opus-4-1"
        }
        if key == "claude-sonnet-5" || key.hasPrefix("claude-sonnet-5-")
            || key.hasSuffix("/claude-sonnet-5") || key.contains(".claude-sonnet-5")
            || key == "vertex_ai/claude-sonnet-5@default" {
            return "claude-sonnet-5"
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
        if key == "gpt-5.5-pro" || key.hasPrefix("gpt-5.5-pro-20") {
            return "gpt-5.5-pro"
        }
        if key == "gpt-5.5" || key.hasPrefix("gpt-5.5-20") {
            return "gpt-5.5"
        }
        if key == "gpt-5.6-sol" || key.hasPrefix("gpt-5.6-sol-20") {
            return "gpt-5.6-sol"
        }
        if key == "gpt-5.6-terra" || key.hasPrefix("gpt-5.6-terra-20") {
            return "gpt-5.6-terra"
        }
        if key == "gpt-5.6-luna" || key.hasPrefix("gpt-5.6-luna-20") {
            return "gpt-5.6-luna"
        }
        if key == "gpt-5.6" || key.hasPrefix("gpt-5.6-20") {
            return "gpt-5.6-sol"
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
            let fallback = defaultRates[family]
            result[family] = Rate(
                input: p["input"] ?? 0, output: p["output"] ?? 0,
                cacheRead: p["cacheRead"] ?? 0, cacheWrite: p["cacheWrite"] ?? 0,
                cacheWrite1h: p["cacheWrite1h"] ?? fallback?.cacheWrite1h,
                inputTiered: p["inputTiered"], outputTiered: p["outputTiered"],
                cacheWriteTiered: p["cacheWriteTiered"], cacheReadTiered: p["cacheReadTiered"],
                cacheWrite1hTiered: p["cacheWrite1hTiered"] ?? fallback?.cacheWrite1hTiered,
                longContextThreshold: p["longContextThreshold"].map(Int.init)
                    ?? fallback?.longContextThreshold)
        }
        return result.isEmpty ? nil : (result, -mod.timeIntervalSinceNow)
    }

    private static func writeCache(_ rates: [String: Rate]) {
        var json: [String: [String: Double]] = [:]
        for (family, r) in rates {
            var d: [String: Double] = [
                "input": r.input, "output": r.output,
                "cacheRead": r.cacheRead, "cacheWrite": r.cacheWrite,
                "cacheWrite1h": r.cacheWrite1h
            ]
            if let v = r.inputTiered { d["inputTiered"] = v }
            if let v = r.outputTiered { d["outputTiered"] = v }
            if let v = r.cacheWriteTiered { d["cacheWriteTiered"] = v }
            if let v = r.cacheReadTiered { d["cacheReadTiered"] = v }
            if let v = r.cacheWrite1hTiered { d["cacheWrite1hTiered"] = v }
            if let v = r.longContextThreshold { d["longContextThreshold"] = Double(v) }
            json[family] = d
        }
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            try? data.write(to: cacheFile, options: .atomic)
        }
    }
}
