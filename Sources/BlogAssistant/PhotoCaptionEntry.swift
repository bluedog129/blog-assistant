import Photos
import SwiftUI

struct PhotoCaptionEntry: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @FocusState private var captionFocused: Bool

    private var trimmedCaption: String { caption.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("어떤 사진인가요?").font(.title2.bold())
            PhotoThumbnail(asset: asset, manager: manager, showFullImage: true)
                .frame(maxWidth: 360, maxHeight: 330)
            TextField("예: 가게 전경, 돈코츠 라멘, 기본 반찬", text: $caption)
                .textFieldStyle(.roundedBorder).focused($captionFocused)
                .onSubmit { add() }
            Text("설명은 ChatGPT 작성 요청에 포함됩니다. 본문의 [사진 번호] 위치에 이 사진을 미리 보여줍니다.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("사진 추가") { add() }.buttonStyle(.borderedProminent)
                    .disabled(trimmedCaption.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 420)
        .onAppear { captionFocused = true }
    }

    private func add() {
        guard !trimmedCaption.isEmpty else { return }
        onAdd(trimmedCaption)
        dismiss()
    }
}
