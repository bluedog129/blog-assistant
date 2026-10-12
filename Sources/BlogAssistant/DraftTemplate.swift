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
    var color: String { role == "menu" || role == "section" ? "#003960" : (role == "price" ? "#777777" : "#333333") }
}

// Parse only explicit labels. Ambiguous pasted information stays verbatim.
enum BusinessSummary {
    struct Row: Equatable { let label: String; let value: String }
    static func rows(_ source: String) -> [Row] {
        let labels: [(String, String)] = [
            ("영업시간", "영업시간"), ("운영시간", "영업시간"),
            ("정기휴무", "휴무"), ("휴무일", "휴무"), ("휴무", "휴무"),
            ("브레이크타임", "브레이크타임"), ("브레이크 타임", "브레이크타임"),
            ("라스트오더", "라스트오더"), ("라스트 오더", "라스트오더"),
            ("마지막 주문", "라스트오더")
        ]
        var values: [String: [String]] = [:]
        var other: [String] = []
        var current: String?
        for raw in source.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { current = nil; continue }
            if let pair = labels.first(where: {
                line == $0.0 || line.hasPrefix($0.0 + ":") || line.hasPrefix($0.0 + "：") || line.hasPrefix($0.0 + " ")
            }) {
                current = pair.1
                let value = String(line.dropFirst(pair.0.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :：\t"))
                if !value.isEmpty { values[pair.1, default: []].append(value) }
            } else if line.range(of: #"^[가-힣A-Za-z ]+[:：]"#, options: .regularExpression) != nil {
                current = nil
                other.append(line)
            } else if let current {
                values[current, default: []].append(line)
            } else { other.append(line) }
        }
        var result = ["영업시간", "휴무", "브레이크타임", "라스트오더"].compactMap { label -> Row? in
            guard let entries = values[label], !entries.isEmpty else { return nil }
            return Row(label: label, value: entries.joined(separator: "\n"))
        }
        if !other.isEmpty { result.append(Row(label: "추가 정보", value: other.joined(separator: "\n"))) }
        return result
    }
    static func markdown(_ source: String) -> String {
        let rows = rows(source)
        guard !rows.isEmpty else { return "" }
        return "## 방문 전 확인\n" + rows.map { row in
            "**\(row.label)**: " + row.value
        }.joined(separator: "\n")
    }
}

enum DraftFormatting {
    static func title(_ source: String) -> String {
        var result = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("# ") { result.removeFirst(2) }
        return inline(result).map(\.text).joined()
    }

    static func expandBusinessInfo(_ text: String, review: VisitReview?) -> String {
        let summary = BusinessSummary.markdown(review?.businessInfo ?? "")
        return text.components(separatedBy: "\n").map { line in
            line.trimmingCharacters(in: .whitespaces) == "[영업정보]" ? summary : line
        }.joined(separator: "\n")
    }

    static func paragraphs(_ source: String, menus: [ReviewMenu] = []) -> [DraftParagraph] {
        var info = false
        return source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return DraftParagraph(role: "body", runs: []) }
            let heading = line.hasPrefix("## ") || line.hasPrefix("### ")
            let content = heading ? String(line.dropFirst(line.hasPrefix("### ") ? 4 : 3)) : line
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
        var lines = paragraphs(expandBusinessInfo(source, review: review), menus: review?.menus ?? []).map(\.text)
        if let first = lines.first { lines[0] = title(first) }
        return lines.joined(separator: "\n")
    }
}
