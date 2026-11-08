import CoreLocation

/// One fix of a recorded trip, on the iPhone or, without it, on the Watch.
struct TrackPoint: Codable, Sendable {
    var position: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }

    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speed: Double
    var timestamp: Date
    /// Degrees, negative to the left. Missing in trips recorded before it was kept, and on the Watch alone.
    var lean: Double?

    init(_ location: CLLocation, lean: Double? = nil) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        speed = max(location.speed, 0)
        timestamp = location.timestamp
        self.lean = lean
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
