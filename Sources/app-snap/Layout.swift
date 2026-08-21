import Foundation

/// A single window's saved position, size, and enough identity to find it again
/// later — either the same window (matched by title) or, failing that, the Nth
/// window of the same app (matched by index).
struct WindowState: Codable {
    var appBundleID: String
    var appName: String
    var title: String
    var windowIndex: Int
    var position: CGPoint
    var size: CGSize
    var displayUUID: String
}

/// A saved arrangement of windows, tied to the specific set of monitors it was
/// captured on via `fingerprint` (see `DisplayFingerprint`).
struct Layout: Codable, Identifiable {
    var id: UUID
    var name: String
    var fingerprint: [String]
    var displaysLabel: String
    var createdAt: Date
    var windows: [WindowState]

    init(name: String, fingerprint: [String], displaysLabel: String, windows: [WindowState]) {
        self.id = UUID()
        self.name = name
        self.fingerprint = fingerprint
        self.displaysLabel = displaysLabel
        self.createdAt = Date()
        self.windows = windows
    }
}
