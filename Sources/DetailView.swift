import SwiftUI

// MARK: - Design tokens (unified monospaced/engineering aesthetic)

enum Font2 {
    /// Service name & section header
    static let header    = Font.system(size: 13, weight: .semibold, design: .monospaced)
    /// Big hero percentage (the ONE number user checks at a glance)
    static let hero      = Font.system(size: 24, weight: .bold, design: .monospaced)
    /// Smaller percent sign following hero
    static let heroUnit  = Font.system(size: 12, weight: .semibold, design: .monospaced)
    /// Body stats (tokens / cost / count)
    static let stat      = Font.system(size: 15, weight: .semibold, design: .monospaced)
    /// Labels under stats
    static let label     = Font.system(size: 10, weight: .regular, design: .monospaced)
    /// Section meta (Resets in, Week, 5h, 7d etc.)
    static let meta      = Font.system(size: 10, weight: .medium, design: .monospaced)
    /// Chart row text (model names, weekday, token amounts)
    static let row       = Font.system(size: 10, weight: .regular, design: .monospaced)
    /// Section eyebrow (TODAY, THIS WEEK) — slightly more prominent
    static let eyebrow   = Font.system(size: 11, weight: .bold, design: .monospaced)
    /// Small window badge (5H / 7D) next to percentages
    static let badge     = Font.system(size: 10, weight: .bold, design: .monospaced)
    /// Footer
    static let footer    = Font.system(size: 10, weight: .regular, design: .monospaced)
}

