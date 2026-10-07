import Foundation

struct NaverPostPacket: Codable {
    let type: String
    let version: Int
    let blogID: String
    let categoryNo: String
    let title: String
    let blocks: [Block]
    let photos: [Photo]
    struct Block: Codable { let kind: String; let text: String?; let photoNumber: Int? }
    struct Photo: Codable { let number: Int; let filename: String; let caption: String }

    static func make(text: String, photos: [DraftPhoto], filenames: [String]) throws -> NaverPostPacket {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let newline = trimmed.firstIndex(of: "\n") else { throw invalid("첫 줄에 제목, 다음 줄부터 본문이 필요합니다.") }
        let title = String(trimmed[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(trimmed[trimmed.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200, !body.isEmpty, filenames.count == photos.count else { throw invalid("제목·본문·사진 구성을 확인하세요. 제목은 첫 줄에서 가져옵니다.") }
        guard DraftLayout.warnings(text: body, photoCount: photos.count).isEmpty else { throw invalid("사진 번호의 누락·중복·범위 오류를 먼저 수정하세요.") }
        let blocks = DraftLayout.blocks(body).map { block in
            Block(kind: block.photoNumber == nil ? "text" : "photo", text: block.text, photoNumber: block.photoNumber)
        }
        guard blocks.contains(where: { $0.kind == "text" }) else { throw invalid("본문 텍스트가 필요합니다.") }
        return NaverPostPacket(type: "blog-assistant.naver-post", version: 1, blogID: "bluedog129", categoryNo: "65", title: title, blocks: blocks,
                               photos: photos.enumerated().map { Photo(number: $0.offset + 1, filename: filenames[$0.offset], caption: $0.element.caption) })
    }
    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "NaverPostPacket", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
