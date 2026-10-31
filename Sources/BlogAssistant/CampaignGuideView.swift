import AppKit
import SwiftUI

struct CampaignGuidePanel: View {
    let restaurantName: String
    let record: CampaignGuideRecord
    let checks: [CampaignChecklist.Check]
    let text: String
    let photos: [DraftPhoto]
    let disabled: Bool
    let onSave: (CampaignGuideRecord) throws -> Void
    @State private var editing = false
    @State private var error: String?

    private var summary: String {
        guard record.guide != nil else { return record.rawSource.isEmpty ? "체험단 요구사항 · 선택 사항" : "체험단 요구사항 · 정리 결과 등록 필요" }
        let required = checks.filter { $0.requirement.required }
        return "체험단 요구사항 · 필수 \(required.filter { $0.status == .passed }.count)/\(required.count) 충족"
    }
    var body: some View {
        DisclosureGroup(summary) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button(record.guide == nil ? "가이드 등록" : "원문·요구사항 수정") { editing = true }.disabled(disabled)
                    Text("원문 → GPT 정리 → 확인·저장 → 작성 요청에 자동 포함")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if record.needsReview {
                    Text("원문이 바뀌었습니다. 정리 결과를 다시 확인·저장하면 작성 요청에 사용할 수 있습니다.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                if let guide = record.guide {
                    Text("자동 검사와 직접 확인을 구분합니다. 글·사진 연결을 바꾸면 직접 확인을 다시 진행하세요.")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(checks) { check in requirementRow(check) }
                            if !guide.notes.isEmpty {
                                DisclosureGroup("원문의 참고 안내") {
                                    ForEach(Array(guide.notes.enumerated()), id: \.offset) { _, note in
                                        Text(note).font(.caption).textSelection(.enabled)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 260)
                } else {
                    Text(record.rawSource.isEmpty ? "체험단일 때만 가이드를 등록하세요. 일반 후기는 지금처럼 작성할 수 있습니다." : "원문만 저장된 상태입니다. GPT 정리 결과를 확인하고 저장해야 작성 요청에 조건이 포함됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
        }
        .sheet(isPresented: $editing) {
            CampaignGuideEditor(restaurantName: restaurantName, initial: record, onSave: onSave)
        }
    }

    private func requirementRow(_ check: CampaignChecklist.Check) -> some View {
        let item = check.requirement
        let automatic = item.kind == .keyword || item.kind == .exactText || item.kind == .minPhotos
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                Image(systemName: check.status == .passed ? "checkmark.circle.fill" : (check.status == .missing ? "exclamationmark.circle" : "circle.dashed"))
                    .foregroundStyle(check.status == .passed ? Color.green : (check.status == .missing ? .orange : .secondary))
                Text(item.label).font(.callout.bold())
                Text(item.required ? "필수" : "선택").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(automatic ? "자동 검사" : "직접 확인").font(.caption).foregroundStyle(.secondary)
            }
            Text(item.summary).font(.caption).textSelection(.enabled)
            Text(check.detail).font(.caption).foregroundStyle(check.status == .missing ? Color.orange : .secondary)
            DisclosureGroup("조건 근거") { Text(item.evidence).font(.caption).textSelection(.enabled) }
            if item.kind == .photo {
                DisclosureGroup("해당 사진 연결") {
                    ForEach(Array(photos.enumerated()).filter { !$0.element.isVideo }, id: \.element.id) { index, photo in
                        Toggle("사진 \(index + 1) · \(photo.caption.isEmpty ? "설명 없음" : photo.caption)", isOn: Binding(
                            get: { (record.photoLinks[item.id] ?? []).contains(photo.id) },
                            set: { selected in
                                var updated = record
                                var ids = updated.photoLinks[item.id] ?? []
                                ids.removeAll { $0 == photo.id }; if selected { ids.append(photo.id) }
                                updated.photoLinks[item.id] = ids
                                commit(updated)
                            }))
                    }
                    if photos.allSatisfy(\.isVideo) { Text("왼쪽 목록에서 사진을 먼저 선택하세요.").font(.caption) }
                }.disabled(disabled)
            }
            if !automatic {
                Toggle("현재 글과 사진 기준 직접 확인 완료", isOn: Binding(
                    get: { check.status == .passed },
                    set: { confirmed in
                        var updated = record
                        updated.confirmations[item.id] = confirmed ? CampaignChecklist.token(text: text, photos: photos, links: record.photoLinks) : nil
                        commit(updated)
                    }))
                    .disabled(disabled || record.needsReview || CampaignGuide.clean(text).isEmpty || (item.kind == .photo && check.status == .missing) || (item.kind == .photo && (record.photoLinks[item.id] ?? []).isEmpty))
            }
            Divider()
        }
    }
    private func commit(_ updated: CampaignGuideRecord) {
        do { try onSave(updated); error = nil } catch { self.error = error.localizedDescription }
    }
}

private struct CampaignGuideEditor: View {
    let restaurantName: String
    let initial: CampaignGuideRecord
    let onSave: (CampaignGuideRecord) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var source: String
    @State private var result = ""
    @State private var staged: CampaignGuide?
    @State private var saved: CampaignGuideRecord
    @State private var message: String?
    @State private var discard = false

    init(restaurantName: String, initial: CampaignGuideRecord, onSave: @escaping (CampaignGuideRecord) throws -> Void) {
        self.restaurantName = restaurantName; self.initial = initial; self.onSave = onSave
        _source = State(initialValue: initial.rawSource); _saved = State(initialValue: initial)
    }
    private var dirty: Bool { source != saved.rawSource || !result.isEmpty || staged != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("체험단 가이드 · \(restaurantName)").font(.title2.bold())
                Spacer()
                Button("닫기") { if dirty { discard = true } else { dismiss() } }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("① 메일·가이드 원문 입력").font(.headline)
                    Text("메일과 PDF에서 복사한 내용, 매니저에게 확인받은 내용과 출처를 함께 넣으세요. 앱은 메일을 자동으로 읽거나 GPT를 직접 호출하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: Binding(get: { source }, set: { source = $0; staged = nil })).frame(height: 140).border(Color.secondary.opacity(0.3)).accessibilityLabel("체험단 가이드 원문")
                    HStack {
                        Button("원문 저장") { saveSource(copyRequest: false) }
                        Button("가이드 정리 요청 복사") { saveSource(copyRequest: true) }
                            .buttonStyle(.borderedProminent).disabled(CampaignGuide.clean(source).isEmpty)
                        Link("ChatGPT 열기", destination: URL(string: "https://chatgpt.com/")!)
                    }
                    Text("② GPT 정리 결과 가져오기").font(.headline)
                    Text("복사한 요청을 GPT에 전달하고 정리 결과 전체를 아래에 붙여넣으세요. 기존 글 초안은 변경하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: Binding(get: { result }, set: { result = $0; staged = nil })).frame(height: 100).border(Color.secondary.opacity(0.3)).accessibilityLabel("가이드 정리 결과")
                    HStack {
                        Button("정리 결과 붙여넣기") {
                            if let text = NSPasteboard.general.string(forType: .string) { result = text; parseResult() }
                            else { message = "GPT의 가이드 정리 결과를 먼저 복사하세요." }
                        }
                        Button("결과 확인") { parseResult() }.disabled(result.isEmpty)
                        if saved.guide != nil {
                            Button("저장된 요구사항 수정") { staged = saved.guide; result = "" }
                        }
                    }
                    if staged != nil {
                        Text("③ 내용 확인 후 저장").font(.headline)
                        ForEach(staged?.requirements.indices.map { $0 } ?? [], id: \.self) { index in
                            editableRequirement(index)
                        }
                    }
                }.padding(.trailing, 8)
            }
            if let message { Text(message).font(.caption).textSelection(.enabled) }
            HStack {
                if saved.guide != nil {
                    Button("가이드 사용 해제") {
                        var value = saved; value.guide = nil; value.confirmedSource = nil
                        value.confirmations = [:]; value.photoLinks = [:]
                        do { try onSave(value); saved = value; dismiss() } catch { message = error.localizedDescription }
                    }
                }
                Spacer()
                Button("확인하고 저장") { saveGuide() }.buttonStyle(.borderedProminent).disabled(staged == nil)
            }
        }.padding(24).frame(width: 760, height: 760)
            .interactiveDismissDisabled(dirty)
            .confirmationDialog("저장하지 않은 입력을 버리고 닫을까요?", isPresented: $discard, titleVisibility: .visible) {
                Button("입력 버리고 닫기", role: .destructive) { dismiss() }
                Button("계속 입력", role: .cancel) {}
            }
    }

    private func editableRequirement(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("항목명", text: binding(index, \.label)).font(.headline)
            Picker("조건 종류", selection: binding(index, \.kind)) {
                ForEach(CampaignGuide.Kind.allCases, id: \.rawValue) { kind in Text(kind.name).tag(kind) }
            }
            Toggle("필수 요구사항", isOn: binding(index, \.required))
            if let item = staged?.requirements[index] {
                if item.kind == .keyword {
                    TextField("키워드 (쉼표로 구분)", text: Binding(get: { staged?.requirements[index].terms.joined(separator: ", ") ?? "" }, set: { value in
                        staged?.requirements[index].terms = value.components(separatedBy: ",").map(CampaignGuide.clean).filter { !$0.isEmpty }
                    }))
                    Picker("키워드 조건", selection: binding(index, \.match)) {
                        Text("모두 포함").tag(CampaignGuide.Match.all); Text("하나 이상").tag(CampaignGuide.Match.any)
                    }
                    HStack {
                        ForEach([CampaignGuide.Location.title, .body, .tags], id: \.rawValue) { location in
                            Toggle(location == .title ? "제목" : (location == .body ? "본문" : "태그"), isOn: Binding(get: { staged?.requirements[index].locations.contains(location) ?? false }, set: { selected in
                                staged?.requirements[index].locations.removeAll { $0 == location }
                                if selected { staged?.requirements[index].locations.append(location) }
                            }))
                        }
                    }
                } else if item.kind == .minPhotos || item.kind == .captureCount {
                    Stepper(item.summary, value: Binding(get: { staged?.requirements[index].minimum ?? 1 }, set: { staged?.requirements[index].minimum = $0 }), in: 1...1_000)
                } else {
                    TextField("조건 내용", text: binding(index, \.text))
                }
                Text("원문 근거: \(item.evidence)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Divider()
        }.padding(.vertical, 4)
    }
    private func binding<T>(_ index: Int, _ keyPath: WritableKeyPath<CampaignGuide.Requirement, T>) -> Binding<T> {
        let fallback = staged!.requirements[index][keyPath: keyPath]
        return Binding(get: {
            guard let staged, staged.requirements.indices.contains(index) else { return fallback }
            return staged.requirements[index][keyPath: keyPath]
        }, set: { value in
            guard staged?.requirements.indices.contains(index) == true else { return }
            staged?.requirements[index][keyPath: keyPath] = value
        })
    }
    private func parseResult() {
        do { staged = try CampaignGuide.parse(result, source: source, restaurantName: restaurantName); message = "원문 근거를 확인했습니다. 항목을 확인하고 필요한 내용을 수정한 뒤 저장하세요." }
        catch { staged = nil; message = error.localizedDescription }
    }
    private func saveSource(copyRequest: Bool) {
        do {
            let request = copyRequest ? try CampaignGuide.extractionRequest(source: source, restaurantName: restaurantName) : nil
            var value = saved; value.rawSource = source
            try onSave(value); saved = value
            if let request { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(request, forType: .string) }
            message = copyRequest ? "원문을 저장하고 정리 요청을 복사했습니다. GPT 결과를 이 화면으로 가져오세요." : "원문을 저장했습니다."
        } catch { message = error.localizedDescription }
    }
    private func saveGuide() {
        guard let staged else { return }
        do {
            let checked = try CampaignGuide.parse(CampaignGuide.json(staged), source: source, restaurantName: restaurantName)
            var value = saved; value.rawSource = source; value.guide = checked; value.confirmedSource = source
            value.confirmations = [:]; value.photoLinks = [:]
            try onSave(value); saved = value; result = ""; self.staged = nil; dismiss()
        } catch { message = error.localizedDescription }
    }
}
