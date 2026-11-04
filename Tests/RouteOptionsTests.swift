import Foundation
import Testing
@testable import Virage

private let origin = Coordinate(latitude: 45, longitude: 6)
private let metersPerDegree = Geo.earthRadius * .pi / 180

private func point(north: Double, east: Double = 0) -> Coordinate {
    Coordinate(
        latitude: origin.latitude + north / metersPerDegree,
        longitude: origin.longitude + east / (metersPerDegree * cos(origin.latitude * .pi / 180))
    )
}

/// A line north with points every 10 m, swinging east and back every `period` meters: a winding road.
private func zigzag(length: Double, period: Double, amplitude: Double) -> [Coordinate] {
    stride(from: 0.0, through: length, by: 10).map { north in
        point(north: north, east: amplitude * sin(2 * .pi * north / period))
    }
}

private func route(_ points: [Coordinate], minutes: Double) -> NavigationRoute {
    NavigationRoute(
        destinationName: "Col",
        destination: points.last!,
        mode: .route,
        options: RouteOptions(style: .winding),
        points: points,
        distance: 0,
        expectedTravelTime: minutes * 60
    )
}

struct RouteOptionsTests {
    @Test func aStraightRoadDoesNotTurn() {
        let straight = stride(from: 0.0, through: 5_000, by: 10).map { point(north: $0) }
        #expect(RouteBuilder.windiness(of: straight) < 1)
    }

    @Test func aWindingRoadTurnsMore() {
        let straight = stride(from: 0.0, through: 5_000, by: 10).map { point(north: $0) }
        let winding = zigzag(length: 5_000, period: 400, amplitude: 60)
        #expect(RouteBuilder.windiness(of: winding) > 100)
        #expect(RouteBuilder.windiness(of: winding) > RouteBuilder.windiness(of: straight))
    }

    @Test func picksTheMostWindingRouteWithinTheExtraTime() {
        let quick = route(stride(from: 0.0, through: 5_000, by: 10).map { point(north: $0) }, minutes: 10)
        let twisty = route(zigzag(length: 5_000, period: 400, amplitude: 60), minutes: 12)
        let chosen = RouteBuilder.mostWinding([quick, twisty])
        #expect(chosen?.id == twisty.id)
    }

    @Test func refusesAWindingRouteThatTakesFarLonger() {
        let quick = route(stride(from: 0.0, through: 5_000, by: 10).map { point(north: $0) }, minutes: 10)
        let detour = route(zigzag(length: 5_000, period: 400, amplitude: 60), minutes: 20)
        #expect(RouteBuilder.mostWinding([quick, detour])?.id == quick.id)
    }

    @Test func highwaysAreAvoidedForEveryStyleButTheFastest() {
        #expect(!RouteOptions(style: .fastest).avoidsHighways)
        #expect(RouteOptions(style: .noHighways).avoidsHighways)
        #expect(RouteOptions(style: .winding).avoidsHighways)
    }
}

struct TrackBendTests {
    /// Hairpins every 150 m on a pass: one call for the run instead of one per bend.
    @Test func announcesARunOfBendsOnce() throws {
        var points: [Coordinate] = []
        // Straight 1 km, then a switchback: legs of 150 m going east and west, climbing 30 m each.
        points += stride(from: 0.0, through: 1_000, by: 10).map { point(north: $0) }
        var north = 1_000.0
        var east = 0.0
        for leg in 0..<6 {
            let direction = leg.isMultiple(of: 2) ? 1.0 : -1.0
            for _ in 1...15 {
                east += 10 * direction
                points.append(point(north: north, east: east))
            }
            for _ in 1...3 {
                north += 10
                points.append(point(north: north, east: east))
            }
        }
        points += stride(from: 10.0, through: 1_000, by: 10).map { point(north: north + $0, east: east) }

        let route = try #require(RouteBuilder.follow(ImportedTrack(name: "Col", points: points)))
        let bends = route.steps.filter { $0.maneuver != .arrive }
        #expect(bends.count == 1)
        #expect(bends.first?.instruction.contains("virages sur") == true)
    }

    @Test func roundsTheLengthOfARun() {
        #expect(RouteBuilder.roundedLength(740) == "700 m")
        #expect(RouteBuilder.roundedLength(2_460) == "2,5 km")
    }
}

struct FuelGaugeTests {
    @Test func warnsOnceWhenReachingTheReserve() {
        var fuel = FuelGauge(range: 200_000, reserve: 40_000, sinceRefuel: 150_000)
        #expect(!fuel.isLow)
        let first = fuel.add(5_000)
        let second = fuel.add(6_000)
        #expect(!first)
        #expect(second)
        #expect(fuel.isLow)
        let third = fuel.add(1_000)
        #expect(!third)
        #expect(fuel.remaining == 38_000)
    }

    @Test func aFillUpGivesTheFullRangeBack() {
        var fuel = FuelGauge(range: 200_000, reserve: 40_000, sinceRefuel: 190_000)
        fuel.refuel()
        #expect(fuel.remaining == 200_000)
        #expect(!fuel.isLow)
    }

    @Test func neverGoesBelowEmpty() {
        var fuel = FuelGauge(range: 200_000, reserve: 40_000, sinceRefuel: 0)
        _ = fuel.add(250_000)
        #expect(fuel.remaining == 0)
    }

    @Test func readsTheSettingsInKilometers() throws {
        let defaults = try #require(UserDefaults(suiteName: "FuelGaugeTests"))
        defaults.removePersistentDomain(forName: "FuelGaugeTests")
        #expect(FuelSettings.load(from: defaults) == nil)
        defaults.set(true, forKey: FuelSettings.enabledKey)
        defaults.set(300.0, forKey: FuelSettings.rangeKey)
        FuelSettings.save(sinceRefuel: 12_000, to: defaults)
        let fuel = try #require(FuelSettings.load(from: defaults))
        #expect(fuel.range == 300_000)
        #expect(fuel.reserve == 50_000)
        #expect(fuel.remaining == 288_000)
    }
}

struct SavedTrackTests {
    @Test func theSameFileIsKeptOnce() {
        let track = ImportedTrack(name: "Tour", points: [point(north: 0), point(north: 1_000)])
        var again = track
        again.id = UUID()
        #expect(SavedTrack.key(for: track) == SavedTrack.key(for: again))
        #expect(abs(SavedTrack.length(of: track.points) - 1_000) < 1)
    }
}
