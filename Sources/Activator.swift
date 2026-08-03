import AppKit
import ApplicationServices

/// What happened when we tried to open a hidden item.
enum ActivationOutcome {
    /// The item's own menu or popover appeared. Nothing further needed.
    case opened
    /// We are not trusted for Accessibility, or the press did nothing. Caller should fall back.
    case failed
}

/// Presses another app's status item via the Accessibility API.
///
/// Coverage is partial by nature: items backed by an `NSMenu` respond to `AXPress`, but items
/// that consume the mouse event themselves (popover-based items, observed in testing)
/// ignore it even when fully visible. We therefore never assume success, we press, look for
/// something to actually appear, and report honestly so the caller can degrade.
enum Activator {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt. Only ever called from an explicit menu action, /// the app must never prompt on its own.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Press the item and confirm something appeared.
    static func open(_ item: MenuBarItem) -> ActivationOutcome {
        guard isTrusted, let element = element(for: item) else { return .failed }

        let before = windowCount(pid: item.pid)
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            return .failed
        }

        // Menus and popovers are windows. Poll rather than guessing a fixed delay, and give a
        // slow app real time: a menu that opens at 700ms is a success, and misreading it as a
        // failure used to fire the fallback on top of a working click-through.
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.08)
            if hasMenuChild(element) || windowCount(pid: item.pid) > before { return .opened }
        }
        return .failed
    }

    // MARK: - Element lookup

    /// The AX element for this specific status item.
    ///
    /// An app can own several (Stats has four), so when there is a choice we match on horizontal
    /// centre against the frame WindowServer reported. AX position and CGWindow bounds differ by
    /// a few points of padding, hence nearest-match rather than equality.
    private static func element(for item: MenuBarItem) -> AXUIElement? {
        let app = AXUIElementCreateApplication(item.pid)

        var extras: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &extras) == .success,
              let raw = extras, CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        let bar = raw as! AXUIElement

        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &kids) == .success,
              let children = kids as? [AXUIElement], !children.isEmpty
        else { return nil }

        if children.count == 1 { return children[0] }
        let target = item.frame.midX
        return children.min { abs(centerX($0) - target) < abs(centerX($1) - target) }
    }

    private static func centerX(_ element: AXUIElement) -> CGFloat {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let p = positionRef, let s = sizeRef,
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID()
        else { return .greatestFiniteMagnitude }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return point.x + size.width / 2
    }

    // MARK: - Did anything appear?

    private static func hasMenuChild(_ element: AXUIElement) -> Bool {
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &kids) == .success,
              let children = kids as? [AXUIElement] else { return false }
        return children.contains { child in
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success
            else { return false }
            return (role as? String) == kAXMenuRole
        }
    }

    /// On-screen windows big enough to be a menu or popover. An observed menu measured 121×54,
    /// so the floor has to stay low.
    private static func windowCount(pid: pid_t) -> Int {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return 0 }
        return raw.filter { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let b = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = b["Width"], let h = b["Height"] else { return false }
            return w > 60 && h > 40
        }.count
    }
}
