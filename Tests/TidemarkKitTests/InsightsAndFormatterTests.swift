import XCTest
@testable import TidemarkKit

final class InsightsAndFormatterTests: XCTestCase {

    // MARK: Formatters

    func testCountdownFormatting() {
        XCTAssertEqual(Formatters.countdown(2 * 3600 + 18 * 60), "2h 18m")
        XCTAssertEqual(Formatters.countdown(47 * 60), "47m")
        XCTAssertEqual(Formatters.countdown(30), "< 1m")
        XCTAssertEqual(Formatters.countdown(-5), "now")
        XCTAssertEqual(Formatters.countdown(3 * 86_400 + 4 * 3600), "3d 4h")
    }

    func testSpokenDurationReadsAsASentenceFragment() {
        XCTAssertEqual(Formatters.spokenDuration(2 * 3600 + 18 * 60), "2 hours 18 minutes")
        XCTAssertEqual(Formatters.spokenDuration(60), "1 minute")
        XCTAssertEqual(Formatters.spokenDuration(10), "less than a minute")
    }

    func testPercentClampsBelowZero() {
        XCTAssertEqual(Formatters.percent(-1), "0%")
        XCTAssertEqual(Formatters.percent(0.345), "35%")
        XCTAssertEqual(Formatters.percent(1), "100%")
    }

    func testCompactCount() {
        XCTAssertEqual(Formatters.compactCount(950), "950")
        XCTAssertEqual(Formatters.compactCount(68_000), "68k")
        XCTAssertEqual(Formatters.compactCount(1_500_000), "1.5M")
    }

    func testRelativeUpdatedWording() {
        let now = Fixture.date(2026, 8, 30, 12, 0)
        XCTAssertEqual(Formatters.relativeUpdated(now.addingTimeInterval(-10), now: now), "just now")
        XCTAssertEqual(Formatters.relativeUpdated(now.addingTimeInterval(-600), now: now), "10m ago")
        XCTAssertEqual(Formatters.relativeUpdated(now.addingTimeInterval(-7200), now: now), "2h ago")
    }

    func testTimeFormattingRespectsTheRequestedZone() {
        let instant = Fixture.date(2026, 8, 30, 12, 0)   // noon UTC
        let utc = Formatters.time(instant, in: Fixture.utc, locale: Locale(identifier: "en_US"))
        let kolkata = Formatters.time(instant, in: Fixture.kolkata, locale: Locale(identifier: "en_US"))
        XCTAssertNotEqual(utc, kolkata)
        XCTAssertTrue(utc.contains("12"))
        XCTAssertTrue(kolkata.contains("5:30"))
    }

    func testDayQualifierIsNilForToday() {
        let now = Fixture.date(2026, 8, 30, 10, 0)
        XCTAssertNil(Formatters.dayQualifier(for: now.addingTimeInterval(3600), now: now, in: Fixture.utc))
        XCTAssertEqual(
            Formatters.dayQualifier(for: Fixture.date(2026, 8, 31, 9, 0), now: now, in: Fixture.utc),
            "tomorrow"
        )
    }

    // MARK: Insights

    func testPeakHourNeedsEnoughSamplesBeforeItClaimsAPattern() {
        let few = (0..<3).map {
            SessionRecord(id: "\($0)", title: "t", providerID: "p",
                          lastActive: Fixture.date(2026, 8, 30, 14, 0))
        }
        XCTAssertNil(InsightEngine.peakHour(sessions: few, zone: Fixture.utc),
                     "Three points is not a pattern")
    }

    func testPeakHourFindsTheBusiestHour() {
        var sessions: [SessionRecord] = []
        for i in 0..<10 {
            sessions.append(SessionRecord(id: "a\(i)", title: "t", providerID: "p",
                                          lastActive: Fixture.date(2026, 8, 30, 15, 0)))
        }
        for i in 0..<2 {
            sessions.append(SessionRecord(id: "b\(i)", title: "t", providerID: "p",
                                          lastActive: Fixture.date(2026, 8, 30, 9, 0)))
        }
        XCTAssertEqual(InsightEngine.peakHour(sessions: sessions, zone: Fixture.utc), 15)
    }

    func testPeakHourMovesWithTheDisplayTimezone() {
        let sessions = (0..<10).map {
            SessionRecord(id: "\($0)", title: "t", providerID: "p",
                          lastActive: Fixture.date(2026, 8, 30, 12, 0))   // noon UTC
        }
        XCTAssertEqual(InsightEngine.peakHour(sessions: sessions, zone: Fixture.utc), 12)
        XCTAssertEqual(InsightEngine.peakHour(sessions: sessions, zone: Fixture.kolkata), 17,
                       "Noon UTC is 17:30 in Kolkata, so the peak hour is 17 there")
    }

    func testBurnRateIsNilTooEarlyInAWindow() {
        let now = Fixture.date(2026, 8, 30, 12, 0)
        var provider = Fixture.provider(
            fraction: 0.1,
            window: UsageWindow(cadence: .rolling(hours: 5), windowStart: now.addingTimeInterval(-60), timeZone: Fixture.utc)
        )
        provider.estimatedCost = 1
        XCTAssertNil(InsightEngine.burnRate(for: provider, now: now),
                     "A rate from one minute of data would be noise")
    }

    func testBurnRateComputesAndStatesItsAssumption() {
        let now = Fixture.date(2026, 8, 30, 12, 0)
        // Half the 4-hour window gone (2h), 50% used -> 25% per hour.
        let provider = Fixture.provider(
            fraction: 0.5,
            window: UsageWindow(cadence: .rolling(hours: 4), windowStart: now.addingTimeInterval(-2 * 3600), timeZone: Fixture.utc)
        )
        let rate = InsightEngine.burnRate(for: provider, now: now)
        XCTAssertEqual(rate?.fractionPerHour ?? 0, 0.25, accuracy: 0.01)
        XCTAssertFalse(rate?.assumption.isEmpty ?? true, "A rate without its assumption is not transparent")
    }

    func testInsightsStayEmptyWithoutEnoughInput() {
        let context = TimeZoneResolver.resolve(source: .system, locationAware: true, systemTimeZone: Fixture.utc)
        let insights = InsightEngine.insights(
            activity: [], sessions: [], providers: [], location: context, now: Date()
        )
        XCTAssertTrue(insights.isEmpty, "An empty panel beats an invented observation")
    }

    func testInsightsAppearOnceThereIsRealHistory() async {
        let now = Fixture.date(2026, 8, 30, 12, 0)
        let snapshot = await MockUsageDataSource(scenario: .healthy).fetch(now: now)
        let context = TimeZoneResolver.resolve(source: .system, locationAware: true, systemTimeZone: Fixture.utc)
        let insights = InsightEngine.insights(
            activity: snapshot.activity, sessions: snapshot.sessions,
            providers: snapshot.providers, location: context, now: now
        )
        XCTAssertFalse(insights.isEmpty)
        for insight in insights {
            XCTAssertFalse(insight.title.isEmpty)
            XCTAssertFalse(insight.detail.isEmpty)
        }
    }
}
