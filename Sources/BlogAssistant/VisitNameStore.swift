import Foundation

/// Names are attached to photo identifiers, so adding a photo or losing the
/// first photo in the recent-300 window does not erase a visit's name.
final class VisitNameStore {
    private let defaults: UserDefaults
    private let key = "visitRestaurantNames.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func names(for identifiers: [String]) -> [String] {
        let saved = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return Set(identifiers.compactMap { saved[$0] }).sorted()
    }

    func save(_ name: String, for identifiers: [String]) {
        var saved = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for id in identifiers {
            if trimmed.isEmpty { saved.removeValue(forKey: id) }
            else { saved[id] = trimmed }
        }
        defaults.set(saved, forKey: key)
    }
}
