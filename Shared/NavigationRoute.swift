import Foundation

struct Coordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
}

enum NavigationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Turn by turn along a MapKit route.
    case route
    /// An arrow towards the destination; the rider picks the roads.
    case compass

    var id: Self { self }
}

enum Maneuver: String, Codable, Sendable {
    case straight
    case slightLeft
    case left
    case sharpLeft
    case slightRight
    case right
    case sharpRight
    case uTurn
    /// Reaching a stop on the way: announced like a turn, then the route goes on.
    case waypoint
    case arrive

    /// MapKit gives instructions as text only, so the maneuver is read from the route's shape.
    ///
    /// `turnAngle` is the heading change in degrees, positive to the right, in (-180, 180].
    static func from(turnAngle: Double) -> Maneuver {
        switch turnAngle {
        case -20...20: .straight
        case 20..<60: .slightRight
        case 60..<120: .right
        case 120..<165: .sharpRight
        case -60 ..< -20: .slightLeft
        case -120 ..< -60: .left
        case -165 ..< -120: .sharpLeft
        default: .uTurn
        }
    }

    var symbolName: String {
        switch self {
        case .straight: "arrow.up"
        case .slightLeft: "arrow.up.left"
        case .left: "arrow.turn.up.left"
        case .sharpLeft: "arrow.down.left"
        case .slightRight: "arrow.up.right"
        case .right: "arrow.turn.up.right"
        case .sharpRight: "arrow.down.right"
        case .uTurn: "arrow.uturn.down"
        case .waypoint: "mappin.and.ellipse"
        case .arrive: "flag.checkered"
        }
    }
}

struct RouteStep: Codable, Equatable, Sendable {
    var instruction: String
    var maneuver: Maneuver
    /// Where the maneuver happens, as a distance from the start of the route.
    var distanceAlongRoute: Double
}

/// A place to go through on the way to the destination.
struct Waypoint: Codable, Hashable, Sendable {
    var name: String
    var coordinate: Coordinate
}

/// A waypoint placed on the route.
struct RouteStop: Codable, Equatable, Sendable {
    var waypoint: Waypoint
    /// Where the stop is, as a distance from the start of the route.
    var distanceAlongRoute: Double
}

/// A planned trip, sent from the iPhone to the Watch.
struct NavigationRoute: Codable, Identifiable, Sendable {
    var id = UUID()
    var destinationName: String
    var destination: Coordinate
    var mode: NavigationMode
    var avoidsTolls: Bool
    /// The route geometry; empty in compass mode.
    var points: [Coordinate] = []
    var steps: [RouteStep] = []
    var distance: Double = 0
    var expectedTravelTime: TimeInterval = 0
    /// The stops before the destination, in order.
    var stops: [RouteStop] = []
    /// Imported from a GPX file: the line is the plan, so leaving it does not reroute with Apple Maps.
    var followsTrack = false
}

/// What the Watch receives: a route to follow, or `nil` when navigation ends.
struct NavigationEnvelope: Codable, Sendable {
    var route: NavigationRoute?
}

enum Geo {
    static let earthRadius = 6_371_000.0

