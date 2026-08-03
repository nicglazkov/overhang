import AppKit

/// The dropdown. Rebuilt on every open so it always reflects the live bar.
final class OverhangMenu: NSObject, NSMenuDelegate {
    weak var controller: BarController?
    let menu = NSMenu()

    override init() {
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let safeAreaMinX = NSScreen.main?.auxiliaryTopRightArea?.minX ?? 0
        let hidden = StatusItemScanner.casualties(in: StatusItemScanner.scan(),
                                                  safeAreaMinX: safeAreaMinX)

        if hidden.isEmpty {
            addDisabled("Nothing hidden")
        } else {
            addDisabled("Hidden items")

            // One row per owning app. Stats contributes four items and four identical rows
            // would be noise, so collapse by pid and keep the leftmost frame for matching.
            var seen = Set<pid_t>()
            for item in hidden where !seen.contains(item.pid) {
                seen.insert(item.pid)
                let count = hidden.filter { $0.pid == item.pid }.count
                let row = NSMenuItem(title: count > 1 ? "\(item.displayName) (\(count))" : item.displayName,
                                     action: #selector(open(_:)),
                                     keyEquivalent: "")
                row.target = self
                row.image = item.icon
                row.representedObject = item
                menu.addItem(row)
            }
        }

        menu.addItem(.separator())
        // Only surface this when it is actionable; when it is on it just adds noise, and the
        // state is visible in Settings anyway.
        if !Activator.isTrusted {
            add("Enable click-through…", #selector(enableClickThrough))
        }
        add("Settings…", #selector(openSettings), key: ",")
        add("Quit Overhang", #selector(quit), key: "q")
    }

    private func add(_ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func addDisabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    // MARK: - Actions

    /// Try to open the item's own menu. Degrade in the open rather than pretending it worked.
    @objc private func open(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? MenuBarItem else { return }

        if Activator.open(item) == .opened { return }

        // AXPress did nothing, either we are untrusted, or this item consumes the mouse event
        // itself. Bring the owning app forward so something visibly happens. An earlier version
        // also collapsed the chevron to make room for the item, but the most that could ever
        // free was 22pt, which reveals nothing, while leaving a dead 16pt stub where the
        // chevron was for eight seconds; the layout shift users saw was that stub.
        item.app?.activate(options: [.activateAllWindows])
    }

    @objc private func enableClickThrough() { Activator.requestTrust() }
    @objc private func openSettings() { controller?.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
