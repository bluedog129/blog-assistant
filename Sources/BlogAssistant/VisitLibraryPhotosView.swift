import Photos
import SwiftUI

struct VisitLibraryPhotosView: View {
    let sourcePhotoIDs: [String]
    @ObservedObject var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [DraftPhoto] = []
    @State private var baseline: [DraftPhoto] = []
    @State private var assets: [PHAsset] = []
    @State private var sections: [PhotoDay] = []
    @State private var total = 0
    @State private var offset = 0
    @State private var date = Date()
    @State private var before: Date?
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var loading = false
    @State private var error: String?
    @State private var discard = false
    @State private var pageTask: Task<Void, Never>?
    @State private var generation = 0
    private var dirty: Bool { selected != baseline }
    private var canEdit: Bool { loaded && !loadFailed && library.canRead && !library.isLoading }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("전체 보관함에서 사진·영상 추가").font(.title2.bold())
                Spacer()
                Button("닫기") { if dirty { discard = true } else { dismiss() } }.keyboardShortcut(.cancelAction)
                Button("선택 저장") { save() }.buttonStyle(.borderedProminent).disabled(!canEdit || !dirty)
            }
            Text("원래 장소·날짜 그룹은 유지하고 이 방문의 글에 연결합니다. 같은 사진을 다른 글에서도 사용할 수 있습니다.")
                .font(.callout)
            HStack {
                DatePicker("찾을 날짜", selection: $date, displayedComponents: .date).fixedSize()
                Button("이 날짜부터 과거 보기") {
                    before = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))
                    fetch(reset: true)
                }
                Button("최신부터 전체 보기") { before = nil; fetch(reset: true) }
                Spacer()
                Text("\(assets.count) / \(total)개").font(.caption).foregroundStyle(.secondary)
            }.disabled(!canEdit)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HSplitView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(sections) { day in
                            Text(day.date?.formatted(date: .complete, time: .omitted) ?? "촬영일 없음").font(.headline)
                            ForEach(Array(day.visits.enumerated()), id: \.element.id) { index, visit in
                                Text("\(library.restaurantName(for: visit) ?? "방문 후보 \(index + 1)") · \(visit.start?.formatted(date: .omitted, time: .shortened) ?? "시간 없음") · \(visit.assets.count)개")
                                    .font(.caption).foregroundStyle(.secondary)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 230), spacing: 12)], spacing: 12) {
                                    ForEach(visit.assets, id: \.localIdentifier) { asset in
                                        VStack(alignment: .leading, spacing: 6) {
                                            PhotoThumbnail(asset: asset, manager: library.imageManager)
                                            if sourcePhotoIDs.contains(asset.localIdentifier) {
                                                Label("이번 방문 사진", systemImage: "checkmark.circle.fill").font(.caption)
                                            } else {
                                                Toggle(selected.contains { $0.id == asset.localIdentifier } ? "선택됨" : "선택", isOn: Binding(
                                                    get: { selected.contains { $0.id == asset.localIdentifier } },
                                                    set: { toggle(asset, selected: $0) }))
                                                    .toggleStyle(.checkbox).disabled(!canEdit)
                                            }
                                        }
                                    }
                                }
                            }
                            Divider()
                        }
                        if loading { ProgressView("보관함 불러오는 중…") }
                        else if offset < total {
                            Button("이전 사진·영상 \(LibraryPhotoPaging.size)개 더 보기") { fetch(reset: false) }.disabled(!canEdit)
                        } else if assets.isEmpty { Text("표시할 사진·영상이 없습니다.").foregroundStyle(.secondary) }
                    }.padding(.trailing, 12)
                }.frame(minWidth: 440)
                VStack(alignment: .leading, spacing: 10) {
                    Text("추가 선택 \(selected.count)개").font(.headline)
                    Text("여기서는 사진·영상만 선택합니다. 정리 완료 후 블로그 초안에서 설명을 입력하세요.").font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(selected) { photo in
                                VStack(alignment: .leading, spacing: 6) {
                                    if let asset = library.assets(for: [photo.id]).first {
                                        PhotoThumbnail(asset: asset, manager: library.imageManager).frame(maxWidth: 180)
                                        Text(asset.creationDate?.formatted(date: .numeric, time: .shortened) ?? "촬영일 없음").font(.caption)
                                    } else { Text("사용할 수 없는 사진·영상 · 제외 후 저장하세요.").font(.caption).foregroundStyle(.orange) }
                                    Button("선택 제외") { selected.removeAll { $0.id == photo.id } }
                                    Divider()
                                }.disabled(!canEdit)
                            }
                        }
                    }
                }.padding(.leading, 12).frame(minWidth: 230, idealWidth: 260, maxWidth: 310)
            }
        }.padding(24).frame(minWidth: 860, idealWidth: 1050, minHeight: 620, idealHeight: 760)
        .task(id: "\(library.photoRevision)-\(library.canRead)-\(library.isLoading)") {
            if !loaded {
                do { selected = try VisitPhotoSelectionStore().load(sourcePhotoIDs: sourcePhotoIDs); baseline = selected }
                catch { loadFailed = true; self.error = "추가 사진 기록을 읽지 못했습니다. 기존 자료 보호를 위해 저장을 중단했습니다." }
                loaded = true
            }
            fetch(reset: true)
        }
        .onDisappear { pageTask?.cancel() }
        .interactiveDismissDisabled(dirty)
        .confirmationDialog("사진 선택 변경을 저장할까요?", isPresented: $discard, titleVisibility: .visible) {
            Button("저장하고 닫기") { save() }
            Button("변경 버리고 닫기", role: .destructive) { dismiss() }
            Button("계속 선택", role: .cancel) { }
        }
    }

    private func toggle(_ asset: PHAsset, selected value: Bool) {
        guard canEdit, !sourcePhotoIDs.contains(asset.localIdentifier) else { return }
        if !value { selected.removeAll { $0.id == asset.localIdentifier }; return }
        guard !selected.contains(where: { $0.id == asset.localIdentifier }) else { return }
        let sourceDays = Set(library.assets(for: sourcePhotoIDs).compactMap(\.creationDate).map { Calendar.current.startOfDay(for: $0) })
        let differentDate = asset.creationDate.flatMap { sourceDays.contains(Calendar.current.startOfDay(for: $0)) ? nil : $0 }
        selected.append(DraftPhoto(id: asset.localIdentifier, previousVisitDate: differentDate, mediaType: asset.mediaType == .video ? "video" : nil))
    }
    private func fetch(reset: Bool) {
        if !reset && loading { return }
        pageTask?.cancel(); generation += 1
        let expected = generation
        if reset { assets = []; sections = []; offset = 0; total = 0; if !loadFailed { error = nil } }
        guard library.canRead, !library.isLoading else { loading = false; return }
        loading = true
        let start = offset, cutoff = before
        pageTask = Task { @MainActor in
            defer { if generation == expected { loading = false } }
            do {
                let page = try await library.libraryPhotos(offset: start, before: cutoff)
                guard !Task.isCancelled, generation == expected else { return }
                var seen = Set(assets.map(\.localIdentifier))
                assets += page.assets.filter { seen.insert($0.localIdentifier).inserted }
                sections = library.browsingDays(for: assets)
                offset = start + page.assets.count; total = page.total
            } catch {
                guard !Task.isCancelled, generation == expected else { return }
                self.error = error.localizedDescription
            }
        }
    }
    private func save() {
        guard canEdit, Set(library.assets(for: sourcePhotoIDs).map(\.localIdentifier)) == Set(sourcePhotoIDs),
              Set(library.assets(for: selected.map(\.id)).map(\.localIdentifier)) == Set(selected.map(\.id)) else {
            error = "사진 권한·방문 구성이 바뀌었거나 사용할 수 없는 사진이 있습니다. 선택 목록을 확인하세요."
            return
        }
        do { try VisitPhotoSelectionStore().save(selected, sourcePhotoIDs: sourcePhotoIDs); baseline = selected; dismiss() }
        catch { self.error = "사진 선택을 저장하지 못했습니다: \(error.localizedDescription)" }
    }
}
