import Foundation

/// User-configurable settings, backed by UserDefaults so they survive relaunches
/// (including relaunches driven by `brew services`).
enum Preferences {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let lastUsedLayoutID = "lastUsedLayoutID"
        static let autoApplyEnabled = "autoApplyEnabled"
    }

    /// Remembers the last-applied layout so the menu can show it as a quick default,
    /// and so auto-apply can disambiguate when several saved layouts share a
    /// fingerprint (see `AppDelegate.checkForAutoApply`).
    static var lastUsedLayoutID: UUID? {
        get {
            guard let raw = defaults.string(forKey: Key.lastUsedLayoutID) else { return nil }
            return UUID(uuidString: raw)
        }
        set { defaults.set(newValue?.uuidString, forKey: Key.lastUsedLayoutID) }
    }

    /// Whether layout-saver should automatically apply a matching saved layout when it
    /// detects the connected monitor set has changed. Defaults to on; there's no
    /// stored value yet the first time this is read, so fall back to `true` rather
    /// than UserDefaults' usual `false` default for missing Bool keys.
    static var autoApplyEnabled: Bool {
        get {
            if defaults.object(forKey: Key.autoApplyEnabled) == nil { return true }
            return defaults.bool(forKey: Key.autoApplyEnabled)
        }
        set { defaults.set(newValue, forKey: Key.autoApplyEnabled) }
    }
}
