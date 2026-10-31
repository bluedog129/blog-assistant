import Foundation

enum DraftTemplate: String, Codable, CaseIterable, Identifiable {
    case record, plain
    var id: String { rawValue }
    var name: String { self == .record ? "단정한 기록" : "기본 텍스트" }
}

struct DraftTextRun: Codable, Equatable {
    let text: String
    let bold: Bool
}

struct DraftParagraph: Codable, Equatable {
    let role: String
    let runs: [DraftTextRun]
    var text: String { runs.map(\.text).joined() }
    var size: Double { role == "menu" ? 19 : (role == "price" || role == "info" ? 15 : 16) }
    var color: String { role == "price" ? "#777777" : "#333333" }
}

// Keep unrecognized information verbatim rather than guessing a schedule.
enum BusinessSummary {
    struct Row: Equatable { let label: String; let value: String }
    private struct Entry { var days: [Int]?; let value: String }
    private static let weekdays = ["월", "화", "수", "목", "금", "토", "일"]
    private static let labels: [(String, String)] = [
        ("도로명주소", "주소"), ("매장주소", "주소"), ("주소", "주소"),
        ("전화번호", "전화번호"), ("연락처", "전화번호"), ("전화", "전화번호"), ("Tel", "전화번호"),
        ("주차정보", "주차"), ("주차", "주차"), ("아기의자", "아기의자"), ("유아의자", "아기의자"),
        ("지하철", "교통"), ("교통", "교통"),
        ("체험단 방문시간", "체험단 방문시간"), ("방문가능 시간", "방문가능 시간"), ("방문가능시간", "방문가능 시간"),
        ("브레이크 타임", "브레이크타임"), ("브레이크타임", "브레이크타임"),
        ("라스트 오더", "라스트오더"), ("라스트오더", "라스트오더"), ("마지막 주문", "라스트오더"),
        ("정기휴무", "휴무"), ("휴무일", "휴무"), ("휴무", "휴무"),
        ("영업시간", "영업시간"), ("운영시간", "영업시간")
    ]

