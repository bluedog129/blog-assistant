import AppKit
import Foundation
import Network
import SwiftUI

@MainActor final class NaverBridge: ObservableObject {
    static let shared = NaverBridge()
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published private(set) var message = "Chrome 확장 프로그램을 연결하세요."
    private(set) var configuration: BridgeConfiguration?
    private var listener: NWListener?
    private var job: Job?
    private var timeout: Task<Void, Never>?
    private var previousResultUnknown = false
    private let defaults: UserDefaults
    private let port: UInt16
    private let queue = DispatchQueue(label: "BlogAssistant.NaverBridge")
    private struct Job {
        let id: String
        let folder: URL
        let packet: NaverPostPacket
        var claimed = false
    }
    init(defaults: UserDefaults = .standard, port: UInt16 = 48765) {
        self.defaults = defaults
        self.port = port
        if let data = defaults.data(forKey: "naverBridge.v1") {
            configuration = try? JSONDecoder().decode(BridgeConfiguration.self, from: data)
        }
        if defaults.bool(forKey: "naverBridge.pending") {
            previousResultUnknown = true
            message = "이전 임시저장 작업의 결과를 확인하지 못했습니다. 네이버 임시저장 목록을 확인하세요."
            defaults.set(false, forKey: "naverBridge.pending")
        }
    }
    func connect(_ code: String) throws {
        guard !busy else { throw failure("작업 중에는 연결을 바꿀 수 없습니다.") }
        configuration = try BridgeConfiguration.parse(code)
        defaults.set(try JSONEncoder().encode(configuration), forKey: "naverBridge.v1")
        start()
    }
    func start() {
        guard configuration != nil, listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            let server = try NWListener(using: parameters)
            listener = server
            server.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    if case .ready = state { self.ready = true; if !self.busy && !self.previousResultUnknown { self.message = "Chrome 연결 준비 완료" } }
                    if case .failed = state { self.ready = false; self.message = "Chrome 연결 서버를 열지 못했습니다. 앱을 중복 실행했는지 확인하세요."; self.listener?.cancel(); self.listener = nil }
                }
            }
            server.newConnectionHandler = { [weak self] connection in
                connection.start(queue: DispatchQueue(label: "BlogAssistant.BridgeRequest"))
                BridgeHTTP.receive(connection) { request in
                    Task { @MainActor in
                        guard let self else { connection.cancel(); return }
                        let response = self.respond(request)
                        BridgeHTTP.send(response, on: connection)
                    }
                }
            }
            server.start(queue: queue)
        } catch { listener = nil; ready = false; message = "Chrome 연결을 시작하지 못했습니다." }
    }
    func submit(folder: URL) async throws {
        guard configuration != nil else { throw failure("먼저 Chrome 연결 설정을 완료하세요.") }
        let id = try prepareJob(folder: folder)
        let url = URL(string: "https://blog.naver.com/bluedog129")!
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        do {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
        } catch { finish("Chrome을 열지 못했습니다. Chrome 설치와 확장 프로그램 연결을 확인하세요."); throw error }
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.busy, self.job?.id == id, self.job?.claimed == false {
                self.finish("확장 프로그램이 작업을 받지 못했습니다. Chrome 프로필·확장 프로그램 새로고침·연결 코드를 확인하세요.")
                return
            }
            try? await Task.sleep(nanoseconds: 1_110_000_000_000)
            guard !Task.isCancelled, self.busy, self.job?.id == id else { return }
            self.finish("임시저장 결과를 확인하지 못했습니다. 네이버 편집기와 임시저장 목록을 확인하세요.")
        }
    }
    func prepareJob(folder: URL) throws -> String {
        guard ready, configuration != nil else { throw failure("먼저 Chrome 연결 설정을 완료하세요.") }
        guard !busy else { throw failure("이미 네이버 임시저장 작업이 진행 중입니다.") }
        let packet = try JSONDecoder().decode(NaverPostPacket.self, from: Data(contentsOf: folder.appendingPathComponent("naver-post.json")))
        let id = UUID().uuidString
        job = Job(id: id, folder: folder, packet: packet)
        previousResultUnknown = false
        busy = true; message = "Chrome에 글과 사진을 전달하는 중…"
        defaults.set(true, forKey: "naverBridge.pending")
        return id
    }
    func disconnect() {
        guard !busy else { return }
        listener?.cancel(); listener = nil; ready = false; configuration = nil
        defaults.removeObject(forKey: "naverBridge.v1")
        message = "Chrome 연결을 해제했습니다."
    }
    private func finish(_ value: String) {
        busy = false; message = value; timeout?.cancel(); timeout = nil
        defaults.set(false, forKey: "naverBridge.pending")
        if let job { try? FileManager.default.removeItem(at: job.folder) }
    }
    private func respond(_ request: BridgeHTTPRequest) -> BridgeHTTPResponse {
        guard let configuration, request.headers["host"] == "127.0.0.1:\(port)" else { return .text(403, "접근이 허용되지 않습니다.") }
        let origin = "chrome-extension://\(configuration.extensionID)"
        if let supplied = request.headers["origin"], supplied != origin { return .text(403, "연결된 확장 프로그램이 아닙니다.") }
        func allow(_ response: BridgeHTTPResponse) -> BridgeHTTPResponse {
            var value = response
            value.headers["Access-Control-Allow-Origin"] = origin
            return value
        }
        if request.method == "OPTIONS" {
            guard request.headers["origin"] == origin else { return .text(403, "연결된 확장 프로그램이 아닙니다.") }
            var response = allow(.text(204, ""))
            response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
            response.headers["Access-Control-Allow-Headers"] = "Content-Type, X-Blog-Assistant-Token"
            return response
        }
        guard request.headers["x-blog-assistant-token"] == configuration.token else { return .text(403, "접근이 허용되지 않습니다.") }
        if request.method == "GET", request.path == "/health" { return allow(.text(200, "ready")) }
        if request.method == "GET", request.path == "/pending" {
            struct Pending: Encodable { let jobID: String? }
            let id = busy && job?.claimed == false ? job?.id : nil
            return allow(BridgeHTTPResponse(status: 200, body: (try? JSONEncoder().encode(Pending(jobID: id))) ?? Data(), type: "application/json"))
        }
        guard let current = job, busy else { return allow(.text(404, "진행 중인 작업이 없습니다.")) }
        let prefix = "/jobs/\(current.id)"
        if request.method == "POST", request.path == prefix + "/claim" {
            guard !current.claimed else { return allow(.text(409, "이미 전달한 작업입니다. 중복 입력은 하지 않습니다.")) }
            job?.claimed = true
            return allow(BridgeHTTPResponse(status: 200, body: (try? JSONEncoder().encode(current.packet)) ?? Data(), type: "application/json"))
        }
        if request.method == "GET", request.path.hasPrefix(prefix + "/photos/"), current.claimed,
           let number = Int(request.path.dropFirst((prefix + "/photos/").count)),
           let photo = current.packet.photos.first(where: { $0.number == number }),
           let bytes = try? Data(contentsOf: current.folder.appendingPathComponent(photo.filename)) {
            return allow(BridgeHTTPResponse(status: 200, body: bytes, type: "image/jpeg"))
        }
        if request.method == "POST", request.path == prefix + "/status", current.claimed {
            struct Status: Decodable { let state: String; let message: String }
            guard let result = try? JSONDecoder().decode(Status.self, from: request.body), result.message.count <= 3000,
                  ["progress", "success", "failure"].contains(result.state) else { return allow(.text(400, "상태 형식 오류")) }
            if result.state == "progress" { message = result.message }
            else { finish(result.state == "success" ? "네이버 임시저장 완료" : "임시저장 중단: \(result.message)") }
            return allow(.text(200, "ok"))
        }
        return allow(.text(404, "작업을 찾지 못했습니다."))
    }
    private func failure(_ value: String) -> NSError { NSError(domain: "NaverBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: value]) }
}

struct ChromeConnectionView: View {
    @ObservedObject var bridge = NaverBridge.shared
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Chrome 연결 · 처음 한 번").font(.title2.bold())
            Text("확장 프로그램을 새로고침한 뒤 ‘앱 연결 코드 복사’를 누르고 아래에 붙여넣으세요.")
            SecureField("앱 연결 코드", text: $code).textFieldStyle(.roundedBorder)
            Text(bridge.message).font(.caption)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Text("연결 후에는 초안의 ‘네이버 임시저장’ 버튼으로 글과 사진을 자동 전달합니다. 네이버에 로그인된 Chrome이 필요합니다.").font(.caption)
            HStack {
                Button("연결 해제") { bridge.disconnect() }.disabled(bridge.busy)
                Button("닫기") { dismiss() }
                Spacer()
                Button("연결 저장") { do { try bridge.connect(code); code = ""; error = nil } catch { self.error = error.localizedDescription } }
                    .disabled(code.isEmpty || bridge.busy).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 500)
    }
}
