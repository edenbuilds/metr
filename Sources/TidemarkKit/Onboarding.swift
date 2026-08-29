import Foundation

/// The four things a new user must decide before the panel is useful.
///
/// Each step is a real control that changes real settings — not a slideshow
/// the user clicks through and then has to go and configure anyway.
public enum SetupStep: String, CaseIterable, Codable, Sendable, Identifiable {
    case placement
    case dataSource
    case location
    case alerts

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .placement: return "Where should it live?"
        case .dataSource: return "What should it read?"
        case .location: return "Which clock?"
        case .alerts: return "When should it speak up?"
        }
    }

    public var summary: String {
        switch self {
        case .placement: return "A quiet rail on the screen edge, or an island under the menu bar."
        case .dataSource: return "Real session files already on this Mac, or demo data to look around first."
        case .location: return "Reset times are shown in this timezone. Change it when you travel."
        case .alerts: return "A nudge before you hit a limit, and silence when you are asleep."
        }
    }

    public var symbolName: String {
        switch self {
        case .placement: return "rectangle.trailingthird.inset.filled"
        case .dataSource: return "externaldrive.connected.to.line.below"
        case .location: return "globe"
        case .alerts: return "bell.badge"
        }
    }
}

/// A one-time inline hint. Shown once, dismissable, never nagging.
public enum Hint: String, CaseIterable, Codable, Sendable, Identifiable {
    case dragToMove
    case collapseToRail
    case measuredVsEstimated
    case keyboardShortcuts

    public var id: String { rawValue }

    public var text: String {
        switch self {
        case .dragToMove: return "Drag the header to slide this along the edge. It snaps back on release."
        case .collapseToRail: return "Collapse it and it shrinks to a thin rail. Hover the rail to peek."
        case .measuredVsEstimated: return "“Measured” came from a file on this Mac. “Estimated” came from an assumption, which is always written next to it."
        case .keyboardShortcuts: return "⌘R refreshes, ⌘1–⌘3 switch tabs, Esc collapses."
        }
    }
}

/// Persisted onboarding progress.
public struct OnboardingState: Equatable, Codable, Sendable {
    /// False until the user finishes or skips the setup card.
    public var hasCompletedSetup: Bool = false
    /// Steps the user has actively confirmed.
    public var completedSteps: Set<SetupStep> = []
    /// Hints already dismissed.
    public var dismissedHints: Set<Hint> = []
    /// True once the checklist card has been dismissed from the overview.
    public var checklistDismissed: Bool = false
    /// The step the setup card is currently showing.
    public var currentStep: SetupStep = .placement

    public init() {}

    /// Same forward-compatible decoding as `Preferences`: a missing key means
    /// "use the default", not "throw away everything the user has done".
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedSetup = (try? c.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup)) .flatMap { $0 } ?? false
        completedSteps = (try? c.decodeIfPresent(Set<SetupStep>.self, forKey: .completedSteps)) .flatMap { $0 } ?? []
        dismissedHints = (try? c.decodeIfPresent(Set<Hint>.self, forKey: .dismissedHints)) .flatMap { $0 } ?? []
        checklistDismissed = (try? c.decodeIfPresent(Bool.self, forKey: .checklistDismissed)) .flatMap { $0 } ?? false
        currentStep = (try? c.decodeIfPresent(SetupStep.self, forKey: .currentStep)) .flatMap { $0 } ?? .placement
    }

    public var progress: Double {
        Double(completedSteps.count) / Double(SetupStep.allCases.count)
    }

    public var remainingSteps: [SetupStep] {
        SetupStep.allCases.filter { !completedSteps.contains($0) }
    }

    /// Whether the getting-started checklist should still appear in Overview.
    public var showsChecklist: Bool {
        !checklistDismissed && !remainingSteps.isEmpty
    }

    public func shouldShow(_ hint: Hint) -> Bool {
        hasCompletedSetup && !dismissedHints.contains(hint)
    }

    public mutating func complete(_ step: SetupStep) {
        completedSteps.insert(step)
    }

    public mutating func advance() {
        let all = SetupStep.allCases
        guard let index = all.firstIndex(of: currentStep) else { return }
        completedSteps.insert(currentStep)
        if index + 1 < all.count {
            currentStep = all[index + 1]
        } else {
            hasCompletedSetup = true
        }
    }

    public mutating func retreat() {
        let all = SetupStep.allCases
        guard let index = all.firstIndex(of: currentStep), index > 0 else { return }
        currentStep = all[index - 1]
    }

    /// Skip the rest of setup. Steps stay incomplete so the checklist can still
    /// offer them later rather than pretending the user configured them.
    public mutating func skip() {
        hasCompletedSetup = true
    }

    public mutating func restart() {
        hasCompletedSetup = false
        checklistDismissed = false
        currentStep = .placement
    }
}

// MARK: - Persistence

public final class OnboardingStore {
    private let defaults: UserDefaults
    private let key = "onboarding.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> OnboardingState {
        if let json = ProcessInfo.processInfo.environment["UP_ONBOARDING"],
           let overridden = try? JSONDecoder().decode(OnboardingState.self, from: Data(json.utf8)) {
            return overridden
        }
        guard let data = defaults.data(forKey: key) else { return OnboardingState() }
        return (try? JSONDecoder().decode(OnboardingState.self, from: data)) ?? OnboardingState()
    }

    public var isOverriddenByEnvironment: Bool {
        ProcessInfo.processInfo.environment["UP_ONBOARDING"] != nil
    }

    public func save(_ state: OnboardingState) {
        guard !isOverriddenByEnvironment else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    public func reset() { defaults.removeObject(forKey: key) }
}
