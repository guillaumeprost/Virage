import CoreLocation
import Foundation
import Testing
@testable import Virage

/// A fix every ~111 m northward along a meridian.
private func point(_ index: Int, speedKmh: Double, lean: Double? = nil) -> TrackPoint {
    let location = CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: 45 + Double(index) * 0.001, longitude: 6),
        altitude: 500,
        horizontalAccuracy: 5,
        verticalAccuracy: 5,
        course: 0,
        speed: speedKmh / 3.6,
        timestamp: Date(timeIntervalSince1970: Double(index))
    )
    return TrackPoint(location, lean: lean)
}

struct TrackColoringTests {
    @Test func speedBands() {
        #expect(TrackColoring.speed.band(of: 20 / 3.6) == 0)
        #expect(TrackColoring.speed.band(of: 70 / 3.6) == 2)
        #expect(TrackColoring.speed.band(of: 150 / 3.6) == 4)
    }

    @Test func legendInTheRidersUnit() {
        #expect(TrackColoring.speed.legend(.kilometersPerHour) == ["< 30", "30+", "60+", "90+", "120+"])
        #expect(TrackColoring.lean.legend(.kilometersPerHour).first == "< 15°")
    }

    @Test func oneSegmentPerBandWithoutGaps() {
        let track = (0..<10).map { point($0, speedKmh: 20) } + (10..<20).map { point($0, speedKmh: 100) }
        let segments = TripInsights.segments(track, by: .speed)
        #expect(segments.map(\.band) == [0, 3])
        // The first stretch ends where the second begins.
        #expect(segments[0].coordinates.last?.latitude == segments[1].coordinates.first?.latitude)
        #expect(segments.reduce(0) { $0 + $1.coordinates.count } == track.count + 1)
    }

    @Test func aJoltDoesNotChangeTheColor() {
        var track = (0..<20).map { point($0, speedKmh: 50) }
        track[10] = point(10, speedKmh: 130)
        #expect(TripInsights.segments(track, by: .speed).count == 1)
    }

    @Test func pointsWithoutLeanAreNeutral() {
        let track = (0..<5).map { point($0, speedKmh: 50) }
        #expect(TripInsights.segments(track, by: .lean).map(\.band) == [nil])
    }
}

struct LeanPeakTests {
    @Test func pinsTheMostLeanedBendsApart() {
        var track = (0..<40).map { point($0, speedKmh: 60, lean: 5) }
        track[5] = point(5, speedKmh: 60, lean: 38)
        // Same bend, 111 m on: not a second peak.
        track[6] = point(6, speedKmh: 60, lean: 36)
        track[20] = point(20, speedKmh: 60, lean: -42)
        track[35] = point(35, speedKmh: 60, lean: 25)
        let peaks = TripInsights.leanPeaks(track)
        #expect(peaks.map(\.lean) == [-42, 38, 25])
    }

    @Test func gentleRidesHaveNoPeaks() {
        let track = (0..<10).map { point($0, speedKmh: 60, lean: 10) }
        #expect(TripInsights.leanPeaks(track).isEmpty)
    }
}

struct TripSummaryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func trip(_ day: String, km: Double, speed: Double = 30, lean: Double = 20) -> TripFigures {
        let start = try! Date("\(day)T10:00:00+01:00", strategy: .iso8601)
        return TripFigures(start: start, distance: km * 1_000, movingTime: 3_600, maxSpeed: speed, maxLean: lean)
    }

    @Test func addsUpEachMonthNewestFirst() {
        let trips = [trip("2026-10-12", km: 80), trip("2026-11-02", km: 120), trip("2026-11-05", km: 60)]
        let months = TripInsights.months(trips, calendar: calendar)
        #expect(months.map(\.count) == [2, 1])
        #expect(months.first?.distance == 180_000)
        #expect(months.first?.movingTime == 7_200)
    }

    @Test func recordsPickTheBestTrip() {
        let trips = [trip("2026-10-12", km: 80, speed: 40), trip("2026-11-02", km: 210, lean: 41), trip("2026-11-05", km: 60, speed: 45)]
        #expect(TripInsights.record(trips, by: \.distance) == 1)
        #expect(TripInsights.record(trips, by: \.maxSpeed) == 2)
        #expect(TripInsights.record(trips, by: \.maxLean) == 1)
    }

    @Test func noRecordWithoutAValue() {
        let trips = [trip("2026-10-12", km: 80, lean: 0)]
        #expect(TripInsights.record(trips, by: \.maxLean) == nil)
    }
}

