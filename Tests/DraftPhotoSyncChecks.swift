import Foundation

@main struct DraftPhotoSyncChecks {
    static func main() throws {
        var review = VisitReview()
        review.photoIDs = ["a", "b", "replacement", "shared", "fish"]
        review.menus = [ReviewMenu(name: "첫 메뉴", photoIDs: ["a"]), ReviewMenu(name: "둘째 메뉴", photoIDs: ["b"])]
        let original = MenuDraftPhotos.make(review: review)
        let manual = DraftPhoto(id: "manual", caption: "직접 추가한 전경")
        var plan = DraftPhotoPlan(selected: original + [manual], requestPhotos: original, requestReview: review)
        plan.syncMenuPhotos(review: review)
        review.menus[0].photoIDs = ["replacement"]
        plan.syncMenuPhotos(review: review)
        precondition(plan.selected.map(\.id) == ["replacement", "b", "manual"])
        precondition(plan.requestPhotos == original && !plan.selected.contains { $0.id == "a" })
        plan.syncMenuPhotos(review: review)
        precondition(plan.selected.map(\.id) == ["replacement", "b", "manual"])
        review.menus[1].photoIDs = []
        plan.syncMenuPhotos(review: review)
        precondition(plan.selected == [DraftPhoto(id: "replacement", caption: "첫 메뉴"), manual])
        review.menus[0].name = "새 메뉴명"
        plan.syncMenuPhotos(review: review)
        precondition(plan.selected[0].caption == "새 메뉴명")
        plan.selected[0].caption = "직접 수정한 설명"
        review.menus[0].name = "다시 바꾼 메뉴명"
        plan.syncMenuPhotos(review: review)
        precondition(plan.selected[0].caption == "직접 수정한 설명")
        review.menus = []
        plan.syncMenuPhotos(review: review)
        precondition(plan.selected == [manual])

        // Splitting a wrongly shared fish/shrimp link updates both image and caption.
        review.menus = [ReviewMenu(name: "활어초밥", photoIDs: ["shared"]), ReviewMenu(name: "간장새우초밥", photoIDs: ["shared"])]
        let sharedPhotos = MenuDraftPhotos.make(review: review)
        var sharedPlan = DraftPhotoPlan(selected: sharedPhotos, requestPhotos: sharedPhotos, requestReview: review)
        sharedPlan.syncMenuPhotos(review: review)
        review.menus[0].photoIDs = ["fish"]
        sharedPlan.syncMenuPhotos(review: review)
        precondition(sharedPlan.selected == [DraftPhoto(id: "fish", caption: "활어초밥"), DraftPhoto(id: "shared", caption: "간장새우초밥")])
        precondition(sharedPlan.requestPhotos?.first?.caption == "활어초밥 · 간장새우초밥")
        review.menus[1].photoIDs = []
        sharedPlan.syncMenuPhotos(review: review)
        precondition(sharedPlan.selected == [DraftPhoto(id: "fish", caption: "활어초밥")])

        review.menus = [ReviewMenu(name: "사진 순서", photoIDs: ["a", "b"])]
        var ordered = DraftPhotoPlan(selected: MenuDraftPhotos.make(review: review))
        ordered.syncMenuPhotos(review: review)
        review.menus[0].photoIDs = ["b", "a"]
        ordered.syncMenuPhotos(review: review)
        precondition(ordered.selected.map(\.id) == ["b", "a"])
        ordered.selected.swapAt(0, 1)
        review.menus[0].photoIDs += ["replacement"]
        ordered.syncMenuPhotos(review: review)
        precondition(ordered.selected.map(\.id) == ["a", "replacement", "b"])
        ordered.selected.removeAll { $0.id == "b" }
        ordered.syncMenuPhotos(review: review)
        precondition(!ordered.selected.contains { $0.id == "b" })
        ordered.syncMenuPhotos(review: review, includeExcluded: true)
        precondition(ordered.selected.contains { $0.id == "b" })

        review.menus = [ReviewMenu(name: "첫 메뉴", photoIDs: ["a"]), ReviewMenu(name: "둘째 메뉴", photoIDs: ["b"])]
        var excluded = DraftPhotoPlan(selected: MenuDraftPhotos.make(review: review))
        excluded.syncMenuPhotos(review: review)
        excluded.selected.removeAll { $0.id == "b" }
        excluded.syncMenuPhotos(review: review)
        precondition(excluded.selected.map(\.id) == ["a"])
        review.menus[0].photoIDs = ["b"]
        excluded.syncMenuPhotos(review: review)
        precondition(excluded.selected == [DraftPhoto(id: "b", caption: "첫 메뉴 · 둘째 메뉴")])

        // A legacy plan uses the copied review as its previous source, not the new review.
        var oldReview = review
        oldReview.menus = [ReviewMenu(name: "메뉴", photoIDs: ["a"])]
        var legacy = DraftPhotoPlan(selected: MenuDraftPhotos.make(review: oldReview), requestReview: oldReview)
        var latestReview = oldReview
        latestReview.menus[0].photoIDs = ["replacement"]
        legacy.syncMenuPhotos(review: latestReview)
        precondition(legacy.selected.map(\.id) == ["replacement"])

        // Read the latest saved menu links even when the caller still holds an older value.
        let suite = "BlogAssistant.PhotoSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReviewStore(defaults: defaults)
        try store.save(oldReview)
        var storedPlan = DraftPhotoPlan(selected: MenuDraftPhotos.make(review: oldReview))
        storedPlan.syncMenuPhotos(review: oldReview)
        try store.save(latestReview)
        let saved = try store.load(id: oldReview.id)!
        precondition(saved.menus[0].photoIDs == ["replacement"] && oldReview.menus[0].photoIDs == ["a"])
        storedPlan.syncMenuPhotos(review: saved)
        let restored = try JSONDecoder().decode(DraftPhotoPlan.self, from: JSONEncoder().encode(storedPlan))
        precondition(restored.selected.map(\.id) == ["replacement"] && restored.menuPhotosSnapshot == MenuDraftPhotos.make(review: saved))
        print("Passed menu-photo replacement/removal, shared-link correction, caption and source-order updates, manual edits/exclusions, legacy migration and latest saved-review reload")
    }
}
