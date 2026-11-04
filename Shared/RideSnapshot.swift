import Foundation

/// Live state of a ride. The iPhone sends it to the Watch, which shows it as is.
struct RideSnapshot: Codable, Equatable, Sendable {
    var isRiding = false
    /// Meters per second, never negative.
    var speed: Double = 0
    var maxSpeed: Double = 0
    /// Average over the time spent moving, in meters per second.
    var averageSpeed: Double = 0
    /// Meters.
    var distance: Double = 0
    /// Last accepted fix. The Watch runs its own guidance from it.
    var position: Coordinate?
    /// Meters above sea level.
    var altitude: Double?
    /// Degrees clockwise from true north.
    var course: Double?
    /// Degrees, positive when leaning right.
    var leanAngle: Double = 0
    var maxLeanLeft: Double = 0
    var maxLeanRight: Double = 0
    var movingTime: TimeInterval = 0
    var startDate: Date?
    /// A paused ride keeps its place and speed up to date but adds nothing to its statistics.
    var isPaused = false
    /// Time spent in finished pauses; a pause in progress counts from `pausedAt`.
    var pausedDuration: TimeInterval = 0
    var pausedAt: Date?

    /// The start shifted by the pauses: a timer counting up from here shows the ride time without them.
    var timerStart: Date? {
        startDate.map { $0.addingTimeInterval(pausedDuration) }
    }

    /// Ride time at `date`, pauses excluded.
    func elapsed(at date: Date) -> TimeInterval {
        guard let timerStart else { return 0 }
        return max((pausedAt ?? date).timeIntervalSince(timerStart), 0)
    }
}
