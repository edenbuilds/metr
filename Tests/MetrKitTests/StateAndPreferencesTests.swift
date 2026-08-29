import XCTest
@testable import MetrKit

final class StateAndPreferencesTests: XCTestCase {

    // MARK: DataState

    func testOnlyLiveStateIsTrustworthy() {
        XCTAssertTrue(DataState.live(fetched: Date()).isTrustworthy)
        XCTAssertFalse(DataState.stale(fetched: Date(), age: 60).isTrustworthy)
        XCTAssertFalse(DataState.offline(lastKnown: Date()).isTrustworthy)
    }

    func testStatesThatHaveNoUsableNumber() {
        XCTAssertTrue(DataState.authenticationRequired.hasNoData)
        XCTAssertTrue(DataState.unavailable(reason: "x").hasNoData)
        XCTAssertTrue(DataState.offline(lastKnown: nil).hasNoData)
        XCTAssertFalse(DataState.offline(lastKnown: Date()).hasNoData, "A cached number is still a number")
        XCTAssertFalse(DataState.stale(fetched: Date(), age: 60).hasNoData)
    }

    func testEveryStateHasASymbolAndAWordNotJustAColour() {
        let states: [DataState] = [
            .loading, .live(fetched: Date()), .stale(fetched: Date(), age: 60),
            .offline(lastKnown: nil), .authenticationRequired, .unavailable(reason: "no file")
        ]
        for state in states {
            XCTAssertFalse(state.label.isEmpty)
            XCTAssertFalse(state.symbolName.isEmpty)
            XCTAssertFalse(state.explanation.isEmpty)
        }
        for severity in [Severity.nominal, .watch, .critical] {
            XCTAssertFalse(severity.label.isEmpty)
            XCTAssertFalse(severity.symbolName.isEmpty)
        }
    }

    func testProviderSeverityTakesTheWorseOfUsageAndConnection() {
        let stale = Fixture.provider(fraction: 0.1, state: .stale(fetched: Date(), age: 3600))
        XCTAssertEqual(stale.severity(thresholds: .default), .watch, "Low usage but stale data still warrants a look")
    }

    func testContextFractionGuardsAgainstAZeroBudget() {
        var provider = Fixture.provider()
        provider.contextUsed = 10
        provider.contextBudget = 0
        XCTAssertNil(provider.contextFraction)
    }

    // MARK: Preferences

    func testPreferencesRoundTripThroughDefaults() {
        let defaults = Fixture.defaults()
        let store = PreferencesStore(defaults: defaults)

        var prefs = Preferences()
        prefs.mode = .both
        prefs.appearance = .dark
        prefs.hiddenProviderIDs = ["codex"]
        prefs.thresholds = AlertThresholds(watch: 0.5, critical: 0.7)
        store.save(prefs)

        let loaded = PreferencesStore(defaults: defaults).load()
        XCTAssertEqual(loaded.mode, .both)
        XCTAssertEqual(loaded.appearance, .dark)
        XCTAssertEqual(loaded.hiddenProviderIDs, ["codex"])
        XCTAssertEqual(loaded.thresholds.watch, 0.5, accuracy: 0.001)
    }

    func testCorruptPreferencesFallBackToDefaultsInsteadOfFailing() {
        let defaults = Fixture.defaults()
        defaults.set(Data("not json".utf8), forKey: "preferences.v2")
        let loaded = PreferencesStore(defaults: defaults).load()
        XCTAssertEqual(loaded.mode, Preferences().mode)
    }

    func testEveryPresentationModeHasAVisibleTitleAndSymbol() {
        for mode in PresentationMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.symbolName.isEmpty)
        }
    }

    func testProviderVisibilityFiltering() {
        var prefs = Preferences()
        XCTAssertTrue(prefs.isVisible("claude"))
        prefs.hiddenProviderIDs.insert("claude")
        XCTAssertFalse(prefs.isVisible("claude"))
    }

    func testManualCadenceHasNoTimerInterval() {
        XCTAssertNil(RefreshCadence.manual.interval)
        XCTAssertEqual(RefreshCadence.fast.interval, 30)
    }

    // MARK: Onboarding

    func testSetupAdvancesThroughEveryStepThenCompletes() {
        var state = OnboardingState()
        XCTAssertFalse(state.hasCompletedSetup)
        for _ in SetupStep.allCases { state.advance() }
        XCTAssertTrue(state.hasCompletedSetup)
        XCTAssertEqual(state.completedSteps.count, SetupStep.allCases.count)
        XCTAssertEqual(state.progress, 1.0, accuracy: 0.001)
    }

    func testSkippingLeavesStepsOutstandingSoTheChecklistStillOffersThem() {
        var state = OnboardingState()
        state.advance()          // completes step 1
        state.skip()
        XCTAssertTrue(state.hasCompletedSetup)
        XCTAssertFalse(state.remainingSteps.isEmpty)
        XCTAssertTrue(state.showsChecklist, "Skipping must not hide the way back")
    }

    func testChecklistDisappearsOnceEverythingIsDone() {
        var state = OnboardingState()
        for _ in SetupStep.allCases { state.advance() }
        XCTAssertFalse(state.showsChecklist)
    }

    func testRetreatStopsAtTheFirstStep() {
        var state = OnboardingState()
        state.retreat()
        XCTAssertEqual(state.currentStep, .placement)
    }

    func testHintsShowOnlyAfterSetupAndNeverReturnOnceDismissed() {
        var state = OnboardingState()
        XCTAssertFalse(state.shouldShow(.dragToMove), "Do not stack tips on top of setup")
        state.skip()
        XCTAssertTrue(state.shouldShow(.dragToMove))
        state.dismissedHints.insert(.dragToMove)
        XCTAssertFalse(state.shouldShow(.dragToMove))
    }

    func testOnboardingRoundTripsThroughDefaults() {
        let defaults = Fixture.defaults()
        var state = OnboardingState()
        state.advance()
        state.dismissedHints.insert(.keyboardShortcuts)
        OnboardingStore(defaults: defaults).save(state)

        let loaded = OnboardingStore(defaults: defaults).load()
        XCTAssertEqual(loaded.completedSteps, state.completedSteps)
        XCTAssertEqual(loaded.dismissedHints, [.keyboardShortcuts])
    }

    func testEverySetupStepAndHintHasCopy() {
        for step in SetupStep.allCases {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.summary.isEmpty)
            XCTAssertFalse(step.symbolName.isEmpty)
        }
        for hint in Hint.allCases {
            XCTAssertFalse(hint.text.isEmpty)
        }
    }
}

