import Foundation

// MARK: - Severity

/// How much attention a value deserves. Never communicated by colour alone:
/// every severity carries a symbol and a word (see `symbolName` / `label`).
public enum Severity: Int, Comparable, Codable, Sendable {
    case nominal = 0
    case watch = 1
    case critical = 2

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .nominal: return "Clear"
        case .watch: return "Watch"
        case .critical: return "Near limit"
        }
    }

    public var symbolName: String {
        switch self {
        case .nominal: return "checkmark.circle.fill"
        case .watch: return "exclamationmark.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    /// Classify a 0...1 fraction against the user's thresholds.
    public static func forFraction(_ fraction: Double, thresholds: AlertThresholds) -> Severity {
        if fraction >= thresholds.critical { return .critical }
        if fraction >= thresholds.watch { return .watch }
        return .nominal
    }
}

// MARK: - Data state

/// The connection/freshness state of a provider's data. Modelled explicitly so
/// the UI always has something honest to say instead of rendering stale numbers
/// as if they were live.
public enum DataState: Equatable, Sendable {
    case loading
    case live(fetched: Date)
    case stale(fetched: Date, age: TimeInterval)
    case offline(lastKnown: Date?)
    case authenticationRequired
    case unavailable(reason: String)

    public var label: String {
        switch self {
        case .loading: return "Checking"
        case .live: return "Live"
        case .stale: return "Stale"
        case .offline: return "Offline"
        case .authenticationRequired: return "Sign in needed"
        case .unavailable: return "Unavailable"
        }
    }

    public var symbolName: String {
        switch self {
        case .loading: return "arrow.triangle.2.circlepath"
        case .live: return "dot.radiowaves.up.forward"
        case .stale: return "clock.badge.exclamationmark"
        case .offline: return "wifi.slash"
        case .authenticationRequired: return "lock"
        case .unavailable: return "questionmark.circle"
        }
    }

    /// True when the numbers attached to this state can be trusted as current.
    public var isTrustworthy: Bool {
        if case .live = self { return true }
        return false
    }

    /// True when there is no usable number at all and the UI must show an empty state.
    public var hasNoData: Bool {
        switch self {
        case .authenticationRequired, .unavailable, .loading: return true
        case .offline(let lastKnown): return lastKnown == nil
        case .live, .stale: return false
        }
    }

    public var severity: Severity {
        switch self {
        case .live, .loading: return .nominal
        case .stale, .offline: return .watch
        case .authenticationRequired, .unavailable: return .watch
        }
    }

    /// Short sentence explaining the state, used in empty/error surfaces.
    public var explanation: String {
        switch self {
        case .loading: return "Reading the latest numbers."
        case .live: return "Numbers are current."
        case .stale(_, let age):
            return "Last successful read was \(Formatters.approximateDuration(age)) ago."
        case .offline(let lastKnown):
            guard let lastKnown else { return "No network, and nothing cached yet." }
            return "No network. Showing the last read from \(Formatters.shortTime(lastKnown))."
        case .authenticationRequired: return "This provider needs credentials before it can report usage."
        case .unavailable(let reason): return reason
        }
    }
}

// MARK: - Confidence

/// Whether a number was measured or inferred. Surfaced in the UI so estimates
/// are never mistaken for provider-reported truth.
public enum Confidence: String, Codable, Sendable {
    /// Read directly from a provider or from a file the provider itself wrote.
    case measured
    /// Derived from measured inputs plus a stated assumption.
    case estimated

    public var label: String {
        switch self {
        case .measured: return "Measured"
        case .estimated: return "Estimated"
        }
    }
}

// MARK: - Reset schedule

/// How a provider's usage window rolls over.
public enum ResetCadence: Equatable, Sendable {
    /// A window that begins when you first use it and expires `hours` later.
    case rolling(hours: Int)
    /// Resets every day at a wall-clock time in the provider's timezone.
    case dailyAt(hour: Int, minute: Int)
    /// Resets weekly. `weekday` uses Foundation's 1 = Sunday convention.
    case weeklyOn(weekday: Int, hour: Int, minute: Int)
    /// Resets on a day-of-month (clamped to the month's length).
    case monthlyOn(day: Int, hour: Int, minute: Int)

    public var label: String {
        switch self {
        case .rolling(let hours): return "\(hours)-hour rolling window"
        case .dailyAt: return "Daily window"
        case .weeklyOn: return "Weekly window"
        case .monthlyOn: return "Monthly window"
        }
    }
}

/// A usage window belonging to a provider, including the timezone the provider
/// actually resets in. Keeping the provider timezone separate from the user's
/// display timezone is what makes dual-time reset labels possible.
public struct UsageWindow: Equatable, Sendable {
    public var cadence: ResetCadence
    /// For `.rolling` cadences: when the current window opened.
    public var windowStart: Date?
    /// The timezone the provider's schedule is defined in.
    public var timeZone: TimeZone

    public init(cadence: ResetCadence, windowStart: Date? = nil, timeZone: TimeZone = TimeZone(identifier: "UTC") ?? .current) {
        self.cadence = cadence
        self.windowStart = windowStart
        self.timeZone = timeZone
    }

    /// The next instant this window resets, at or after `now`.
    ///
    /// All wall-clock cadences are resolved in `timeZone`, so a provider that
    /// resets "midnight UTC" keeps resetting at midnight UTC no matter where
    /// the user is or which timezone they have chosen to display.
    public func nextReset(after now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        var cal = calendar
        cal.timeZone = timeZone

        switch cadence {
        case .rolling(let hours):
            guard let start = windowStart else {
                return now.addingTimeInterval(TimeInterval(hours) * 3600)
            }
            let length = TimeInterval(hours) * 3600
            guard length > 0 else { return now }
            // Advance whole windows until we land strictly after `now`.
            let elapsed = now.timeIntervalSince(start)
            let completed = max(0, floor(elapsed / length))
            var reset = start.addingTimeInterval((completed + 1) * length)
            if reset <= now { reset = reset.addingTimeInterval(length) }
            return reset

        case .dailyAt(let hour, let minute):
            return Self.nextWallClock(after: now, calendar: cal) { comps in
                comps.hour = hour; comps.minute = minute; comps.second = 0
            } advanceBy: { date in cal.date(byAdding: .day, value: 1, to: date) }

        case .weeklyOn(let weekday, let hour, let minute):
            var comps = DateComponents()
            comps.weekday = weekday
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            return cal.nextDate(after: now, matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents)
                ?? now.addingTimeInterval(7 * 86_400)

        case .monthlyOn(let day, let hour, let minute):
            var cursor = now
            for _ in 0..<14 {
                guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: cursor)),
                      let range = cal.range(of: .day, in: .month, for: monthStart) else { break }
                var comps = cal.dateComponents([.year, .month], from: monthStart)
                comps.day = min(day, range.count)
                comps.hour = hour
                comps.minute = minute
                comps.second = 0
                if let candidate = cal.date(from: comps), candidate > now { return candidate }
                guard let next = cal.date(byAdding: .month, value: 1, to: monthStart) else { break }
                cursor = next
            }
            return now.addingTimeInterval(30 * 86_400)
        }
    }

    /// Shared "next matching wall-clock time" walk, used by the daily cadence.
    private static func nextWallClock(
        after now: Date,
        calendar: Calendar,
        set: (inout DateComponents) -> Void,
        advanceBy: (Date) -> Date?
    ) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        set(&comps)
        guard var candidate = calendar.date(from: comps) else { return now }
        if candidate <= now, let advanced = advanceBy(candidate) { candidate = advanced }
        return candidate
    }

    /// How far through the window we are, 0...1, when that is knowable.
    public func elapsedFraction(now: Date) -> Double? {
        guard case .rolling(let hours) = cadence, let start = windowStart else { return nil }
        let length = TimeInterval(hours) * 3600
        guard length > 0 else { return nil }
        let elapsed = now.timeIntervalSince(start).truncatingRemainder(dividingBy: length)
        return min(1, max(0, elapsed / length))
    }
}

