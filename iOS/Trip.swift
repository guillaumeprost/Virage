import CoreLocation
import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

@Model
final class Trip {
    var startDate: Date
    var endDate: Date
    var distance: Double
    var movingTime: TimeInterval
    var maxSpeed: Double
    var averageSpeed: Double
    var maxLeanLeft: Double
    var maxLeanRight: Double
    /// The track can hold thousands of points: kept out of the main store, encoded as one blob.
    @Attribute(.externalStorage) var trackData: Data
    /// Meters climbed, and the highest point: read from the track once, so lists and records need not decode it.
    /// A zero highest point means not measured yet, for trips recorded before.
    var elevationGain: Double = 0
    var maxAltitude: Double = 0
    /// The mountain passes the track goes over, looked up in Apple Maps once the trip is first opened.
    var passes: [TripPass] = []
    var passesChecked = false
    /// Given by the rider, "Tour du lac" or "Les Aravis avec Paul": nil until then, the date standing in.
    var name: String?

    init(snapshot: RideSnapshot, endDate: Date, track: [TrackPoint]) {
        startDate = snapshot.startDate ?? track.first?.timestamp ?? endDate
        self.endDate = endDate
        distance = snapshot.distance
        movingTime = snapshot.movingTime
        maxSpeed = snapshot.maxSpeed
        averageSpeed = snapshot.averageSpeed
        maxLeanLeft = snapshot.maxLeanLeft
        maxLeanRight = snapshot.maxLeanRight
        trackData = (try? JSONEncoder().encode(track)) ?? Data()
        measureElevation(track)
    }

    func measureElevation(_ track: [TrackPoint]) {
        let elevation = TripInsights.elevation(track)
        elevationGain = elevation.gain
        maxAltitude = elevation.highest ?? 0
    }

    var track: [TrackPoint] {
        (try? JSONDecoder().decode([TrackPoint].self, from: trackData)) ?? []
    }

    /// The name, or the day and time of the ride: "samedi 7 novembre à 14:39".
    var title: String {
        name ?? startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
    }

    /// Blank clears the name, the date showing again.
    func rename(_ text: String) {
        name = Self.cleanName(text)
    }

    static func cleanName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// For file names: the day, then the name if any, without the characters Files refuses.
    var fileTitle: String {
        let day = startDate.formatted(.iso8601.year().month().day())
        guard let name else { return "Virage \(day)" }
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        return "Virage \(day) \(safe)"
    }
}

/// A mountain pass crossed on a trip.
struct TripPass: Codable, Hashable, Identifiable {
    var name: String
    var latitude: Double
    var longitude: Double

    var id: String { name }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var position: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

extension UTType {
    /// Declared in the Info.plist, so Files and Mail offer to open .gpx files with Virage.
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
}

/// A trip exported as GPX 1.1, the format every mapping and route app reads.
struct GPXFile: Transferable {
    let name: String
    let content: String

    init(trip: Trip) {
        name = "\(trip.fileTitle).gpx"
        let title = trip.name ?? "Virage \(trip.startDate.formatted(.iso8601.year().month().day()))"
        let points = trip.track.map { point in
            """
                  <trkpt lat="\(point.latitude)" lon="\(point.longitude)"><ele>\(point.altitude)</ele>\
            <time>\(point.timestamp.ISO8601Format())</time></trkpt>
            """
        }
        content = """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="Virage" xmlns="http://www.topografix.com/GPX/1/1">
              <metadata><time>\(trip.startDate.ISO8601Format())</time></metadata>
              <trk>
                <name>\(Self.escaped(title))</name>
                <trkseg>
            \(points.joined(separator: "\n"))
                </trkseg>
              </trk>
            </gpx>

            """
    }

    /// A name typed by the rider may hold "&" or "<", which XML reserves.
    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .gpx) { file in
            Data(file.content.utf8)
        }
        .suggestedFileName { $0.name }
    }
}
