import SwiftUI

final class UsageStore: ObservableObject {
    typealias Clock = () -> Date
    typealias RateReader = () -> RateLimit?
    typealias ClaudeRateSnapshotReader = () -> (rate: RateLimit?, status: ClaudeRateStatus)
    typealias CodexEntriesReader = (Date) -> [CodexReader.UsageEntry]?
    typealias PricingLoader = () -> Void

    struct TokenLoadStats: Equatable {
        var scannedFiles = 0
        var fullParsedFiles = 0
        var incrementalFiles = 0
        var reusedFiles = 0
        var parsedBytes = 0

        static let zero = TokenLoadStats()
    }

    private struct CollectionSignature: Equatable {
        let count: Int
        let hash: Int

        static let empty = CollectionSignature(count: 0, hash: 0)
    }

    private struct CachedFile {
        let mod: Date
        let size: Int
        let fileID: UInt64?
        let lineCount: Int
        let trailingData: Data
        let entries: [UsageEntry]
    }

    private struct ParsedChunk {
        let entries: [UsageEntry]
        let lineCount: Int
        let trailingData: Data
        let bytesRead: Int
    }

    private struct ClaudeLoadResult {
        let entries: [UsageEntry]
        let signature: CollectionSignature
        let cache: [String: CachedFile]
        let stats: TokenLoadStats
    }

    private struct TokenLoadResult {
        let ccEntries: [UsageEntry]
        let ccSignature: CollectionSignature
        let cxEntries: [CodexReader.UsageEntry]?
        let cxSignature: CollectionSignature?
        let usageSummary: UsageSummary
        let cache: [String: CachedFile]
        let stats: TokenLoadStats
    }

    // Server-provided rate limits
    @Published var claudeRate: RateLimit?
    @Published var codexRate: RateLimit?
    @Published var claudeRateStatus: ClaudeRateStatus = .waitingForSessionData

    // Local token data for detail views
    @Published var ccEntries: [UsageEntry] = []
    @Published var cxEntries: [CodexReader.UsageEntry] = []
    @Published private(set) var usageSummary: UsageSummary = .empty
    @Published var isLoading = true

    private var timer: Timer?
    private var rateTimer: Timer?
    private let claudeProjectsDirProvider: () -> URL
    private let now: Clock
    private let claudeRateSnapshotReader: ClaudeRateSnapshotReader
    private let codexRateReader: RateReader
    private let codexEntriesReader: CodexEntriesReader
    private let pricingLoader: PricingLoader
    private var defaultsObserver: NSObjectProtocol?

    // File cache lives on the main thread; captured into Stage 2 by value,
    // written back on main when Stage 2 completes. `stage2InFlight` prevents
    // overlapping loads that would race on the cache. `stage1InFlight`
    // serializes rate-limit reads so out-of-order callbacks can't overwrite
    // fresher data with stale snapshots.
    private var fileCache: [String: CachedFile] = [:]
    private var stage1InFlight = false
    private var stage2InFlight = false
    private var ccSignature = CollectionSignature.empty
    private var cxSignature = CollectionSignature.empty
    private var observedClaudeRoot = AppPaths.claudeRoot
    private var observedCodexRoot = AppPaths.codexRoot
    private var loadGeneration = 0

