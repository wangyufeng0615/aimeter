import AppKit
import Foundation

enum SetupHelper {
    static let rateFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/usage-rate.json")
    static let settingsFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
    static let teeFragment = "tee ~/.claude/usage-rate.json"

    /// Check on launch and prompt user if needed. Call from main thread.
    static func checkOnLaunch() {
        guard UsageStore.claudeInstalled else { return }
        guard !isAlreadyConfigured() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            promptUser()
        }
    }

    /// Check whether the hook is currently installed (for Settings display).
    /// Matches either `~/.claude/usage-rate.json` (tilde form) or the fully
    /// expanded path — shells may expand `~` when the user saves the file.
    static func isHookInstalled(at settingsFile: URL = SetupHelper.settingsFile) -> Bool {
        guard let json = readSettings(at: settingsFile),
              let sl = json["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String
        else { return false }
        return cmd.contains("tee") && cmd.contains("usage-rate.json")
    }

    /// Re-run the install wizard from Settings panel. `completion` fires with success.
    static func promptAndInstall(completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.main.async {
            promptUser()
            completion?(isHookInstalled())
        }
    }

    /// Uninstall the tee hook (restore statusLine to what it was without our prefix).
    @discardableResult
    static func uninstallHook(at settingsFile: URL = SetupHelper.settingsFile) -> Bool {
        guard var json = readSettings(at: settingsFile) else { return false }
        guard let sl = json["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String,
              cmd.contains("tee"), cmd.contains("usage-rate.json")
        else { return false }

        // Backup before mutating
        let stamp = Int(Date().timeIntervalSince1970)
        _ = try? FileManager.default.copyItem(
            atPath: settingsFile.path,
            toPath: settingsFile.path + ".bak-\(stamp)")

        // Match the tee fragment with optional `~` or full path to usage-rate.json
        let pattern = #"tee\s+(?:~|/[^\s]*)/\.claude/usage-rate\.json(?:\s*\|\s*)?"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(cmd.startIndex..., in: cmd)
        let stripped = regex?.stringByReplacingMatches(
            in: cmd, range: range, withTemplate: "") ?? cmd
        let trimmed = stripped.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            json.removeValue(forKey: "statusLine")
        } else {
            var newSl = sl
            newSl["command"] = trimmed
            json["statusLine"] = newSl
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return false }
        return ((try? data.write(to: settingsFile, options: .atomic)) != nil)
    }

    private static func isAlreadyConfigured() -> Bool {
        // If rate file exists and is fresh (< 6h), tee is working
        if FileManager.default.fileExists(atPath: rateFile.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: rateFile.path),
           let mod = attrs[.modificationDate] as? Date,
           mod.timeIntervalSinceNow > -6 * 3600 {
            return true
        }
        // Fall back to checking settings.json
        return isHookInstalled()
    }

    private static func promptUser() {
        // Pre-flight: detect any condition that would make automatic edit unsafe
        if let issue = preflight() {
            showManualInstructions(reason: issue)
            return
        }

        let alert = NSAlert()
        alert.messageText = S.zh ? "需要一次性配置" : "One-time Setup Required"
        alert.informativeText = S.zh
            ? """
              Claude Code 的 rate limit 数据只在运行时通过内部管道传输，不会保存到磁盘。

              需要在 statusline 命令中加入 tee，将数据写入本地文件，本应用才能读取百分比。

              将修改 ~/.claude/settings.json：
              · 自动备份到 settings.json.bak-{时间戳}
              · 仅添加 tee 命令，保留所有其他配置
              """
            : """
              Claude Code's rate limit data only flows through an internal pipe at runtime — it's never saved to disk.

              This app needs to add a tee command to your statusline config so it can read the percentages.

              Will modify ~/.claude/settings.json:
              · Auto-backup to settings.json.bak-{timestamp}
              · Only adds a tee command; all other settings preserved
              """
        alert.alertStyle = .informational
        alert.addButton(withTitle: S.zh ? "允许配置" : "Allow")
        alert.addButton(withTitle: S.zh ? "稍后" : "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            switch injectTee() {
            case .success:
                showSimple(
                    S.zh ? "配置完成" : "Setup Complete",
                    S.zh
                        ? "下次 Claude Code 响应时，rate limit 数据就会显示。原配置已备份。"
                        : "Rate limit data will appear after your next Claude Code response. Backup saved."
                )
            case .failed(let reason):
                showManualInstructions(reason: reason)
            }
        }
    }

    // MARK: - Pre-flight safety checks

    enum PreflightIssue {
        case unreadable          // file exists but can't read
        case malformed           // file exists but isn't valid JSON
        case symlink             // file is a symlink
        case unexpectedFormat    // statusLine exists but in unexpected shape
    }

    static func preflight(at settingsFile: URL = SetupHelper.settingsFile) -> PreflightIssue? {
        guard FileManager.default.fileExists(atPath: settingsFile.path) else {
            // No settings file yet — safe to create from scratch
            return nil
        }

        // Reject symlinks — atomic write would replace the target, breaking semantics
        if let attrs = try? FileManager.default.attributesOfItem(atPath: settingsFile.path),
           let type = attrs[.type] as? FileAttributeType, type == .typeSymbolicLink {
            return .symlink
        }

        guard let data = try? Data(contentsOf: settingsFile) else {
            return .unreadable
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed
        }

        // Validate statusLine if present
        if let sl = json["statusLine"] {
            guard let dict = sl as? [String: Any], dict["command"] is String else {
                return .unexpectedFormat
            }
        }
        return nil
    }

    // MARK: - Inject

    enum InjectResult: Equatable {
        case success
        case failed(PreflightIssue)
    }

    static func injectTee(at settingsFile: URL = SetupHelper.settingsFile) -> InjectResult {
        // Final preflight (file may have changed since prompt)
        if let issue = preflight(at: settingsFile) { return .failed(issue) }

        // Snapshot the original bytes + mtime — used as TOCTOU guard before write
        let fileExists = FileManager.default.fileExists(atPath: settingsFile.path)
        var originalData: Data? = nil
        var originalMtime: Date? = nil
        if fileExists {
            originalData = try? Data(contentsOf: settingsFile)
            originalMtime = (try? FileManager.default.attributesOfItem(atPath: settingsFile.path))?[.modificationDate] as? Date
            if originalData == nil { return .failed(.unreadable) }
        }

        // Build new JSON
        var json: [String: Any]
        if let raw = originalData,
           let parsed = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] {
            json = parsed
        } else {
            json = [:]
        }

        if let sl = json["statusLine"] as? [String: Any],
           let cmd = sl["command"] as? String {
            if cmd.contains(teeFragment) { return .success }
            var newSl = sl  // preserve unknown keys
            newSl["command"] = "\(teeFragment) | \(cmd)"
            json["statusLine"] = newSl
        } else {
            json["statusLine"] = ["type": "command", "command": teeFragment]
        }

        guard let newData = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return .failed(.malformed) }

        // TOCTOU re-check: file unchanged since snapshot?
        if fileExists {
            let currentMtime = (try? FileManager.default.attributesOfItem(atPath: settingsFile.path))?[.modificationDate] as? Date
            if currentMtime != originalMtime { return .failed(.unexpectedFormat) }

            // Backup before write
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = settingsFile.path + ".bak-\(stamp)"
            guard (try? FileManager.default.copyItem(atPath: settingsFile.path, toPath: backup)) != nil
            else { return .failed(.unreadable) }
            cleanupBackups(at: settingsFile, keeping: 3)
        }

        return ((try? newData.write(to: settingsFile, options: .atomic)) != nil)
            ? .success : .failed(.unreadable)
    }

    /// Keep only the most recent N backup files
    static func cleanupBackups(at settingsFile: URL = SetupHelper.settingsFile, keeping limit: Int) {
        let dir = settingsFile.deletingLastPathComponent()
        let prefix = settingsFile.lastPathComponent + ".bak-"
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        let backups = urls.filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for url in backups.dropFirst(limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func readSettings(at settingsFile: URL = SetupHelper.settingsFile) -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    // MARK: - Manual instructions fallback

    private static func showManualInstructions(reason: PreflightIssue) {
        let why: String
        switch reason {
        case .unreadable:        why = S.zh ? "无法读取 settings.json" : "Cannot read settings.json"
        case .malformed:         why = S.zh ? "settings.json 格式异常（可能含注释或无效 JSON）" : "settings.json is malformed (may contain comments or invalid JSON)"
        case .symlink:           why = S.zh ? "settings.json 是符号链接" : "settings.json is a symbolic link"
        case .unexpectedFormat:  why = S.zh ? "statusLine 字段格式与预期不符" : "statusLine field has unexpected format"
        }

        let snippet = "\"statusLine\": {\n  \"type\": \"command\",\n  \"command\": \"tee ~/.claude/usage-rate.json | <your existing command, or omit if none>\"\n}"

        let alert = NSAlert()
        alert.messageText = S.zh ? "需要手动配置" : "Manual Setup Required"
        alert.informativeText = S.zh
            ? "无法自动配置（\(why)）。请手动在 ~/.claude/settings.json 中添加：\n\n\(snippet)"
            : "Auto-setup unavailable (\(why)). Please add this to ~/.claude/settings.json manually:\n\n\(snippet)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func showSimple(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.runModal()
    }
}
