import Foundation
import Testing
@testable import Virage

/// A point `north` and `east` meters away from a fixed origin.
private func point(north: Double, east: Double = 0) -> Coordinate {
    let origin = Coordinate(latitude: 45, longitude: 6)
    let metersPerDegree = Geo.earthRadius * .pi / 180
    return Coordinate(
        latitude: origin.latitude + north / metersPerDegree,
        longitude: origin.longitude + east / (metersPerDegree * cos(origin.latitude * .pi / 180))
    )
}

/// 1 km north, then a right turn and 500 m east, shaped like a MapKit response: an empty departure step,
/// then steps whose instruction applies at the end of their polyline.
private func lRoute() -> NavigationRoute {
    RouteBuilder.build(
        steps: [
            ("", [point(north: 0)]),
            ("Tournez à droite sur la D909", [point(north: 0), point(north: 500), point(north: 1_000)]),
            ("Vous arriverez à destination", [point(north: 1_000), point(north: 1_000, east: 250), point(north: 1_000, east: 500)]),
        ],
        destinationName: "Col",
        destination: point(north: 1_000, east: 500),
        avoidsTolls: false,
        expectedTravelTime: 120
    )
}

struct ManeuverTests {
    @Test(arguments: [
        (0.0, Maneuver.straight), (35, .slightRight), (90, .right), (140, .sharpRight),
        (-35, .slightLeft), (-90, .left), (-140, .sharpLeft), (178, .uTurn), (-178, .uTurn),
    ])
    func classifiesTurnAngles(angle: Double, expected: Maneuver) {
        #expect(Maneuver.from(turnAngle: angle) == expected)
    }

    @Test func measuresTurnsAcrossNorth() {
        #expect(Geo.turn(from: 350, to: 20) == 30)
        #expect(Geo.turn(from: 20, to: 350) == -30)
    }
}

struct RouteBuilderTests {
    @Test func joinsStepsAndReadsTheTurnFromTheGeometry() {
        let route = lRoute()

        #expect(route.points.count == 5)
        #expect(abs(route.distance - 1_500) < 2)
        #expect(route.steps.count == 2)
        #expect(route.steps[0].maneuver == .right)
        #expect(route.steps[0].instruction == "Tournez à droite sur la D909")
        #expect(abs(route.steps[0].distanceAlongRoute - 1_000) < 1)
        #expect(route.steps[1].maneuver == .arrive)
        #expect(route.steps[1].instruction == "Vous arriverez à destination")
    }

    @Test func addsTheArrivalWhenMapKitGivesNone() {
        let route = RouteBuilder.build(
            steps: [("Continuez", [point(north: 0), point(north: 400)]), ("", [point(north: 400), point(north: 800)])],
            destinationName: "Col",
            destination: point(north: 800),
            avoidsTolls: false,
            expectedTravelTime: 60
        )

        #expect(route.steps.map(\.maneuver) == [.straight, .arrive])
        #expect(route.steps.last?.instruction == "Col")
    }
}

struct GuidanceTests {
    @Test func countsDownToTheNextTurnAndCuesItTwice() {
        var guidance = Guidance(route: lRoute())

        #expect(guidance.update(point(north: 200)).isEmpty)
        #expect(guidance.state.maneuver == .right)
        #expect(abs(guidance.state.distanceToManeuver - 800) < 2)
        #expect(abs(guidance.state.remainingDistance - 1_300) < 2)

        #expect(guidance.update(point(north: 750, east: 8)) == [.prepare(.right)])
        #expect(guidance.update(point(north: 760)).isEmpty)
        #expect(guidance.update(point(north: 975)) == [.turn(.right)])
        #expect(guidance.update(point(north: 990)).isEmpty)
    }

    @Test func movesOnToTheNextStepOnceTheTurnIsBehind() {
        var guidance = Guidance(route: lRoute())
        _ = guidance.update(point(north: 990))
        _ = guidance.update(point(north: 1_000, east: 100))

        #expect(guidance.state.maneuver == .arrive)
        #expect(abs(guidance.state.distanceToManeuver - 400) < 2)
    }

