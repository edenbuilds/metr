import AppKit
import ServiceManagement
import SwiftUI
import MetrKit

/// The preferences window. Small on purpose: five tabs of settings for a panel
/// this size would be its own product.
struct PreferencesView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        TabView {
            panelTab.tabItem { Label("Panel", systemImage: "macwindow") }
            dataTab.tabItem { Label("Data", systemImage: "internaldrive") }
            alertsTab.tabItem { Label("Alerts", systemImage: "bell") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 430, height: 430)
    }

    // MARK: Panel

    private var panelTab: some View {
        Form {
            Picker("Placement", selection: $store.preferences.mode) {
                ForEach(PresentationMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Appearance", selection: $store.preferences.appearance) {
                ForEach(AppearanceMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if store.preferences.mode != .top {
                Picker("Edge", selection: $store.preferences.edge) {
                    ForEach(ScreenEdge.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Picker("Width", selection: $store.preferences.panelWidth) {
                ForEach(PanelWidth.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Compact shows", selection: $store.preferences.compactMetric) {
                ForEach(CompactMetric.allCases, id: \.self) { Text($0.title).tag($0) }
            }

            Divider()

            Toggle("Collapse to a rail when unfocused", isOn: $store.preferences.autoHide)
            Toggle("Keep open (ignore auto-hide)", isOn: $store.preferences.pinned)
            Toggle("Reduce motion", isOn: $store.preferences.reduceMotionOverride)
            Toggle("Launch at login", isOn: Binding(
                get: { store.preferences.launchAtLogin },
                set: { newValue in
                    store.preferences.launchAtLogin = LoginItem.set(enabled: newValue)
                }
            ))
            Text(LoginItem.statusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: Data

    private var dataTab: some View {
        Form {
            Picker("Source", selection: $store.preferences.dataSource) {
                ForEach(DataSourceKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)

            Text(store.dataSourceProvenance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Picker("Refresh", selection: $store.preferences.refresh) {
                ForEach(RefreshCadence.allCases, id: \.self) { Text($0.title).tag($0) }
            }

            Section("Providers") {
                if store.allProviders.isEmpty {
                    Text("Nothing has reported yet.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(store.allProviders) { provider in
                    Toggle(provider.identity.name, isOn: Binding(
                        get: { store.preferences.isVisible(provider.id) },
                        set: { visible in
                            if visible { store.preferences.hiddenProviderIDs.remove(provider.id) }
                            else { store.preferences.hiddenProviderIDs.insert(provider.id) }
                        }
                    ))
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Alerts

    private var alertsTab: some View {
        Form {
            Toggle("Warn me before I hit a limit", isOn: $store.preferences.alertsEnabled)

            Section("Thresholds") {
                ThresholdSliders().disabled(!store.preferences.alertsEnabled)
            }

            Section("Quiet hours") {
                Toggle("Hold alerts overnight", isOn: $store.preferences.quietHours.enabled)
                Stepper("From \(store.preferences.quietHours.startHour):00",
                        value: $store.preferences.quietHours.startHour, in: 0...23)
                Stepper("Until \(store.preferences.quietHours.endHour):00",
                        value: $store.preferences.quietHours.endHour, in: 0...23)
                Text("Evaluated in your Mac’s system timezone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!store.preferences.alertsEnabled)
        }
        .formStyle(.grouped)
    }

    // MARK: About

    private var aboutTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.base) {
                Text("metr")
                    .font(.headline)
                Text("A calm companion for AI usage windows. It runs as a menu-bar accessory and keeps one small surface on screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("What is real, and what is not") {
                    VStack(alignment: .leading, spacing: Theme.Space.snug) {
                        bullet("Session lists and daily counts are read from files the agent CLIs already wrote on this Mac.")
                        bullet("Usage and reset windows are provider-reported when an existing Codex or Claude Code login is available.")
                        bullet("When live quota is unavailable, local activity is kept clearly labelled as an estimate, never presented as a plan limit.")
                        bullet("Costs are estimates from a stated assumption, shown next to the number. They are not billing data.")
                        bullet("metr has no server or telemetry. Read-only credentials are sent only to their own provider endpoint and are never stored by metr.")
                    }
                    .padding(.vertical, 2)
                }

                GroupBox("Keyboard") {
                    VStack(alignment: .leading, spacing: 3) {
                        shortcut("⌘R", "Refresh now")
                        shortcut("⌘1 ⌘2 ⌘3", "Overview, History, Insights")
                        shortcut("⌘,", "Preferences")
                        shortcut("Esc", "Collapse the panel")
                        shortcut("Tab", "Move through controls")
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    Button("Replay setup") { store.restartSetup() }
                    Button("Show all tips again") { store.onboarding.dismissedHints.removeAll() }
                    Spacer()
                    Button("Reset everything", role: .destructive) { store.resetAllStoredData() }
                }
                .controlSize(.small)
            }
            .padding()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcut(_ keys: String, _ meaning: String) -> some View {
        HStack {
            Text(keys).font(.system(.caption, design: .monospaced)).frame(width: 78, alignment: .leading)
            Text(meaning).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Login item

/// Launch-at-login via `SMAppService`, which needs no helper bundle on macOS 13+.
enum LoginItem {

    /// - Returns: the state actually achieved, so a failure cannot leave the
    ///   toggle showing something untrue.
    @discardableResult
    static func set(enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return isEnabled
        } catch {
            return isEnabled
        }
    }

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Login items only work for a real app bundle, so say so plainly when the
    /// app is being run straight from `swift run`.
    static var statusDescription: String {
        guard #available(macOS 13.0, *) else { return "Requires macOS 13 or later." }
        switch SMAppService.mainApp.status {
        case .enabled: return "Registered. macOS will start metr at login."
        case .requiresApproval: return "Approve metr in System Settings › General › Login Items."
        case .notFound: return "Only available when running the built app bundle, not `swift run`."
        default: return "Not registered."
        }
    }
}
