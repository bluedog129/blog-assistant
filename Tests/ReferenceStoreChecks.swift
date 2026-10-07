import Foundation

@main
struct ReferenceStoreChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("reference-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReferenceStore(fileURL: directory.appendingPathComponent("references.json"))
        func json(_ article: [String: Any], version: Int = 1) throws -> String {
            let envelope: [String: Any] = ["type":"blog-assistant.references", "version":version,
                "blogID":"bluedog129", "categoryNo":"65", "categoryName":"맛집탐방",
                "collectedAt":"2026-10-07T08:00:00.000Z", "articles":[article], "warnings":[]]
            return String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
        }
        let article: [String: Any] = ["postID":"123", "title":"식당 후기", "publishedDate":"2026-09-10",
            "url":"https://blog.naver.com/bluedog129/123", "body":"도입\n\n[사진]\n\n메뉴 감상", "photoCount":1]
        let packet = try ReferencePacket.parse(json(article))
        try store.save(packet)
        let restored = try store.load()
        precondition(restored?.articles.first?.body == packet.articles[0].body)
        precondition(restored?.categoryNo == "65")
        var changed = article
        changed["title"] = "새 참고 글"
        try store.save(ReferencePacket.parse(json(changed)))
        let backup = try ReferenceStore(fileURL: directory.appendingPathComponent("references.previous.json")).load()
        precondition(backup?.articles[0].title == "식당 후기")
        func reject(_ text: String) {
            do { _ = try ReferencePacket.parse(text); preconditionFailure("Invalid input accepted") }
            catch { }
        }
        reject("일반 텍스트")
        reject(try json(article, version: 2))
        changed["url"] = "https://example.com/bluedog129/123"
        reject(try json(changed))
        changed = article; changed["publishedDate"] = "2026-02-30"
        reject(try json(changed))
        changed = article; changed["body"] = " \n"
        reject(try json(changed))
        var object = try JSONSerialization.jsonObject(with: Data(json(article).utf8)) as! [String: Any]
        object["articles"] = Array(repeating: article, count: 6)
        reject(String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self))
        object["articles"] = [article, article]
        reject(String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self))
        let unaffected = try store.load()
        precondition(unaffected?.articles[0].title == "새 참고 글")
        print("Passed reference import, JSON persistence, backup, wrong-version, URL, date and count checks")
    }
}
