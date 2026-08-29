import Foundation

// MARK: - Source of truth for "where am I"

/// Where the display timezone comes from.
///
/// Deliberately only two cases. There is no GPS case: the app never links
/// CoreLocation, so it cannot ask for precise location even by accident.
public enum TimeZoneSource: Equatable, Sendable {
    /// Follow the system timezone, and keep following it when the Mac changes zones.
    case system
    /// A timezone the user picked by hand, with an optional label they wrote.
    case manual(identifier: String, label: String?)

    public var isManual: Bool {
        if case .manual = self { return true }
        return false
    }

    public var manualIdentifier: String? {
        if case .manual(let id, _) = self { return id }
        return nil
    }

    public var manualLabel: String? {
        if case .manual(_, let label) = self { return label }
        return nil
    }
}

// MARK: - Resolved context

/// The resolved "where the user is, for display purposes" context.
public struct LocationContext: Equatable, Sendable {
    public var timeZone: TimeZone
    /// Human label derived from the system timezone. Kept for diagnostics.
    public var placeLabel: String
    /// e.g. "India Standard Time".
    public var zoneName: String
    /// e.g. "GMT+5:30".
    public var offsetLabel: String
    public var isOverridden: Bool
    /// Region from the user's system locale settings. Never from GPS.
    public var regionCode: String?
    /// True when location-aware display is switched off in privacy settings.
    public var isDisabled: Bool

    public init(
        timeZone: TimeZone,
        placeLabel: String,
        zoneName: String,
        offsetLabel: String,
        isOverridden: Bool,
        regionCode: String?,
        isDisabled: Bool
    ) {
        self.timeZone = timeZone
        self.placeLabel = placeLabel
        self.zoneName = zoneName
        self.offsetLabel = offsetLabel
        self.isOverridden = isOverridden
        self.regionCode = regionCode
        self.isDisabled = isDisabled
    }

    /// Normal UI never exposes city aliases; macOS is the authority.
    public var inlinePhrase: String { isOverridden ? "\(placeLabel) time" : "system time" }

    /// One-line description for the location row in preferences.
    public var summary: String {
        if isDisabled { return "Location context off · times shown in system timezone" }
        let base = "\(placeLabel) · \(offsetLabel)"
        return isOverridden ? "\(base) · set manually" : base
    }
}

// MARK: - Resolver

/// Turns a `TimeZoneSource` plus a privacy switch into a `LocationContext`.
///
/// Pure and synchronous so it can be tested without a running app.
public enum TimeZoneResolver {

