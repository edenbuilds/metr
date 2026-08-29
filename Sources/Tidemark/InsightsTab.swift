import SwiftUI
import TidemarkKit

struct InsightsTab: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            let insights = store.insights

            if insights.isEmpty {
                Card {
                    EmptyStateView(
                        symbolName: "lightbulb",
                        title: "Not enough to go on yet",
                        message: "Insights need a week or so of activity before they say anything you could act on. Until then, an empty panel is more honest than a made-up one.",
                        actionLabel: store.preferences.dataSource == .local ? "See it with demo data" : nil,
                        action: store.preferences.dataSource == .local ? { store.preferences.dataSource = .mock } : nil
                    )
                }
            } else {
                ForEach(insights) { insight in
                    Card {
                        HStack(alignment: .top, spacing: Theme.Space.base) {
                            Image(systemName: insight.symbolName)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(insight.title)
                                    .font(Theme.Text.captionTight.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(insight.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(insight.title). \(insight.detail)")
                }
            }

            provenanceCard
        }
    }

    /// Says exactly where the numbers came from. This is the surface that keeps
    /// the rest of the panel honest.
    private var provenanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                HStack(spacing: Theme.Space.tight) {
                    Image(systemName: "info.circle").imageScale(.small)
                    Text("Where these numbers come from").font(Theme.Text.captionTight.weight(.semibold))
                }
                Text(store.dataSourceProvenance)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Times and day boundaries use \(store.location.inlinePhrase).")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