// MARK: - Forward compatibility & unknown status

final class ForwardCompatibilityTests: XCTestCase {

    func testPreferencesFromAnOlderBuildStillLoad() throws {
        // Only two keys, as an older version might have written.
        let json = #"{"mode":"top","alertsEnabled":false}"#
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertEqual(prefs.mode, .top, "The keys that were present must be honoured")
        XCTAssertFalse(prefs.alertsEnabled)
        XCTAssertEqual(prefs.panelWidth, Preferences().panelWidth, "Missing keys fall back to defaults")
        XCTAssertEqual(prefs.refresh, Preferences().refresh)
    }

    func testPreferencesIgnoreKeysTheyDoNotUnderstand() throws {
        let json = #"{"mode":"side","somethingFromTheFuture":{"a":1}}"#
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertEqual(prefs.mode, .side)
    }

    func testPreferencesSurviveAWrongTypeForOneKey() throws {
        // A hand-edited or corrupted value must cost that one setting, not all of them.
        let json = #"{"mode":"top","panelWidth":42}"#
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertEqual(prefs.mode, .top)
        XCTAssertEqual(prefs.panelWidth, Preferences().panelWidth)
    }

    func testOnboardingFromAnOlderBuildStillLoads() throws {
        let json = #"{"hasCompletedSetup":true}"#
        let state = try JSONDecoder().decode(OnboardingState.self, from: Data(json.utf8))
        XCTAssertTrue(state.hasCompletedSetup)
        XCTAssertEqual(state.currentStep, .placement)
        XCTAssertTrue(state.dismissedHints.isEmpty)
    }

    @MainActor
    func testStatusIsUnknownUntilAProviderReports() async {
        let store = UsageStore(
            preferencesStore: PreferencesStore(defaults: Fixture.defaults()),
            onboardingStore: OnboardingStore(defaults: Fixture.defaults()),
            dataSource: MockUsageDataSource(scenario: .noData)
        )
        XCTAssertFalse(store.statusIsKnown)
        XCTAssertFalse(store.headerStatus.isKnown, "A green 'Clear' before any data would be a lie")

        await store.refresh()
        XCTAssertFalse(store.statusIsKnown, "Still nothing reported")

        store.useDataSource(MockUsageDataSource(scenario: .healthy))
        await store.refresh()
        XCTAssertTrue(store.statusIsKnown)
        XCTAssertTrue(store.headerStatus.isKnown)
        XCTAssertEqual(store.headerStatus.severity, .nominal)
    }

    @MainActor
    func testStatusStaysUnknownWhenEveryProviderNeedsAuth() async {
        let store = UsageStore(
            preferencesStore: PreferencesStore(defaults: Fixture.defaults()),
            onboardingStore: OnboardingStore(defaults: Fixture.defaults()),
            dataSource: MockUsageDataSource(scenario: .authRequired)
        )
        await store.refresh()
        XCTAssertFalse(store.headerStatus.isKnown)
    }

    @MainActor
    func testHiddenProvidersAreExcludedFromStatusAndAlerts() async {
        let store = UsageStore(
            preferencesStore: PreferencesStore(defaults: Fixture.defaults()),
            onboardingStore: OnboardingStore(defaults: Fixture.defaults()),
            dataSource: MockUsageDataSource(scenario: .atLimit)
        )
        await store.refresh()
        XCTAssertEqual(store.overallSeverity, .critical)

        store.preferences.hiddenProviderIDs = Set(store.allProviders.map(\.id))
        XCTAssertTrue(store.visibleProviders.isEmpty)
        XCTAssertFalse(store.statusIsKnown, "Hiding everything means we no longer know, not that all is well")
    }

    @MainActor
    func testQuietHoursFollowTheSystemTimezone() async {
        let store = UsageStore(
            preferencesStore: PreferencesStore(defaults: Fixture.defaults()),
            onboardingStore: OnboardingStore(defaults: Fixture.defaults()),
            dataSource: MockUsageDataSource(scenario: .healthy)
        )
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        let hour = calendar.component(.hour, from: Date())
        store.preferences.quietHours = QuietHours(enabled: true, startHour: hour, endHour: (hour + 1) % 24)
        XCTAssertTrue(store.isInQuietHours)

        store.preferences.quietHours = QuietHours(enabled: true, startHour: (hour + 2) % 24, endHour: (hour + 3) % 24)
        XCTAssertFalse(store.isInQuietHours)
    }
}
