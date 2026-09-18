import Foundation

/// Tells a slide *along* the top or bottom edge (a volume or brightness slider)
/// from a pull *away* from it (the shade, the control centre, leaving fullscreen).
public enum EdgeSlide {
    public enum Decision: Equatable, Sendable { case undecided, slide, pull }

    /// `along` is travel parallel to the edge, `inward` is travel away from it
    /// (negative when the finger moves toward the edge). A pull wins as soon as it
    /// qualifies, so the existing edge gestures keep their feel; a slide needs to be
    /// clearly sideways.
    public static func decide(along: Double, inward: Double, startedInBand: Bool,
                              pullActivate: Double = 10, slideActivate: Double = 34) -> Decision {
        if inward > pullActivate { return .pull }
        if startedInBand, abs(along) >= slideActivate, abs(along) > abs(inward) * 3 { return .slide }
        return .undecided
    }

    /// The slider's new value: `travel` is a fraction of the panel's width, and a
    /// little over half the strip covers the whole range.
    public static func value(start: Double, travel: Double, fullRange: Double = 0.55) -> Double {
        min(1, max(0, start + travel / fullRange))
    }
}