    static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b`, in degrees clockwise from north, in [0, 360).
    static func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalized(atan2(y, x) * 180 / .pi)
    }

    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// Signed difference `to - from`, in (-180, 180], positive clockwise.
    static func turn(from: Double, to: Double) -> Double {
        let delta = normalized(to - from)
        return delta > 180 ? delta - 360 : delta
    }

    /// Closest point to `p` on the segment `a`→`b`: the fraction along it and the distance in meters.
    ///
    /// Uses a flat projection around `a`, accurate for segments of a few kilometers.
    static func project(_ p: Coordinate, ontoSegment a: Coordinate, _ b: Coordinate) -> (fraction: Double, distance: Double) {
        let metersPerDegreeLat = earthRadius * .pi / 180
        let metersPerDegreeLon = metersPerDegreeLat * cos(a.latitude * .pi / 180)
        let bx = (b.longitude - a.longitude) * metersPerDegreeLon, by = (b.latitude - a.latitude) * metersPerDegreeLat
        let px = (p.longitude - a.longitude) * metersPerDegreeLon, py = (p.latitude - a.latitude) * metersPerDegreeLat
        let lengthSquared = bx * bx + by * by
        let fraction = lengthSquared > 0 ? min(max((px * bx + py * by) / lengthSquared, 0), 1) : 0
        let dx = px - fraction * bx, dy = py - fraction * by
        return (fraction, sqrt(dx * dx + dy * dy))
    }
}

/// Turns MapKit's route steps into a single polyline and a list of maneuvers.
enum RouteBuilder {
    /// How far before and after a maneuver to look when measuring the turn, so GPS-level wiggles in the
    /// geometry do not read as turns.
    static let turnProbeDistance = 25.0

    /// Each MapKit step's instruction is the maneuver at the END of its polyline: the step covers the road
    /// leading up to the turn. Checked against real routes, where the turn measured at the start of a step
    /// matches the previous step's instruction.
    static func build(
        steps: [(instruction: String, points: [Coordinate])],
        destinationName: String,
        destination: Coordinate,
        avoidsTolls: Bool,
        expectedTravelTime: TimeInterval
    ) -> NavigationRoute {
        var points: [Coordinate] = []
        var stepEnds: [(instruction: String, index: Int)] = []
        for step in steps {
            let continues = !points.isEmpty && step.points.first == points.last
            points.append(contentsOf: continues ? Array(step.points.dropFirst()) : step.points)
            // The departure step has no instruction, and nothing to announce at the starting point.
            if !step.instruction.isEmpty, points.count > 1 {
                stepEnds.append((step.instruction, points.count - 1))
            }
        }

        var cumulative = [0.0]
        for index in points.indices.dropFirst() {
            cumulative.append(cumulative[index - 1] + Geo.distance(points[index - 1], points[index]))
        }
        let total = cumulative.last ?? 0

        var routeSteps = stepEnds.map { end in
            RouteStep(
                instruction: end.instruction,
                maneuver: maneuver(at: end.index, points: points, cumulative: cumulative),
                distanceAlongRoute: cumulative[end.index]
            )
        }
        if let last = routeSteps.last, total - last.distanceAlongRoute < 5 {
            routeSteps[routeSteps.count - 1].maneuver = .arrive
        } else {
            routeSteps.append(RouteStep(instruction: destinationName, maneuver: .arrive, distanceAlongRoute: total))
        }

        return NavigationRoute(
            destinationName: destinationName,
            destination: destination,
            mode: .route,
            avoidsTolls: avoidsTolls,
            points: points,
            steps: routeSteps,
            distance: total,
            expectedTravelTime: expectedTravelTime
        )
    }

    /// One route through stops, from the legs between them: each leg's arrival becomes a waypoint along the way.
    /// `stops` are the places the legs end at, all but the last leg.
    static func join(
        _ legs: [NavigationRoute],
        stops: [Waypoint],
        destinationName: String,
        destination: Coordinate,
        avoidsTolls: Bool
    ) -> NavigationRoute {
        precondition(legs.count == stops.count + 1, "one leg more than stops")
        var points: [Coordinate] = []
        var steps: [RouteStep] = []
        var routeStops: [RouteStop] = []
        var offset = 0.0
        var travelTime = 0.0
        for (index, leg) in legs.enumerated() {
            // Legs normally meet; if not, the gap between them still counts, as the guidance will measure it.
            if let last = points.last, let first = leg.points.first {
                offset += Geo.distance(last, first)
            }
            let continues = !points.isEmpty && leg.points.first == points.last
            points.append(contentsOf: continues ? Array(leg.points.dropFirst()) : leg.points)
            var legSteps = leg.steps.map { step in
                RouteStep(instruction: step.instruction, maneuver: step.maneuver, distanceAlongRoute: step.distanceAlongRoute + offset)
            }
            if index < stops.count {
                let stop = stops[index]
                if let last = legSteps.indices.last, legSteps[last].maneuver == .arrive {
                    legSteps[last].maneuver = .waypoint
                    legSteps[last].instruction = "Étape : \(stop.name)"
                }
                routeStops.append(RouteStop(waypoint: stop, distanceAlongRoute: offset + leg.distance))
            }
            steps.append(contentsOf: legSteps)
            offset += leg.distance
            travelTime += leg.expectedTravelTime
        }
        return NavigationRoute(
            destinationName: destinationName,
            destination: destination,
            mode: .route,
            avoidsTolls: avoidsTolls,
            points: points,
            steps: steps,
            distance: offset,
            expectedTravelTime: travelTime,
            stops: routeStops
        )
    }

    private static func maneuver(at index: Int, points: [Coordinate], cumulative: [Double]) -> Maneuver {
        guard index > 0, index < points.count - 1 else { return .arrive }
        return .from(turnAngle: turnAngle(at: index, points: points, cumulative: cumulative))
    }

    /// The heading change at a point, measured a little before and after it so GPS-level wiggles do not count.
    static func turnAngle(at index: Int, points: [Coordinate], cumulative: [Double]) -> Double {
        var before = index - 1
        while before > 0, cumulative[index] - cumulative[before] < turnProbeDistance { before -= 1 }
        var after = index + 1
        while after < points.count - 1, cumulative[after] - cumulative[index] < turnProbeDistance { after += 1 }
        let incoming = Geo.bearing(points[before], points[index])
        let outgoing = Geo.bearing(points[index], points[after])
        return Geo.turn(from: incoming, to: outgoing)
    }
}
