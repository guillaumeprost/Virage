import Foundation
import Testing
@testable import Virage

/// Naming a trip: the name stands in for the date in the list, the share image and the GPX file.
@MainActor
@Suite("Trip names")
struct TripNameTests {
    private func trip() -> Trip {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 14, minute: 39))!
        return Trip(snapshot: RideSnapshot(isRiding: true, startDate: start), endDate: start.addingTimeInterval(3_600), track: [])
    }

    @Test("Spaces around a name are dropped, a blank name clears it")
    func cleaning() {
        #expect(Trip.cleanName("  Tour du lac \n") == "Tour du lac")
        #expect(Trip.cleanName("   ") == nil)
        #expect(Trip.cleanName("") == nil)
    }

    @Test("Without a name, the date titles the trip")
    func dateStandsIn() {
        let trip = trip()
        #expect(trip.name == nil)
        #expect(trip.title == trip.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
    }

    @Test("Renaming, then clearing, brings the date back")
    func renameAndClear() {
        let trip = trip()
        trip.rename("Les Aravis avec Paul")
        #expect(trip.title == "Les Aravis avec Paul")
        trip.rename(" ")
        #expect(trip.name == nil)
        #expect(trip.title != "Les Aravis avec Paul")
    }

    @Test("Files carry the day, then the name, without the characters Files refuses")
    func fileTitle() {
        let trip = trip()
        #expect(trip.fileTitle == "Virage 2026-11-07")
        trip.rename("Annecy / Albertville: 2 cols?")
        #expect(trip.fileTitle == "Virage 2026-11-07 Annecy - Albertville- 2 cols-")
    }

    @Test("The GPX track carries the name, escaped for XML")
    func gpxName() {
        let trip = trip()
        trip.rename("Lac & cols <3")
        let file = GPXFile(trip: trip)
        #expect(file.content.contains("<name>Lac &amp; cols &lt;3</name>"))
        #expect(file.name == "Virage 2026-11-07 Lac & cols -3.gpx")
    }

    @Test("Unnamed, the GPX keeps its old name")
    func gpxWithoutName() {
        let file = GPXFile(trip: trip())
        #expect(file.content.contains("<name>Virage 2026-11-07</name>"))
        #expect(file.name == "Virage 2026-11-07.gpx")
    }
}