struct DetailView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Subtle wordmark header
            HStack {
                Text("aimeter")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary).opacity(0.5)
                    .kerning(0.5)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)

            Divider()

            VStack(spacing: 12) {
                rateSection
                todaySection
                weekSection
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            Spacer(minLength: 0)

            Divider()
            HStack(spacing: 4) {
                FooterButton(icon: "gearshape", label: S.settings) {
                    openSettingsFromMenuBar()
                }
                Spacer()
                FooterButton(icon: "power", label: S.quit) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
        }
        .frame(width: 320, alignment: .top)
    }

    /// Reliable Settings opening from a MenuBarExtra(.window) popover.
    /// `NSApp.sendAction(showSettingsWindow:)` is flaky here — the responder
    /// chain dispatch inside MenuBarExtra's window doesn't reach the Settings
    /// scene. Using SwiftUI's `openSettings` action (macOS 14+) is the
    /// official path and works reliably.
    private func openSettingsFromMenuBar() {
        dismiss()  // Close the menu bar popover first
        Task { @MainActor in
            // Yield a frame so the popover dismissal completes before we
            // bring up a titled window.
            await Task.yield()
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
    }

    // MARK: - Rate limits

    private var rateSection: some View {
        VStack(spacing: 4) {
            if UsageStore.claudeInstalled {
                rateCard(
                    name: "Claude Code",
                    rate: store.claudeRate,
                    emptyMessage: claudeEmptyRateMessage
                )
            }
            if UsageStore.codexInstalled {
                rateCard(name: "Codex", rate: store.codexRate, emptyMessage: S.codexRateWaiting)
            }
        }
    }

    private var claudeEmptyRateMessage: String {
        switch store.claudeRateStatus {
        case .available:
            return S.noData
        case .waitingForSessionData:
            return S.claudeRateWaiting
        case .rateLimitsUnavailable:
            return S.claudeRateUnavailable
        }
    }

    private func rateCard(name: String, rate: RateLimit?, emptyMessage: String = S.noData) -> some View {
        let pct5 = rate?.fiveHourPct ?? 0
        let pct7 = rate?.sevenDayPct ?? 0
        let hasRate = rate != nil

        // Column widths — keep 5H and 7D bars/percentages vertically aligned
        let labelWidth: CGFloat = 20
        let valueWidth: CGFloat = 46

        return VStack(alignment: .leading, spacing: 0) {
            // Service name
            Text(name).font(Font2.header)
                .padding(.bottom, 2)

            // ── 5H row (primary: thick bar, big percentage) ──
            HStack(alignment: .center, spacing: 8) {
                Text("5H")
                    .font(Font2.badge)
                    .foregroundColor(.secondary)
                    .frame(width: labelWidth, alignment: .leading)

                UsageBar(value: pct5, color: pctColor(pct5), height: 9, fillOpacity: 0.9)

                percentageText(pct5, color: pctColor(pct5),
                               numberSize: 14, unitSize: 8)
                    .frame(width: valueWidth, alignment: .trailing)
            }

            // Reset time — indented under 5H bar
            if hasRate,
               let r = rate?.fiveHourResetsAt,
               let m = resetMinutesRemaining(until: r) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: labelWidth + 8)
                    Text(S.resetsIn(S.timeSpan(minutes: m)))
                        .font(Font2.meta)
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                    Spacer()
                }
                .padding(.top, 0)
            }

            Spacer().frame(height: 2)

            // ── 7D row (secondary: thin bar, smaller percentage — hierarchy via SIZE, not color dimming) ──
            HStack(alignment: .center, spacing: 8) {
                Text("7D")
                    .font(Font2.badge)
                    .foregroundColor(.secondary)
                    .frame(width: labelWidth, alignment: .leading)

                UsageBar(value: pct7, color: pctColor(pct7), height: 5, fillOpacity: 0.85)

                percentageText(pct7, color: pctColor(pct7),
                               numberSize: 11, unitSize: 7)
                    .frame(width: valueWidth, alignment: .trailing)
            }

            if !hasRate {
                Text(emptyMessage)
                    .font(Font2.meta)
                    .foregroundColor(.secondary)
                    .opacity(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
            }
        }
    }

    /// Formatted percentage text: big number + small unit, both tinted the same color.
    private func percentageText(_ pct: Double, color: Color,
                                numberSize: CGFloat, unitSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(Int(pct))")
                .font(.system(size: numberSize, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(color)
            Text("%")
                .font(.system(size: unitSize, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .opacity(0.7)
                .baselineOffset(1)
        }
    }


    // MARK: - Today

    /// True only during the very first data load (Stage 2 hasn't completed yet)
    private var isInitialLoad: Bool {
        store.isLoading && store.ccEntries.isEmpty && store.cxEntries.isEmpty
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                SectionHeader(S.today)
                if isInitialLoad {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }
                Spacer()
            }

            let today = store.usageSummary.today
            let models = today.models

            HStack(spacing: 0) {
                StatCell(value: fmtTokens(today.tokens), label: S.tokens)
                dot
                StatCell(value: fmtCost(today.cost), label: S.cost)
                dot
                StatCell(value: "\(today.messageCount)", label: S.messages)
            }
            .redacted(reason: isInitialLoad ? .placeholder : [])

            if !models.isEmpty {
                let peak = models.map(\.tokens).max() ?? 1
                VStack(spacing: 3) {
                    ForEach(models.prefix(3)) { m in
                        HStack(spacing: 4) {
                            Text(m.displayName)
                                .font(Font2.row)
                                .foregroundColor(.secondary)
                                .frame(width: 86, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(m.fullName)  // hover tooltip with full model name
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(modelColor(m).opacity(0.55))
                                    .frame(width: max(2, geo.size.width * CGFloat(m.tokens) / CGFloat(peak)))
                            }.frame(height: 7)
                            Text(fmtTokens(m.tokens))
                                .font(Font2.row)
                                .foregroundColor(.secondary)
                                .frame(width: 44, alignment: .trailing)
                            Text(fmtCostShort(m.cost))
                                .font(Font2.row)
                                .foregroundColor(.secondary).opacity(0.6)
                                .frame(width: 40, alignment: .trailing)
                        }.frame(height: 12)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - This week

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SectionHeader(S.thisWeek)
                if isInitialLoad {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }
                Spacer()
            }

            let weekly = store.usageSummary.weekly
            let peak = max(1, weekly.map(\.tokens).max() ?? 1)

            VStack(spacing: 2) {
                ForEach(weekly) { day in
                    let isToday = Calendar.current.isDateInToday(day.date)
                    HStack(spacing: 4) {
                        Text(S.weekday(Calendar.current.component(.weekday, from: day.date)))
                            .font(Font2.row)
                            .fontWeight(isToday ? .bold : .regular)
                            .foregroundColor(isToday ? .primary : .secondary)
                            .frame(width: 24, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(isToday ? 0.7 : 0.25))
                                .frame(width: day.tokens > 0
                                    ? max(2, geo.size.width * CGFloat(day.tokens) / CGFloat(peak))
                                    : 0)
                        }.frame(height: 7)
                        Text(day.tokens > 0 ? fmtTokens(day.tokens) : "—")
                            .font(Font2.row)
                            .foregroundColor(.secondary)
                            .opacity(day.tokens > 0 ? 1 : 0.4)
                            .frame(width: 44, alignment: .trailing)
                        Text(day.cost > 0 ? fmtCostShort(day.cost) : "")
                            .font(Font2.row)
                            .foregroundColor(.secondary).opacity(0.6)
                            .frame(width: 40, alignment: .trailing)
                    }.frame(height: 12)
                }
            }
            .redacted(reason: isInitialLoad ? .placeholder : [])
        }
    }

    // MARK: - Helpers

    private var dot: some View {
        Circle().fill(Color.primary.opacity(0.06)).frame(width: 3, height: 3)
    }

    private func resetMinutesRemaining(until date: Date) -> Int? {
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        return max(1, Int(ceil(remaining / 60)))
    }

    private func pctColor(_ pct: Double) -> Color {
        switch pct {
        case ..<50: .statusSafe
        case ..<80: .statusWarn
        default:    .statusDanger
        }
    }

    private func modelColor(_ model: UsageStore.ModelBreakdown) -> Color {
        switch model.source {
        case .claude:
            return modelColor(model.fullName)
        case .codex:
            return .orange
        }
    }

    private func modelColor(_ m: String) -> Color {
        let l = m.lowercased()
        if l.contains("opus") { return .indigo }
        if l.contains("sonnet") { return .blue }
        if l.contains("haiku") { return .teal }
        return .gray
    }
}

// MARK: - Components

struct UsageBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 7
    var fillOpacity: Double = 0.85
    var trackOpacity: Double = 0.06

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2.5)
                    .fill(Color.primary.opacity(trackOpacity))
                RoundedRectangle(cornerRadius: height / 2.5)
                    .fill(color.opacity(fillOpacity))
                    .frame(width: geo.size.width * max(0, min(CGFloat(value) / 100, 1)))
            }
        }.frame(height: height)
    }
}

struct SectionHeader: View {
    let text: String; init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Font2.eyebrow)
            .foregroundColor(.primary).opacity(0.75)
            .kerning(1.2)
    }
}

struct StatCell: View {
    let value: String; let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(Font2.stat).monospacedDigit()
            Text(label).font(Font2.label).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

func fmtTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000     { return String(format: "%.0fK", Double(n) / 1_000) }
    return "\(n)"
}

func fmtCost(_ v: Double) -> String { String(format: "$%.2f", v) }

/// Footer action button with icon + label and subtle hover highlight.
struct FooterButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .medium))
                Text(label)
            }
            .font(Font2.footer)
            .foregroundColor(hovering ? .primary : .secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Compact cost: $1.2 / $0.03 / $123
func fmtCostShort(_ v: Double) -> String {
    if v >= 100  { return "$\(Int(v))" }
    if v >= 10   { return String(format: "$%.1f", v) }
    if v >= 1    { return String(format: "$%.2f", v) }
    if v >= 0.01 { return String(format: "$%.2f", v) }
    if v > 0     { return "<$0.01" }
    return ""
}
