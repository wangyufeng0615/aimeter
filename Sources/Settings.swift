import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("language") private var language: String = Language.auto.rawValue
    @AppStorage(AppPaths.Keys.claudeRoot) private var storedClaudeRoot = AppPaths.defaultClaudeRootPath
    @AppStorage(AppPaths.Keys.codexRoot) private var storedCodexRoot = AppPaths.defaultCodexRootPath
    @State private var hookInstalled = SetupHelper.isHookInstalled()
    @State private var claudeRootDraft = AppPaths.defaultClaudeRootPath
    @State private var codexRootDraft = AppPaths.defaultCodexRootPath

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        Form {
            Section(header: sectionHeader(S.zh ? "隐私" : "Privacy")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(Color.statusSafe)
                            .font(.system(size: 14))
                        Text(S.zh
                            ? "aimeter 完全在你的本机运行。不存储、不上传任何使用数据。"
                            : "aimeter runs entirely on your machine. It doesn't store or upload any of your usage data.")
                            .font(.system(size: 11, design: .monospaced))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(S.zh ? "本地读取：" : "Reads locally:")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        privacyItem("\(AppPaths.displayPath(AppPaths.claudeProjectsDir))/**/*.jsonl")
                        privacyItem(AppPaths.displayPath(AppPaths.claudeRateFile))
                        privacyItem(AppPaths.displayPath(AppPaths.claudeSettingsFile)
                            + "  (" + (S.zh ? "仅用于安装 hook" : "to install the hook") + ")")
                        privacyItem(AppPaths.displayPath(AppPaths.codexStateFile))
                        privacyItem("\(AppPaths.displayPath(AppPaths.codexSessionsDir))/**/rollout-*.jsonl")
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(S.zh ? "网络请求：" : "Network:")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        privacyItem(S.zh
                            ? "raw.githubusercontent.com  (仅取 LiteLLM 定价，每次启动一次)"
                            : "raw.githubusercontent.com  (LiteLLM pricing, once per launch)")
                    }
                }
                .padding(.vertical, 4)
            }

            Section(header: sectionHeader(S.zh ? "通用" : "General")) {
                Toggle(S.zh ? "开机自动启动" : "Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, new in applyLaunchAtLogin(new) }

                Picker(S.zh ? "语言" : "Language", selection: $language) {
                    Text(S.zh ? "跟随系统" : "Follow system").tag(Language.auto.rawValue)
                    Text("English").tag(Language.en.rawValue)
                    Text("中文").tag(Language.zh.rawValue)
                }
            }

            Section(header: sectionHeader(S.zh ? "目录" : "Paths")) {
                VStack(alignment: .leading, spacing: 8) {
                    PathRow(
                        title: "Claude Code",
                        text: $claudeRootDraft,
                        storedValue: storedClaudeRoot,
                        defaultURL: AppPaths.defaultClaudeRoot,
                        commit: saveClaudeRoot
                    )

                    PathRow(
                        title: "Codex",
                        text: $codexRootDraft,
                        storedValue: storedCodexRoot,
                        defaultURL: AppPaths.defaultCodexRoot,
                        commit: saveCodexRoot
                    )

                    Text(S.zh
                        ? "如果你的 Claude Code 或 Codex 没有安装在默认目录，可以在这里修改。"
                        : "If your Claude Code or Codex isn't installed in the default directory, change it here.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }

            Section(header: sectionHeader(S.zh ? "集成" : "Integration")) {
                LabeledContent("Claude Code") {
                    StatusBadge(status: hookInstalled ? .ok : .warn,
                                text: hookInstalled
                                    ? (S.zh ? "已安装" : "Hook installed")
                                    : (S.zh ? "未安装" : "Hook missing"))
                }

                Text(S.zh
                    ? "Claude Code 只通过 statusline 管道暴露用量数据。aimeter 会在 \(AppPaths.displayPath(AppPaths.claudeSettingsFile)) 里加一个 tee 命令，把数据流抓到本地文件。"
                    : "Claude Code exposes rate limits only through its statusline pipe. aimeter adds a `tee` to \(AppPaths.displayPath(AppPaths.claudeSettingsFile)) to capture it.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    if hookInstalled {
                        Button(S.zh ? "定位 settings.json" : "Reveal settings.json") {
                            reveal(AppPaths.claudeSettingsFile)
                        }
                        Button(S.zh ? "移除 hook" : "Remove hook", role: .destructive) {
                            _ = SetupHelper.uninstallHook()
                            hookInstalled = false
                        }
                    } else {
                        Button(S.zh ? "安装 hook…" : "Install hook…") {
                            SetupHelper.promptAndInstall { _ in
                                hookInstalled = SetupHelper.isHookInstalled()
                            }
                        }
                    }
                    Spacer()
                }

                LabeledContent("Codex") {
                    StatusBadge(status: UsageStore.codexInstalled ? .ok : .muted,
                                text: UsageStore.codexInstalled
                                    ? (S.zh ? "已检测到" : "Detected")
                                    : (S.zh ? "未安装" : "Not installed"))
                }
                if UsageStore.codexInstalled {
                    Text(S.zh
                        ? "Codex 把用量数据直接写入 session JSONL 文件。aimeter 直接读取 \(AppPaths.displayPath(AppPaths.codexSessionsDir))，无需安装 hook。"
                        : "Codex writes rate limits into session JSONL files. aimeter reads \(AppPaths.displayPath(AppPaths.codexSessionsDir)) directly — no hook needed.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

#if canImport(Sparkle)
            Section(header: sectionHeader(S.updatesSectionTitle)) {
                UpdatesSettingsSection()
            }
#endif

            Section(header: sectionHeader(S.zh ? "关于" : "About")) {
                LabeledContent(S.zh ? "版本" : "Version") {
                    Text(version)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LabeledContent(S.zh ? "源码" : "Source") {
                    AboutLink("github.com/wangyufeng0615/aimeter",
                              url: "https://github.com/wangyufeng0615/aimeter")
                }
            }
        }
        .formStyle(.grouped)
        // Keep the settings window usable on smaller laptop displays and let
        // Form provide its native vertical scrolling when content grows.
        .frame(width: 560, height: 640)
        .onAppear {
            claudeRootDraft = storedClaudeRoot
            codexRootDraft = storedCodexRoot
            hookInstalled = SetupHelper.isHookInstalled()
        }
        .background(WindowConfig { window in
            // Hide minimize/zoom; keep only the red close button
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            // Don't allow resize (content auto-sizes)
            window.styleMask.remove(.resizable)
        })
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.primary).opacity(0.7)
            .kerning(1.2)
    }

    private func privacyItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·").foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func applyLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silent — user can re-toggle
        }
    }

    private func saveClaudeRoot() {
        let normalized = AppPaths.normalizedRootInput(claudeRootDraft, defaultURL: AppPaths.defaultClaudeRoot)
        storedClaudeRoot = normalized
        claudeRootDraft = normalized
        hookInstalled = SetupHelper.isHookInstalled()
    }

    private func saveCodexRoot() {
        let normalized = AppPaths.normalizedRootInput(codexRootDraft, defaultURL: AppPaths.defaultCodexRoot)
        storedCodexRoot = normalized
        codexRootDraft = normalized
    }

    private func reveal(_ url: URL) {
        let fm = FileManager.default
        let target = fm.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }
}

// MARK: - Components

private enum Status { case ok, warn, muted }

private struct StatusBadge: View {
    let status: Status
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
    private var symbol: String {
        switch status {
        case .ok:    return "checkmark.circle.fill"
        case .warn:  return "exclamationmark.triangle.fill"
        case .muted: return "circle.dashed"
        }
    }
    private var color: Color {
        switch status {
        case .ok:    return .statusSafe
        case .warn:  return .statusWarn
        case .muted: return .secondary
        }
    }
}

private struct AboutLink: View {
    let title: String
    let url: String
    init(_ title: String, url: String) { self.title = title; self.url = url }
    var body: some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, design: .monospaced))
                Image(systemName: "arrow.up.right.square").font(.caption2)
            }
        }
        .buttonStyle(.link)
    }
}

