import AppKit

final class BarController {
    private let bar = NSStatusBar.system
    private var spacer: NSStatusItem!
    private var chevron: NSStatusItem!
    private let menuController = OverflowMenu()
    private let settings = SettingsWindowController()

    func showSettings() { settings.show() }

    private static let spacerAutosave = "com.nic.overflow.spacer"
    private static let chevronAutosave = "com.nic.overflow.chevron"
    private static let lengthKey = "SpacerLength"

    /// Step used by Hide more / Hide less.
    static let step: CGFloat = 50

    private var spacerLength: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: Self.lengthKey)) }
        set { UserDefaults.standard.set(Double(newValue), forKey: Self.lengthKey) }
    }

    func start() {
        // Ask macOS for the rightmost third-party slot. Confirmed to land just left of
        // Control Center; system items cannot be displaced.
        // Preferred position is measured from the RIGHT edge: smaller wins the rightmost slot.
        // The chevron must sit to the spacer's right, otherwise growing the spacer drags the
        // chevron leftward along with everything else instead of leaving it anchored.
        let defaults = UserDefaults.standard
        defaults.set(997.0, forKey: "NSStatusItem Preferred Position \(Self.chevronAutosave)")
        defaults.set(998.0, forKey: "NSStatusItem Preferred Position \(Self.spacerAutosave)")

        spacer = bar.statusItem(withLength: max(1, spacerLength))
        spacer.autosaveName = Self.spacerAutosave
        spacer.button?.title = ""
        spacer.button?.image = nil

        chevron = bar.statusItem(withLength: NSStatusItem.squareLength)
        chevron.autosaveName = Self.chevronAutosave
        if let button = chevron.button {
            button.image = NSImage(systemSymbolName: "chevron.down",
                                   accessibilityDescription: "Hidden menu bar items")
            button.image?.isTemplate = true
        }

        menuController.controller = self
        settings.controller = self
        chevron.menu = menuController.menu

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        applyLength(spacerLength)
    }

    // MARK: - Geometry

    /// Left edge of the usable status area. On a notched display this is the notch's right edge;
    /// on an external display it is simply the screen's left edge.
    var notchMinX: CGFloat {
        guard let screen = NSScreen.main else { return 0 }
        return screen.auxiliaryTopRightArea?.minX ?? screen.frame.minX
    }

    /// Live x-position of our own chevron, read back from WindowServer.
    private var chevronMinX: CGFloat? {
        let mine = StatusItemScanner.scan().filter { $0.pid == getpid() && $0.isOnscreen }
        return mine.map(\.frame.minX).max()
    }

    // MARK: - Mutation

    func applyLength(_ proposed: CGFloat) {
        let current = spacer.length
        guard let x = chevronMinX else {
            // Chevron not measurable yet; refuse to grow rather than risk losing it.
            spacer.length = max(1, min(proposed, current))
            return
        }
        let safe = SpacerClamp.clamp(proposed,
                                     chevronMinX: x,
                                     notchMinX: notchMinX,
                                     currentLength: current)
        spacer.length = max(1, safe)
        spacerLength = safe
    }

    func hideMore() { applyLength(spacer.length + Self.step) }
    func hideLess() { applyLength(spacer.length - Self.step) }
    func reset() { applyLength(0) }

    var currentSpacerLength: CGFloat { spacer.length }

    // MARK: - Temporary reveal (fallback when AXPress does not work)

    private var restoreTimer: Timer?
    private var savedSpacerLength: CGFloat?
    private var savedChevronLength: CGFloat?

    /// Bring `item` back on screen long enough for the user to click it themselves, then undo.
    ///
    /// Two cases. If our own spacer is what pushed it off, collapsing the spacer is enough. If
    /// the bar was simply full — the item was already a casualty at spacer 0 — the only space we
    /// control is our own chevron, so we surrender that too and rely on the timer to bring it
    /// back. Returns whether the item actually became visible.
    @discardableResult
    func temporarilyReveal(_ item: MenuBarItem, seconds: TimeInterval = 8) -> Bool {
        restoreNow()

        savedSpacerLength = spacer.length
        savedChevronLength = chevron.length
        spacer.length = 1

        var visible = waitUntilVisible(pid: item.pid)
        if !visible {
            chevron.length = 0
            visible = waitUntilVisible(pid: item.pid)
        }

        restoreTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.restoreNow()
        }
        return visible
    }

    private func waitUntilVisible(pid: pid_t) -> Bool {
        for _ in 0..<6 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
            if StatusItemScanner.scan().contains(where: { $0.pid == pid && $0.isOnscreen }) {
                return true
            }
        }
        return false
    }

    private func restoreNow() {
        restoreTimer?.invalidate()
        restoreTimer = nil
        if let s = savedSpacerLength { spacer.length = s; savedSpacerLength = nil }
        if let c = savedChevronLength { chevron.length = c; savedChevronLength = nil }
    }

    @objc private func screensChanged() {
        // Boundary moved; re-clamp against the new geometry.
        applyLength(spacerLength)
    }
}
