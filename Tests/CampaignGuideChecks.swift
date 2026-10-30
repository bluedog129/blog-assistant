import Foundation

@main struct CampaignGuideChecks {
    static func main() throws {
        let source = """
        테스트 가게 안내
        제목·본문·태그에 암사 흑염소와 암사동 맛집 모두 포함.
        본문에 ‘업체에서 제공받아 작성했습니다.’를 넣어주세요.
        로스팅 공정 소개. 포토존 사진 포함. 게시 사진 2장 이상.
        촬영 20컷 이상. 제목 키워드 개수는 확인 필요.
        예약 연락처 010-1111-2222.
        """
        typealias R = CampaignGuide.Requirement
        let rules: [R] = [
            R(id: "keywords", kind: .keyword, label: "키워드", required: true, terms: ["암사 흑염소", "암사동 맛집"], match: .all, locations: [.title, .body, .tags], text: "", evidence: "암사 흑염소와 암사동 맛집 모두 포함"),
            R(id: "disclosure", kind: .exactText, label: "제공 고지", required: true, terms: [], match: .all, locations: [], text: "업체에서 제공받아 작성했습니다.", evidence: "업체에서 제공받아 작성했습니다."),
            R(id: "intro", kind: .mention, label: "로스팅 소개", required: true, terms: [], match: .all, locations: [], text: "로스팅 공정 소개", evidence: "로스팅 공정 소개"),
            R(id: "photo", kind: .photo, label: "포토존", required: true, terms: [], match: .all, locations: [], text: "포토존 사진", evidence: "포토존 사진 포함"),
            R(id: "count", kind: .minPhotos, label: "게시 사진 수", required: true, terms: [], match: .all, locations: [], text: "", minimum: 2, evidence: "게시 사진 2장 이상"),
            R(id: "capture", kind: .captureCount, label: "촬영 수", required: true, terms: [], match: .all, locations: [], text: "", minimum: 20, evidence: "촬영 20컷 이상"),
            R(id: "unclear", kind: .uncertain, label: "키워드 개수 확인", required: false, terms: [], match: .all, locations: [], text: "키워드 개수 확인", evidence: "제목 키워드 개수는 확인 필요")
        ]
        let guide = CampaignGuide(type: "blog-assistant.campaign", version: 1, restaurantName: "테스트 가게", requirements: rules, notes: ["예약은 원문 참고"])
        let json = try CampaignGuide.json(guide)
        let parsed = try CampaignGuide.parse("```json\n\(json)\n```", source: source, restaurantName: "테스트 가게")
        precondition(parsed == guide)
        func rejected(_ guide: CampaignGuide, source: String = source, name: String = "테스트 가게") {
            do { _ = try CampaignGuide.parse(CampaignGuide.json(guide), source: source, restaurantName: name); fatalError("Accepted invalid guide") } catch {}
        }
        rejected(guide, name: "다른 지점")
        var invalid = guide; invalid.requirements.append(rules[0]); rejected(invalid)
        invalid = guide; invalid.requirements[0].evidence = "원문에 없는 근거"; rejected(invalid)
        invalid = guide; invalid.requirements[0].terms = []; rejected(invalid)
        invalid = guide; invalid.requirements[0].locations = []; rejected(invalid)
        invalid = guide; invalid.requirements[4].minimum = 0; rejected(invalid)
        invalid = guide; invalid.version = 9; rejected(invalid)
        do { _ = try CampaignGuide.parse("글 초안입니다", source: source, restaurantName: "테스트 가게"); fatalError("Accepted prose as guide") } catch {}
        let extraction = try CampaignGuide.extractionRequest(source: source, restaurantName: "테스트 가게")
        precondition(extraction.contains("captureCount") && extraction.contains("uncertain") && extraction.contains(source.components(separatedBy: "\n")[0]))
        var record = CampaignGuideRecord(rawSource: source, guide: guide, confirmedSource: source)
        var review = VisitReview(); review.restaurantName = "테스트 가게"; review.visitDate = Date()
        review.photoIDs = ["p1"]; review.menus = [ReviewMenu(name: "전골", impression: "간은 아쉬웠어요.")]
        let photos = [DraftPhoto(id: "p1", caption: "포토존"), DraftPhoto(id: "v1", caption: "영상", mediaType: "video"), DraftPhoto(id: "p2", caption: "전골")]
        let text = """
        암사 흑염소 암사동 맛집 테스트 가게 전골
        업체에서 제공받아 작성했습니다.
        암사 흑염소를 먹은 암사동 맛집 방문 기록.
        로스팅 공정 소개.
        [사진 1]
        [영상 2]
        [사진 3]
        #암사흑염소 #암사동맛집
        """
        func checks(_ text: String = text, photos: [DraftPhoto] = photos, record: CampaignGuideRecord = record) -> [String: CampaignChecklist.Check] {
            Dictionary(uniqueKeysWithValues: CampaignChecklist.checks(record: record, text: text, photos: photos, review: review).map { ($0.id, $0) })
        }
        var result = checks()
        precondition(result["keywords"]?.status == .passed && result["disclosure"]?.status == .passed)
        precondition(result["intro"]?.status == .manual && result["count"]?.status == .passed)
        precondition(result["photo"]?.status == .manual && result["capture"]?.status == .manual)
        precondition(checks("")["count"]?.status == .manual)
        precondition(checks(text.replacingOccurrences(of: "암사 흑염소를 먹은 암사동 맛집 방문 기록.", with: "음식 기록"))["keywords"]?.status == .missing)
        precondition(checks(text.replacingOccurrences(of: "#암사동맛집", with: "#암사동맛집추천"))["keywords"]?.status == .missing)
        precondition(checks(text.replacingOccurrences(of: "업체에서 제공받아 작성했습니다.", with: "고지 없음"))["disclosure"]?.status == .missing)
        precondition(checks(text.replacingOccurrences(of: "[사진 3]", with: ""))["count"]?.status == .missing)
        precondition(checks(text.replacingOccurrences(of: "[사진 3]", with: "[영상 3]"))["count"]?.status == .missing)
        precondition(checks(text.replacingOccurrences(of: "[사진 3]", with: "[사진 1]"))["count"]?.status == .missing)
        precondition(checks("[사진 1]\n[사진 3]")["count"]?.status == .missing)
        let duplicateIDs = [photos[0], photos[1], DraftPhoto(id: "p1")]
        precondition(checks(photos: duplicateIDs)["count"]?.status == .missing)
        record.photoLinks["photo"] = ["p1"]
        let token = CampaignChecklist.token(text: text, photos: photos, links: record.photoLinks)
        for id in ["photo", "intro", "capture"] { record.confirmations[id] = token }
        result = checks(record: record)
        precondition(result["photo"]?.status == .passed && result["intro"]?.status == .passed && result["capture"]?.status == .passed)
        precondition(checks(text + "수정", record: record)["intro"]?.status == .manual)
        var changedPhotos = photos; changedPhotos[0].caption = "다른 설명"
        precondition(checks(photos: changedPhotos, record: record)["photo"]?.status == .manual)
        precondition(checks(text.replacingOccurrences(of: "[사진 1]", with: ""), record: record)["photo"]?.status == .missing)
        record.rawSource += "\n추가 확인 내용"
        precondition(record.needsReview && checks(record: record).values.allSatisfy { $0.status == .manual })
        record.rawSource = source
        var anyGuide = guide; anyGuide.requirements = [rules[0]]; anyGuide.requirements[0].match = .any
        let anyRecord = CampaignGuideRecord(rawSource: source, guide: anyGuide, confirmedSource: source)
        let oneKeyword = text.replacingOccurrences(of: "암사동 맛집", with: "가게").replacingOccurrences(of: "#암사동맛집", with: "")
        precondition(checks(oneKeyword, record: anyRecord)["keywords"]?.status == .passed)
        let writing = try DraftPrompt.make(review: review, references: nil, photos: photos, campaign: guide)
        precondition(writing.contains("체험단 작성 조건") && writing.contains("암사 흑염소") && writing.contains("간은 아쉬웠어요."))
        precondition(!writing.contains("010-1111-2222") && !writing.contains("evidence") && !writing.contains("\"p1\""))
        let title = try DraftPrompt.titleRequest(review: review, currentTitle: "제목", campaign: guide)
        precondition(title.contains("암사동 맛집") && !title.contains("포토존") && !title.contains("업체에서 제공받아 작성했습니다."))
        let ordinaryPrompt = try DraftPrompt.make(review: review, references: nil)
        precondition(!ordinaryPrompt.contains("체험단 작성 조건 (일반 제목"))

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CampaignGuideStore(fileURL: folder.appendingPathComponent("guides.json"))
        try store.save(record, reviewID: "visit1")
        try store.save(CampaignGuideRecord(rawSource: "두 번째 원문"), reviewID: "visit2")
        let savedFirst = try store.load(reviewID: "visit1")
        let savedSecond = try store.load(reviewID: "visit2")
        precondition(savedFirst == record)
        precondition(savedSecond.rawSource == "두 번째 원문")
        let broken = Data("broken".utf8); try broken.write(to: store.fileURL)
        do { try store.save(record, reviewID: "visit1"); fatalError("Overwrote broken guide store") } catch {}
        let preserved = try Data(contentsOf: store.fileURL)
        precondition(preserved == broken)

        let now = Date()
        let draft = BlogDraft(reviewID: "visit1", sourceReview: review, referencePostIDs: [], model: "test", createdAt: now, updatedAt: now, text: text, photos: photos, campaignGuide: guide)
        let restored = try JSONDecoder().decode(BlogDraft.self, from: JSONEncoder().encode(draft))
        precondition(restored.campaignGuide == guide)
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
        oldJSON.removeValue(forKey: "campaignGuide")
        let legacy = try JSONDecoder().decode(BlogDraft.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        precondition(legacy.campaignGuide == nil && legacy.text == text)
        var plan = DraftPhotoPlan(); plan.requestCampaign = guide
        let restoredPlan = try JSONDecoder().decode(DraftPhotoPlan.self, from: JSONEncoder().encode(plan))
        precondition(restoredPlan.requestCampaign == guide)
        print("Passed campaign import grounding, invalid/foreign guide rejection, all/any scoped keywords, exact text, manual checks/invalidation, actual unique image counts, store isolation/corruption protection, prompt/title integration and legacy draft compatibility")
    }
}
