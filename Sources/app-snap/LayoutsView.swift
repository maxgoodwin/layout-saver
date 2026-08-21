import SwiftUI

struct LayoutsView: View {
    let store: LayoutStore
    @State private var layouts: [Layout] = []

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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(layout.name).font(.headline)
                            Text("\(layout.displaysLabel) · \(layout.windows.count) window\(layout.windows.count == 1 ? "" : "s") · saved \(layout.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        layouts = store.all().sorted { $0.createdAt > $1.createdAt }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            store.delete(layouts[index].id)
        }
        refresh()
    }
}
