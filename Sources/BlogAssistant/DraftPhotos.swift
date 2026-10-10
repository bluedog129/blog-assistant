import Foundation

struct DraftPhoto: Codable, Equatable, Identifiable {
    let id: String
    var caption: String = ""
}

struct DraftPhotoPlan: Codable {
    var selected: [DraftPhoto] = []
    var requestPhotos: [DraftPhoto]?
    var requestReview: VisitReview?
    var referencePostIDs: [String]?
}

final class DraftPhotoPlanStore {
    let fileURL: URL
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlogAssistant", isDirectory: true).appendingPathComponent("photo-plans.json")
    }
    private func records() throws -> [String: DraftPhotoPlan] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        return try JSONDecoder().decode([String: DraftPhotoPlan].self, from: Data(contentsOf: fileURL))
    }
    func load(reviewID: String) throws -> DraftPhotoPlan { try records()[reviewID] ?? DraftPhotoPlan() }
    func save(_ plan: DraftPhotoPlan, reviewID: String) throws {
        var all = try records()
        all[reviewID] = plan
        let data = try JSONEncoder().encode(all)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

struct DraftBlock: Identifiable, Equatable {
    let id: Int
    let text: String?
    let photoNumber: Int?
}

enum DraftLayout {
    static func blocks(_ text: String) -> [DraftBlock] {
        // Markers occupy a whole line, so prose mentioning a photo is not replaced.
        let pattern = #"(?m)^\s*\[사진\s+([0-9]+)\]\s*$"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let source = text as NSString
        var result: [DraftBlock] = []
        var position = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            if match.range.location > position {
                let part = source.substring(with: NSRange(location: position, length: match.range.location - position)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty { result.append(DraftBlock(id: result.count, text: part, photoNumber: nil)) }
            }
            result.append(DraftBlock(id: result.count, text: nil, photoNumber: Int(source.substring(with: match.range(at: 1))) ?? 0))
            position = NSMaxRange(match.range)
        }
        let tail = source.substring(from: position).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(DraftBlock(id: result.count, text: tail, photoNumber: nil)) }
        return result
    }
    static func warnings(text: String, photoCount: Int) -> [String] {
        let numbers = blocks(text).compactMap(\.photoNumber)
        var result: [String] = []
        let invalid = Set(numbers.filter { $0 < 1 || $0 > photoCount }).sorted()
        if !invalid.isEmpty { result.append("연결할 수 없는 사진 번호: \(invalid.map(String.init).joined(separator: ", "))") }
        let missing = (photoCount > 0 ? Array(1...photoCount) : []).filter { !numbers.contains($0) }
        if !missing.isEmpty { result.append("본문에 없는 사진 번호: \(missing.map(String.init).joined(separator: ", "))") }
        let counts = numbers.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
        let duplicates = counts.filter { $0.value > 1 }.map(\.key).sorted()
        if !duplicates.isEmpty { result.append("여러 번 사용한 사진 번호: \(duplicates.map(String.init).joined(separator: ", "))") }
        return result
    }
}

// A shared photo is included once, with all linked menu names in its caption.
enum MenuDraftPhotos {
    static func make(review: VisitReview) -> [DraftPhoto] {
        let available = Set(review.photoIDs)
        var result: [DraftPhoto] = []
        for menu in review.menus {
            let name = menu.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            for id in menu.photoIDs where available.contains(id) {
                if let index = result.firstIndex(where: { $0.id == id }) {
                    if !result[index].caption.components(separatedBy: " · ").contains(name) {
                        result[index].caption += " · " + name
                    }
                } else { result.append(DraftPhoto(id: id, caption: name)) }
            }
        }
        return result
    }
}
