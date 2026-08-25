import SwiftUI

struct LayoutsView: View {
    let store: LayoutStore
    @State private var layouts: [Layout] = []
    @State private var layoutPendingUpdate: Layout?
    @State private var layoutPendingRename: Layout?
    @State private var renameText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if layouts.isEmpty {
                VStack(spacing: 8) {
                    Text("No saved layouts yet")
                        .font(.headline)
                    Text("Use “Save Current Layout…” from the menu bar to create one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(layouts) { layout in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(layout.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                if layout.isDefault {
                                    Text("Default")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(.tint, in: Capsule())
                                        .foregroundStyle(.white)
                                        .fixedSize()
                                }
                                Spacer(minLength: 0)
                            }
                            Text("\(layout.displaysLabel) · \(layout.windows.count) window\(layout.windows.count == 1 ? "" : "s") · saved \(layout.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                iconButton(
                                    systemImage: layout.isDefault ? "star.fill" : "star",
                                    help: layout.isDefault
                                        ? "Default for its monitor setup — click to unset"
                                        : "Make default for its monitor setup"
                                ) { toggleDefault(layout) }

                                iconButton(
                                    systemImage: layout.launchMissingApps ? "app.badge.checkmark" : "app.badge",
                                    help: layout.launchMissingApps
                                        ? "Launch Missing Apps: On — applying this layout will launch apps that aren't running"
                                        : "Launch Missing Apps: Off — applying this layout skips apps that aren't running"
                                ) { toggleLaunchMissingApps(layout) }

                                iconButton(systemImage: "pencil", help: "Rename") {
                                    renameText = layout.name
                                    layoutPendingRename = layout
                                }

                                iconButton(systemImage: "arrow.triangle.2.circlepath", help: "Update with current window arrangement") {
                                    layoutPendingUpdate = layout
                                }

                                iconButton(systemImage: "plus.square.on.square", help: "Duplicate — creates a copy to use as a starting point for a variant") {
                                    duplicate(layout)
                                }

                                Spacer(minLength: 0)

                                iconButton(systemImage: "trash", help: "Delete", role: .destructive) {
                                    delete(layout)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .frame(minWidth: 460, idealWidth: 560, minHeight: 300, idealHeight: 420)
        .onAppear(perform: refresh)
        .alert(
            "Update “\(layoutPendingUpdate?.name ?? "")”?",
            isPresented: Binding(
                get: { layoutPendingUpdate != nil },
                set: { if !$0 { layoutPendingUpdate = nil } }
            ),
            presenting: layoutPendingUpdate
        ) { layout in
            Button("Update") { update(layout) }
            Button("Cancel", role: .cancel) {}
        } message: { layout in
            Text("This overwrites the saved layout with your current window arrangement (\(DisplayFingerprint.currentLabel())).")
        }
        .alert(
            "Rename Layout",
            isPresented: Binding(
                get: { layoutPendingRename != nil },
                set: { if !$0 { layoutPendingRename = nil } }
            ),
            presenting: layoutPendingRename
        ) { layout in
            TextField("Name", text: $renameText)
            Button("Rename") { rename(layout, to: renameText) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Choose a new name for this layout.")
        }
    }

    /// Compact icon-only action button shared by every row, so the action row
    /// stays a fixed, predictable width instead of a wall of truncated text
    /// buttons that fight the window for space.
    private func iconButton(systemImage: String, help: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .help(help)
    }

    private func refresh() {
        layouts = store.all().sorted { $0.createdAt > $1.createdAt }
    }

    private func update(_ layout: Layout) {
        let updated = LayoutStore.updating(layout, withCurrentWindows: WindowManager.captureCurrentWindows())
        store.save(updated)
        refresh()
    }

    private func toggleDefault(_ layout: Layout) {
        store.setDefault(layout.id)
        refresh()
    }

    private func duplicate(_ layout: Layout) {
        store.duplicate(layout)
        refresh()
    }

    private func toggleLaunchMissingApps(_ layout: Layout) {
        var updated = layout
        updated.launchMissingApps.toggle()
        store.save(updated)
        refresh()
    }

    private func rename(_ layout: Layout, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var renamed = layout
        renamed.name = trimmed
        store.save(renamed)
        refresh()
    }

    private func delete(_ layout: Layout) {
        store.delete(layout.id)
        refresh()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            store.delete(layouts[index].id)
        }
        refresh()
    }
}
