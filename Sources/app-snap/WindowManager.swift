import AppKit
import ApplicationServices

/// Reads and writes window position/size for other running apps via the
/// Accessibility API. All coordinates read and written here are in AX's native
/// global display space (top-left origin) — never converted to/from Cocoa's
/// bottom-left-origin NSScreen space, which is the classic source of windows
/// landing tens of pixels off from where they should be.
enum WindowManager {
    struct ApplyResult {
        var appliedWindowCount = 0
        var skippedApps: [String] = []
        var skippedWindows = 0
    }

    // MARK: - Capture

    /// Snapshots every eligible window of every regular (non-background/agent) app
    /// currently running, tagging each with which connected display it's on.
    static func captureCurrentWindows() -> [WindowState] {
        var states: [WindowState] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            let windows = axWindows(of: axApp)

            for (index, window) in windows.enumerated() {
                guard !isMinimized(window), !isFullScreen(window) else { continue }
                guard let position = position(of: window), let size = size(of: window) else { continue }
                let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
                let displayUUID = DisplayFingerprint.display(containing: center)?.uuid ?? ""

                states.append(WindowState(
                    appBundleID: bundleID,
                    appName: app.localizedName ?? bundleID,
                    title: title(of: window) ?? "",
                    windowIndex: index,
                    position: position,
                    size: size,
                    displayUUID: displayUUID
                ))
            }
        }

        return states
    }

    // MARK: - Apply

    /// Restores each saved window's position/size on whichever running app owns
    /// it, matching windows by title first (stable across relaunch) and falling
    /// back to index. Apps that aren't currently running are skipped, per the
    /// "position/size of currently-running apps only" scope.
    static func apply(_ windows: [WindowState]) -> ApplyResult {
        var result = ApplyResult()
        let runningByBundleID = Dictionary(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
                .map { ($0.bundleIdentifier!, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let byApp = Dictionary(grouping: windows, by: \.appBundleID)
        for (bundleID, savedWindows) in byApp {
            guard let app = runningByBundleID[bundleID] else {
                result.skippedApps.append(savedWindows.first?.appName ?? bundleID)
                continue
            }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            let liveWindows = axWindows(of: axApp)

            for saved in savedWindows {
                guard let target = matchWindow(saved, in: liveWindows) else {
                    result.skippedWindows += 1
                    continue
                }
                if set(position: saved.position, size: saved.size, on: target) {
                    result.appliedWindowCount += 1
                } else {
                    result.skippedWindows += 1
                }
            }
        }

        return result
    }

    private static func matchWindow(_ saved: WindowState, in liveWindows: [AXUIElement]) -> AXUIElement? {
        if !saved.title.isEmpty, let byTitle = liveWindows.first(where: { title(of: $0) == saved.title }) {
            return byTitle
        }
        guard saved.windowIndex >= 0, saved.windowIndex < liveWindows.count else { return nil }
        return liveWindows[saved.windowIndex]
    }

    /// Sets size, then position, then size again — the repeated size call defeats
    /// macOS's habit of clamping a window's size to fit its *current* display
    /// while it's still being repositioned onto a different one.
    private static func set(position: CGPoint, size: CGSize, on window: AXUIElement) -> Bool {
        guard
            isSettable(window, kAXSizeAttribute),
            isSettable(window, kAXPositionAttribute)
        else { return false }

        setSize(size, on: window)
        setPosition(position, on: window)
        setSize(size, on: window)
        return true
    }

    // MARK: - AX attribute helpers

    private static func axWindows(of app: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(app, kAXWindowsAttribute) else { return [] }
        return (value as? [AXUIElement])?.filter { role(of: $0) == kAXWindowRole } ?? []
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    private static func role(of window: AXUIElement) -> String? {
        copyAttribute(window, kAXRoleAttribute) as? String
    }

    private static func title(of window: AXUIElement) -> String? {
        copyAttribute(window, kAXTitleAttribute) as? String
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        (copyAttribute(window, kAXMinimizedAttribute) as? Bool) ?? false
    }

    private static func isFullScreen(_ window: AXUIElement) -> Bool {
        (copyAttribute(window, "AXFullScreen") as? Bool) ?? false
    }

    private static func position(of window: AXUIElement) -> CGPoint? {
        guard let value = copyAttribute(window, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue((value as! AXValue), .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(of window: AXUIElement) -> CGSize? {
        guard let value = copyAttribute(window, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue((value as! AXValue), .cgSize, &size) else { return nil }
        return size
    }

    private static func isSettable(_ window: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        let error = AXUIElementIsAttributeSettable(window, attribute as CFString, &settable)
        return error == .success && settable.boolValue
    }

    private static func setPosition(_ point: CGPoint, on window: AXUIElement) {
        var mutablePoint = point
        guard let axValue = AXValueCreate(.cgPoint, &mutablePoint) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
    }

    private static func setSize(_ size: CGSize, on window: AXUIElement) {
        var mutableSize = size
        guard let axValue = AXValueCreate(.cgSize, &mutableSize) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
    }
}
