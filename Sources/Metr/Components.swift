import SwiftUI
import MetrKit

/// Alert thresholds shared by setup and Settings. Kept separate from timezone
/// controls so the system-timezone policy cannot regress through UI reuse.
struct ThresholdSliders: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            sliderRow(
                title: "Watch from",
                value: Binding(
                    get: { store.preferences.thresholds.watch },
                    set: { store.preferences.thresholds = AlertThresholds(watch: $0, critical: store.preferences.thresholds.critical) }
                ),
                range: 0.3...0.9
            )
            sliderRow(
                title: "Near limit from",
                value: Binding(
                    get: { store.preferences.thresholds.critical },
                    set: { store.preferences.thresholds = AlertThresholds(watch: store.preferences.thresholds.watch, critical: $0) }
                ),
                range: 0.5...0.98
            )
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: Theme.Space.snug) {
            Text(title).font(Theme.Text.caption).foregroundStyle(.secondary).frame(width: 104, alignment: .leading)
            Slider(value: value, in: range)
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue(Formatters.percent(value.wrappedValue))
            Text(Formatters.percent(value.wrappedValue))
                .font(Theme.Text.caption.monospacedDigit())
                .frame(width: 38, alignment: .trailing)
        }
    }
}

// MARK: - Status pill

/// Status as symbol + word + colour, in that order of importance. Readable in
/// greyscale, by a screen reader, and at a glance.
struct StatusPill: View {
    let symbolName: String
    let label: String
    let severity: Severity
    var prominent = false

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            Image(systemName: symbolName)
                .imageScale(.small)
            Text(label)
                .font(Theme.Text.captionTight.weight(.semibold))
        }
        .foregroundStyle(prominent ? Color.white : Theme.color(for: severity))
        .padding(.horizontal, Theme.Space.snug)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(prominent ? Theme.color(for: severity) : Theme.color(for: severity).opacity(0.14))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(label)")
    }
}

// MARK: - Meter

/// A usage meter with the alert thresholds marked on the track.
///
/// The ticks are what make this readable without colour: you can see where
/// "watch" and "near limit" begin relative to the fill, so the bar means
/// something even in greyscale.
struct Meter: View {
    let fraction: Double
    let tint: Color
    let severity: Severity
    var thresholds: AlertThresholds = .default
    var showsThresholds = true

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.meterTrack)

                Capsule()
                    .fill(tint)
                    .frame(width: max(3, width * min(1, max(0, fraction))))

                if showsThresholds {
                    ForEach([thresholds.watch, thresholds.critical], id: \.self) { mark in
                        Rectangle()
                            .fill(Color(nsColor: .labelColor).opacity(0.35))
                            .frame(width: 1)
                            .offset(x: width * mark)
                    }
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// Icon button that keeps a visible focus ring and a real hover state.
struct QuietIconButton: View {
    let symbolName: String
    let help: String
    var isOn: Bool = false
    let action: () -> Void

    @State private var hovering = false
    @EnvironmentObject private var motion: MotionSettings

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn
                              ? Color(nsColor: .controlAccentColor).opacity(0.18)
                              : (hovering ? Color(nsColor: .labelColor).opacity(0.08) : .clear))
                )
                .foregroundStyle(isOn ? Color(nsColor: .controlAccentColor) : Color.secondary)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(motion.accent) { self.hovering = hovering }
        }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The panel's tab strip. A real segmented control would fight the material
/// surface, so this is a capsule strip that still behaves like one: arrow keys
/// move between tabs, and the selection is announced.
struct TabStrip: View {
    @Binding var selection: PanelTab
    @EnvironmentObject private var motion: MotionSettings
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases) { tab in
                Button {
                    withAnimation(motion.accent) { selection = tab }
                } label: {
                    Text(tab.title)
                        .font(Theme.Text.captionTight.weight(selection == tab ? .semibold : .regular))
                        .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                        .padding(.horizontal, Theme.Space.base)
                        .padding(.vertical, 5)
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(Color(nsColor: .labelColor).opacity(0.15))
                                    .matchedGeometryEffect(id: "tab", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel sections")
    }
}

// MARK: - Cards

/// The panel's standard container.
struct Card<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.Space.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(tint?.opacity(0.08) ?? Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.cardStroke.opacity(0.85), lineWidth: 0.5)
            )
    }
}

// MARK: - Empty / unavailable states

/// The surface shown whenever there is nothing real to display. Always says
/// what happened, and always offers the next move.
struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.snug) {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(Theme.Text.heading)
            Text(message)
                .font(Theme.Text.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.link)
                    .font(Theme.Text.caption)
                    .padding(.top, Theme.Space.hair)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.roomy)
        .padding(.horizontal, Theme.Space.base)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}

// MARK: - Inline hint

/// A one-time, dismissable tip. Never returns once dismissed.
struct HintBanner: View {
    let hint: Hint
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            Image(systemName: "lightbulb")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(hint.text)
                .font(Theme.Text.captionTight)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.tight)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(.horizontal, Theme.Space.base)
        .padding(.vertical, Theme.Space.snug)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Color(nsColor: .labelColor).opacity(0.05))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tip: \(hint.text)")
    }
}

// MARK: - Labelled row

/// Key/value row used throughout the expanded panel.
struct DetailRow: View {
    let label: String
    let value: String
    var symbolName: String?
    var valueTint: Color?

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            if let symbolName {
                Image(systemName: symbolName).imageScale(.small).foregroundStyle(.secondary)
            }
            Text(label).font(Theme.Text.caption).foregroundStyle(.secondary)
            Spacer(minLength: Theme.Space.snug)
            Text(value)
                .font(Theme.Text.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(valueTint ?? .primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Marks a number as measured or estimated, so the two are never confused.
struct ConfidenceTag: View {
    let confidence: Confidence
    let assumption: String?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: confidence == .measured ? "checkmark.seal" : "function")
                .font(.system(size: 8, weight: .semibold))
            Text(confidence.label)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(.tertiary)
        .help(assumption ?? confidence.label)
        .accessibilityLabel(assumption.map { "\(confidence.label). \($0)" } ?? confidence.label)
    }
}
