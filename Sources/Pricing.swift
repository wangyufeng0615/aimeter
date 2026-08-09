import Foundation

/// Resolve model prices from validated defaults, a bounded disk cache, and a
/// periodically refreshed LiteLLM snapshot. Provider-specific invariants are
/// applied after the remote merge so stale upstream data cannot override known
/// rules or reprice historical usage.
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

    // Hardcoded fallback — verified against provider pricing as of 2026-08.
    private static let baseDefaultRates: [String: Rate] = [
        // Claude models
        "claude-fable-5": Rate(input: 10e-6, output: 50e-6, cacheRead: 1e-6,
                               cacheWrite: 12.5e-6, cacheWrite1h: 20e-6,
                               inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-mythos-5": Rate(input: 10e-6, output: 50e-6, cacheRead: 1e-6,
                                cacheWrite: 12.5e-6, cacheWrite1h: 20e-6,
                                inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-opus-5": Rate(input: 5e-6, output: 25e-6, cacheRead: 0.5e-6,
                               cacheWrite: 6.25e-6, cacheWrite1h: 10e-6,
                               inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-opus-5-fast": Rate(input: 10e-6, output: 50e-6, cacheRead: 1e-6,
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
        "claude-opus-4-6": Rate(input: 5e-6, output: 25e-6, cacheRead: 0.5e-6,
                                cacheWrite: 6.25e-6, cacheWrite1h: 10e-6,
                                inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        "claude-opus-4-1": Rate(input: 15e-6, output: 75e-6, cacheRead: 1.5e-6,
                                cacheWrite: 18.75e-6, cacheWrite1h: 30e-6,
                                inputTiered: nil, outputTiered: nil, cacheWriteTiered: nil, cacheReadTiered: nil),
        // Introductory pricing through 2026-08-31. `rate(for:at:)` applies the
        // provider's effective-date schedule to each usage entry.
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

    private static let sonnet5StandardRate = Rate(
        input: 3e-6, output: 15e-6, cacheRead: 0.3e-6,
        cacheWrite: 3.75e-6, cacheWrite1h: 6e-6,
        inputTiered: nil, outputTiered: nil,
        cacheWriteTiered: nil, cacheReadTiered: nil
    )

    private static let sonnet5StandardPricingStart: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 1
        ))!
    }()

    private static let lock = NSLock()
    private static var _rates: [String: Rate] = baseDefaultRates
    private static var rates: [String: Rate] {
        get { lock.lock(); defer { lock.unlock() }; return _rates }
        set { lock.lock(); defer { lock.unlock() }; _rates = newValue }
    }

    private static let refreshLock = NSLock()
    private static var didLoadCache = false
    private static var lastFetchAttempt: Date?
    private static let cacheTTL: TimeInterval = 24 * 60 * 60
    private static let failedFetchRetryInterval: TimeInterval = 15 * 60
    private static let cacheFile: URL = {
        // Prefer ~/Library/Caches; fall back to ~/.claude/
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let dir = caches.appendingPathComponent("com.aimeter.app")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pricing.json")
    }()

    /// Call from a background thread. A long-running menu app rechecks cache
    /// freshness on every Stage 2 refresh and retries transient failures after
    /// a bounded delay.
    static func loadFromLiteLLM() {
        refreshLock.lock()
        defer { refreshLock.unlock() }

        let now = Date()
        let cached = readCache(now: now)
        if !didLoadCache {
            if let cached { rates = mergeRates(cached.rates) }
            didLoadCache = true
        }

        let secondsSinceLastAttempt = lastFetchAttempt.map { now.timeIntervalSince($0) }
        guard shouldRefreshPricing(
            cacheAge: cached?.age,
            secondsSinceLastAttempt: secondsSinceLastAttempt
        ) else {
            return
        }
        lastFetchAttempt = now

        if let fetched = fetchLiteLLM() {
            let merged = mergeRates(fetched)
            rates = merged
            writeCache(merged)
        } else if let cached {
            rates = mergeRates(cached.rates)
        }
    }

    static func shouldRefreshPricing(
        cacheAge: TimeInterval?,
        secondsSinceLastAttempt: TimeInterval?
    ) -> Bool {
        if let cacheAge, cacheAge >= 0, cacheAge < cacheTTL { return false }
        guard let secondsSinceLastAttempt else { return true }
        return secondsSinceLastAttempt >= failedFetchRetryInterval
    }

    /// Merge fetched rates with defaults (so OpenAI models always have pricing)
    private static func mergeRates(_ fetched: [String: Rate]) -> [String: Rate] {
        var result = baseDefaultRates
        for (k, v) in fetched { result[k] = normalizedRate(v, family: k) }
        return result
    }

    /// Keep provider-documented invariants authoritative when LiteLLM or an
    /// older on-disk cache still contains stale values.
    private static func normalizedRate(_ rate: Rate, family: String) -> Rate {
        let fallback = baseDefaultRates[family]
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
                     at usageDate: Date = Date(),
                     input: Int, output: Int, cacheWrite: Int,
                     cacheWrite1h: Int = 0, cacheRead: Int) -> Double {
        let family = modelFamily(model)
        guard let billingFamily = billingFamily(family, speed: speed),
              let r = rate(for: billingFamily, baseFamily: family, at: usageDate)
        else { return 0 }
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
        guard let billingFamily = billingFamily(family, speed: speed) else { return false }
        return rate(for: billingFamily, baseFamily: family, at: Date()) != nil
    }

    private static func rate(for billingFamily: String, baseFamily: String, at usageDate: Date) -> Rate? {
        if baseFamily == "claude-sonnet-5" {
            return usageDate >= sonnet5StandardPricingStart
                ? sonnet5StandardRate
                : baseDefaultRates["claude-sonnet-5"]
        }
        return rates[billingFamily]
    }

    /// Map model name to pricing key.
    static func modelFamily(_ model: String) -> String {
        modelFamily(model, availableFamilies: Set(rates.keys))
    }

    /// Pure resolver used by tests to verify remote-only future model support.
    static func modelFamily(_ model: String, availableFamilies: Set<String>) -> String {
        let m = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Claude: accept direct model IDs and explicit legacy aliases only.
        // Arbitrary provider/relay prefixes stay unknown because their billing
        // contract cannot be inferred from a substring.
        if let shorthandFamily = directClaudeFamily("claude-\(m)"),
           availableFamilies.contains(shorthandFamily) {
            return shorthandFamily
        }
        if m == "claude-opus-4-20250514" { return "claude-opus-4-1" }
        if m == "claude-opus-4-5" || m.hasPrefix("claude-opus-4-5-20") {
            return "claude-opus-4-6"
        }
        if m == "claude-sonnet-4-20250514" { return "claude-sonnet-4-6" }
        if m == "claude-sonnet-4-5" || m.hasPrefix("claude-sonnet-4-5-20") {
            return "claude-sonnet-4-6"
        }
        // Future direct Claude versions can be priced without an app release
        // once LiteLLM has supplied a validated rate for their canonical key.
        if let family = directClaudeFamily(m), availableFamilies.contains(family) { return family }
        // OpenAI: allow canonical IDs (and the official `openai/` prefix), but
        // keep custom relay namespaces fail-closed.
        let openAIModel = m.hasPrefix("openai/") ? String(m.dropFirst("openai/".count)) : m
        if openAIModel == "gpt-5.6-sol-pro" { return "unknown" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.6-terra") { return "gpt-5.6-terra" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.6-luna") { return "gpt-5.6-luna" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.6-sol") { return "gpt-5.6-sol" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.6") {
            return "gpt-5.6-sol"
        }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.4-mini") { return "gpt-5.4-mini" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.4-nano") { return "gpt-5.4-nano" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.4-pro") { return "gpt-5.4-pro" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.5-pro") { return "gpt-5.5-pro" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.5") { return "gpt-5.5" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.1-codex-mini") { return "gpt-5.1-codex-mini" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.1-codex-max") { return "gpt-5.1-codex" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.1-codex") { return "gpt-5.1-codex" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.2-codex") { return "gpt-5.2-codex" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.3-codex") { return "gpt-5.3-codex" }
        if matchesDirectModel(openAIModel, canonical: "gpt-5.4") { return "gpt-5.4" }
        return "unknown"
    }

    private static func billingFamily(_ family: String, speed: String?) -> String? {
        guard speed?.lowercased() == "fast" else { return family }
        switch family {
        case "claude-opus-5", "claude-opus-4-8":
            return "\(family)-fast"
        case "claude-opus-4-7":
            return nil
        default:
            return family
        }
    }

    private static func geographyMultiplier(family: String, inferenceGeo: String?) -> Double {
        guard inferenceGeo?.lowercased() == "us" else { return 1 }
        return supportsUSInference(family: family) ? 1.1 : 1
    }

    static func supportsUSInference(family: String) -> Bool {
        guard let version = claudeVersionComponents(family) else { return false }
        return version.major > 4 || (version.major == 4 && version.minor >= 6)
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

            let fallbackRate = baseDefaultRates[family]
            let cacheRead = info["cache_read_input_token_cost"] as? Double
            let cacheWrite = info["cache_creation_input_token_cost"] as? Double
            let cacheWrite1h = info["cache_creation_input_token_cost_above_1hr"] as? Double
                ?? info["cache_creation_input_token_cost_1h"] as? Double
            // A newly discovered Claude family is only safe to expose when
            // LiteLLM supplies the full standard cache contract. Falling back
            // to input price would manufacture a plausible but wrong total.
            if fallbackRate == nil, directClaudeFamily(family) != nil,
               (cacheRead == nil || cacheWrite == nil || cacheWrite1h == nil) {
                continue
            }

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
                cacheRead: cacheRead ?? fallbackRate?.cacheRead ?? inp,
                cacheWrite: cacheWrite ?? fallbackRate?.cacheWrite ?? inp,
                cacheWrite1h: cacheWrite1h ?? fallbackRate?.cacheWrite1h,
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
        if key == "claude-opus-5-fast" || key.hasPrefix("claude-opus-5-fast-") {
            return "claude-opus-5-fast"
        }
        if key == "claude-opus-4-8-fast" || key.hasPrefix("claude-opus-4-8-fast-") {
            return "claude-opus-4-8-fast"
        }
        if key == "claude-opus-5" || key.hasPrefix("claude-opus-5-20")
            || key.hasSuffix("/claude-opus-5") || key.contains(".claude-opus-5")
            || key == "vertex_ai/claude-opus-5@default" {
            return "claude-opus-5"
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
        // Keep the fail-closed boundary for arbitrary/custom models, while
        // allowing a new version of an established direct Claude product line
        // to flow through LiteLLM without waiting for another app release.
        if let family = directClaudeFamily(key) { return family }
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

    private static func directClaudeFamily(_ raw: String) -> String? {
        var candidate = raw.lowercased()
        guard candidate.hasPrefix("claude-") else { return nil }
        if let datedSuffix = candidate.range(
            of: #"-\d{8}(?:[-@].*)?$"#,
            options: .regularExpression
        ) {
            candidate = String(candidate[..<datedSuffix.lowerBound])
        }
        guard candidate.range(
            of: #"^claude-(?:fable|mythos|opus|sonnet|haiku)-\d+(?:-\d+)*$"#,
            options: .regularExpression
        ) != nil else { return nil }
        return candidate
    }

    private static func matchesDirectModel(_ model: String, canonical: String) -> Bool {
        model == canonical
            || model.range(
                of: "^\(NSRegularExpression.escapedPattern(for: canonical))-20\\d{6}$",
                options: .regularExpression
            ) != nil
    }

    private static func claudeVersionComponents(_ family: String) -> (major: Int, minor: Int)? {
        guard let match = family.range(
            of: #"^claude-(?:fable|mythos|opus|sonnet|haiku)-(\d+)(?:-(\d+))?$"#,
            options: .regularExpression
        ) else { return nil }
        let suffix = family[match].split(separator: "-")
        guard let major = suffix.dropFirst(2).first.flatMap({ Int($0) }) else { return nil }
        let minor = suffix.dropFirst(3).first.flatMap { Int($0) } ?? 0
        return (major, minor)
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

    private static func readCache(now: Date = Date()) -> (rates: [String: Rate], age: TimeInterval)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
              let mod = attrs[.modificationDate] as? Date,
              let data = try? Data(contentsOf: cacheFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]]
        else { return nil }

        var result: [String: Rate] = [:]
        for (family, p) in json {
            let fallback = baseDefaultRates[family]
            guard let input = p["input"], let output = p["output"],
                  let cacheRead = p["cacheRead"], let cacheWrite = p["cacheWrite"]
            else { continue }
            let cacheWrite1h = p["cacheWrite1h"] ?? fallback?.cacheWrite1h
            if fallback == nil, directClaudeFamily(family) != nil, cacheWrite1h == nil {
                continue
            }
            result[family] = Rate(
                input: input, output: output,
                cacheRead: cacheRead, cacheWrite: cacheWrite,
                cacheWrite1h: cacheWrite1h,
                inputTiered: p["inputTiered"], outputTiered: p["outputTiered"],
                cacheWriteTiered: p["cacheWriteTiered"], cacheReadTiered: p["cacheReadTiered"],
                cacheWrite1hTiered: p["cacheWrite1hTiered"] ?? fallback?.cacheWrite1hTiered,
                longContextThreshold: p["longContextThreshold"].map(Int.init)
                    ?? fallback?.longContextThreshold)
        }
        return result.isEmpty ? nil : (result, max(0, now.timeIntervalSince(mod)))
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
