import Foundation

struct NaverPostPacket: Codable {
    let type: String
    let version: Int
    let blogID: String
    let categoryNo: String
    let title: String
    let blocks: [Block]
    var photos: [Photo]
    var template: String? = nil
    struct Block: Codable {
        let kind: String; let text: String?; let photoNumber: Int?
        var paragraphs: [DraftParagraph]? = nil
        var place: Place? = nil
    }
    struct Place: Codable, Equatable {
        let name: String
        let address: String
        let url: String

        static func target(_ review: VisitReview?) -> Place? {
            guard let review, let url = NaverMapLink.url(review.naverMapURL) else { return nil }
            return Place(name: review.restaurantName.trimmingCharacters(in: .whitespacesAndNewlines),
                         address: BusinessSummary.rows(review.businessInfo).first { $0.label == "주소" }?.value ?? "",
                         url: url.absoluteString)
        }
    }
    struct Photo: Codable {
        let number: Int; let filename: String; let caption: String
        var mediaType: String? = nil
        var byteCount: Int? = nil
        var isVideo: Bool { mediaType == "video" }
    }

    static func make(text: String, photos: [DraftPhoto], filenames: [String], template: DraftTemplate = .plain, review: VisitReview? = nil) throws -> NaverPostPacket {
        let trimmed = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.components(separatedBy: "\n").filter({ $0.trimmingCharacters(in: .whitespaces) == "[영업정보]" }).count <= 1 else { throw invalid("[영업정보] 표시는 본문에 한 번만 넣으세요.") }
        guard trimmed.components(separatedBy: "\n").filter({ $0.trimmingCharacters(in: .whitespacesAndNewlines) == DraftMapLink.marker }).count <= 1 else { throw invalid("[네이버지도] 표시는 본문에 한 번만 넣으세요.") }
        if let review { _ = try NaverMapLink.normalized(review.naverMapURL) }
        guard let newline = trimmed.firstIndex(of: "\n") else { throw invalid("첫 줄에 제목, 다음 줄부터 본문이 필요합니다.") }
        let title = DraftFormatting.title(String(trimmed[..<newline]))
        let body = String(trimmed[trimmed.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200, !body.isEmpty, filenames.count == photos.count else { throw invalid("제목·본문·사진 구성을 확인하세요. 제목은 첫 줄에서 가져옵니다.") }
        guard DraftLayout.warnings(text: body, photos: photos).isEmpty else { throw invalid("사진 번호의 누락·중복·범위 오류를 먼저 수정하세요.") }
        guard photos.filter(\.isVideo).count <= 10 else { throw invalid("영상은 한 글에 최대 10개까지 선택하세요.") }
        let blocks = try DraftLayout.blocks(body, visitMarkers: true).compactMap { block -> Block? in
            if block.visitMarker == "네이버지도" {
                guard let place = Place.target(review) else { return nil }
                guard !place.name.isEmpty, place.name.count <= 200, place.address.count <= 500,
                      place.name.rangeOfCharacter(from: .newlines) == nil, place.address.rangeOfCharacter(from: .newlines) == nil else {
                    throw invalid("지도에 표시할 매장 이름과 한 줄의 주소를 확인하세요.")
                }
                return Block(kind: "map", text: nil, photoNumber: nil, place: place)
            }
            if block.visitMarker == "영업정보" {
                let paragraphs = BusinessSummary.paragraphs(review?.businessInfo ?? "")
                guard !paragraphs.isEmpty else { return nil }
                return Block(kind: template == .record ? "info" : "text", text: paragraphs.map(\.text).joined(separator: "\n"), photoNumber: nil,
                             paragraphs: template == .record ? paragraphs : nil)
            }
            guard let content = block.text else { return Block(kind: block.isVideo ? "video" : "photo", text: nil, photoNumber: block.photoNumber) }
            let paragraphs = DraftFormatting.paragraphs(content, menus: review?.menus ?? [])
            let plain = paragraphs.map(\.text).joined(separator: "\n")
            guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Block(kind: "text", text: plain, photoNumber: nil, paragraphs: template == .record ? paragraphs : nil)
        }
        guard blocks.contains(where: { $0.kind == "text" || $0.kind == "info" }) else { throw invalid("본문 텍스트가 필요합니다.") }
        let hasVisitBlocks = blocks.contains { $0.kind == "map" || $0.kind == "info" }
        return NaverPostPacket(type: "blog-assistant.naver-post", version: hasVisitBlocks ? 4 : photos.contains(where: \.isVideo) ? 3 : (template == .record ? 2 : 1), blogID: "bluedog129", categoryNo: "65", title: title, blocks: blocks,
                               photos: photos.enumerated().map { Photo(number: $0.offset + 1, filename: filenames[$0.offset], caption: $0.element.caption, mediaType: $0.element.isVideo ? "video" : nil) }, template: template == .record ? "record" : nil)
    }
    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "NaverPostPacket", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
