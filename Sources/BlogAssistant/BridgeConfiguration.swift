import Foundation

struct BridgeConfiguration: Codable {
    let extensionID: String
    let token: String
    static func parse(_ value: String) throws -> Self {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].range(of: "^[a-p]{32}$", options: .regularExpression) != nil,
              parts[1].range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw NSError(domain: "NaverBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "확장 프로그램의 앱 연결 코드를 복사해 붙여넣으세요."])
        }
        return Self(extensionID: String(parts[0]), token: String(parts[1]))
    }
}

