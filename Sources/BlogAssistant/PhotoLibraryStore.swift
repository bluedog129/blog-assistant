import AppKit
import Photos
import SwiftUI

struct NearbyPhoto: Identifiable {
    let asset: PHAsset
    let distance: Double
    var id: String { asset.localIdentifier }
}

struct PhotoDay: Identifiable {
    let date: Date?
    let visits: [PhotoVisit]
    var count: Int { visits.reduce(0) { $0 + $1.assets.count } }
    var id: String { date.map { String($0.timeIntervalSince1970) } ?? "unknown" }
}

struct PhotoVisit: Identifiable {
    let id: String
    let assets: [PHAsset]
    let start: Date?
    let end: Date?
    let locatedCount: Int
    let isManual: Bool
    var hasLocation: Bool { locatedCount > 0 }
    var uncertainCount: Int { assets.count - locatedCount }
}

@MainActor
final class PhotoLibraryStore: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var days: [PhotoDay] = []
    @Published private(set) var photoRevision = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isRequesting = false
    @Published private(set) var nameRevision = 0
    private let visitNames = VisitNameStore()
    private let visitGroups = VisitGroupStore()
    private let reviews = ReviewStore()
    @Published private(set) var reviewRevision = 0
    let imageManager = PHCachingImageManager()
    let photoLimit = 300
    private var observing = false
    private var generation = 0

    var canRead: Bool { authorization == .authorized || authorization == .limited }
    var count: Int { days.reduce(0) { $0 + $1.count } }

    func savedNames(for visit: PhotoVisit) -> [String] {
        visitNames.names(for: visit.assets.map(\.localIdentifier))
    }

    func restaurantName(for visit: PhotoVisit) -> String? {
        let names = savedNames(for: visit)
        return names.count == 1 ? names[0] : nil
    }

    func isOrganized(_ visit: PhotoVisit) -> Bool {
        visitNames.isComplete(for: visit.assets.map(\.localIdentifier))
    }

    // Fetch saved identifiers directly, including photos outside the recent-300 list.
    func assets(for identifiers: [String]) -> [PHAsset] {
        guard canRead, !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(Set(identifiers)), options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            if asset.mediaType == .image { assets.append(asset) }
        }
        return assets
    }

    func nearbyPhotos(photoIDs: [String], referenceID: String, radius: Double) async throws -> [NearbyPhoto] {
        guard canRead else { throw photoSearchFailure("사진 보관함 접근 권한이 필요합니다.") }
        let currentAssets = assets(for: photoIDs)
        guard let reference = currentAssets.first(where: { $0.localIdentifier == referenceID }),
              let anchor = reference.location, LocationPhotoSearch.isValid(anchor) else {
            throw photoSearchFailure("이번 방문에 유효한 GPS가 있는 사진을 검색 기준으로 선택하세요.")
        }
        let calendar = Calendar.current
        let dates = currentAssets.compactMap(\.creationDate)
        guard !dates.isEmpty else { throw photoSearchFailure("이번 방문의 날짜를 먼저 확인하세요.") }
        let query = LocationPhotoSearch(anchor: anchor, radius: radius,
                                       excludedIDs: Set(photoIDs),
                                       excludedDays: Set(dates.map { calendar.startOfDay(for: $0) }), calendar: calendar)
        let search = Task.detached(priority: .userInitiated) { () throws -> [NearbyPhoto] in
            try Task.checkCancellation()
            let options = PHFetchOptions()
            // No fetch limit: search metadata throughout the accessible image library.
            let result = PHAsset.fetchAssets(with: .image, options: options)
            var matches: [NearbyPhoto] = []
            result.enumerateObjects { asset, _, stop in
                if Task.isCancelled { stop.pointee = true; return }
                if let distance = query.distance(id: asset.localIdentifier, date: asset.creationDate, location: asset.location) {
                    matches.append(NearbyPhoto(asset: asset, distance: distance))
                }
            }
            try Task.checkCancellation()
            return matches.sorted {
                if $0.asset.creationDate == $1.asset.creationDate {
                    if $0.distance == $1.distance { return $0.id < $1.id }
                    return $0.distance < $1.distance
                }
                return ($0.asset.creationDate ?? .distantPast) > ($1.asset.creationDate ?? .distantPast)
            }
        }
        let matches = try await withTaskCancellationHandler(operation: {
            try await search.value
        }, onCancel: { search.cancel() })
        try Task.checkCancellation()
        guard canRead else { throw photoSearchFailure("사진 보관함 접근 권한이 필요합니다.") }
        return matches
    }

    private func photoSearchFailure(_ message: String) -> NSError {
        NSError(domain: "LocationPhotoSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func savedReviews(for visit: PhotoVisit) throws -> [VisitReview] {
        try reviews.matches(photoIDs: visit.assets.map(\.localIdentifier))
    }

    func reviewStatus(for visit: PhotoVisit) -> String {
        guard let saved = try? savedReviews(for: visit) else { return "후기 정보 읽기 실패" }
        guard !saved.isEmpty else { return "후기 정보 미입력" }
        guard saved.count == 1, let record = saved.first,
              Set(record.photoIDs) == Set(visit.assets.map(\.localIdentifier)),
              record.restaurantName == restaurantName(for: visit) else { return "입력 중 · 방문 정보 확인 필요" }
        return record.isReady && isOrganized(visit) ? "초안 생성 가능" : "입력 중"
    }

    func saveReview(_ review: VisitReview, for visitID: String) throws {
        guard canRead, isLoading == false,
              let current = days.flatMap(\.visits).first(where: { $0.id == visitID }), isOrganized(current),
              Set(current.assets.map(\.localIdentifier)) == Set(review.photoIDs),
              restaurantName(for: current) == review.restaurantName else {
            throw NSError(domain: "Review", code: 1, userInfo: [NSLocalizedDescriptionKey: "방문 사진 또는 음식점명이 변경됐습니다. 목록에서 방문을 다시 확인하세요."])
        }
        try reviews.save(review)
        reviewRevision += 1
    }

    func saveRestaurantName(_ name: String, for visit: PhotoVisit) {
        visitNames.save(name, for: visit.assets.map(\.localIdentifier))
        nameRevision += 1
    }

    func otherVisits(onDayOf visitID: String) -> [PhotoVisit] {
        days.first { $0.visits.contains { $0.id == visitID } }?.visits.filter { $0.id != visitID } ?? []
    }

    // Return the group to display after editing. All operations use fresh library state.
    func split(visitID: String, photoIDs: Set<String>) -> String? {
        guard canRead, !isLoading,
              let day = days.first(where: { $0.visits.contains { $0.id == visitID } }),
              let source = day.visits.first(where: { $0.id == visitID }) else { return nil }
        let ids = Set(source.assets.map(\.localIdentifier))
        guard !photoIDs.isEmpty, photoIDs.isSubset(of: ids), photoIDs.count < ids.count else { return nil }
        let sourceID = source.isManual ? source.id : "manual-\(UUID().uuidString)"
        visitGroups.assign(Array(ids.subtracting(photoIDs)), to: sourceID)
        visitGroups.assign(Array(photoIDs), to: "manual-\(UUID().uuidString)")
        rebuild(day)
        return sourceID
    }

    func move(visitID: String, photoIDs: Set<String>, to targetID: String) -> String? {
        guard canRead, !isLoading, visitID != targetID,
              let day = days.first(where: { $0.visits.contains { $0.id == visitID } }),
              let source = day.visits.first(where: { $0.id == visitID }),
              let target = day.visits.first(where: { $0.id == targetID }) else { return nil }
        let ids = Set(source.assets.map(\.localIdentifier))
        guard !photoIDs.isEmpty, photoIDs.isSubset(of: ids) else { return nil }
        let destination = target.isManual ? target.id : "manual-\(UUID().uuidString)"
        let remaining = ids.subtracting(photoIDs)
        if !remaining.isEmpty {
            visitGroups.assign(Array(remaining), to: source.isManual ? source.id : "manual-\(UUID().uuidString)")
        }
        visitGroups.assign(target.assets.map(\.localIdentifier) + Array(photoIDs), to: destination)
        rebuild(day)
        return destination
    }

    func resetGrouping(for visitID: String) {
        guard canRead, !isLoading,
              let day = days.first(where: { $0.visits.contains { $0.id == visitID } }) else { return }
        visitGroups.reset(day.visits.flatMap { $0.assets.map(\.localIdentifier) })
        rebuild(day)
    }

    private func rebuild(_ day: PhotoDay) {
        generation += 1
        let updated = Self.makeDay(date: day.date, assets: day.visits.flatMap(\.assets), assignments: visitGroups.assignments)
        days = days.map { $0.id == day.id ? updated : $0 }
    }

    nonisolated private static func makeDay(date: Date?, assets: [PHAsset], assignments: [String: String]) -> PhotoDay {
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        let metadata = assets.map { VisitPhoto(id: $0.localIdentifier, date: $0.creationDate, location: $0.location) }
        let automatic = VisitGrouping.groups(for: metadata)
        let located = Set(automatic.flatMap { $0 }.filter { $0.location != nil }.map(\.id))
        let visits = VisitGroupStore.apply(to: automatic.map { $0.map(\.id) }, assignments: assignments).map { group in
            let sorted = group.photoIDs.compactMap { byID[$0] }.sorted {
                if $0.creationDate == $1.creationDate { return $0.localIdentifier < $1.localIdentifier }
                return ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
            }
            return PhotoVisit(id: group.id, assets: sorted, start: sorted.first?.creationDate,
                              end: sorted.last?.creationDate, locatedCount: group.photoIDs.filter { located.contains($0) }.count,
                              isManual: group.isManual)
        }.sorted {
            if $0.start == $1.start { return $0.id < $1.id }
            return ($0.start ?? .distantPast) > ($1.start ?? .distantPast)
        }
        return PhotoDay(date: date, visits: visits)
    }

    func requestAccess() async {
        guard !isRequesting else { return }
        isRequesting = true
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        isRequesting = false
        refresh()
    }

    func refresh() {
        photoRevision += 1
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        generation += 1
        let currentGeneration = generation
        guard canRead else {
            days = []
            isLoading = false
            imageManager.stopCachingImagesForAllAssets()
            return
        }
        if !observing {
            PHPhotoLibrary.shared().register(self)
            observing = true
        }
        isLoading = true
        let limit = photoLimit
        let assignments = visitGroups.assignments
        DispatchQueue.global(qos: .userInitiated).async {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = limit
            let result = PHAsset.fetchAssets(with: .image, options: options)
            var grouped: [Date: [PHAsset]] = [:]
            var unknown: [PHAsset] = []
            let calendar = Calendar.current
            result.enumerateObjects { asset, _, _ in
                if let date = asset.creationDate {
                    grouped[calendar.startOfDay(for: date), default: []].append(asset)
                } else {
                    unknown.append(asset)
                }
            }
            var sections = grouped.keys.sorted(by: >).map { Self.makeDay(date: $0, assets: grouped[$0]!, assignments: assignments) }
            if !unknown.isEmpty { sections.append(Self.makeDay(date: nil, assets: unknown, assignments: assignments)) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.days = sections
                self.isLoading = false
            }
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    deinit {
        if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    }
}
