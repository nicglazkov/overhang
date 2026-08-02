import AppKit
import SwiftUI

/// Settings and About in one panel. A menu bar utility with a dozen preferences buried in a
/// submenu is worse than one small window, so everything adjustable lives here.
final class SettingsWindowController {
    private var window: NSWindow?
    weak var controller: BarController?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(controller: controller))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Overhang"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        // Accessory apps are not in the Dock, so the window needs an explicit activation to
        // come forward, otherwise it opens behind whatever the user is looking at.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    weak var controller: BarController?

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var hiddenWidth: Double = 0
    @State private var trusted = Activator.isTrusted
    @State private var hiddenCount = 0

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "Version \(v)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if LoginItem.setEnabled(newValue) == nil { launchAtLogin = LoginItem.isEnabled }
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hide from the bar")
                        Spacer()
                        Text("\(Int(hiddenWidth))pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $hiddenWidth, in: 0...400, step: 10) { editing in
                        if !editing { apply() }
                    }
                    Text("Pushes items off the left edge to make room. \(hiddenCount) item\(hiddenCount == 1 ? "" : "s") currently hidden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        // Without this the caption truncates instead of wrapping inside the
                        // window's fixed width.
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(trusted ? .green : .orange)
                        Text(trusted ? "Click-through enabled" : "Click-through disabled")
                        Spacer()
                        if !trusted {
                            Button("Enable…") { Activator.requestTrust() }
                        }
                    }
                    Text(trusted
                         ? "Clicking a hidden item opens its own menu directly."
                         : "Without Accessibility, hidden items are revealed in the bar for you to click by hand.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)

            Divider()
            HStack {
                Text("No data leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit Overhang") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 380)
        .onAppear(perform: refresh)
        // The window is reused rather than rebuilt, so onAppear fires only once. Without this
        // the panel shows whatever was true the first time it was opened.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("Overhang").font(.title2).bold()
                Text(version).font(.caption).foregroundStyle(.secondary)
                Text("Reaches menu bar items hidden by the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private func refresh() {
        launchAtLogin = LoginItem.isEnabled
        trusted = Activator.isTrusted
        hiddenWidth = Double(controller?.currentSpacerLength ?? 0)
        hiddenCount = StatusItemScanner.casualties(in: StatusItemScanner.scan()).count
    }

    private func apply() {
        controller?.applyLength(CGFloat(hiddenWidth))
        // The controller clamps, so read back rather than trusting what the slider asked for.
        hiddenWidth = Double(controller?.currentSpacerLength ?? 0)
        hiddenCount = StatusItemScanner.casualties(in: StatusItemScanner.scan()).count
    }
}
