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
            && !store.preferences.pinned
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
        return ZStack(alignment: .bottomTrailing) {
            MetrCatLogo(size: 34)
            if status.isKnown {
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0, level))))
                    .stroke(Theme.color(for: status.severity), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1)
            }
        }
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

/// The minimized dock: a small, glanceable control surface with one affordance
/// per provider. It stays useful while minimized and opens the full panel with
/// one click, matching the edge-popover language of the reference.
struct RailView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var motion: MotionSettings
    @EnvironmentObject private var metrics: PanelMetrics
    @Environment(\.panelActions) private var actions

    @State private var hovering = false
    @State private var hoveredProvider: String?

    private var isVertical: Bool { store.preferences.mode != .top }

    var body: some View {
        Group {
            if isVertical {
                HStack(spacing: Theme.Space.base) {
                    if store.preferences.edge == .trailing {
                        if hovering { peekCard }
                        Spacer(minLength: 0)
                        dockContent
                    } else {
                        dockContent
                        Spacer(minLength: 0)
                        if hovering { peekCard }
                    }
                }
                .padding(.horizontal, Theme.Space.snug)
            } else {
                VStack(spacing: Theme.Space.snug) {
                    if hovering { peekCard }
                    dockContent
                }
                .padding(.vertical, Theme.Space.snug)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                withAnimation(motion.accent) { self.hovering = true }
                actions.setRailHover(true)
            case .ended:
                withAnimation(motion.accent) { self.hovering = false }
                actions.setRailHover(false)
            }
        }
        .animation(motion.accent, value: hovering)
        .accessibilityElement()
        .accessibilityLabel("\(Brand.name) usage dock")
        .accessibilityHint("Choose a provider to open the detailed usage panel")
    }

    private var dockSurface: some ShapeStyle {
        Color(nsColor: .controlBackgroundColor).opacity(0.98)
    }

    private var dockContent: some View {
        VStack(spacing: Theme.Space.tight) {
            ForEach(store.visibleProviders) { provider in dockItem(provider) }
        }
        .padding(.vertical, isVertical ? Theme.dockSidePadding : 0)
        .padding(.horizontal, isVertical ? 0 : Theme.Space.snug)
        .background(dockSurface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(hovering ? 0.28 : 0.2), radius: hovering ? 16 : 10, y: 4)
        .overlay(alignment: isVertical ? .top : .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.28))
                .frame(width: isVertical ? 3 : 24, height: isVertical ? 24 : 3)
                .padding(isVertical ? .top : .leading, 8)
                .help("Drag to move metr")
                .accessibilityLabel("Drag to move metr dock")
        }
        // Track the real control surface as well as the surrounding window.
        // This keeps hover reliable while the panel grows to reveal the peek.
        .onHover { value in
            withAnimation(motion.accent) { hovering = value }
            actions.setRailHover(value)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in actions.dragRailChanged(value.translation) }
                .onEnded { _ in actions.dragRailEnded() }
        )
    }

    @ViewBuilder
    private var peekCard: some View {
        if let provider = hoveredProvider.flatMap({ id in store.visibleProviders.first { $0.id == id } }) ?? store.focusProvider {
            let fraction = provider.usedFraction
            let reset = store.resetDescription(for: provider)
            let showsRemaining = store.preferences.usageDisplay == .remaining
            let displayFraction = fraction.map { showsRemaining ? 1 - $0 : $0 }
            let spokenFraction = displayFraction.map(Formatters.percent) ?? "unknown"
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                HStack(spacing: Theme.Space.snug) {
                    ProviderLogo(identity: provider.identity, size: 18)
                    Text(provider.identity.name).font(Theme.Text.heading)
                    Spacer(minLength: 0)
                    Text(provider.state.label).font(Theme.Text.fine).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(displayFraction.map(Formatters.percent) ?? "—")
                        .font(Theme.Text.metricLarge)
                    Text(showsRemaining ? "remaining" : "used")
                        .font(Theme.Text.captionTight).foregroundStyle(.secondary)
                    Spacer()
                    if let resetAt = provider.quotaPeriods.first?.resetAt {
                        Text("Resets \(Formatters.countdown(resetAt.timeIntervalSince(store.now)))")
                            .font(Theme.Text.fine.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Meter(
                    fraction: displayFraction ?? 0,
                    tint: Theme.tint(provider.identity.tintName),
                    severity: provider.severity(thresholds: store.preferences.thresholds),
                    thresholds: store.preferences.thresholds,
                    showsThresholds: false
                )
                if let weekly = provider.quotaPeriods.dropFirst().first {
                    HStack {
                        Text(weekly.label).font(Theme.Text.fine).foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatters.percent(weekly.usedFraction)).font(Theme.Text.fine.monospacedDigit())
                    }
                }
                Text(provider.confidence == .measured ? "Provider limit" : "Local activity estimate")
                    .font(Theme.Text.fine)
                    .foregroundStyle(.tertiary)
            }
            .padding(Theme.Space.roomy)
            .frame(width: 222, alignment: .leading)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.cardStroke.opacity(0.7), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
            .transition(motion.reduceMotion ? .opacity : .scale(scale: 0.96, anchor: store.preferences.edge == .trailing ? .trailing : .leading).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Quick \(provider.identity.name) status")
            .accessibilityValue("\(spokenFraction) \(showsRemaining ? "remaining" : "used"). \(reset.primary). \(reset.countdown).")
        }
    }

    private func dockItem(_ provider: ProviderSnapshot) -> some View {
        let fraction = provider.usedFraction ?? 0
        let tint = Brand.providerColor(for: provider.identity)
        let isHovered = hoveredProvider == provider.id
        return Button {
            actions.setExpanded(true)
        } label: {
            Group {
                if isVertical {
                    VStack(spacing: 2) { badge(provider, tint: tint, fraction: fraction); metric(provider) }
                } else {
                    HStack(spacing: 4) { badge(provider, tint: tint, fraction: fraction); metric(provider) }
                }
            }
            .frame(width: isVertical ? 62 : 80, height: isVertical ? 52 : 52)
            .background(Color.primary.opacity(isHovered ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(isHovered ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(motion.accent) { hoveredProvider = value ? provider.id : nil }
        }
        .help("Open \(provider.identity.name) usage")
        .accessibilityElement()
        .accessibilityLabel("\(provider.identity.name), \(store.compactValue(for: provider))")
        .accessibilityHint("Opens detailed usage")
        .accessibilityAddTraits(.isButton)
    }

    private func badge(_ provider: ProviderSnapshot, tint: Color, fraction: Double) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.14), lineWidth: 3)
            Circle().trim(from: 0, to: CGFloat(min(1, max(0, fraction))))
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            ProviderLogo(identity: provider.identity)
        }
        .frame(width: 30, height: 30)
    }

    private func metric(_ provider: ProviderSnapshot) -> some View {
        Text(store.compactValue(for: provider))
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.primary)
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
                ProviderLogo(identity: provider.identity, size: 13)
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
