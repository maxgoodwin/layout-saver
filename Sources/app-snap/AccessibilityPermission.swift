import AppKit
import ApplicationServices

/// Gates all window-control features on macOS's Accessibility (TCC) permission —
/// without it, AXUIElement calls to other processes silently fail.
enum AccessibilityPermission {
    /// Check-only, no system prompt. Safe to call often (e.g. on menu open).
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system "app-snap would like to control this computer" prompt
    /// if not already trusted, which deep-links the user into System Settings.
    /// Calling this repeatedly after the user has dismissed the prompt once has
    /// no further effect, which is why `openSystemSettings()` exists as a fallback.
    @discardableResult
    static func requestAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
