import AppKit
import Photos
import SwiftUI

struct DraftView: View {
    private let initialReview: VisitReview
    @State private var updatedReview: VisitReview?
    private var review: VisitReview { updatedReview ?? initialReview }
    @ObservedObject var library: PhotoLibraryStore
    @ObservedObject private var bridge = NaverBridge.shared
    @Environment(\.dismiss) private var dismiss
    @State private var references: ReferencePacket?
    @State private var referenceError: String?
    @State private var includeReferences = true
    @State private var draft: BlogDraft?
    @State private var plan = DraftPhotoPlan()
    @State private var text = ""
    @State private var baseline = ""
    @State private var photoConnectionChanged = false
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var message: String?
    @State private var closeConfirmation = false
    @State private var replacementText: String?
    @State private var replaceConfirmation = false
    @State private var preview = false
    @State private var exporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var pendingPhoto: DraftPhoto?
    @State private var chromeConnectionVisible = false
    @AppStorage("preferredDraftTemplate") private var preferredTemplate = DraftTemplate.record.rawValue
    @State private var template = DraftTemplate.record
    @State private var baselineTemplate = DraftTemplate.record

    init(review: VisitReview, library: PhotoLibraryStore) {
        initialReview = review
        self.library = library
    }
    private var dirty: Bool { text != baseline || photoConnectionChanged || template != baselineTemplate }
    private var sourceReview: VisitReview { draft?.sourceReview ?? plan.requestReview ?? review }
    private var assets: [PHAsset] {
        library.assets(for: review.photoIDs).sorted {
            if $0.creationDate == $1.creationDate { return $0.localIdentifier < $1.localIdentifier }
            return ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }
    }
    private var assetMap: [String: PHAsset] {
        let storedIDs = plan.selected.map(\.id) + displayPhotos.map(\.id) + (pendingPhoto.map { [$0.id] } ?? [])
        let fetched = library.assets(for: review.photoIDs + storedIDs)
        return Dictionary(fetched.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var displayPhotos: [DraftPhoto] { draft?.photos ?? plan.requestPhotos ?? plan.selected }
    private var photoSelectionChanged: Bool { !text.isEmpty && displayPhotos != plan.selected }
    private var prompt: String { (try? DraftPrompt.make(review: review, references: includeReferences ? references : nil, photos: plan.selected, template: template)) ?? "" }
    private var canCopyRequest: Bool {
        let mapping = assetMap
        return loaded && !loadFailed && review.isReady && (!includeReferences || referenceError == nil) &&
        plan.selected.allSatisfy { mapping[$0.id] != nil && !$0.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("블로그 초안").font(.title2.bold())
                    Text(review.restaurantName).font(.headline)
                }
                Spacer()
                Button("닫기") {
                    if dirty { closeConfirmation = true } else { dismiss() }
                }.keyboardShortcut(.cancelAction).disabled(exporting)
            }
            Text("① 사진 준비 → ② 작성 요청 복사 → ChatGPT에서 생성 → ③ 초안 붙여넣기").font(.callout)
            HSplitView {
                photoPreparation.frame(minWidth: 280, idealWidth: 340)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("참고 글 문체 사용 (\(references?.articles.count ?? 0)개)", isOn: $includeReferences)
                    Picker("글 양식", selection: $template) {
                        ForEach(DraftTemplate.allCases) { Text($0.name).tag($0) }
                    }.disabled(exporting || bridge.busy)
                    Text(template == .record ? "메뉴명 19·볼드 / 본문 16 / 남색 소제목 / 회색 가격. 핵심 구절은 **볼드**, 소제목은 ## 메뉴명으로 표시하세요. 영업정보는 [영업정보] 줄에 자동 표시합니다." : "서식 표시를 제외한 기본 텍스트로 미리보기·전달합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let referenceError, includeReferences { Text(referenceError).font(.caption).foregroundStyle(.red) }
                    DisclosureGroup("ChatGPT에 붙여넣을 내용 확인 · \(prompt.count)자") {
                        ScrollView { Text(prompt).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: 140)
                    }
                    HStack {
                        Button("작성 요청 복사") { copyRequest() }.buttonStyle(.borderedProminent).disabled(!canCopyRequest || exporting)
                        Link("ChatGPT 열기", destination: URL(string: "https://chatgpt.com/")!)
                        Spacer()
                        Button("초안 붙여넣기") { pasteDraft() }.disabled(!loaded || loadFailed || exporting)
                    }
                    Text("앱은 AI를 직접 호출하지 않습니다. 복사한 내용을 ChatGPT에 붙여넣고 결과를 가져오세요. 사진 파일은 작성 요청에 포함되지 않습니다.").font(.caption).foregroundStyle(.secondary)
                    if plan.selected.contains(where: { $0.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                        Text("작성 요청을 복사하려면 선택한 사진의 설명을 입력하세요.").font(.caption).foregroundStyle(.orange)
                    }
                    if let draft, draft.sourceReview != review {
                        Text("초안 작성 후 방문 정보가 바뀌었습니다. 작성 요청을 다시 복사해 생성하거나 글을 수정하세요.").font(.caption).foregroundStyle(.orange)
                    }
                    if let requested = plan.requestPhotos, requested != plan.selected {
                        Text("사진 구성이 마지막 작성 요청과 다릅니다. 기존 초안의 사진 번호는 유지합니다. 새 구성을 반영하려면 작성 요청을 다시 복사하고 새 초안을 가져오세요.").font(.caption).foregroundStyle(.orange)
                    }
                    if let linked = draft?.photos, linked != plan.selected, plan.requestPhotos == plan.selected {
                        Text("현재 초안은 이전 사진 구성에 연결되어 있습니다. 새 작성 요청으로 생성한 결과를 붙여넣으면 새 사진 구성으로 연결됩니다.").font(.caption).foregroundStyle(.orange)
                    }
                    if photoSelectionChanged {
                        HStack {
                            Button("현재 선택한 사진을 초안에 연결") { connectCurrentPhotos() }
                                .disabled(loadFailed || exporting || plan.selected.contains { assetMap[$0.id] == nil })
                            Text("기존 사진의 연결을 유지하고 번호를 갱신합니다. 새 사진 표시는 본문 끝에 추가합니다.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let message { Text(message).font(.caption).textSelection(.enabled) }
                    HStack {
                        Picker("보기", selection: $preview) {
                            Text("글 편집").tag(false)
                            Text("서식·사진 미리보기").tag(true)
                        }.pickerStyle(.segmented).frame(width: 260)
                        Spacer()
                        Button("초안 복사") { copy(DraftFormatting.plainText(text, review: sourceReview)); message = "사진 표시를 포함한 기본 텍스트를 복사했습니다. 글 서식은 네이버 임시저장으로 자동 적용합니다." }.disabled(text.isEmpty)
                        Button("초안 저장") { _ = save() }.disabled(!dirty || loadFailed || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .keyboardShortcut("s", modifiers: .command)
                    }
                    if preview { draftPreview } else {
                        TextEditor(text: $text).border(Color.secondary.opacity(0.25))
                            .disabled(!loaded || loadFailed).accessibilityLabel("블로그 초안 편집")
                    }
                    if !text.isEmpty {
                        ForEach(DraftLayout.warnings(text: text, photoCount: displayPhotos.count), id: \.self) {
                            Text($0).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    HStack {
                        Text(dirty ? "저장하지 않은 변경사항이 있습니다." : "붙여넣은 초안은 확인 후 저장하세요.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(bridge.busy ? "네이버 입력 중…" : "네이버 임시저장") { sendToNaver() }
                            .buttonStyle(.borderedProminent)
                            .disabled(exporting || bridge.busy || text.isEmpty || dirty || photoSelectionChanged || loadFailed || !DraftLayout.warnings(text: text, photoCount: displayPhotos.count).isEmpty || !library.canRead)
                        if bridge.busy {
                            Button("작업 중단") { bridge.cancelCurrentJob() }
                        }
                        Button(exporting ? "사진 내보내는 중…" : "사진만 내보내기") { exportPhotos() }
                            .disabled(exporting || photoSelectionChanged || displayPhotos.isEmpty || !library.canRead)
                    }
                    Text(bridge.message).font(.caption).foregroundStyle(.secondary)
                    Text("사진 표시는 별도 줄에 [사진 1] 형식으로 입력하세요. 네이버 임시저장은 이 위치에 사진을 넣고 임시저장까지 진행합니다.").font(.caption).foregroundStyle(.secondary)
                    if photoSelectionChanged {
                        Text("현재 선택 \(plan.selected.count)장 · 초안에 연결 \(displayPhotos.count)장. 새 작성 요청으로 초안을 생성하거나 위의 사진 연결 버튼을 누른 뒤 저장하세요.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.padding(.leading, 12).frame(minWidth: 570)
            }
        }.padding(24).frame(minWidth: 980, idealWidth: 1180, minHeight: 700, idealHeight: 840)
        .onAppear { if loaded { refreshReviewPhotos() } else { load() } }
        .onChange(of: library.reviewRevision) { _ in if loaded { refreshReviewPhotos() } }
        .onChange(of: initialReview) { _ in if loaded { refreshReviewPhotos() } }
        .onChange(of: text) { _ in repairPhotoConnectionIfNeeded() }
        .onChange(of: template) { value in if loaded { preferredTemplate = value.rawValue } }
        .sheet(isPresented: $chromeConnectionVisible) { ChromeConnectionView() }
        .sheet(item: $pendingPhoto) { photo in
            if let asset = assetMap[photo.id] {
                PhotoCaptionEntry(asset: asset, manager: library.imageManager, previousVisitDate: photo.previousVisitDate) { caption in
                    guard library.canRead, assetMap[photo.id] != nil,
                          !plan.selected.contains(where: { $0.id == photo.id }) else {
                        message = "사진을 추가할 수 없습니다. 사진 권한과 방문 구성을 확인하세요."
                        return
                    }
                    plan.selected.append(DraftPhoto(id: photo.id, caption: caption, previousVisitDate: photo.previousVisitDate))
                    persistPlan()
                }
            } else {
                VStack(spacing: 16) {
                    Text("사진을 사용할 수 없습니다. 권한과 방문 구성을 확인하세요.")
                    Button("닫기") { pendingPhoto = nil }
                }.padding(24)
            }
        }
        .onDisappear { exportTask?.cancel() }
        .interactiveDismissDisabled(dirty || exporting)
        .confirmationDialog("기존 초안을 교체할까요? 현재 초안을 먼저 저장하면 이전 버전으로 보관됩니다.", isPresented: $replaceConfirmation, titleVisibility: .visible) {
            Button("현재 초안 저장 후 가져오기") { if save(), let replacementText { applyPaste(replacementText) } }
            Button("현재 수정 버리고 가져오기", role: .destructive) { if let replacementText { applyPaste(replacementText) } }
            Button("취소", role: .cancel) { replacementText = nil }
        }
        .confirmationDialog("초안 수정을 저장할까요?", isPresented: $closeConfirmation, titleVisibility: .visible) {
            Button("저장하고 닫기") { if save() { dismiss() } }
            Button("수정 버리고 닫기", role: .destructive) { dismiss() }
            Button("계속 편집", role: .cancel) { }
        }
    }

    private var photoPreparation: some View {
        let mapping = assetMap
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("① 사진 선택 · \(plan.selected.count)장").font(.headline)
                Text("후기에서 저장한 메뉴 사진의 추가·교체·해제와 메뉴명을 반영합니다. 전경·반찬 등 직접 추가한 사진과 직접 편집한 설명은 유지합니다. 선택 순서가 사진 번호입니다.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("후기 사진 다시 반영") { refreshReviewPhotos(includeExcluded: true) }
                    Button("선택 해제") { plan.selected = []; persistPlan() }
                }.disabled(!loaded || loadFailed || exporting || !library.canRead)
                ForEach(Array(plan.selected.enumerated()), id: \.element.id) { index, photo in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("사진 \(index + 1)").font(.headline)
                                Spacer()
                                Button("↑") { movePhoto(index, by: -1) }.disabled(index == 0).accessibilityLabel("사진 위로 이동")
                                Button("↓") { movePhoto(index, by: 1) }.disabled(index == plan.selected.count - 1).accessibilityLabel("사진 아래로 이동")
                                Button("제외") { plan.selected.removeAll { $0.id == photo.id }; persistPlan() }
                            }
                            if let asset = mapping[photo.id] { PhotoThumbnail(asset: asset, manager: library.imageManager).frame(maxWidth: 210) }
                            else { Text("사진을 사용할 수 없습니다. 권한 또는 방문 구성을 확인하세요.").font(.caption).foregroundStyle(.orange) }
                            if let date = photo.previousVisitDate {
                                Text("다른 날짜 · \(date.formatted(date: .numeric, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            TextField("사진 설명 (예: 돈코츠 라멘)", text: Binding(
                                get: { plan.selected.first { $0.id == photo.id }?.caption ?? "" },
                                set: { value in
                                    if let position = plan.selected.firstIndex(where: { $0.id == photo.id }) {
                                        plan.selected[position].caption = value; persistPlan()
                                    }
                                })).textFieldStyle(.roundedBorder)
                        }.padding(4)
                    }
                }.disabled(!loaded || loadFailed || exporting)
                Text("선택하지 않은 사진").font(.headline)
                ForEach(assets.filter { asset in !plan.selected.contains { $0.id == asset.localIdentifier } }, id: \.localIdentifier) { asset in
                    HStack {
                        PhotoThumbnail(asset: asset, manager: library.imageManager).frame(width: 110)
                        Button("추가") { pendingPhoto = DraftPhoto(id: asset.localIdentifier) }
                    }.disabled(!loaded || loadFailed || exporting)
                }
                Divider()
                Text("다른 날짜 사진은 방문 상세의 GPS 검색에서 선택할 수 있습니다. 선택한 사진은 초안에 이어집니다.").font(.caption).foregroundStyle(.secondary)
            }.padding(.trailing, 12)
        }
    }
    private var draftPreview: some View {
        let mapping = assetMap
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(DraftLayout.blocks(DraftFormatting.expandBusinessInfo(text, review: sourceReview))) { block in
                    if let content = block.text { formattedText(content, firstBlock: block.id == 0) }
                    if let number = block.photoNumber {
                        if number > 0, number <= displayPhotos.count {
                            let photo = displayPhotos[number - 1]
                            if let asset = mapping[photo.id] {
                                PhotoThumbnail(asset: asset, manager: library.imageManager, showFullImage: true).frame(maxWidth: 420)
                                Text("사진 \(number) · \(photo.caption)").font(.caption).foregroundStyle(.secondary)
                                if let date = photo.previousVisitDate {
                                    Text("다른 날짜 · \(date.formatted(date: .numeric, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } else { Text("[사진 \(number)] 사진을 사용할 수 없습니다.").foregroundStyle(.orange) }
                        } else { Text("[사진 \(number)] 연결할 사진이 없습니다.").foregroundStyle(.orange) }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }.border(Color.secondary.opacity(0.25))
    }
    private func formattedText(_ content: String, firstBlock: Bool) -> some View {
        let paragraphs = DraftFormatting.paragraphs(content, menus: sourceReview.menus)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                if paragraph.text.isEmpty { Spacer().frame(height: 14) }
                else if firstBlock && index == 0 {
                    Text(DraftFormatting.title(paragraph.text)).font(.title2.bold()).padding(.bottom, 12)
                } else {
                    let color: Color = paragraph.color == "#003960" ? Color(red: 0, green: 57 / 255, blue: 96 / 255) : (paragraph.role == "price" ? .secondary : .primary)
                    paragraph.runs.reduce(Text("")) { value, run in
                        value + Text(run.text).font(.system(size: template == .record ? paragraph.size : 16, weight: template == .record && run.bold ? .bold : .regular))
                    }.foregroundStyle(template == .record ? color : .primary)
                        .lineSpacing(5).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.frame(maxWidth: 570, alignment: .leading)
    }
    private func load() {
        guard !loaded else { return }
        do {
            updatedReview = try ReviewStore().load(id: initialReview.id) ?? initialReview
            draft = try DraftStore().latest(reviewID: review.id)
            plan = try DraftPhotoPlanStore().load(reviewID: review.id)
            let previousSelection = plan.selected
            let added = plan.syncMenuPhotos(review: review)
            let visitPhotos = try VisitPhotoSelectionStore().load(sourcePhotoIDs: review.photoIDs)
            plan.syncVisitPhotos(visitPhotos)
            try DraftPhotoPlanStore().save(plan, reviewID: review.id)
            text = draft?.text ?? ""; baseline = text
            template = draft?.template ?? DraftTemplate(rawValue: preferredTemplate) ?? .record
            baselineTemplate = template
            if previousSelection != plan.selected, draft != nil || plan.requestPhotos != nil {
                message = "후기의 최신 사진 연결을 반영했습니다(새 사진 \(added)장). 기존 초안은 새 작성 요청이나 사진 연결 후 저장으로 반영할 수 있습니다."
            }
        } catch { loadFailed = true; message = "기존 초안 또는 사진 구성을 읽지 못했습니다. 기존 자료 보호를 위해 저장·가져오기를 중단했습니다." }
        do { references = try ReferenceStore().load() }
        catch { referenceError = "참고 글을 읽지 못했습니다. 참고 글 관리에서 확인하거나 문체 사용을 끄세요." }
        loaded = true
        repairPhotoConnectionIfNeeded()
    }
    private func repairPhotoConnectionIfNeeded() {
        guard loaded, !loadFailed, !exporting,
              let repaired = draft?.repairingPhotoConnection(text: text, plan: plan) else { return }
        draft = repaired
        draft?.template = template
        photoConnectionChanged = true
        message = "본문의 사진 번호가 마지막 작성 요청과 일치해 사진 \(repaired.photos?.count ?? 0)장을 연결했습니다. 글은 유지했습니다. 미리보기 확인 후 초안 저장을 누르세요."
    }
    private func refreshReviewPhotos(includeExcluded: Bool = false) {
        guard loaded, !loadFailed, !exporting else { return }
        do {
            guard let latest = try ReviewStore().load(id: initialReview.id) else {
                message = "후기 정보가 변경되어 이전 방문을 찾을 수 없습니다. 방문 목록에서 다시 열어주세요."
                return
            }
            var updatedPlan = plan
            updatedPlan.syncMenuPhotos(review: latest, includeExcluded: includeExcluded)
            try DraftPhotoPlanStore().save(updatedPlan, reviewID: latest.id)
            updatedReview = latest
            plan = updatedPlan
            message = "후기에서 저장한 최신 사진 연결을 반영했습니다. 선택 사진 \(plan.selected.count)장입니다."
        } catch { message = "후기 사진을 갱신하지 못했습니다: \(error.localizedDescription)" }
    }
    private func persistPlan() {
        guard !loadFailed else { return }
        do { try DraftPhotoPlanStore().save(plan, reviewID: review.id) }
        catch { message = "사진 구성을 저장하지 못했습니다: \(error.localizedDescription)" }
    }
    private func movePhoto(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard plan.selected.indices.contains(destination) else { return }
        plan.selected.swapAt(index, destination); persistPlan()
    }
    private func copy(_ value: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
    }
    private func copyRequest() {
        guard canCopyRequest else { return }
        var snapshot = plan
        snapshot.syncMenuPhotos(review: review)
        snapshot.requestPhotos = snapshot.selected
        snapshot.requestReview = review
        snapshot.referencePostIDs = includeReferences ? references?.articles.map(\.postID) ?? [] : []
        do {
            let request = try DraftPrompt.make(review: review, references: includeReferences ? references : nil, photos: snapshot.selected, template: template)
            try DraftPhotoPlanStore().save(snapshot, reviewID: review.id)
            plan = snapshot; copy(request)
            message = "사진 \(snapshot.selected.count)장을 포함한 작성 요청을 복사했습니다. ChatGPT에 붙여넣고 생성된 글을 가져오세요."
        } catch { message = "작성 요청의 사진 구성을 저장하지 못했습니다: \(error.localizedDescription)" }
    }
    private func pasteDraft() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "ChatGPT가 작성한 글을 먼저 복사하세요."; return
        }
        guard value.utf8.count <= 1_000_000 else { message = "붙여넣을 내용이 너무 큽니다."; return }
        guard value != prompt, !value.contains("문체 참고 글 JSON:") else { message = "작성 요청이 아닌 ChatGPT의 생성 결과를 복사하세요."; return }
        if !text.isEmpty { replacementText = value; replaceConfirmation = true }
        else { applyPaste(value) }
    }
    private func applyPaste(_ value: String) {
        let now = Date()
        draft = BlogDraft(reviewID: review.id, sourceReview: plan.requestReview ?? review,
                          referencePostIDs: plan.referencePostIDs ?? [], model: "ChatGPT 수동 가져오기",
                          createdAt: now, updatedAt: now, text: value, photos: plan.requestPhotos ?? plan.selected)
        text = value; baseline = ""; replacementText = nil; photoConnectionChanged = false
        draft?.template = template
        message = "초안을 가져왔습니다. 사진 미리보기에서 확인한 뒤 저장하세요."
    }
    @discardableResult private func save() -> Bool {
        guard !loadFailed else { return false }
        repairPhotoConnectionIfNeeded()
        let now = Date()
        var value = draft ?? BlogDraft(reviewID: review.id, sourceReview: plan.requestReview ?? review,
                                      referencePostIDs: plan.referencePostIDs ?? [], model: "직접 작성",
                                      createdAt: now, updatedAt: now, text: text, photos: plan.requestPhotos ?? plan.selected)
        value.text = text; value.updatedAt = now; value.template = template
        do {
            try DraftStore().save(value)
            draft = value; baseline = text; baselineTemplate = template; photoConnectionChanged = false; message = "초안을 저장했습니다."
            return true
        } catch { message = "초안을 저장하지 못했습니다: \(error.localizedDescription)"; return false }
    }
    private func connectCurrentPhotos() {
        guard !loadFailed else { return }
        let adoptingNumbers = !DraftLayout.warnings(text: text, photoCount: displayPhotos.count).isEmpty &&
            Set(plan.selected.map(\.id)).count == plan.selected.count &&
            DraftLayout.warnings(text: text, photoCount: plan.selected.count).isEmpty
        let updatedText: String
        do {
            if adoptingNumbers {
                // An already regenerated text uses the new numbering; remapping it
                // as an older draft would either fail or replace the wrong photos.
                updatedText = text
            } else {
                updatedText = try DraftLayout.reconnect(text: text, from: displayPhotos, to: plan.selected)
            }
        }
        catch { message = error.localizedDescription; return }
        let now = Date()
        var value = draft ?? BlogDraft(reviewID: review.id, sourceReview: review,
                                      referencePostIDs: plan.referencePostIDs ?? [], model: "직접 작성",
                                      createdAt: now, updatedAt: now, text: text)
        value.photos = plan.selected
        value.text = updatedText
        draft = value
        text = updatedText
        photoConnectionChanged = true
        preview = true
        message = adoptingNumbers ? "본문의 사진 번호에 현재 선택한 \(plan.selected.count)장을 연결했습니다. 글과 사진 표시의 위치는 유지했습니다. 미리보기 확인 후 초안 저장을 누르세요." : "현재 선택한 \(plan.selected.count)장을 연결했습니다. 새 사진 표시는 본문 끝(해시태그 앞)에 추가했습니다. 사진 위치와 설명을 확인한 뒤 초안 저장을 누르세요."
    }
    private func exportPhotos(includePost: Bool = false) {
        guard !photoSelectionChanged else {
            message = "현재 선택한 사진을 초안에 연결한 뒤 내보내세요. 이전 사진 구성은 내보내지 않았습니다."
            return
        }
        if includePost {
            do { _ = try NaverPostPacket.make(text: text, photos: displayPhotos, filenames: displayPhotos.map { $0.id }, template: template, review: sourceReview) }
            catch { message = error.localizedDescription; return }
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "사진 내보내기"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let photos = displayPhotos
        let mapping = assetMap
        let postText = includePost ? text : nil
        exporting = true
        exportTask = Task { @MainActor in
            defer { exporting = false; exportTask = nil }
            do {
                let result = try await DraftPhotoExporter.export(photos, assets: mapping, folder: folder, postText: postText, template: template, review: sourceReview)
                message = includePost ? "임시저장용 묶음을 내보냈습니다. Chrome 확장 프로그램의 네이버 임시저장에서 이 폴더의 파일들을 선택하세요." : "사진 \(photos.count)장을 내보냈습니다: \(result.lastPathComponent)"
                NSWorkspace.shared.open(result)
            } catch { message = "사진 내보내기 실패: \(error.localizedDescription)" }
        }
    }
    private func sendToNaver() {
        guard !photoSelectionChanged else {
            message = "현재 선택한 사진과 초안의 사진 구성이 다릅니다. 새 초안을 가져오거나 현재 선택한 사진을 초안에 연결한 뒤 저장하세요."
            return
        }
        guard bridge.ready else { chromeConnectionVisible = true; return }
        let photos = displayPhotos
        let mapping = assetMap
        let content = text
        do { _ = try NaverPostPacket.make(text: content, photos: photos, filenames: photos.map(\.id), template: template, review: sourceReview) }
        catch { message = error.localizedDescription; return }
        exporting = true
        exportTask = Task { @MainActor in
            defer { exporting = false; exportTask = nil }
            var prepared: URL?
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NaverBridge", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let result = try await DraftPhotoExporter.export(photos, assets: mapping, folder: folder, postText: content, template: template, review: sourceReview)
                prepared = result
                try Task.checkCancellation()
                try await bridge.submit(folder: result)
                message = "Chrome에서 처리 중입니다. 아래 진행 상태를 확인하세요."
            } catch {
                if let prepared { try? FileManager.default.removeItem(at: prepared) }
                message = "네이버 전달 실패: \(error.localizedDescription)"
            }
        }
    }
}
