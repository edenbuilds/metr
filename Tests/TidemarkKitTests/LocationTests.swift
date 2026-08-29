import XCTest
@testable import TidemarkKit

final class LocationTests: XCTestCase {

    // MARK: Resolution

    func testSystemSourceFollowsTheSystemZone() {
        let context = TimeZoneResolver.resolve(
            source: .system, locationAware: true, systemTimeZone: Fixture.kolkata
        )
        XCTAssertEqual(context.timeZone, Fixture.kolkata)
        XCTAssertFalse(context.isOverridden)
        XCTAssertEqual(context.placeLabel, "Kolkata")
    }

    func testManualOverrideWins() {
        let context = TimeZoneResolver.resolve(
            source: .manual(identifier: "Europe/London", label: nil),
            locationAware: true,
            systemTimeZone: Fixture.kolkata
        )
        XCTAssertEqual(context.timeZone, Fixture.london)
        XCTAssertTrue(context.isOverridden)
        XCTAssertEqual(context.placeLabel, "London")
    }

    func testCustomLabelReplacesTheDerivedPlaceName() {
        // The India zone is named for Kolkata; someone in Mumbai can say so.
        let context = TimeZoneResolver.resolve(
            source: .manual(identifier: "Asia/Kolkata", label: "Mumbai"),
            locationAware: true,
            systemTimeZone: Fixture.utc
        )
        XCTAssertEqual(context.placeLabel, "Mumbai")
        XCTAssertEqual(context.inlinePhrase, "Mumbai time")
        XCTAssertEqual(context.timeZone, Fixture.kolkata)
    }

    func testBlankCustomLabelFallsBackToTheDerivedName() {
        let context = TimeZoneResolver.resolve(
            source: .manual(identifier: "Asia/Kolkata", label: "   "),
            locationAware: true,
            systemTimeZone: Fixture.utc
        )
        XCTAssertEqual(context.placeLabel, "Kolkata")
    }

    func testUnknownTimezoneIdentifierFallsBackToTheSystemZone() {
        // A stale or hand-edited preference must not break the panel.
        let context = TimeZoneResolver.resolve(
            source: .manual(identifier: "Mars/Olympus_Mons", label: "Mars"),
            locationAware: true,
            systemTimeZone: Fixture.newYork
        )
        XCTAssertEqual(context.timeZone, Fixture.newYork)
        XCTAssertFalse(context.isOverridden, "A failed override must not claim to be overriding")
        XCTAssertEqual(context.placeLabel, "New York")
    }

    func testPrivacySwitchIgnoresOverrideWithoutErasingIt() {
        let source = TimeZoneSource.manual(identifier: "Europe/London", label: "Home")
        let context = TimeZoneResolver.resolve(
            source: source, locationAware: false, systemTimeZone: Fixture.kolkata
        )
        XCTAssertEqual(context.timeZone, Fixture.kolkata, "Privacy off means follow the system")
        XCTAssertFalse(context.isOverridden)
        XCTAssertTrue(context.isDisabled)
        // The stored value survives, so turning the switch back on restores it.
        XCTAssertEqual(source.manualIdentifier, "Europe/London")
    }

    // MARK: Labels

    func testPlaceNameHandlesMultiSegmentIdentifiers() {
        let zone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        XCTAssertEqual(TimeZoneResolver.placeName(for: zone), "Buenos Aires")
    }

    func testPlaceNameForUTC() {
        XCTAssertEqual(TimeZoneResolver.placeName(for: Fixture.utc), "UTC")
    }

    func testOffsetLabelFormatsHalfHourZones() {
        let date = Fixture.date(2026, 8, 30, 12, 0)
        XCTAssertEqual(TimeZoneResolver.offsetLabel(for: Fixture.kolkata, at: date), "GMT+5:30")
        XCTAssertEqual(TimeZoneResolver.offsetLabel(for: Fixture.utc, at: date), "GMT")
        XCTAssertEqual(TimeZoneResolver.offsetLabel(for: Fixture.newYork, at: date), "GMT-4")
    }

    func testSearchMatchesCityNamesWithSpaces() {
        let all = TimeZoneResolver.selectableIdentifiers()
        XCTAssertTrue(TimeZoneResolver.search("buenos aires", in: all).contains("America/Argentina/Buenos_Aires"))
        XCTAssertTrue(TimeZoneResolver.search("KOLKATA", in: all).contains("Asia/Kolkata"))
        XCTAssertTrue(TimeZoneResolver.search("", in: all).count == all.count)
        XCTAssertTrue(TimeZoneResolver.search("zzzznotazone", in: all).isEmpty)
    }

    // Foundation's own list is stuck on several pre-rename aliases, so the
    // picker has to modernise them or an Indian user is offered "Calcutta".
    func testPickerListUsesModernZoneNamesNotFoundationsLegacyAliases() {
        let all = TimeZoneResolver.selectableIdentifiers()
        XCTAssertTrue(all.contains("Asia/Kolkata"))
        XCTAssertFalse(all.contains("Asia/Calcutta"))
        XCTAssertTrue(all.contains("Europe/Kyiv"))
        XCTAssertFalse(all.contains("Europe/Kiev"))
    }

    func testSearchingTheOldNameStillFindsTheZone() {
        let all = TimeZoneResolver.selectableIdentifiers()
        XCTAssertTrue(TimeZoneResolver.search("calcutta", in: all).contains("Asia/Kolkata"))
        XCTAssertTrue(TimeZoneResolver.search("saigon", in: all).contains("Asia/Ho_Chi_Minh"))
    }

