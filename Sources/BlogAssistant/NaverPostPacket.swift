import Foundation

struct NaverPostPacket: Codable {
    let type: String
    let version: Int
    let blogID: String
    let categoryNo: String
    let title: String
    let blocks: [Block]
    let photos: [Photo]
    var template: String? = nil
    struct Block: Codable {
        let kind: String; let text: String?; let photoNumber: Int?
        var paragraphs: [DraftParagraph]? = nil
    }
    struct Photo: Codable { let number: Int; let filename: String; let caption: String }

    static func make(text: String, photos: [DraftPhoto], filenames: [String], template: DraftTemplate = .plain, review: VisitReview? = nil) throws -> NaverPostPacket {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.components(separatedBy: "\n").filter({ $0.trimmingCharacters(in: .whitespaces) == "[영업정보]" }).count <= 1 else { throw invalid("[영업정보] 표시는 본문에 한 번만 넣으세요.") }
        guard let newline = trimmed.firstIndex(of: "\n") else { throw invalid("첫 줄에 제목, 다음 줄부터 본문이 필요합니다.") }
        let title = DraftFormatting.title(String(trimmed[..<newline]))
        let body = DraftFormatting.expandBusinessInfo(String(trimmed[trimmed.index(after: newline)...]), review: review).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200, !body.isEmpty, filenames.count == photos.count else { throw invalid("제목·본문·사진 구성을 확인하세요. 제목은 첫 줄에서 가져옵니다.") }
        guard DraftLayout.warnings(text: body, photoCount: photos.count).isEmpty else { throw invalid("사진 번호의 누락·중복·범위 오류를 먼저 수정하세요.") }
        let blocks = DraftLayout.blocks(body).compactMap { block -> Block? in
            guard let content = block.text else { return Block(kind: "photo", text: nil, photoNumber: block.photoNumber) }
            let paragraphs = DraftFormatting.paragraphs(content, menus: review?.menus ?? [])
            let plain = paragraphs.map(\.text).joined(separator: "\n")
            guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Block(kind: "text", text: plain, photoNumber: nil, paragraphs: template == .record ? paragraphs : nil)
        }
        guard blocks.contains(where: { $0.kind == "text" }) else { throw invalid("본문 텍스트가 필요합니다.") }
        return NaverPostPacket(type: "blog-assistant.naver-post", version: template == .record ? 2 : 1, blogID: "bluedog129", categoryNo: "65", title: title, blocks: blocks,
                               photos: photos.enumerated().map { Photo(number: $0.offset + 1, filename: filenames[$0.offset], caption: $0.element.caption) }, template: template == .record ? "record" : nil)
    }
    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "NaverPostPacket", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
