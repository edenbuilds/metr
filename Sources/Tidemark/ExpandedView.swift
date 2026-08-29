import SwiftUI
import TidemarkKit

/// The expanded card. Answers "what should I do next?" before it shows detail.
struct ExpandedView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var motion: MotionSettings
    @EnvironmentObject private var metrics: PanelMetrics
    @Environment(\.panelActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            if !store.onboarding.hasCompletedSetup {
                SetupCard()
            } else {
                headline
                TabStrip(selection: $store.selectedTab)
                content
                FooterView()
            }
        }
        .padding(.horizontal, Theme.Space.roomy)
        .padding(.bottom, Theme.Space.roomy)
        .animation(motion.content, value: store.selectedTab)
        .animation(motion.content, value: store.onboarding.hasCompletedSetup)
    }

    // MARK: Headline

    /// The one sentence that earns the panel its place on screen.
    private var headline: some View {
        let h = store.headline
        return HStack(alignment: .top, spacing: Theme.Space.base) {
            Image(systemName: h.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.color(for: h.severity))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(h.title)
                    .font(Theme.Text.heading)
                Text(h.detail)
                    .font(Theme.Text.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.color(for: h.severity).opacity(0.09))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(h.title). \(h.detail)")
    }

    @ViewBuilder
    private var content: some View {
        // The panel is height-clamped to the screen, so tall content scrolls
        // rather than growing past the edge of a small display.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Space.base) {
                switch store.selectedTab {
                case .overview: OverviewTab()
                case .history: HistoryTab()
                case .insights: InsightsTab()
                }
            }
        }
        .frame(maxHeight: max(120, metrics.maxContentHeight - 230))
        .scrollDisabledIfPossible(false)
    }
}

private extension View {
    /// `scrollDisabled` only exists from macOS 13.0; this keeps the call site tidy.
    @ViewBuilder func scrollDisabledIfPossible(_ disabled: Bool) -> some View {
        if #available(macOS 13.0, *) { self.scrollDisabled(disabled) } else { self }
    }
}

// MARK: - Footer

struct FooterView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.panelActions) private var actions

    var body: some View {
        VStack(spacing: Theme.Space.snug) {
            if store.onboarding.shouldShow(.dragToMove) {
                HintBanner(hint: .dragToMove) { store.dismiss(.dragToMove) }
            }

            // Placement is a real segmented control rather than a button whose
            // label flips — the previous version made you read it to know state.
            Picker("", selection: $store.preferences.mode) {
                ForEach(PresentationMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .help("Move Tidemark between the top of the screen and the side edge")
            .accessibilityLabel("Panel placement")

            HStack(spacing: Theme.Space.snug) {
                Toggle(isOn: $store.preferences.autoHide) {
                    Label("Auto-hide", systemImage: store.preferences.autoHide ? "eye" : "eye.slash")
                        .font(Theme.Text.captionTight)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(store.preferences.autoHide
                      ? "On — collapses to a thin rail a few seconds after you click away"
                      : "Off — stays open until you minimise it")

                Spacer()

                if store.isInQuietHours {
                    StatusPill(symbolName: "moon.zzz", label: "Quiet", severity: .nominal)
                        .help("Quiet hours are on, so alerts are held back")
                }

                Button {
                    store.isShowingPreferences = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(Theme.Text.captionTight)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Preferences (⌘,)")
            }
        }
    }
}

enum ScreenEdgeSymbol {
    static let top = "rectangle.topthird.inset.filled"
    static let side = "rectangle.trailingthird.inset.filled"
}
