import CoreLocation
import Foundation

// One fixed anchor prevents a chain of nearby photos from expanding the search area.
struct LocationPhotoSearch {
    let anchor: CLLocation
    let radius: CLLocationDistance
    let excludedIDs: Set<String>
    let excludedDays: Set<Date>
    let calendar: Calendar

    static func isValid(_ location: CLLocation?) -> Bool {
        guard let location else { return false }
        return location.horizontalAccuracy >= 0 && location.horizontalAccuracy.isFinite &&
            CLLocationCoordinate2DIsValid(location.coordinate)
    }

    func distance(id: String, date: Date?, location: CLLocation?) -> CLLocationDistance? {
        guard Self.isValid(anchor), Self.isValid(location), radius.isFinite, radius > 0,
              !excludedIDs.contains(id), let date,
              !excludedDays.contains(calendar.startOfDay(for: date)), let location else { return nil }
        let distance = location.distance(from: anchor)
        return distance.isFinite && distance <= radius ? distance : nil
    }
}
