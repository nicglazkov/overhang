import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let bar = BarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        bar.start()
    }
}
