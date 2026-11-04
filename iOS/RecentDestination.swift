import Foundation
import SwiftData

/// A destination navigated to, offered again at the top of the search tab.
@Model
final class RecentDestination {
    /// Name and position rounded to about 10 m: searching the same place twice moves it up instead of
    /// adding a duplicate.
    @Attribute(.unique) var key: String
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var lastUsed: Date
    /// The stops of the trip, encoded; `nil` for a trip straight to the destination. Optional, so stores from
    /// before stops existed open as they are.
    var viaData: Data?

    /// Older entries are dropped beyond this.
    static let limit = 20

    init(_ destination: Destination, at date: Date) {
        key = Self.key(for: destination)
        name = destination.name
        subtitle = destination.subtitle
        latitude = destination.coordinate.latitude
        longitude = destination.coordinate.longitude
        lastUsed = date
        viaData = destination.via.isEmpty ? nil : try? JSONEncoder().encode(destination.via)
    }

    var via: [Waypoint] {
        viaData.flatMap { try? JSONDecoder().decode([Waypoint].self, from: $0) } ?? []
    }

    var destination: Destination {
        Destination(name: name, subtitle: subtitle, coordinate: Coordinate(latitude: latitude, longitude: longitude), via: via)
    }

    /// The stops when there are some, otherwise where the place is.
    var summary: String {
        let stops = via
        return stops.isEmpty ? subtitle : "Via " + stops.map(\.name).formatted(.list(type: .and))
    }

    /// The same place through other stops is another trip, kept apart in the history.
    static func key(for destination: Destination) -> String {
        let place = String(format: "%@|%.4f|%.4f", destination.name, destination.coordinate.latitude, destination.coordinate.longitude)
        let stops = destination.via.map { String(format: "%@|%.4f|%.4f", $0.name, $0.coordinate.latitude, $0.coordinate.longitude) }
        return ([place] + stops).joined(separator: ">")
    }

    static func record(_ destination: Destination, in context: ModelContext, at date: Date = .now) {
        let key = key(for: destination)
        let existing = try? context.fetch(FetchDescriptor<RecentDestination>(predicate: #Predicate { $0.key == key })).first
        if let existing {
            existing.lastUsed = date
        } else {
            context.insert(RecentDestination(destination, at: date))
        }

        // Trimmed by hand: a fetch offset is ignored for unsaved changes, and the fetch would return the
        // whole history, the entry just inserted included, to be deleted.
        let history = (try? context.fetch(FetchDescriptor<RecentDestination>(sortBy: [SortDescriptor(\.lastUsed, order: .reverse)]))) ?? []
        history.dropFirst(limit).forEach(context.delete)
        try? context.save()
    }
}
