import Foundation

/// Deterministic synthetic data.
///
/// Deterministic on purpose: the same `now` always yields the same snapshot, so
/// screenshots and tests are reproducible and the UI does not jitter between
/// refreshes for no reason.
public final class MockUsageDataSource: UsageDataSource {

    /// The situation to simulate. Every state the UI must handle has a scenario,
    /// which is how the empty/error surfaces get exercised without unplugging
    /// anything.
    public enum Scenario: String, CaseIterable, Sendable {
        case healthy, approachingLimit, atLimit, mixed, offline, authRequired, stale, noData

        public var title: String {
            switch self {
            case .healthy: return "Healthy"
            case .approachingLimit: return "Approaching limit"
            case .atLimit: return "At limit"
            case .mixed: return "Mixed states"
            case .offline: return "Offline"
            case .authRequired: return "Needs sign-in"
            case .stale: return "Stale data"
            case .noData: return "No data"
            }
        }
    }

    public let kind: DataSourceKind = .mock
    public var scenario: Scenario
    public var provenance: String { "Synthetic data, scenario “\(scenario.title)”. Nothing is read from disk or the network." }

    public init(scenario: Scenario = .healthy) {
        self.scenario = scenario
    }

    public func fetch(now: Date) async -> UsageSnapshot {
        UsageSnapshot(
            providers: providers(now: now),
            sessions: sessions(now: now),
            activity: activity(now: now),
            capturedAt: now
        )
    }

    // MARK: Providers

    private func providers(now: Date) -> [ProviderSnapshot] {
        let claudeWindow = UsageWindow(
            cadence: .rolling(hours: 5),
            windowStart: now.addingTimeInterval(-2.4 * 3600),
            timeZone: TimeZone(identifier: "UTC") ?? .current
        )
        // A weekly window that resets Monday 00:00 UTC — a real dual-timezone case.
        let codexWindow = UsageWindow(
            cadence: .weeklyOn(weekday: 2, hour: 0, minute: 0),
            timeZone: TimeZone(identifier: "UTC") ?? .current
        )

        func snapshot(
            _ identity: ProviderIdentity,
            model: String,
            fraction: Double?,
            window: UsageWindow,
            state: DataState,
            context: (Int, Int)?,
            cost: Double?
        ) -> ProviderSnapshot {
            ProviderSnapshot(
                identity: identity,
                model: model,
                state: state,
                usedFraction: fraction,
                usedLabel: fraction == nil ? nil : "of plan limit",
                window: window,
                contextUsed: context?.0,
                contextBudget: context?.1,
                estimatedCost: cost,
                costAssumption: cost == nil ? nil : "Demo figure. Not derived from real billing.",
                confidence: .estimated,
                sourceDescription: "Demo data"
            )
        }

        let live = DataState.live(fetched: now)

        switch scenario {
        case .healthy:
            return [
                snapshot(KnownProvider.claude, model: "Opus 5", fraction: 0.34, window: claudeWindow, state: live, context: (68_000, 200_000), cost: 1.84),
                snapshot(KnownProvider.codex, model: "GPT-5", fraction: 0.18, window: codexWindow, state: live, context: (24_000, 128_000), cost: 0.42)
            ]
        case .approachingLimit:
            return [
                snapshot(KnownProvider.claude, model: "Opus 5", fraction: 0.72, window: claudeWindow, state: live, context: (151_000, 200_000), cost: 6.10),
                snapshot(KnownProvider.codex, model: "GPT-5", fraction: 0.66, window: codexWindow, state: live, context: (88_000, 128_000), cost: 3.05)
            ]
        case .atLimit:
            return [
                snapshot(KnownProvider.claude, model: "Opus 5", fraction: 0.94, window: claudeWindow, state: live, context: (191_000, 200_000), cost: 11.40),
                snapshot(KnownProvider.codex, model: "GPT-5", fraction: 0.88, window: codexWindow, state: live, context: (119_000, 128_000), cost: 7.75)
            ]
        case .mixed:
            return [
                snapshot(KnownProvider.claude, model: "Opus 5", fraction: 0.88, window: claudeWindow, state: live, context: (176_000, 200_000), cost: 9.20),
                snapshot(KnownProvider.codex, model: "GPT-5", fraction: nil, window: codexWindow, state: .authenticationRequired, context: nil, cost: nil)
            ]
        case .offline:
            let lastKnown = now.addingTimeInterval(-1_500)
            return [
                snapshot(KnownProvider.claude, model: "Opus 5", fraction: 0.41, window: claudeWindow, state: .offline(lastKnown: lastKnown), context: (72_000, 200_000), cost: 2.10),
                snapshot(KnownProvider.codex, model: "GPT-5", fraction: nil, window: codexWindow, state: .offline(lastKnown: nil), context: nil, cost: nil)
            ]
        case .authRequired:
            return KnownProvider.all.map {
                snapshot($0, model: "—", fraction: nil, window: claudeWindow, state: .authenticationRequired, context: nil, cost: nil)
            }
        case .stale:
            let fetched = now.addingTimeInterval(-4 * 3600)
            return [
                snapshot(KnownProvider.claude, model: "Opus 5", fraction: 0.52, window: claudeWindow, state: .stale(fetched: fetched, age: 4 * 3600), context: (96_000, 200_000), cost: 3.30),
                snapshot(KnownProvider.codex, model: "GPT-5", fraction: 0.29, window: codexWindow, state: .stale(fetched: fetched, age: 4 * 3600), context: nil, cost: 0.90)
            ]
        case .noData:
            return []
        }
    }

    // MARK: Sessions & activity

    private func sessions(now: Date) -> [SessionRecord] {
        guard scenario != .noData, scenario != .authRequired else { return [] }
        let titles = [
            "Refine the usage panel", "Fix reset countdown math", "Timezone override review",
            "Panel geometry pass", "Alert threshold tuning", "History chart accessibility",
            "Local adapter provenance", "Quiet hours wraparound", "Edge rail hover states",
            "Preferences layout"
        ]
        // Hours chosen so the peak-hour insight has a real, stable answer.
        let hourOffsets: [Double] = [1, 3, 5, 22, 26, 28, 29, 46, 50, 53]
        return zip(titles, hourOffsets).enumerated().map { index, pair in
            SessionRecord(
                id: "mock-\(index)",
                title: pair.0,
                providerID: index.isMultiple(of: 2) ? KnownProvider.claude.id : KnownProvider.codex.id,
                lastActive: now.addingTimeInterval(-pair.1 * 3600),
                workingDirectory: "~/Projects/tidemark"
            )
        }
    }

    private func activity(now: Date) -> [DailyActivity] {
        guard scenario != .noData else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let counts = [180, 420, 260, 610, 540, 720, 210, 300, 480, 390, 650, 580, 700, 240]
        return counts.enumerated().compactMap { index, count in
            guard let date = cal.date(byAdding: .day, value: -(counts.count - 1 - index), to: cal.startOfDay(for: now)) else { return nil }
            return DailyActivity(
                date: date,
                messageCount: count,
                sessionCount: max(1, count / 90),
                toolCallCount: count / 3
            )
        }
    }
}
