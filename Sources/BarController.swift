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

}
