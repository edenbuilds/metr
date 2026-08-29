import SwiftUI
import TidemarkKit

struct HistoryTab: View {
    @EnvironmentObject private var store: UsageStore

    private var recent: [DailyActivity] {
        Array(store.snapshot.activity.suffix(14))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            if recent.isEmpty {
                Card {
                    EmptyStateView(
                        symbolName: "chart.bar",
                        title: "No history yet",
                        message: "History appears once there are a few days of activity to compare. Nothing has been recorded so far.",
                        actionLabel: store.preferences.dataSource == .local ? "Try demo data" : nil,
                        action: store.preferences.dataSource == .local ? { store.preferences.dataSource = .mock } : nil
                    )
                }
            } else {
                activityCard
            }

            sessionsCard
        }
    }

    // MARK: Activity chart

    private var activityCard: some View {
        let peak = max(1, recent.map(\.messageCount).max() ?? 1)
        let staleDays = recent.last.map { Int(store.now.timeIntervalSince($0.date) / 86_400) } ?? 0

        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                HStack {
                    Text("Daily messages")
                        .font(Theme.Text.heading)
                    Spacer()
                    if staleDays >= 2 {
                        StatusPill(symbolName: "clock.badge.exclamationmark", label: "\(staleDays)d behind", severity: .watch)
                            .help("The activity file this comes from was last written \(staleDays) days ago.")
                    }
                    ConfidenceTag(confidence: .measured, assumption: "Counted from the activity file on this Mac.")
                }

                // The chart is one accessibility element with a spoken summary;
                // a screen reader user gets the shape without tabbing 14 bars.
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(recent) { day in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Theme.tint("indigo").opacity(isToday(day.date) ? 0.95 : 0.55))
                                .frame(height: max(2, CGFloat(day.messageCount) / CGFloat(peak) * 64))
                        }
                        .frame(maxWidth: .infinity)
                        .help("\(dayLabel(day.date)): \(day.messageCount) messages, \(day.sessionCount) sessions")
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

                Text("Days shown in \(store.location.inlinePhrase).")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily message history")
            .accessibilityValue(chartSummary)
        }
    }

    private var chartSummary: String {
        guard !recent.isEmpty else { return "No data" }
        let total = recent.reduce(0) { $0 + $1.messageCount }
        let busiest = recent.max { $0.messageCount < $1.messageCount }
        let average = total / recent.count
        var summary = "\(recent.count) days, \(total) messages total, averaging \(average) per day"
        if let busiest {
            summary += ". Busiest was \(dayLabel(busiest.date)) with \(busiest.messageCount)"
        }
        return summary + ". Shown in \(store.location.inlinePhrase)."
    }

    private func isToday(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = store.location.timeZone
        return cal.isDate(date, inSameDayAs: store.now)
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = store.location.timeZone
        f.setLocalizedDateFormatFromTemplate("EEEd")
        return f.string(from: date)
    }

    // MARK: Recent sessions

    private var sessionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                HStack {
                    Text("Recent sessions").font(Theme.Text.heading)
                    Spacer()
                    Text("\(store.snapshot.sessions.count)")
                        .font(Theme.Text.captionTight.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                if store.snapshot.sessions.isEmpty {
                    EmptyStateView(
                        symbolName: "bubble.left.and.bubble.right",
                        title: "No sessions found",
                        message: "Sessions appear here once an agent CLI has written a transcript on this Mac."
                    )
                } else {
                    ForEach(store.snapshot.sessions.prefix(6)) { session in
                        sessionRow(session)
                    }
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
        .accessibilityLabel("\(session.title), last active \(time) \(store.location.inlinePhrase)")
    }
}
