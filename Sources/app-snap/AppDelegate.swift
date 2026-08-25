import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let layoutStore = LayoutStore()
    private var layoutsWindow: NSWindow?

    /// The monitor fingerprint as of the last auto-apply check, so we only react to
    /// an actual *change* in the connected display set rather than re-triggering on
    /// every debounced notification while it stays the same.
    private var lastFingerprint: Set<String> = []
    private var autoApplyDebounceTimer: Timer?
    private var statusMessageResetTimer: Timer?

    /// Snapshot of every window's position/size taken immediately before the
    /// most recent apply (manual or auto), so "Undo Last Apply" can put things
    /// back. In-memory only — intentionally not persisted, since it only makes
    /// sense to undo something from this same running session.
    private var undoSnapshot: [WindowState]?

    /// Fixed global shortcut for "apply whichever saved layout matches the
    /// current monitor setup, right now" — independent of auto-apply's
    /// monitor-change trigger. Held as monitor tokens so they can (in principle)
    /// be torn down; not currently user-configurable.
    private var globalShortcutMonitor: Any?
    private var localShortcutMonitor: Any?
    private static let shortcutModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
    private static let shortcutKeyCode: UInt16 = 37 // kVK_ANSI_L

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateStatusIcon()

        // Baseline the fingerprint at launch so we react to *changes* going
        // forward, not to whatever setup happens to already be connected.
        lastFingerprint = Set(DisplayFingerprint.currentFingerprint())
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        installGlobalShortcut()
    }

    /// Registers ⌃⌥⌘L to immediately apply whichever saved layout matches the
    /// current monitor setup — a manual escape hatch independent of
    /// auto-apply's monitor-change trigger (e.g. if a layout was updated after
    /// the setup was last detected, or auto-apply is off).
    ///
    /// `addGlobalMonitorForEvents` only *observes* key-down events system-wide
    /// (it can't consume/block them) and, like the window-control APIs
    /// elsewhere in this file, is gated by the same Accessibility trust
    /// app-snap already requires — no separate permission needed. The local
    /// monitor covers the case where one of app-snap's own windows (e.g. Manage
    /// Layouts) happens to be key, since the global monitor doesn't fire then.
    private func installGlobalShortcut() {
        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handlePotentialShortcut(event)
        }
        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handlePotentialShortcut(event)
            return event
        }
    }

    private func handlePotentialShortcut(_ event: NSEvent) {
        guard
            event.keyCode == Self.shortcutKeyCode,
            event.modifierFlags.intersection(.deviceIndependentFlagsMask) == Self.shortcutModifiers
        else { return }
        applyMatchingLayoutNow()
    }

    /// Applies whichever saved layout matches the current monitor setup right
    /// now, using the same default/last-used disambiguation as auto-apply.
    /// Shared by the global shortcut; shows a status message either way so it's
    /// clear the shortcut did something (or that there was nothing to apply).
    @objc private func applyMatchingLayoutNow() {
        guard AccessibilityPermission.isTrusted else {
            showStatusMessage("Accessibility access needed")
            return
        }

        let fingerprint = DisplayFingerprint.currentFingerprint()
        let matching = layoutStore.layouts(matching: fingerprint)
        guard !matching.isEmpty else {
            showStatusMessage("No saved layout for this setup")
            return
        }

        let layout = matching.first(where: \.isDefault)
            ?? matching.first { $0.id == Preferences.lastUsedLayoutID }
            ?? matching.first!

        undoSnapshot = WindowManager.captureCurrentWindows()

        Task {
            let result = await WindowManager.apply(layout.windows, launchMissingApps: layout.launchMissingApps)
            Preferences.lastUsedLayoutID = layout.id
            showStatusMessage("Applied “\(layout.name)” (\(result.appliedWindowCount) window\(result.appliedWindowCount == 1 ? "" : "s"))")
        }
    }

    /// Swaps the status-bar glyph between a filled and outline variant depending
    /// on whether the *current* monitor setup has any saved layout at all — a
    /// quick visual nudge to save one, discoverable without opening the menu.
    private func updateStatusIcon() {
        let hasMatch = !layoutStore.layouts(matching: DisplayFingerprint.currentFingerprint()).isEmpty
        let symbolName = hasMatch ? "rectangle.3.group.fill" : "rectangle.3.group"
        let description = hasMatch ? "app-snap (layout saved for this setup)" : "app-snap (no layout saved for this setup)"
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        updateStatusIcon()

        let trusted = AccessibilityPermission.isTrusted
        let fingerprint = DisplayFingerprint.currentFingerprint()

        menu.addItem(disabledItem("Current setup: \(DisplayFingerprint.currentLabel())"))

        if !trusted {
            menu.addItem(.separator())
            menu.addItem(disabledItem("⚠️ Accessibility access needed"))
            menu.addItem(item("Grant Accessibility Access…", #selector(grantAccess)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Save Current Layout…", #selector(saveCurrentLayout), enabled: trusted))

        let layouts = layoutStore.all()
        let applyItem = item("Apply Layout", nil, enabled: trusted && !layouts.isEmpty)
        applyItem.submenu = layouts.isEmpty ? nil : buildLayoutMenu(layouts: layouts, matching: fingerprint, action: #selector(applyLayout(_:)))
        menu.addItem(applyItem)

        let updateItem = item("Update Layout", nil, enabled: trusted && !layouts.isEmpty)
        updateItem.submenu = layouts.isEmpty ? nil : buildLayoutMenu(layouts: layouts, matching: fingerprint, action: #selector(updateLayout(_:)))
        menu.addItem(updateItem)

        let defaultItem = item("Set Default Layout", nil, enabled: !layouts.isEmpty)
        defaultItem.submenu = layouts.isEmpty ? nil : buildLayoutMenu(layouts: layouts, matching: fingerprint, action: #selector(setDefaultLayout(_:)), showDefaultMarker: true)
        menu.addItem(defaultItem)

        let launchMissingItem = item("Launch Missing Apps When Applying", nil, enabled: !layouts.isEmpty)
        launchMissingItem.submenu = layouts.isEmpty ? nil : buildLayoutMenu(layouts: layouts, matching: fingerprint, action: #selector(toggleLaunchMissingApps(_:)), showLaunchMissingMarker: true)
        menu.addItem(launchMissingItem)

        menu.addItem(item("Undo Last Apply", #selector(undoLastApply), enabled: trusted && undoSnapshot != nil))

        let shortcutItem = item("Apply Matching Layout Now", #selector(applyMatchingLayoutNow), enabled: trusted)
        shortcutItem.keyEquivalent = "l"
        shortcutItem.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(shortcutItem)

        menu.addItem(.separator())
        let autoApplyItem = item("Auto-Apply on Monitor Change", #selector(toggleAutoApply))
        autoApplyItem.state = Preferences.autoApplyEnabled ? .on : .off
        menu.addItem(autoApplyItem)

        // Only offered when running as a real .app bundle (has a bundle
        // identifier) — SMAppService.mainApp registers *this* bundle as a login
        // item, which is meaningless for a bare SwiftPM binary invoked directly
        // or via `brew services` (which already manages its own launchd job).
        if Bundle.main.bundleIdentifier != nil {
            let loginItem = item("Launch at Login", #selector(toggleLaunchAtLogin))
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(loginItem)
        }

        menu.addItem(.separator())
        menu.addItem(item("Manage Layouts…", #selector(openLayoutsWindow)))
        menu.addItem(.separator())
        menu.addItem(item("Quit app-snap", #selector(quit), keyEquivalent: "q"))
    }

    /// Builds a submenu listing every saved layout (current-setup matches grouped on
    /// top), wired to the given action. Shared by "Apply Layout", "Update Layout",
    /// "Set Default Layout" (`showDefaultMarker`), and "Launch Missing Apps When
    /// Applying" (`showLaunchMissingMarker`) — each marker option puts a checkmark
    /// on layouts where that respective flag is set.
    private func buildLayoutMenu(
        layouts: [Layout],
        matching fingerprint: [String],
        action: Selector,
        showDefaultMarker: Bool = false,
        showLaunchMissingMarker: Bool = false
    ) -> NSMenu {
        let submenu = NSMenu()
        let matchSet = Set(fingerprint)
        // Default-for-its-fingerprint layouts sort first within each group.
        let matching = layouts.filter { Set($0.fingerprint) == matchSet }.sorted { $0.isDefault && !$1.isDefault }
        let others = layouts.filter { Set($0.fingerprint) != matchSet }.sorted { $0.isDefault && !$1.isDefault }

        func addLayout(_ layout: Layout) {
            let title = layout.isDefault ? "\(layout.name) (\(layout.displaysLabel)) — Default" : "\(layout.name) (\(layout.displaysLabel))"
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = layout.id
            if showDefaultMarker { menuItem.state = layout.isDefault ? .on : .off }
            if showLaunchMissingMarker { menuItem.state = layout.launchMissingApps ? .on : .off }
            submenu.addItem(menuItem)
        }

        if !matching.isEmpty {
            submenu.addItem(disabledItem("Matches current setup"))
            matching.forEach(addLayout)
        }
        if !others.isEmpty {
            if !matching.isEmpty { submenu.addItem(.separator()) }
            submenu.addItem(disabledItem("Other setups"))
            others.forEach(addLayout)
        }
        return submenu
    }

    private func item(_ title: String, _ action: Selector?, keyEquivalent: String = "", enabled: Bool = true) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.target = self
        menuItem.isEnabled = enabled
        return menuItem
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        return menuItem
    }

    // MARK: - Actions

    @objc private func grantAccess() {
        AccessibilityPermission.requestAccess()
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func toggleAutoApply() {
        Preferences.autoApplyEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            inform(title: "Couldn't Update Login Item", body: error.localizedDescription)
        }
    }

    // MARK: - Auto-apply on monitor change

    /// macOS fires `didChangeScreenParametersNotification` repeatedly while a
    /// display is connecting/disconnecting (as the OS renegotiates modes), so we
    /// debounce and only act once things settle.
    @objc private func screenParametersChanged() {
        autoApplyDebounceTimer?.invalidate()
        autoApplyDebounceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.checkForAutoApply() }
        }
    }

    private func checkForAutoApply() {
        let fingerprint = Set(DisplayFingerprint.currentFingerprint())
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        updateStatusIcon()

        guard Preferences.autoApplyEnabled, AccessibilityPermission.isTrusted else { return }

        let matching = layoutStore.layouts(matching: Array(fingerprint))
        guard !matching.isEmpty else { return }

        // If several saved layouts share this fingerprint: prefer the one
        // explicitly marked default, then the one most recently applied/updated,
        // then whichever comes first — otherwise there's only one candidate.
        let layout = matching.first(where: \.isDefault)
            ?? matching.first { $0.id == Preferences.lastUsedLayoutID }
            ?? matching.first!

        undoSnapshot = WindowManager.captureCurrentWindows()

        Task {
            let result = await WindowManager.apply(layout.windows, launchMissingApps: layout.launchMissingApps)
            Preferences.lastUsedLayoutID = layout.id
            showStatusMessage("Auto-applied “\(layout.name)” (\(result.appliedWindowCount) window\(result.appliedWindowCount == 1 ? "" : "s"))")
        }
    }

    /// Briefly shows a status-bar title (rather than a modal alert, which would
    /// interrupt whatever the user is doing right as they reconnect a monitor).
    private func showStatusMessage(_ text: String) {
        statusMessageResetTimer?.invalidate()
        statusItem.button?.title = " \(text)"
        statusMessageResetTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.statusItem.button?.title = "" }
        }
    }

    @objc private func saveCurrentLayout() {
        let alert = NSAlert()
        alert.messageText = "Save Current Layout"
        alert.informativeText = "Name this arrangement so you can find it later."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = DisplayFingerprint.currentLabel()
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let typedName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typedName.isEmpty ? DisplayFingerprint.currentLabel() : typedName

        let windows = WindowManager.captureCurrentWindows()
        let layout = Layout(
            name: name,
            fingerprint: DisplayFingerprint.currentFingerprint(),
            displaysLabel: DisplayFingerprint.currentLabel(),
            windows: windows
        )
        layoutStore.save(layout)
        inform(title: "Layout Saved", body: "Saved \(windows.count) window\(windows.count == 1 ? "" : "s") as “\(name)”.")
    }

    @objc private func applyLayout(_ sender: NSMenuItem) {
        guard
            let id = sender.representedObject as? UUID,
            let layout = layoutStore.all().first(where: { $0.id == id })
        else { return }

        undoSnapshot = WindowManager.captureCurrentWindows()

        Task {
            let result = await WindowManager.apply(layout.windows, launchMissingApps: layout.launchMissingApps)
            Preferences.lastUsedLayoutID = layout.id

            var body = "Applied \(result.appliedWindowCount) window\(result.appliedWindowCount == 1 ? "" : "s")."
            if !result.skippedApps.isEmpty {
                body += " Not running: \(result.skippedApps.joined(separator: ", "))."
            }
            inform(title: "Applied “\(layout.name)”", body: body)
        }
    }

    @objc private func undoLastApply() {
        guard let snapshot = undoSnapshot else { return }
        undoSnapshot = nil
        Task {
            let result = await WindowManager.apply(snapshot)
            showStatusMessage("Undid last apply (\(result.appliedWindowCount) window\(result.appliedWindowCount == 1 ? "" : "s"))")
        }
    }

    @objc private func toggleLaunchMissingApps(_ sender: NSMenuItem) {
        guard
            let id = sender.representedObject as? UUID,
            var layout = layoutStore.all().first(where: { $0.id == id })
        else { return }
        layout.launchMissingApps.toggle()
        layoutStore.save(layout)
    }

    @objc private func setDefaultLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        layoutStore.setDefault(id)
    }

    @objc private func updateLayout(_ sender: NSMenuItem) {
        guard
            let id = sender.representedObject as? UUID,
            let layout = layoutStore.all().first(where: { $0.id == id })
        else { return }

        guard confirmUpdate(of: layout) else { return }

        let updated = LayoutStore.updating(layout, withCurrentWindows: WindowManager.captureCurrentWindows())
        layoutStore.save(updated)
        inform(title: "Layout Updated", body: "Updated “\(layout.name)” with \(updated.windows.count) window\(updated.windows.count == 1 ? "" : "s").")
    }

    /// Shared confirmation prompt for overwriting a saved layout, used by both the
    /// menu bar's "Update Layout" submenu and the Manage Layouts window.
    private func confirmUpdate(of layout: Layout) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Update “\(layout.name)”?"
        alert.informativeText = "This overwrites the saved layout with your current window arrangement (\(DisplayFingerprint.currentLabel()))."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func openLayoutsWindow() {
        if layoutsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            let hostingController = NSHostingController(rootView: LayoutsView(store: layoutStore))
            hostingController.sizingOptions = [.preferredContentSize]
            window.title = "app-snap Layouts"
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.center()
            layoutsWindow = window
        }
        layoutsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// A quick modal summary rather than a system notification: app-snap ships as
    /// a bare, unsigned SwiftPM binary with no bundle identifier, and
    /// UNUserNotificationCenter/NSUserNotification are unreliable (often silently
    /// no-op) without one. An alert always works.
    private func inform(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
