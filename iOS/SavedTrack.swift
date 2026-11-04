import Foundation
import SwiftData

/// A GPX route or track, kept once imported so it can be ridden again without the file.
@Model
final class SavedTrack {
    /// Name, ends and size: importing the same file twice moves it up instead of adding a duplicate.
    @Attribute(.unique) var key: String
    var name: String
    /// The line, encoded: a ride planner's export holds thousands of points.
    @Attribute(.externalStorage) var pointsData: Data
    /// Along the line, in meters.
    var distance: Double
    var lastUsed: Date

    init(_ track: ImportedTrack, at date: Date) {
        key = Self.key(for: track)
        name = track.name
        pointsData = (try? JSONEncoder().encode(track.points)) ?? Data()
        distance = Self.length(of: track.points)
        lastUsed = date
    }

    var track: ImportedTrack {
        ImportedTrack(name: name, points: (try? JSONDecoder().decode([Coordinate].self, from: pointsData)) ?? [])
    }

    static func key(for track: ImportedTrack) -> String {
        let ends = [track.points.first, track.points.last].compactMap { $0 }
            .map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) }
        return ([track.name, "\(track.points.count)"] + ends).joined(separator: "|")
    }

    static func length(of points: [Coordinate]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) }
    }

    /// Adds the track to the library, or moves it to the top if it is there already.
    static func save(_ track: ImportedTrack, in context: ModelContext, at date: Date = .now) {
        let key = key(for: track)
        if let existing = try? context.fetch(FetchDescriptor<SavedTrack>(predicate: #Predicate { $0.key == key })).first {
            existing.lastUsed = date
        } else {
            context.insert(SavedTrack(track, at: date))
        }
        try? context.save()
    }
}
