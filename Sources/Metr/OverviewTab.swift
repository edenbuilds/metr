import AppKit
import SwiftUI
import MetrKit

struct OverviewTab: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            if store.onboarding.showsChecklist {
                ChecklistCard()
            }

            if store.visibleProviders.isEmpty {
                Card {
                    EmptyStateView(
                        symbolName: store.snapshot.providers.isEmpty ? "tray" : "eye.slash",
                        title: store.snapshot.providers.isEmpty ? "No providers reporting" : "Everything is hidden",
                        message: store.snapshot.providers.isEmpty
                            ? "Nothing was found on the last refresh. Try demo data to see how the panel behaves."
                            : "You have hidden every provider. Turn one back on to see its usage.",
                        actionLabel: store.snapshot.providers.isEmpty ? "Use demo data" : "Open Preferences",
                        action: {
                            if store.snapshot.providers.isEmpty {
                                store.preferences.dataSource = .mock
                            } else {
                                store.isShowingPreferences = true
                            }
                        }
                    )
                }
            } else {
                ForEach(store.visibleProviders) { provider in
                    ProviderCard(provider: provider)
                }
                costRow
            }

            if store.onboarding.shouldShow(.measuredVsEstimated) {
                HintBanner(hint: .measuredVsEstimated) { store.dismiss(.measuredVsEstimated) }
            }
        }
    }

    @ViewBuilder
    private var costRow: some View {
        if let total = store.totalEstimatedCost {
            HStack(spacing: Theme.Space.snug) {
                Image(systemName: "chart.line.uptrend.xyaxis").imageScale(.small)
                Text("Estimated today")
                Spacer()
                Text(Formatters.currency(total)).fontWeight(.semibold).monospacedDigit()
                ConfidenceTag(
                    confidence: .estimated,
                    assumption: store.visibleProviders.compactMap(\.costAssumption).first
                )
            }
            .font(Theme.Text.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Estimated cost today, \(Formatters.currency(total)). Estimated, not billing data.")
        }
    }
}

// MARK: - Provider card

struct ProviderCard: View {
    let provider: ProviderSnapshot
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var motion: MotionSettings
    @State private var hovering = false