    static func rows(_ source: String) -> [Row] {
        var values: [String: [Entry]] = [:]
        var other: [String] = []
        var currentDays: [Int]?
        var currentLabel: String?
        var pendingDay: String?
        for raw in source.components(separatedBy: .newlines) {
            let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty else {
                if let pendingDay { other.append(pendingDay) }
                pendingDay = nil; currentDays = nil; currentLabel = nil
                continue
            }
            var line = original
            let day = dayPrefix(line)
            if let day {
                if let pendingDay { other.append(pendingDay) }
                pendingDay = nil
                currentDays = day.days
                line = day.rest
                if line.isEmpty {
                    if currentLabel == "휴무" {
                        values["휴무", default: []].append(Entry(days: day.days, value: "휴무"))
                    } else { pendingDay = original }
                    continue
                }
            }
            // A label must start the line, or follow a time, not appear in prose.
            var explicitLabel: String?
            for (alias, label) in labels {
                if line == alias || line.hasPrefix(alias + ":") || line.hasPrefix(alias + "：") || line.hasPrefix(alias + " ") || line.hasPrefix(alias + "(") || line.hasPrefix(alias + "（") {
                    explicitLabel = label
                    line = clean(String(line.dropFirst(alias.count)))
                    break
                }
                if let range = line.range(of: alias), timeValue(String(line[..<range.lowerBound])) != nil {
                    let suffix = clean(String(line[range.upperBound...]))
                    // Additional prose after a time label remains unclassified.
                    if suffix.isEmpty {
                        explicitLabel = label
                        line = clean(String(line[..<range.lowerBound]))
                        break
                    }
                }
            }
            if let label = explicitLabel {
                currentLabel = line.isEmpty ? label : nil
                if line.isEmpty {
                    if label == "휴무", let currentDays {
                        values[label, default: []].append(Entry(days: currentDays, value: "휴무"))
                        pendingDay = nil
                        currentLabel = nil
                    }
                    continue
                }
                // Holiday descriptions already carrying weekdays should not gain a second prefix.
                let schedule = ["휴무", "영업시간", "브레이크타임", "라스트오더", "방문가능 시간", "체험단 방문시간"].contains(label)
                var scopedDays = !schedule || (label == "휴무" && line.contains("요일")) ? nil : currentDays
                if label != "휴무", let innerDay = dayPrefix(line), !innerDay.rest.isEmpty {
                    scopedDays = innerDay.days
                    line = innerDay.rest
                }
                values[label, default: []].append(Entry(days: scopedDays, value: timeValue(line) ?? line))
                pendingDay = nil
            } else if let time = timeValue(line), currentDays != nil || currentLabel != nil {
                // An unlabeled range under a weekday means opening hours; a single
                // clock time alone is ambiguous, even under an opening-hours label.
                let label = currentLabel ?? (line.containsRangeSeparator ? "영업시간" : nil)
                if let label, label != "휴무", (label != "영업시간" || line.containsRangeSeparator) {
                    values[label, default: []].append(Entry(days: currentDays, value: time))
                    pendingDay = nil
                } else { other.append(original); currentLabel = nil }
            } else if let currentLabel, currentDays == nil, day == nil,
                      line.range(of: #"^[가-힣A-Za-z ]+[:：]"#, options: .regularExpression) == nil {
                // Preserve legacy multiline labeled fields, without interpreting prose.
                values[currentLabel, default: []].append(Entry(days: nil, value: line))
            } else {
                other.append(original)
                currentLabel = nil
            }
        }
        if let pendingDay { other.append(pendingDay) }
        var result = ["주소", "영업시간", "브레이크타임", "라스트오더", "휴무", "전화번호", "주차", "교통", "아기의자", "방문가능 시간", "체험단 방문시간"].compactMap { label -> Row? in
            guard let entries = values[label], !entries.isEmpty else { return nil }
            return Row(label: label, value: grouped(entries).joined(separator: "\n"))
        }
        if !other.isEmpty { result.append(Row(label: "추가 정보", value: other.joined(separator: "\n"))) }
        return result
    }

    static func markdown(_ source: String) -> String {
        let rows = rows(source)
        guard !rows.isEmpty else { return "" }
        return rows.map { row in
            let lines = row.value.components(separatedBy: "\n")
            if row.label == "추가 정보" { return row.value }
            return "\(icon(row.label)) **\(row.label):** \(lines[0])" + lines.dropFirst().map { "\n　　" + $0 }.joined()
        }.joined(separator: "\n")
    }

    static func icon(_ label: String) -> String {
        switch label {
        case "주소": return "📍"
        case "영업시간": return "⏰"
        case "브레이크타임": return "☕"
        case "라스트오더": return "🍽️"
        case "휴무": return "📅"
        case "전화번호": return "☎️"
        case "주차": return "🚗"
        case "교통": return "🚇"
        case "아기의자": return "🪑"
        default: return "🕒"
        }
    }

    static func paragraphs(_ source: String) -> [DraftParagraph] {
        markdown(source).components(separatedBy: "\n").filter { !$0.isEmpty }.map {
            DraftParagraph(role: "info", runs: DraftFormatting.inline($0))
        }
    }

