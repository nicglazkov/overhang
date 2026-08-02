import AppKit

final class BarController {
    private let bar = NSStatusBar.system
    private var chevron: NSStatusItem!
    private let menuController = OverhangMenu()
    private let settings = SettingsWindowController()

    func showSettings() { settings.show() }

    private static let chevronAutosave = "com.nic.overhang.chevron"

    func start() {
        // Ask macOS for the rightmost third-party slot. Confirmed to land just left of
        // Control Center; system items cannot be displaced. Preferred position is measured
        // from the RIGHT edge: smaller wins the rightmost slot.
        let defaults = UserDefaults.standard
        defaults.set(997.0, forKey: "NSStatusItem Preferred Position \(Self.chevronAutosave)")

        // Earlier versions carried a second status item, a spacer whose width hid icons on
        // request. The feature is gone; scrub its persisted state so nothing lingers.
        defaults.removeObject(forKey: "SpacerLength")
        defaults.removeObject(forKey: "NSStatusItem Preferred Position com.nic.overhang.spacer")
        defaults.removeObject(forKey: "NSStatusItem Visible com.nic.overhang.spacer")

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
    }

    // MARK: - Temporary reveal (fallback when AXPress does not work)

    private var restoreTimer: Timer?
    private var savedChevronLength: CGFloat?

    /// Bring `item` back on screen long enough for the user to click it themselves, then undo.
    ///
    /// The only space this app owns is its own chevron, so it surrenders that width and relies
    /// on the timer to bring it back. That frees one slot, enough to surface the item nearest
    /// the boundary. Returns whether the item actually became visible.
    @discardableResult
    func temporarilyReveal(_ item: MenuBarItem, seconds: TimeInterval = 8) -> Bool {
        restoreNow()

        savedChevronLength = chevron.length
        chevron.length = 0

        let visible = waitUntilVisible(pid: item.pid)

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
        if let c = savedChevronLength { chevron.length = c; savedChevronLength = nil }
    }
}