    private var severity: Severity { provider.severity(thresholds: store.preferences.thresholds) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                header

                if provider.state.hasNoData {
                    unavailableBody
                } else {
                    meterBlock
                    if provider.quotaPeriods.count > 1 { additionalWindows }
                    resetBlock
                    if let contextFraction = provider.contextFraction { contextBlock(contextFraction) }
                    quickActions
                }
            }
        }
        .scaleEffect(hovering ? 1.006 : 1)
        .shadow(color: .black.opacity(hovering ? 0.08 : 0), radius: 7, y: 2)
        .onHover { value in
            withAnimation(motion.accent) { hovering = value }
        }
    }

    private var additionalWindows: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            ForEach(provider.quotaPeriods.dropFirst()) { period in
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    HStack {
                        Text(period.label)
                            .font(Theme.Text.captionTight.weight(.medium))
                        Spacer()
                        Text(Formatters.percent(period.usedFraction))
                            .font(Theme.Text.captionTight.weight(.semibold).monospacedDigit())
                        if let reset = period.resetAt {
                            Text("· resets in \(Formatters.countdown(reset.timeIntervalSince(store.now)))")
                                .font(Theme.Text.captionTight.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Meter(
                        fraction: period.usedFraction,
                        tint: Theme.tint(provider.identity.tintName),
                        severity: Severity.forFraction(period.usedFraction, thresholds: store.preferences.thresholds),
                        thresholds: store.preferences.thresholds,
                        showsThresholds: false
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Additional \(provider.identity.name) limits")
    }

    private var header: some View {
        HStack(spacing: Theme.Space.snug) {
            Circle()
                .fill(Theme.tint(provider.identity.tintName))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(provider.identity.name)
                .font(Theme.Text.heading)
            if let model = provider.model {
                Text(model)
                    .font(Theme.Text.captionTight)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(nsColor: .labelColor).opacity(0.07)))
            }
            Spacer(minLength: Theme.Space.tight)
            StatusPill(
                symbolName: provider.state.isTrustworthy ? severity.symbolName : provider.state.symbolName,
                label: provider.state.isTrustworthy ? severity.label : provider.state.label,
                severity: provider.state.isTrustworthy ? severity : provider.state.severity
            )
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var unavailableBody: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Text(provider.state.explanation)
                .font(Theme.Text.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if case .authenticationRequired = provider.state {
                Button("How to connect this provider") { store.isShowingPreferences = true }
                    .buttonStyle(.link)
                    .font(Theme.Text.captionTight)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(provider.identity.name) unavailable. \(provider.state.explanation)")
    }

    private var meterBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.snug) {
                Text(provider.usedFraction.map { Formatters.percent($0) } ?? "—")
                    .font(Theme.Text.metricLarge)
                Text(provider.usedLabel ?? "used")
                    .font(Theme.Text.captionTight)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                ConfidenceTag(confidence: provider.confidence, assumption: provider.sourceDescription)
            }

            Meter(
                fraction: provider.usedFraction ?? 0,
                tint: Theme.tint(provider.identity.tintName),
                severity: severity,
                thresholds: store.preferences.thresholds
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.identity.name) usage")
        .accessibilityValue("\(provider.usedFraction.map { Formatters.percent($0) } ?? "unknown"), \(severity.label). \(provider.sourceDescription)")
    }

    /// Reset time in the display timezone, with the provider's own timezone
    /// underneath whenever the two differ.
    private var resetBlock: some View {
        let reset = store.resetDescription(for: provider)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Theme.Space.snug) {
                Text(provider.window.cadence.label)
                    .font(Theme.Text.captionTight)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.Space.tight)
                Text("Resets \(reset.primary)")
                    .font(Theme.Text.captionTight.weight(.medium).monospacedDigit())
                Text("· \(reset.countdown)")
                    .font(Theme.Text.captionTight.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Theme.Space.tight) {
                Text(store.location.inlinePhrase)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                if let providerTime = reset.providerTime {
                    Text("· \(providerTime) for \(provider.identity.name)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.identity.name) window")
        .accessibilityValue(reset.accessibleDescription)
    }

    private func contextBlock(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack {
                Text("Context")
                    .font(Theme.Text.captionTight)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Formatters.compactCount(provider.contextUsed ?? 0)) of \(Formatters.compactCount(provider.contextBudget ?? 0))")
                    .font(Theme.Text.captionTight.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Meter(
                fraction: fraction,
                tint: Brand.olive,
                severity: Severity.forFraction(fraction, thresholds: store.preferences.thresholds),
                thresholds: store.preferences.thresholds,
                showsThresholds: false
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context budget for \(provider.identity.name)")
        .accessibilityValue("\(Formatters.percent(fraction)) used, \(Formatters.compactCount(provider.contextUsed ?? 0)) of \(Formatters.compactCount(provider.contextBudget ?? 0)) tokens")
    }

    /// Quick actions open the thing the row is about, rather than making the
    /// user go and find it.
    private var quickActions: some View {
        HStack(spacing: Theme.Space.snug) {
            Button {
                store.historyProviderID = provider.id
                store.selectedTab = .history
            } label: {
                Label("Weekly details", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 9))
            }
            .buttonStyle(.link)
            .help("See weekly usage and recent \(provider.identity.name) sessions")

            let latest = store.snapshot.sessions.first { $0.providerID == provider.id }
            if let latest, let directory = latest.workingDirectory {
                Button {
                    QuickActions.openInTerminal(path: directory)
                } label: {
                    Label("Open in Terminal", systemImage: "terminal")
                        .font(.system(size: 9))
                }
                .buttonStyle(.link)
                .help("Open a Terminal window at \(directory)")

                Button {
                    QuickActions.revealInFinder(path: directory)
                } label: {
                    Label("Reveal", systemImage: "folder")
                        .font(.system(size: 9))
                }
                .buttonStyle(.link)
                .help("Show \(directory) in the Finder")
            }
            Spacer()
        }
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Quick actions

enum QuickActions {
    /// Open Terminal at a path. Fails quietly: a stale path from a session file
    /// is a normal thing to encounter, not an error worth interrupting anyone.
    static func openInTerminal(path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([URL(fileURLWithPath: expanded)], withApplicationAt: terminal, configuration: config)
    }

    static func revealInFinder(path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expanded)
    }
}
