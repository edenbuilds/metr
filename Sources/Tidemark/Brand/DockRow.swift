import SwiftUI

/// Shared hover position for a Dock-style row, in the row's own coordinates.
@MainActor
final class DockHoverState: ObservableObject {
    @Published var location: CGFloat?
}

/// A row of icon actions that magnifies like the Dock: the item under the
/// pointer grows most, its neighbours grow a little, everything else rests.
///
/// The magnification is distance-based rather than per-item hover, which is what
/// makes it feel continuous instead of steppy.
struct DockRow<Content: View>: View {
    @ViewBuilder var content: Content
    @StateObject private var hover = DockHoverState()
    @EnvironmentObject private var motion: MotionSettings

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            content
        }
        .environmentObject(hover)
        .coordinateSpace(name: DockMetrics.space)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            hover.location = point.x
                        case .ended:
                            withAnimation(motion.accent) { hover.location = nil }
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        )
    }
}

enum DockMetrics {
    static let space = "dock-row"
    /// How far the influence of the pointer reaches, in points.
    static let falloff: CGFloat = 46
    static let maxScale: CGFloat = 1.30
    static let maxLift: CGFloat = 3
}

/// One magnifying item in a `DockRow`.
struct DockItem<Content: View>: View {
    @ViewBuilder var content: Content

    @EnvironmentObject private var hover: DockHoverState
    @EnvironmentObject private var motion: MotionSettings
    @State private var centre: CGFloat = 0

    private var magnification: CGFloat {
        guard !motion.reduceMotion, let location = hover.location else { return 0 }
        let distance = abs(location - centre)
        guard distance < DockMetrics.falloff else { return 0 }
        // Cosine falloff: smooth at both ends, no visible seam where it stops.
        return (cos(distance / DockMetrics.falloff * .pi) + 1) / 2
    }

    var body: some View {
        content
            .scaleEffect(1 + (DockMetrics.maxScale - 1) * magnification, anchor: .bottom)
            .offset(y: -DockMetrics.maxLift * magnification)
            .background(
                GeometryReader { proxy in
                    Color.clear.onAppear {
                        centre = proxy.frame(in: .named(DockMetrics.space)).midX
                    }
                    .onChange(of: proxy.frame(in: .named(DockMetrics.space)).midX) { newValue in
                        centre = newValue
                    }
                }
            )
            .animation(motion.reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7), value: magnification)
    }
}

// MARK: - Micro-interactions

/// Press feedback: a quick squash on mouse-down, a spring back on release.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    @EnvironmentObject private var motion: MotionSettings

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(motion.reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
            .animation(motion.reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

/// A number that rolls when it changes, rather than snapping.
struct RollingNumber: View {
    let value: String
    var font: Font = Theme.Text.metric
    @EnvironmentObject private var motion: MotionSettings

    var body: some View {
        Text(value)
            .font(font)
            .contentTransition(.numericText())
            .animation(motion.reduceMotion ? nil : .snappy(duration: 0.28), value: value)
    }
}

/// Wraps content so it gently breathes when a condition holds — used to draw
/// the eye to something that needs attention, without flashing.
struct AttentionPulse: ViewModifier {
    var active: Bool
    @EnvironmentObject private var motion: MotionSettings
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && on && !motion.reduceMotion ? 1.04 : 1)
            .animation(
                active && !motion.reduceMotion
                    ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                    : nil,
                value: on
            )
            .onAppear { on = true }
    }
}

extension View {
    func attentionPulse(_ active: Bool) -> some View { modifier(AttentionPulse(active: active)) }
}
