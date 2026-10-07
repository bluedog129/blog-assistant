import SwiftUI

struct VisitDetailView: View {
    let visitID: String
    @ObservedObject var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var originalName = ""
    @State private var initialized = false
    @State private var confirmDiscard = false

    private var visit: PhotoVisit? {
        library.days.flatMap(\.visits).first { $0.id == visitID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("방문 상세").font(.title2.bold())
                Spacer()
                Button("닫기") { close() }.keyboardShortcut(.cancelAction)
            }
            if let visit, library.canRead {
                if let start = visit.start, let end = visit.end {
                    Text("\(start.formatted(date: .complete, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("음식점명")
                    TextField("예: 정돈 성수", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { save(visit) }
                    Button("저장") { save(visit) }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines) == originalName)
                }
                Text(name.trimmingCharacters(in: .whitespacesAndNewlines) == originalName
                     ? (originalName.isEmpty ? "이름을 입력하고 저장하세요. 빈 이름을 저장하면 기존 이름이 해제됩니다." : "음식점명이 저장되어 있습니다.")
                     : "저장하지 않은 변경사항이 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if library.savedNames(for: visit).count > 1 {
                    Text("이 후보에 저장된 이름: \(library.savedNames(for: visit).joined(separator: ", ")). 이름을 저장하면 이 후보의 사진에 동일하게 적용됩니다.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("\(visit.assets.count)장 · 위치 불확실 \(visit.uncertainCount)장")
                    .font(.subheadline).foregroundStyle(.secondary)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 16)], spacing: 16) {
                        ForEach(visit.assets, id: \.localIdentifier) { asset in
                            PhotoThumbnail(asset: asset, manager: library.imageManager)
                        }
                    }
                }
            } else {
                Text("이 방문 후보를 더 이상 조회할 수 없습니다. 사진 접근 권한 또는 보관함 변경을 확인하세요.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(24).frame(minWidth: 680, idealWidth: 820, minHeight: 560, idealHeight: 680)
        .onAppear {
            guard !initialized, let visit else { return }
            originalName = library.restaurantName(for: visit) ?? ""
            name = originalName
            initialized = true
        }
        .interactiveDismissDisabled(name.trimmingCharacters(in: .whitespacesAndNewlines) != originalName)
        .confirmationDialog("저장하지 않은 음식점명 변경을 버릴까요?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("변경 버리고 닫기", role: .destructive) { dismiss() }
            Button("계속 편집", role: .cancel) { }
        }
    }

    private func save(_ visit: PhotoVisit) {
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        library.saveRestaurantName(name, for: visit)
        originalName = name
    }

    private func close() {
        if name.trimmingCharacters(in: .whitespacesAndNewlines) != originalName { confirmDiscard = true }
        else { dismiss() }
    }
}
