import Foundation

@main struct VisitPhotoSelectionChecks {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = VisitPhotoSelectionStore(fileURL: folder.appendingPathComponent("selections.json"))
        precondition(LibraryPhotoPaging.range(offset: 0, total: 0).isEmpty)
        precondition(LibraryPhotoPaging.range(offset: 0, total: 201) == 0..<200)
        precondition(LibraryPhotoPaging.range(offset: 200, total: 201) == 200..<201)
        precondition(LibraryPhotoPaging.range(offset: 500, total: 201).isEmpty)
        let allPages = stride(from: 0, to: 1_001, by: LibraryPhotoPaging.size).flatMap { Array(LibraryPhotoPaging.range(offset: $0, total: 1_001)) }
        precondition(allPages == Array(0..<1_001))
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
        let video = DraftPhoto(id: "shared-video", caption: "직접 입력한 영상 설명", previousVisitDate: second.previousVisitDate, mediaType: "video")
        try reopened.save([past, video, video], sourcePhotoIDs: ["a", "b"])
        try reopened.save([past, video], sourcePhotoIDs: ["other"])
        let reused = try reopened.load(sourcePhotoIDs: ["a", "b"])
        precondition(reused == [past, video])
        try reopened.save([], sourcePhotoIDs: ["other"])
        let stillLinked = try reopened.load(sourcePhotoIDs: ["a", "b"])
        precondition(stillLinked == reused && stillLinked[1].isVideo)
        let withoutDescription = DraftPhoto(id: "selected-first", previousVisitDate: past.previousVisitDate)
        try reopened.save([withoutDescription], sourcePhotoIDs: ["before-organized"])
        let picked = try reopened.load(sourcePhotoIDs: ["before-organized"])
        precondition(picked.count == 1 && picked[0].caption.isEmpty)
        var laterPlan = DraftPhotoPlan()
        laterPlan.syncVisitPhotos(picked)
        laterPlan.selected[0].caption = "정리 완료 후 작성한 설명"
        laterPlan.syncVisitPhotos(picked)
        precondition(laterPlan.selected[0].caption == "정리 완료 후 작성한 설명")

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
