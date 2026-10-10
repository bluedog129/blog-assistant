import Foundation

@main struct DraftChecks {
    static func main() async throws {
        var review = VisitReview()
        review.restaurantName = "테스트 식당"
        review.visitDate = Date(timeIntervalSince1970: 1_700_000_000)
        review.photoIDs = ["private-photo-id"]
        review.menus = [ReviewMenu(name: "파스타", price: "18,000원", impression: "담백했어요")]
        let legacyMenu = Data(#"{"id":"legacy","name":"파스타","price":"","impression":"맛있음"}"#.utf8)
        let decodedLegacyMenu = try JSONDecoder().decode(ReviewMenu.self, from: legacyMenu)
        precondition(decodedLegacyMenu.photoIDs.isEmpty)
        var linkedReview = review
        linkedReview.photoIDs = ["first", "second", "shared"]
        linkedReview.menus = [
            ReviewMenu(name: "파스타", impression: "담백", photoIDs: ["first", "second", "shared", "missing"]),
            ReviewMenu(name: "피자", impression: "바삭", photoIDs: ["shared"])
        ]
        let linkedPhotos = MenuDraftPhotos.make(review: linkedReview)
        precondition(linkedPhotos.map(\.id) == ["first", "second", "shared"])
        precondition(linkedPhotos.last?.caption == "파스타 · 피자")
        let encodedMenu = try JSONEncoder().encode(linkedReview.menus[0])
        let decodedMenu = try JSONDecoder().decode(ReviewMenu.self, from: encodedMenu)
        precondition(decodedMenu == linkedReview.menus[0])
        let linkedPrompt = try DraftPrompt.make(review: linkedReview, references: nil, photos: linkedPhotos)
        precondition(linkedPrompt.contains("photoNumbers") && !linkedPrompt.contains("shared") && !linkedPrompt.contains("missing"))
        let reference = ReferencePacket(type: "blog-assistant.references", version: 1, blogID: "test", categoryNo: "65", categoryName: "맛집", collectedAt: "now", articles: [ReferenceArticle(postID: "123", title: "참고 제목", publishedDate: "2026-10-07", url: "https://blog.naver.com/test/123", body: "문체 예시 [사진]", photoCount: 1)], warnings: [])
        let prompt = try DraftPrompt.make(review: review, references: reference)
        precondition(prompt.contains("테스트 식당") && prompt.contains("담백했어요") && prompt.contains("문체 예시"))
        precondition(!prompt.contains("private-photo-id") && !prompt.contains("https://blog.naver.com"))
        precondition(!prompt.contains("\"visitBackground\""))
        var withBackground = review
        withBackground.visitBackground = "문토 모임으로 방문했어요"
        let backgroundPrompt = try DraftPrompt.make(review: withBackground, references: nil)
        precondition(backgroundPrompt.contains("문토 모임으로 방문했어요"))
        precondition(backgroundPrompt.contains("\"visitBackground\""))
        withBackground.visitBackground = "  \n "
        let blankBackgroundPrompt = try DraftPrompt.make(review: withBackground, references: nil)
        precondition(!blankBackgroundPrompt.contains("\"visitBackground\""))
        var incomplete = review; incomplete.menus = []
        do { _ = try DraftPrompt.make(review: incomplete, references: nil); fatalError("Accepted incomplete facts") } catch {}
        let generated = "제목\n\n[사진 1]\n\n본문"
        let photo = DraftPhoto(id: "private-photo-id", caption: "파스타")
        let posting = try NaverPostPacket.make(text: generated, photos: [photo], filenames: ["01_파스타.jpg"])
        precondition(posting.title == "제목" && posting.blocks.first?.photoNumber == 1 && posting.photos.first?.filename == "01_파스타.jpg")
        do { _ = try NaverPostPacket.make(text: "제목\n[사진 2]\n본문", photos: [photo], filenames: ["01_파스타.jpg"]); fatalError("Accepted invalid posting photo") } catch {}
        let photoPrompt = try DraftPrompt.make(review: review, references: nil, photos: [photo])
        precondition(photoPrompt.contains("파스타") && photoPrompt.contains("[사진 1]"))
        precondition(!photoPrompt.contains("private-photo-id"))
        let historicalPhoto = DraftPhoto(id: "past-private-id", caption: "예전에 먹었던 파스타", previousVisitDate: Date(timeIntervalSince1970: 1_600_000_000))
        let historicalPrompt = try DraftPrompt.make(review: review, references: nil, photos: [photo, historicalPhoto])
        precondition(historicalPrompt.contains("\"previousVisitDate\""))
        precondition(historicalPrompt.contains("2020-09-13") && historicalPrompt.contains("예전에 먹었던 파스타"))
        precondition(!historicalPrompt.contains("past-private-id"))
        let legacyPhoto = try JSONDecoder().decode(DraftPhoto.self, from: Data(#"{"id":"legacy-photo","caption":"전경"}"#.utf8))
        precondition(legacyPhoto.previousVisitDate == nil)
        let restoredHistoricalPhoto = try JSONDecoder().decode(DraftPhoto.self, from: JSONEncoder().encode(historicalPhoto))
        precondition(restoredHistoricalPhoto == historicalPhoto)
        let historicalPacket = try NaverPostPacket.make(text: "제목\n[사진 1]\n[사진 2]\n본문", photos: [photo, historicalPhoto], filenames: ["01.jpg", "02.jpg"])
        precondition(historicalPacket.photos.count == 2 && historicalPacket.blocks.compactMap(\.photoNumber) == [1, 2])
        let blocks = DraftLayout.blocks("제목\n\n[사진 1]\n\n한글 감상 😊\n[사진 2]\n끝")
        precondition(blocks.compactMap(\.photoNumber) == [1, 2])
        precondition(blocks.compactMap(\.text) == ["제목", "한글 감상 😊", "끝"])
        precondition(DraftLayout.warnings(text: generated, photoCount: 1).isEmpty)
        precondition(DraftLayout.warnings(text: "[사진 1]\n[사진 1]\n[사진 9]", photoCount: 2).count == 3)
        precondition(DraftLayout.blocks("문장 속 [사진 1] 표현").allSatisfy { $0.photoNumber == nil })
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DraftStore(fileURL: folder.appendingPathComponent("drafts.json"))
        let now = Date()
        var first = BlogDraft(reviewID: review.id, sourceReview: review, referencePostIDs: ["123"], model: "test-model", createdAt: now, updatedAt: now, text: generated)
        first.photos = [photo]
        try store.save(first)
        first.text = "편집한 초안"; first.updatedAt = now.addingTimeInterval(1)
        try store.save(first)
        let second = BlogDraft(reviewID: review.id, sourceReview: review, referencePostIDs: [], model: "test-model", createdAt: now.addingTimeInterval(2), updatedAt: now.addingTimeInterval(2), text: "다시 생성한 초안")
        try store.save(second)
        let latest = try store.latest(reviewID: review.id)
        precondition(latest?.text == second.text)
        let oldJSON = try JSONEncoder().encode(second)
        var oldObject = try JSONSerialization.jsonObject(with: oldJSON) as! [String: Any]
        oldObject.removeValue(forKey: "photos")
        let oldDraft = try JSONDecoder().decode(BlogDraft.self, from: JSONSerialization.data(withJSONObject: oldObject))
        precondition(oldDraft.photos == nil)
        let planStore = DraftPhotoPlanStore(fileURL: folder.appendingPathComponent("plans.json"))
        var plan = DraftPhotoPlan(selected: [photo, historicalPhoto])
        plan.requestPhotos = plan.selected
        plan.requestReview = review
        plan.selected.swapAt(0, 1)
        try planStore.save(plan, reviewID: review.id)
        let restored = try planStore.load(reviewID: review.id)
        precondition(restored.selected.first == historicalPhoto && restored.requestPhotos?.first?.id == photo.id)
        precondition(restored.requestReview == review)
        try Data("corrupt".utf8).write(to: planStore.fileURL)
        do { try planStore.save(plan, reviewID: review.id); fatalError("Overwrote corrupt photo plan") } catch {}
        let records = try JSONDecoder().decode([BlogDraft].self, from: Data(contentsOf: store.fileURL))
        precondition(records.count == 2 && records.contains { $0.text == "편집한 초안" })
        precondition(FileManager.default.fileExists(atPath: folder.appendingPathComponent("drafts.previous.json").path))
        try Data("corrupt".utf8).write(to: store.fileURL)
        do { try store.save(second); fatalError("Overwrote corrupt store") } catch {}
        let preserved = try String(contentsOf: store.fileURL, encoding: .utf8)
        precondition(preserved == "corrupt")
        print("Passed prompt facts/privacy, photo markers/warnings, frozen photo order, legacy drafts, editing/history and corrupt-store protection")
    }
}
