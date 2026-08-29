import Foundation

// MARK: - Thresholds

/// Where "watch" and "near limit" begin, as fractions of the plan limit.
public struct AlertThresholds: Equatable, Codable, Sendable {
    public var watch: Double
    public var critical: Double

    public init(watch: Double = 0.65, critical: Double = 0.85) {
        // Keep the pair ordered and inside 0...1 no matter what is persisted.
        let w = min(max(watch, 0.05), 0.98)
        self.watch = w
        self.critical = min(max(critical, w + 0.01), 0.99)
    }

    public static let `default` = AlertThresholds()
}

// MARK: - Quiet hours

/// A nightly window during which alerts are suppressed. Evaluated in the user's
/// *display* timezone, so travelling with a manual override moves quiet hours
/// with it rather than leaving them on home time.
public struct QuietHours: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var startHour: Int
    public var endHour: Int

    public init(enabled: Bool = true, startHour: Int = 22, endHour: Int = 8) {
        self.enabled = enabled
        self.startHour = min(max(startHour, 0), 23)
        self.endHour = min(max(endHour, 0), 23)
    }

    public static let `default` = QuietHours()

    /// True when `date`, read in `zone`, falls inside the quiet window.
    /// Handles windows that wrap past midnight (the common case).
    public func contains(_ date: Date, in zone: TimeZone, calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        guard enabled else { return false }
        if startHour == endHour { return false }
        var cal = calendar
        cal.timeZone = zone
        let hour = cal.component(.hour, from: date)
        if startHour < endHour { return hour >= startHour && hour < endHour }
        return hour >= startHour || hour < endHour   // wraps midnight
    }

    public var summary: String {
        guard enabled else { return "Off" }
        return String(format: "%02d:00 – %02d:00", startHour, endHour)
    }
}

// MARK: - Alerts

public struct UsageAlert: Identifiable, Equatable, Sendable {
    public let id: String
    public let providerID: String
    public let severity: Severity
    public let title: String
    public let body: String
    public let raisedAt: Date

    public init(id: String, providerID: String, severity: Severity, title: String, body: String, raisedAt: Date) {
        self.id = id
        self.providerID = providerID
        self.severity = severity
        self.title = title
        self.body = body
        self.raisedAt = raisedAt
    }
}

/// Decides which alerts should fire, without any knowledge of how they are
/// delivered. Pure input -> output so the rules are directly testable.
public enum AlertEngine {

    /// - Parameters:
    ///   - alreadyRaised: ids previously delivered, so a provider sitting at 90%
    ///     does not re-alert on every refresh tick.
    /// - Returns: the alerts to deliver now, and the updated raised-id set.
    public static func evaluate(
        providers: [ProviderSnapshot],
        thresholds: AlertThresholds,
        quietHours: QuietHours,
        displayZone: TimeZone,
        now: Date,
        alreadyRaised: Set<String>
    ) -> (fire: [UsageAlert], raised: Set<String>) {
        var raised = alreadyRaised
        var fire: [UsageAlert] = []

        // Ids that are currently "true". Anything not in here has recovered and
        // is cleared so it can alert again later.
        var active: Set<String> = []

        for provider in providers {
            guard let fraction = provider.usedFraction, !provider.state.hasNoData else { continue }
            let severity = Severity.forFraction(fraction, thresholds: thresholds)
            guard severity != .nominal else { continue }
            let id = "\(provider.id)|\(severity.rawValue)"
            active.insert(id)
            guard !raised.contains(id) else { continue }
            raised.insert(id)

            let title = severity == .critical
                ? "\(provider.identity.name) is near its limit"
                : "\(provider.identity.name) crossed \(Formatters.percent(thresholds.watch))"
            let reset = provider.window.nextReset(after: now)
            let body = "\(Formatters.percent(fraction)) used · resets in \(Formatters.countdown(reset.timeIntervalSince(now)))"
            fire.append(UsageAlert(id: id, providerID: provider.id, severity: severity, title: title, body: body, raisedAt: now))
        }

        raised.formIntersection(active)

        // Quiet hours suppress delivery, but the ids stay marked as raised so the
        // user is not ambushed by a backlog the moment quiet hours end.
        if quietHours.contains(now, in: displayZone) { fire = [] }

        return (fire, raised)
    }
}
