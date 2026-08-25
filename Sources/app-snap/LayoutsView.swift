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
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(layout.name).font(.headline)
                                    if layout.isDefault {
                                        Text("Default")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(.tint, in: Capsule())
                                            .foregroundStyle(.white)
                                    }
                                }
                                Text("\(layout.displaysLabel) · \(layout.windows.count) window\(layout.windows.count == 1 ? "" : "s") · saved \(layout.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                toggleLaunchMissingApps(layout)
                            } label: {
                                Image(systemName: layout.launchMissingApps ? "app.badge.checkmark" : "app.badge")
                            }
                            .buttonStyle(.bordered)
                            .help(layout.launchMissingApps
                                ? "Launch Missing Apps: On — applying this layout will launch apps that aren't running"
                                : "Launch Missing Apps: Off — applying this layout skips apps that aren't running")
                            Button(layout.isDefault ? "Unset Default" : "Make Default") { toggleDefault(layout) }
                                .buttonStyle(.bordered)
                            Button("Rename…") {
                                renameText = layout.name
                                layoutPendingRename = layout
                            }
                            .buttonStyle(.bordered)
                            Button("Update…") { layoutPendingUpdate = layout }
                                .buttonStyle(.bordered)
                            Button {
                                duplicate(layout)
                            } label: {
                                Image(systemName: "plus.square.on.square")
                            }
                            .buttonStyle(.bordered)
                            .help("Duplicate — creates a copy to use as a starting point for a variant")
                            Button(role: .destructive) { delete(layout) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
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
