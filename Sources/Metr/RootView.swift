import SwiftUI
import MetrKit

/// Reports the measured height of the card back to the window layer.
private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Routes between the three presentations: rail, compact pill, expanded card.
struct RootView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var motion: MotionSettings
    @EnvironmentObject private var metrics: PanelMetrics
    @Environment(\.panelActions) private var actions

    private var isRailed: Bool {
        !store.preferences.expanded && store.preferences.autoHide
            && !store.preferences.pinned && !metrics.railHovered
    }

    var body: some View {
        Group {
            if isRailed {
                RailView()
            } else {
                card
                    .padding(Theme.shadowMargin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPreferenceChange(HeightKey.self) { height in
            guard height > 0, !isRailed else { return }
            actions.reportHeight(height + Theme.shadowMargin * 2)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HeaderView()
            if store.preferences.expanded {
                ExpandedView()
                    .transition(motion.contentTransition)
            } else {
                CompactView()
                    .transition(motion.contentTransition)
            }
        }
        .frame(width: CGFloat(store.preferences.panelWidth.points))
        // Material + ordered-dither wash + film grain, so the surface reads as
        // printed rather than as a flat digital panel.
        .panelSurface()
        .shadow(color: .black.opacity(0.22), radius: 18, y: 7)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
            }
        )
        .animation(motion.geometry, value: store.preferences.expanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("metr")
    }
}

// MARK: - Header

struct HeaderView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var motion: MotionSettings
    @Environment(\.panelActions) private var actions

    @State private var wavePhase: Double = 0

    var body: some View {
        HStack(spacing: Theme.Space.base) {
            mark

            VStack(alignment: .leading, spacing: 0) {
                Text(Brand.name)
                    .font(Theme.Text.title)
                Text(store.lastRefresh.map { Formatters.relativeUpdated($0, now: store.now) } ?? "not read yet")
                .font(Theme.Text.captionTight)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Updated \(store.lastRefresh.map { Formatters.relativeUpdated($0, now: store.now) } ?? "never").")
            }

            Spacer(minLength: Theme.Space.snug)

            // Dock-style action row. Every control has a visible chip so it can
            // be found without hunting, and magnifies under the pointer.
            DockRow {
                DockItem {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.75)
                            .frame(width: 30, height: 30)
                            .accessibilityLabel("Refreshing")
                    } else {
                        ChipButton(symbolName: "arrow.clockwise", help: "Refresh now (⌘R)") {
                            Task { await store.refresh() }
                        }
                    }
                }
                DockItem {
                    ChipButton(
                        symbolName: store.preferences.pinned ? "pin.fill" : "pin",
                        help: store.preferences.pinned ? "Unpin — allow auto-collapse" : "Pin open — stop it collapsing",
                        isOn: store.preferences.pinned
                    ) {
                        store.preferences.pinned.toggle()
                    }
                }
                DockItem {
                    ChipButton(
                        symbolName: store.preferences.expanded ? "minus" : "chevron.up",
                        help: store.preferences.expanded ? "Minimise to the compact bar (Esc)" : "Expand"
                    ) {
                        actions.setExpanded(!store.preferences.expanded)
                    }
                }
                DockItem {
                    ChipButton(symbolName: "xmark", help: "Hide metr — reopen from the menu bar (⌘W)") {
                        actions.close()
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.roomy)
        .padding(.top, Theme.Space.roomy)
        .padding(.bottom, store.preferences.expanded ? Theme.Space.base : Theme.Space.roomy)
        .onAppear { startWave() }
    }

    /// The mascot doubles as the status indicator: its water level is the usage
    /// level and its eyes change with severity.
    private var mark: some View {
        let status = store.headerStatus
        let level = store.focusProvider?.usedFraction ?? 0.15
        return MetrMark(
            level: status.isKnown ? level : 0.1,
            severity: status.severity,
            isKnown: status.isKnown,
            foreground: Brand.bone,
            background: Brand.charcoal,
            phase: wavePhase
        )
        .frame(width: 34, height: 34)
        .attentionPulse(status.isKnown && status.severity == .critical)
        .help("\(Brand.name) — \(status.label)")
        .accessibilityElement()
        .accessibilityLabel("Overall status: \(status.label)")
    }

    /// A slow, continuous drift. One animation for the life of the panel, not a
    /// per-frame timer, so it costs effectively nothing.
    private func startWave() {
        guard !motion.reduceMotion else { return }
        withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
            wavePhase = .pi * 2
        }
    }
}

