import AppKit
import Photos
import SwiftUI

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
    var hasLocation: Bool { locatedCount > 0 }
    var uncertainCount: Int { assets.count - locatedCount }
}

@MainActor
final class PhotoLibraryStore: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var days: [PhotoDay] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRequesting = false
    @Published private(set) var nameRevision = 0
    private let visitNames = VisitNameStore()
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

    func saveRestaurantName(_ name: String, for visit: PhotoVisit) {
        visitNames.save(name, for: visit.assets.map(\.localIdentifier))
        nameRevision += 1
    }

    func requestAccess() async {
        guard !isRequesting else { return }
        isRequesting = true
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        isRequesting = false
        refresh()
    }

    func refresh() {
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
            func makeDay(date: Date?, assets: [PHAsset]) -> PhotoDay {
                let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
                let metadata = assets.map { VisitPhoto(id: $0.localIdentifier, date: $0.creationDate, location: $0.location) }
                let visits = VisitGrouping.groups(for: metadata).map { photos in
                    PhotoVisit(id: photos[0].id, assets: photos.compactMap { byID[$0.id] },
                               start: photos.first?.date, end: photos.last?.date,
                               locatedCount: photos.filter { $0.location != nil }.count)
                }
                return PhotoDay(date: date, visits: visits.reversed())
            }
            var sections = grouped.keys.sorted(by: >).map { makeDay(date: $0, assets: grouped[$0]!) }
            if !unknown.isEmpty { sections.append(makeDay(date: nil, assets: unknown)) }
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
