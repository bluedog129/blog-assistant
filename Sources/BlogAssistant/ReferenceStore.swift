import Foundation

struct ReferenceArticle: Codable, Identifiable {
    let postID: String
    let title: String
    let publishedDate: String
    let url: String
    let body: String
    let photoCount: Int
    var id: String { postID }
}

struct ReferencePacket: Codable {
    let type: String
    let version: Int
    let blogID: String
    let categoryNo: String
    let categoryName: String
    let collectedAt: String
    var articles: [ReferenceArticle]
    let warnings: [String]

    static func parse(_ text: String) throws -> ReferencePacket {
        guard let data = text.data(using: .utf8), data.count <= 1_000_000 else { throw invalid("복사된 내용이 너무 큽니다.") }
        var packet = try JSONDecoder().decode(Self.self, from: data)
        guard packet.type == "blog-assistant.references", packet.version == 1 else { throw invalid("지원되는 참고 글 형식이 아닙니다. 확장 프로그램에서 결과를 복사하세요.") }
        guard packet.blogID.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
              packet.categoryNo.range(of: "^[0-9]+$", options: .regularExpression) != nil,
              !packet.categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...5).contains(packet.articles.count),
              Set(packet.articles.map(\.postID)).count == packet.articles.count else { throw invalid("블로그·카테고리·글 개수를 확인하세요. 최대 5개 글을 가져올 수 있습니다.") }
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.calendar = Calendar(identifier: .gregorian)
        date.dateFormat = "yyyy-MM-dd"
        date.isLenient = false
        for article in packet.articles {
            guard article.postID.range(of: "^[0-9]+$", options: .regularExpression) != nil,
                  let url = URLComponents(string: article.url), url.scheme == "https", url.host == "blog.naver.com",
                  url.user == nil, url.password == nil, url.port == nil,
                  url.path == "/\(packet.blogID)/\(article.postID)", url.query == nil, url.fragment == nil,
                  !article.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !article.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  article.body.count <= 100_000, article.title.count <= 1000,
                  article.photoCount >= 0, article.photoCount <= 10000,
                  let parsed = date.date(from: article.publishedDate), date.string(from: parsed) == article.publishedDate else {
                throw invalid("글의 제목·본문·게시일 또는 원문 주소가 올바르지 않습니다.")
            }
        }
        packet.articles.sort {
            if $0.publishedDate == $1.publishedDate {
                if $0.postID.count == $1.postID.count { return $0.postID > $1.postID }
                return $0.postID.count > $1.postID.count
            }
            return $0.publishedDate > $1.publishedDate
        }
        return packet
    }

    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "ReferenceImport", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

final class ReferenceStore {
    let fileURL: URL
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlogAssistant", isDirectory: true).appendingPathComponent("references.json")
    }

    func load() throws -> ReferencePacket? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return try ReferencePacket.parse(text)
    }

    func save(_ packet: ReferencePacket) throws {
        let data = try JSONEncoder().encode(packet)
        _ = try ReferencePacket.parse(String(decoding: data, as: UTF8.self))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Preserve the previous confirmed packet for recovery before replacement.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let previous = try Data(contentsOf: fileURL)
            try previous.write(to: fileURL.deletingLastPathComponent().appendingPathComponent("references.previous.json"), options: .atomic)
        }
        try data.write(to: fileURL, options: .atomic)
    }
}
