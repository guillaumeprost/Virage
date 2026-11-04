import CoreLocation

/// One fix of a recorded trip, on the iPhone or, without it, on the Watch.
struct TrackPoint: Codable, Sendable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speed: Double
    var timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        speed = max(location.speed, 0)
        timestamp = location.timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
