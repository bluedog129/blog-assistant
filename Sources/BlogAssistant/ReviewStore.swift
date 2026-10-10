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
    var restaurantName = ""
    var visitDate: Date?
    var businessInfo = ""
    var waitingNote = ""
    var menus: [ReviewMenu] = []

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

    func save(_ review: VisitReview) throws {
        guard !review.photoIDs.isEmpty else { return }
        let ids = Set(review.photoIDs)
        // Only detach this visit's photos. Other visits' saved information stays intact.
        var remaining = try records().compactMap { old -> VisitReview? in
            guard old.id != review.id else { return nil }
            var updated = old
            updated.photoIDs.removeAll { ids.contains($0) }
            return updated.photoIDs.isEmpty ? nil : updated
        }
        remaining.append(review)
        defaults.set(try JSONEncoder().encode(remaining), forKey: key)
    }
}
