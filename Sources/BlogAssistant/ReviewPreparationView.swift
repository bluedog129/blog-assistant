import AppKit
import SwiftUI

struct ReviewPreparationView: View {
    let visitID: String
    @ObservedObject var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var review = VisitReview()
    @State private var baseline = VisitReview()
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var existing: [VisitReview] = []
    @State private var needsConfirmation = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var closeConfirmation = false
    @State private var draftVisible = false

    private var visit: PhotoVisit? { library.days.flatMap(\.visits).first { $0.id == visitID } }
    private var dirty: Bool { loaded && review != baseline }
    private var canSave: Bool {
        guard let visit else { return false }
        return loaded && !loadFailed && library.canRead && !library.isLoading && library.isOrganized(visit) &&
        library.restaurantName(for: visit) == review.restaurantName &&
        Set(visit.assets.map(\.localIdentifier)) == Set(review.photoIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("후기 작성 준비").font(.title2.bold())
                    Text(review.restaurantName).font(.headline)
                }
                Spacer()
                Button("블로그 초안") { draftVisible = true }
                    .disabled(!canSave || dirty || needsConfirmation || !review.isReady)
                Button("저장") { save() }.buttonStyle(.borderedProminent)
                    .disabled(!canSave || (!dirty && !needsConfirmation))
                    .keyboardShortcut("s", modifiers: .command)
                Button("닫기") {
                    if dirty { closeConfirmation = true } else { dismiss() }
                }.keyboardShortcut(.cancelAction)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.caption) }
            if !canSave && loaded && !loadFailed {
                Text("사진 보관함을 불러오는 중이거나 방문 정보가 변경됐습니다. 입력 내용은 화면에 유지되며, 방문이 일치할 때 저장할 수 있습니다.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if needsConfirmation {
                Text(existing.count > 1 ? "병합한 방문에 여러 후기 정보가 있습니다. 참고할 정보를 선택하거나 새로 입력한 뒤 저장하세요." : "사진 그룹 또는 음식점명이 변경됐습니다. 기존 입력을 확인한 뒤 저장하세요.")
                    .font(.caption).foregroundStyle(.orange)
                if existing.count > 1 {
                    Menu("기존 후기 정보 가져오기") {
                        ForEach(existing) { record in
                            Button("\(record.restaurantName) · \(record.menus.count)개 메뉴") { importRecord(record) }
                        }
                    }
                    Text("저장하면 이 방문의 기존 후기 정보가 현재 입력 내용으로 대체됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GroupBox("식당 정보") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("방문일")
                                    DatePicker("방문일", selection: Binding(
                                        get: { review.visitDate ?? Date() }, set: { review.visitDate = $0 }), displayedComponents: .date)
                                        .labelsHidden()
                                    if review.visitDate == nil {
                                        Button("오늘로 지정") { review.visitDate = Date() }
                                        Text("날짜를 선택하세요").font(.caption).foregroundStyle(.orange)
                                    }
                                    Spacer()
                                }
                                Text("방문 계기 (선택)").font(.headline)
                                Text("예: 문토 모임으로 방문했어요 / 친구 추천으로 방문했어요. 입력한 내용은 초안 도입부에 반영됩니다.")
                                    .font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: $review.visitBackground).frame(minHeight: 65)
                                    .border(Color.secondary.opacity(0.25)).accessibilityLabel("방문 계기")
                                Button { searchRestaurant() } label: { Label("네이버에서 검색", systemImage: "magnifyingglass") }
                                Text("영업정보 (선택)").font(.headline)
                                Text("영업시간·브레이크타임·휴무·라스트오더 등을 찾아 한 번에 붙여넣으세요.")
                                    .font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: $review.businessInfo).frame(minHeight: 110)
                                    .border(Color.secondary.opacity(0.25))
                                    .accessibilityLabel("영업정보")
                                Text("웨이팅·예약 메모 (선택)").font(.headline)
                                TextEditor(text: $review.waitingNote).frame(minHeight: 65)
                                    .border(Color.secondary.opacity(0.25)).accessibilityLabel("웨이팅 예약 메모")
                            }.padding(8)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("먹은 메뉴와 감상").font(.headline)
                                Spacer()
                                Button("메뉴 추가") { review.menus.append(ReviewMenu()) }
                            }
                            Text("메뉴명과 실제 감상은 필수, 가격은 선택입니다. 중간에도 저장하고 나중에 이어 쓸 수 있습니다.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach($review.menus) { $menu in
                                GroupBox {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            TextField("메뉴명", text: $menu.name).textFieldStyle(.roundedBorder)
                                            Button("메뉴 삭제", role: .destructive) {
                                                review.menus.removeAll { $0.id == menu.id }
                                            }
                                        }
                                        TextField("가격 (선택, 예: 18,000원)", text: $menu.price).textFieldStyle(.roundedBorder)
                                        menuPhotos(menuID: menu.id)
                                        Text("이 메뉴에 대한 실제 감상").font(.caption)
                                        TextEditor(text: $menu.impression).frame(minHeight: 90)
                                            .border(Color.secondary.opacity(0.25)).accessibilityLabel("메뉴 감상")
                                    }.padding(8)
                                }
                            }
                        }
                    }.padding(.trailing, 12)
                }.frame(minWidth: 420)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("방문 사진 · \(visit?.assets.count ?? 0)장").font(.headline)
                        if library.canRead, let visit {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                                ForEach(visit.assets, id: \.localIdentifier) { asset in
                                    PhotoThumbnail(asset: asset, manager: library.imageManager)
                                }
                            }
                        }
                    }.padding(.leading, 12)
                }.frame(minWidth: 280)
            }.disabled(!loaded || loadFailed)
            HStack {
                Text(dirty ? "저장하지 않은 변경사항이 있습니다." : (savedMessage ?? "입력 내용은 이 Mac에 저장됩니다."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(review.isReady ? ((dirty || needsConfirmation) ? "필수 입력 완료 · 저장 필요" : "초안 생성 가능") : "입력 중 · 방문일과 메뉴명·감상을 채워주세요")
                    .font(.caption).foregroundStyle(review.isReady ? Color.green : Color.secondary)
            }
            Text("필수 정보를 저장한 뒤 블로그 초안에서 생성·수정·복사할 수 있습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 840, idealWidth: 1060, minHeight: 620, idealHeight: 760)
        .onAppear { load() }
        .sheet(isPresented: $draftVisible) { DraftView(review: review, library: library) }
        .interactiveDismissDisabled(dirty)
        .confirmationDialog("입력한 변경사항을 저장할까요?", isPresented: $closeConfirmation, titleVisibility: .visible) {
            Button("저장하고 닫기") { if save() { dismiss() } }.disabled(!canSave)
            Button("변경 버리고 닫기", role: .destructive) { dismiss() }
            Button("계속 편집", role: .cancel) { }
        }
    }

    private func trimMenuPhotos() {
        let available = Set(review.photoIDs)
        for index in review.menus.indices {
            review.menus[index].photoIDs.removeAll { !available.contains($0) }
        }
    }

    private func menuPhotos(menuID: String) -> some View {
        DisclosureGroup("메뉴 사진 · \(review.menus.first { $0.id == menuID }?.photoIDs.count ?? 0)장 (여러 장 선택 가능)") {
            Text("이 메뉴의 사진을 선택하세요. 메뉴명이 초안의 사진 설명에 자동으로 반영됩니다.")
                .font(.caption).foregroundStyle(.secondary)
            if library.canRead, let visit {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                    ForEach(visit.assets, id: \.localIdentifier) { asset in
                        VStack {
                            PhotoThumbnail(asset: asset, manager: library.imageManager)
                            Toggle("선택", isOn: Binding(
                                get: { review.menus.first { $0.id == menuID }?.photoIDs.contains(asset.localIdentifier) ?? false },
                                set: { selected in
                                    guard let index = review.menus.firstIndex(where: { $0.id == menuID }) else { return }
                                    review.menus[index].photoIDs.removeAll { $0 == asset.localIdentifier }
                                    if selected { review.menus[index].photoIDs.append(asset.localIdentifier) }
                                }))
                        }
                    }
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        guard let visit else {
            errorMessage = "방문을 조회할 수 없습니다. 목록에서 방문을 다시 선택하세요."
            loadFailed = true
            return
        }
        do {
            existing = try library.savedReviews(for: visit)
            let photoIDs = visit.assets.map(\.localIdentifier)
            let name = library.restaurantName(for: visit) ?? ""
            if existing.count == 1, let record = existing.first {
                review = record
                needsConfirmation = Set(record.photoIDs) != Set(photoIDs) || record.restaurantName != name
                if needsConfirmation { review.id = UUID().uuidString }
            } else {
                review = VisitReview()
                review.visitDate = visit.start
                needsConfirmation = !existing.isEmpty
            }
            review.photoIDs = photoIDs
            review.restaurantName = name
            trimMenuPhotos()
            baseline = review
            loaded = true
        } catch {
            errorMessage = "후기 정보를 읽지 못했습니다. 기존 데이터를 보호하기 위해 저장을 중단했습니다."
            loadFailed = true
        }
    }

    private func importRecord(_ record: VisitReview) {
        let ids = review.photoIDs
        let name = review.restaurantName
        review = record
        review.id = UUID().uuidString
        review.photoIDs = ids
        review.restaurantName = name
        trimMenuPhotos()
    }

    @discardableResult private func save() -> Bool {
        guard canSave else { return false }
        do {
            try library.saveReview(review, for: visitID)
            baseline = review
            needsConfirmation = false
            errorMessage = nil
            savedMessage = "저장 완료 · 나중에 이어서 작성할 수 있습니다."
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    private func searchRestaurant() {
        var components = URLComponents(string: "https://search.naver.com/search.naver")!
        components.queryItems = [URLQueryItem(name: "query", value: "\(review.restaurantName) 영업시간")]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}
