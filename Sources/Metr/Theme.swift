import AppKit
import SwiftUI
import MetrKit

/// Design tokens.
///
/// Two rules hold the visual language together:
/// 1. Colour is never the only carrier of meaning — every status also has a
///    symbol and a word.
/// 2. Every font is a *relative* style, so the whole panel responds to the
///    system text size instead of staying pinned at whatever looked right on
///    one Mac.
enum Theme {

    // MARK: Geometry

    enum Radius {
        static let panel: CGFloat = 20
        static let card: CGFloat = 12
        static let chip: CGFloat = 8
    }

    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 6
        static let base: CGFloat = 10
        static let roomy: CGFloat = 14
        static let loose: CGFloat = 18
    }

    /// Outer margin between the panel card and the window edge. The window is
    /// larger than the card by this much on every side so the shadow has room.
    static let shadowMargin: CGFloat = 12

    /// The minimized dock is a real control surface, not a decorative line.
    static let dockWidth: CGFloat = 76
    static let dockRowHeight: CGFloat = 58
    static let dockTopHeight: CGFloat = 68
    static let dockSidePadding: CGFloat = 6

    // MARK: Typography

    enum Text {
        /// Panel title / wordmark.
        static let title = Font.system(.title3, design: .rounded).weight(.semibold)
        /// Section and card headings.
        static let heading = Font.system(.subheadline, design: .rounded).weight(.semibold)
        /// Primary numeric readouts. Monospaced digits stop the panel twitching
        /// as a countdown ticks.
        static let metric = Font.system(.body, design: .rounded).weight(.semibold).monospacedDigit()
        static let metricLarge = Font.system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
        /// Body copy.
        static let body = Font.system(.subheadline)
        /// Supporting detail — the smallest text in the app.
        static let caption = Font.footnote
        static let captionTight = Font.caption
        /// Fine print (provenance, assumptions). Never used for anything the
        /// user has to read to operate the app.
        static let fine = Font.caption2
    }

    // MARK: Colour

    /// Provider identity hues. Identity only — never status.
    static func tint(_ name: String) -> Color {
        switch name {
        case "orange": return Color(nsColor: .systemOrange)
        case "indigo": return Color(nsColor: .systemIndigo)
        case "mint": return Color(nsColor: .systemTeal)
        case "purple": return Color(nsColor: .systemPurple)
        default: return Color(nsColor: .systemBlue)
        }
    }

    /// Status colour, from the semantic system palette so it tracks the user's
    /// appearance and accessibility settings (including increased contrast).
    static func color(for severity: Severity) -> Color {
        Brand.statusColor(for: severity)
    }

    /// An adaptive opaque-biased fill keeps cards distinct over desktop imagery
    /// in both appearances without turning the panel into stacked glass.
    static let cardFill = Color(nsColor: .controlBackgroundColor).opacity(0.64)
    static let cardStroke = Color(nsColor: .separatorColor)
    static let meterTrack = Color(nsColor: .secondaryLabelColor).opacity(0.24)
}

// MARK: - Motion

/// Tracks whether motion should be reduced, from the system setting *or* the
/// app's own override, and hands out animations accordingly.
@MainActor
final class MotionSettings: ObservableObject {
    @Published private(set) var systemReducesMotion: Bool
    /// Mirrors `Preferences.reduceMotionOverride`.
    @Published var userReducesMotion: Bool = false

    var reduceMotion: Bool { systemReducesMotion || userReducesMotion }

    private var observer: NSObjectProtocol?

    init() {
        systemReducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.systemReducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// The spring used for size and position changes. Nil when motion is
    /// reduced, which makes every `withAnimation` call site a no-op instead of
    /// needing its own conditional.
    var geometry: Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86)
    }

    /// A shorter spring for small in-place changes (hover, chips, toggles).
    var accent: Animation? {
        reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.9)
    }

    /// Content swaps. Reduced motion still gets a fade, which conveys the change
    /// without any travel.
    var content: Animation? {
        reduceMotion ? .easeInOut(duration: 0.12) : .easeInOut(duration: 0.2)
    }

    /// Transition for content that replaces other content.
    var contentTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 6)),
                removal: .opacity
            )
    }
}
