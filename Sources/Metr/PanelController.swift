import AppKit
import SwiftUI
import MetrKit

// MARK: - Panel

/// Borderless panel that can still take keyboard focus.
///
/// `.nonactivatingPanel` plus `canBecomeKey` is the combination that lets the
/// panel accept Tab, arrow keys and ⌘-shortcuts without yanking the user out of
/// whatever app they were working in.
final class MetrPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The view that fills the panel. It exists to let clicks fall through the
/// transparent margin the shadow lives in — otherwise the window's full
/// rectangle would swallow clicks meant for the app underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// Region, in view coordinates, that should actually accept clicks.
    var interactiveRect: CGRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}

// MARK: - Live layout metrics

/// Values the SwiftUI layer needs from the window layer.
@MainActor
final class PanelMetrics: ObservableObject {
    /// Tallest the card may become on the current screen before it must scroll.
    @Published var maxContentHeight: CGFloat = 620
    /// True while the collapsed rail is hovered.
    @Published var railHovered = false
    /// True while the panel is being dragged.
    @Published var isDragging = false
}

// MARK: - Controller

/// Owns the panel window: how big it is, where it sits, and how it moves.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {

    private let store: UsageStore
    private let motion: MotionSettings
    let metrics = PanelMetrics()

    private var panel: MetrPanel!
    private var hostingView: PassthroughHostingView<AnyView>!

    /// Height reported by the SwiftUI content for the current width.
    private var contentHeight: CGFloat = 320
    /// Suppresses the move-notification handler while we reposition ourselves.
    private var isProgrammaticMove = false
    private var snapWorkItem: DispatchWorkItem?
    private var autoHideWorkItem: DispatchWorkItem?
    private var railDragOrigin: NSPoint?
    private var railHoverWorkItem: DispatchWorkItem?

    /// True when the panel is showing only its edge rail.
    private var isRailed: Bool {
        !store.preferences.expanded && store.preferences.autoHide && !store.preferences.pinned && !metrics.railHovered
    }

    init(store: UsageStore, motion: MotionSettings) {
        self.store = store
        self.motion = motion
        super.init()
        build()
    }

    // MARK: Construction

    private func build() {
        panel = MetrPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false            // the SwiftUI card draws its own shadow
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.autorecalculatesKeyViewLoop = true      // keeps Tab order correct as views appear
        panel.preventsApplicationTerminationWhenModal = false
        panel.animationBehavior = .none
        panel.delegate = self
        panel.identifier = NSUserInterfaceItemIdentifier("metr-panel")
        panel.title = "metr"
        panel.setAccessibilityTitle("metr")

        let root = RootView()
            .environmentObject(store)
            .environmentObject(motion)
            .environmentObject(metrics)
            .environment(\.panelActions, PanelActions(
                setExpanded: { [weak self] expanded in self?.setExpanded(expanded) },
                setRailHover: { [weak self] hovering in self?.setRailHover(hovering) },
                dragRailChanged: { [weak self] translation in self?.dragRailChanged(translation) },
                dragRailEnded: { [weak self] in self?.dragRailEnded() },
                reportHeight: { [weak self] height in self?.updateContentHeight(height) },
                close: { [weak self] in self?.hide() }
            ))

        hostingView = PassthroughHostingView(rootView: AnyView(root))
        panel.contentView = hostingView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelMoved),
            name: NSWindow.didMoveNotification,
            object: panel
        )
    }

    // MARK: Visibility

    var isVisible: Bool { panel.isVisible }

    func show(activating: Bool = false) {
        layout(animated: false)
        panel.orderFrontRegardless()
        if activating { panel.makeKey() }
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        if panel.isVisible { hide() } else { show(activating: true) }
    }

    /// Bring the panel forward, expand it, and give it keyboard focus.
    func focus() {
        if !store.preferences.expanded { setExpanded(true) }
        show(activating: true)
    }

    // MARK: State changes

    func setExpanded(_ expanded: Bool) {
        store.setExpanded(expanded)
        layout(animated: true)
        if expanded { panel.makeKey() }
    }

    private func setRailHover(_ hovering: Bool) {
        railHoverWorkItem?.cancel()
        if hovering {
            guard !metrics.railHovered else { return }
            metrics.railHovered = true
            layout(animated: true)
            return
        }

        // The rail briefly changes width when its preview appears. Debouncing
        // exit prevents that animated re-layout from stealing the pointer and
        // collapsing the preview before the user can reach it.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.metrics.railHovered else { return }
                self.metrics.railHovered = false
                self.layout(animated: true)
            }
        }
        railHoverWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: work)
    }

    private func dragRailChanged(_ translation: CGSize) {
        if railDragOrigin == nil {
            railDragOrigin = panel.frame.origin
            metrics.isDragging = true
            snapWorkItem?.cancel()
        }
        guard let origin = railDragOrigin else { return }
        isProgrammaticMove = true
        panel.setFrameOrigin(NSPoint(x: origin.x + translation.width, y: origin.y - translation.height))
        isProgrammaticMove = false
    }

    private func dragRailEnded() {
        guard railDragOrigin != nil else { return }
        railDragOrigin = nil
        snapToEdge()
    }

    /// Called by the SwiftUI layer whenever its measured height changes.
    private func updateContentHeight(_ height: CGFloat) {
        let clamped = max(48, min(height, metrics.maxContentHeight))
        guard abs(clamped - contentHeight) > 0.5 else { return }
        contentHeight = clamped
        layout(animated: true)
    }

    /// Preferences that affect geometry changed.
    func preferencesChanged(from old: Preferences) {
        let needsLayout = old.mode != store.preferences.mode
            || old.edge != store.preferences.edge
            || old.panelWidth != store.preferences.panelWidth
            || old.expanded != store.preferences.expanded
            || old.autoHide != store.preferences.autoHide
            || old.pinned != store.preferences.pinned
            || old.edgeOffset != store.preferences.edgeOffset
        if needsLayout { layout(animated: true) }
    }

    @objc private func screensChanged() {
        // A display was added, removed, or resized. Re-derive the clamp and
        // re-dock, so the panel never ends up parked off-screen.
        layout(animated: false)
    }

    // MARK: Geometry

    /// The screen the panel currently belongs to, falling back sensibly when
    /// the panel is off-screen or no screen reports as main.
    private var targetScreen: NSScreen {
        if panel.isVisible, let screen = panel.screen { return screen }
        if let mouse = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) { return mouse }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    private func layout(animated: Bool) {
        let screen = targetScreen
        // `visibleFrame` already excludes the menu bar and the Dock, and on a
        // notched Mac it sits below the notch — so working inside it is what
        // keeps the top island clear of both the menu bar and the camera housing.
        let visible = screen.visibleFrame

        // Leave room for the panel's own margins plus a little breathing space.
        metrics.maxContentHeight = min(620, max(420, visible.height - (Theme.shadowMargin * 2) - 24))

        let frame = isRailed
            ? railFrame(in: visible)
            : cardFrame(in: visible)

        let interactive = isRailed
            ? CGRect(origin: .zero, size: frame.size)
            : CGRect(x: Theme.shadowMargin, y: Theme.shadowMargin,
                     width: frame.width - Theme.shadowMargin * 2,
                     height: frame.height - Theme.shadowMargin * 2)
        hostingView.interactiveRect = interactive

        isProgrammaticMove = true
        if animated, let animation = motion.geometry {
            _ = animation
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in self?.isProgrammaticMove = false }
            }
        } else {
            panel.setFrame(frame, display: true)
            isProgrammaticMove = false
        }
    }

    /// Full card geometry, docked to the configured edge.
    private func cardFrame(in visible: CGRect) -> CGRect {
        let width = CGFloat(store.preferences.panelWidth.points) + Theme.shadowMargin * 2
        let height = min(contentHeight, metrics.maxContentHeight) + Theme.shadowMargin * 2
        let gap: CGFloat = 2
        let offset = CGFloat(min(max(store.preferences.edgeOffset, 0), 1))

        switch store.preferences.mode {
        case .top:
            // Anchored to the top edge and grows downward, so expanding feels
            // like the island unrolling from under the menu bar.
            let travel = max(0, visible.width - width)
            let x = visible.minX + travel * offset
            let y = visible.maxY - height + Theme.shadowMargin - gap
            return CGRect(x: x, y: y, width: width, height: height)

        case .side, .both:
            let travel = max(0, visible.height - height)
            // offset 0 = top of the screen, so dragging up lowers the number.
            let y = visible.maxY - height - travel * offset
            let x = store.preferences.edge == .trailing
                ? visible.maxX - width + Theme.shadowMargin - gap
                : visible.minX - Theme.shadowMargin + gap
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    /// The minimized dock hugs the selected edge while keeping a comfortable
    /// target for pointer, keyboard and VoiceOver users.
    private func railFrame(in visible: CGRect) -> CGRect {
        let count = CGFloat(max(1, store.visibleProviders.count))
        let sideWidth = Theme.dockWidth
        let sideHeight = count * Theme.dockRowHeight + Theme.dockSidePadding * 2
        let peekWidth: CGFloat = metrics.railHovered ? 232 : 0
        let peekGap: CGFloat = metrics.railHovered ? 8 : 0
        let sideFrameWidth = sideWidth + peekWidth + peekGap
        let topWidth = max(176, count * 88 + 20)
        let topHeight = Theme.dockTopHeight + (metrics.railHovered ? 112 : 0)
        let offset = CGFloat(min(max(store.preferences.edgeOffset, 0), 1))

        switch store.preferences.mode {
        case .top:
            let travel = max(0, visible.width - topWidth)
            return CGRect(x: visible.minX + travel * offset,
                          y: visible.maxY - topHeight,
                          width: topWidth, height: topHeight)
        case .side, .both:
            let travel = max(0, visible.height - sideHeight)
            let y = visible.maxY - sideHeight - travel * offset
            let x = store.preferences.edge == .trailing
                ? visible.maxX - sideFrameWidth
                : visible.minX
            return CGRect(x: x, y: y, width: sideFrameWidth, height: sideHeight)
        }
    }

    // MARK: Drag & snap

    @objc private func panelMoved() {
        guard !isProgrammaticMove else { return }
        metrics.isDragging = true

        // The user is dragging. Wait for them to stop, then re-dock.
        snapWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.snapToEdge() }
        }
        snapWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    /// Translate wherever the user dropped the panel into the nearest docked
    /// position, and remember the offset along that edge.
    private func snapToEdge() {
        metrics.isDragging = false
        let screen = targetScreen
        let visible = screen.visibleFrame
        let frame = panel.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)

        var prefs = store.preferences

        // Dropped near the top of the screen becomes a top island; anywhere
        // else docks to whichever side edge is closer.
        let distanceToTop = visible.maxY - frame.maxY
        if distanceToTop < 80 {
            prefs.mode = .top
            let travel = max(1, visible.width - frame.width)
            prefs.edgeOffset = Double(min(max((frame.minX - visible.minX) / travel, 0), 1))
        } else {
            prefs.mode = .side
            prefs.edge = center.x > visible.midX ? .trailing : .leading
            let travel = max(1, visible.height - frame.height)
            prefs.edgeOffset = Double(min(max((visible.maxY - frame.maxY) / travel, 0), 1))
        }

        store.preferences = prefs   // persists, and calls back into preferencesChanged
        layout(animated: true)
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // A non-activating panel loses key focus constantly — every time the
        // user clicks back into their editor. Collapsing instantly on that would
        // make the panel feel twitchy, so auto-hide waits, and cancels if the
        // pointer is still on the panel or focus comes back.
        scheduleAutoHide()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
    }

    /// Delay before an unfocused panel collapses to its rail.
    private static let autoHideDelay: TimeInterval = 2.5

    private func scheduleAutoHide() {
        autoHideWorkItem?.cancel()
        guard store.preferences.autoHide, !store.preferences.pinned, store.preferences.expanded else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.store.preferences.autoHide, !self.store.preferences.pinned else { return }
                guard !self.panel.isKeyWindow, !self.metrics.railHovered, !self.metrics.isDragging else { return }
                // Never collapse out from under the pointer.
                guard !self.panel.frame.contains(NSEvent.mouseLocation) else {
                    self.scheduleAutoHide()
                    return
                }
                self.setExpanded(false)
            }
        }
        autoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoHideDelay, execute: work)
    }
}

// MARK: - Actions bridge

/// The handful of window-level operations the SwiftUI layer needs. Passed
/// through the environment so no view has to reach for `NSApp.delegate`.
struct PanelActions {
    var setExpanded: (Bool) -> Void = { _ in }
    var setRailHover: (Bool) -> Void = { _ in }
    var dragRailChanged: (CGSize) -> Void = { _ in }
    var dragRailEnded: () -> Void = {}
    var reportHeight: (CGFloat) -> Void = { _ in }
    var close: () -> Void = {}
}

private struct PanelActionsKey: EnvironmentKey {
    static let defaultValue = PanelActions()
}

extension EnvironmentValues {
    var panelActions: PanelActions {
        get { self[PanelActionsKey.self] }
        set { self[PanelActionsKey.self] = newValue }
    }
}
