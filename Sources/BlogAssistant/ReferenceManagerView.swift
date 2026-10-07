import AppKit
import SwiftUI

struct ReferenceManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var saved: ReferencePacket?
    @State private var preview: ReferencePacket?
    @State private var message: String?
    @State private var errorMessage: String?
    private let store = ReferenceStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("참고 글 관리").font(.title2.bold())
                Spacer()
                Button("참고 글 붙여넣기") { paste() }.buttonStyle(.borderedProminent)
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Chrome 확장 프로그램에서 최근 맛집 글을 가져와 복사한 뒤 붙여넣으세요. 내용을 확인하고 저장하면 이후 초안의 문체 참고 자료로 사용합니다.")
                .foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.caption) }
            if let message { Text(message).foregroundStyle(.secondary).font(.caption) }
            if let packet = preview ?? saved {
                HStack {
                    Text("\(packet.blogID) · \(packet.categoryName) · \(packet.articles.count)개 글").font(.headline)
                    Spacer()
                    Text(preview == nil ? "저장된 참고 글" : "붙여넣기 미리보기 · 아직 저장 전").font(.caption).foregroundStyle(.secondary)
                }
                Text("수집 시각: \(packet.collectedAt)").font(.caption).foregroundStyle(.secondary)
                if !packet.warnings.isEmpty {
                    Text(packet.warnings.joined(separator: "\n")).font(.caption).foregroundStyle(.orange)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(packet.articles) { article in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(article.title).font(.headline)
                                    HStack {
                                        Text("\(article.publishedDate) · 사진 위치 \(article.photoCount)개").foregroundStyle(.secondary)
                                        Spacer()
                                        if let url = URL(string: article.url) { Link("원문 열기", destination: url) }
                                    }.font(.caption)
                                    Text(article.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(8)
                            }
                        }
                    }
                }
                if preview != nil {
                    HStack {
                        Button("미리보기 취소") { preview = nil }
                        Spacer()
                        Button(saved == nil ? "확인 후 저장" : "확인 후 기존 참고 글 교체") { save() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Spacer()
                Text("저장된 참고 글이 없습니다. 1개만 있어도 사용할 수 있습니다.").foregroundStyle(.secondary)
                Spacer()
            }
        }.padding(24).frame(minWidth: 700, idealWidth: 880, minHeight: 560, idealHeight: 720)
        .task {
            do { saved = try store.load() }
            catch { errorMessage = "저장된 참고 글을 읽지 못했습니다: \(error.localizedDescription)" }
        }
    }

    private func paste() {
        do {
            guard let text = NSPasteboard.general.string(forType: .string) else {
                errorMessage = "클립보드에 텍스트가 없습니다. 확장 프로그램에서 결과를 복사하세요."
                return
            }
            let packet = try ReferencePacket.parse(text)
            preview = packet
            errorMessage = nil
            message = "본문과 카테고리를 확인하세요. 저장하기 전에는 기존 참고 글이 바뀌지 않습니다."
        } catch { errorMessage = "붙여넣기 실패: \(error.localizedDescription)" }
    }

    private func save() {
        guard let preview else { return }
        do {
            try store.save(preview)
            saved = preview
            self.preview = nil
            message = "참고 글 저장 완료. 앱을 다시 열어도 유지됩니다."
            errorMessage = nil
        } catch { errorMessage = "저장 실패: \(error.localizedDescription)" }
    }
}
