import XCTest

/// The clamp exists to prevent one specific catastrophe: the app pushing its own chevron off
/// screen, leaving the user with no way to reach it. Numbers below come from a real 14" MacBook
/// Pro, notch boundary at x=1010, chevron parked at x=1568.
final class SpacerClampTests: XCTestCase {
    private let notch: CGFloat = 1010
    private let chevron: CGFloat = 1568

    func testRejectsLengthThatWouldSwallowTheChevron() {
        // The observed failure: length 10000 displaced every third-party item, chevron included.
        let clamped = SpacerClamp.clamp(10000, chevronMinX: chevron, notchMinX: notch, currentLength: 0)
        XCTAssertEqual(clamped, 550, "should cap at the chevron's headroom, not the request")
        XCTAssertLessThan(clamped, 10000)
    }

    func testAllowsModestGrowth() {
        let clamped = SpacerClamp.clamp(150, chevronMinX: chevron, notchMinX: notch, currentLength: 0)
        XCTAssertEqual(clamped, 150, "150pt is well inside the headroom and must pass through")
    }

    func testHeadroomShrinksAsTheSpacerGrows() {
        // After growing by 400, the chevron has slid 400 closer to the notch.
        let ceilingAtRest = SpacerClamp.maxLength(chevronMinX: chevron, notchMinX: notch, currentLength: 0)
        let ceilingAfterGrowth = SpacerClamp.maxLength(chevronMinX: chevron - 400, notchMinX: notch, currentLength: 400)
        XCTAssertEqual(ceilingAtRest, ceilingAfterGrowth,
                       "total reachable length is invariant, the spacer trades its own width for headroom")
    }

    func testNeverReturnsNegative() {
        XCTAssertEqual(SpacerClamp.clamp(-500, chevronMinX: chevron, notchMinX: notch, currentLength: 0), 0)
    }

    func testChevronAlreadyAtTheBoundaryYieldsNoHeadroom() {
        // Nothing further may be hidden once the chevron is against the notch.
        let ceiling = SpacerClamp.maxLength(chevronMinX: notch, notchMinX: notch, currentLength: 0)
        XCTAssertEqual(ceiling, 0)
    }

    func testMarginIsRespected() {
        // Exactly `margin` of daylight must survive.
        let ceiling = SpacerClamp.maxLength(chevronMinX: notch + SpacerClamp.margin,
                                            notchMinX: notch, currentLength: 0)
        XCTAssertEqual(ceiling, 0, "margin is consumed before any hiding is permitted")
    }

    func testExternalDisplayWithNoNotch() {
        // On a notch-free screen the boundary is simply x=0, so headroom is the full width.
        let ceiling = SpacerClamp.maxLength(chevronMinX: 1900, notchMinX: 0, currentLength: 0)
        XCTAssertEqual(ceiling, 1892)
    }
}
