import CoreLocation

private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T) {
    precondition(actual == expected, "Expected \(expected), got \(actual)")
}
private func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }

@main
struct VisitGroupingTests {
    static func main() {
        let tests = Self()
        tests.testNearbyPhotosAndTimeOnlyPhotoShareCandidate()
        tests.testDistanceAndReturnVisitSplitEvenWithMissingGPSBetween()
        tests.testLongGapSplitsSameLocation()
        tests.testAnchorPreventsLocationDrift()
        tests.testMissingDatesAndInvalidGPSRemainUncertain()
        print("Passed all 5 visit grouping scenarios")
    }
    private func photo(_ id: String, minutes: Double, meters: Double? = 0) -> VisitPhoto {
        VisitPhoto(id: id, date: Date(timeIntervalSince1970: minutes * 60),
                   location: meters.map { CLLocation(latitude: $0 / 111_000, longitude: 0) })
    }

    func testNearbyPhotosAndTimeOnlyPhotoShareCandidate() {
        let groups = VisitGrouping.groups(for: [photo("c", minutes: 20, meters: 40),
                                               photo("a", minutes: 0), photo("b", minutes: 10, meters: nil)])
        XCTAssertEqual(groups.map { $0.map(\.id) }, [["a", "b", "c"]])
        XCTAssertNil(groups[0][1].location)
    }

    func testDistanceAndReturnVisitSplitEvenWithMissingGPSBetween() {
        let groups = VisitGrouping.groups(for: [photo("a", minutes: 0), photo("b", minutes: 10, meters: nil),
                                               photo("c", minutes: 20, meters: 250), photo("d", minutes: 30)])
        XCTAssertEqual(groups.map { $0.map(\.id) }, [["a", "b"], ["c"], ["d"]])
    }

    func testLongGapSplitsSameLocation() {
        XCTAssertEqual(VisitGrouping.groups(for: [photo("a", minutes: 0), photo("b", minutes: 91)]).count, 2)
        XCTAssertEqual(VisitGrouping.groups(for: [photo("a", minutes: 0), photo("b", minutes: 90)]).count, 1)
    }

    func testAnchorPreventsLocationDrift() {
        XCTAssertEqual(VisitGrouping.groups(for: [photo("a", minutes: 0), photo("b", minutes: 10, meters: 70),
                                                  photo("c", minutes: 20, meters: 140)]).count, 2)
    }

    func testMissingDatesAndInvalidGPSRemainUncertain() {
        let invalid = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                 altitude: 0, horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: Date())
        let photos = [VisitPhoto(id: "a", date: Date(timeIntervalSince1970: 0), location: invalid),
                      photo("b", minutes: 91, meters: nil), VisitPhoto(id: "c", date: nil, location: nil)]
        let groups = VisitGrouping.groups(for: photos)
        XCTAssertEqual(groups.map { $0.map(\.id) }, [["a"], ["b"], ["c"]])
        XCTAssertNil(groups[0][0].location)
        XCTAssertEqual(VisitGrouping.groups(for: []).count, 0)
    }
}