struct TrackPointLeanTests {
    @Test func oldTracksStillDecode() throws {
        let json = #"[{"latitude":45,"longitude":6,"altitude":500,"speed":10,"timestamp":0}]"#
        let track = try JSONDecoder().decode([TrackPoint].self, from: Data(json.utf8))
        #expect(track.first?.lean == nil)
    }
}

struct ScenicKindTests {
    @Test func passesByName() {
        #expect(ScenicSearch.kind(of: "col de Bluffy") == .pass)
        #expect(ScenicSearch.kind(of: "Le Col de la Forclaz") == .pass)
        #expect(ScenicSearch.kind(of: "Col des Aravis") == .pass)
        #expect(ScenicSearch.kind(of: "Passo dello Stelvio") == .pass)
    }

    @Test func viewpointsByName() {
        #expect(ScenicSearch.kind(of: "Point de vue sur le lac") == .viewpoint)
        #expect(ScenicSearch.kind(of: "Belvédère de la Tournette") == .viewpoint)
    }

    @Test func otherPlacesAreLeftOut() {
        #expect(ScenicSearch.kind(of: "Collège Jean Jaurès") == nil)
        #expect(ScenicSearch.kind(of: "Colombier") == nil)
        #expect(ScenicSearch.kind(of: "Boulangerie du Col") == nil)
    }
}

struct ElevationTests {
    private func point(_ index: Int, altitude: Double) -> TrackPoint {
        TrackPoint(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 45, longitude: 6),
            altitude: altitude, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: Date(timeIntervalSince1970: Double(index))
        ))
    }

    @Test func climbsAddUpAndNoiseDoesNot() {
        // Up 300 m, down 100 m, up 50 m, with a meter or two of GPS noise all along.
        let climb: [Double] = (0..<30).map { 500 + Double($0) * 10 }
        let descent: [Double] = (0..<10).map { 800 - Double($0) * 10 }
        let again: [Double] = (0..<5).map { 700 + Double($0) * 10 }
        let profile = climb + descent + again
        let noisy: [Double] = profile.enumerated().map { index, altitude in
            altitude + (index.isMultiple(of: 2) ? 1.5 : -1.5)
        }
        let elevation = TripInsights.elevation(noisy.enumerated().map { point($0, altitude: $1) })
        // About 340 m climbed: smoothing trims the short last climb a little, never adds noise.
        #expect(elevation.gain > 290 && elevation.gain < 350)
        #expect(abs((elevation.highest ?? 0) - 790) < 5)
    }

    @Test func flatRideClimbsNothing() {
        let track = (0..<50).map { point($0, altitude: 450 + ($0.isMultiple(of: 2) ? 2 : -2)) }
        #expect(TripInsights.elevation(track).gain == 0)
    }
}

@Suite("Trip list helpers")
struct TripListHelperTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    @Test("A month's summary and its section use the same key")
    func monthKeysAgree() {
        let calendar = calendar
        let dates = [
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 30))!,
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 15))!,
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!,
        ]
        let figures = dates.map { TripFigures(start: $0, distance: 10_000, movingTime: 600, maxSpeed: 20, maxLean: 0) }
        let sections = Dictionary(grouping: dates) { TripInsights.monthStart(of: $0, calendar: calendar) }
        let months = TripInsights.months(figures, calendar: calendar)
        #expect(months.count == 2)
        for month in months {
            #expect(sections[month.month]?.count == month.count)
        }
    }

    @Test("The last minutes of a month stay in it")
    func monthBoundary() {
        let calendar = calendar
        let late = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 59))!
        let start = TripInsights.monthStart(of: late, calendar: calendar)
        #expect(calendar.component(.month, from: start) == 10)
        #expect(calendar.component(.day, from: start) == 1)
    }

    @Test("A ride's length reads in hours and minutes, without seconds")
    func shortDuration() {
        let text = Format.shortDuration(3_725)
        #expect(text.contains("1"))
        #expect(text.contains("2"))
        #expect(!text.contains("5"))
        #expect(!text.contains(":"))
    }

    @Test("A band's color, neutral where a point has no value")
    func bandColors() {
        #expect(TrackColoring.color(for: 0) == TrackColoring.colors[0])
        #expect(TrackColoring.color(for: 4) == TrackColoring.colors[4])
        #expect(TrackColoring.color(for: nil) == .gray)
    }

    @Test("A fix's position, for distances and searches")
    func trackPointPosition() {
        let fix = point(3, speedKmh: 50)
        #expect(fix.position == Coordinate(latitude: fix.latitude, longitude: fix.longitude))
    }
}

