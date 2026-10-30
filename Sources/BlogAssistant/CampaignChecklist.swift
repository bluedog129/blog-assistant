import Foundation
import CryptoKit

enum CampaignChecklist {
    enum Status { case passed, missing, manual }
    struct Check: Identifiable {
        let requirement: CampaignGuide.Requirement
        let status: Status
        let detail: String
        var id: String { requirement.id }
    }
    static func token(text: String, photos: [DraftPhoto], links: [String: [String]]) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        struct Input: Encodable { let text: String; let photos: [DraftPhoto]; let links: [String: [String]] }
        let data = (try? encoder.encode(Input(text: text, photos: photos, links: links))) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func checks(record: CampaignGuideRecord, text: String, photos: [DraftPhoto], review: VisitReview) -> [Check] {
        guard let guide = record.guide else { return [] }
        let token = token(text: text, photos: photos, links: record.photoLinks)
        let trimmed = CampaignGuide.clean(text)
        let expanded = DraftFormatting.plainText(text, review: review)
        let lines = expanded.components(separatedBy: .newlines)
        let titleIndex = lines.firstIndex { !CampaignGuide.clean($0).isEmpty }
        let title = titleIndex.map { lines[$0] } ?? ""
        let bodyLines = titleIndex.map { Array(lines.dropFirst($0 + 1)) } ?? []
        func isTagLine(_ line: String) -> Bool { line.range(of: #"^\s*(?:#[\p{L}\p{N}_]+\s*)+$"#, options: .regularExpression) != nil }
        let tags = bodyLines.filter(isTagLine).joined(separator: " ").split(whereSeparator: \.isWhitespace).map(String.init)
        let body = bodyLines.filter { !isTagLine($0) }.joined(separator: "\n")
        let sourceLines = text.components(separatedBy: .newlines)
        let bodySource = sourceLines.firstIndex { !CampaignGuide.clean($0).isEmpty }.map { sourceLines.dropFirst($0 + 1).joined(separator: "\n") } ?? ""
        let placed = Set(DraftLayout.blocks(bodySource).compactMap { block -> String? in
            guard let n = block.photoNumber, !block.isVideo, photos.indices.contains(n - 1), !photos[n - 1].isVideo else { return nil }
            return photos[n - 1].id
        })
        func contains(_ haystack: String, _ needle: String) -> Bool {
            let normalize: (String) -> String = { $0.precomposedStringWithCanonicalMapping.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).lowercased() }
            return normalize(haystack).contains(normalize(needle))
        }
        return guide.requirements.map { item in
            func result(_ status: Status, _ detail: String) -> Check { Check(requirement: item, status: status, detail: detail) }
            guard !record.needsReview else { return result(.manual, "원문 변경 후 요구사항을 다시 확인·저장하세요.") }
            guard !trimmed.isEmpty else { return result(.manual, "초안을 붙여넣으면 검사합니다.") }
            switch item.kind {
            case .keyword:
                let failed = item.locations.filter { location in
                    let matches = item.terms.map { term in
                        location == .tags ? tags.contains { CampaignGuide.compact($0) == "#" + CampaignGuide.compact(term) } : contains(location == .title ? title : body, term)
                    }
                    return item.match == .all ? !matches.allSatisfy { $0 } : !matches.contains(true)
                }
                let names = failed.map { $0 == .title ? "제목" : ($0 == .body ? "본문" : "태그") }
                return result(failed.isEmpty ? .passed : .missing, failed.isEmpty ? "지정 위치의 키워드를 확인했습니다." : "\(names.joined(separator: "·")) 키워드 누락 · \(item.terms.joined(separator: " / "))")
            case .exactText:
                return result(contains(body, item.text) ? .passed : .missing, contains(body, item.text) ? "본문에서 지정 문장을 확인했습니다." : "본문에 지정 문장이 없습니다.")
            case .minPhotos:
                return result(placed.count >= (item.minimum ?? Int.max) ? .passed : .missing, "본문 사진 \(placed.count)장 / 최소 \(item.minimum ?? 0)장 · 영상·중복 제외")
            case .photo:
                let linked = Set(record.photoLinks[item.id] ?? [])
                guard !linked.isEmpty else { return result(.manual, "해당 사진을 연결하고 실제 피사체를 확인하세요.") }
                guard linked.isSubset(of: placed) else { return result(.missing, "연결한 사진이 본문에 빠졌거나 사진 종류·번호가 다릅니다.") }
                return result(record.confirmations[item.id] == token ? .passed : .manual, record.confirmations[item.id] == token ? "직접 내용 확인 완료 · 본문 사진 배치 확인" : "본문 배치 확인 · 실제 사진 내용은 직접 확인하세요.")
            case .mention, .captureCount, .uncertain:
                let confirmed = record.confirmations[item.id] == token
                return result(confirmed ? .passed : .manual, confirmed ? "현재 초안 기준 직접 확인 완료" : (item.kind == .captureCount ? "촬영 수 조건입니다. 게시 사진 수로 자동 판정하지 않습니다." : "의미·조건을 직접 확인하세요. 단어 포함만으로 자동 통과시키지 않습니다."))
            }
        }
    }
}
