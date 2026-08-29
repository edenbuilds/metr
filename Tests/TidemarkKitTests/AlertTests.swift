import XCTest
@testable import TidemarkKit

final class AlertTests: XCTestCase {

    // MARK: Thresholds

    func testThresholdsStayOrderedEvenWhenSetBackwards() {
        let thresholds = AlertThresholds(watch: 0.9, critical: 0.4)
        XCTAssertLessThan(thresholds.watch, thresholds.critical)
    }

    func testThresholdsClampToSaneBounds() {
        let thresholds = AlertThresholds(watch: -5, critical: 99)
        XCTAssertGreaterThanOrEqual(thresholds.watch, 0.05)
        XCTAssertLessThanOrEqual(thresholds.critical, 0.99)
    }

    func testSeverityClassification() {
        let t = AlertThresholds(watch: 0.6, critical: 0.85)
        XCTAssertEqual(Severity.forFraction(0.1, thresholds: t), .nominal)
        XCTAssertEqual(Severity.forFraction(0.6, thresholds: t), .watch)
        XCTAssertEqual(Severity.forFraction(0.99, thresholds: t), .critical)
    }

    // MARK: Quiet hours

    func testQuietHoursWrapAroundMidnight() {
        let quiet = QuietHours(enabled: true, startHour: 22, endHour: 8)
        XCTAssertTrue(quiet.contains(Fixture.date(2026, 8, 30, 23, 0), in: Fixture.utc))
        XCTAssertTrue(quiet.contains(Fixture.date(2026, 8, 30, 3, 0), in: Fixture.utc))
        XCTAssertFalse(quiet.contains(Fixture.date(2026, 8, 30, 12, 0), in: Fixture.utc))
        XCTAssertFalse(quiet.contains(Fixture.date(2026, 8, 30, 8, 0), in: Fixture.utc), "End hour is exclusive")
    }

    func testQuietHoursWithinASingleDay() {
        let quiet = QuietHours(enabled: true, startHour: 9, endHour: 17)
        XCTAssertTrue(quiet.contains(Fixture.date(2026, 8, 30, 12, 0), in: Fixture.utc))
        XCTAssertFalse(quiet.contains(Fixture.date(2026, 8, 30, 20, 0), in: Fixture.utc))
    }

    func testQuietHoursAreEvaluatedInTheDisplayTimezone() {
        // 23:00 in Kolkata is 17:30 UTC. Quiet at home, not quiet in UTC.
        let quiet = QuietHours(enabled: true, startHour: 22, endHour: 8)
        let instant = Fixture.date(2026, 8, 30, 23, 0, in: Fixture.kolkata)
        XCTAssertTrue(quiet.contains(instant, in: Fixture.kolkata))
        XCTAssertFalse(quiet.contains(instant, in: Fixture.utc))
    }

    func testDisabledQuietHoursNeverMatch() {
        let quiet = QuietHours(enabled: false, startHour: 0, endHour: 23)
        XCTAssertFalse(quiet.contains(Fixture.date(2026, 8, 30, 12, 0), in: Fixture.utc))
    }

    // MARK: Alert engine

    func testAlertFiresOnceThenStaysQuiet() {
        let now = Date()
        let providers = [Fixture.provider(id: "a", fraction: 0.9)]
        let quiet = QuietHours(enabled: false)

        let first = AlertEngine.evaluate(
            providers: providers, thresholds: .default, quietHours: quiet,
            displayZone: Fixture.utc, now: now, alreadyRaised: []
        )
        XCTAssertEqual(first.fire.count, 1)
        XCTAssertEqual(first.fire.first?.severity, .critical)

        let second = AlertEngine.evaluate(
            providers: providers, thresholds: .default, quietHours: quiet,
            displayZone: Fixture.utc, now: now, alreadyRaised: first.raised
        )
        XCTAssertTrue(second.fire.isEmpty, "The same condition must not re-alert every refresh")
    }

    func testAlertReArmsAfterRecovery() {
        let now = Date()
        let quiet = QuietHours(enabled: false)
        let hot = AlertEngine.evaluate(
            providers: [Fixture.provider(id: "a", fraction: 0.9)], thresholds: .default,
            quietHours: quiet, displayZone: Fixture.utc, now: now, alreadyRaised: []
        )
        // Window reset; usage drops back to nothing.
        let cooled = AlertEngine.evaluate(
            providers: [Fixture.provider(id: "a", fraction: 0.05)], thresholds: .default,
            quietHours: quiet, displayZone: Fixture.utc, now: now, alreadyRaised: hot.raised
        )
        XCTAssertTrue(cooled.raised.isEmpty, "Recovering clears the latch")

        let hotAgain = AlertEngine.evaluate(
            providers: [Fixture.provider(id: "a", fraction: 0.9)], thresholds: .default,
            quietHours: quiet, displayZone: Fixture.utc, now: now, alreadyRaised: cooled.raised
        )
        XCTAssertEqual(hotAgain.fire.count, 1, "It must be able to warn again next window")
    }

    func testQuietHoursSuppressDeliveryButStillLatch() {
        let now = Fixture.date(2026, 8, 30, 23, 0)
        let quiet = QuietHours(enabled: true, startHour: 22, endHour: 8)
        let result = AlertEngine.evaluate(
            providers: [Fixture.provider(id: "a", fraction: 0.9)], thresholds: .default,
            quietHours: quiet, displayZone: Fixture.utc, now: now, alreadyRaised: []
        )
        XCTAssertTrue(result.fire.isEmpty, "Nothing is delivered during quiet hours")
        XCTAssertFalse(result.raised.isEmpty, "But it is marked, so morning is not an ambush")
    }

    func testProvidersWithoutDataNeverAlert() {
        let provider = Fixture.provider(id: "a", fraction: nil, state: .authenticationRequired)
        let result = AlertEngine.evaluate(
            providers: [provider], thresholds: .default, quietHours: QuietHours(enabled: false),
            displayZone: Fixture.utc, now: Date(), alreadyRaised: []
        )
        XCTAssertTrue(result.fire.isEmpty)
    }

    func testNominalUsageDoesNotAlert() {
        let result = AlertEngine.evaluate(
            providers: [Fixture.provider(id: "a", fraction: 0.1)], thresholds: .default,
            quietHours: QuietHours(enabled: false), displayZone: Fixture.utc, now: Date(), alreadyRaised: []
        )
        XCTAssertTrue(result.fire.isEmpty)
    }

    func testEscalationFromWatchToCriticalFiresASecondAlert() {
        let now = Date()
        let quiet = QuietHours(enabled: false)
        let watch = AlertEngine.evaluate(
            providers: [Fixture.provider(id: "a", fraction: 0.7)], thresholds: .default,
            quietHours: quiet, displayZone: Fixture.utc, now: now, alreadyRaised: []
        )
        XCTAssertEqual(watch.fire.first?.severity, .watch)

        let critical = AlertEngine.evaluate(
            providers: [Fixture.provider(id: "a", fraction: 0.95)], thresholds: .default,
            quietHours: quiet, displayZone: Fixture.utc, now: now, alreadyRaised: watch.raised
        )
        XCTAssertEqual(critical.fire.first?.severity, .critical, "Getting worse deserves a second word")
    }
}
