import CoreLocation
import Foundation

@main struct LocationPhotoSearchChecks {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        let past = calendar.date(byAdding: .day, value: -30, to: day)!
        let future = calendar.date(byAdding: .day, value: 1, to: day)!
        let anchor = CLLocation(latitude: 37.5, longitude: 127.0)
        let nearby = CLLocation(latitude: 37.5002, longitude: 127.0)
        let far = CLLocation(latitude: 37.51, longitude: 127.0)
        let query = LocationPhotoSearch(anchor: anchor, radius: 50, excludedIDs: ["current"],
                                        excludedDays: [day], calendar: calendar)
        precondition(query.distance(id: "unnamed-old-photo", date: past, location: nearby) != nil)
        precondition(query.distance(id: "different-date", date: future, location: anchor) == 0)
        precondition(query.distance(id: "current", date: past, location: anchor) == nil)
        precondition(query.distance(id: "same-day", date: day.addingTimeInterval(23 * 3600), location: anchor) == nil)
        precondition(query.distance(id: "previous-midnight", date: day.addingTimeInterval(-1), location: anchor) == 0)
        precondition(query.distance(id: "far", date: past, location: far) == nil)
        precondition(query.distance(id: "undated", date: nil, location: anchor) == nil)
        precondition(query.distance(id: "no-gps", date: past, location: nil) == nil)
        let invalid = CLLocation(coordinate: anchor.coordinate, altitude: 0, horizontalAccuracy: -1,
                                 verticalAccuracy: -1, timestamp: Date())
        precondition(query.distance(id: "invalid-accuracy", date: past, location: invalid) == nil)
        let invalidCoordinates = CLLocation(latitude: 91, longitude: 127)
        precondition(!LocationPhotoSearch.isValid(invalidCoordinates))
        let boundary = LocationPhotoSearch(anchor: anchor, radius: nearby.distance(from: anchor),
                                           excludedIDs: [], excludedDays: [day], calendar: calendar)
        precondition(boundary.distance(id: "boundary", date: past, location: nearby) != nil)
        let smaller = LocationPhotoSearch(anchor: anchor, radius: nearby.distance(from: anchor) - 0.01,
                                          excludedIDs: [], excludedDays: [day], calendar: calendar)
        precondition(smaller.distance(id: "outside", date: past, location: nearby) == nil)
        let invalidAnchor = LocationPhotoSearch(anchor: invalid, radius: 50, excludedIDs: [], excludedDays: [], calendar: calendar)
        precondition(invalidAnchor.distance(id: "bad-anchor", date: past, location: nearby) == nil)
        // More than 300 metadata candidates and no saved restaurant names are needed.
        let matches = (0..<350).compactMap { query.distance(id: "old-\($0)", date: past, location: nearby) }
        precondition(matches.count == 350)
        print("Passed GPS radius boundaries, different-day/timezone exclusion, missing/invalid metadata and unnamed photos beyond 300 checks")
    }
}