    private static func grouped(_ entries: [Entry]) -> [String] {
        var groups: [Entry] = []
        for entry in entries {
            if let days = entry.days,
               let index = groups.firstIndex(where: { $0.days != nil && $0.value == entry.value }) {
                groups[index].days = Array(Set(groups[index].days! + days)).sorted()
            } else if !groups.contains(where: { $0.days == entry.days && $0.value == entry.value }) {
                groups.append(entry)
            }
        }
        let ordered = groups.enumerated().sorted {
            let left = $0.element.days?.min() ?? -1
            let right = $1.element.days?.min() ?? -1
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
        return ordered.map { entry in
            guard let days = entry.days else { return entry.value }
            let prefix = dayText(days)
            return entry.value == "휴무" ? "\(prefix) 휴무" : "\(prefix) \(entry.value)"
        }
    }

    private static func dayText(_ days: [Int]) -> String {
        let sorted = Array(Set(days)).sorted()
        if sorted == Array(0...6) { return "매일" }
        var parts: [String] = []
        var index = 0
        while index < sorted.count {
            var end = index
            while end + 1 < sorted.count && sorted[end + 1] == sorted[end] + 1 { end += 1 }
            if end - index >= 2 { parts.append(weekdays[sorted[index]] + "–" + weekdays[sorted[end]]) }
            else { parts += sorted[index...end].map { weekdays[$0] } }
            index = end + 1
        }
        return parts.joined(separator: "·")
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " :：\t"))
    }

    private static func dayPrefix(_ line: String) -> (days: [Int], rest: String)? {
        let pattern = #"^(매일|평일|주말|[월화수목금토일](?:요일)?(?:\s*[-~–—～·,/]\s*[월화수목금토일](?:요일)?)*)(?=\s|[:：]|$)"#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        let token = String(line[range]).replacingOccurrences(of: "요일", with: "").replacingOccurrences(of: " ", with: "")
        let days: [Int]
        switch token {
        case "매일": days = Array(0...6)
        case "평일": days = Array(0...4)
        case "주말": days = [5, 6]
        default:
            var parsed: [Int] = []
            let pieces = token.components(separatedBy: CharacterSet(charactersIn: "·,/"))
            for piece in pieces {
                let rangeParts = piece.components(separatedBy: CharacterSet(charactersIn: "-~–—～"))
                guard let first = rangeParts.first, let start = weekdays.firstIndex(of: first) else { return nil }
                if rangeParts.count == 2, let end = weekdays.firstIndex(of: rangeParts[1]) {
                    parsed += start <= end ? Array(start...end) : Array(start...6) + Array(0...end)
                } else if rangeParts.count == 1 { parsed.append(start) }
                else { return nil }
            }
            days = Array(Set(parsed)).sorted()
        }
        return (days, clean(String(line[range.upperBound...])))
    }

    private static func timeValue(_ line: String) -> String? {
        let value = clean(line)
        guard value.range(of: #"^\d{1,2}:\d{2}(?:\s*[-~–—～]\s*\d{1,2}:\d{2})?$"#, options: .regularExpression) != nil else { return nil }
        let times = value.components(separatedBy: CharacterSet(charactersIn: "-~–—～")).map { clean($0) }
        guard times.allSatisfy({ time in
            let parts = time.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && (0...29).contains(parts[0]) && (0...59).contains(parts[1])
        }) else { return nil }
        return times.map { time in
            let parts = time.split(separator: ":").compactMap { Int($0) }
            return String(format: "%02d:%02d", parts[0], parts[1])
        }.joined(separator: "–")
    }
}

private extension String {
    var containsRangeSeparator: Bool { rangeOfCharacter(from: CharacterSet(charactersIn: "-~–—～")) != nil }
}

enum DraftFormatting {
    static func title(_ source: String) -> String {
        var result = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("# ") { result.removeFirst(2) }
        return inline(result).map(\.text).joined()
    }

