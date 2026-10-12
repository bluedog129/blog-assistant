import Foundation

struct BlogDraft: Codable, Identifiable {
    var id = UUID().uuidString
    let reviewID: String
    let sourceReview: VisitReview
    let referencePostIDs: [String]
    let model: String
    let createdAt: Date
    var updatedAt: Date
    var text: String
    var photos: [DraftPhoto]? = nil
    var template: DraftTemplate? = nil

    // A direct paste into the editor can replace the text without passing through
    // the import button. Adopt a recorded request only when the old photo list
    // cannot describe the text and the requested list describes every marker.
    func repairingPhotoConnection(text: String, plan: DraftPhotoPlan, now: Date = Date()) -> BlogDraft? {
        guard let requested = plan.requestPhotos,
              Set(requested.map(\.id)).count == requested.count,
              plan.requestReview == nil || plan.requestReview?.id == reviewID,
              !DraftLayout.warnings(text: text, photoCount: (photos ?? requested).count).isEmpty,
              DraftLayout.warnings(text: text, photoCount: requested.count).isEmpty else { return nil }
        return BlogDraft(reviewID: reviewID, sourceReview: plan.requestReview ?? sourceReview,
                         referencePostIDs: plan.referencePostIDs ?? referencePostIDs, model: model,
                         createdAt: now, updatedAt: now, text: text, photos: requested, template: template)
    }
}

final class DraftStore {
    let fileURL: URL
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlogAssistant", isDirectory: true).appendingPathComponent("drafts.json")
    }
    private func records() throws -> [BlogDraft] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([BlogDraft].self, from: Data(contentsOf: fileURL))
    }
    func latest(reviewID: String) throws -> BlogDraft? {
        try records().filter { $0.reviewID == reviewID }.max { $0.updatedAt < $1.updatedAt }
    }
    func save(_ draft: BlogDraft) throws {
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "DraftStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "초안이 비어 있습니다."])
        }
        var values = try records()
        values.removeAll { $0.id == draft.id }
        values.append(draft)
        let data = try JSONEncoder().encode(values)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try Data(contentsOf: fileURL).write(to: fileURL.deletingLastPathComponent().appendingPathComponent("drafts.previous.json"), options: .atomic)
        }
        try data.write(to: fileURL, options: .atomic)
    }
}
