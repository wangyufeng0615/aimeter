import Foundation

/// UI language preference — "auto" follows system locale.
enum Language: String, CaseIterable {
    case auto, en, zh
}

/// Bilingual string helper. `zh` is computed fresh on every access so SwiftUI
/// views that re-render (via @AppStorage("language")) pick up the new value.
enum S {
    static var zh: Bool {
        let raw = UserDefaults.standard.string(forKey: "language") ?? Language.auto.rawValue
        switch Language(rawValue: raw) ?? .auto {
        case .en:   return false
        case .zh:   return true
        case .auto: return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    static var today: String        { zh ? "今日" : "TODAY" }
    static var thisWeek: String     { zh ? "近 7 天" : "LAST 7 DAYS" }
    static var tokens: String       { zh ? "用量" : "tokens" }
    static var cost: String         { zh ? "花费" : "cost" }
    static var messages: String     { zh ? "消息" : "messages" }
    static var quit: String         { zh ? "退出" : "Quit" }
    static var settings: String     { zh ? "设置" : "Settings" }
    static var title: String        { "aimeter" }
    static var noData: String       { zh ? "等待会话数据…" : "Waiting for session data…" }
    static var claudeRateWaiting: String {
        zh
            ? "在 Claude Code 里发一条消息即可显示 5H / 7D 限额"
            : "Send a message in Claude Code to populate 5H / 7D limits."
    }
    static var codexRateWaiting: String {
        zh
            ? "在 Codex 里发一条消息即可显示 rate limit"
            : "Send a message in Codex to populate rate limits."
    }
    static var claudeRateUnavailable: String {
        zh
            ? "当前账号未返回 5H / 7D 限额数据（可能非订阅账号）"
            : "5H / 7D limits are not provided by this account (non-subscription?)."
    }
    static var week: String         { zh ? "本周" : "Week" }

    // Updates (Sparkle)
    static var checkForUpdates: String    { zh ? "检查更新…" : "Check for Updates…" }
    static var autoCheckUpdates: String   { zh ? "自动检查更新" : "Automatically check for updates" }
    static var updatesSectionTitle: String { zh ? "更新" : "Updates" }

    static func resetsIn(_ t: String) -> String {
        zh ? "\(t) 后重置" : "Resets in \(t)"
    }

    static func timeSpan(minutes m: Int) -> String {
        if m >= 60 {
            return zh ? "\(m/60)h\(m%60)m" : "\(m/60)h \(m%60)m"
        }
        return "\(m)m"
    }

    static func weekday(_ wd: Int) -> String {
        guard (1...7).contains(wd) else { return "?" }
        if zh { return ["日","一","二","三","四","五","六"][wd - 1] }
        return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][wd - 1]
    }
}
