import CoreLocation
import Foundation

struct VisitPhoto {
    let id: String
    let date: Date?
    let location: CLLocation?
}

enum VisitGrouping {
    static let maximumDistance: CLLocationDistance = 100
    static let maximumInterval: TimeInterval = 90 * 60

    // The caller supplies one calendar day at a time. Missing dates stay unassigned.
    static func groups(for photos: [VisitPhoto]) -> [[VisitPhoto]] {
        let dated = photos.filter { $0.date != nil }.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return $0.date! < $1.date!
        }
        var groups: [[VisitPhoto]] = []
        var current: [VisitPhoto] = []
        var anchor: CLLocation?
        for photo in dated {
            let location = photo.location.flatMap {
                $0.horizontalAccuracy >= 0 && CLLocationCoordinate2DIsValid($0.coordinate) ? $0 : nil
            }
            let timeBreak = current.last.map { photo.date!.timeIntervalSince($0.date!) > maximumInterval } ?? false
            // Keep a fixed first GPS anchor so walking photos cannot chain across places.
            let distanceBreak = location.flatMap { location in
                anchor.map { location.distance(from: $0) > maximumDistance }
            } ?? false
            if !current.isEmpty && (timeBreak || distanceBreak) {
                groups.append(current)
                current = []
                anchor = nil
            }
            current.append(VisitPhoto(id: photo.id, date: photo.date, location: location))
            if anchor == nil { anchor = location }
        }
        if !current.isEmpty { groups.append(current) }
        let undated = photos.filter { $0.date == nil }.sorted { $0.id < $1.id }
        if !undated.isEmpty { groups.append(undated) }
        return groups
    }
}
