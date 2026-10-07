import Foundation

@main struct BridgeChecks {
    @MainActor static func main() async throws {
        let token = String(repeating: "a", count: 64)
        let extensionID = String(repeating: "a", count: 32)
        let configuration = try BridgeConfiguration.parse(extensionID + ":" + token)
        precondition(configuration.token == token)
        do { _ = try BridgeConfiguration.parse("bad:code"); fatalError("Accepted invalid pairing") } catch {}
        let partial = Data("POST /jobs/x/status HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\nab".utf8)
        let parsedPartial = try BridgeHTTPRequest.parse(partial)
        precondition(parsedPartial == nil)
        for raw in ["GET /../secret HTTP/1.1\r\n\r\n", "GET /%2fsecret HTTP/1.1\r\n\r\n", "POST / HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 1\r\n\r\n", "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"] {
            do { _ = try BridgeHTTPRequest.parse(Data(raw.utf8)); fatalError("Accepted malformed request") } catch {}
        }
        let suite = "BridgeChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bridge = NaverBridge(defaults: defaults, port: 48766)
        try bridge.connect(extensionID + ":" + token)
        defer { bridge.disconnect() }
        for _ in 0..<200 { if bridge.ready { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(bridge.ready, "Test loopback listener did not start")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        func request(_ path: String, method: String = "GET", key: String = token, origin: String? = nil, body: Data? = nil) async throws -> (Data, Int) {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:48766" + path)!)
            request.httpMethod = method; request.httpBody = body
            request.setValue(key, forHTTPHeaderField: "X-Blog-Assistant-Token")
            if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
            let (data, response) = try await session.data(for: request)
            return (data, (response as! HTTPURLResponse).statusCode)
        }
        let health = try await request("/health")
        precondition(health.1 == 200)
        let unauthorized = try await request("/health", key: "wrong")
        precondition(unauthorized.1 == 403)
        let wrongOrigin = try await request("/health", origin: "https://example.com")
        precondition(wrongOrigin.1 == 403)
        let preflight = try await request("/health", method: "OPTIONS", key: "", origin: "chrome-extension://" + extensionID)
        precondition(preflight.1 == 204)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let packet = NaverPostPacket(type: "blog-assistant.naver-post", version: 1, blogID: "bluedog129", categoryNo: "65", title: "테스트", blocks: [.init(kind: "text", text: "본문", photoNumber: nil)], photos: [.init(number: 1, filename: "01_사진.jpg", caption: "사진")])
        try JSONEncoder().encode(packet).write(to: folder.appendingPathComponent("naver-post.json"))
        let photo = Data([1, 2, 3, 4])
        try photo.write(to: folder.appendingPathComponent("01_사진.jpg"))
        let id = try bridge.prepareJob(folder: folder)
        let pending = try await request("/pending")
        let pendingJSON = try JSONSerialization.jsonObject(with: pending.0) as! [String: Any]
        precondition(pending.1 == 200 && pendingJSON["jobID"] as? String == id)
        let earlyPhoto = try await request("/jobs/\(id)/photos/1")
        precondition(earlyPhoto.1 == 404)
        let claim = try await request("/jobs/\(id)/claim", method: "POST")
        precondition(claim.1 == 200)
        let claimedPending = try await request("/pending")
        let claimedJSON = try JSONSerialization.jsonObject(with: claimedPending.0) as! [String: Any]
        precondition(claimedJSON["jobID"] == nil)
        let duplicate = try await request("/jobs/\(id)/claim", method: "POST")
        precondition(duplicate.1 == 409)
        let bytes = try await request("/jobs/\(id)/photos/1")
        precondition(bytes.0 == photo && bytes.1 == 200)
        let done = try await request("/jobs/\(id)/status", method: "POST", body: Data(#"{"state":"success","message":"완료"}"#.utf8))
        precondition(done.1 == 200 && !bridge.busy && bridge.message == "네이버 임시저장 완료")
        precondition(!FileManager.default.fileExists(atPath: folder.path))
        print("Passed loopback pairing/authentication/CORS, request limits, one-time claim, photo transfer, status callback and temporary cleanup")
    }
}
