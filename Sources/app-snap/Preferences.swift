import Foundation

/// User-configurable settings, backed by UserDefaults so they survive relaunches
/// (including relaunches driven by `brew services`). Minimal for Phase 1 — grows
/// with auto-apply-on-monitor-change in Phase 2.
enum Preferences {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let lastUsedLayoutID = "lastUsedLayoutID"
    }

    /// Remembers the last-applied layout so the menu can show it as a quick default.
    static var lastUsedLayoutID: UUID? {
        get {
            guard let raw = defaults.string(forKey: Key.lastUsedLayoutID) else { return nil }
            return UUID(uuidString: raw)
        }
        set { defaults.set(newValue?.uuidString, forKey: Key.lastUsedLayoutID) }
    }
}
