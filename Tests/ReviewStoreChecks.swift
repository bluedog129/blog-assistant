import Foundation

@main
struct ReviewStoreChecks {
    static func main() throws {
        let suite = "BlogAssistant.ReviewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReviewStore(defaults: defaults)
        var first = VisitReview()
        first.photoIDs = ["a", "b"]
        first.restaurantName = "정돈 성수"
        first.visitDate = Date(timeIntervalSince1970: 1_700_000_000)
        first.businessInfo = "월–금 11:00–21:00\n브레이크타임 15:00–17:00"
        first.menus = [ReviewMenu(name: "안심 돈카츠", price: "18,000원", impression: "소금에 찍어 먹었을 때 부드러웠음")]
        precondition(first.isReady)
        var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as! [String: Any]
        legacyObject.removeValue(forKey: "visitBackground")
        let legacy = try JSONDecoder().decode(VisitReview.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        precondition(legacy == first && legacy.visitBackground.isEmpty && legacy.isReady)
        first.visitBackground = "문토 모임으로 방문했어요"
        try store.save(first)
        let reopened = ReviewStore(defaults: UserDefaults(suiteName: suite)!)
        let restored = try reopened.matches(photoIDs: ["a", "b"])
        precondition(restored == [first])
        let otherVisit = try reopened.matches(photoIDs: ["another-visit"])
        precondition(otherVisit.isEmpty)
        // Missing menu impressions prevent readiness even if other menus are complete.
        var incomplete = first
        incomplete.menus.append(ReviewMenu(name: "카레"))
        precondition(!incomplete.isReady)
        incomplete.menus[1].impression = "무난했음"
        precondition(incomplete.isReady)
        incomplete.visitDate = nil
        precondition(!incomplete.isReady)
        // Splitting preserves information for photos left in the original visit.
        var split = first
        split.id = UUID().uuidString
        split.photoIDs = ["b"]
        split.menus[0].impression = "분리한 방문의 감상"
        try reopened.save(split)
        let old = try reopened.matches(photoIDs: ["a"])
        precondition(old.count == 1 && old[0].menus == first.menus)
        let changed = try reopened.matches(photoIDs: ["b"])
        precondition(changed == [split])
        let conflicts = try reopened.matches(photoIDs: ["a", "b"])
        precondition(conflicts.count == 2)
        // An explicit merge save replaces competing memberships without duplicating them.
        var merged = first
        merged.id = UUID().uuidString
        merged.menus += split.menus
        try reopened.save(merged)
        let combined = try reopened.matches(photoIDs: ["a", "b"])
        precondition(combined == [merged])
        var unfinished = VisitReview()
        unfinished.photoIDs = ["c"]
        unfinished.waitingNote = "웨이팅 메모만 작성 중"
        try reopened.save(unfinished)
        precondition(!unfinished.isReady)
        let partial = try reopened.matches(photoIDs: ["c"])
        precondition(partial == [unfinished])
        // A corrupt store must fail rather than silently erase existing records.
        defaults.set(Data("invalid".utf8), forKey: "visitReviews.v1")
        do {
            try reopened.save(first)
            preconditionFailure("Corrupt data should block saving")
        } catch is DecodingError { }
        print("Passed review readiness, persistence, independent visits, split/merge and corrupt-data checks")
    }
}
