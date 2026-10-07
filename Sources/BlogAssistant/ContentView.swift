import AppKit
import Photos
import SwiftUI

private enum VisitFilter: String, CaseIterable {
    case pending = "미정리"
    case organized = "정리 완료"
    case all = "전체"
}

struct ContentView: View {
    @ObservedObject var library: PhotoLibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedVisit: PhotoVisit?
    @State private var visitFilter: VisitFilter = .pending
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 230), spacing: 16)]

    private var visibleDays: [PhotoDay] {
        library.days.compactMap { day in
            let visits = day.visits.filter { visit in
                switch visitFilter {
                case .pending: return !library.isOrganized(visit)
                case .organized: return library.isOrganized(visit)
                case .all: return true
                }
            }
            return visits.isEmpty ? nil : PhotoDay(date: day.date, visits: visits)
        }
    }

    private func visitCount(for filter: VisitFilter) -> Int {
        library.days.flatMap(\.visits).filter { visit in
            switch filter {
            case .pending: return !library.isOrganized(visit)
            case .organized: return library.isOrganized(visit)
            case .all: return true
            }
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("맛집 기록의 시작").font(.largeTitle.bold())
                    Text("최근 사진을 촬영일과 방문 장소 후보별로 확인하세요.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if library.canRead {
                    Button { library.refresh() } label: {
                        Label("새로고침", systemImage: "arrow.clockwise")
                    }.disabled(library.isLoading)
                }
            }.padding(24)
            Divider()
            if library.canRead {
                photoGrid
            } else {
                permissionView
            }
        }
        .task { library.refresh() }
        .sheet(item: $selectedVisit) { visit in
            VisitDetailView(visitID: visit.id, library: library)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { library.refresh() }
        }
    }

    private var photoGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("방문 정리 상태", selection: $visitFilter) {
                ForEach(VisitFilter.allCases, id: \.self) { filter in
                    Text("\(filter.rawValue) (\(visitCount(for: filter)))").tag(filter)
                }
            }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.top, 16)
            HStack {
                Text("\(visitFilter.rawValue) · \(visibleDays.reduce(0) { $0 + $1.count })장")
                Spacer()
                Text("촬영일 최신순 · 최대 \(library.photoLimit)장")
            }.font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 16)
            if library.authorization == .limited {
                Text("허용된 사진만 표시됩니다. 접근 범위는 시스템 설정에서 변경할 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24)
            }
            if library.isLoading && library.days.isEmpty {
                Spacer()
                HStack { Spacer(); ProgressView("사진을 불러오는 중…"); Spacer() }
                Spacer()
            } else if library.days.isEmpty {
                message(icon: "photo.on.rectangle", title: "표시할 사진이 없습니다", detail: "시스템 사진 보관함에 사진을 추가한 후 새로고침하세요.")
            } else if visibleDays.isEmpty {
                message(icon: visitFilter == .pending ? "checkmark.circle" : "tray",
                        title: visitFilter == .pending ? "모든 방문의 정리가 완료됐습니다" : "정리 완료된 방문이 없습니다",
                        detail: visitFilter == .pending ? "정리 완료 목록에서 음식점명을 저장한 방문을 확인하세요." : "미정리 방문의 상세 화면에서 음식점명을 저장하세요.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                        ForEach(visibleDays) { day in
                            Section {
                                ForEach(Array(day.visits.enumerated()), id: \.element.id) { index, visit in
                                    VStack(alignment: .leading, spacing: 12) {
                                        visitHeader(visit, number: index + 1)
                                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                                            ForEach(visit.assets, id: \.localIdentifier) { asset in
                                                PhotoThumbnail(asset: asset, manager: library.imageManager)
                                            }
                                        }
                                    }.padding(16)
                                        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedVisit = visit }
                                }
                            } header: {
                                HStack {
                                    Text(day.date.map { $0.formatted(date: .complete, time: .omitted) } ?? "촬영일 정보 없음")
                                        .font(.headline)
                                    Text("\(day.visits.count)개 후보 · \(day.count)장").foregroundStyle(.secondary)
                                    Spacer()
                                }.padding(.vertical, 12).background(.background)
                            }
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
        }
    }

    private func visitHeader(_ visit: PhotoVisit, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(library.restaurantName(for: visit) ?? (visit.hasLocation ? "장소 후보 \(number)" : "위치 미확인 \(number)"),
                      systemImage: visit.hasLocation ? "mappin.and.ellipse" : "location.slash")
                    .font(.headline)
                Spacer()
                Text("\(visit.assets.count)장").foregroundStyle(.secondary)
                if library.isOrganized(visit) {
                    Label("정리 완료", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                Button("상세 보기") { selectedVisit = visit }
            }
            if let start = visit.start, let end = visit.end {
                Text("\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(visit.hasLocation
                 ? (visit.uncertainCount > 0 ? "GPS 기반 후보 · 위치 불확실 \(visit.uncertainCount)장 포함 (시간 기준)" : "GPS 기반 후보 · 음식점 확인 필요")
                 : "GPS 정보 없음 · 촬영 시간으로만 묶은 후보")
                .font(.caption).foregroundStyle(.secondary)
            if library.savedNames(for: visit).count > 1 {
                Text("저장된 음식점명이 여러 개입니다. 상세 화면에서 확인하세요.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if visit.isManual {
                Label("직접 수정한 방문", systemImage: "hand.draw").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var permissionView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "photo.badge.plus").font(.system(size: 48)).foregroundStyle(.tint)
            Text("사진 보관함 접근이 필요합니다").font(.title2.bold())
            Text(permissionDescription).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if library.authorization == .notDetermined {
                Button(library.isRequesting ? "권한 요청 중…" : "사진 접근 허용") {
                    Task { await library.requestAccess() }
                }.buttonStyle(.borderedProminent).disabled(library.isRequesting)
            } else if library.authorization == .denied {
                Button("시스템 설정 열기") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                        NSWorkspace.shared.open(url)
                    }
                }.buttonStyle(.borderedProminent)
            }
            Spacer()
        }.frame(maxWidth: .infinity).padding(32)
    }

    private var permissionDescription: String {
        switch library.authorization {
        case .denied: return "시스템 설정 → 개인정보 보호 및 보안 → 사진에서 이 앱의 접근을 허용하세요."
        case .restricted: return "이 Mac의 정책으로 사진 접근이 제한되어 있습니다. 기기 관리자에게 확인하세요."
        default: return "맛집 블로그에 사용할 사진을 찾기 위해 사진 보관함을 조회합니다.\nV1에서는 사진을 수정하거나 업로드하지 않습니다."
        }
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.title2)
            Text(detail).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity).padding()
    }
}
