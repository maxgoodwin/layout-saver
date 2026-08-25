import Foundation

/// Persists saved layouts as a single JSON file in Application Support, mirroring
/// how spotlight-wallpaper's ImageStore keeps its index alongside cached images.
final class LayoutStore {
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("app-snap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("layouts.json")
    }

    func all() -> [Layout] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Layout].self, from: data)) ?? []
    }

    func layouts(matching fingerprint: [String]) -> [Layout] {
        let target = Set(fingerprint)
        return all().filter { Set($0.fingerprint) == target }
    }

    @discardableResult
    func save(_ layout: Layout) -> [Layout] {
        var current = all()
        current.removeAll { $0.id == layout.id }
        current.append(layout)
        write(current)
        return current
    }

    func delete(_ id: UUID) {
        var current = all()
        current.removeAll { $0.id == id }
        write(current)
    }

    /// Saves a copy of `layout` as a new independent entry — a fresh id and
    /// createdAt, name suffixed with " copy" (deduplicated if that name is
    /// already taken), and isDefault cleared (a fingerprint should still have
    /// at most one default, and blindly copying the flag would create two).
    /// Everything else — windows, fingerprint, displaysLabel, launchMissingApps —
    /// is copied as-is, as a starting point for a variant.
    @discardableResult
    func duplicate(_ layout: Layout) -> Layout {
        let existingNames = Set(all().map(\.name))
        var candidateName = "\(layout.name) copy"
        var suffix = 2
        while existingNames.contains(candidateName) {
            candidateName = "\(layout.name) copy \(suffix)"
            suffix += 1
        }

        var copy = Layout(
            name: candidateName,
            fingerprint: layout.fingerprint,
            displaysLabel: layout.displaysLabel,
            windows: layout.windows
        )
        copy.launchMissingApps = layout.launchMissingApps
        save(copy)
        return copy
    }

    /// Marks the layout with `id` as the default for its fingerprint, clearing
    /// `isDefault` on every other saved layout that shares that same fingerprint
    /// (at most one default per monitor set). Passing the id of an already-default
    /// layout un-defaults it (toggle), leaving that fingerprint with no default.
    func setDefault(_ id: UUID) {
        var current = all()
        guard let target = current.first(where: { $0.id == id }) else { return }
        let fingerprint = Set(target.fingerprint)
        let makingDefault = !target.isDefault
        for index in current.indices where Set(current[index].fingerprint) == fingerprint {
            current[index].isDefault = current[index].id == id && makingDefault
        }
        write(current)
    }

    /// Returns a copy of `layout` with its windows (and the fingerprint/label they
    /// were captured on) replaced by `windows` — everything else (id, name,
    /// createdAt) is preserved so `save(_:)` overwrites it in place rather than
    /// creating a second entry.
    static func updating(_ layout: Layout, withCurrentWindows windows: [WindowState]) -> Layout {
        var updated = layout
        updated.windows = windows
        updated.fingerprint = DisplayFingerprint.currentFingerprint()
        updated.displaysLabel = DisplayFingerprint.currentLabel()
        return updated
    }

    private func write(_ layouts: [Layout]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(layouts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
