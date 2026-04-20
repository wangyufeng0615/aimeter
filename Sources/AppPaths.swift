import Foundation

enum AppPaths {
    enum Keys {
        static let claudeRoot = "claudeRootPath"
        static let codexRoot = "codexRootPath"
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL

    static let defaultClaudeRoot = home.appendingPathComponent(".claude", isDirectory: true)
    static let defaultCodexRoot = home.appendingPathComponent(".codex", isDirectory: true)

    static let defaultClaudeRootPath = displayPath(defaultClaudeRoot)
    static let defaultCodexRootPath = displayPath(defaultCodexRoot)

    static var claudeRoot: URL {
        rootURL(forKey: Keys.claudeRoot, defaultURL: defaultClaudeRoot)
    }

    static var codexRoot: URL {
        rootURL(forKey: Keys.codexRoot, defaultURL: defaultCodexRoot)
    }

    static var claudeProjectsDir: URL {
        claudeRoot.appendingPathComponent("projects", isDirectory: true)
    }

    static var claudeRateFile: URL {
        claudeRoot.appendingPathComponent("usage-rate.json")
    }

    static var claudeSettingsFile: URL {
        claudeRoot.appendingPathComponent("settings.json")
    }

    static var codexStateFile: URL {
        codexRoot.appendingPathComponent("state_5.sqlite")
    }

    static var codexSessionsDir: URL {
        codexRoot.appendingPathComponent("sessions", isDirectory: true)
    }

    static func normalizedRootInput(_ raw: String, defaultURL: URL) -> String {
        displayPath(expandedURL(from: raw, defaultURL: defaultURL))
    }

    static func expandedURL(from raw: String, defaultURL: URL) -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultURL }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    static func displayPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = home.path

        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath + "/") {
            return "~" + String(path.dropFirst(homePath.count))
        }
        return path
    }

    static func shellPath(_ url: URL) -> String {
        let display = displayPath(url)
        if display.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
           !display.contains("'") {
            return display
        }
        return shellQuote(url.standardizedFileURL.path)
    }

    static func claudeRateCacheFile() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? home
        let dir = caches.appendingPathComponent("com.aimeter.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("claude-rate-v1-\(stableHash(claudeRoot.path)).json")
    }

    private static func rootURL(forKey key: String, defaultURL: URL) -> URL {
        let raw = UserDefaults.standard.string(forKey: key) ?? displayPath(defaultURL)
        return expandedURL(from: raw, defaultURL: defaultURL)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }
}
