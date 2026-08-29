import SwiftUI
import MetrKit

/// First-run setup, shown inside the panel rather than in a separate window.
///
/// Every step is the real control, wired to the real setting. Finishing setup
/// means the app is actually configured — there is no "now go to preferences
/// and do it properly" afterwards.
struct SetupCard: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var motion: MotionSettings

    private var step: SetupStep { store.onboarding.currentStep }
    private var stepIndex: Int { SetupStep.allCases.firstIndex(of: step) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            header
            body(for: step)
                .transition(motion.contentTransition)
                .id(step)
            controls
        }
        .padding(Theme.Space.base)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(nsColor: .controlAccentColor).opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Color(nsColor: .controlAccentColor).opacity(0.25), lineWidth: 0.5)
        )
        .animation(motion.content, value: step)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup, step \(stepIndex + 1) of \(SetupStep.allCases.count)")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Space.base) {
            Image(systemName: step.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(Theme.Text.heading)
                Text(step.summary)
                    .font(Theme.Text.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("\(stepIndex + 1)/\(SetupStep.allCases.count)")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func body(for step: SetupStep) -> some View {
        switch step {
        case .placement: placementStep
        case .dataSource: dataSourceStep
        case .alerts: alertsStep
        }
    }

    // MARK: Steps

    private var placementStep: some View {
        VStack(spacing: Theme.Space.snug) {
            ForEach(PresentationMode.allCases, id: \.self) { mode in
                ChoiceRow(
                    title: mode.title,
                    detail: placementDetail(mode),
                    symbolName: mode.symbolName,
                    isSelected: store.preferences.mode == mode
                ) {
                    store.preferences.mode = mode
                }
            }
        }
    }

    private var dataSourceStep: some View {
        VStack(spacing: Theme.Space.snug) {
            ForEach(DataSourceKind.allCases, id: \.self) { kind in
                ChoiceRow(
                    title: kind.title,
                    detail: kind.explanation,
                    symbolName: kind == .local ? "internaldrive" : "sparkles",
                    isSelected: store.preferences.dataSource == kind
                ) {
                    store.preferences.dataSource = kind
                }
            }
            Text("metr stores no credentials. Live quota requests go only to that provider; local history stays on this Mac.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var alertsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Toggle(isOn: $store.preferences.alertsEnabled) {
                Text("Warn me before I hit a limit").font(Theme.Text.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if store.preferences.alertsEnabled {
                ThresholdSliders()
                Toggle(isOn: $store.preferences.quietHours.enabled) {
                    Text("Stay quiet \(store.preferences.quietHours.summary)").font(Theme.Text.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Text("Quiet hours follow your Mac’s timezone automatically.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func placementDetail(_ mode: MetrKit.PresentationMode) -> String {
        switch mode {
        case .top: return "A glanceable strip under the menu bar."
        case .side: return "A magnetic edge dock that collapses to a quiet rail."
        case .both: return "Keep the edge dock and a compact top readout together."
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: Theme.Space.snug) {
            if stepIndex > 0 {
                Button("Back") { store.goBackASetupStep() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Button("Skip setup") { store.skipSetup() }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(Theme.Text.captionTight)
            Spacer()
            Button(stepIndex == SetupStep.allCases.count - 1 ? "Done" : "Continue") {
                store.completeCurrentSetupStep()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Choice row

/// A radio-style option that shows the consequence of the choice, not just its name.
struct ChoiceRow: View {
    let title: String
    let detail: String
    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @EnvironmentObject private var motion: MotionSettings

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Space.snug) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color(nsColor: .controlAccentColor) : Color.secondary)
                    .imageScale(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Label(title, systemImage: symbolName)
                        .font(Theme.Text.captionTight.weight(.medium))
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.snug)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(hovering ? Color(nsColor: .labelColor).opacity(0.05) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(motion.accent) { hovering = h } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

// MARK: - Checklist

/// Getting-started checklist. Appears in Overview until every step is done or
/// the user dismisses it, so skipping setup does not mean losing the way back.
struct ChecklistCard: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                HStack {
                    Text("Finish setting up").font(Theme.Text.heading)
                    Spacer()
                    Text("\(store.onboarding.completedSteps.count) of \(SetupStep.allCases.count)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Button {
                        store.dismissChecklist()
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss setup checklist")
                }

                ForEach(SetupStep.allCases) { step in
                    let done = store.onboarding.completedSteps.contains(step)
                    Button {
                        store.jumpTo(step: step)
                    } label: {
                        HStack(spacing: Theme.Space.snug) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .imageScale(.small)
                                .foregroundStyle(done ? Color(nsColor: .systemGreen) : Color.secondary)
                            Text(step.title)
                                .font(Theme.Text.captionTight)
                                .foregroundStyle(done ? .secondary : .primary)
                                .strikethrough(done, color: .secondary)
                            Spacer()
                            if !done {
                                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(done)
                    .accessibilityLabel("\(step.title), \(done ? "done" : "not done")")
                    .accessibilityHint(done ? "" : "Opens this setup step")
                }
            }
        }
    }
}
