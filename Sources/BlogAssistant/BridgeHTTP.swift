import Foundation
import Network

struct BridgeHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    static func parse(_ bytes: Data) throws -> Self? {
        guard bytes.count <= 80_000 else { throw CocoaError(.fileReadTooLarge) }
        guard let boundary = bytes.range(of: Data("\r\n\r\n".utf8)) else {
            if bytes.count > 16_000 { throw CocoaError(.fileReadTooLarge) }
            return nil
        }
        guard boundary.lowerBound <= 16_000, let head = String(data: bytes[..<boundary.lowerBound], encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count == 3, first[2] == "HTTP/1.1", ["GET", "POST", "OPTIONS"].contains(String(first[0])),
              first[1].hasPrefix("/"), !first[1].contains(".."), !first[1].contains("%") else { throw CocoaError(.fileReadCorruptFile) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw CocoaError(.fileReadCorruptFile) }
            let name = line[..<colon].lowercased()
            guard headers[name] == nil else { throw CocoaError(.fileReadCorruptFile) }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil, let length = Int(headers["content-length"] ?? "0"), (0...64_000).contains(length) else { throw CocoaError(.fileReadCorruptFile) }
        let start = boundary.upperBound
        guard bytes.count >= start + length else { return nil }
        guard bytes.count == start + length else { throw CocoaError(.fileReadCorruptFile) }
        return Self(method: String(first[0]), path: String(first[1]), headers: headers, body: Data(bytes[start...]))
    }
}

struct BridgeHTTPResponse {
    let status: Int
    let body: Data
    let type: String
    var headers: [String: String] = [:]
    static func text(_ status: Int, _ value: String) -> Self { Self(status: status, body: Data(value.utf8), type: "text/plain; charset=utf-8") }
    var data: Data {
        var head = "HTTP/1.1 \(status) Response\r\nContent-Length: \(body.count)\r\nContent-Type: \(type)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        var data = Data((head + "\r\n").utf8); data.append(body); return data
    }
}

enum BridgeHTTP {
    static func receive(_ connection: NWConnection, accumulated: Data = Data(), completion: @escaping (BridgeHTTPRequest) -> Void) {
        if accumulated.isEmpty {
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { connection.cancel() }
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_000) { bytes, _, done, error in
            var data = accumulated
            if let bytes { data.append(bytes) }
            do {
                if let request = try BridgeHTTPRequest.parse(data) { completion(request) }
                else if done || error != nil { connection.cancel() }
                else { receive(connection, accumulated: data, completion: completion) }
            } catch { send(.text(400, "요청 형식 오류"), on: connection) }
        }
    }
    static func send(_ response: BridgeHTTPResponse, on connection: NWConnection) {
        connection.send(content: response.data, completion: .contentProcessed { _ in connection.cancel() })
    }
}
