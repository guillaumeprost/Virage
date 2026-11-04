import Foundation
import Testing
@testable import Virage

struct GPXImportTests {
    private func gpx(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Kurviger" xmlns="http://www.topografix.com/GPX/1/1">
        \(body)
        </gpx>
        """.utf8)
    }

    @Test func prefersThePlannedRouteToTheTrack() throws {
        let track = try GPXReader.read(gpx("""
        <rte><name>Tour du lac</name>
          <rtept lat="45.90" lon="6.13"><name>Départ</name></rtept>
          <rtept lat="45.85" lon="6.20"></rtept>
        </rte>
        <trk><name>Enregistré</name><trkseg>
          <trkpt lat="1" lon="1"></trkpt><trkpt lat="2" lon="2"></trkpt><trkpt lat="3" lon="3"></trkpt>
        </trkseg></trk>
        """), fallbackName: "fichier")

        #expect(track.name == "Tour du lac")
        #expect(track.points == [Coordinate(latitude: 45.90, longitude: 6.13), Coordinate(latitude: 45.85, longitude: 6.20)])
    }

    @Test func readsATrackAndFallsBackOnTheFileName() throws {
        let track = try GPXReader.read(gpx("""
        <trk><trkseg>
          <trkpt lat="45.90" lon="6.13"><ele>450</ele></trkpt>
          <trkpt lat="45.91" lon="6.14"></trkpt>
        </trkseg></trk>
        """), fallbackName: "balade")

        #expect(track.name == "balade")
        #expect(track.points.count == 2)
    }

    @Test func rejectsAFileWithoutPoints() {
        #expect(throws: GPXReader.Failure.self) {
            try GPXReader.read(gpx("<metadata><name>Vide</name></metadata>"), fallbackName: "vide")
        }
    }

    /// North 1 km, a right-angle turn, east 500 m, with points every 10 m as a recorded track has.
    @Test func announcesTheTurnsReadFromTheShape() throws {
        let origin = Coordinate(latitude: 45, longitude: 6)
        let metersPerDegree = Geo.earthRadius * .pi / 180
        func point(north: Double, east: Double = 0) -> Coordinate {
            Coordinate(
                latitude: origin.latitude + north / metersPerDegree,
                longitude: origin.longitude + east / (metersPerDegree * cos(origin.latitude * .pi / 180))
            )
        }
        let points = stride(from: 0.0, through: 1_000, by: 10).map { point(north: $0) }
            + stride(from: 10.0, through: 500, by: 10).map { point(north: 1_000, east: $0) }

        let route = try #require(RouteBuilder.follow(ImportedTrack(name: "Col", points: points)))

        #expect(route.followsTrack)
        #expect(abs(route.distance - 1_500) < 2)
        #expect(route.steps.map(\.maneuver) == [.right, .arrive])
        #expect(route.steps.first?.instruction == "Tournez à droite")
        #expect(abs((route.steps.first?.distanceAlongRoute ?? 0) - 1_000) < 15)
        #expect(abs(route.expectedTravelTime - 100) < 1)
    }
}
