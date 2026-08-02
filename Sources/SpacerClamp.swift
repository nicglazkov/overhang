import CoreGraphics

/// Clamp arithmetic for the spacer, kept pure and dependency-free so it can be tested without
/// a live menu bar.
enum SpacerClamp {
    /// Daylight kept between the chevron and the notch boundary.
    static let margin: CGFloat = 8

    /// Largest spacer length that still leaves the chevron on screen.
    ///
    /// Growing the spacer shifts the whole third-party run leftward, the chevron included. If
    /// the chevron crosses the notch boundary it is culled and the app becomes unreachable.
    /// Observed at length 10000, which displaced every third-party item. Headroom is therefore
    /// measured from the chevron's live position rather than assumed.
    static func maxLength(chevronMinX: CGFloat,
                          notchMinX: CGFloat,
                          currentLength: CGFloat,
                          margin: CGFloat = margin) -> CGFloat {
        let headroom = chevronMinX - notchMinX - margin
        return max(0, currentLength + headroom)
    }

    static func clamp(_ proposed: CGFloat,
                      chevronMinX: CGFloat,
                      notchMinX: CGFloat,
                      currentLength: CGFloat,
                      margin: CGFloat = margin) -> CGFloat {
        let ceiling = maxLength(chevronMinX: chevronMinX,
                                notchMinX: notchMinX,
                                currentLength: currentLength,
                                margin: margin)
        return min(max(0, proposed), ceiling)
    }
}