// MARK: - Path row

private struct PathRow: View {
    let title: String
    @Binding var text: String
    let storedValue: String
    let defaultURL: URL
    let commit: () -> Void

    private var resolvedURL: URL {
        AppPaths.expandedURL(from: text, defaultURL: defaultURL)
    }

    private var exists: Bool {
        var isDir: ObjCBool = false
        let ok = FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDir)
        return ok && isDir.boolValue
    }

    private var isDirty: Bool {
        AppPaths.normalizedRootInput(text, defaultURL: defaultURL) != storedValue
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 88, alignment: .leading)

            ZStack(alignment: .trailing) {
                // Commit only on explicit Return or via Choose…; avoids racing
                // with the Choose button's focus-loss event (which would
                // otherwise persist an unconfirmed draft even if the user
                // cancels the panel).
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .onSubmit { commit() }

                if isDirty {
                    Text(S.zh ? "↵ 保存" : "↵ save")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )
                        .padding(.trailing, 6)
                        .allowsHitTesting(false)
                } else if !exists {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.statusWarn)
                        .padding(.trailing, 8)
                        .help(S.zh ? "目录不存在" : "Directory not found")
                        .allowsHitTesting(false)
                }
            }

            Button(S.zh ? "选择…" : "Choose…", action: chooseDirectory)
                .help(S.zh ? "选择目录" : "Browse for directory")
        }
    }

    private func chooseDirectory() {
        // Discard any unsaved draft — the panel is the source of truth once
        // it opens.
        text = storedValue

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = exists ? resolvedURL : defaultURL
        panel.prompt = S.zh ? "选择" : "Choose"
        panel.message = S.zh
            ? "选择 \(title) 的根目录"
            : "Choose the \(title) root directory"

        if panel.runModal() == .OK, let chosen = panel.url {
            text = AppPaths.displayPath(chosen)
            commit()
        }
    }
}

// MARK: - Window config bridge

/// Configures the hosting NSWindow after the view mounts.
private struct WindowConfig: NSViewRepresentable {
    let setup: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let w = view.window {
                setup(w)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let w = nsView.window { setup(w) }
        }
    }
}
