import Foundation
import Combine

public enum PanelTab: Int, CaseIterable, Identifiable, Sendable {
    case overview, history, insights

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .history: return "History"
        case .insights: return "Insights"
        }
    }

    public var symbolName: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .history: return "chart.bar"
        case .insights: return "lightbulb"
        }
    }
}

/// The single observable object the presentation layer binds to.
///
/// It owns preferences, onboarding, the active data source, and the refresh
/// timer. It deliberately knows nothing about windows, panels or SwiftUI views.
@MainActor
public final class UsageStore: ObservableObject {

    // MARK: Published state

    @Published public private(set) var snapshot: UsageSnapshot = .empty
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastRefresh: Date?
    @Published public private(set) var alerts: [UsageAlert] = []
    @Published public var selectedTab: PanelTab = .overview
    @Published public var isShowingPreferences = false

    @Published public var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferencesStore.save(preferences)
            if preferences.refresh != oldValue.refresh { restartTimer() }
            if preferences.dataSource != oldValue.dataSource {
                rebuildDataSource()
                Task { await refresh() }
            }
            onPreferencesChanged?(preferences, oldValue)
        }
    }

    @Published public var onboarding: OnboardingState {
        didSet {
            guard onboarding != oldValue else { return }
            onboardingStore.save(onboarding)
        }
    }

    /// Ticks once a second while expanded so countdowns stay live without the
    /// whole snapshot being refetched.
    @Published public private(set) var now: Date = Date()

    // MARK: Callbacks into the presentation layer

    /// Called when preferences change, so the panel can re-lay itself out.
    public var onPreferencesChanged: ((Preferences, Preferences) -> Void)?
    /// Called with alerts that should be delivered as notifications.
    public var onAlerts: (([UsageAlert]) -> Void)?

    // MARK: Dependencies

    private let preferencesStore: PreferencesStore
    private let onboardingStore: OnboardingStore
    private var dataSource: UsageDataSource
    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var raisedAlertIDs: Set<String> = []
    private var timeZoneObserver: NSObjectProtocol?

    /// Bumped whenever the system timezone changes under us, so the UI can say
    /// so rather than silently re-rendering every time in a new zone.
    @Published public private(set) var systemTimeZoneChangedAt: Date?

    public init(
        preferencesStore: PreferencesStore = PreferencesStore(),
        onboardingStore: OnboardingStore = OnboardingStore(),
        dataSource: UsageDataSource? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.onboardingStore = onboardingStore
        let loaded = preferencesStore.load()
        self.preferences = loaded
        self.onboarding = onboardingStore.load()
        self.dataSource = dataSource ?? Self.makeDataSource(for: loaded.dataSource)

        timeZoneObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The Mac moved timezone. Recompute everything that depends on it.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.systemTimeZoneChangedAt = Date()
                self.objectWillChange.send()
            }
        }
    }

    deinit {
        if let timeZoneObserver { NotificationCenter.default.removeObserver(timeZoneObserver) }
        refreshTimer?.invalidate()
        tickTimer?.invalidate()
    }

    private static func makeDataSource(for kind: DataSourceKind) -> UsageDataSource {
        switch kind {
        case .local: return LocalActivityDataSource()
        case .mock:
            // `UP_SCENARIO` picks which demo situation to show, so the offline,
            // stale, auth-required and empty surfaces can all be reviewed.
            let name = ProcessInfo.processInfo.environment["UP_SCENARIO"] ?? ""
            return MockUsageDataSource(scenario: MockUsageDataSource.Scenario(rawValue: name) ?? .healthy)
        }
    }

    private func rebuildDataSource() {
        dataSource = Self.makeDataSource(for: preferences.dataSource)
    }

    public var dataSourceProvenance: String { dataSource.provenance }

    /// Swap the adapter at runtime. Used by tests and by the demo-scenario picker.
    public func useDataSource(_ source: UsageDataSource) {
        dataSource = source
    }

    // MARK: - Location

    /// The resolved display location, honouring the privacy switch.
    public var location: LocationContext {
        TimeZoneResolver.resolve(
            source: preferences.timeZoneSource,
            locationAware: preferences.locationAware
        )
    }

    /// Point the display clock at a timezone the user picked by hand.
    public func setManualTimeZone(_ identifier: String, label: String?) {
        preferences.manualTimeZoneID = identifier
        preferences.manualPlaceLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Go back to following the Mac's timezone.
    public func useSystemTimeZone() {
        preferences.clearLocationData()
    }

    /// Privacy control: forget every stored location value.
    public func clearStoredLocationData() {
        preferences.clearLocationData()
        systemTimeZoneChangedAt = nil
    }

    // MARK: - Lifecycle

    public func start() {
        restartTimer()
        startTicking()
        Task { await refresh() }
    }

    public func stop() {
        refreshTimer?.invalidate(); refreshTimer = nil
        tickTimer?.invalidate(); tickTimer = nil
    }

    private func restartTimer() {
        refreshTimer?.invalidate()
        guard let interval = preferences.refresh.interval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
        // .tolerance lets the system coalesce our wakeups with others, which is
        // most of the difference between a background app that costs battery
        // and one that does not.
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// The one-second tick only runs while something on screen actually shows a
    /// countdown. Collapsed to the rail, there is nothing to animate.
    private func startTicking() {
        tickTimer?.invalidate()
        guard preferences.expanded else { now = Date(); return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
            }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    public func setExpanded(_ expanded: Bool) {
        preferences.expanded = expanded
        startTicking()
    }

    // MARK: - Refresh

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let captured = Date()
        let fresh = await dataSource.fetch(now: captured)
        snapshot = fresh
        lastRefresh = captured
        now = captured
        evaluateAlerts(now: captured)
    }

    private func evaluateAlerts(now: Date) {
        guard preferences.alertsEnabled else { alerts = []; return }
        let (fire, raised) = AlertEngine.evaluate(
            providers: visibleProviders,
            thresholds: preferences.thresholds,
            quietHours: preferences.quietHours,
            displayZone: location.timeZone,
            now: now,
            alreadyRaised: raisedAlertIDs
        )
        raisedAlertIDs = raised
        alerts = fire
        if !fire.isEmpty { onAlerts?(fire) }
    }

    // MARK: - Derived state

    public var visibleProviders: [ProviderSnapshot] {
        snapshot.providers.filter { preferences.isVisible($0.id) }
    }

    public var allProviders: [ProviderSnapshot] { snapshot.providers }

    /// The provider under the most pressure; what the compact state summarises.
    public var focusProvider: ProviderSnapshot? {
        visibleProviders
            .filter { $0.usedFraction != nil }
            .max { ($0.usedFraction ?? 0) < ($1.usedFraction ?? 0) }
            ?? visibleProviders.first
    }

    public var overallSeverity: Severity {
        visibleProviders.map { $0.severity(thresholds: preferences.thresholds) }.max() ?? .nominal
    }

    /// False until at least one provider has produced a usable number.
    /// Without this the panel shows a green "Clear" before it knows anything,
    /// which is the one thing a usage meter must never do.
    public var statusIsKnown: Bool {
        visibleProviders.contains { !$0.state.hasNoData }
    }

    /// Header status: symbol, word and colour, or an explicit unknown state.
    public var headerStatus: (symbol: String, label: String, severity: Severity, isKnown: Bool) {
        guard statusIsKnown else {
            let checking = isRefreshing || lastRefresh == nil
            return (checking ? "circle.dotted" : "questionmark.circle",
                    checking ? "Checking" : "No data",
                    .nominal, false)
        }
        let severity = overallSeverity
        return (severity.symbolName, severity.label, severity, true)
    }

    /// The single sentence at the top of the expanded panel.
    public var headline: (symbol: String, title: String, detail: String, severity: Severity) {
        if visibleProviders.isEmpty {
            return ("questionmark.circle", "Nothing to show yet",
                    snapshot.providers.isEmpty
                        ? "No provider reported usage on the last refresh."
                        : "Every provider is hidden. Turn one back on in Preferences.",
                    .watch)
        }
        if visibleProviders.allSatisfy({ $0.state.hasNoData }) {
            let first = visibleProviders.first!
            return (first.state.symbolName, first.state.label, first.state.explanation, .watch)
        }
        guard let focus = focusProvider, let guidance = continuationGuidance(for: focus) else {
            return ("checkmark.circle.fill", "Room to think", "Your active windows are below their limits.", .nominal)
        }
        return (guidance.verdict.symbolName, guidance.headline, guidance.detail, guidance.verdict.severity)
    }

    public func continuationGuidance(for provider: ProviderSnapshot) -> ContinuationGuidance? {
        let reset = provider.window.nextReset(after: now)
        return ResetFormatter.continuationGuidance(
            usedFraction: provider.usedFraction,
            remaining: reset.timeIntervalSince(now),
            elapsedFraction: provider.window.elapsedFraction(now: now),
            thresholds: preferences.thresholds
        )
    }

    public func resetDescription(for provider: ProviderSnapshot) -> ResetDescription {
        let reset = provider.window.nextReset(after: now)
        return ResetFormatter.describe(
            reset: reset,
            now: now,
            display: location,
            providerZone: preferences.showProviderTimeZone ? provider.window.timeZone : location.timeZone
        )
    }

    public var insights: [Insight] {
        InsightEngine.insights(
            activity: snapshot.activity,
            sessions: snapshot.sessions,
            providers: visibleProviders,
            location: location,
            now: now
        )
    }

    public var totalEstimatedCost: Double? {
        let costs = visibleProviders.compactMap(\.estimatedCost)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    /// True when quiet hours are currently suppressing alerts.
    public var isInQuietHours: Bool {
        preferences.quietHours.contains(now, in: location.timeZone)
    }

    /// The text under the compact pill, chosen by the user's compact metric.
    public func compactValue(for provider: ProviderSnapshot) -> String {
        switch preferences.compactMetric {
        case .percentUsed:
            return provider.usedFraction.map { Formatters.percent($0) } ?? "—"
        case .timeToReset:
            return Formatters.countdown(provider.window.nextReset(after: now).timeIntervalSince(now))
        case .contextLeft:
            guard let fraction = provider.contextFraction else { return "—" }
            return Formatters.percent(1 - fraction)
        case .estimatedCost:
            return provider.estimatedCost.map { Formatters.currency($0) } ?? "—"
        }
    }

    // MARK: - Onboarding

    public func completeCurrentSetupStep() { onboarding.advance() }
    public func goBackASetupStep() { onboarding.retreat() }
    public func skipSetup() { onboarding.skip() }
    public func restartSetup() { onboarding.restart() }
    public func dismissChecklist() { onboarding.checklistDismissed = true }
    public func dismiss(_ hint: Hint) { onboarding.dismissedHints.insert(hint) }
    public func jumpTo(step: SetupStep) {
        onboarding.currentStep = step
        onboarding.hasCompletedSetup = false
    }

    /// Reset absolutely everything this app has stored.
    public func resetAllStoredData() {
        preferencesStore.reset()
        onboardingStore.reset()
        preferences = Preferences()
        onboarding = OnboardingState()
        raisedAlertIDs = []
        rebuildDataSource()
    }
}
