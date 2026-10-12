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
        // Reopen a saved seven-photo draft after linking an exterior and two interiors.
        var expandedReview = review
        let foodIDs = (1...7).map { "food-\($0)" }
        expandedReview.photoIDs = foodIDs + ["exterior", "interior-a", "interior-b"]
        expandedReview.menus = foodIDs.enumerated().map { ReviewMenu(name: "음식 \($0.offset + 1)", impression: "감상", photoIDs: [$0.element]) }
        let originalPhotos = MenuDraftPhotos.make(review: expandedReview)
        var changedPlan = DraftPhotoPlan(selected: originalPhotos, requestPhotos: originalPhotos, requestReview: expandedReview)
        expandedReview.menus += [ReviewMenu(name: "전경", impression: "입구", photoIDs: ["exterior"]), ReviewMenu(name: "내부", impression: "넓은 간격", photoIDs: ["interior-a", "interior-b"])]
        precondition(changedPlan.syncMenuPhotos(review: expandedReview) == 3)
        precondition(changedPlan.selected.count == 10 && changedPlan.requestPhotos == originalPhotos)
        let expandedPrompt = try DraftPrompt.make(review: expandedReview, references: nil, photos: changedPlan.selected)
        let factsJSON = expandedPrompt.components(separatedBy: "방문 정보 JSON:\n")[1].components(separatedBy: "\n\n순서대로 배치할 사진 목록 JSON:")[0]
        let facts = try JSONSerialization.jsonObject(with: Data(factsJSON.utf8)) as! [String: Any]
        let promptMenus = facts["menus"] as! [[String: Any]]
        precondition(promptMenus[7]["photoNumbers"] as! [Int] == [8])
        precondition(promptMenus[8]["photoNumbers"] as! [Int] == [9, 10])
        precondition(!expandedPrompt.contains("interior-a") && expandedPrompt.contains("같은 사진은 전체 글에서 한 번만"))
        changedPlan.selected[0].caption = "직접 쓴 설명"
        changedPlan.selected.swapAt(0, 1)
        changedPlan.selected.removeAll { $0.id == "interior-a" }
        precondition(changedPlan.syncMenuPhotos(review: expandedReview) == 0)
        precondition(changedPlan.selected[1].caption == "직접 쓴 설명" && !changedPlan.selected.contains { $0.id == "interior-a" })
        var copiedPlan = try JSONDecoder().decode(DraftPhotoPlan.self, from: JSONEncoder().encode(changedPlan))
        precondition(copiedPlan.menuPhotosSnapshot?.count == 10)
        precondition(copiedPlan.syncMenuPhotos(review: expandedReview) == 0)
        expandedReview.menus[0].name = "새 이름"
        precondition(copiedPlan.syncMenuPhotos(review: expandedReview) == 0 && copiedPlan.selected[1].caption == "직접 쓴 설명")
        let oldBody = "제목\n\n" + (1...7).map { "음식 \($0) 감상\n[사진 \($0)]" }.joined(separator: "\n\n") + "\n\n#맛집 #후기"
        let allPhotos = MenuDraftPhotos.make(review: expandedReview)
        let reconnected = try DraftLayout.reconnect(text: oldBody, from: originalPhotos, to: allPhotos)
        precondition(DraftLayout.warnings(text: reconnected, photoCount: 10).isEmpty)
        precondition(reconnected.hasSuffix("#맛집 #후기") && reconnected.contains("음식 1 감상\n[사진 1]"))
        let expandedPacket = try NaverPostPacket.make(text: reconnected, photos: allPhotos, filenames: (1...10).map { "\($0).jpg" })
        precondition(expandedPacket.photos.count == 10 && expandedPacket.blocks.compactMap(\.photoNumber) == Array(1...10))
        let oldPair = [DraftPhoto(id: "a", caption: "메뉴 A"), DraftPhoto(id: "b", caption: "메뉴 B")]
        let reordered = [DraftPhoto(id: "new", caption: "전경"), oldPair[1], oldPair[0]]
        let remapped = try DraftLayout.reconnect(text: "제목\n메뉴 A\n[사진 1]\n메뉴 B\n[사진 2]\n끝", from: oldPair, to: reordered)
        precondition(remapped.contains("메뉴 A\n[사진 3]") && remapped.contains("메뉴 B\n[사진 2]"))
        precondition(DraftLayout.warnings(text: remapped, photoCount: 3).isEmpty)
        let removed = try DraftLayout.reconnect(text: "제목\n메뉴 A\n[사진 1]\n메뉴 B\n[사진 2]", from: oldPair, to: [oldPair[1]])
        precondition(removed.contains("메뉴 B\n[사진 1]") && !removed.contains("[사진 2]"))
        let cleared = try DraftLayout.reconnect(text: removed, from: [oldPair[1]], to: [])
        precondition(DraftLayout.blocks(cleared).compactMap(\.photoNumber).isEmpty && cleared.contains("메뉴 A"))
        let unicode = try DraftLayout.reconnect(text: "제목 😊\r\n감상 🍣\r\n[사진 1]\r\n끝", from: [oldPair[0]], to: [oldPair[1], oldPair[0]])
        precondition(unicode.replacingOccurrences(of: "\r\n", with: "\n").contains("감상 🍣\n[사진 2]\n끝"))
        do { _ = try DraftLayout.reconnect(text: "제목\n[사진 9]", from: oldPair, to: reordered); fatalError("Rebound an invalid old photo") } catch {}
        do { _ = try DraftLayout.reconnect(text: "제목\n[사진 1]\n[사진 2]", from: oldPair, to: [oldPair[0], oldPair[0]]); fatalError("Accepted duplicate photo identities") } catch {}
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
        var styledReview = review
        styledReview.businessInfo = "휴무: 월요일\n영업시간\n화~일 11:00–21:00\n브레이크타임: 15:00–17:00\n\n주차는 매장에 문의"
        let summary = BusinessSummary.rows(styledReview.businessInfo)
        precondition(summary.map(\.label) == ["영업시간", "휴무", "브레이크타임", "추가 정보"])
        precondition(summary.first?.value == "화~일 11:00–21:00")
        precondition(BusinessSummary.rows(" \n").isEmpty)
        precondition(BusinessSummary.rows("라스트오더:\n").isEmpty)
        precondition(BusinessSummary.rows("휴무: 없음").first?.value == "없음")
        precondition(BusinessSummary.rows("영업시간: 11:00–21:00\n주차: 무료").map(\.label) == ["영업시간", "추가 정보"])
        precondition(DraftFormatting.plainText("# 제목\n## 메뉴\n**맛있음**", review: nil) == "제목\n메뉴\n맛있음")
        let styledText = "**제목**\n\n[영업정보]\n\n## 파스타\n가격: 18,000원\n[사진 1]\n**담백한 점**이 좋았어요.\n\n## 먹고 나서\n재방문하고 싶어요."
        let styledPacket = try NaverPostPacket.make(text: styledText, photos: [DraftPhoto(id: "p", caption: "파스타")], filenames: ["01_파스타.jpg"], template: .record, review: styledReview)
        precondition(styledPacket.version == 2 && styledPacket.template == "record" && styledPacket.title == "제목")
        let styledParagraphs = styledPacket.blocks.flatMap { $0.paragraphs ?? [] }
        precondition(styledParagraphs.contains { $0.role == "menu" && $0.text == "파스타" && $0.runs.first?.bold == true })
        precondition(styledParagraphs.contains { $0.role == "price" && $0.size == 15 })
        precondition(styledParagraphs.contains { $0.role == "body" && $0.runs == [DraftTextRun(text: "담백한 점", bold: true), DraftTextRun(text: "이 좋았어요.", bold: false)] })
        precondition(styledPacket.blocks.compactMap(\.text).allSatisfy { !$0.contains("**") && !$0.contains("## ") && !$0.contains("[영업정보]") && !$0.contains("라스트오더") })
        let plainPacket = try NaverPostPacket.make(text: styledText, photos: [DraftPhoto(id: "p")], filenames: ["01_파스타.jpg"], template: .plain, review: styledReview)
        precondition(plainPacket.version == 1 && plainPacket.blocks.allSatisfy { $0.paragraphs == nil })
        precondition(plainPacket.blocks.compactMap(\.text) == styledPacket.blocks.compactMap(\.text))
        precondition(DraftFormatting.inline("별표 **미완성").map(\.text).joined() == "별표 **미완성")
        let emptyInfo = DraftFormatting.expandBusinessInfo("도입\n[영업정보]\n감상", review: review)
        precondition(!emptyInfo.contains("방문 전 확인") && !emptyInfo.contains("[영업정보]"))
        do { _ = try NaverPostPacket.make(text: "제목\n[영업정보]\n[영업정보]\n본문", photos: [], filenames: [], template: .record, review: styledReview); fatalError("Accepted duplicate business summary") } catch {}
        let decodedPacket = try JSONDecoder().decode(NaverPostPacket.self, from: JSONEncoder().encode(styledPacket))
        precondition(decodedPacket.blocks.first?.paragraphs == styledPacket.blocks.first?.paragraphs)
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
        // A direct editor paste/save left a twelve-photo text attached to seven photos.
        let twelvePhotos = (1...12).map { DraftPhoto(id: "requested-\($0)", caption: "사진 \($0)") }
        let twelveText = "새 제목\n\n" + (1...12).map { "설명 \($0)\n[사진 \($0)]" }.joined(separator: "\n\n")
        var requestedReview = review
        requestedReview.visitBackground = "갱신한 방문 정보"
        let twelvePlan = DraftPhotoPlan(selected: twelvePhotos, requestPhotos: twelvePhotos, requestReview: requestedReview, referencePostIDs: ["new-reference"])
        var staleDraft = BlogDraft(reviewID: review.id, sourceReview: review, referencePostIDs: ["old-reference"], model: "direct-paste", createdAt: Date(), updatedAt: Date(), text: twelveText, photos: Array(twelvePhotos.prefix(7)), template: .record)
        let repairStore = DraftStore(fileURL: folder.appendingPathComponent("repair-drafts.json"))
        try repairStore.save(staleDraft)
        let reopenedStale = try repairStore.latest(reviewID: review.id)!
        let repaired = reopenedStale.repairingPhotoConnection(text: twelveText, plan: twelvePlan)!
        precondition(repaired.text == twelveText && repaired.photos == twelvePhotos && repaired.id != staleDraft.id)
        precondition(repaired.sourceReview == requestedReview && repaired.referencePostIDs == ["new-reference"] && repaired.template == .record)
        precondition(repaired.repairingPhotoConnection(text: twelveText, plan: twelvePlan) == nil)
        let repairedPacket = try NaverPostPacket.make(text: repaired.text, photos: repaired.photos!, filenames: (1...12).map { "\($0).jpg" })
        precondition(repairedPacket.photos.count == 12 && repairedPacket.blocks.compactMap(\.photoNumber) == Array(1...12))
        try repairStore.save(repaired)
        let repairHistory = try JSONDecoder().decode([BlogDraft].self, from: Data(contentsOf: repairStore.fileURL))
        precondition(repairHistory.count == 2 && repairHistory.first { $0.id == staleDraft.id }?.photos?.count == 7)
        let repairedLatest = try repairStore.latest(reviewID: review.id)
        precondition(repairedLatest?.photos?.count == 12)
        staleDraft.text = "제목\n" + (1...7).map { "[사진 \($0)]" }.joined(separator: "\n")
        precondition(staleDraft.repairingPhotoConnection(text: staleDraft.text, plan: twelvePlan) == nil)
        var sameCountPlan = twelvePlan
        sameCountPlan.requestPhotos = Array(twelvePhotos.prefix(7).reversed())
        precondition(staleDraft.repairingPhotoConnection(text: staleDraft.text, plan: sameCountPlan) == nil)
        var unrecordedPlan = twelvePlan; unrecordedPlan.requestPhotos = nil
        precondition(staleDraft.repairingPhotoConnection(text: twelveText, plan: unrecordedPlan) == nil)
        var wrongReviewPlan = twelvePlan; wrongReviewPlan.requestReview?.id = "other-review"
        precondition(staleDraft.repairingPhotoConnection(text: twelveText, plan: wrongReviewPlan) == nil)
        var duplicatePlan = twelvePlan; duplicatePlan.requestPhotos?[11] = twelvePhotos[0]
        precondition(staleDraft.repairingPhotoConnection(text: twelveText, plan: duplicatePlan) == nil)
        precondition(staleDraft.repairingPhotoConnection(text: twelveText + "\n[사진 1]", plan: twelvePlan) == nil)
        let store = DraftStore(fileURL: folder.appendingPathComponent("drafts.json"))
        let now = Date()
        var first = BlogDraft(reviewID: review.id, sourceReview: review, referencePostIDs: ["123"], model: "test-model", createdAt: now, updatedAt: now, text: generated)
        first.photos = [photo]
        first.template = .record
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
        precondition(oldDraft.photos == nil && oldDraft.template == nil)
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
        precondition(records.first { $0.id == first.id }?.template == .record)
        precondition(FileManager.default.fileExists(atPath: folder.appendingPathComponent("drafts.previous.json").path))
        try Data("corrupt".utf8).write(to: store.fileURL)
        do { try store.save(second); fatalError("Overwrote corrupt store") } catch {}
        let preserved = try String(contentsOf: store.fileURL, encoding: .utf8)
        precondition(preserved == "corrupt")
        print("Passed prompt facts/privacy, photo markers/warnings, frozen photo order, legacy drafts, editing/history and corrupt-store protection")
    }
}
