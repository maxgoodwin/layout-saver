import AppKit

/// Identifies the currently connected set of monitors, independent of cable/port
/// order, so a saved layout can be tied to "this physical set of displays" rather
/// than to a specific arrangement that might shuffle on reconnect.
///
/// Deliberately built on CGDirectDisplayID / CGDisplayBounds rather than NSScreen:
/// CGDisplayBounds is in the same top-left-origin "global display space" that the
/// Accessibility API's window positions use, so window frames can be compared
/// against display frames directly with no Cocoa Y-flip to get wrong.
enum DisplayFingerprint {
    struct DisplayInfo {
        var uuid: String
        var bounds: CGRect
    }

    private static let maxDisplays: UInt32 = 16

    /// One entry per active display, in on-screen (CGGetActiveDisplayList) order —
    /// not sorted; callers that need order-independence should compare `Set(ids)`.
    static func currentDisplays() -> [DisplayInfo] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else { return [] }

        let count = min(displayCount, maxDisplays)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &displayCount) == .success else { return [] }

        return displayIDs.compactMap { displayID in
            guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
            let uuidString = CFUUIDCreateString(nil, cfUUID) as String? ?? "unknown-\(displayID)"
            return DisplayInfo(uuid: uuidString, bounds: CGDisplayBounds(displayID))
        }
    }

    /// Order-independent identity of the current monitor set — this is what
    /// layouts are stored and matched against.
    static func currentFingerprint() -> [String] {
        currentDisplays().map(\.uuid).sorted()
    }

    /// Human-readable summary for the menu header, e.g. "2 displays" or "Built-in only".
    static func currentLabel() -> String {
        let count = currentDisplays().count
        if count <= 1 { return "Built-in display only" }
        return "\(count) displays"
    }

    /// Which connected display's bounds contain `point` (an AX-space window
    /// position), falling back to the display whose bounds the point is nearest
    /// to when the window straddles an edge or sits slightly off-screen.
    static func display(containing point: CGPoint) -> DisplayInfo? {
        let displays = currentDisplays()
        if let exact = displays.first(where: { $0.bounds.contains(point) }) {
            return exact
        }
        return displays.min { lhs, rhs in
            distance(point, lhs.bounds) < distance(point, rhs.bounds)
        }
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
