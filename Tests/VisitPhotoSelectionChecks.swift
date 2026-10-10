import Foundation

@main struct VisitPhotoSelectionChecks {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = VisitPhotoSelectionStore(fileURL: folder.appendingPathComponent("selections.json"))
        let past = DraftPhoto(id: "past", caption: "예전 가게 전경", previousVisitDate: Date(timeIntervalSince1970: 1_600_000_000))
        let second = DraftPhoto(id: "second", caption: "예전 메뉴", previousVisitDate: Date(timeIntervalSince1970: 1_610_000_000))
        try store.save([past, past, DraftPhoto(id: "a", caption: "current")], sourcePhotoIDs: ["b", "a"])
        let reopened = VisitPhotoSelectionStore(fileURL: store.fileURL)
        let saved = try reopened.load(sourcePhotoIDs: ["a", "b"])
        precondition(saved == [past])
        let other = try reopened.load(sourcePhotoIDs: ["other"])
        precondition(other.isEmpty)
        let split = try reopened.load(sourcePhotoIDs: ["a"])
        precondition(split.isEmpty)
        try reopened.save([second], sourcePhotoIDs: ["other"])
        try reopened.save([], sourcePhotoIDs: ["b", "a"])
        let removed = try reopened.load(sourcePhotoIDs: ["a", "b"])
        let preserved = try reopened.load(sourcePhotoIDs: ["other"])
        precondition(removed.isEmpty && preserved == [second])

        let current = DraftPhoto(id: "current", caption: "이번 메뉴")
        var plan = DraftPhotoPlan(selected: [current])
        plan.syncVisitPhotos([past])
        precondition(plan.selected == [current, past])
        plan.requestPhotos = plan.selected
        plan.selected[1].caption = "직접 수정한 설명"
        plan.syncVisitPhotos([past, second])
        precondition(plan.selected.count == 3 && plan.selected[1].caption == "직접 수정한 설명")
        precondition(plan.requestPhotos == [current, past])
        plan.selected.removeAll { $0.id == "second" }
        plan.syncVisitPhotos([past, second])
        precondition(!plan.selected.contains { $0.id == "second" })
        plan.syncVisitPhotos([])
        precondition(plan.selected == [current] && plan.requestPhotos == [current, past])
        plan.syncVisitPhotos([past])
        precondition(plan.selected == [current, past])
        let planStore = DraftPhotoPlanStore(fileURL: folder.appendingPathComponent("plans.json"))
        try planStore.save(plan, reviewID: "review")
        let restoredPlan = try planStore.load(reviewID: "review")
        precondition(restoredPlan.visitPhotosSnapshot == [past] && restoredPlan.requestPhotos == [current, past])

        try Data("corrupt".utf8).write(to: store.fileURL)
        do { try reopened.save([past], sourcePhotoIDs: ["a", "b"]); fatalError("Overwrote corrupt selections") } catch {}
        let contents = try String(contentsOf: store.fileURL, encoding: .utf8)
        precondition(contents == "corrupt")
        print("Passed unnamed-visit photo selection persistence, duplicate/source exclusion, independent visits, removal, draft handoff, frozen requests and corrupt-store protection")
    }
}
