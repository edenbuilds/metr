import XCTest
@testable import MetrKit

final class ResetScheduleTests: XCTestCase {

    // MARK: Rolling

    func testRollingWindowResetsOneLengthAfterStart() {
        let start = Fixture.date(2026, 8, 30, 10, 0)
        let window = UsageWindow(cadence: .rolling(hours: 5), windowStart: start, timeZone: Fixture.utc)
        let now = start.addingTimeInterval(2 * 3600)
        XCTAssertEqual(window.nextReset(after: now), start.addingTimeInterval(5 * 3600))
    }

    func testRollingWindowRollsForwardAcrossManyElapsedWindows() {
        let start = Fixture.date(2026, 8, 30, 10, 0)
        let window = UsageWindow(cadence: .rolling(hours: 5), windowStart: start, timeZone: Fixture.utc)
        // 12 hours later is two full windows plus two hours.
        let now = start.addingTimeInterval(12 * 3600)
        XCTAssertEqual(window.nextReset(after: now), start.addingTimeInterval(15 * 3600))
    }

    func testRollingResetIsAlwaysStrictlyInTheFuture() {
        let start = Fixture.date(2026, 8, 30, 10, 0)
        let window = UsageWindow(cadence: .rolling(hours: 5), windowStart: start, timeZone: Fixture.utc)
        // Exactly on a boundary must roll to the next window, not return "now".
        let now = start.addingTimeInterval(5 * 3600)
        XCTAssertGreaterThan(window.nextReset(after: now), now)
        XCTAssertEqual(window.nextReset(after: now), start.addingTimeInterval(10 * 3600))
    }

    func testRollingWithoutStartFallsBackToFullWindowFromNow() {
        let window = UsageWindow(cadence: .rolling(hours: 5), windowStart: nil, timeZone: Fixture.utc)
        let now = Fixture.date(2026, 8, 30, 10, 0)
        XCTAssertEqual(window.nextReset(after: now), now.addingTimeInterval(5 * 3600))
    }

    func testElapsedFractionTracksProgressThroughTheWindow() {
        let start = Fixture.date(2026, 8, 30, 10, 0)
        let window = UsageWindow(cadence: .rolling(hours: 4), windowStart: start, timeZone: Fixture.utc)
        let fraction = window.elapsedFraction(now: start.addingTimeInterval(3600))!
        XCTAssertEqual(fraction, 0.25, accuracy: 0.001)
    }

    func testElapsedFractionIsNilForNonRollingCadences() {
        let window = UsageWindow(cadence: .dailyAt(hour: 0, minute: 0), timeZone: Fixture.utc)
        XCTAssertNil(window.elapsedFraction(now: Date()))
    }

    // MARK: Daily, and the provider timezone

    func testDailyResetUsesTheProviderTimezoneNotTheUsers() {
        // Reset is "midnight UTC". Whoever is looking, it stays midnight UTC.
        let window = UsageWindow(cadence: .dailyAt(hour: 0, minute: 0), timeZone: Fixture.utc)
        let now = Fixture.date(2026, 8, 30, 18, 0, in: Fixture.kolkata)
        let reset = window.nextReset(after: now)
        let utcComponents = Fixture.components(reset, in: Fixture.utc)
        XCTAssertEqual(utcComponents.hour, 0)
        XCTAssertEqual(utcComponents.minute, 0)
    }

    func testDailyResetHoldsItsWallClockAcrossDaylightSaving() {
        // 09:00 New York stays 09:00 New York either side of the change, even
        // though the underlying UTC offset moves by an hour.
        let window = UsageWindow(cadence: .dailyAt(hour: 9, minute: 0), timeZone: Fixture.newYork)

        let beforeDST = Fixture.date(2026, 3, 6, 12, 0, in: Fixture.newYork)   // EST
        let afterDST = Fixture.date(2026, 3, 10, 12, 0, in: Fixture.newYork)   // EDT

        let resetBefore = window.nextReset(after: beforeDST)
        let resetAfter = window.nextReset(after: afterDST)

        XCTAssertEqual(Fixture.components(resetBefore, in: Fixture.newYork).hour, 9)
        XCTAssertEqual(Fixture.components(resetAfter, in: Fixture.newYork).hour, 9)
        // The offsets really did differ, so this test proves something.
        XCTAssertNotEqual(
            Fixture.newYork.secondsFromGMT(for: resetBefore),
            Fixture.newYork.secondsFromGMT(for: resetAfter)
        )
    }

    func testDailyResetSkipsToTomorrowWhenTodaysTimeHasPassed() {
        let window = UsageWindow(cadence: .dailyAt(hour: 9, minute: 0), timeZone: Fixture.utc)
        let now = Fixture.date(2026, 8, 30, 14, 0)
        let reset = window.nextReset(after: now)
        XCTAssertEqual(Fixture.components(reset, in: Fixture.utc).day, 31)
        XCTAssertEqual(Fixture.components(reset, in: Fixture.utc).hour, 9)
    }

    // MARK: Weekly / monthly

    func testWeeklyResetLandsOnTheConfiguredWeekday() {
        // weekday 2 == Monday in Foundation's 1-based, Sunday-first numbering.
        let window = UsageWindow(cadence: .weeklyOn(weekday: 2, hour: 0, minute: 0), timeZone: Fixture.utc)
        let now = Fixture.date(2026, 8, 30, 12, 0)   // a Sunday
        let reset = window.nextReset(after: now)
        XCTAssertEqual(Fixture.components(reset, in: Fixture.utc).weekday, 2)
        XCTAssertGreaterThan(reset, now)
    }

    func testMonthlyResetClampsToShortMonths() {
        // Day 31 in February must land on the last day that exists.
        let window = UsageWindow(cadence: .monthlyOn(day: 31, hour: 0, minute: 0), timeZone: Fixture.utc)
        let now = Fixture.date(2026, 2, 10, 12, 0)
        let reset = window.nextReset(after: now)
        let comps = Fixture.components(reset, in: Fixture.utc)
        XCTAssertEqual(comps.month, 2)
        XCTAssertEqual(comps.day, 28)   // 2026 is not a leap year
    }

    func testMonthlyResetRollsToNextMonthOncePassed() {
        let window = UsageWindow(cadence: .monthlyOn(day: 1, hour: 0, minute: 0), timeZone: Fixture.utc)
        let now = Fixture.date(2026, 8, 15, 12, 0)
        let reset = window.nextReset(after: now)
        XCTAssertEqual(Fixture.components(reset, in: Fixture.utc).month, 9)
        XCTAssertEqual(Fixture.components(reset, in: Fixture.utc).day, 1)
    }
}
