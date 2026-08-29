import Foundation
@testable import TidemarkKit

enum Fixture {
    static let utc = TimeZone(identifier: "UTC")!
    static let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    static let newYork = TimeZone(identifier: "America/New_York")!
    static let london = TimeZone(identifier: "Europe/London")!

    /// Build a Date from wall-clock components in a specific zone.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, in zone: TimeZone = utc) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return cal.date(from: comps)!
    }

    /// Read a date back as wall-clock components in a zone.
    static func components(_ date: Date, in zone: TimeZone) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
    }

    /// An isolated UserDefaults suite so tests never touch real preferences.
    static func defaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    static func provider(
        id: String = "test",
        fraction: Double? = 0.5,
        window: UsageWindow = UsageWindow(cadence: .rolling(hours: 5)),
        state: DataState = .live(fetched: Date())
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: ProviderIdentity(id: id, name: id.capitalized, tintName: "indigo"),
            state: state,
            usedFraction: fraction,
            window: window,
            sourceDescription: "test"
        )
    }
}
