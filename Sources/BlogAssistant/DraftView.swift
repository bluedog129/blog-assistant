import AppKit
import Photos
import SwiftUI

struct DraftView: View {
    let review: VisitReview
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
    private var dirty: Bool { text != baseline || photoConnectionChanged }
    private var assets: [PHAsset] {
        guard library.canRead else { return [] }
        let ids = Set(review.photoIDs)
        return library.days.flatMap(\.visits).flatMap(\.assets).filter { ids.contains($0.localIdentifier) }
            .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
    }
    private var assetMap: [String: PHAsset] { Dictionary(assets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first }) }
    private var displayPhotos: [DraftPhoto] { draft?.photos ?? plan.requestPhotos ?? plan.selected }
    private var prompt: String { (try? DraftPrompt.make(review: review, references: includeReferences ? references : nil, photos: plan.selected)) ?? "" }
    private var canCopyRequest: Bool {
        loaded && !loadFailed && review.isReady && (!includeReferences || referenceError == nil) &&
        plan.selected.allSatisfy { assetMap[$0.id] != nil && !$0.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
                    if !text.isEmpty, !plan.selected.isEmpty, displayPhotos != plan.selected {
                        HStack {
                            Button("현재 선택한 사진을 초안에 연결") { connectCurrentPhotos() }
                                .disabled(loadFailed || exporting || plan.selected.contains { assetMap[$0.id] == nil })
                            Text("본문의 사진 1부터 왼쪽 선택 순서대로 연결합니다.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let message { Text(message).font(.caption).textSelection(.enabled) }
                    HStack {
                        Picker("보기", selection: $preview) {
                            Text("글 편집").tag(false)
                            Text("사진 미리보기").tag(true)
                        }.pickerStyle(.segmented).frame(width: 260)
                        Spacer()
                        Button("초안 복사") { copy(text); message = "사진 표시를 포함한 초안을 복사했습니다." }.disabled(text.isEmpty)
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
                        Button("네이버 임시저장") { sendToNaver() }
                            .buttonStyle(.borderedProminent)
                            .disabled(exporting || bridge.busy || text.isEmpty || dirty || loadFailed || !DraftLayout.warnings(text: text, photoCount: displayPhotos.count).isEmpty || !library.canRead)
                        Button(exporting ? "사진 내보내는 중…" : "사진만 내보내기") { exportPhotos() }
                            .disabled(exporting || displayPhotos.isEmpty || !library.canRead)
                    }
                    Text(bridge.message).font(.caption).foregroundStyle(.secondary)
                    Text("사진 표시는 별도 줄에 [사진 1] 형식으로 입력하세요. 네이버 임시저장은 이 위치에 사진을 넣고 임시저장까지 진행합니다.").font(.caption).foregroundStyle(.secondary)
                }.padding(.leading, 12).frame(minWidth: 570)
            }
        }.padding(24).frame(minWidth: 980, idealWidth: 1180, minHeight: 700, idealHeight: 840)
        .onAppear { load() }
        .sheet(isPresented: $chromeConnectionVisible) { ChromeConnectionView() }
        .sheet(item: $pendingPhoto) { photo in
            if let asset = assetMap[photo.id] {
                PhotoCaptionEntry(asset: asset, manager: library.imageManager) { caption in
                    guard library.canRead, assetMap[photo.id] != nil,
                          !plan.selected.contains(where: { $0.id == photo.id }) else {
                        message = "사진을 추가할 수 없습니다. 사진 권한과 방문 구성을 확인하세요."
                        return
                    }
                    plan.selected.append(DraftPhoto(id: photo.id, caption: caption))
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("① 사진 선택 · \(plan.selected.count)장").font(.headline)
                Text("메뉴에 연결한 사진은 메뉴명이 자동 입력됩니다. 전경·반찬 등 다른 사진은 설명을 입력해 추가하세요. 선택 순서가 사진 번호입니다.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("메뉴 사진 추가") { addMenuPhotos(); persistPlan() }
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
                            if let asset = assetMap[photo.id] { PhotoThumbnail(asset: asset, manager: library.imageManager).frame(maxWidth: 210) }
                            else { Text("사진을 사용할 수 없습니다. 권한 또는 방문 구성을 확인하세요.").font(.caption).foregroundStyle(.orange) }
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
            }.padding(.trailing, 12)
        }
    }
    private var draftPreview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(DraftLayout.blocks(text)) { block in
                    if let content = block.text { Text(content).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    if let number = block.photoNumber {
                        if number > 0, number <= displayPhotos.count {
                            let photo = displayPhotos[number - 1]
                            if let asset = assetMap[photo.id] {
                                PhotoThumbnail(asset: asset, manager: library.imageManager, showFullImage: true).frame(maxWidth: 420)
                                Text("사진 \(number) · \(photo.caption)").font(.caption).foregroundStyle(.secondary)
                            } else { Text("[사진 \(number)] 사진을 사용할 수 없습니다.").foregroundStyle(.orange) }
                        } else { Text("[사진 \(number)] 연결할 사진이 없습니다.").foregroundStyle(.orange) }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }.border(Color.secondary.opacity(0.25))
    }
    private func load() {
        guard !loaded else { return }
        do {
            draft = try DraftStore().latest(reviewID: review.id)
            plan = try DraftPhotoPlanStore().load(reviewID: review.id)
            if draft == nil && plan.selected.isEmpty && plan.requestPhotos == nil {
                addMenuPhotos()
                try DraftPhotoPlanStore().save(plan, reviewID: review.id)
            }
            text = draft?.text ?? ""; baseline = text
        } catch { loadFailed = true; message = "기존 초안 또는 사진 구성을 읽지 못했습니다. 기존 자료 보호를 위해 저장·가져오기를 중단했습니다." }
        do { references = try ReferenceStore().load() }
        catch { referenceError = "참고 글을 읽지 못했습니다. 참고 글 관리에서 확인하거나 문체 사용을 끄세요." }
        loaded = true
    }
    private func addMenuPhotos() {
        for photo in MenuDraftPhotos.make(review: review) where !plan.selected.contains(where: { $0.id == photo.id }) {
            plan.selected.append(photo)
        }
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
        snapshot.requestPhotos = plan.selected
        snapshot.requestReview = review
        snapshot.referencePostIDs = includeReferences ? references?.articles.map(\.postID) ?? [] : []
        do {
            try DraftPhotoPlanStore().save(snapshot, reviewID: review.id)
            plan = snapshot; copy(prompt)
            message = "작성 요청을 복사했습니다. ChatGPT에 붙여넣고 생성된 글을 가져오세요."
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
        message = "초안을 가져왔습니다. 사진 미리보기에서 확인한 뒤 저장하세요."
    }
    @discardableResult private func save() -> Bool {
        guard !loadFailed else { return false }
        let now = Date()
        var value = draft ?? BlogDraft(reviewID: review.id, sourceReview: plan.requestReview ?? review,
                                      referencePostIDs: plan.referencePostIDs ?? [], model: "직접 작성",
                                      createdAt: now, updatedAt: now, text: text, photos: plan.requestPhotos ?? plan.selected)
        value.text = text; value.updatedAt = now
        do {
            try DraftStore().save(value)
            draft = value; baseline = text; photoConnectionChanged = false; message = "초안을 저장했습니다."
            return true
        } catch { message = "초안을 저장하지 못했습니다: \(error.localizedDescription)"; return false }
    }
    private func connectCurrentPhotos() {
        guard !loadFailed, !plan.selected.isEmpty else { return }
        let now = Date()
        var value = draft ?? BlogDraft(reviewID: review.id, sourceReview: review,
                                      referencePostIDs: plan.referencePostIDs ?? [], model: "직접 작성",
                                      createdAt: now, updatedAt: now, text: text)
        value.photos = plan.selected
        draft = value
        photoConnectionChanged = true
        preview = true
        message = "현재 사진을 연결했습니다. 위치를 확인한 뒤 초안 저장을 누르세요."
    }
    private func exportPhotos(includePost: Bool = false) {
        if includePost {
            do { _ = try NaverPostPacket.make(text: text, photos: displayPhotos, filenames: displayPhotos.map { $0.id }) }
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
                let result = try await DraftPhotoExporter.export(photos, assets: mapping, folder: folder, postText: postText)
                message = includePost ? "임시저장용 묶음을 내보냈습니다. Chrome 확장 프로그램의 네이버 임시저장에서 이 폴더의 파일들을 선택하세요." : "사진 \(photos.count)장을 내보냈습니다: \(result.lastPathComponent)"
                NSWorkspace.shared.open(result)
            } catch { message = "사진 내보내기 실패: \(error.localizedDescription)" }
        }
    }
    private func sendToNaver() {
        guard bridge.ready else { chromeConnectionVisible = true; return }
        let photos = displayPhotos
        let mapping = assetMap
        let content = text
        do { _ = try NaverPostPacket.make(text: content, photos: photos, filenames: photos.map(\.id)) }
        catch { message = error.localizedDescription; return }
        exporting = true
        exportTask = Task { @MainActor in
            defer { exporting = false; exportTask = nil }
            var prepared: URL?
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NaverBridge", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let result = try await DraftPhotoExporter.export(photos, assets: mapping, folder: folder, postText: content)
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
