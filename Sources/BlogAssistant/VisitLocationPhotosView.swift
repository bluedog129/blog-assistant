import Photos
import SwiftUI

struct VisitLocationPhotosView: View {
    let sourcePhotoIDs: [String]
    @ObservedObject var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [DraftPhoto] = []
    @State private var matches: [NearbyPhoto] = []
    @State private var referenceID = ""
    @State private var radius = 50.0
    @State private var searching = false
    @State private var completed = false
    @State private var initialSearch = true
    @State private var loadFailed = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var pendingPhoto: DraftPhoto?

    private var references: [PHAsset] {
        library.assets(for: sourcePhotoIDs).filter { LocationPhotoSearch.isValid($0.location) }.sorted {
            if $0.creationDate == $1.creationDate { return $0.localIdentifier < $1.localIdentifier }
            return ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }
    }
    private var context: String {
        "\(referenceID)-\(radius)-\(library.photoRevision)-\(library.canRead)-\(library.isLoading)"
    }
    private var canSave: Bool {
        !loadFailed && library.canRead && !library.isLoading &&
            Set(library.assets(for: sourcePhotoIDs).map(\.localIdentifier)) == Set(sourcePhotoIDs)
    }

    var body: some View {
        let taskContext = context
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("같은 위치의 다른 날짜 사진").font(.title2.bold())
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("식당명이나 후기 입력 없이 검색할 수 있습니다. 사진만 추가하며 이번 방문의 날짜·메뉴는 유지합니다.")
                .font(.callout)
            if references.isEmpty {
                Text("이번 방문 사진에 유효한 GPS가 없어 위치로 검색할 수 없습니다.")
                    .foregroundStyle(.orange)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    if let reference = references.first(where: { $0.localIdentifier == referenceID }) {
                        PhotoThumbnail(asset: reference, manager: library.imageManager).frame(width: 110)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("기준 사진", selection: $referenceID) {
                            ForEach(Array(references.enumerated()), id: \.element.localIdentifier) { index, asset in
                                Text("사진 \(index + 1) · \(asset.creationDate?.formatted(date: .numeric, time: .shortened) ?? "날짜 없음")")
                                    .tag(asset.localIdentifier)
                            }
                        }
                        Picker("검색 반경", selection: $radius) {
                            Text("30m").tag(30.0)
                            Text("50m").tag(50.0)
                            Text("100m").tag(100.0)
                        }.pickerStyle(.segmented)
                        HStack {
                            Button(searching ? "검색 중…" : "사진 찾기") { search() }
                                .buttonStyle(.borderedProminent)
                                .disabled(searching || !library.canRead || library.isLoading || !references.contains { $0.localIdentifier == referenceID })
                            if searching {
                                ProgressView().controlSize(.small)
                                Button("검색 취소") { resetSearch() }
                            }
                        }
                    }
                }
            }
            Text("주변 가게 사진도 포함될 수 있으니 촬영일·거리를 확인하고 선택하세요. 추가·제외는 바로 저장됩니다.")
                .font(.caption).foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.orange) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !selected.isEmpty {
                        Text("이 방문의 글에 사용할 다른 날짜 사진 · \(selected.count)장").font(.headline)
                        selectedPhotos
                        Divider()
                    }
                    if completed {
                        Text(matches.isEmpty ? "조건에 맞는 사진이 없습니다. 기준 사진이나 반경을 바꿔보세요." : "검색 결과 \(matches.count)장 · 선택한 사진은 아래 결과에서 숨깁니다.")
                            .font(.callout)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                        ForEach(matches.filter { match in !selected.contains { $0.id == match.id } }) { match in
                            VStack(alignment: .leading, spacing: 8) {
                                PhotoThumbnail(asset: match.asset, manager: library.imageManager)
                                Text(match.asset.creationDate?.formatted(date: .numeric, time: .omitted) ?? "촬영일 없음").font(.caption)
                                Text("기준 위치에서 약 \(Int(match.distance.rounded()))m").font(.caption).foregroundStyle(.secondary)
                                Button("사진 추가") {
                                    pendingPhoto = DraftPhoto(id: match.id, previousVisitDate: match.asset.creationDate)
                                }.disabled(!canSave)
                            }
                        }
                    }
                }
            }
        }.padding(24).frame(minWidth: 680, idealWidth: 800, minHeight: 580, idealHeight: 740)
        .onAppear { load() }
        .task(id: taskContext) {
            guard !Task.isCancelled, taskContext == context else { return }
            resetSearch()
            if initialSearch && !referenceID.isEmpty && library.canRead && !library.isLoading {
                initialSearch = false
                search()
            }
        }
        .onDisappear { searchTask?.cancel() }
        .sheet(item: $pendingPhoto) { photo in
            if let asset = library.assets(for: [photo.id]).first {
                PhotoCaptionEntry(asset: asset, manager: library.imageManager, previousVisitDate: photo.previousVisitDate) { caption in
                    guard canSave, !library.assets(for: [photo.id]).isEmpty else {
                        errorMessage = "사진을 추가할 수 없습니다. 접근 권한과 사진 목록을 확인하세요."
                        return
                    }
                    var updated = selected
                    if !updated.contains(where: { $0.id == photo.id }) {
                        updated.append(DraftPhoto(id: photo.id, caption: caption, previousVisitDate: photo.previousVisitDate))
                    }
                    save(updated)
                }
            } else {
                VStack(spacing: 12) {
                    Text("사진을 사용할 수 없습니다. 사진 접근 권한과 보관함을 확인하세요.")
                    Button("닫기") { pendingPhoto = nil }
                }.padding(24)
            }
        }
    }

    private var selectedPhotos: some View {
        let mapping = Dictionary(library.assets(for: selected.map(\.id)).map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
            ForEach(selected) { photo in
                VStack(alignment: .leading, spacing: 8) {
                    if let asset = mapping[photo.id] { PhotoThumbnail(asset: asset, manager: library.imageManager) }
                    else { Text("사진을 사용할 수 없습니다.").foregroundStyle(.orange) }
                    if let date = photo.previousVisitDate { Text(date.formatted(date: .numeric, time: .omitted)).font(.caption) }
                    Text(photo.caption).font(.caption)
                    Button("제외") { save(selected.filter { $0.id != photo.id }) }.disabled(!canSave)
                }
            }
        }
    }

    private func load() {
        do { selected = try VisitPhotoSelectionStore().load(sourcePhotoIDs: sourcePhotoIDs) }
        catch { loadFailed = true; errorMessage = "추가 사진 기록을 읽지 못했습니다. 기존 자료 보호를 위해 추가·제외를 중단했습니다." }
        referenceID = references.first?.localIdentifier ?? ""
    }
    private func save(_ photos: [DraftPhoto]) {
        guard canSave else { return }
        do {
            try VisitPhotoSelectionStore().save(photos, sourcePhotoIDs: sourcePhotoIDs)
            selected = photos
            errorMessage = nil
        } catch { errorMessage = "추가 사진을 저장하지 못했습니다: \(error.localizedDescription)" }
    }
    private func resetSearch() {
        searchTask?.cancel(); searchTask = nil
        matches = []; searching = false; completed = false
    }
    private func search() {
        resetSearch()
        guard library.canRead, !library.isLoading, references.contains(where: { $0.localIdentifier == referenceID }) else { return }
        let expectedContext = context
        let anchorID = referenceID
        let searchRadius = radius
        searching = true
        searchTask = Task { @MainActor in
            do {
                let photos = try await library.nearbyPhotos(photoIDs: sourcePhotoIDs, referenceID: anchorID, radius: searchRadius)
                guard !Task.isCancelled, expectedContext == context else { return }
                matches = photos; completed = true
            } catch {
                guard !Task.isCancelled, expectedContext == context else { return }
                errorMessage = error.localizedDescription
            }
            searching = false; searchTask = nil
        }
    }
}
