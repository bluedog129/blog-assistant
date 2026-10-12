import Foundation

struct DraftPhoto: Codable, Equatable, Identifiable {
    let id: String
    var caption: String = ""
    var previousVisitDate: Date?
}

struct DraftPhotoPlan: Codable {
    var selected: [DraftPhoto] = []
    var requestPhotos: [DraftPhoto]?
    var requestReview: VisitReview?
    var referencePostIDs: [String]?
    var visitPhotosSnapshot: [DraftPhoto]?
    var menuPhotosSnapshot: [DraftPhoto]?
    var menuPhotoLinksSnapshot: [String: [String]]?

    // Update the working selection; a generated draft and request stay frozen.
    @discardableResult mutating func syncMenuPhotos(review: VisitReview, includeExcluded: Bool = false) -> Int {
        let photos = MenuDraftPhotos.make(review: review)
        let previous = menuPhotosSnapshot ?? requestReview.map { MenuDraftPhotos.make(review: $0) } ?? []
        let previousIDs = Set(previous.map(\.id))
        let currentIDs = Set(photos.map(\.id))
        let links = Dictionary(review.menus.map { ($0.id, $0.photoIDs) }, uniquingKeysWith: { first, second in first + second })
        let previousLinks = menuPhotoLinksSnapshot ?? requestReview.map {
            Dictionary($0.menus.map { ($0.id, $0.photoIDs) }, uniquingKeysWith: { first, second in first + second })
        }
        let newlyLinkedIDs = Set(links.flatMap { menuID, ids in
            ids.filter { !(previousLinks?[menuID] ?? []).contains($0) }
        })
        let selectedIDs = Set(selected.map(\.id))
        let manuallyOrdered = selected.filter { previousIDs.contains($0.id) }.map(\.id) != previous.filter { selectedIDs.contains($0.id) }.map(\.id)
        selected.removeAll { previousIDs.contains($0.id) && !currentIDs.contains($0.id) }
        var added = 0
        for (position, photo) in photos.enumerated() {
            if let index = selected.firstIndex(where: { $0.id == photo.id }) {
                if let old = previous.first(where: { $0.id == photo.id }), selected[index] == old {
                    selected[index] = photo
                }
            } else if menuPhotosSnapshot == nil || !previousIDs.contains(photo.id) || (previousLinks != nil && newlyLinkedIDs.contains(photo.id)) || includeExcluded {
                // Put a replacement near its menu instead of appending it after all meals.
                let before = photos[..<position].reversed().compactMap { previous in selected.firstIndex { $0.id == previous.id } }.first
                let after = photos[(position + 1)...].compactMap { next in selected.firstIndex { $0.id == next.id } }.first
                selected.insert(photo, at: before.map { $0 + 1 } ?? after ?? selected.count)
                added += 1
            }
        }
        if !manuallyOrdered {
            let positions = selected.indices.filter { currentIDs.contains(selected[$0].id) }
            let byID = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
            let ordered = photos.compactMap { byID[$0.id] }
            for (index, photo) in zip(positions, ordered) { selected[index] = photo }
        }
        menuPhotosSnapshot = photos
        menuPhotoLinksSnapshot = links
        return added
    }

    // Keep requestPhotos frozen; manual caption edits and exclusions survive a reopen.
    mutating func syncVisitPhotos(_ photos: [DraftPhoto]) {
        let previous = visitPhotosSnapshot ?? []
        let currentIDs = Set(photos.map(\.id))
        let removedIDs = Set(previous.map(\.id)).subtracting(currentIDs)
        selected.removeAll { removedIDs.contains($0.id) }
        for photo in photos {
            if let index = selected.firstIndex(where: { $0.id == photo.id }) {
                if let old = previous.first(where: { $0.id == photo.id }), selected[index] == old {
                    selected[index] = photo
                }
            } else if !previous.contains(where: { $0.id == photo.id }) {
                selected.append(photo)
            }
        }
        visitPhotosSnapshot = photos
    }
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
    private static let markerPattern = #"(?m)^[ \t]*\[사진[ \t]+([0-9]+)\][ \t]*\r?$"#
    static func blocks(_ text: String) -> [DraftBlock] {
        // Markers occupy a whole line, so prose mentioning a photo is not replaced.
        let regex = try! NSRegularExpression(pattern: markerPattern)
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

    // A marker keeps its photo identity when selection order changes.
    static func reconnect(text: String, from old: [DraftPhoto], to selected: [DraftPhoto]) throws -> String {
        guard Set(old.map(\.id)).count == old.count, Set(selected.map(\.id)).count == selected.count,
              warnings(text: text, photoCount: old.count).isEmpty else {
            throw NSError(domain: "DraftLayout", code: 1, userInfo: [NSLocalizedDescriptionKey: "기존 초안의 사진 번호 누락·중복·범위 오류를 먼저 수정하세요. 사진 연결은 변경하지 않았습니다."])
        }
        let numbers = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ($0.element.id, $0.offset + 1) })
        let source = text as NSString
        let updated = NSMutableString(string: text)
        let regex = try! NSRegularExpression(pattern: markerPattern)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let index = Int(source.substring(with: match.range(at: 1)))! - 1
            let replacement = numbers[old[index].id].map { "[사진 \($0)]" } ?? ""
            updated.replaceCharacters(in: match.range, with: replacement)
        }
        let existing = Set(old.map(\.id))
        let newMarkers = selected.enumerated().filter { !existing.contains($0.element.id) }
            .map { "[사진 \($0.offset + 1)]" }.joined(separator: "\n\n")
        guard !newMarkers.isEmpty else { return updated as String }
        var lines = (updated as String).components(separatedBy: "\n")
        // Keep trailing hashtags at the end of the post.
        if let last = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[last].trimmingCharacters(in: .whitespaces).range(of: #"^#[^\s#]+"#, options: .regularExpression) != nil {
            lines.insert("\n" + newMarkers + "\n", at: last)
            return lines.joined(separator: "\n")
        }
        return (updated as String).trimmingCharacters(in: .newlines) + "\n\n" + newMarkers
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