    private(set) var lastTokenLoadStats: TokenLoadStats = .zero

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init(
        projectsDir: URL? = nil,
        autoload: Bool = true,
        autoRefresh: Bool = true,
        refreshInterval: TimeInterval = 15,
        rateRefreshInterval: TimeInterval = 5,
        now: @escaping Clock = Date.init,
        claudeRateReader: RateReader? = nil,
        claudeRateStatusReader: (() -> ClaudeRateStatus)? = nil,
        claudeRateSnapshotReader: @escaping ClaudeRateSnapshotReader = { ClaudeRateReader.inspect() },
        codexRateReader: @escaping RateReader = CodexRateReader.read,
        codexEntriesReader: @escaping CodexEntriesReader = CodexReader.readEntries,
        pricingLoader: @escaping PricingLoader = Pricing.loadFromLiteLLM
    ) {
        self.claudeProjectsDirProvider = { projectsDir ?? AppPaths.claudeProjectsDir }
        self.now = now
        if claudeRateReader != nil || claudeRateStatusReader != nil {
            let snapshotReader = claudeRateSnapshotReader
            let rateReader = claudeRateReader ?? { snapshotReader().rate }
            let statusReader = claudeRateStatusReader ?? { snapshotReader().status }
            self.claudeRateSnapshotReader = { (rateReader(), statusReader()) }
        } else {
            self.claudeRateSnapshotReader = claudeRateSnapshotReader
        }
        self.codexRateReader = codexRateReader
        self.codexEntriesReader = codexEntriesReader
        self.pricingLoader = pricingLoader
        self.defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            self?.reloadIfPathsChanged()
        }
        self.usageSummary = buildUsageSummary(ccEntries: [], cxEntries: [], now: now())