    func testModernisedIdentifiersAllConstructARealTimezone() {
        for identifier in TimeZoneResolver.selectableIdentifiers() {
            XCTAssertNotNil(TimeZone(identifier: identifier), "\(identifier) is not a usable zone")
        }
    }

    func testPlaceNameUsesTheModernCityName() {
        let zone = TimeZone(identifier: "Asia/Calcutta")!
        XCTAssertEqual(TimeZoneResolver.placeName(for: zone), "Kolkata")
    }

    // MARK: Dual-time reset descriptions

    func testProviderTimeIsShownOnlyWhenTheOffsetsDiffer() {
        let now = Fixture.date(2026, 8, 30, 6, 0)
        let reset = Fixture.date(2026, 8, 30, 12, 0)
        let kolkataContext = TimeZoneResolver.resolve(source: .system, locationAware: true, systemTimeZone: Fixture.kolkata)

        let differing = ResetFormatter.describe(reset: reset, now: now, display: kolkataContext, providerZone: Fixture.utc)
        XCTAssertNotNil(differing.providerTime, "UTC and Kolkata differ, so both times are useful")

        let same = ResetFormatter.describe(reset: reset, now: now, display: kolkataContext, providerZone: Fixture.kolkata)
        XCTAssertNil(same.providerTime, "Repeating the same time twice is noise")
    }

    func testResetDescriptionCarriesACountdownAndASpokenForm() {
        let now = Fixture.date(2026, 8, 30, 10, 0)
        let reset = now.addingTimeInterval(2 * 3600 + 18 * 60)
        let context = TimeZoneResolver.resolve(source: .system, locationAware: true, systemTimeZone: Fixture.utc)
        let description = ResetFormatter.describe(reset: reset, now: now, display: context, providerZone: Fixture.utc)

        XCTAssertEqual(description.countdown, "2h 18m")
        XCTAssertEqual(description.remaining, 2 * 3600 + 18 * 60, accuracy: 1)
        XCTAssertTrue(description.accessibleDescription.contains("2 hours 18 minutes"))
        XCTAssertTrue(description.accessibleDescription.contains("UTC time"))
    }

    func testResetDescriptionQualifiesTomorrow() {
        let context = TimeZoneResolver.resolve(source: .system, locationAware: true, systemTimeZone: Fixture.utc)
        let now = Fixture.date(2026, 8, 30, 22, 0)
        let reset = Fixture.date(2026, 8, 31, 9, 0)
        let description = ResetFormatter.describe(reset: reset, now: now, display: context, providerZone: Fixture.utc)
        XCTAssertTrue(description.primary.contains("tomorrow"), "Got: \(description.primary)")
    }

    func testPassedResetIsDescribedAsPassed() {
        let context = TimeZoneResolver.resolve(source: .system, locationAware: true, systemTimeZone: Fixture.utc)
        let now = Fixture.date(2026, 8, 30, 12, 0)
        let description = ResetFormatter.describe(reset: now.addingTimeInterval(-60), now: now, display: context, providerZone: Fixture.utc)
        XCTAssertLessThan(description.remaining, 0)
        XCTAssertTrue(description.accessibleDescription.contains("passed"))
    }

    // MARK: Continuation guidance

    func testGuidanceSaysSafeWhenPaceLandsWellUnderTheLimit() {
        let guidance = ResetFormatter.continuationGuidance(
            usedFraction: 0.2, remaining: 3600, elapsedFraction: 0.5, thresholds: .default
        )
        XCTAssertEqual(guidance?.verdict, .safe)
    }

    func testGuidanceSaysHoldWhenPaceWouldExceedTheLimit() {
        // 60% used in the first 40% of the window projects to 150%.
        let guidance = ResetFormatter.continuationGuidance(
            usedFraction: 0.6, remaining: 3600, elapsedFraction: 0.4, thresholds: .default
        )
        XCTAssertEqual(guidance?.verdict, .hold)
    }

    func testGuidanceIsCautiousInBetween() {
        // 40% used in half a window projects to 80%, above the 85% critical? No —
        // just under, so this must be caution only once it crosses critical.
        let cautious = ResetFormatter.continuationGuidance(
            usedFraction: 0.45, remaining: 3600, elapsedFraction: 0.5, thresholds: .default
        )
        XCTAssertEqual(cautious?.verdict, .caution, "0.45/0.5 = 90% projected, above the 85% critical mark")
    }

    func testGuidanceIsNilWithoutAUsageNumber() {
        XCTAssertNil(ResetFormatter.continuationGuidance(
            usedFraction: nil, remaining: 3600, elapsedFraction: 0.5, thresholds: .default
        ))
    }

    func testGuidanceFallsBackToLevelWhenPaceIsUnknown() {
        let guidance = ResetFormatter.continuationGuidance(
            usedFraction: 0.9, remaining: 3600, elapsedFraction: nil, thresholds: .default
        )
        XCTAssertEqual(guidance?.verdict, .hold)
    }

    func testGuidanceAfterResetIsSafe() {
        let guidance = ResetFormatter.continuationGuidance(
            usedFraction: 0.99, remaining: -10, elapsedFraction: 0.9, thresholds: .default
        )
        XCTAssertEqual(guidance?.verdict, .safe)
    }
}