/// An icon button with a permanent, visible chip. The previous version drew no
/// background until hover, which made the controls genuinely hard to find.
struct ChipButton: View {
    let symbolName: String
    let help: String
    var isOn: Bool = false
    let action: () -> Void

    @State private var hovering = false
    @EnvironmentObject private var motion: MotionSettings

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(hovering ? 0.9 : 0.45), lineWidth: 0.5)
                )
                .foregroundStyle(isOn ? Brand.burntOrange : Color.primary.opacity(0.75))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in withAnimation(motion.accent) { self.hovering = hovering } }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var fill: Color {
        if isOn { return Brand.burntOrange.opacity(0.16) }
        return Color(nsColor: .labelColor).opacity(hovering ? 0.12 : 0.06)
    }
}

// MARK: - Rail

/// The collapsed edge rail. Thin enough to ignore, but capped with the mark so
/// it is recognisably Metr rather than a stray line on the screen edge.
struct RailView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var motion: MotionSettings
    @EnvironmentObject private var metrics: PanelMetrics
    @Environment(\.panelActions) private var actions

    @State private var hovering = false

    private var isVertical: Bool { store.preferences.mode != .top }

    var body: some View {
        let status = store.headerStatus
        let thickness = hovering ? Theme.railHoverThickness : Theme.railThickness
        let tint = status.isKnown ? Brand.statusColor(for: status.severity) : Brand.warmGray

        ZStack {
            Capsule()
                .fill(tint.opacity(hovering ? 1 : 0.82))
                .frame(
                    width: isVertical ? thickness : Theme.railLength,
                    height: isVertical ? Theme.railLength : thickness
                )
                .overlay(
                    Capsule()
                        .fill(Brand.bone.opacity(0.35))
                        .frame(
                            width: isVertical ? thickness : Theme.railLength * fillFraction,
                            height: isVertical ? Theme.railLength * fillFraction : thickness
                        ),
                    alignment: isVertical ? .bottom : .leading
                )
                .shadow(color: .black.opacity(0.22), radius: 5, y: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(motion.accent) { self.hovering = hovering }
            actions.setRailHover(hovering)
        }
        .onTapGesture { actions.setExpanded(true) }
        .animation(motion.accent, value: hovering)
        .help("\(Brand.name) — \(status.label). Click to open.")
        .accessibilityElement()
        .accessibilityLabel("\(Brand.name), \(status.label)")
        .accessibilityHint("Opens the usage panel")
        .accessibilityAddTraits(.isButton)
    }

    /// The rail itself shows the level, so the collapsed state still says something.
    private var fillFraction: CGFloat {
        CGFloat(min(1, max(0.05, store.focusProvider?.usedFraction ?? 0.05)))
    }
}

// MARK: - Compact

/// The collapsed-but-visible state. One deliberate metric per provider plus a
/// status word — not a squeezed copy of the expanded view.
struct CompactView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        HStack(spacing: Theme.Space.roomy) {
            if store.visibleProviders.isEmpty {
                Text(store.snapshot.providers.isEmpty ? "No data yet" : "All providers hidden")
                    .font(Theme.Text.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(store.visibleProviders) { provider in
                    compactMetric(provider)
                }
                Spacer(minLength: Theme.Space.snug)
                StatusPill(
                    symbolName: store.headerStatus.symbol,
                    label: store.headerStatus.label,
                    severity: store.headerStatus.severity
                )
            }
        }
        .padding(.horizontal, Theme.Space.roomy)
        .padding(.bottom, Theme.Space.roomy)
    }

    private func compactMetric(_ provider: ProviderSnapshot) -> some View {
        let severity = provider.severity(thresholds: store.preferences.thresholds)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Space.tight) {
                Circle()
                    .fill(Theme.tint(provider.identity.tintName))
                    .frame(width: 6, height: 6)
                Text(provider.identity.name)
                    .font(Theme.Text.captionTight)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 3) {
                Text(store.compactValue(for: provider))
                    .font(Theme.Text.metric)
                if severity != .nominal {
                    Image(systemName: severity.symbolName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.color(for: severity))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.identity.name), \(store.preferences.compactMetric.title) \(store.compactValue(for: provider)), \(severity.label)")
    }
}
