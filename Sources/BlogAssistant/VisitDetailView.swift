import SwiftUI

struct VisitDetailView: View {
    let visitID: String
    @ObservedObject var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var originalName = ""
    @State private var initialized = false
    @State private var confirmDiscard = false
    @State private var activeVisitID: String?
    @State private var selectedPhotos: Set<String> = []
    @State private var destinationID = ""
    @State private var resetConfirmation = false
    @State private var operationError: String?
    private var nameDirty: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines) != originalName }

    private var visit: PhotoVisit? {
        library.days.flatMap(\.visits).first { $0.id == (activeVisitID ?? visitID) }
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
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines) == originalName && library.isOrganized(visit))
                }
                Text(name.trimmingCharacters(in: .whitespacesAndNewlines) == originalName
                     ? (originalName.isEmpty ? "이름을 입력하고 저장하세요. 빈 이름을 저장하면 기존 이름이 해제됩니다." : (library.isOrganized(visit) ? "음식점명이 저장되어 있습니다." : "일부 사진에 이름이 없습니다. 저장하면 방문 전체에 적용되어 정리 완료로 이동합니다."))
                     : "저장하지 않은 변경사항이 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if library.savedNames(for: visit).count > 1 {
                    Text("이 후보에 저장된 이름: \(library.savedNames(for: visit).joined(separator: ", ")). 이름을 저장하면 이 후보의 사진에 동일하게 적용됩니다.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("\(visit.assets.count)장 · 위치 불확실 \(visit.uncertainCount)장")
                    .font(.subheadline).foregroundStyle(.secondary)
                groupControls(visit)
                if let operationError {
                    Text(operationError).font(.caption).foregroundStyle(.red)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 16)], spacing: 16) {
                        ForEach(visit.assets, id: \.localIdentifier) { asset in
                            VStack(alignment: .leading, spacing: 8) {
                                PhotoThumbnail(asset: asset, manager: library.imageManager)
                                Toggle("사진 선택", isOn: Binding(
                                    get: { selectedPhotos.contains(asset.localIdentifier) },
                                    set: { value in
                                        if value { selectedPhotos.insert(asset.localIdentifier) }
                                        else { selectedPhotos.remove(asset.localIdentifier) }
                                    }))
                                    .toggleStyle(.checkbox)
                            }
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
        .confirmationDialog("이 날짜의 그룹을 자동 분류로 되돌릴까요?", isPresented: $resetConfirmation, titleVisibility: .visible) {
            Button("이 날짜의 수동 그룹 해제", role: .destructive) {
                if let visit { library.resetGrouping(for: visit.id) }
                dismiss()
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("현재 조회된 이 날짜 사진의 병합·분리를 해제합니다. 저장된 음식점명은 유지됩니다.")
        }
        .onChange(of: library.days.flatMap(\.visits).flatMap { $0.assets.map(\.localIdentifier) }) { _ in
            selectedPhotos.formIntersection(Set(visit?.assets.map(\.localIdentifier) ?? []))
        }
    }

    private func groupControls(_ visit: PhotoVisit) -> some View {
        let targets = library.otherVisits(onDayOf: visit.id)
        let validTarget = targets.contains { $0.id == destinationID }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(selectedPhotos.count)장 선택").font(.subheadline)
                Button("전체 선택") { selectedPhotos = Set(visit.assets.map(\.localIdentifier)) }
                Button("선택 해제") { selectedPhotos = [] }
                Spacer()
                Button("새 방문으로 분리") {
                    finish(library.split(visitID: visit.id, photoIDs: selectedPhotos))
                }.disabled(selectedPhotos.isEmpty || selectedPhotos.count >= visit.assets.count || nameDirty || library.isLoading)
            }
            HStack {
                Picker("같은 날짜의 방문", selection: $destinationID) {
                    Text("이동·병합 대상 선택").tag("")
                    ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                        Text("\(library.restaurantName(for: target) ?? "방문 후보 \(index + 1)") · \(target.start.map { $0.formatted(date: .omitted, time: .shortened) } ?? "시간 미확인") · \(target.assets.count)장")
                            .tag(target.id)
                    }
                }
                Button("선택 사진 이동") {
                    finish(library.move(visitID: visit.id, photoIDs: selectedPhotos, to: destinationID))
                }.disabled(!validTarget || selectedPhotos.isEmpty || nameDirty || library.isLoading)
                Button("방문 전체 병합") {
                    finish(library.move(visitID: visit.id, photoIDs: Set(visit.assets.map(\.localIdentifier)), to: destinationID))
                }.disabled(!validTarget || nameDirty || library.isLoading)
            }
            HStack {
                Text(nameDirty ? "음식점명 변경을 먼저 저장한 뒤 그룹을 수정하세요." : "그룹 수정은 바로 저장됩니다. 사진 앱의 원본은 변경하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("이 날짜 자동 분류로 복원") { resetConfirmation = true }
                    .font(.caption).disabled(nameDirty || library.isLoading)
            }
        }
    }

    private func finish(_ groupID: String?) {
        guard let groupID else {
            operationError = "사진 목록이 변경되어 수정하지 못했습니다. 방문과 선택 사진을 다시 확인하세요."
            return
        }
        activeVisitID = groupID
        selectedPhotos = []
        destinationID = ""
        operationError = nil
        originalName = visit.flatMap { library.restaurantName(for: $0) } ?? ""
        name = originalName
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
