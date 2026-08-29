import Foundation

public enum PresentationMode: String, CaseIterable, Codable, Sendable {
    case top, side, both

    public var title: String {
        switch self {
        case .top: return "Top bar"
        case .side: return "Side dock"
        case .both: return "Both"
        }
    }

    public var symbolName: String {
        switch self {
        case .top: return "rectangle.topthird.inset.filled"
        case .side: return "rectangle.trailingthird.inset.filled"
        case .both: return "rectangle.split.2x1"
        }
    }
}

/// Which side the side-edge rail lives on.
public enum ScreenEdge: String, CaseIterable, Codable, Sendable {
    case leading, trailing

    public var title: String {
        switch self {
        case .leading: return "Left"
        case .trailing: return "Right"
        }
    }
}

/// What the collapsed pill shows. Keeps the compact state a deliberate choice
/// rather than a truncation of the expanded one.
public enum CompactMetric: String, CaseIterable, Codable, Sendable {
    case percentUsed, timeToReset, contextLeft, estimatedCost

    public var title: String {
        switch self {
        case .percentUsed: return "Percent used"
        case .timeToReset: return "Time to reset"
        case .contextLeft: return "Context left"
        case .estimatedCost: return "Cost today"
        }
    }
}

public enum PanelWidth: String, CaseIterable, Codable, Sendable {
    case compact, standard, wide

    public var title: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .wide: return "Wide"
        }
    }

    public var points: Double {
        switch self {
        case .compact: return 366
        case .standard: return 420
        case .wide: return 484
        }
    }
}

public enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system, light, dark

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum RefreshCadence: String, CaseIterable, Codable, Sendable {
    case fast, normal, relaxed, manual

    public var title: String {
        switch self {
        case .fast: return "Every 30s"
        case .normal: return "Every 2 min"
        case .relaxed: return "Every 10 min"
        case .manual: return "Manual only"
        }
    }

    /// Nil means "never fire a timer".
    public var interval: TimeInterval? {
        switch self {
        case .fast: return 30
        case .normal: return 120
        case .relaxed: return 600
        case .manual: return nil
        }
    }
}

public enum DataSourceKind: String, CaseIterable, Codable, Sendable {
    /// Reads provider quota with an existing sign-in and local history files.
    case local
    /// Deterministic synthetic data, for demoing and for UI tests.
    case mock

    public var title: String {
        switch self {
        case .local: return "Local activity"
        case .mock: return "Demo data"
        }
    }

    public var explanation: String {
        switch self {
        case .local: return "Reads provider quota with your existing sign-in, plus local session history. Read-only."
        case .mock: return "Synthetic data for trying the interface without touching your files."
        }
    }
}

/// Everything the user can configure. One `Codable` struct so the whole thing
/// round-trips through `UserDefaults` as a single value.
public struct Preferences: Equatable, Codable, Sendable {
    public var mode: PresentationMode = .side
    public var edge: ScreenEdge = .trailing
    public var expanded: Bool = true
    public var pinned: Bool = false
    public var autoHide: Bool = true
    public var panelWidth: PanelWidth = .standard
    public var appearance: AppearanceMode = .system
    public var refresh: RefreshCadence = .normal
    public var compactMetric: CompactMetric = .percentUsed
    public var thresholds: AlertThresholds = .default
    public var quietHours: QuietHours = .default
    public var alertsEnabled: Bool = true
    public var launchAtLogin: Bool = false
    public var reduceMotionOverride: Bool = false
    public var dataSource: DataSourceKind = .local
    /// Provider ids the user has hidden.
    public var hiddenProviderIDs: Set<String> = []
    /// Position along the docked edge, 0 = start, 1 = end. Persisted after a drag.
    public var edgeOffset: Double = 0.5

    public init() {}

    /// Decoded field by field with `decodeIfPresent`, so a preferences file
    /// written by an older build (or a newer one with fields we do not know)
    /// still loads. The synthesised decoder would reject the whole file for one
    /// missing key and silently reset every setting the user had chosen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback
        }
        let defaults = Preferences()
        mode = value(.mode, defaults.mode)
        edge = value(.edge, defaults.edge)
        expanded = value(.expanded, defaults.expanded)
        pinned = value(.pinned, defaults.pinned)
        autoHide = value(.autoHide, defaults.autoHide)
        panelWidth = value(.panelWidth, defaults.panelWidth)
        appearance = value(.appearance, defaults.appearance)
        refresh = value(.refresh, defaults.refresh)
        compactMetric = value(.compactMetric, defaults.compactMetric)
        thresholds = value(.thresholds, defaults.thresholds)
        quietHours = value(.quietHours, defaults.quietHours)
        alertsEnabled = value(.alertsEnabled, defaults.alertsEnabled)
        launchAtLogin = value(.launchAtLogin, defaults.launchAtLogin)
        reduceMotionOverride = value(.reduceMotionOverride, defaults.reduceMotionOverride)
        dataSource = value(.dataSource, defaults.dataSource)
        hiddenProviderIDs = value(.hiddenProviderIDs, defaults.hiddenProviderIDs)
        edgeOffset = value(.edgeOffset, defaults.edgeOffset)
    }

    public func isVisible(_ providerID: String) -> Bool { !hiddenProviderIDs.contains(providerID) }
}

// MARK: - Persistence

/// Thin `UserDefaults` wrapper. Kept separate from `Preferences` so tests can
/// use an ephemeral suite.
public final class PreferencesStore {
    private let defaults: UserDefaults
    private let key = "preferences.v2"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Preferences {
        // `METR_PREFS` lets a test or a demo pin the app into an exact state
        // without touching the user's real preferences. Ignored when unset.
        if let json = ProcessInfo.processInfo.environment["METR_PREFS"],
           let overridden = try? JSONDecoder().decode(Preferences.self, from: Data(json.utf8)) {
            return overridden
        }
        guard let data = defaults.data(forKey: key) else { return Preferences() }
        // A decode failure means a preferences format change or a corrupt value.
        // Falling back to defaults is better than refusing to launch.
        return (try? JSONDecoder().decode(Preferences.self, from: data)) ?? Preferences()
    }

    /// True when preferences are being driven by the environment, in which case
    /// nothing should be written back over the user's real settings.
    public var isOverriddenByEnvironment: Bool {
        ProcessInfo.processInfo.environment["METR_PREFS"] != nil
    }

    public func save(_ preferences: Preferences) {
        guard !isOverriddenByEnvironment else { return }
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }

    /// Remove every persisted preference.
    public func reset() { defaults.removeObject(forKey: key) }
}
