import Foundation

struct ReviewMenu: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = ""
    var price = ""
    var impression = ""
    var photoIDs: [String] = []

    init(id: String = UUID().uuidString, name: String = "", price: String = "", impression: String = "", photoIDs: [String] = []) {
        self.id = id; self.name = name; self.price = price
        self.impression = impression; self.photoIDs = photoIDs
    }

    private enum CodingKeys: String, CodingKey { case id, name, price, impression, photoIDs }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        price = try values.decode(String.self, forKey: .price)
        impression = try values.decode(String.self, forKey: .impression)
        photoIDs = try values.decodeIfPresent([String].self, forKey: .photoIDs) ?? []
    }
}

struct VisitReview: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var photoIDs: [String] = []
    var videoIDs: [String] = []
    var restaurantName = ""
    var visitDate: Date?
    var businessInfo = ""
    var naverMapURL = ""
    var waitingNote = ""
    var visitBackground = ""
    var menus: [ReviewMenu] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case id, photoIDs, videoIDs, restaurantName, visitDate, businessInfo, naverMapURL, waitingNote, visitBackground, menus
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        photoIDs = try values.decode([String].self, forKey: .photoIDs)
        videoIDs = try values.decodeIfPresent([String].self, forKey: .videoIDs) ?? []
        restaurantName = try values.decode(String.self, forKey: .restaurantName)
        visitDate = try values.decodeIfPresent(Date.self, forKey: .visitDate)
        businessInfo = try values.decode(String.self, forKey: .businessInfo)
        naverMapURL = try values.decodeIfPresent(String.self, forKey: .naverMapURL) ?? ""
        waitingNote = try values.decode(String.self, forKey: .waitingNote)
        visitBackground = try values.decodeIfPresent(String.self, forKey: .visitBackground) ?? ""
        menus = try values.decode([ReviewMenu].self, forKey: .menus)
    }

    var isReady: Bool {
        !restaurantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && visitDate != nil &&
        !menus.isEmpty && menus.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.impression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

final class ReviewStore {
    private let defaults: UserDefaults
    private let key = "visitReviews.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func records() throws -> [VisitReview] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return try JSONDecoder().decode([VisitReview].self, from: data)
    }

    func matches(photoIDs: [String]) throws -> [VisitReview] {
        let ids = Set(photoIDs)
        return try records().filter { !ids.isDisjoint(with: $0.photoIDs) }
    }

    func load(id: String) throws -> VisitReview? { try records().first { $0.id == id } }

    func save(_ review: VisitReview) throws {
        guard !review.photoIDs.isEmpty else { return }
        var normalized = review
        normalized.videoIDs = Array(Set(review.videoIDs).intersection(review.photoIDs)).sorted()
        normalized.naverMapURL = try NaverMapLink.normalized(review.naverMapURL)
        let ids = Set(review.photoIDs)
        // Only detach this visit's photos. Other visits' saved information stays intact.
        var remaining = try records().compactMap { old -> VisitReview? in
            guard old.id != review.id else { return nil }
            var updated = old
            updated.photoIDs.removeAll { ids.contains($0) }
            return updated.photoIDs.isEmpty ? nil : updated
        }
        remaining.append(normalized)
        defaults.set(try JSONEncoder().encode(remaining), forKey: key)
    }
}


// Validate the address structure only. A shared short link is not resolved, and
// users confirm the actual branch by opening it before saving.
enum NaverMapLink {
    private static let hosts: Set<String> = ["naver.me", "map.naver.com", "m.place.naver.com", "pcmap.place.naver.com"]
    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func url(_ source: String) -> URL? {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 2_048,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              value.rangeOfCharacter(from: .controlCharacters) == nil,
              var components = URLComponents(string: value), components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), hosts.contains(host),
              components.user == nil, components.password == nil, components.port == nil,
              !components.path.isEmpty, components.path != "/" else { return nil }
        components.scheme = "https"; components.host = host
        return components.url
    }

    static func normalized(_ source: String) throws -> String {
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
        guard let url = url(source) else { throw invalid("https로 시작하는 네이버 지도·플레이스 또는 naver.me 공유 링크를 입력하세요.") }
        return url.absoluteString
    }

    static func pastedURL(_ source: String) throws -> String {
        guard source.utf8.count <= 16_384 else { throw invalid("공유 내용이 너무 깁니다. 매장 링크만 복사하세요.") }
        if let url = url(source) { return url.absoluteString }
        let matches = detector.matches(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source))
        let urls = Set(matches.compactMap { match in match.url.flatMap { url($0.absoluteString)?.absoluteString } })
        guard urls.count == 1, let url = urls.first else {
            throw invalid(urls.isEmpty ? "공유 내용에서 네이버 지도 링크를 찾지 못했습니다. 매장의 공유 링크를 복사하세요." : "여러 매장 링크가 있습니다. 사용할 매장 링크 하나만 복사하세요.")
        }
        return url
    }

    static func searchURL(for restaurantName: String) -> URL? {
        let name = restaurantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://map.naver.com/p/search/" + encoded)
    }

    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "NaverMapLink", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
