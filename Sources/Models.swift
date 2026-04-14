import Foundation

struct UsageEntry: Identifiable, Equatable, Hashable {
    let id: String
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let costUSD: Double?  // from JSONL if available (ccusage "auto" mode)

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var cost: Double {
        if let c = costUSD { return c }
        return Pricing.cost(model: model, input: inputTokens, output: outputTokens,
                            cacheWrite: cacheCreationTokens, cacheRead: cacheReadTokens)
    }
}

struct DailyUsage: Identifiable {
    let id: String
    let date: Date
    let entries: [UsageEntry]

    var totalTokens: Int { entries.reduce(0) { $0 + $1.totalTokens } }
    var totalCost: Double { entries.reduce(0) { $0 + $1.cost } }
    var messageCount: Int { entries.count }
}

struct ModelUsage: Identifiable {
    let id: String
    let model: String
    let entries: [UsageEntry]

    var totalTokens: Int { entries.reduce(0) { $0 + $1.totalTokens } }
    var totalCost: Double { entries.reduce(0) { $0 + $1.cost } }
}
