import AppKit
import Combine
import QuartzCore
import SwiftUI
import UserNotifications
import MetrKit

// MARK: - App

@main
struct MetrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The panel and preferences window are both AppKit-owned, so the app's
        // only Scene is an empty Settings placeholder.
        Settings { EmptyView() }
    }
}

// MARK: - Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let store = UsageStore()
    private let motion = MotionSettings()
    private var panelController: PanelController!
    private var statusItem: NSStatusItem!
    private var preferencesWindow: NSWindow?
    private var localKeyMonitor: Any?
    private var subscriptions: Set<AnyCancellable> = []
    private var statusAnimationTimer: Timer?
    private var statusWaveStep = 0
    private var previousSeverity: Severity?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        motion.userReducesMotion = store.preferences.reduceMotionOverride
        applyAppearance(store.preferences.appearance)
        // Keep the reported login-item state honest at launch: the user may have
        // revoked it in System Settings since we last stored it.
        store.preferences.launchAtLogin = LoginItem.isEnabled
        // 0.3 keeps the side presentation in the natural right-top glance zone
        // for existing installs, while preserving any deliberate repositioning.
        if store.preferences.mode != .top,
           store.preferences.edge == .trailing,
           abs(store.preferences.edgeOffset - 0.5) < 0.001 {
            store.preferences.edgeOffset = 0.06
        }

        panelController = PanelController(store: store, motion: motion)

        store.onPreferencesChanged = { [weak self] new, old in
            guard let self else { return }
            self.motion.userReducesMotion = new.reduceMotionOverride
            self.applyAppearance(new.appearance)
            self.panelController.preferencesChanged(from: old)
            self.updateStatusItem()
        }
        store.onAlerts = { [weak self] alerts in
            self?.deliver(alerts)
        }

        buildStatusItem()
        observeUsageStatus()
        installKeyMonitor()
        requestNotificationAuthorizationIfNeeded()

        store.start()
        panelController.show()
        updateStatusItem()

        // Reflect the preferences flag the panel raises.
        observePreferencesRequests()
    }

    private func applyAppearance(_ appearance: AppearanceMode) {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        statusAnimationTimer?.invalidate()
    }

    // MARK: Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.behavior = []          // never let a drag remove it from the menu bar
        statusItem.isVisible = true
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.image(level: 0.15, severity: .nominal, isKnown: false)
        button.image?.isTemplate = true
        // A target/action on the status button means Return activates it during
        // full keyboard navigation, not just a mouse click.
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("metr")
    }

    /// Status title carries the headline number so the menu bar itself is
    /// informative, with a symbol for the state rather than colour alone.
    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let status = store.headerStatus
        if let focus = store.focusProvider, let fraction = focus.usedFraction {
            button.title = " \(Formatters.percent(fraction))"
        } else {
            button.title = ""
        }
        // The menu-bar glyph fills with the same level the panel shows, so the
        // menu bar alone tells you where you stand.
        button.image = MenuBarIcon.image(
            level: store.focusProvider?.usedFraction ?? 0.15,
            severity: status.severity,
            isKnown: status.isKnown
        )
        button.image?.isTemplate = true
        button.toolTip = "\(Brand.name) — \(status.label)"
        button.setAccessibilityLabel("metr, \(status.label)")
    }

    /// Keep the menu-bar readout in lockstep with every refresh. While a read
    /// is in flight, the fill makes one quiet wave; a newly critical state gets
    /// two opacity pulses. Both effects respect Reduce Motion.
    private func observeUsageStatus() {
        store.$snapshot
            .combineLatest(store.$isRefreshing)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, refreshing in
                guard let self else { return }
                self.updateStatusItem()
                self.setStatusAnimation(active: refreshing)

                let severity = self.store.headerStatus.severity
                if severity == .critical, self.previousSeverity != .critical {
                    self.pulseStatusItem()
                }
                self.previousSeverity = severity
            }
            .store(in: &subscriptions)
    }

    private func setStatusAnimation(active: Bool) {
        statusAnimationTimer?.invalidate()
        statusAnimationTimer = nil
        guard active, !motion.reduceMotion else { updateStatusItem(); return }

        statusWaveStep = 0
        let timer = Timer(timeInterval: 0.14, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let button = self.statusItem?.button else { return }
                let offsets: [Double] = [0, 0.04, 0.08, 0.04]
                let status = self.store.headerStatus
                let level = min(1, (self.store.focusProvider?.usedFraction ?? 0.15) + offsets[self.statusWaveStep % offsets.count])
                button.image = MenuBarIcon.image(level: level, severity: status.severity, isKnown: status.isKnown)
                button.image?.isTemplate = true
                self.statusWaveStep += 1
            }
        }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        statusAnimationTimer = timer
    }

    private func pulseStatusItem() {
        guard !motion.reduceMotion, let button = statusItem?.button else { return }
        button.wantsLayer = true
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.45
        pulse.toValue = 1.0
        pulse.duration = 0.42
        pulse.autoreverses = true
        pulse.repeatCount = 2
        button.layer?.add(pulse, forKey: "metr-attention")
    }

    @objc private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRightClick {
            showMenu()
        } else {
            panelController.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: panelController.isVisible ? "Hide metr" : "Show metr",
                     action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: store.preferences.expanded ? "Minimise to Compact" : "Expand Panel",
                     action: #selector(toggleExpanded), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(withTitle: "Replay Setup", action: #selector(replaySetup), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit metr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = $0.target ?? self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil   // restore click-to-toggle for the next left click
    }

    @objc private func togglePanel() { panelController.toggle() }
    @objc private func toggleExpanded() {
        panelController.setExpanded(!store.preferences.expanded)
        if !panelController.isVisible { panelController.show(activating: true) }
    }
    @objc private func refreshNow() { Task { await store.refresh() } }
    @objc private func replaySetup() {
        store.restartSetup()
        panelController.focus()
    }

    // MARK: Preferences window

    private func observePreferencesRequests() {
        // `isShowingPreferences` is set from inside the panel; mirror it onto an
        // AppKit window and clear the flag once handled.
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.store.isShowingPreferences else { return }
                self.store.isShowingPreferences = false
                self.showPreferences()
            }
        }
    }

    @objc private func showPreferences() {
        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = PreferencesView()
            .environmentObject(store)
            .environmentObject(motion)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "metr Settings"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("metr-preferences")
        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Keyboard

    /// Shortcuts that work while the panel has key focus. There is deliberately
    /// no global hotkey: registering one would require Accessibility or Input
    /// Monitoring permission, which is too much to ask of a usage meter.
    private func installKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let command = event.modifierFlags.contains(.command)

            if event.keyCode == 53 {   // Escape
                if self.store.preferences.expanded {
                    self.panelController.setExpanded(false)
                    return nil
                }
            }
            guard command, let characters = event.charactersIgnoringModifiers else { return event }
            switch characters {
            case "r": Task { await self.store.refresh() }; return nil
            case "w": self.panelController.hide(); return nil
            case ",": self.showPreferences(); return nil
            case "1": self.store.selectedTab = .overview; return nil
            case "2": self.store.selectedTab = .history; return nil
            case "3": self.store.selectedTab = .insights; return nil
            default: return event
            }
        }
    }

    // MARK: Notifications

    private func requestNotificationAuthorizationIfNeeded() {
        guard store.preferences.alertsEnabled else { return }
        // Only meaningful for a real bundle; `swift run` has no bundle identifier
        // to attach notifications to, so skip rather than log a crash-looking error.
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func deliver(_ alerts: [UsageAlert]) {
        updateStatusItem()
        guard Bundle.main.bundleIdentifier != nil else { return }
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = alert.severity == .critical ? .default : nil
            let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