    static func expandVisitInfo(_ text: String, review: VisitReview?) -> String {
        let summary = BusinessSummary.markdown(review?.businessInfo ?? "")
        let map = NaverMapLink.url(review?.naverMapURL ?? "").map { "**네이버 지도**\n" + $0.absoluteString } ?? ""
        return text.components(separatedBy: "\n").map { line in
            switch line.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "[영업정보]": return summary
            case DraftMapLink.marker: return map
            default: return line
            }
        }.joined(separator: "\n")
    }

    static func paragraphs(_ source: String, menus: [ReviewMenu] = []) -> [DraftParagraph] {
        var info = false
        return source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return DraftParagraph(role: "body", runs: []) }
            let heading = line.hasPrefix("## ") || line.hasPrefix("### ")
            let content = heading ? String(line.dropFirst(line.hasPrefix("### ") ? 4 : 3)) : line
            if NaverMapLink.url(content) != nil {
                return DraftParagraph(role: info ? "info" : "body", runs: [DraftTextRun(text: content, bold: false)])
            }
            let plain = inline(content).map(\.text).joined()
            let section = ["방문 전 확인", "영업정보", "가게 정보", "먹고 나서", "한 줄 후기"].contains(plain)
            if heading { info = ["방문 전 확인", "영업정보", "가게 정보"].contains(plain) }
            if heading || menus.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == plain }) {
                return DraftParagraph(role: section ? "section" : "menu", runs: [DraftTextRun(text: plain, bold: true)])
            }
            if line.hasPrefix("가격: ") || line.hasPrefix("가격：") {
                return DraftParagraph(role: "price", runs: [DraftTextRun(text: plain, bold: false)])
            }
            return DraftParagraph(role: info ? "info" : "body", runs: inline(line))
        }
    }

    // Paired markers only; an unmatched marker is preserved instead of eating text.
    static func inline(_ source: String) -> [DraftTextRun] {
        var remaining = source[...]
        var result: [DraftTextRun] = []
        while let start = remaining.range(of: "**"),
              let end = remaining[start.upperBound...].range(of: "**"), end.lowerBound > start.upperBound {
            if start.lowerBound > remaining.startIndex {
                result.append(DraftTextRun(text: String(remaining[..<start.lowerBound]), bold: false))
            }
            result.append(DraftTextRun(text: String(remaining[start.upperBound..<end.lowerBound]), bold: true))
            remaining = remaining[end.upperBound...]
        }
        if !remaining.isEmpty { result.append(DraftTextRun(text: String(remaining), bold: false)) }
        return result
    }

    static func plainText(_ source: String, review: VisitReview?) -> String {
        var lines = paragraphs(expandVisitInfo(source, review: review), menus: review?.menus ?? []).map(\.text)
        if let first = lines.first { lines[0] = title(first) }
        return lines.joined(separator: "\n")
    }
}


enum DraftMapLink {
    static let marker = "[네이버지도]"
    private static let markerLine = try! NSRegularExpression(pattern: #"(?m)^[ \t]*\[네이버지도\][ \t]*(?=\r?$)"#)
    private static let businessLine = try! NSRegularExpression(pattern: #"(?m)^[ \t]*\[영업정보\][ \t]*(?=\r?$)"#)
    private static let lines = try! NSRegularExpression(pattern: #"(?m)^[^\r\n]+"#)

    static func applying(to source: String, url: String) throws -> String {
        let normalized = try NaverMapLink.normalized(url)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid("초안을 먼저 가져오거나 작성하세요.") }
        let whole = NSRange(source.startIndex..<source.endIndex, in: source)
        let existing = markerLine.matches(in: source, range: whole)
        guard existing.count <= 1 else { throw invalid("[네이버지도] 표시는 본문에 한 번만 남겨주세요.") }
        if let match = existing.first, let range = Range(match.range, in: source) {
            return normalized.isEmpty ? source.replacingCharacters(in: range, with: "") : source
        }
        guard !normalized.isEmpty else { return source }
        let newline = source.contains("\r\n") ? "\r\n" : "\n"
        if let info = businessLine.firstMatch(in: source, range: whole),
           let range = Range(NSRange(location: NSMaxRange(info.range), length: 0), in: source) {
            return source.replacingCharacters(in: range, with: newline + newline + marker)
        }
        // Place an appended link before all trailing hashtag lines, leaving
        // existing prose and photo markers untouched.
        let ns = source as NSString
        var tagStart: Int?
        for line in lines.matches(in: source, range: whole).reversed() {
            let value = ns.substring(with: line.range).trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }
            let words = value.split(whereSeparator: { $0.isWhitespace })
            guard words.allSatisfy({ $0.hasPrefix("#") && $0.count > 1 && !$0.hasPrefix("##") }) else { break }
            tagStart = line.range.location
        }
        if let tagStart, let range = Range(NSRange(location: tagStart, length: 0), in: source) {
            return source.replacingCharacters(in: range, with: marker + newline + newline)
        }
        return source + newline + newline + marker
    }

    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "DraftMapLink", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
