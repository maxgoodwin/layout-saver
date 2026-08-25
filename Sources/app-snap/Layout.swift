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
    /// Whether this is the layout to prefer when several saved layouts share the
    /// same fingerprint (used by auto-apply and the "matches current setup" menu
    /// grouping). At most one layout per fingerprint should be marked default —
    /// enforced by `LayoutStore.setDefault(_:)`, not by this type itself.
    var isDefault: Bool

    init(name: String, fingerprint: [String], displaysLabel: String, windows: [WindowState]) {
        self.id = UUID()
        self.name = name
        self.fingerprint = fingerprint
        self.displaysLabel = displaysLabel
        self.createdAt = Date()
        self.windows = windows
        self.isDefault = false
    }

    /// Custom decoding so layouts saved before `isDefault` existed (plain JSON
    /// with no such key) still decode cleanly, defaulting to `false`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        fingerprint = try container.decode([String].self, forKey: .fingerprint)
        displaysLabel = try container.decode(String.self, forKey: .displaysLabel)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        windows = try container.decode([WindowState].self, forKey: .windows)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
}
