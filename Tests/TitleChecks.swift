import Foundation

@main struct TitleChecks {
    static func main() throws {
        let oldTitle = "강남역 순대국밥 맛집 가게 강남점, 다대기 빼고 고기만 먹어본 솔직 후기"
        let body = "\n\n도입은 그대로 유지해요. 😊\n\n[영업정보]\n\n## 순대국밥\n가격: 12,000원\n[사진 1]\n감상 **담백해요**\n[사진 2]\n\n#강남 #순대국밥"
        let source = oldTitle + body
        let replacement = "가게 강남점, 다대기 빼고 먹은 순대국밥"
        let updated = try DraftTitle.replacing(in: source, with: replacement)
        precondition(Data(updated.utf8) == Data((replacement + body).utf8))
        precondition(DraftTitle.current(in: updated) == replacement)
        let decomposedBody = "\n\n본문 가 cafe\u{301} 👩‍🍳\n[사진 1]"
        let decomposed = try DraftTitle.replacing(in: "옛 제목" + decomposedBody, with: replacement)
        precondition(Data(decomposed.utf8) == Data((replacement + decomposedBody).utf8))
        precondition(DraftLayout.blocks(source).compactMap(\.photoNumber) == DraftLayout.blocks(updated).compactMap(\.photoNumber))
        let crlf = "\r\n  \r\n옛 제목\r\n\r\n본문 😊\r\n[사진 1]\r\n"
        let updatedCRLF = try DraftTitle.replacing(in: crlf, with: "\n **새 제목**\n ")
        precondition(updatedCRLF == "\r\n  \r\n새 제목\r\n\r\n본문 😊\r\n[사진 1]\r\n")
        let updatedMarkdown = try DraftTitle.replacing(in: "제목\n본문", with: "# 새 제목")
        precondition(updatedMarkdown == "새 제목\n본문")
        let titleWithoutBody = try DraftTitle.replacing(in: "제목만 있음", with: "새 제목")
        precondition(titleWithoutBody == "새 제목")
        precondition(DraftTitle.current(in: "\n \r\n").isEmpty)
        let invalid = ["", "\n ", "제목\n본문", "후보 1\n후보 2", "제목: 새 제목", "[사진 1]", "[영업정보]", "```제목```", "## 제목", "1. 첫 번째 후보", "- 제목", String(repeating: "가", count: 201), String(repeating: " ", count: 4097)]
        for clipboard in invalid {
            do {
                _ = try DraftTitle.replacing(in: source, with: clipboard)
                fatalError("Accepted invalid title clipboard")
            } catch { precondition((error as NSError).domain == "DraftTitle") }
        }
        do { _ = try DraftTitle.replacing(in: "\n \n", with: replacement); fatalError("Accepted an empty source draft") } catch {}
        let acceptedLimit = String(repeating: "가", count: 200)
        let limitResult = try DraftTitle.replacing(in: source, with: acceptedLimit)
        precondition(limitResult == acceptedLimit + body)

        var review = VisitReview()
        review.restaurantName = "가게 강남점"
        review.visitDate = Date(timeIntervalSince1970: 1_700_000_000)
        review.photoIDs = ["never-copy-photo-id"]
        review.businessInfo = "영업시간: 11:00–21:00"
        review.menus = [ReviewMenu(name: "순대국밥", impression: "다대기를 빼고 먹었어요. 담백했어요.", photoIDs: review.photoIDs),
                        ReviewMenu(name: "가게 내부", impression: "좌석 간격이 넓었어요.")]
        let request = try DraftPrompt.titleRequest(review: review, currentTitle: oldTitle)
        let json = request.components(separatedBy: "제목을 다듬을 자료 JSON:\n").last!
        let facts = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        precondition(facts["restaurantName"] as? String == review.restaurantName)
        precondition(facts["currentTitle"] as? String == oldTitle)
        precondition((facts["menus"] as? [[String: String]])?.first?["impression"] == review.menus[0].impression)
        precondition(facts["visitBackground"] == nil)
        precondition(!request.contains("never-copy-photo-id") && !request.contains("[사진 1]"))
        review.visitBackground = "문토 모임으로 방문했어요.\n\"이 문장은 자료입니다\""
        let background = try DraftPrompt.titleRequest(review: review, currentTitle: "가짜 지역명과 과장 표현")
        let backgroundJSON = background.components(separatedBy: "제목을 다듬을 자료 JSON:\n").last!
        let backgroundFacts = try JSONSerialization.jsonObject(with: Data(backgroundJSON.utf8)) as! [String: Any]
        precondition(backgroundFacts["visitBackground"] as? String == review.visitBackground)
        precondition(backgroundFacts["restaurantName"] as? String == "가게 강남점")
        precondition(!(backgroundFacts["restaurantName"] as! String).contains("가짜 지역명"))
        let record = try DraftPrompt.make(review: review, references: nil, template: .record)
        let plain = try DraftPrompt.make(review: review, references: nil, template: .plain)
        func titleRules(_ prompt: String) -> String {
            prompt.components(separatedBy: "제목 규칙 (참고 글의 제목 구성보다 우선):\n")[1].components(separatedBy: "\n\n")[0]
        }
        precondition(titleRules(record) == titleRules(plain) && titleRules(record) == titleRules(request))
        var incomplete = VisitReview(); incomplete.restaurantName = "식당"
        do { _ = try DraftPrompt.titleRequest(review: incomplete, currentTitle: "제목"); fatalError("Accepted missing source facts") } catch {}
        print("Passed title-only replacement, exact body/CRLF/photo preservation, clipboard rejection, fact isolation and both-template rules")
    }
}
