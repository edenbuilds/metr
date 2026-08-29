import Foundation

/// A short, plain-language observation about how the week has gone.
public struct Insight: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbolName: String
    public let title: String
    public let detail: String

    public init(id: String, symbolName: String, title: String, detail: String) {
        self.id = id
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
    }
}

/// Burn rate over a window, with the assumption that produced it spelled out.
public struct BurnRate: Equatable, Sendable {
    /// Fraction of the limit consumed per hour.
    public var fractionPerHour: Double
    /// Cost per hour in the provider's billing currency.
    public var costPerHour: Double?
    /// The sentence shown under the number, e.g. "from 42 min elapsed".
    public var assumption: String

    public init(fractionPerHour: Double, costPerHour: Double?, assumption: String) {
        self.fractionPerHour = fractionPerHour
        self.costPerHour = costPerHour
        self.assumption = assumption
    }
}

public enum InsightEngine {

    /// Burn rate for one provider, derived from how much of the window has
    /// elapsed. Returns nil when the window's elapsed fraction is unknown or so
    /// small that the rate would be meaningless noise.
    public static func burnRate(for provider: ProviderSnapshot, now: Date) -> BurnRate? {
        guard let used = provider.usedFraction,
              let elapsedFraction = provider.window.elapsedFraction(now: now),
              case .rolling(let hours) = provider.window.cadence,
              elapsedFraction > 0.05 else { return nil }
        let elapsedHours = elapsedFraction * Double(hours)
        guard elapsedHours > 0.1 else { return nil }
        let perHour = used / elapsedHours
        let costPerHour = provider.estimatedCost.map { $0 / max(elapsedHours, 0.1) }
        let minutes = Int((elapsedHours * 60).rounded())
        return BurnRate(
            fractionPerHour: perHour,
            costPerHour: costPerHour,
            assumption: "From \(Formatters.percent(used)) used over \(minutes) min of a \(hours)-hour window."
        )
    }

    /// The hour-of-day, in `zone`, when sessions most often start.
    /// Returns nil below `minimumSamples`, because a "peak" from three data
    /// points is a decorative metric, not a useful one.
    public static func peakHour(
        sessions: [SessionRecord],
        zone: TimeZone,
        minimumSamples: Int = 8,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Int? {
        guard sessions.count >= minimumSamples else { return nil }
        var cal = calendar
        cal.timeZone = zone
        var buckets = [Int](repeating: 0, count: 24)
        for session in sessions {
            buckets[cal.component(.hour, from: session.lastActive)] += 1
        }
        guard let best = buckets.indices.max(by: { buckets[$0] < buckets[$1] }), buckets[best] > 0 else { return nil }
        return best
    }

    /// Human range around the peak, e.g. "2–4 PM" or "14–16" depending on locale.
    public static func peakWindowLabel(hour: Int, zone: TimeZone, locale: Locale = .current) -> String {
        // These are wall-clock labels rather than instants, so build them from a
        // fixed reference day in UTC and format in UTC. Using `zone` here would
        // shift the label away from the hour we were asked to describe.
        var cal = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        cal.timeZone = utc
        var comps = DateComponents()
        comps.year = 2001; comps.month = 1; comps.day = 1; comps.minute = 0

        let f = DateFormatter()
        f.locale = locale
        f.timeZone = utc
        f.setLocalizedDateFormatFromTemplate("j")

        comps.hour = hour
        let startDate = cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
        comps.hour = (hour + 2) % 24
        let endDate = cal.date(from: comps) ?? startDate

        return "\(f.string(from: startDate))–\(f.string(from: endDate))"
    }

    /// Build the Insights list. Every entry is derived from measured counts;
    /// none of them exist purely to fill space.
    public static func insights(
        activity: [DailyActivity],
        sessions: [SessionRecord],
        providers: [ProviderSnapshot],
        location: LocationContext,
        now: Date
    ) -> [Insight] {
        var results: [Insight] = []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = location.timeZone

        // Peak period, expressed in the display timezone so it stays correct
        // when the user travels or overrides their location.
        if let hour = peakHour(sessions: sessions, zone: location.timeZone) {
            let suffix = location.isOverridden ? " (\(location.inlinePhrase))" : ""
            results.append(Insight(
                id: "peak",
                symbolName: "clock.arrow.circlepath",
                title: "Busiest around \(peakWindowLabel(hour: hour, zone: location.timeZone))\(suffix)",
                detail: "Based on when your \(sessions.count) most recent sessions were last active."
            ))
        }

        // Week-over-week pacing from measured message counts.
        let recent = activity.sorted { $0.date < $1.date }
        if recent.count >= 8 {
            let lastSeven = recent.suffix(7)
            let priorSeven = recent.dropLast(7).suffix(7)
            let a = lastSeven.reduce(0) { $0 + $1.messageCount }
            let b = priorSeven.reduce(0) { $0 + $1.messageCount }
            if b > 0 {
                let delta = (Double(a) - Double(b)) / Double(b)
                let direction = delta >= 0 ? "up" : "down"
                results.append(Insight(
                    id: "pacing",
                    symbolName: delta >= 0 ? "arrow.up.right" : "arrow.down.right",
                    title: "Last 7 days \(direction) \(Formatters.percent(abs(delta)))",
                    detail: "\(a) messages this stretch versus \(b) in the previous seven days."
                ))
            }
        }

        // Quietest weekday — only when there is enough of a spread to matter.
        if recent.count >= 10 {
            var byWeekday: [Int: (total: Int, days: Int)] = [:]
            for day in recent {
                let wd = cal.component(.weekday, from: day.date)
                var entry = byWeekday[wd] ?? (0, 0)
                entry.total += day.messageCount
                entry.days += 1
                byWeekday[wd] = entry
            }
            let averages = byWeekday.mapValues { Double($0.total) / Double(max(1, $0.days)) }
            if let busiest = averages.max(by: { $0.value < $1.value }),
               let quietest = averages.min(by: { $0.value < $1.value }),
               busiest.value > quietest.value * 1.5 {
                let f = DateFormatter()
                f.locale = .current
                f.timeZone = location.timeZone
                results.append(Insight(
                    id: "weekday",
                    symbolName: "calendar",
                    title: "\(f.weekdaySymbols[busiest.key - 1]) is your heaviest day",
                    detail: "Averaging \(Int(busiest.value)) messages, against \(Int(quietest.value)) on \(f.weekdaySymbols[quietest.key - 1])."
                ))
            }
        }

        // Burn rate for the provider currently under most pressure.
        if let hottest = providers.filter({ $0.usedFraction != nil }).max(by: { ($0.usedFraction ?? 0) < ($1.usedFraction ?? 0) }),
           let rate = burnRate(for: hottest, now: now) {
            results.append(Insight(
                id: "burn",
                symbolName: "flame",
                title: "\(hottest.identity.name) burning \(Formatters.percent(rate.fractionPerHour)) of its limit per hour",
                detail: rate.assumption
            ))
        }

        return results
    }
}
