import Foundation

struct StoredVisitGroup {
    let id: String
    let photoIDs: [String]
    let isManual: Bool
}

final class VisitGroupStore {
    private let defaults: UserDefaults
    private let key = "manualVisitGroups.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var assignments: [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    func assign(_ identifiers: [String], to groupID: String) {
        var saved = assignments
        for id in identifiers { saved[id] = groupID }
        defaults.set(saved, forKey: key)
    }

    func reset(_ identifiers: [String]) {
        var saved = assignments
        for id in identifiers { saved.removeValue(forKey: id) }
        defaults.set(saved, forKey: key)
    }

    /// Apply saved memberships after automatic grouping, without adding or losing photos.
    static func apply(to automatic: [[String]], assignments: [String: String]) -> [StoredVisitGroup] {
        var result: [StoredVisitGroup] = []
        var manual: [String: [String]] = [:]
        for group in automatic {
            var remaining: [String] = []
            for id in group {
                if let manualID = assignments[id] { manual[manualID, default: []].append(id) }
                else { remaining.append(id) }
            }
            if let first = remaining.first {
                result.append(StoredVisitGroup(id: first, photoIDs: remaining, isManual: false))
            }
        }
        for id in manual.keys.sorted() {
            result.append(StoredVisitGroup(id: id, photoIDs: manual[id]!, isManual: true))
        }
        return result
    }
}
