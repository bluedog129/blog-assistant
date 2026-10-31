import Foundation

@main struct MapLinkChecks {
    static func main() throws {
        let short = "https://naver.me/Example1"
        let place = "https://m.place.naver.com/restaurant/123456789/home"
        let desktop = "https://map.naver.com/p/entry/place/123456789?c=15.00,0,0,0,dh"
        precondition(tryValue("  \(short)\n") == short)
        precondition(NaverMapLink.url(place)?.absoluteString == place)
        precondition(NaverMapLink.url(desktop)?.absoluteString == desktop)
        precondition(NaverMapLink.url("https://pcmap.place.naver.com/restaurant/123456789/home") != nil)
        precondition(NaverMapLink.url("HTTPS://NAVER.ME/Example1")?.absoluteString == short)
        for invalid in ["javascript:alert(1)", "file:///tmp/a", "http://naver.me/Example1", "https://naver.me", "https://map.naver.com/", "https://naver.me.evil.example/a", "https://evil.example/naver.me/a", "https://user@naver.me/a", "https://naver.me:443/a", "https://naver.me/a b", "https://naver.me/a\nb", "https://naver.me/" + String(repeating: "a", count: 2048)] {
            precondition(NaverMapLink.url(invalid) == nil)
            do { _ = try NaverMapLink.normalized(invalid); fatalError("Accepted invalid map address") } catch {}
        }
        let empty = try NaverMapLink.normalized(" \n ")
        precondition(empty.isEmpty)
        let shared = try NaverMapLink.pastedURL("[네이버 지도]\n테스트 식당\n서울시 어느 길\n\(short)")
        precondition(shared == short)
        let repeated = try NaverMapLink.pastedURL("\(short)\n\(short)")
        precondition(repeated == short)
        for invalid in ["복사 내용 없음", "https://example.com/a", "\(short)\n\(place)"] {
            do { _ = try NaverMapLink.pastedURL(invalid); fatalError("Accepted missing/ambiguous shared map link") } catch {}
        }
        let search = NaverMapLink.searchURL(for: "가게 성수 / 본점 #1?")!
        precondition(search.host == "map.naver.com" && search.path == "/p/search/가게 성수 / 본점 #1?")
        precondition(search.query == nil && search.fragment == nil)
        precondition(NaverMapLink.searchURL(for: " \n ") == nil)

        var review = VisitReview()
        review.photoIDs = ["private-map-photo"]
        review.restaurantName = "테스트 식당"
        review.visitDate = Date(timeIntervalSince1970: 1_700_000_000)
        review.menus = [ReviewMenu(name: "파스타", impression: "담백했어요", photoIDs: review.photoIDs)]
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(review)) as! [String: Any]
        legacy.removeValue(forKey: "naverMapURL")
        let decoded = try JSONDecoder().decode(VisitReview.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(decoded.naverMapURL.isEmpty && decoded == review)
        let suite = "BlogAssistant.MapLinkTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReviewStore(defaults: defaults)
        review.naverMapURL = "  \(short) "
        try store.save(review)
        let saved = try store.load(id: review.id)!
        precondition(saved.naverMapURL == short && saved.photoIDs == review.photoIDs && saved.menus == review.menus)
        var invalidReview = saved; invalidReview.naverMapURL = "https://invalid.example/a"
        do { try store.save(invalidReview); fatalError("Saved an invalid map address") } catch {}
        let afterInvalidSave = try store.load(id: saved.id)!
        precondition(afterInvalidSave == saved)
        var cleared = saved; cleared.naverMapURL = ""
        try store.save(cleared)
        let afterClear = try store.load(id: saved.id)!
        precondition(afterClear.naverMapURL.isEmpty && afterClear.menus == saved.menus)

        let source = "제목\n\n도입 😊\n\n[영업정보]\n\n## 파스타\n[사진 1]\n담백해요.\n\n#맛집\n#파스타\n"
        let withMap = try DraftMapLink.applying(to: source, url: short)
        precondition(withMap == source.replacingOccurrences(of: "[영업정보]", with: "[영업정보]\n\n[네이버지도]"))
        precondition(DraftLayout.blocks(withMap).compactMap(\.photoNumber) == [1])
        let twice = try DraftMapLink.applying(to: withMap, url: place)
        precondition(twice == withMap)
        let removed = try DraftMapLink.applying(to: withMap, url: "")
        precondition(removed == source.replacingOccurrences(of: "[영업정보]", with: "[영업정보]\n\n"))
        let noBusiness = "제목\n\n본문\n[사진 1]\n\n#맛집\n#파스타\n"
        let appended = try DraftMapLink.applying(to: noBusiness, url: short)
        precondition(appended == "제목\n\n본문\n[사진 1]\n\n[네이버지도]\n\n#맛집\n#파스타\n")
        let crlf = "\r\n제목\r\n[영업정보]\r\n[사진 1]\r\n"
        let updatedCRLF = try DraftMapLink.applying(to: crlf, url: short)
        precondition(Data(updatedCRLF.utf8) == Data("\r\n제목\r\n[영업정보]\r\n\r\n[네이버지도]\r\n[사진 1]\r\n".utf8))
        do { _ = try DraftMapLink.applying(to: " \n", url: short); fatalError("Accepted an empty draft") } catch {}
        do { _ = try DraftMapLink.applying(to: "제목\n[네이버지도]\n[네이버지도]", url: short); fatalError("Accepted duplicate map markers") } catch {}

        review = saved
        review.businessInfo = "휴무: 월요일\n영업시간: 화–일 11:00–21:00"
        let expanded = DraftFormatting.expandVisitInfo(withMap, review: review)
        precondition(expanded.contains("**네이버 지도**\n" + short) && expanded.contains("화–일 11:00–21:00"))
        precondition(!expanded.contains("[네이버지도]") && !expanded.contains("[영업정보]"))
        precondition(!DraftFormatting.expandVisitInfo(withMap, review: nil).contains("네이버 지도"))
        for template in DraftTemplate.allCases {
            let prompt = try DraftPrompt.make(review: review, references: nil, photos: [DraftPhoto(id: review.photoIDs[0], caption: "파스타")], template: template)
            let json = prompt.components(separatedBy: "방문 정보 JSON:\n")[1].components(separatedBy: "\n\n순서대로 배치할 사진 목록 JSON:")[0]
            let facts = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
            precondition(facts["naverMapURL"] as? String == short)
            let packet = try NaverPostPacket.make(text: withMap, photos: [DraftPhoto(id: "private-map-photo", caption: "파스타")], filenames: ["01.jpg"], template: template, review: review)
            let body = packet.blocks.compactMap(\.text).joined(separator: "\n")
            precondition(!body.contains(short) && !body.contains("[네이버지도]"))
            let maps = packet.blocks.filter { $0.kind == "map" }
            precondition(packet.version == 4 && maps.count == 1 && maps[0].place?.url == short && maps[0].place?.name == review.restaurantName)
            precondition(packet.blocks.compactMap(\.photoNumber) == [1] && packet.title == "제목")
            let copy = DraftFormatting.plainText(withMap, review: review)
            precondition(copy.contains(short) && !copy.contains("[네이버지도]"))
        }
        review.businessInfo += "\n주소: 서울 예시로 1"
        precondition(NaverPostPacket.Place.target(review)?.address == "서울 예시로 1")
        let mixed = try NaverPostPacket.make(text: "제목\r\n도입\r\n[네이버지도]\r\n[영업정보]\r\n[사진 1]\r\n[영상 2]\r\n감상",
                                             photos: [DraftPhoto(id: "p", caption: "음식"), DraftPhoto(id: "v", caption: "영상", mediaType: "video")],
                                             filenames: ["01_음식.jpg", "02_영상.mp4"], template: .record, review: review)
        precondition(mixed.version == 4 && mixed.blocks.map(\.kind) == ["text", "map", "info", "photo", "video", "text"])
        precondition(mixed.blocks.compactMap(\.photoNumber) == [1, 2] && mixed.photos[1].isVideo)
        let unusual = "https://map.naver.com/p/entry/place/123?query=one**two**three"
        let paragraph = DraftFormatting.paragraphs(unusual)[0]
        precondition(paragraph.text == unusual && paragraph.runs.count == 1 && !paragraph.runs[0].bold)
        do { _ = try NaverPostPacket.make(text: "제목\n[네이버지도]\n[네이버지도]\n본문", photos: [], filenames: [], review: review); fatalError("Exported duplicate map markers") } catch {}
        print("Passed map link validation/share extraction, legacy/persistence/clear, marker insertion/removal/CRLF, frozen-link expansion and both-template prompt/export/copy checks")
    }

    private static func tryValue(_ value: String) -> String { try! NaverMapLink.normalized(value) }
}
