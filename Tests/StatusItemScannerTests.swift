import XCTest

/// Casualty classification is the one piece of judgement in the scanner, and getting it wrong is
/// user-visible in both directions: miss a real casualty and the item stays unreachable; admit a
/// phantom and the menu fills with entries that do nothing.
///
/// Fixtures below are taken from a real 14" MacBook Pro bar, including the Control Center
/// phantoms that motivated the intersection test.
final class StatusItemScannerTests: XCTestCase {
    private let ownPID: pid_t = 999

    private func item(_ name: String, x: CGFloat, w: CGFloat,
                      onscreen: Bool, pid: pid_t = 100) -> MenuBarItem {
        MenuBarItem(windowNumber: Int(x), pid: pid, ownerName: name,
                    frame: CGRect(x: x, y: 0, width: w, height: 38), isOnscreen: onscreen)
    }

    func testCulledItemIsACasualty() {
        // An overflowing item, allocated x=1010 to 1050 and never composited.
        let items = [item("Docker Desktop", x: 1010, w: 40, onscreen: false),
                     item("JetBrains Toolbox", x: 1050, w: 38, onscreen: true)]
        let casualties = StatusItemScanner.casualties(in: items, safeAreaMinX: 1010, excluding: ownPID)
        XCTAssertEqual(casualties.map(\.ownerName), ["Docker Desktop"])
    }

    func testDisabledControlCenterModulesAreNotCasualties() {
        // Control Center leaves stale offscreen windows for modules the user switched off. They
        // overlap live items, which is how we tell them apart from real casualties.
        let items = [item("Ollama", x: 1348, w: 38, onscreen: true),
                     item("Control Center", x: 1350, w: 36, onscreen: false),
                     item("Control Center", x: 1479, w: 48, onscreen: false),
                     item("Control Center", x: 1466, w: 38, onscreen: true)]
        XCTAssertTrue(StatusItemScanner.casualties(in: items, safeAreaMinX: 1010, excluding: ownPID).isEmpty,
                      "phantoms overlap live items and must be filtered")
    }

    func testOwnItemsAreNeverCasualties() {
        // The app hides its own spacer; reporting it would be nonsense.
        let items = [item("Overhang", x: 900, w: 17, onscreen: false, pid: ownPID)]
        XCTAssertTrue(StatusItemScanner.casualties(in: items, safeAreaMinX: 1010, excluding: ownPID).isEmpty)
    }

    func testItemsParkedAtOriginAreIgnored() {
        // TextInputMenuAgent sits at x=0 permanently; it is not a casualty.
        let items = [item("TextInputMenuAgent", x: 0, w: 35, onscreen: false)]
        XCTAssertTrue(StatusItemScanner.casualties(in: items, safeAreaMinX: 1010, excluding: ownPID).isEmpty)
    }

    func testOnscreenItemsAreNeverCasualties() {
        let items = [item("Stats", x: 1160, w: 47, onscreen: true),
                     item("Stats", x: 1207, w: 47, onscreen: true)]
        XCTAssertTrue(StatusItemScanner.casualties(in: items, safeAreaMinX: 1010, excluding: ownPID).isEmpty)
    }

    func testSpacerHiddenRunIsReportedInFull() {
        // With the spacer at 150pt, eight items were pushed left of the notch. All are casualties.
        let pushed = [("UTM", 741.0), ("Docker Desktop", 773.0), ("Ollama", 806.0),
                      ("JetBrains Toolbox", 846.0), ("Stats", 884.0), ("Multipass", 918.0)]
        var items = pushed.enumerated().map { i, p in
            item(p.0, x: CGFloat(p.1), w: 30, onscreen: false, pid: pid_t(200 + i))
        }
        items.append(item("Ollama", x: 1144, w: 38, onscreen: true))
        let casualties = StatusItemScanner.casualties(in: items, safeAreaMinX: 1010, excluding: ownPID)
        XCTAssertEqual(casualties.count, 6)
        XCTAssertEqual(casualties.first?.ownerName, "UTM", "results stay in left-to-right order")
    }


    func testItemParkedOnscreenInsideTheDeadZoneIsACasualty() {
        // macOS layout quirk observed live: an item registered into a crowded bar and was
        // parked at x=974 inside the dead zone, still marked onscreen, composited behind the
        // physical notch where it can be neither seen nor clicked.
        let items = [item("Pixel Audio Bridge", x: 974, w: 33, onscreen: true, pid: 300),
                     item("UTM", x: 1052, w: 32, onscreen: true, pid: 301)]
        let casualties = StatusItemScanner.casualties(in: items, safeAreaMinX: 1010, excluding: ownPID)
        XCTAssertEqual(casualties.map(\.ownerName), ["Pixel Audio Bridge"])
    }

    func testParkedRuleIsInertWithoutANotch() {
        // safeAreaMinX 0 models a display with no notch: everything onscreen is reachable.
        let items = [item("Docker Desktop", x: 20, w: 45, onscreen: true)]
        XCTAssertTrue(StatusItemScanner.casualties(in: items, safeAreaMinX: 0, excluding: ownPID).isEmpty)
    }

    func testVisibleExcludesOwnItems() {
        let items = [item("Stats", x: 1160, w: 47, onscreen: true),
                     item("Overhang", x: 1568, w: 38, onscreen: true, pid: ownPID)]
        XCTAssertEqual(StatusItemScanner.visible(in: items, excluding: ownPID).map(\.ownerName), ["Stats"])
    }
}