    /// Resolve the display context.
    /// - Parameters:
    ///   - source: what the user chose.
    ///   - locationAware: the privacy master switch. When false, the system
    ///     timezone is used and any manual override is ignored (but not erased).
    ///   - systemTimeZone: injected for testing; defaults to the live system zone.
    ///   - locale: injected for testing.
    public static func resolve(
        source: TimeZoneSource,
        locationAware: Bool,
        systemTimeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> LocationContext {
        let overridden = locationAware && source.isManual
        // An override that names a timezone the system does not know (a stale
        // preference, a renamed zone, a hand-edited plist) falls back to system.
        let resolvedZone: TimeZone = {
            guard overridden, let id = source.manualIdentifier, let tz = TimeZone(identifier: id) else {
                return systemTimeZone
            }
            return tz
        }()
        let didFallBack = overridden && TimeZone(identifier: source.manualIdentifier ?? "") == nil

        let custom = overridden && !didFallBack ? source.manualLabel?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let place = (custom?.isEmpty == false ? custom! : placeName(for: resolvedZone, locale: locale))

        return LocationContext(
            timeZone: resolvedZone,
            placeLabel: place,
            zoneName: resolvedZone.localizedName(for: .generic, locale: locale) ?? resolvedZone.identifier,
            offsetLabel: offsetLabel(for: resolvedZone),
            isOverridden: overridden && !didFallBack,
            regionCode: regionCode(from: locale),
            isDisabled: !locationAware
        )
    }

    /// "Asia/Kolkata" -> "Kolkata", "America/Argentina/Buenos_Aires" -> "Buenos Aires".
    public static func placeName(for zone: TimeZone, locale: Locale = .current) -> String {
        if zone.identifier == "UTC" || zone.identifier == "GMT" { return "UTC" }
        let identifier = modernIdentifier(for: zone.identifier)
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// "GMT+5:30" / "GMT-8" / "GMT" — computed rather than parsed out of a name.
    public static func offsetLabel(for zone: TimeZone, at date: Date = Date()) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        if seconds == 0 { return "GMT" }
        let sign = seconds < 0 ? "-" : "+"
        let total = abs(seconds) / 60
        let hours = total / 60
        let minutes = total % 60
        return minutes == 0 ? "GMT\(sign)\(hours)" : String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }

    /// Region comes from system locale settings only. This is a *region* setting
    /// (e.g. "IN"), not a position, and requires no permission of any kind.
    public static func regionCode(from locale: Locale = .current) -> String? {
        if #available(macOS 13, *) { return locale.region?.identifier }
        return nil
    }

    /// Foundation still reports several zones under their pre-rename aliases
    /// (`knownTimeZoneIdentifiers` contains `Asia/Calcutta`, not `Asia/Kolkata`).
    /// Showing a user in India a picker entry called "Calcutta" is wrong, so the
    /// list is modernised for display. Both spellings construct the same zone,
    /// so substituting the modern one is safe everywhere it is stored.
    static let modernIdentifiers: [String: String] = [
        "Asia/Calcutta": "Asia/Kolkata",
        "Asia/Katmandu": "Asia/Kathmandu",
        "Asia/Rangoon": "Asia/Yangon",
        "Asia/Saigon": "Asia/Ho_Chi_Minh",
        "Asia/Thimbu": "Asia/Thimphu",
        "Asia/Ujung_Pandang": "Asia/Makassar",
        "Europe/Kiev": "Europe/Kyiv",
        "America/Godthab": "America/Nuuk",
        "Pacific/Ponape": "Pacific/Pohnpei",
        "Pacific/Truk": "Pacific/Chuuk",
        "Atlantic/Faeroe": "Atlantic/Faroe"
    ]

    /// The name this zone should be listed and displayed under.
    public static func modernIdentifier(for identifier: String) -> String {
        guard let modern = modernIdentifiers[identifier], TimeZone(identifier: modern) != nil else {
            return identifier
        }
        return modern
    }

    /// Timezone identifiers offered in the manual picker.
    public static func selectableIdentifiers() -> [String] {
        var seen = Set<String>()
        return TimeZone.knownTimeZoneIdentifiers
            .filter { $0.contains("/") || $0 == "UTC" }
            .map(modernIdentifier(for:))
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    /// Filter for the picker's search field. Matches the identifier and the
    /// city name, so "buenos aires" finds `America/Argentina/Buenos_Aires`.
    public static func search(_ query: String, in identifiers: [String]) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return identifiers }
        let needle = trimmed.lowercased().replacingOccurrences(of: " ", with: "_")
        return identifiers.filter { identifier in
            if identifier.lowercased().contains(needle) { return true }
            // Also match the alias, so someone typing "Calcutta" still lands on Kolkata.
            return modernIdentifiers.first { $0.value == identifier }?.key.lowercased().contains(needle) ?? false
        }
    }
}

// MARK: - Dual-time reset formatting

/// A reset instant rendered for a specific display timezone, plus the
/// provider's own timezone when that differs.
public struct ResetDescription: Equatable, Sendable {
    /// e.g. "Resets 4:20 PM"
    public var primary: String
    /// e.g. "10:50 AM UTC" — nil when the provider resets in the same offset.
    public var providerTime: String?
    /// e.g. "in 2h 18m"
    public var countdown: String
    /// Seconds remaining; negative once passed.
    public var remaining: TimeInterval
    /// Spoken form for VoiceOver, which must not rely on layout to be understood.
    public var accessibleDescription: String

    public init(primary: String, providerTime: String?, countdown: String, remaining: TimeInterval, accessibleDescription: String) {
        self.primary = primary
        self.providerTime = providerTime
        self.countdown = countdown
        self.remaining = remaining
        self.accessibleDescription = accessibleDescription
    }
}

public enum ResetFormatter {

