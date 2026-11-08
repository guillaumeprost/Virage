#if DEBUG
import CoreLocation
import SwiftData

/// `-demoTrips YES`: a few made-up rides with speed and lean, to try the trips screens in the simulator, which has
/// no gyroscope. Added once, to an empty store.
enum DemoTrips {
    @MainActor
    static func insert(into context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "demoTrips"),
              (try? context.fetchCount(FetchDescriptor<Trip>())) == 0 else { return }
        let calendar = Calendar.current
        let now = Date.now
        let rides: [(daysAgo: Int, bends: Int, pace: Double)] = [(1, 14, 1), (4, 8, 0.8), (12, 20, 1.15), (38, 10, 0.9)]
        for ride in rides {
            let start = calendar.date(byAdding: .day, value: -ride.daysAgo, to: now) ?? now
            let track = winding(from: start, bends: ride.bends, pace: ride.pace)
            context.insert(trip(track))
        }
        // Two days ago at 10:00: real roads over two passes, for the passes and the photos of the trip.
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let tenOClock = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: twoDaysAgo) ?? twoDaysAgo
        context.insert(trip(overThePasses(from: tenOClock)))
    }

    /// Annecy, the col de Bluffy, Talloires, the col de la Forclaz and down to Montmin.
    private static func overThePasses(from start: Date) -> [TrackPoint] {
        let waypoints: [(latitude: Double, longitude: Double, altitude: Double)] = [
            (45.8992, 6.1294, 450), (45.8850, 6.1700, 470), (45.873237, 6.212253, 630),
            (45.8600, 6.2000, 480), (45.8406, 6.2131, 450), (45.8200, 6.2300, 800),
            (45.80845, 6.24476, 1150), (45.8033, 6.2631, 1050),
        ]
        var track: [TrackPoint] = []
        var time = start
        for (from, to) in zip(waypoints, waypoints.dropFirst()) {
            let meters = CLLocation(latitude: from.latitude, longitude: from.longitude)
                .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
            let steps = max(Int(meters / 50), 1)
            for step in 0..<steps {
                let share = Double(step) / Double(steps)
                let bend = sin(Double(track.count) / 9)
                let location = CLLocation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: from.latitude + (to.latitude - from.latitude) * share,
                        longitude: from.longitude + (to.longitude - from.longitude) * share
                    ),
                    altitude: from.altitude + (to.altitude - from.altitude) * share,
                    horizontalAccuracy: 5,
                    verticalAccuracy: 5,
                    course: 0,
                    speed: (70 - 30 * abs(bend)) / 3.6,
                    timestamp: time
                )
                track.append(TrackPoint(location, lean: 38 * bend * abs(bend)))
                time = time.addingTimeInterval(3)
            }
        }
        return track
    }

    /// A road snaking north-east from Annecy: fast on the straights, slower and leaned in the bends.
    private static func winding(from start: Date, bends: Int, pace: Double) -> [TrackPoint] {
        let count = bends * 60
        return (0..<count).map { index in
            let progress = Double(index) / Double(count)
            let phase = progress * Double(bends) * .pi
            let bend = sin(phase)
            let speedKmh = (95 - 55 * abs(bend)) * pace
            let location = CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 45.90 + progress * 0.25,
                    longitude: 6.13 + progress * 0.20 + 0.004 * cos(phase)
                ),
                altitude: 450 + 900 * progress,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: 45,
                speed: speedKmh / 3.6,
                timestamp: start.addingTimeInterval(Double(index) * 4)
            )
            // Each bend leaned its own way: some tight, some open.
            let bendIndex = Int(progress * Double(bends))
            let tightness = 0.55 + 0.45 * abs(sin(Double(bendIndex) * 2.7))
            return TrackPoint(location, lean: 44 * pace * tightness * bend * abs(bend))
        }
    }

    private static func trip(_ track: [TrackPoint]) -> Trip {
        var stats = RideSnapshot()
        stats.startDate = track.first?.timestamp
        stats.distance = zip(track, track.dropFirst()).reduce(0) { total, pair in
            total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
        stats.movingTime = (track.last?.timestamp ?? .now).timeIntervalSince(track.first?.timestamp ?? .now)
        stats.maxSpeed = track.map(\.speed).max() ?? 0
        stats.averageSpeed = stats.movingTime > 0 ? stats.distance / stats.movingTime : 0
        stats.maxLeanLeft = -(track.compactMap(\.lean).min() ?? 0)
        stats.maxLeanRight = track.compactMap(\.lean).max() ?? 0
        return Trip(snapshot: stats, endDate: track.last?.timestamp ?? .now, track: track)
    }
}
#endif
