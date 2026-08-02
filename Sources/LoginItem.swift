import AppKit
import ServiceManagement

/// Launch-at-login, via the modern registration API.
///
/// `SMAppService.mainApp` needs no helper bundle and no `SMLoginItemSetEnabled` shim, the
/// system reads the app's own bundle. Registration survives moves within /Applications.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns the resulting state, or nil if the system refused.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return isEnabled
        } catch {
            NSLog("Overhang: login item \(enabled ? "register" : "unregister") failed, \(error)")
            return nil
        }
    }

    static func toggle() { setEnabled(!isEnabled) }
}