    /// Describe a reset instant in the user's display timezone, adding the
    /// provider's timezone only when it would actually tell the user something
    /// new (i.e. the two zones are at different UTC offsets at that instant).
    public static func describe(
        reset: Date,
        now: Date,
        display: LocationContext,
        providerZone: TimeZone,
        locale: Locale = .current
    ) -> ResetDescription {
        let remaining = reset.timeIntervalSince(now)
        let displayZone = display.timeZone
        let sameOffset = displayZone.secondsFromGMT(for: reset) == providerZone.secondsFromGMT(for: reset)

        let primaryTime = Formatters.time(reset, in: displayZone, locale: locale)
        let dayQualifier = Formatters.dayQualifier(for: reset, now: now, in: displayZone, locale: locale)
        let primary = dayQualifier.map { "\(primaryTime) \($0)" } ?? primaryTime

        let providerTime: String? = sameOffset ? nil : {
            let t = Formatters.time(reset, in: providerZone, locale: locale)
            return "\(t) \(TimeZoneResolver.offsetLabel(for: providerZone, at: reset))"
        }()

        let countdown = Formatters.countdown(remaining)

        var spoken = remaining >= 0
            ? "Resets in \(Formatters.spokenDuration(remaining)), at \(primary) \(display.inlinePhrase)"
            : "Reset window has passed"
        if let providerTime { spoken += ", which is \(providerTime) for the provider" }

        return ResetDescription(
            primary: primary,
            providerTime: providerTime,
            countdown: countdown,
            remaining: remaining,
            accessibleDescription: spoken
        )
    }

    /// "Safe to continue" guidance: is there enough of the window left, at the
    /// current burn rate, to keep working without hitting the limit?
    ///
    /// - Returns: nil when there is not enough information to say anything.
    public static func continuationGuidance(
        usedFraction: Double?,
        remaining: TimeInterval,
        elapsedFraction: Double?,
        thresholds: AlertThresholds
    ) -> ContinuationGuidance? {
        guard let usedFraction else { return nil }
        guard remaining > 0 else {
            return ContinuationGuidance(verdict: .safe, headline: "Window has reset", detail: "A fresh window is available.")
        }
        // Without knowing how far through the window we are, fall back to level only.
        guard let elapsedFraction, elapsedFraction > 0.02 else {
            let severity = Severity.forFraction(usedFraction, thresholds: thresholds)
            switch severity {
            case .nominal:
                return ContinuationGuidance(verdict: .safe, headline: "Safe to continue", detail: "Well inside the limit for this window.")
            case .watch:
                return ContinuationGuidance(verdict: .caution, headline: "Pace yourself", detail: "Past the halfway mark with time left in the window.")
            case .critical:
                return ContinuationGuidance(verdict: .hold, headline: "Close to the limit", detail: "Consider pausing until the window resets.")
            }
        }
        // Projected consumption if the current pace holds to the end of the window.
        let projected = usedFraction / elapsedFraction
        if projected >= 1.0 {
            return ContinuationGuidance(
                verdict: .hold,
                headline: "On pace to hit the limit",
                detail: "At this pace you would reach the limit before the window resets."
            )
        }
        if projected >= thresholds.critical {
            return ContinuationGuidance(
                verdict: .caution,
                headline: "Tight for this window",
                detail: "This pace lands around \(Formatters.percent(projected)) of the limit by reset."
            )
        }
        return ContinuationGuidance(
            verdict: .safe,
            headline: "Safe to continue",
            detail: "This pace lands around \(Formatters.percent(projected)) of the limit by reset."
        )
    }
}

public struct ContinuationGuidance: Equatable, Sendable {
    public enum Verdict: Sendable { case safe, caution, hold

        public var symbolName: String {
            switch self {
            case .safe: return "checkmark.circle.fill"
            case .caution: return "exclamationmark.circle.fill"
            case .hold: return "hand.raised.fill"
            }
        }

        public var severity: Severity {
            switch self {
            case .safe: return .nominal
            case .caution: return .watch
            case .hold: return .critical
            }
        }
    }

    public var verdict: Verdict
    public var headline: String
    public var detail: String

    public init(verdict: Verdict, headline: String, detail: String) {
        self.verdict = verdict
        self.headline = headline
        self.detail = detail
    }
}
