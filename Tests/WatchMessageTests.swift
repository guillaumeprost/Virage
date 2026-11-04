import CoreLocation
import Foundation
import Testing
@testable import Virage

struct WatchMessageTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func payload(isRiding: Bool, sentSecondsAgo: Double) -> [String: Any] {
        WatchMessage.payload(RideSnapshot(isRiding: isRiding), unit: .kilometersPerHour, at: now.addingTimeInterval(-sentSecondsAgo)) ?? [:]
    }

    @Test func keepsARecentRide() {
        #expect(WatchMessage.snapshot(in: payload(isRiding: true, sentSecondsAgo: 2), now: now)?.0.isRiding == true)
    }

    /// The application context replays an iPhone ride that ended when the app was closed.
    @Test func dropsAStaleRide() {
        #expect(WatchMessage.snapshot(in: payload(isRiding: true, sentSecondsAgo: 600), now: now) == nil)
    }

    /// The end of a ride matters however late it arrives.
    @Test func keepsAStaleStop() {
        #expect(WatchMessage.snapshot(in: payload(isRiding: false, sentSecondsAgo: 600), now: now)?.0.isRiding == false)
    }
}

struct WatchTripTests {
    /// What the Watch writes to the file is what the iPhone reads back into its trip history.
    @Test func survivesTheTransfer() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let fixes = (0..<3).map { second in
            TrackPoint(CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 45.9 + Double(second) * 0.001, longitude: 6.13),
                altitude: 450, horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 20,
                timestamp: start.addingTimeInterval(Double(second))
            ))
        }
        var snapshot = RideSnapshot(isRiding: true, startDate: start)
        snapshot.distance = 222
        let sent = WatchTrip(snapshot: snapshot, endDate: start.addingTimeInterval(3), track: fixes)

        let received = try JSONDecoder().decode(WatchTrip.self, from: JSONEncoder().encode(sent))
        let trip = Trip(snapshot: received.snapshot, endDate: received.endDate, track: received.track)

        #expect(trip.startDate == start)
        #expect(trip.distance == 222)
        #expect(trip.track.count == 3)
        #expect(trip.track.last?.speed == 20)
    }
}