    @Test func measuresProgressTowardsTheTurnAndTheTimeLeft() {
        var guidance = Guidance(route: lRoute())
        _ = guidance.update(point(north: 250))

        #expect(abs(guidance.state.stepLength - 1_000) < 2)
        #expect(abs(guidance.state.maneuverProgress - 0.25) < 0.01)
        // 1 250 m left of 1 500 m, at the 120 s Apple Maps expects for the whole route.
        #expect(abs((guidance.state.remainingTime ?? 0) - 100) < 1)

        _ = guidance.update(point(north: 1_000, east: 100))
        #expect(abs(guidance.state.stepLength - 500) < 2)
        #expect(abs(guidance.state.maneuverProgress - 0.2) < 0.01)
    }

    @Test func flagsOffRouteOnlyAfterSeveralFarFixes() {
        var guidance = Guidance(route: lRoute())
        _ = guidance.update(point(north: 200))

        #expect(guidance.update(point(north: 300, east: 200)).isEmpty)
        #expect(guidance.update(point(north: 310, east: 210)).isEmpty)
        #expect(guidance.update(point(north: 320, east: 220)) == [.offRoute])
        #expect(guidance.state.isOffRoute)

        _ = guidance.update(point(north: 400))
        #expect(!guidance.state.isOffRoute)
    }

    @Test func arrivesNearTheDestination() {
        var guidance = Guidance(route: lRoute())
        _ = guidance.update(point(north: 1_000, east: 400))

        #expect(guidance.update(point(north: 1_000, east: 480)) == [.arrived])
        #expect(guidance.state.hasArrived)
        #expect(guidance.update(point(north: 1_000, east: 500)).isEmpty)
    }

    @Test func pointsTowardsTheDestinationInCompassMode() {
        var guidance = Guidance(route: RoutePlanner.compass(to: point(north: 1_000, east: 1_000), named: "Lac"))
        _ = guidance.update(point(north: 0))

        #expect(abs(guidance.state.bearingToDestination - 45) < 1)
        #expect(abs(guidance.state.distanceToManeuver - 1_414) < 5)
        #expect(guidance.state.remainingTime == nil)
    }
}

struct StopsTests {
    /// North 1 km to a café, then east 500 m to the col.
    private func routeWithStop() -> NavigationRoute {
        let toCafe = RouteBuilder.build(
            steps: [("", [point(north: 0)]), ("Vous arriverez à destination", [point(north: 0), point(north: 500), point(north: 1_000)])],
            destinationName: "Café",
            destination: point(north: 1_000),
            avoidsTolls: false,
            expectedTravelTime: 80
        )
        let toCol = RouteBuilder.build(
            steps: [("", [point(north: 1_000)]), ("Vous arriverez à destination", [point(north: 1_000), point(north: 1_000, east: 500)])],
            destinationName: "Col",
            destination: point(north: 1_000, east: 500),
            avoidsTolls: false,
            expectedTravelTime: 40
        )
        return RouteBuilder.join(
            [toCafe, toCol],
            stops: [Waypoint(name: "Café", coordinate: point(north: 1_000))],
            destinationName: "Col",
            destination: point(north: 1_000, east: 500),
            avoidsTolls: false
        )
    }

    @Test func joinsLegsAndAnnouncesTheStop() {
        let route = routeWithStop()

        #expect(abs(route.distance - 1_500) < 2)
        #expect(route.expectedTravelTime == 120)
        #expect(route.points.count == 4)
        #expect(route.steps.map(\.maneuver) == [.waypoint, .arrive])
        #expect(route.steps.first?.instruction == "Étape : Café")
        #expect(abs((route.stops.first?.distanceAlongRoute ?? 0) - 1_000) < 2)
    }

    @Test func guidesThroughTheStopToTheDestination() {
        var guidance = Guidance(route: routeWithStop())
        _ = guidance.update(point(north: 900))

        #expect(guidance.state.maneuver == .waypoint)
        #expect(abs(guidance.state.distanceToManeuver - 100) < 2)
        #expect(!guidance.state.hasArrived)
        #expect(guidance.remainingStops.map(\.name) == ["Café"])

        _ = guidance.update(point(north: 1_000, east: 100))
        #expect(guidance.state.maneuver == .arrive)
        // Past the café, a new route only has to reach the col.
        #expect(guidance.remainingStops.isEmpty)
    }
}
