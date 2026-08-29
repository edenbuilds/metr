import SwiftUI
import TidemarkKit

/// Timezone / location control.
///
/// The whole feature is timezone-shaped on purpose: it delivers the useful part
/// of "knowing where you are" (correct reset times, quiet hours that travel)
/// without asking for a permission or storing a position.
struct LocationPicker: View {
    @EnvironmentObject private var store: UsageStore
    var compact = false

    @State private var query = ""
    @State private var customLabel = ""
    @State private var isChoosing = false

    private var identifiers: [String] {
        TimeZoneResolver.search(query, in: TimeZoneResolver.selectableIdentifiers())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            currentRow

            if store.systemTimeZoneChangedAt != nil && !store.location.isOverridden {
                changedNotice
            }

            if isChoosing { picker }

            if !compact { privacyControls }
        }
        .onAppear { customLabel = store.preferences.manualPlaceLabel ?? "" }
    }

    // MARK: Current

    private var currentRow: some View {
        HStack(spacing: Theme.Space.snug) {
            Image(systemName: store.preferences.locationAware ? "globe" : "globe.badge.chevron.backward")
                .imageScale(.small)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                Text(store.location.placeLabel)
                    .font(Theme.Text.captionTight.weight(.medium))
                Text(store.location.summary)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.tight)

            Text(Formatters.time(store.now, in: store.location.timeZone))
                .font(Theme.Text.captionTight.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(isChoosing ? "Close" : "Change") {
                withAnimation { isChoosing.toggle() }
            }
            .buttonStyle(.link)
            .font(.system(size: 10))
            .disabled(!store.preferences.locationAware)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Display timezone: \(store.location.placeLabel), \(store.location.summary). Current time \(Formatters.time(store.now, in: store.location.timeZone)).")
    }

    /// Shown when the Mac itself changed timezone while the app was running.
    private var changedNotice: some View {
        HStack(spacing: Theme.Space.tight) {
            Image(systemName: "airplane.departure").font(.system(size: 9))
            Text("Your Mac changed timezone. Times now follow \(store.location.placeLabel).")
                .font(.system(size: 9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Space.snug)
        .padding(.vertical, Theme.Space.tight)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .labelColor).opacity(0.05)))
    }

    // MARK: Picker

    private var picker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            TextField("Search cities or zones", text: $query)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(Theme.Text.captionTight)
                .accessibilityLabel("Search timezones")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(identifiers.prefix(60), id: \.self) { identifier in
                        zoneRow(identifier)
                    }
                    if identifiers.isEmpty {
                        Text("No timezone matches “\(query)”.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(Theme.Space.snug)
                    }
                }
            }
            .frame(height: 132)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .labelColor).opacity(0.04)))

            HStack(spacing: Theme.Space.snug) {
                TextField("Call it something else (optional)", text: $customLabel)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(Theme.Text.captionTight)
                    .accessibilityLabel("Custom name for this location")
                    .onSubmit(applyCustomLabel)
                Button("Save", action: applyCustomLabel)
                    .controlSize(.small)
                    .disabled(store.preferences.manualTimeZoneID == nil)
            }

            HStack {
                Text("A label only changes what the panel calls this place.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Follow my Mac") {
                    store.useSystemTimeZone()
                    customLabel = ""
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
                .disabled(store.preferences.manualTimeZoneID == nil)
            }
        }
    }

    private func zoneRow(_ identifier: String) -> some View {
        let isSelected = store.preferences.manualTimeZoneID == identifier
        let zone = TimeZone(identifier: identifier)
        return Button {
            store.setManualTimeZone(identifier, label: customLabel.isEmpty ? nil : customLabel)
        } label: {
            HStack(spacing: Theme.Space.snug) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.small)
                    .foregroundStyle(isSelected ? Color(nsColor: .controlAccentColor) : Color.secondary)
                Text(TimeZoneResolver.placeName(for: zone ?? .current))
                    .font(.system(size: 10))
                Text(identifier)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.tight)
                if let zone {
                    Text(Formatters.time(store.now, in: zone))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Space.snug)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(TimeZoneResolver.placeName(for: zone ?? .current)), \(identifier)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private func applyCustomLabel() {
        guard let identifier = store.preferences.manualTimeZoneID else { return }
        store.setManualTimeZone(identifier, label: customLabel.isEmpty ? nil : customLabel)
    }

    // MARK: Privacy

    private var privacyControls: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Divider().padding(.vertical, 2)

            Toggle(isOn: $store.preferences.locationAware) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Use location context").font(Theme.Text.captionTight)
                    Text("Labels times with a place name and lets you override the zone. Turn off to use your Mac's timezone with no place labels.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $store.preferences.showProviderTimeZone) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Show the provider's timezone too").font(Theme.Text.captionTight)
                    Text("Adds the provider's own reset time when it differs from yours.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!store.preferences.locationAware)

            HStack(spacing: Theme.Space.snug) {
                Button("Clear stored location data") {
                    store.clearStoredLocationData()
                    customLabel = ""
                    query = ""
                }
                .controlSize(.small)
                .disabled(store.preferences.manualTimeZoneID == nil && store.preferences.manualPlaceLabel == nil)
                Spacer()
            }

            Text("Tidemark never links CoreLocation, so it cannot request GPS or Wi-Fi positioning. The only stored location values are the timezone identifier and label you type here.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Thresholds

struct ThresholdSliders: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
            Slider(value: value, in: range)
                .controlSize(.mini)
                .accessibilityLabel(title)
                .accessibilityValue(Formatters.percent(value.wrappedValue))
            Text(Formatters.percent(value.wrappedValue))
                .font(.system(size: 10).monospacedDigit())
                .frame(width: 32, alignment: .trailing)
        }
    }
}