        if autoload {
            loadAsync()
        }
        if autoRefresh {
            timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
                self?.loadAsync()
            }
            timer?.tolerance = refreshInterval * 0.1
            // Rate limits are cheap to read (a few KB) and the data the user
            // cares about most right after installing the hook. Poll them
            // faster than the full JSONL scan so new data shows up quickly.
            rateTimer = Timer.scheduledTimer(withTimeInterval: rateRefreshInterval, repeats: true) { [weak self] _ in
                self?.loadRateLimitsAsync()
            }
            rateTimer?.tolerance = rateRefreshInterval * 0.1
        }
    }

    deinit {
        timer?.invalidate()
        rateTimer?.invalidate()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    // MARK: - Installed detection

    static var claudeInstalled: Bool {
        FileManager.default.fileExists(atPath: AppPaths.claudeRoot.path)
    }

    static var codexInstalled: Bool {
        FileManager.default.fileExists(atPath: AppPaths.codexRoot.path)
    }

    // MARK: - Menu bar

    var claudePct: Double { claudeRate?.fiveHourPct ?? 0 }
    var codexPct: Double { codexRate?.fiveHourPct ?? 0 }
    var showCodex: Bool { Self.codexInstalled && (codexRate != nil || !cxEntries.isEmpty) }

    /// Single-provider fallback text (used when only one is installed)
    var menuBarText: String {
        if Self.claudeInstalled { return "Claude \(Int(claudePct))%" }
        if Self.codexInstalled  { return "Codex \(Int(codexPct))%" }
        return "—"
    }

    // MARK: - Claude detail data

    private static func isSyntheticClaudeModel(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines) == "<synthetic>"
    }

    var ccToday: DailyUsage {
        let today = Calendar.current.startOfDay(for: now())
        return DailyUsage(id: "today", date: today, entries: ccEntries.filter { $0.timestamp >= today })
    }

    var ccWeekly: [DailyUsage] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now())
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        return (0..<7).reversed().map { ago in
            let d = cal.date(byAdding: .day, value: -ago, to: today)!
            let n = cal.date(byAdding: .day, value: 1, to: d)!
            return DailyUsage(id: df.string(from: d), date: d,
                              entries: ccEntries.filter { $0.timestamp >= d && $0.timestamp < n })
        }
    }

    var ccModels: [ModelUsage] {
        let today = Calendar.current.startOfDay(for: now())
        let todayEntries = ccEntries.filter {
            $0.timestamp >= today && !Self.isSyntheticClaudeModel($0.model)
        }
        // Group by the FULL model name so distinct snapshots stay separate
        let grouped = Dictionary(grouping: todayEntries) { $0.model }
        return grouped.map { ModelUsage(id: $0.key, model: $0.key, entries: $0.value) }
            .sorted { $0.totalTokens > $1.totalTokens }
    }

    // MARK: - Codex detail data

    var cxModels: [(model: String, tokens: Int, cost: Double)] {
        let today = Calendar.current.startOfDay(for: now())
        let todayEntries = cxEntries.filter { $0.timestamp >= today }
        let grouped = Dictionary(grouping: todayEntries) { CodexReader.shortenModel($0.model) }
        return grouped.map {
            (
                $0.key,
                $0.value.reduce(0) { $0 + $1.totalTokens },
                $0.value.reduce(0.0) { $0 + $1.cost }
            )
        }
        .sorted { $0.1 > $1.1 }
    }

    // MARK: - Combined weekly (Claude + Codex)

    struct WeeklyDay: Identifiable, Equatable {
        let id: String
        let date: Date
        let tokens: Int
        let cost: Double
    }

    enum UsageSource: String, Equatable, Hashable {
        case claude
        case codex
    }

    struct ModelBreakdown: Identifiable, Equatable, Hashable {
        let source: UsageSource
        let displayName: String
        let fullName: String
        let tokens: Int
        let cost: Double

        var id: String { "\(source.rawValue):\(fullName)" }
    }

    struct TodaySummary: Equatable {
        let tokens: Int
        let cost: Double
        let messageCount: Int
        let models: [ModelBreakdown]

        static let empty = TodaySummary(tokens: 0, cost: 0, messageCount: 0, models: [])
    }

    struct UsageSummary: Equatable {
        let today: TodaySummary
        let weekly: [WeeklyDay]

        static let empty = UsageSummary(today: .empty, weekly: [])
    }

    var weekly: [WeeklyDay] {
        usageSummary.weekly
    }

    // MARK: - Loading

    func refresh() { loadAsync() }

    func refreshSynchronouslyForTesting() {
        let rates = loadRateLimits()
        applyRateLimits(claude: rates.claude, claudeStatus: rates.claudeStatus, codex: rates.codex)
        let result = loadTokenData(snapshot: fileCache, previousCodexEntries: cxEntries)
        applyTokenData(result)
    }

    private func loadAsync() {
        loadRateLimitsAsync()

        // Stage 2: Token data — slow, with race-guard
        guard !stage2InFlight else { return }
        stage2InFlight = true
        let snapshot = self.fileCache  // capture on main thread
        let previousCodexEntries = self.cxEntries
        let generation = loadGeneration

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.loadTokenData(snapshot: snapshot, previousCodexEntries: previousCodexEntries)
            DispatchQueue.main.async {
                guard generation == self.loadGeneration else {
                    self.stage2InFlight = false
                    self.loadAsync()
                    return
                }
                self.applyTokenData(result)
                self.stage2InFlight = false
            }
        }
    }

    /// Stage 1 only — fast path, runs on the dedicated rate-limit timer.
    private func loadRateLimitsAsync() {
        guard !stage1InFlight else { return }
        stage1InFlight = true
        let generation = loadGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let rates = self.loadRateLimits()
            DispatchQueue.main.async {
                guard generation == self.loadGeneration else {
                    self.stage1InFlight = false
                    self.loadRateLimitsAsync()
                    return
                }
                self.applyRateLimits(claude: rates.claude, claudeStatus: rates.claudeStatus, codex: rates.codex)
                self.stage1InFlight = false
            }
        }
    }

    private func loadRateLimits() -> (claude: RateLimit?, claudeStatus: ClaudeRateStatus, codex: RateLimit?) {
        let claude = claudeRateSnapshotReader()
        return (claude.rate, claude.status, codexRateReader())
    }

    private func reloadIfPathsChanged() {
        let claudeRoot = AppPaths.claudeRoot
        let codexRoot = AppPaths.codexRoot
        guard claudeRoot != observedClaudeRoot || codexRoot != observedCodexRoot else { return }

        loadGeneration += 1
        observedClaudeRoot = claudeRoot
        observedCodexRoot = codexRoot
        fileCache = [:]
        ccSignature = .empty
        cxSignature = .empty
        claudeRate = nil
        codexRate = nil
        claudeRateStatus = .waitingForSessionData
        ccEntries = []
        cxEntries = []
        usageSummary = buildUsageSummary(ccEntries: [], cxEntries: [], now: now())
        isLoading = true
        loadAsync()
    }

    private func applyRateLimits(claude: RateLimit?, claudeStatus: ClaudeRateStatus, codex: RateLimit?) {
        if let claude {
            if claudeRate != claude {
                claudeRate = claude
            }
        } else if let existing = claudeRate,
                  existing.updatedAt.timeIntervalSinceNow > -6 * 3600,
                  claudeStatus != .available {
            // Keep the last good Claude limit snapshot across transient empty statusline payloads.
        } else if claudeRate != nil {
            claudeRate = nil
        }
        if self.claudeRateStatus != claudeStatus {
            self.claudeRateStatus = claudeStatus
        }
        if codexRate != codex {
            codexRate = codex
        }
    }

    private func loadTokenData(
        snapshot: [String: CachedFile],
        previousCodexEntries: [CodexReader.UsageEntry]
    ) -> TokenLoadResult {
        pricingLoader()

        var cache = snapshot
        let claude = loadClaudeEntries(cache: &cache)
        let cutoff = now().addingTimeInterval(-7 * 86400)
        let codexEntries = codexEntriesReader(cutoff)
        let visibleCodexEntries = codexEntries ?? previousCodexEntries
        let summary = buildUsageSummary(
            ccEntries: claude.entries,
            cxEntries: visibleCodexEntries,
            now: now()
        )

        return TokenLoadResult(
            ccEntries: claude.entries,
            ccSignature: claude.signature,
            cxEntries: codexEntries,
            cxSignature: codexEntries.map(collectionSignature),
            usageSummary: summary,
            cache: cache,
            stats: claude.stats
        )
    }

    private func applyTokenData(_ result: TokenLoadResult) {
        fileCache = result.cache
        lastTokenLoadStats = result.stats

        if result.ccSignature != ccSignature {
            ccEntries = result.ccEntries
            ccSignature = result.ccSignature
        }
        if let cxEntries = result.cxEntries,
           let cxSignature = result.cxSignature,
           cxSignature != self.cxSignature {
            self.cxEntries = cxEntries
            self.cxSignature = cxSignature
        }
        if result.usageSummary != usageSummary {
            usageSummary = result.usageSummary
        }
        if isLoading {
            isLoading = false
        }
    }

    private func buildUsageSummary(
        ccEntries: [UsageEntry],
        cxEntries: [CodexReader.UsageEntry],
        now: Date
    ) -> UsageSummary {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let weekStart = cal.date(byAdding: .day, value: -6, to: today) ?? today
        let weekEnd = cal.date(byAdding: .day, value: 1, to: today) ?? now
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        var weeklyTokens = Array(repeating: 0, count: 7)
        var weeklyCosts = Array(repeating: 0.0, count: 7)
        var claudeModels: [String: (tokens: Int, cost: Double)] = [:]
        var codexModels: [String: (tokens: Int, cost: Double)] = [:]
        var todayMessageCount = 0

        func weekIndex(for date: Date) -> Int? {
            guard date >= weekStart && date < weekEnd else { return nil }
            let day = cal.startOfDay(for: date)
            let offset = cal.dateComponents([.day], from: weekStart, to: day).day ?? -1
            return (0..<7).contains(offset) ? offset : nil
        }

        for entry in ccEntries {
            if let index = weekIndex(for: entry.timestamp) {
                weeklyTokens[index] += entry.totalTokens
                weeklyCosts[index] += entry.cost
            }

            guard entry.timestamp >= today else { continue }
            todayMessageCount += 1
            guard !Self.isSyntheticClaudeModel(entry.model) else { continue }

            let current = claudeModels[entry.model] ?? (tokens: 0, cost: 0)
            claudeModels[entry.model] = (
                tokens: current.tokens + entry.totalTokens,
                cost: current.cost + entry.cost
            )
        }

        for entry in cxEntries {
            if let index = weekIndex(for: entry.timestamp) {
                weeklyTokens[index] += entry.totalTokens
                weeklyCosts[index] += entry.cost
            }

            guard entry.timestamp >= today else { continue }
            let model = CodexReader.shortenModel(entry.model)
            let current = codexModels[model] ?? (tokens: 0, cost: 0)
            codexModels[model] = (
                tokens: current.tokens + entry.totalTokens,
                cost: current.cost + entry.cost
            )
        }

        var models = claudeModels.map {
            ModelBreakdown(
                source: .claude,
                displayName: Pricing.shortenModelName($0.key),
                fullName: $0.key,
                tokens: $0.value.tokens,
                cost: $0.value.cost
            )
        }
        models += codexModels.map {
            ModelBreakdown(
                source: .codex,
                displayName: $0.key,
                fullName: $0.key,
                tokens: $0.value.tokens,
                cost: $0.value.cost
            )
        }
        models.sort { $0.tokens > $1.tokens }

        let weekly = (0..<7).map { index in
            let date = cal.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
            return WeeklyDay(
                id: df.string(from: date),
                date: date,
                tokens: weeklyTokens[index],
                cost: weeklyCosts[index]
            )
        }
        let todaySummary = TodaySummary(
            tokens: models.reduce(0) { $0 + $1.tokens },
            cost: models.reduce(0.0) { $0 + $1.cost },
            messageCount: todayMessageCount,
            models: models
        )

        return UsageSummary(today: todaySummary, weekly: weekly)
    }

    private func collectionSignature<T: Hashable>(_ values: [T]) -> CollectionSignature {
        var hasher = Hasher()
        hasher.combine(values.count)
        for value in values {
            hasher.combine(value)
        }
        return CollectionSignature(count: values.count, hash: hasher.finalize())
    }

    // MARK: - Claude JSONL parsing

    private func loadClaudeEntries(cache: inout [String: CachedFile]) -> ClaudeLoadResult {
        let cutoff = now().addingTimeInterval(-7 * 86400)
        var all: [UsageEntry] = []
        var seen = Set<String>()
        var newCache: [String: CachedFile] = [:]
        var stats = TokenLoadStats.zero
        let projectsDir = claudeProjectsDirProvider()

        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            cache = [:]
            return ClaudeLoadResult(entries: [], signature: .empty, cache: [:], stats: stats)
        }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mod = vals.contentModificationDate,
                  let size = vals.fileSize,
                  mod >= cutoff else { continue }

            stats.scannedFiles += 1
            let path = url.path
            let fileID = fileID(for: url)
            let fileEntries: [UsageEntry]

            if let cached = cache[path],
               cached.mod == mod,
               cached.size == size,
               cached.fileID == fileID {
                let cachedEntries = entriesInWindow(cached.entries, cutoff: cutoff)
                let updated = cachedEntries.count == cached.entries.count
                    ? cached
                    : CachedFile(
                        mod: cached.mod,
                        size: cached.size,
                        fileID: cached.fileID,
                        lineCount: cached.lineCount,
                        trailingData: cached.trailingData,
                        entries: cachedEntries
                    )
                stats.reusedFiles += 1
                newCache[path] = updated
                fileEntries = cachedEntries
            } else if let cached = cache[path],
                      cached.fileID != nil,
                      cached.fileID == fileID,
                      size >= cached.size {
                let parsed = parseAppendedFile(url, fromOffset: cached.size, cached: cached)
                let mergedEntries = entriesInWindow(cached.entries + parsed.entries, cutoff: cutoff)
                let updated = CachedFile(
                    mod: mod,
                    size: size,
                    fileID: fileID,
                    lineCount: parsed.lineCount,
                    trailingData: parsed.trailingData,
                    entries: mergedEntries
                )
                stats.incrementalFiles += 1
                stats.parsedBytes += parsed.bytesRead
                newCache[path] = updated
                fileEntries = mergedEntries
            } else {
                let parsed = parseWholeFile(url)
                let rebuilt = CachedFile(
                    mod: mod,
                    size: size,
                    fileID: fileID,
                    lineCount: parsed.lineCount,
                    trailingData: parsed.trailingData,
                    entries: parsed.entries
                )
                stats.fullParsedFiles += 1
                stats.parsedBytes += parsed.bytesRead
                let entries = entriesInWindow(parsed.entries, cutoff: cutoff)
                newCache[path] = CachedFile(
                    mod: rebuilt.mod,
                    size: rebuilt.size,
                    fileID: rebuilt.fileID,
                    lineCount: rebuilt.lineCount,
                    trailingData: rebuilt.trailingData,
                    entries: entries
                )
                fileEntries = entries
            }

            for entry in fileEntries where entry.timestamp >= cutoff && seen.insert(entry.id).inserted {
                all.append(entry)
            }
        }

        cache = newCache
        let sorted = all.sorted { $0.timestamp < $1.timestamp }
        return ClaudeLoadResult(entries: sorted,
                                signature: collectionSignature(sorted),
                                cache: newCache,
                                stats: stats)
    }

    private func entriesInWindow(_ entries: [UsageEntry], cutoff: Date) -> [UsageEntry] {
        entries.filter { $0.timestamp >= cutoff }
    }

    private static let maxFileBytes: Int = 64 * 1024 * 1024  // 64MB hard cap per file
    private static let maxLinesPerFile = 200_000

    private func parseWholeFile(_ url: URL) -> ParsedChunk {
        readFile(url, fromOffset: 0, carryover: Data(), lineCount: 0)
    }

    private func parseAppendedFile(_ url: URL, fromOffset offset: Int, cached: CachedFile) -> ParsedChunk {
        readFile(url, fromOffset: offset, carryover: cached.trailingData, lineCount: cached.lineCount)
    }

    private func readFile(_ url: URL, fromOffset offset: Int, carryover: Data, lineCount initialLineCount: Int) -> ParsedChunk {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           size > Self.maxFileBytes {
            return ParsedChunk(entries: [], lineCount: 0, trailingData: Data(), bytesRead: 0)
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ParsedChunk(entries: [], lineCount: initialLineCount, trailingData: carryover, bytesRead: 0)
        }
        defer { try? handle.close() }

        handle.seek(toFileOffset: UInt64(offset))

        var buffer = carryover
        var entries: [UsageEntry] = []
        var lines = initialLineCount
        var bytesRead = 0

        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            bytesRead += chunk.count
            buffer.append(chunk)
            drainCompleteLines(from: &buffer, into: &entries, lineCount: &lines)
            if lines >= Self.maxLinesPerFile {
                buffer.removeAll(keepingCapacity: false)
                break
            }
        }

        return ParsedChunk(entries: entries,
                           lineCount: lines,
                           trailingData: buffer,
                           bytesRead: bytesRead)
    }

    private func drainCompleteLines(from buffer: inout Data, into entries: inout [UsageEntry], lineCount: inout Int) {
        var nextStart = buffer.startIndex

        while nextStart < buffer.endIndex,
              let newline = buffer[nextStart...].firstIndex(of: 0x0A),
              lineCount < Self.maxLinesPerFile {
            let lineData = buffer[nextStart..<newline]
            lineCount += 1
            nextStart = buffer.index(after: newline)

            let text = String(decoding: lineData, as: UTF8.self)
            guard text.contains("\"input_tokens\"") else { continue }
            if let entry = parseLine(text) {
                entries.append(entry)
            }
        }

        if nextStart > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<nextStart)
        }
    }

    private func fileID(for url: URL) -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let raw = attrs[.systemFileNumber] as? NSNumber else {
            return nil
        }
        return raw.uint64Value
    }

    private func parseLine(_ line: String) -> UsageEntry? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String, type == "assistant",
              let msg = json["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let ts = json["timestamp"] as? String,
              let date = parseDate(ts)
        else { return nil }

        let reqId = json["requestId"] as? String ?? ""
        let msgId = msg["id"] as? String ?? ""
        guard !reqId.isEmpty || !msgId.isEmpty else { return nil }

        // ccusage "auto" mode: prefer costUSD from JSONL if available
        let costUSD = json["costUSD"] as? Double

        return UsageEntry(
            id: "\(msgId):\(reqId)", timestamp: date,
            model: msg["model"] as? String ?? "unknown",
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            costUSD: costUSD)
    }

    private func parseDate(_ s: String) -> Date? {
        Self.isoFull.date(from: s) ?? Self.isoBasic.date(from: s)
    }
}
