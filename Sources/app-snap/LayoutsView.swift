import SwiftUI

/// One action available per saved layout, and what it does — shared source of
/// truth for both the icon buttons' tooltips and the "what do these do?"
/// legend popover, so the two can't drift out of sync.
private struct RowAction {
    var systemImage: String
    var title: String
    var explanation: String

    static let makeDefault = RowAction(
        systemImage: "star",
        title: "Make Default",
        explanation: "When several saved layouts match the same monitors, the default is the one auto-apply and the global shortcut use, instead of guessing."
    )
    static let launchMissingApps = RowAction(
        systemImage: "app.badge",
        title: "Launch Missing Apps",
        explanation: "Normally, applying a layout skips apps that aren't running. Turn this on for a layout to also launch those apps first, then position their windows."
    )
    static let rename = RowAction(
        systemImage: "pencil",
        title: "Rename",
        explanation: "Changes this layout's name only — the saved window positions are untouched."
    )
    static let update = RowAction(
        systemImage: "arrow.triangle.2.circlepath",
        title: "Update",
        explanation: "Overwrites this layout's saved windows with your current on-screen arrangement, keeping the same name. Use this after rearranging things you want to keep."
    )
    static let duplicate = RowAction(
        systemImage: "plus.square.on.square",
        title: "Duplicate",
        explanation: "Creates an independent copy of this layout, useful as a starting point for a variant (e.g. \"Office\" → \"Office copy\" for a presenting setup)."
    )
    static let delete = RowAction(
        systemImage: "trash",
        title: "Delete",
        explanation: "Permanently removes this saved layout. It won't be offered by Apply, auto-apply, or the global shortcut anymore."
    )

    static let all: [RowAction] = [.makeDefault, .launchMissingApps, .rename, .update, .duplicate, .delete]
}

struct LayoutsView: View {
    let store: LayoutStore
    @State private var layouts: [Layout] = []
    @State private var layoutPendingUpdate: Layout?
    @State private var layoutPendingRename: Layout?
    @State private var renameText: String = ""
    @State private var showActionsLegend = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !layouts.isEmpty {
                HStack(spacing: 4) {
                    Spacer()
                    Text("What do these icons do?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .onHover { hovering in showActionsLegend = hovering }
                        .popover(isPresented: $showActionsLegend, arrowEdge: .bottom) {
                            actionsLegend
                        }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
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
                                    help: (layout.isDefault ? "Unset Default" : RowAction.makeDefault.title) + " — " + RowAction.makeDefault.explanation
                                ) { toggleDefault(layout) }

                                iconButton(
                                    systemImage: layout.launchMissingApps ? "app.badge.checkmark" : "app.badge",
                                    help: RowAction.launchMissingApps.title + (layout.launchMissingApps ? ": On" : ": Off") + " — " + RowAction.launchMissingApps.explanation
                                ) { toggleLaunchMissingApps(layout) }

                                iconButton(systemImage: RowAction.rename.systemImage, help: RowAction.rename.title + " — " + RowAction.rename.explanation) {
                                    renameText = layout.name
                                    layoutPendingRename = layout
                                }

                                iconButton(systemImage: RowAction.update.systemImage, help: RowAction.update.title + " — " + RowAction.update.explanation) {
                                    layoutPendingUpdate = layout
                                }

                                iconButton(systemImage: RowAction.duplicate.systemImage, help: RowAction.duplicate.title + " — " + RowAction.duplicate.explanation) {
                                    duplicate(layout)
                                }

                                Spacer(minLength: 0)

                                iconButton(systemImage: RowAction.delete.systemImage, help: RowAction.delete.title + " — " + RowAction.delete.explanation, role: .destructive) {
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

    /// Popover content for the (i) next to "What do these icons do?" — lists
    /// every row action with its icon, name, and a plain-English explanation,
    /// so someone unsure what "Update" vs. "Duplicate" (say) does doesn't have
    /// to hover each icon one at a time to find out.
    private var actionsLegend: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(RowAction.all.enumerated()), id: \.offset) { _, action in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: action.systemImage)
                        .frame(width: 20)
                        .foregroundStyle(action.systemImage == "trash" ? .red : .primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title).font(.headline)
                        Text(action.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(width: 340)
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
