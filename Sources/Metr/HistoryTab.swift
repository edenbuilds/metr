import SwiftUI
import MetrKit

/// Provider-specific history. Quotas remain provider-reported; historical
/// activity comes from each app's local files and is labelled separately.
struct HistoryTab: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var motion: MotionSettings

    private var selectedID: String? { store.historyProviderID }

    private var filteredActivity: [DailyActivity] {
        let rows = store.snapshot.activity.filter { selectedID == nil || $0.providerID == selectedID }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = store.location.timeZone
        let grouped = Dictionary(grouping: rows) { calendar.startOfDay(for: $0.date) }
        return grouped.map { day, values in
            DailyActivity(
                date: day,
                messageCount: values.reduce(0) { $0 + $1.messageCount },
                sessionCount: values.reduce(0) { $0 + $1.sessionCount },
                toolCallCount: values.reduce(0) { $0 + $1.toolCallCount },
                providerID: selectedID
            )
        }.sorted { $0.date < $1.date }
    }

    private var recent: [DailyActivity] { Array(filteredActivity.suffix(14)) }

    private var selectedName: String {
        guard let selectedID else { return "All apps" }
        return store.snapshot.providers.first { $0.id == selectedID }?.identity.name ?? "App"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            providerPicker
            Text(selectedID == KnownProvider.claude.id ? "Claude conversations" : "Detailed history")
                .font(Theme.Text.captionTight.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            weeklySummary

            if recent.isEmpty {
                Card {
                    EmptyStateView(
                        symbolName: "chart.bar",
                        title: "No past activity yet",
                        message: "\(selectedName) has not written readable local activity on this Mac. metr will never invent a historical total.",
                        actionLabel: store.preferences.dataSource == .local ? "Try demo data" : nil,
                        action: store.preferences.dataSource == .local ? { store.preferences.dataSource = .mock } : nil
                    )
                }
            } else {
                activityCard
            }

            sessionsCard
        }
        .animation(motion.content, value: store.historyProviderID)
    }

    private var providerPicker: some View {
        Picker("App", selection: Binding(
            get: { store.historyProviderID ?? "all" },
            set: { store.historyProviderID = $0 == "all" ? nil : $0 }
        )) {
            Text("All").tag("all")
            ForEach(store.visibleProviders) { provider in
                Text(provider.id == KnownProvider.claude.id ? "Claude conversations" : provider.identity.name)
                    .tag(provider.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("History app")
    }

    private var weeklySummary: some View {
        let weekAgo = store.now.addingTimeInterval(-7 * 86_400)
        let week = filteredActivity.filter { $0.date >= weekAgo }
        let messages = week.reduce(0) { $0 + $1.messageCount }
        let sessions = week.reduce(0) { $0 + $1.sessionCount }
        let tools = week.reduce(0) { $0 + $1.toolCallCount }
        let provider = selectedID.flatMap { id in store.snapshot.providers.first { $0.id == id } }
        let weeklyQuota = provider?.quotaPeriods.first { ($0.span ?? 0) >= 6 * 86_400 }

        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("This week · \(selectedName)")
                            .font(Theme.Text.heading)
                        Text("Measured from local app activity")
                            .font(Theme.Text.captionTight)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ConfidenceTag(confidence: .measured, assumption: "Session and activity files already stored on this Mac.")
                }

                HStack(spacing: Theme.Space.base) {
                    stat(value: "\(sessions)", label: "sessions")
                    Divider().frame(height: 25)
                    if selectedID == KnownProvider.codex.id {
                        stat(value: "—", label: "messages unavailable")
                    } else {
                        stat(value: Formatters.compactCount(messages), label: "messages")
                    }
                    Divider().frame(height: 25)
                    stat(value: tools == 0 ? "—" : Formatters.compactCount(tools), label: "tool calls")
                }

                if let weeklyQuota {
                    Divider()
                    HStack {
                        Text("Provider weekly limit")
                            .font(Theme.Text.captionTight.weight(.medium))
                        Spacer()
                        Text(Formatters.percent(weeklyQuota.usedFraction))
                            .font(Theme.Text.metric)
                        if let reset = weeklyQuota.resetAt {
                            Text("· \(Formatters.countdown(reset.timeIntervalSince(store.now))) left")
                                .font(Theme.Text.captionTight.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Meter(
                        fraction: weeklyQuota.usedFraction,
                        tint: provider.map { Theme.tint($0.identity.tintName) } ?? .accentColor,
                        severity: Severity.forFraction(weeklyQuota.usedFraction, thresholds: store.preferences.thresholds),
                        thresholds: store.preferences.thresholds,
                        showsThresholds: false
                    )
                }
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Theme.Text.metric)
            Text(label).font(Theme.Text.captionTight).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activityCard: some View {
        let peak = max(1, recent.map { max($0.messageCount, $0.sessionCount) }.max() ?? 1)
        let usesMessages = recent.contains { $0.messageCount > 0 }

        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                HStack {
                    Text(usesMessages ? "Daily messages" : "Daily sessions")
                        .font(Theme.Text.heading)
                    Spacer()
                    Text("Past 14 days")
                        .font(Theme.Text.captionTight)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(recent) { day in
                        let value = usesMessages ? day.messageCount : day.sessionCount
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(chartTint.opacity(isToday(day.date) ? 0.95 : 0.52))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(2, CGFloat(value) / CGFloat(peak) * 64))
                            .help("\(dayLabel(day.date)): \(value) \(usesMessages ? "messages" : "sessions")")
                    }
                }
                .frame(height: 66, alignment: .bottom)

                HStack {
                    Text(recent.first.map { dayLabel($0.date) } ?? "")
                    Spacer()
                    Text(recent.last.map { dayLabel($0.date) } ?? "")
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

                Text("Historical activity, not billing or plan usage. Days use system time.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(selectedName) daily activity")
            .accessibilityValue(chartSummary)
        }
    }

    private var chartTint: Color {
        guard let selectedID,
              let provider = store.snapshot.providers.first(where: { $0.id == selectedID }) else {
            return Brand.olive
        }
        return Theme.tint(provider.identity.tintName)
    }

    private var chartSummary: String {
        let usesMessages = recent.contains { $0.messageCount > 0 }
        let total = recent.reduce(0) { $0 + (usesMessages ? $1.messageCount : $1.sessionCount) }
        return "\(recent.count) days, \(total) \(usesMessages ? "messages" : "sessions") total for \(selectedName)."
    }

    private func isToday(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = store.location.timeZone
        return calendar.isDate(date, inSameDayAs: store.now)
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = store.location.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEd")
        return formatter.string(from: date)
    }

    private var filteredSessions: [SessionRecord] {
        store.snapshot.sessions.filter { selectedID == nil || $0.providerID == selectedID }
    }

    private var sessionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                HStack {
                    Text(selectedID == KnownProvider.claude.id ? "Recent Claude conversations" : "Recent sessions")
                        .font(Theme.Text.heading)
                    Spacer()
                    Text("\(filteredSessions.count)")
                        .font(Theme.Text.captionTight.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                if filteredSessions.isEmpty {
                    EmptyStateView(
                        symbolName: "bubble.left.and.bubble.right",
                        title: "No sessions found",
                        message: "Sessions appear after this app writes readable local history."
                    )
                } else {
                    ForEach(filteredSessions.prefix(6)) { session in sessionRow(session) }
                }
            }
        }
    }

    private func sessionRow(_ session: SessionRecord) -> some View {
        let tint = store.snapshot.providers.first { $0.id == session.providerID }
            .map { Theme.tint($0.identity.tintName) } ?? Color.secondary
        let time = Formatters.time(session.lastActive, in: store.location.timeZone)

        return HStack(spacing: Theme.Space.snug) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(session.title)
                .font(Theme.Text.captionTight)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Theme.Space.tight)
            Text(time)
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .help(session.workingDirectory.map { "\(session.title) — \($0)" } ?? session.title)
        .onTapGesture {
            if let directory = session.workingDirectory { QuickActions.revealInFinder(path: directory) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.title), last active \(time) in system time")
    }
}
