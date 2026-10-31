import Foundation

@main struct BusinessSummaryChecks {
    static func main() throws {
        let days = ["화", "수", "목", "금", "토", "일"]
        let pasted = "월\n정기휴무 (매주 월요일)\n" + days.map {
            "\($0)\n11:00 - 21:00\n15:00 ~ 16:20 브레이크타임\n20:20 라스트오더"
        }.joined(separator: "\n")
        let rows = BusinessSummary.rows(pasted)
        precondition(rows.map(\.label) == ["영업시간", "브레이크타임", "라스트오더", "휴무"])
        precondition(rows[3].value == "(매주 월요일)")
        precondition(rows[0].value == "화–일 11:00–21:00")
        precondition(rows[1].value == "화–일 15:00–16:20")
        precondition(rows[2].value == "화–일 20:20")
        let exceptions = BusinessSummary.rows("영업시간\n평일 11:00~21:00\n토 12:00–22:00\n일 12:00–20:00\n\n주차: 매장 문의")
        precondition(exceptions[0].value == "월–금 11:00–21:00\n토 12:00–22:00\n일 12:00–20:00")
        precondition(exceptions[1] == BusinessSummary.Row(label: "주차", value: "매장 문의"))
        let mixed = BusinessSummary.rows("월 영업시간: 09:00-18:00\n수 영업시간: 9:00~18:00\n금 영업시간: 09:00–18:00\n토 영업시간: 10:00–17:00")
        precondition(mixed[0].value == "월·수·금 09:00–18:00\n토 10:00–17:00")
        precondition(BusinessSummary.rows("영업시간: 매일 11:00 - 21:00")[0].value == "매일 11:00–21:00")
        precondition(BusinessSummary.rows("브레이크타임\n평일 15:00-16:00\n주말 15:00-17:00")[0].value == "월–금 15:00–16:00\n토·일 15:00–17:00")
        precondition(BusinessSummary.rows("브레이크타임\n월\n15:00-16:00\n화\n15:00-16:00")[0] == BusinessSummary.Row(label: "브레이크타임", value: "월·화 15:00–16:00"))
        precondition(BusinessSummary.rows("일 12:00-20:00\n평일 11:00-21:00")[0].value == "월–금 11:00–21:00\n일 12:00–20:00")
        precondition(BusinessSummary.rows("금~월 11:00–02:00")[0].value == "월·금–일 11:00–02:00")
        let conflict = BusinessSummary.rows("월 11:00-21:00\n월 12:00-20:00\n화 11:00-21:00")
        precondition(conflict[0].value == "월·화 11:00–21:00\n월 12:00–20:00")
        let unknown = "공휴일은 매장에 문의\n영업시간은 변동될 수 있습니다\n특별 안내: 예약 필수"
        precondition(BusinessSummary.rows(unknown) == [BusinessSummary.Row(label: "추가 정보", value: unknown)])
        precondition(BusinessSummary.rows("월\n화\n11:00-21:00").last?.value == "월")
        precondition(BusinessSummary.rows("월").first?.value == "월")
        precondition(BusinessSummary.rows("월\n11:99-21:00").last?.value.contains("11:99-21:00") == true)
        precondition(BusinessSummary.rows("휴무: 없음").first?.value == "없음")
        precondition(BusinessSummary.rows("휴무\n월요일\n화요일").first?.value == "월·화 휴무")
        precondition(BusinessSummary.rows("월\n휴무\n화\n11:00-21:00").map(\.value) == ["화 11:00–21:00", "월 휴무"])
        precondition(BusinessSummary.rows("운영시간: 24시간\n브레이크 타임: 없음").map(\.value) == ["24시간", "없음"])
        precondition(BusinessSummary.rows(" \n").isEmpty)
        let formatted = BusinessSummary.markdown(pasted)
        precondition(formatted.contains("⏰ **영업시간:** 화–일 11:00–21:00") && formatted.contains("📅 **휴무:** (매주 월요일)"))
        let detailed = BusinessSummary.markdown("영업시간\n평일 11:00-21:00\n주말 12:00-22:00")
        precondition(detailed.contains("⏰ **영업시간:** 월–금 11:00–21:00\n　　토·일 12:00–22:00"))
        // Preview, copied text, and Naver packet must use the same normalized schedule.
        var review = VisitReview(); review.businessInfo = pasted
        let text = "테스트 제목\n\n[영업정보]\n\n## 먹고 나서\n다시 방문하고 싶어요."
        let packet = try NaverPostPacket.make(text: text, photos: [], filenames: [], template: .record, review: review)
        let paragraphs = packet.blocks.flatMap { $0.paragraphs ?? [] }
        precondition(packet.version == 4 && packet.blocks.first?.kind == "info")
        precondition(paragraphs.contains { $0.text == "⏰ 영업시간: 화–일 11:00–21:00" && $0.runs.contains(DraftTextRun(text: "영업시간:", bold: true)) && $0.role == "info" })
        precondition(DraftFormatting.plainText(text, review: review).contains("라스트오더: 화–일 20:20"))
        let input = "주소: 서울 강동구 예시로 1\n영업시간: 매일 10:00~21:30\n전화번호: 02-000-0000\n주차: 가능\n체험단 방문시간: 평일 14:00~16:00"
        let compact = BusinessSummary.markdown(input)
        precondition(compact.contains("📍 **주소:** 서울 강동구 예시로 1\n⏰ **영업시간:** 매일 10:00–21:30\n☎️ **전화번호:** 02-000-0000"))
        precondition(compact.contains("**체험단 방문시간:** 월–금 14:00–16:00"))
        precondition(!compact.contains("방문 전 확인") && !compact.contains("\n\n") && !compact.contains("추가 정보"))
        let afterSchedule = BusinessSummary.rows("평일 10:00~21:00\n전화번호: 02-000-0000\n주소: 서울 예시로 1")
        precondition(afterSchedule.first?.value == "서울 예시로 1" && afterSchedule.last?.value == "02-000-0000")
        print("Business summary checks passed")
    }
}
