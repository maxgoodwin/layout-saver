import SwiftUI

struct LayoutsView: View {
    let store: LayoutStore
    @State private var layouts: [Layout] = []
    @State private var layoutPendingUpdate: Layout?

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
                                Text(layout.name).font(.headline)
                                Text("\(layout.displaysLabel) · \(layout.windows.count) window\(layout.windows.count == 1 ? "" : "s") · saved \(layout.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Update…") { layoutPendingUpdate = layout }
                                .buttonStyle(.bordered)
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
    }

    private func refresh() {
        layouts = store.all().sorted { $0.createdAt > $1.createdAt }
    }

    private func update(_ layout: Layout) {
        let updated = LayoutStore.updating(layout, withCurrentWindows: WindowManager.captureCurrentWindows())
        store.save(updated)
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
