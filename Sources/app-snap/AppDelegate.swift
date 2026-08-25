import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let layoutStore = LayoutStore()
    private var layoutsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "app-snap")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

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

        menu.addItem(.separator())
        menu.addItem(item("Manage Layouts…", #selector(openLayoutsWindow)))
        menu.addItem(.separator())
        menu.addItem(item("Quit app-snap", #selector(quit), keyEquivalent: "q"))
    }

    /// Builds a submenu listing every saved layout (current-setup matches grouped on
    /// top), wired to the given action. Shared by "Apply Layout" and "Update Layout".
    private func buildLayoutMenu(layouts: [Layout], matching fingerprint: [String], action: Selector) -> NSMenu {
        let submenu = NSMenu()
        let matchSet = Set(fingerprint)
        let matching = layouts.filter { Set($0.fingerprint) == matchSet }
        let others = layouts.filter { Set($0.fingerprint) != matchSet }

        func addLayout(_ layout: Layout) {
            let menuItem = NSMenuItem(title: "\(layout.name) (\(layout.displaysLabel))", action: action, keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = layout.id
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

        let result = WindowManager.apply(layout.windows)
        Preferences.lastUsedLayoutID = layout.id

        var body = "Applied \(result.appliedWindowCount) window\(result.appliedWindowCount == 1 ? "" : "s")."
        if !result.skippedApps.isEmpty {
            body += " Not running: \(result.skippedApps.joined(separator: ", "))."
        }
        inform(title: "Applied “\(layout.name)”", body: body)
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
