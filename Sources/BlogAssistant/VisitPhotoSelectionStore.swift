import Foundation

// Selected additional photos are separate from visit membership and menu facts.
final class VisitPhotoSelectionStore {
    private struct Record: Codable {
        let sourcePhotoIDs: [String]
        var photos: [DraftPhoto]
    }
    let fileURL: URL
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlogAssistant", isDirectory: true).appendingPathComponent("visit-photo-selections.json")
    }
    private func records() throws -> [Record] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([Record].self, from: Data(contentsOf: fileURL))
    }
    func load(sourcePhotoIDs: [String]) throws -> [DraftPhoto] {
        let source = Set(sourcePhotoIDs)
        return try records().first { Set($0.sourcePhotoIDs) == source }?.photos ?? []
    }
    func save(_ photos: [DraftPhoto], sourcePhotoIDs: [String]) throws {
        let source = Set(sourcePhotoIDs)
        guard !source.isEmpty else { return }
        var all = try records()
        all.removeAll { Set($0.sourcePhotoIDs) == source }
        var seen = Set<String>()
        let unique = photos.filter { !source.contains($0.id) && seen.insert($0.id).inserted }
        all.append(Record(sourcePhotoIDs: source.sorted(), photos: unique))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(all).write(to: fileURL, options: .atomic)
    }
}