// MARK: - Provider snapshot

public struct ProviderIdentity: Equatable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    /// Hue used only for identity, never as the sole carrier of status.
    public let tintName: String

    public init(id: String, name: String, tintName: String) {
        self.id = id
        self.name = name
        self.tintName = tintName
    }
}

/// One provider's current picture. This is the single unit the UI renders.
public struct ProviderSnapshot: Identifiable, Equatable, Sendable {
    public var identity: ProviderIdentity
    public var model: String?
    public var state: DataState
    /// 0...1 of the plan limit consumed in the current window. Nil when unknown.
    public var usedFraction: Double?
    public var usedLabel: String?
    public var window: UsageWindow
    /// Tokens in the active session's context, and the model's budget.
    public var contextUsed: Int?
    public var contextBudget: Int?
    /// Cost estimate for the current day, and how it was arrived at.
    public var estimatedCost: Double?
    public var costAssumption: String?
    public var confidence: Confidence
    /// Where the numbers came from, shown verbatim in the UI.
    public var sourceDescription: String

    public var id: String { identity.id }

    public init(
        identity: ProviderIdentity,
        model: String? = nil,
        state: DataState,
        usedFraction: Double? = nil,
        usedLabel: String? = nil,
        window: UsageWindow,
        contextUsed: Int? = nil,
        contextBudget: Int? = nil,
        estimatedCost: Double? = nil,
        costAssumption: String? = nil,
        confidence: Confidence = .estimated,
        sourceDescription: String
    ) {
        self.identity = identity
        self.model = model
        self.state = state
        self.usedFraction = usedFraction
        self.usedLabel = usedLabel
        self.window = window
        self.contextUsed = contextUsed
        self.contextBudget = contextBudget
        self.estimatedCost = estimatedCost
        self.costAssumption = costAssumption
        self.confidence = confidence
        self.sourceDescription = sourceDescription
    }

