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
    }

    var track: [TrackPoint] {
        (try? JSONDecoder().decode([TrackPoint].self, from: trackData)) ?? []
    }
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
        let day = trip.startDate.formatted(.iso8601.year().month().day())
        name = "Virage \(day).gpx"
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
                <name>Virage \(day)</name>
                <trkseg>
            \(points.joined(separator: "\n"))
                </trkseg>
              </trk>
            </gpx>

            """
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .gpx) { file in
            Data(file.content.utf8)
        }
        .suggestedFileName { $0.name }
    }
}
