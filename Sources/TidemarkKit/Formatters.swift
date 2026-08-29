import Foundation

/// Small, allocation-conscious formatting helpers. `DateFormatter` instances
/// are cached because the panel re-renders on a timer.
public enum Formatters {

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var timeFormatters: [String: DateFormatter] = [:]

    private static func timeFormatter(for zone: TimeZone, locale: Locale) -> DateFormatter {
        let key = "\(zone.identifier)|\(locale.identifier)"
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = timeFormatters[key] { return cached }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate("j:mm")
        timeFormatters[key] = f
        return f
    }

    /// Locale-correct clock time (12h or 24h according to system settings).
    public static func time(_ date: Date, in zone: TimeZone, locale: Locale = .current) -> String {
        timeFormatter(for: zone, locale: locale).string(from: date)
    }

    public static func shortTime(_ date: Date, locale: Locale = .current) -> String {
        time(date, in: .current, locale: locale)
    }

    /// "tomorrow" / "Thu" / nil when the reset falls on today in `zone`.
    public static func dayQualifier(for date: Date, now: Date, in zone: TimeZone, locale: Locale = .current) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        cal.locale = locale
        if cal.isDate(date, inSameDayAs: now) { return nil }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        if days == 1 { return "tomorrow" }
        if days == -1 { return "yesterday" }
        if days > 1 && days < 7 {
            let f = DateFormatter()
            f.locale = locale
            f.timeZone = zone
            f.setLocalizedDateFormatFromTemplate("EEE")
            return f.string(from: date)
        }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }

    /// Compact countdown: "2h 18m", "47m", "< 1m", "—" once elapsed.
    public static func countdown(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "now" }
        let total = Int(interval.rounded())
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "< 1m"
    }

    /// Spoken form for VoiceOver: "2 hours 18 minutes".
    public static func spokenDuration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "less than a minute" }
        let total = Int(interval.rounded())
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) day\(days == 1 ? "" : "s")") }
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 && days == 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        return parts.isEmpty ? "less than a minute" : parts.joined(separator: " ")
    }

    /// "3 minutes" / "2 hours" / "4 days" — coarse, for staleness copy.
    public static func approximateDuration(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        if total < 90 { return "a moment" }
        if total < 5400 { return "\(max(1, total / 60)) minutes" }
        if total < 172_800 { return "\(total / 3600) hours" }
        return "\(total / 86_400) days"
    }

    /// Relative wording for "last updated": "just now", "3m ago", "yesterday".
    public static func relativeUpdated(_ date: Date, now: Date = Date()) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 45 { return "just now" }
        if delta < 3600 { return "\(Int(delta / 60))m ago" }
        if delta < 86_400 { return "\(Int(delta / 3600))h ago" }
        return "\(Int(delta / 86_400))d ago"
    }

    /// Whole-percent string from a 0...1 fraction.
    public static func percent(_ fraction: Double) -> String {
        "\(Int((min(1.5, max(0, fraction)) * 100).rounded()))%"
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    /// Cost estimates are always in the provider's billing currency (USD), not
    /// the user's local currency — converting would imply a rate we do not have.
    public static func currency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    /// "68k" / "1.2M" for token counts.
    public static func compactCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return "\(value / 1_000)k" }
        return "\(value)"
    }
}
