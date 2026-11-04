import CoreLocation

/// Turns GPS fixes and lean readings into ride statistics.
///
/// Pure value logic with no framework state, so the iPhone and the Watch share it and tests drive it directly.
struct RideStats: Sendable {
    /// Fixes less precise than this are dropped: they make the speed jump and inflate the distance.
    static let maxHorizontalAccuracy: CLLocationAccuracy = 30
    /// Below ~5 km/h the bike is considered stopped, so GPS jitter adds no distance.
    static let movingThreshold: CLLocationSpeed = 1.5
    /// ~430 km/h. Anything faster is a GPS glitch.
    static let maxPlausibleSpeed: CLLocationSpeed = 120

    private(set) var snapshot = RideSnapshot()
    private var lastLocation: CLLocation?

    mutating func start(at date: Date) {
        snapshot = RideSnapshot(
            isRiding: true,
            speed: snapshot.speed,
            position: snapshot.position,
            altitude: snapshot.altitude,
            course: snapshot.course,
            startDate: date
        )
        lastLocation = nil
    }

    mutating func stop(at date: Date = .now) {
        unpause(at: date)
        snapshot.isRiding = false
    }

    /// Stopped for a coffee or a photo: the ride goes on, its figures wait.
    mutating func pause(at date: Date) {
        guard snapshot.isRiding, !snapshot.isPaused else { return }
        snapshot.isPaused = true
        snapshot.pausedAt = date
    }

    mutating func unpause(at date: Date) {
        guard snapshot.isPaused else { return }
        if let pausedAt = snapshot.pausedAt {
            snapshot.pausedDuration += max(date.timeIntervalSince(pausedAt), 0)
        }
        snapshot.isPaused = false
        snapshot.pausedAt = nil
        // The bike may have moved during the pause: that stretch is not part of the ride.
        lastLocation = nil
    }

    /// Continues a ride from statistics computed elsewhere, e.g. when the Watch takes over from the iPhone.
    mutating func resume(from other: RideSnapshot) {
        snapshot = other
        snapshot.leanAngle = 0
        lastLocation = nil
    }

    /// Returns `false` when the fix is rejected as too imprecise or implausible.
    @discardableResult
    mutating func ingest(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= Self.maxHorizontalAccuracy else {
            return false
        }
        let interval = lastLocation.map { location.timestamp.timeIntervalSince($0.timestamp) }
        if let interval, interval <= 0 {
            return false
        }

        let speed: CLLocationSpeed
        if location.speed >= 0 {
            speed = location.speed
        } else if let lastLocation, let interval {
            speed = location.distance(from: lastLocation) / interval
        } else {
            speed = 0
        }
        guard speed <= Self.maxPlausibleSpeed else { return false }

        snapshot.speed = speed
        snapshot.position = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        if location.verticalAccuracy >= 0 {
            snapshot.altitude = location.altitude
        }
        if location.course >= 0, speed >= Self.movingThreshold {
            snapshot.course = location.course
        }

        if snapshot.isRiding, !snapshot.isPaused {
            snapshot.maxSpeed = max(snapshot.maxSpeed, speed)
            if let lastLocation, let interval, speed >= Self.movingThreshold {
                snapshot.distance += location.distance(from: lastLocation)
                snapshot.movingTime += interval
                snapshot.averageSpeed = snapshot.distance / snapshot.movingTime
            }
        }
        lastLocation = location
        return true
    }

    /// Compass heading, used only when stopped: the GPS course is meaningless without movement.
    mutating func updateHeading(_ degrees: Double) {
        guard degrees >= 0, snapshot.speed < Self.movingThreshold else { return }
        snapshot.course = degrees
    }

    mutating func recordLean(_ degrees: Double) {
        snapshot.leanAngle = degrees
        guard snapshot.isRiding, !snapshot.isPaused else { return }
        if degrees > 0 {
            snapshot.maxLeanRight = max(snapshot.maxLeanRight, degrees)
        } else {
            snapshot.maxLeanLeft = max(snapshot.maxLeanLeft, -degrees)
        }
    }
}