    public func severity(thresholds: AlertThresholds) -> Severity {
        guard let usedFraction, !state.hasNoData else { return state.severity }
        return max(Severity.forFraction(usedFraction, thresholds: thresholds), state.severity)
    }

    public var contextFraction: Double? {
        guard let contextUsed, let contextBudget, contextBudget > 0 else { return nil }
        return min(1, Double(contextUsed) / Double(contextBudget))
    }
}

// MARK: - Sessions & activity

/// A recent agent session discovered on this machine.
public struct SessionRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let providerID: String
    public let lastActive: Date
    /// Working directory, when the transcript records one.
    public let workingDirectory: String?

    public init(id: String, title: String, providerID: String, lastActive: Date, workingDirectory: String? = nil) {
        self.id = id
        self.title = title
        self.providerID = providerID
        self.lastActive = lastActive
        self.workingDirectory = workingDirectory
    }
}

/// One day of measured activity.
public struct DailyActivity: Identifiable, Equatable, Sendable {
    /// Midnight of the day, in the timezone it was recorded in.
    public let date: Date
    public let messageCount: Int
    public let sessionCount: Int
    public let toolCallCount: Int

    public var id: Date { date }

    public init(date: Date, messageCount: Int, sessionCount: Int, toolCallCount: Int) {
        self.date = date
        self.messageCount = messageCount
        self.sessionCount = sessionCount
        self.toolCallCount = toolCallCount
    }
}

/// Everything one refresh produced.
public struct UsageSnapshot: Equatable, Sendable {
    public var providers: [ProviderSnapshot]
    public var sessions: [SessionRecord]
    public var activity: [DailyActivity]
    public var capturedAt: Date

    public init(providers: [ProviderSnapshot], sessions: [SessionRecord] = [], activity: [DailyActivity] = [], capturedAt: Date) {
        self.providers = providers
        self.sessions = sessions
        self.activity = activity
        self.capturedAt = capturedAt
    }

    public static let empty = UsageSnapshot(providers: [], capturedAt: .distantPast)
}
