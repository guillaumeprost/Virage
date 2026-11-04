import Foundation

/// A favorite or recent destination, sent by the iPhone so the Watch can offer it without the iPhone in reach.
struct SavedPlace: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case home, work, favorite, recent
    }

    var kind: Kind
    var name: String
    var subtitle: String
    var coordinate: Coordinate

    var id: String {
        String(format: "%@|%@|%.4f|%.4f", kind.rawValue, name, coordinate.latitude, coordinate.longitude)
    }

    /// Home and work show their role, as in Maps.
    var title: String {
        switch kind {
        case .home: "Maison"
        case .work: "Travail"
        case .favorite, .recent: name
        }
    }

    var symbol: String {
        switch kind {
        case .home: "house.fill"
        case .work: "briefcase.fill"
        case .favorite: "star.fill"
        case .recent: "clock.arrow.circlepath"
        }
    }
}

/// A ride recorded by the Watch alone, sent to the iPhone to join the trip history.
struct WatchTrip: Codable, Sendable {
    var snapshot: RideSnapshot
    var endDate: Date
    var track: [TrackPoint]
}
