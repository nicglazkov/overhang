import AppKit

/// One status item as WindowServer sees it.
struct MenuBarItem: Hashable {
    let windowNumber: Int
    let pid: pid_t
    let ownerName: String
    let frame: CGRect
    let isOnscreen: Bool

    var app: NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }

    /// The owning app's bundle icon. Free — no TCC permission involved.
    var icon: NSImage? {
        let image = app?.icon
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    /// Prefer the app's localized name; fall back to the window owner string.
    var displayName: String { app?.localizedName ?? ownerName }
}

/// Read-only view of the menu bar. No state, no side effects.
enum StatusItemScanner {
    /// Status items sit one layer above the menu bar itself (24).
    static let statusLayer = Int(CGWindowLevelForKey(.statusWindow))

    /// Menu bar strip is 38pt on notched Macs; allow slack for the drop shadow.
    private static let maxItemHeight: CGFloat = 45
    private static let maxItemY: CGFloat = 5

    /// Every status item, including ones WindowServer declined to composite.
    static func scan() -> [MenuBarItem] {
        let options: CGWindowListOption = [.optionAll]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap(parse).sorted { $0.frame.minX < $1.frame.minX }
    }

    private static func parse(_ window: [String: Any]) -> MenuBarItem? {
        guard (window[kCGWindowLayer as String] as? Int) == statusLayer,
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let width = bounds["Width"], let height = bounds["Height"],
              height <= maxItemHeight, y < maxItemY, width > 0,
              let number = window[kCGWindowNumber as String] as? Int,
              let pid = window[kCGWindowOwnerPID as String] as? pid_t
        else { return nil }

        return MenuBarItem(
            windowNumber: number,
            pid: pid,
            ownerName: window[kCGWindowOwnerName as String] as? String ?? "Unknown",
            frame: CGRect(x: x, y: y, width: width, height: height),
            isOnscreen: (window[kCGWindowIsOnscreen as String] as? Bool) ?? false
        )
    }

    /// Items the user has lost access to.
    ///
    /// An offscreen item is only a real casualty if nothing live occupies its space. Control
    /// Center leaves stale offscreen windows behind for modules the user disabled, and those
    /// overlap items that *are* on screen — without the intersection test they show up as
    /// phantoms in the menu.
    static func casualties(in items: [MenuBarItem], excluding ownPID: pid_t = getpid()) -> [MenuBarItem] {
        let live = items.filter { $0.isOnscreen }.map(\.frame)
        return items.filter { item in
            guard !item.isOnscreen else { return false }
            guard item.pid != ownPID else { return false }
            guard item.frame.minX > 0 else { return false }   // TextInputMenuAgent parks at x=0
            return !live.contains { $0.intersects(item.frame) }
        }
    }

    /// Items currently drawn, excluding our own.
    static func visible(in items: [MenuBarItem], excluding ownPID: pid_t = getpid()) -> [MenuBarItem] {
        items.filter { $0.isOnscreen && $0.pid != ownPID }
    }
}
